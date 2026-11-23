// SPDX-License-Identifier: MIT
/*
 * shader-cube: a cube whose faces run Shadertoy shaders, bouncing around a
 * room together with a dynamic point light.  The faces are emissive and light
 * the room; PhysX debris gets knocked around by both.  Renders through
 * OpenGL ES 3.0, OpenGL 4.3 or Vulkan 1.3 (gfx.h), in real time or offline
 * into numbered image files.
 *
 * Each face shader lives in shaders/faceN/ (N = 0..5):
 *   image.glsl              required, Shadertoy "Image" tab
 *   common.glsl             optional, "Common" tab
 *   bufa.glsl .. bufd.glsl  optional, "Buffer A".."Buffer D" tabs
 *   vola.glsl               optional, "Volume A" tab (mainVolume, 3D texture)
 *   channels.cfg            iChannel bindings, resolution, crop
 * tools/import_shadertoy.py generates these from a Shadertoy JSON export.
 * Cube face i uses face shader (i % number_of_face_dirs_found).
 *
 * The GPU is whatever the system hands us: `prime-run shader-cube` renders on
 * the NVIDIA dGPU, plain `shader-cube` on the default (integrated) GPU.
 */
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "gfx.h"
#include "imgout.h"
#include "mathx.h"
#include "physics.h"

#define MAX_FACES 6
#define NUM_BUFS 4
#define P_VOLA 4
#define P_IMAGE 5
#define NUM_PASSES 6

static const char *PASS_NAMES[NUM_PASSES] = {"bufa", "bufb", "bufc", "bufd", "vola", "image"};

/* Channel sources: 1..5 = output of pass (src-1). */
enum { SRC_NONE = 0, SRC_BUFA, SRC_BUFB, SRC_BUFC, SRC_BUFD, SRC_VOLA, SRC_NOISE, SRC_KEYBOARD };

typedef struct { int src, filter, wrap; } Channel;

typedef struct {
    int present;
    GfxProg *prog;
    Channel ch[4];
} Pass;

typedef struct {
    GfxTex *tex[2];
    int latest; /* index of the most recently written texture */
} Target;

typedef struct {
    char dir[512], title[160];
    int w, h, vsize, crop, frame;
    Pass pass[NUM_PASSES];
    Target buf[NUM_BUFS];
    Target vol; /* 3D textures */
    GfxTex *img;
    float mouse[4];
    int stopped;  /* toggled with keys 1-6: keeps showing its last frame */
    float time;   /* own iTime, so a resumed shader continues where it stopped */
} Face;

/* std140 uniform blocks (see the shader sources below). */
typedef struct {
    float res[3], time;
    float tdelta, frate;
    int32_t frame;
    float srate;
    float mouse[4];
    float date[4];
    float chres[4][4];
    float chtime[4][4];
    float slice, pad[3];
} STUniforms;

typedef struct {
    float viewproj[16], model[16], cube_inv[16], cube_rot[16];
    float light_pos[4], light_col[4], cam_pos[4], cube_pos[4];
    float face[6][4];
    float misc[4];
} SceneUniforms;

typedef struct { float p0[4], p1[4]; } PostUniforms;

/* ---------------------------------------------------------------- globals */

static const GfxBackend *gfx;
static Face g_faces[MAX_FACES];
static int g_nfaces;
static GfxTex *g_noise_tex, *g_kbd_tex, *g_black_tex, *g_black3d_tex;
static GfxFormat g_float_fmt = GFX_RGBA32F;
static int g_default_res = 1024;
static const char *g_shader_root = "shaders";

static double g_cam_yaw = 0.785, g_cam_pitch = -0.2;
static int g_orbiting, g_paused, g_reload, g_user_cam, g_view_face = -1, g_blast;
static double g_last_mx, g_last_my;
static char g_api_label[200];
static volatile sig_atomic_t g_quit; /* SIGINT / SIGTERM */
static double g_fps_shown;

/* Interaction with the cube: which cube face is held / has keyboard focus. */
static int g_grab_face = -1;    /* cube face (0..5) the mouse is pressing */
static int g_focus_face = -1;   /* shader face index receiving keyboard */
static unsigned char g_kbd[3][256];

static const v3 ROOM_HALF = {7.0f, 4.5f, 7.0f};
static const float CUBE_HALF = 1.1f;
static const float LIGHT_RADIUS = 0.22f;
static const float GRAVITY = 9.8f;
static const float FOVY = 1.25f;

/* Face order: +X -X +Y -Y +Z -Z.  T x B = N, uv (0,0) at -T,-B. */
static const float FACE_N[6][3] = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
static const float FACE_T[6][3] = {{0,0,-1},{0,0,1},{1,0,0},{1,0,0},{1,0,0},{-1,0,0}};
static const float FACE_B[6][3] = {{0,1,0},{0,1,0},{0,0,-1},{0,0,1},{0,1,0},{0,1,0}};

/* ---------------------------------------------------------------- utils */

static char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *s = malloc((size_t)n + 1);
    if (fread(s, 1, (size_t)n, f) != (size_t)n) { free(s); fclose(f); return NULL; }
    s[n] = 0;
    fclose(f);
    return s;
}

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

/* Sleeps until *deadline (absolute, now_s clock), then schedules the next. */
static void limit_frame_rate(double *deadline, double period) {
    double t = now_s();
    if (*deadline - t > 0.0015) { /* sleep most of the way, spin the rest */
        double until = *deadline - 0.001;
        struct timespec ts = {(time_t)until, (long)((until - (double)(time_t)until) * 1e9)};
        while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL) == EINTR) {}
    }
    while ((t = now_s()) < *deadline) {}
    *deadline += period;
    if (*deadline < t) *deadline = t + period; /* fell behind: don't try to catch up */
}

static void on_signal(int sig) { (void)sig; g_quit = 1; }

/* ./shaders when run from the source tree, else the copy installed next to
 * the executable: <exe>/../share/shader-cube/shaders (AppImage, installs). */
static const char *default_shader_root(void) {
    static char found[1100];
    struct stat st;
    if (!stat("shaders/face0/image.glsl", &st)) return "shaders";
    char exe[1024];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n <= 0) return "shaders";
    exe[n] = 0;
    char *slash = strrchr(exe, '/');
    if (slash) *slash = 0;
    static const char *const rel[] = {"%s/../share/shader-cube/shaders", "%s/shaders"};
    for (size_t i = 0; i < sizeof rel / sizeof *rel; i++) {
        char probe[1200];
        snprintf(found, sizeof found, rel[i], exe);
        snprintf(probe, sizeof probe, "%s/face0/image.glsl", found);
        if (!stat(probe, &st)) return found;
    }
    return "shaders";
}

static int mkdir_p(const char *path) {
    char tmp[1024];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++)
        if (*p == '/') {
            *p = 0;
            if (mkdir(tmp, 0755) && errno != EEXIST) return 0;
            *p = '/';
        }
    return !mkdir(tmp, 0755) || errno == EEXIST;
}

/* ---------------------------------------------------------------- shadertoy passes */

static const char *FS_TRI_VS =
    "void main(){\n"
    "  vec2 p = vec2(float((GFX_VERTEX_ID << 1) & 2), float(GFX_VERTEX_ID & 2));\n"
    "  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);\n"
    "}\n";

static const char *ST_HEAD =
    "#define HW_PERFORMANCE 1\n"
    "GFX_UBO(0) st_Uniforms {\n"
    "  vec3  iResolution; float iTime;\n"
    "  float iTimeDelta; float iFrameRate; int iFrame; float iSampleRate;\n"
    "  vec4  iMouse;\n"
    "  vec4  iDate;\n"
    "  vec3  iChannelResolution[4];\n"
    "  float iChannelTime[4];\n"
    "  float st_Slice;\n"
    "};\n"
    "layout(location = 0) out vec4 st_FragColor;\n";

static const char *ST_IMAGE_MAIN =
    "\nvoid main(){\n"
    "  vec4 c = vec4(0.0, 0.0, 0.0, 1.0);\n"
    "  mainImage(c, gl_FragCoord.xy);\n"
    "  st_FragColor = c;\n"
    "}\n";

static const char *ST_VOLUME_MAIN =
    "\nvoid main(){\n"
    "  vec4 c = vec4(0.0);\n"
    "  mainVolume(c, vec3(gl_FragCoord.xy, st_Slice + 0.5));\n"
    "  st_FragColor = c;\n"
    "}\n";

/* Shown on a face whose shader fails to compile. */
static const char *ERROR_SRC =
    "void mainImage(out vec4 o, in vec2 f){\n"
    "  vec2 c = floor(f / 32.0);\n"
    "  float k = mod(c.x + c.y, 2.0);\n"
    "  o = vec4(mix(vec3(1.0,0.0,1.0), vec3(0.1), k) * (0.6 + 0.4*sin(iTime*4.0)), 1.0);\n"
    "}\n";
static const char *ERROR_VOL_SRC = "void mainVolume(out vec4 o, vec3 v){ o = vec4(0.0); }\n";

static GfxProg *build_st_program(const Pass *p, int volume, const char *common, const char *body,
                                 const char *label) {
    char samplers[256];
    int n = 0;
    for (int c = 0; c < 4; c++)
        n += snprintf(samplers + n, sizeof samplers - (size_t)n, "GFX_TEX(%d) %s iChannel%d;\n", 1 + c,
                      p->ch[c].src == SRC_VOLA ? "sampler3D" : "sampler2D", c);
    GfxProgDesc d = {.label = label, .vs = {FS_TRI_VS}, .nvs = 1,
                     .tex = {"iChannel0", "iChannel1", "iChannel2", "iChannel3"}, .ntex = 4,
                     .vtx = GFX_VTX_NONE};
    int k = 0;
    d.fs[k++] = ST_HEAD;
    d.fs[k++] = samplers;
    if (common) { d.fs[k++] = "#line 1\n"; d.fs[k++] = common; }
    d.fs[k++] = "\n#line 1\n";
    d.fs[k++] = body;
    d.fs[k++] = volume ? ST_VOLUME_MAIN : ST_IMAGE_MAIN;
    d.nfs = k;
    return gfx->program(&d);
}

static int parse_src(const char *s) {
    static const char *names[] = {"none", "bufa", "bufb", "bufc", "bufd", "vola", "noise", "keyboard"};
    for (int i = 0; i < 8; i++)
        if (!strcmp(s, names[i])) return i;
    return SRC_NONE;
}

static int pass_index(const char *s) {
    for (int i = 0; i < NUM_PASSES; i++)
        if (!strcmp(s, PASS_NAMES[i])) return i;
    return -1;
}

/*
 * channels.cfg (one directive per line, '#' comments):
 *   resolution W [H]      face render size (default 1024x1024)
 *   crop                  W>H: show the centre square instead of squashing
 *   volume N              Volume A size (default 128)
 *   <pass> <ch> <source> [nearest|linear|mipmap] [clamp|repeat]
 *     pass   : image | bufa..bufd | vola
 *     source : bufa..bufd | vola | noise | keyboard | none
 */
static void load_config(Face *f) {
    char path[600];
    snprintf(path, sizeof path, "%s/channels.cfg", f->dir);
    char *txt = read_file(path);
    if (!txt) return;
    char *save = NULL;
    for (char *line = strtok_r(txt, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        if (line[0] == '#') {
            /* "# imported from X: "Name" by user" -> title */
            const char *q = strchr(line, '"');
            if (q && !f->title[0]) snprintf(f->title, sizeof f->title, "%s", q);
            continue;
        }
        char *hash = strchr(line, '#');
        if (hash) *hash = 0;
        char a[32] = "", b[32] = "", c[32] = "", d[32] = "", e[32] = "";
        int n = sscanf(line, "%31s %31s %31s %31s %31s", a, b, c, d, e);
        if (n <= 0) continue;
        if (!strcmp(a, "resolution") && n >= 2) {
            f->w = atoi(b);
            f->h = n >= 3 ? atoi(c) : f->w;
            if (f->w < 16) f->w = 16;
            if (f->h < 16) f->h = 16;
            continue;
        }
        if (!strcmp(a, "crop")) { f->crop = 1; continue; }
        if (!strcmp(a, "volume") && n >= 2) { f->vsize = atoi(b); continue; }
        int pi = pass_index(a);
        int ci = atoi(b);
        if (pi < 0 || n < 3 || ci < 0 || ci > 3) {
            fprintf(stderr, "%s: ignoring line '%s'\n", path, line);
            continue;
        }
        Channel *ch = &f->pass[pi].ch[ci];
        ch->src = parse_src(c);
        for (int k = 3; k < n; k++) {
            const char *opt = k == 3 ? d : e;
            if (!strcmp(opt, "nearest")) ch->filter = GFX_NEAREST;
            else if (!strcmp(opt, "linear")) ch->filter = GFX_LINEAR;
            else if (!strcmp(opt, "mipmap")) ch->filter = GFX_MIPMAP;
            else if (!strcmp(opt, "clamp")) ch->wrap = GFX_CLAMP;
            else if (!strcmp(opt, "repeat")) ch->wrap = GFX_REPEAT;
        }
    }
    free(txt);
}

static void free_face(Face *f) {
    for (int i = 0; i < NUM_PASSES; i++) gfx->prog_free(f->pass[i].prog);
    for (int b = 0; b < NUM_BUFS; b++)
        for (int k = 0; k < 2; k++) gfx->tex_free(f->buf[b].tex[k]);
    for (int k = 0; k < 2; k++) gfx->tex_free(f->vol.tex[k]);
    gfx->tex_free(f->img);
    memset(f, 0, sizeof *f);
}

static int load_face(Face *f, const char *dir) {
    char path[600];
    snprintf(path, sizeof path, "%s/image.glsl", dir);
    char *image = read_file(path);
    if (!image) return 0;

    memset(f, 0, sizeof *f);
    snprintf(f->dir, sizeof f->dir, "%s", dir);
    f->w = f->h = g_default_res;
    f->vsize = 128;
    for (int i = 0; i < NUM_PASSES; i++)
        for (int c = 0; c < 4; c++) f->pass[i].ch[c].filter = GFX_LINEAR;
    load_config(f);
    if (!f->title[0]) snprintf(f->title, sizeof f->title, "%.150s", dir);

    snprintf(path, sizeof path, "%s/common.glsl", dir);
    char *common = read_file(path);

    double t0 = now_s();
    for (int i = 0; i < NUM_PASSES; i++) {
        char *body;
        if (i == P_IMAGE) body = image;
        else {
            snprintf(path, sizeof path, "%s/%s.glsl", dir, PASS_NAMES[i]);
            body = read_file(path);
            if (!body) continue;
        }
        char label[640];
        snprintf(label, sizeof label, "%s/%s.glsl", dir, PASS_NAMES[i]);
        Pass *p = &f->pass[i];
        int is_vol = i == P_VOLA;
        p->present = 1;
        p->prog = build_st_program(p, is_vol, common, body, label);
        if (!p->prog) {
            Pass blank = {0};
            p->prog = build_st_program(&blank, is_vol, NULL, is_vol ? ERROR_VOL_SRC : ERROR_SRC, "fallback");
        }
        if (i < NUM_BUFS)
            for (int k = 0; k < 2; k++) f->buf[i].tex[k] = gfx->texture(g_float_fmt, f->w, f->h, 1, 0, 1);
        if (is_vol)
            for (int k = 0; k < 2; k++)
                f->vol.tex[k] = gfx->texture(g_float_fmt, f->vsize, f->vsize, f->vsize, 0, 1);
        if (i != P_IMAGE) free(body);
    }
    f->img = gfx->texture(GFX_RGBA8, f->w, f->h, 1, 1, 1);
    free(common);
    free(image);
    const char *name = strrchr(dir, '/');
    printf("loaded %-6s %-40s %dx%d  (compiled in %.1fs)\n", name ? name + 1 : dir, f->title, f->w, f->h,
           now_s() - t0);
    fflush(stdout);
    return 1;
}

static void load_all_faces(void) {
    if (g_nfaces) gfx->wait_idle();
    for (int i = 0; i < g_nfaces; i++) free_face(&g_faces[i]);
    g_nfaces = 0;
    if (strcmp(g_shader_root, "shaders")) printf("shaders: %s\n", g_shader_root);
    for (int i = 0; i < MAX_FACES; i++) {
        char dir[512];
        snprintf(dir, sizeof dir, "%s/face%d", g_shader_root, i);
        if (!load_face(&g_faces[g_nfaces], dir)) break;
        g_nfaces++;
    }
    if (!g_nfaces) {
        fprintf(stderr, "no face shaders found under %s/face0/image.glsl\n", g_shader_root);
        exit(1);
    }
}

static void make_builtin_textures(void) {
    /* RGBA noise, 256x256, mipmapped (+ repeat via the sampler). */
    unsigned char *px = malloc(256 * 256 * 4);
    unsigned int seed = 0x1234567u;
    for (int i = 0; i < 256 * 256 * 4; i++) {
        seed = seed * 1664525u + 1013904223u;
        px[i] = (unsigned char)(seed >> 24);
    }
    g_noise_tex = gfx->texture(GFX_RGBA8, 256, 256, 1, 1, 1);
    gfx->upload(g_noise_tex, px);
    gfx->gen_mips(g_noise_tex);
    free(px);

    /* Keyboard: 256x3 R8 (row 0 = held, 1 = pressed this frame, 2 = toggled). */
    g_kbd_tex = gfx->texture(GFX_R8, 256, 3, 1, 0, 1);

    unsigned char black[4] = {0, 0, 0, 255};
    g_black_tex = gfx->texture(GFX_RGBA8, 1, 1, 1, 0, 1);
    gfx->upload(g_black_tex, black);
    g_black3d_tex = gfx->texture(GFX_RGBA8, 1, 1, 2, 0, 1);
    unsigned char black2[8] = {0, 0, 0, 255, 0, 0, 0, 255};
    gfx->upload(g_black3d_tex, black2);
}

typedef struct { float t, dt, fps, date[4]; } Clock;

static void st_setup(Face *f, int pi, int rw, int rh, int rd, const Clock *ck, STUniforms *u, GfxDraw *d) {
    Pass *p = &f->pass[pi];
    memset(u, 0, sizeof *u);
    memset(d, 0, sizeof *d);
    for (int c = 0; c < 4; c++) {
        Channel *ch = &p->ch[c];
        GfxTex *tex = g_black_tex;
        int tw = 1, th = 1, td = 1;
        if (ch->src >= SRC_BUFA && ch->src <= SRC_BUFD) {
            Target *b = &f->buf[ch->src - SRC_BUFA];
            if (b->tex[0]) { tex = b->tex[b->latest]; tw = f->w; th = f->h; }
        } else if (ch->src == SRC_VOLA) {
            tex = f->vol.tex[0] ? f->vol.tex[f->vol.latest] : g_black3d_tex;
            tw = th = td = f->vsize;
        } else if (ch->src == SRC_NOISE) {
            tex = g_noise_tex; tw = th = 256;
        } else if (ch->src == SRC_KEYBOARD) {
            tex = g_kbd_tex; tw = 256; th = 3;
        }
        d->tex[c] = tex;
        d->filter[c] = (unsigned char)ch->filter;
        d->wrap[c] = (unsigned char)ch->wrap;
        u->chres[c][0] = (float)tw;
        u->chres[c][1] = (float)th;
        u->chres[c][2] = (float)td;
        u->chtime[c][0] = ck->t;
    }
    u->res[0] = (float)rw; u->res[1] = (float)rh; u->res[2] = (float)rd;
    u->time = ck->t;
    u->tdelta = ck->dt;
    u->frate = ck->fps;
    u->frame = f->frame;
    memcpy(u->mouse, f->mouse, sizeof u->mouse);
    memcpy(u->date, ck->date, sizeof u->date);
    u->srate = 44100.0f;
    d->prog = p->prog;
    d->ubo = u;
    d->ubo_size = sizeof *u;
    d->count = 3;
}

static void render_face(Face *f, const Clock *gck) {
    Clock lc = *gck;
    lc.t = f->time;
    f->time += gck->dt;
    const Clock *ck = &lc;
    STUniforms u;
    GfxDraw d;
    /* Volume first, then Buffers A..D, then Image.  Every target is
     * ping-ponged, so a pass reading itself sees the previous frame and a
     * later pass sees this frame's result. */
    if (f->pass[P_VOLA].present) {
        Target *v = &f->vol;
        int dst = 1 - v->latest;
        st_setup(f, P_VOLA, f->vsize, f->vsize, f->vsize, ck, &u, &d);
        for (int z = 0; z < f->vsize; z++) {
            GfxPass pp = {.color = v->tex[dst], .layer = z};
            gfx->begin_pass(&pp);
            u.slice = (float)z;
            gfx->draw(&d);
            gfx->end_pass();
        }
        v->latest = dst;
    }
    for (int b = 0; b < NUM_BUFS; b++) {
        if (!f->pass[b].present) continue;
        Target *t = &f->buf[b];
        int dst = 1 - t->latest;
        st_setup(f, b, f->w, f->h, 1, ck, &u, &d);
        GfxPass pp = {.color = t->tex[dst]};
        gfx->begin_pass(&pp);
        gfx->draw(&d);
        gfx->end_pass();
        t->latest = dst;
    }
    st_setup(f, P_IMAGE, f->w, f->h, 1, ck, &u, &d);
    GfxPass pp = {.color = f->img};
    gfx->begin_pass(&pp);
    gfx->draw(&d);
    gfx->end_pass();
    gfx->gen_mips(f->img);
    f->frame++;
    f->mouse[3] = -fabsf(f->mouse[3]); /* "clicked" lasts one frame */
}

/* Horizontal scale of the face uv into the texture (centre-square crop). */
static float face_uscale(const Face *f) {
    return (f->crop && f->w > f->h) ? (float)f->h / (float)f->w : 1.0f;
}

/* ---------------------------------------------------------------- scene shaders */

static const char *SCENE_UBO =
    "GFX_UBO(0) st_Uniforms {\n"
    "  mat4 uViewProj; mat4 uModel; mat4 uCubeInv; mat4 uCubeRotM;\n"
    "  vec4 uLightPosR; vec4 uLightColA; vec4 uCamPosH; vec4 uCubePosE;\n"
    "  vec4 uFace[6];\n"                              /* x: crop scale, y: mip giving EN x EN texels */
    "  vec4 uMisc;\n"                                 /* cube draw: x = crop scale, y = focus */
    "};\n"
    "#define uLightPos uLightPosR.xyz\n"
    "#define uLightRadius uLightPosR.w\n"
    "#define uLightCol uLightColA.xyz\n"
    "#define uCamPos uCamPosH.xyz\n"
    "#define uCubeHalf uCamPosH.w\n"
    "#define uCubePos uCubePosE.xyz\n"
    "#define uEmit uCubePosE.w\n"
    "#define uCubeRot mat3(uCubeRotM)\n";

static const char *SCENE_VS =
    "layout(location=0) in vec3 aPos;\n"
    "layout(location=1) in vec3 aNrm;\n"
    "layout(location=2) in vec2 aUV;\n"
    "out vec3 vPos; out vec3 vNrm; out vec2 vUV;\n"
    "#ifdef INSTANCED\n"
    "layout(location=3) in vec4 iPosMat;\n"           /* position, material */
    "layout(location=4) in vec4 iRot;\n"              /* quaternion xyzw */
    "layout(location=5) in vec4 iHalf;\n"             /* half extents */
    "flat out float vMat;\n"
    "vec3 qrot(vec4 q, vec3 v){ vec3 t = 2.0 * cross(q.xyz, v); return v + q.w * t + cross(q.xyz, t); }\n"
    "#endif\n"
    "void main(){\n"
    "#ifdef INSTANCED\n"
    "  vec3 wp = iPosMat.xyz + qrot(iRot, aPos * iHalf.xyz);\n"
    "  vPos = wp; vNrm = qrot(iRot, aNrm); vUV = aUV; vMat = iPosMat.w;\n"
    "  gl_Position = GFX_CLIP(uViewProj * vec4(wp, 1.0));\n"
    "#else\n"
    "  vec4 wp = uModel * vec4(aPos, 1.0);\n"
    "  vPos = wp.xyz; vNrm = mat3(uModel) * aNrm; vUV = aUV;\n"
    "  gl_Position = GFX_CLIP(uViewProj * wp);\n"
    "#endif\n"
    "}\n";

/* Cube faces: what the shader shows, as emitted light, plus a highlight of
 * the bulb.  Output is linear HDR. */
static const char *CUBE_FS =
    "GFX_TEX(1) sampler2D uTex;\n"
    "in vec3 vPos; in vec3 vNrm; in vec2 vUV;\n"
    "layout(location=0) out vec4 oColor;\n"
    "void main(){\n"
    "  vec3 N = normalize(vNrm);\n"
    "  vec3 L = uLightPos - vPos; float d = length(L); L /= d;\n"
    "  vec3 V = normalize(uCamPos - vPos);\n"
    "  float spec = pow(max(dot(N, normalize(L + V)), 0.0), 120.0) * step(0.0, dot(N, L));\n"
    "  vec2 uv = vec2(0.5 + (vUV.x - 0.5) * uMisc.x, vUV.y);\n"
    "  vec3 col = pow(texture(uTex, uv).rgb, vec3(2.2));\n"
    "  col += spec * uLightCol * 3.0 / (1.0 + 0.04 * d * d);\n"
    "  vec2 e = min(vUV, 1.0 - vUV);\n"
    "  float edge = min(e.x, e.y);\n"
    "  col *= mix(0.05, 1.0, smoothstep(0.0, 0.012, edge));\n"
    "  col += uMisc.y * vec3(0.9, 0.9, 1.0) * (1.0 - smoothstep(0.004, 0.012, edge));\n"
    "  oColor = vec4(col, 1.0);\n"
    "}\n";

/* Lighting shared by the room and the debris: the point light with a soft
 * shadow from the cube, the cube faces as area lights, glossy reflections
 * of the cube. */
static const char *LIGHTING_FS =
    "#define EN 4\n"                                   /* emitter patches per face side */
    "GFX_TEX(1) sampler2D uF0; GFX_TEX(2) sampler2D uF1; GFX_TEX(3) sampler2D uF2;\n"
    "GFX_TEX(4) sampler2D uF3; GFX_TEX(5) sampler2D uF4; GFX_TEX(6) sampler2D uF5;\n"
    "layout(location=0) out vec4 oColor;\n"
    "const vec3 FN[6] = vec3[6](vec3(1,0,0),vec3(-1,0,0),vec3(0,1,0),vec3(0,-1,0),vec3(0,0,1),vec3(0,0,-1));\n"
    "const vec3 FT[6] = vec3[6](vec3(0,0,-1),vec3(0,0,1),vec3(1,0,0),vec3(1,0,0),vec3(1,0,0),vec3(-1,0,0));\n"
    "const vec3 FB[6] = vec3[6](vec3(0,1,0),vec3(0,1,0),vec3(0,0,-1),vec3(0,0,1),vec3(0,1,0),vec3(0,1,0));\n"
    "\n"
    "vec3 rad(sampler2D s, vec2 uv, float us, float lod){\n"
    "  return pow(textureLod(s, vec2(0.5 + (uv.x - 0.5) * us, uv.y), lod).rgb, vec3(2.2));\n"
    "}\n"
    "vec3 faceRad(int k, vec2 uv, float lod){\n"
    "  if (k == 0) return rad(uF0, uv, uFace[0].x, lod + uFace[0].y);\n"
    "  if (k == 1) return rad(uF1, uv, uFace[1].x, lod + uFace[1].y);\n"
    "  if (k == 2) return rad(uF2, uv, uFace[2].x, lod + uFace[2].y);\n"
    "  if (k == 3) return rad(uF3, uv, uFace[3].x, lod + uFace[3].y);\n"
    "  if (k == 4) return rad(uF4, uv, uFace[4].x, lod + uFace[4].y);\n"
    "  return rad(uF5, uv, uFace[5].x, lod + uFace[5].y);\n"
    "}\n"
    /* Exact diffuse form factor of a polygon (Lambert's formula). */
    "float edgeTerm(vec3 a, vec3 b, vec3 N){\n"
    "  vec3 c = cross(a, b); float l = length(c);\n"
    "  if (l < 1e-7) return 0.0;\n"
    "  return acos(clamp(dot(a, b), -1.0, 1.0)) * dot(N, c / l);\n"
    "}\n"
    "float quadFF(vec3 P, vec3 N, vec3 p0, vec3 p1, vec3 p2, vec3 p3){\n"
    "  vec3 a = normalize(p0 - P), b = normalize(p1 - P), c = normalize(p2 - P), d = normalize(p3 - P);\n"
    "  float s = edgeTerm(a, b, N) + edgeTerm(b, c, N) + edgeTerm(c, d, N) + edgeTerm(d, a, N);\n"
    "  return max(-s * 0.15915494, 0.0);\n"
    "}\n"
    /* Light arriving at P from the six emissive faces, EN x EN patches each. */
    "vec3 cubeEmission(vec3 P, vec3 N){\n"
    "  vec3 sum = vec3(0.0);\n"
    "  for (int k = 0; k < 6; k++) {\n"
    "    vec3 n = uCubeRot * FN[k], t = uCubeRot * FT[k] * uCubeHalf, b = uCubeRot * FB[k] * uCubeHalf;\n"
    "    vec3 c = uCubePos + n * uCubeHalf;\n"
    "    if (dot(P - c, n) <= 0.0) continue;\n"
    "    for (int i = 0; i < EN; i++)\n"
    "    for (int j = 0; j < EN; j++) {\n"
    "      vec2 u0 = vec2(i, j) / float(EN), u1 = vec2(i + 1, j + 1) / float(EN);\n"
    "      vec3 p0 = c + t * (2.0*u0.x - 1.0) + b * (2.0*u0.y - 1.0);\n"
    "      vec3 p1 = c + t * (2.0*u1.x - 1.0) + b * (2.0*u0.y - 1.0);\n"
    "      vec3 p2 = c + t * (2.0*u1.x - 1.0) + b * (2.0*u1.y - 1.0);\n"
    "      vec3 p3 = c + t * (2.0*u0.x - 1.0) + b * (2.0*u1.y - 1.0);\n"
    "      float ff = quadFF(P, N, p0, p1, p2, p3);\n"
    "      if (ff > 0.0) sum += ff * faceRad(k, (u0 + u1) * 0.5, 0.0);\n"
    "    }\n"
    "  }\n"
    "  return sum * uEmit;\n"
    "}\n"
    /* Ray vs the cube (local space [-1,1]^3). Returns t or -1. */
    "float hitCube(vec3 p, vec3 dir, out vec3 lp){\n"
    "  vec3 ro = (uCubeInv * vec4(p, 1.0)).xyz;\n"
    "  vec3 rd = (uCubeInv * vec4(dir, 0.0)).xyz;\n"
    "  rd = mix(rd, vec3(1e-6), lessThan(abs(rd), vec3(1e-6)));\n"
    "  vec3 t0 = (-1.0 - ro) / rd, t1 = (1.0 - ro) / rd;\n"
    "  vec3 tn3 = min(t0, t1), tf3 = max(t0, t1);\n"
    "  float tn = max(max(tn3.x, tn3.y), tn3.z);\n"
    "  float tf = min(min(tf3.x, tf3.y), tf3.z);\n"
    "  lp = ro + rd * tn;\n"
    "  return (tn < tf && tn > 0.0) ? tn : -1.0;\n"
    "}\n"
    "float occluded(vec3 p, vec3 target){\n"
    "  vec3 lp; float t = hitCube(p, target - p, lp);\n"
    "  return (t > 0.0 && t < 1.0) ? 1.0 : 0.0;\n"
    "}\n"
    "float softShadow(vec3 p){\n"
    "  vec3 L = normalize(uLightPos - p);\n"
    "  vec3 a0 = normalize(cross(L, abs(L.y) < 0.9 ? vec3(0,1,0) : vec3(1,0,0)));\n"
    "  vec3 b0 = cross(L, a0);\n"
    "  float ang = 6.2831853 * fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));\n"
    "  vec3 a = a0 * cos(ang) + b0 * sin(ang), b = b0 * cos(ang) - a0 * sin(ang);\n"
    "  float r = uLightRadius, o = occluded(p, uLightPos);\n"
    "  for (int i = 0; i < 8; i++) {\n"
    "    float th = float(i) * 0.785398;\n"
    "    o += occluded(p, uLightPos + (a * cos(th) + b * sin(th)) * r * (i % 2 == 0 ? 1.0 : 0.55));\n"
    "  }\n"
    "  return 1.0 - o / 9.0;\n"
    "}\n"
    /* Glossy reflection of the cube's faces. */
    "vec3 cubeReflection(vec3 P, vec3 R, float rough){\n"
    "  vec3 lp; float t = hitCube(P, R, lp);\n"
    "  if (t < 0.0) return vec3(0.0);\n"
    "  vec3 a = abs(lp); int k;\n"
    "  if (a.x >= a.y && a.x >= a.z) k = lp.x > 0.0 ? 0 : 1;\n"
    "  else if (a.y >= a.z) k = lp.y > 0.0 ? 2 : 3;\n"
    "  else k = lp.z > 0.0 ? 4 : 5;\n"
    "  vec2 uv = vec2(dot(lp, FT[k]), dot(lp, FB[k])) * 0.5 + 0.5;\n"
    "  float lodAbs = 1.5 + log2(1.0 + rough * t * 20.0);\n"   /* blurrier further away */
    "  return faceRad(k, uv, min(lodAbs - uFace[k].y, 0.0)) * uEmit * 0.35;\n"
    "}\n"
    "vec3 shade(vec3 P, vec3 N, vec3 alb, float rough, float refl){\n"
    "  vec3 V = normalize(uCamPos - P);\n"
    "  vec3 L = uLightPos - P; float d = length(L); L /= d;\n"
    "  float att = 1.0 / (1.0 + 0.04 * d * d);\n"
    "  float diff = max(dot(N, L), 0.0);\n"
    "  float sh = diff > 0.0 ? softShadow(P + N * 0.01) : 0.0;\n"
    "  float spec = pow(max(dot(N, normalize(L + V)), 0.0), mix(400.0, 30.0, rough)) * (1.0 - rough);\n"
    "  vec3 emis = cubeEmission(P, N);\n"
    "  float ao = 1.0 - 0.5 * exp(-0.8 * max(length(P - uCubePos) - uCubeHalf, 0.0));\n"
    "  vec3 col = alb * (vec3(0.012) * ao + 0.7 * diff * att * sh * uLightCol + emis)\n"
    "           + spec * att * sh * uLightCol * 1.5;\n"
    "  float fres = 0.04 + 0.96 * pow(1.0 - max(dot(N, V), 0.0), 5.0);\n"
    "  if (refl > 0.0) col += cubeReflection(P + N * 0.01, reflect(-V, N), rough) * refl * mix(0.25, 1.0, fres);\n"
    "  return col;\n"
    "}\n";

static const char *ROOM_FS =
    "in vec3 vPos; in vec3 vNrm; in vec2 vUV;\n"
    "void main(){\n"
    "  vec3 N = normalize(vNrm);\n"
    "  vec3 P = vPos;\n"
    "  vec3 alb; float rough, refl;\n"
    "  if (N.y > 0.5) {\n"                      /* floor: polished checker */
    "    vec2 c = floor(P.xz);\n"
    "    alb = mix(vec3(0.06, 0.055, 0.05), vec3(0.32, 0.30, 0.28), mod(c.x + c.y, 2.0));\n"
    "    rough = 0.06; refl = 1.0;\n"
    "  } else if (N.y < -0.5) {\n"              /* ceiling */
    "    alb = vec3(0.30); rough = 0.5; refl = 0.0;\n"
    "  } else {\n"                              /* walls: panels */
    "    vec2 q = vec2(abs(N.x) > 0.5 ? P.z : P.x, P.y) / 2.0;\n"
    "    vec2 g = abs(fract(q) - 0.5);\n"
    "    float seam = smoothstep(0.47, 0.49, max(g.x, g.y));\n"
    "    alb = mix(vec3(0.30, 0.31, 0.34), vec3(0.08), seam);\n"
    "    rough = 0.45; refl = 0.0;\n"
    "  }\n"
    "  oColor = vec4(shade(P, N, alb, rough, refl), 1.0);\n"
    "}\n";

/* PhysX debris: glazed bricks in four finishes. */
static const char *DEBRIS_FS =
    "in vec3 vPos; in vec3 vNrm; in vec2 vUV; flat in float vMat;\n"
    "void main(){\n"
    "  vec3 N = normalize(vNrm);\n"
    "  int m = int(vMat + 0.5);\n"
    "  vec3 alb; float rough, refl;\n"
    "  if (m == 0)      { alb = vec3(0.55, 0.52, 0.47); rough = 0.25; refl = 0.5; }\n"
    "  else if (m == 1) { alb = vec3(0.03, 0.03, 0.035); rough = 0.06; refl = 1.0; }\n"
    "  else if (m == 2) { alb = vec3(0.08, 0.27, 0.29); rough = 0.3; refl = 0.4; }\n"
    "  else             { alb = vec3(0.42, 0.15, 0.08); rough = 0.45; refl = 0.2; }\n"
    "  vec2 e = min(vUV, 1.0 - vUV);\n"         /* darkened, rounded-looking edges */
    "  alb *= mix(0.45, 1.0, smoothstep(0.0, 0.08, min(e.x, e.y)));\n"
    "  oColor = vec4(shade(vPos, N, alb, rough, refl), 1.0);\n"
    "}\n";

static const char *LIGHT_FS =
    "in vec3 vPos; in vec3 vNrm; in vec2 vUV;\n"
    "layout(location=0) out vec4 oColor;\n"
    "void main(){\n"
    "  float f = max(dot(normalize(vNrm), normalize(uCamPos - vPos)), 0.0);\n"
    "  oColor = vec4(mix(uLightCol, vec3(1.0), f) * 6.0, 1.0);\n"
    "}\n";

/* ---------------------------------------------------------------- post (bloom + tonemap) */

static const char *POST_UBO = "GFX_UBO(0) st_Uniforms { vec4 uP0; vec4 uP1; };\n";

static const char *POST_DOWN_FS =
    "GFX_TEX(1) sampler2D uSrc;\n"
    "#define uSrcTexel uP0.xy\n#define uInvRes uP0.zw\n#define uPrefilter uP1.x\n"
    "layout(location=0) out vec4 o;\n"
    "void main(){\n"
    "  vec2 uv = gl_FragCoord.xy * uInvRes; vec2 t = uSrcTexel;\n"
    "  vec3 c = texture(uSrc, uv).rgb * 0.5\n"
    "    + (texture(uSrc, uv + vec2(-t.x, -t.y)).rgb + texture(uSrc, uv + vec2(t.x, -t.y)).rgb\n"
    "     + texture(uSrc, uv + vec2(-t.x,  t.y)).rgb + texture(uSrc, uv + vec2(t.x,  t.y)).rgb) * 0.125;\n"
    "  if (uPrefilter > 0.5) {\n"
    "    if (any(isnan(c)) || any(isinf(c))) c = vec3(0.0);\n"
    "    c = clamp(c, vec3(0.0), vec3(40.0));\n"
    "    float br = max(c.r, max(c.g, c.b));\n"
    "    float soft = clamp(br - 0.45, 0.0, 0.5); soft = soft * soft / 2.0;\n"
    "    c *= max(soft, br - 0.95) / max(br, 1e-4);\n"
    "  }\n"
    "  o = vec4(c, 1.0);\n"
    "}\n";

static const char *POST_UP_FS =
    "GFX_TEX(1) sampler2D uSrc;\n"
    "#define uSrcTexel uP0.xy\n#define uInvRes uP0.zw\n"
    "layout(location=0) out vec4 o;\n"
    "void main(){\n"
    "  vec2 uv = gl_FragCoord.xy * uInvRes; vec2 t = uSrcTexel;\n"
    "  vec3 c = texture(uSrc, uv).rgb * 4.0;\n"
    "  c += (texture(uSrc, uv + vec2(t.x, 0)).rgb + texture(uSrc, uv - vec2(t.x, 0)).rgb\n"
    "      + texture(uSrc, uv + vec2(0, t.y)).rgb + texture(uSrc, uv - vec2(0, t.y)).rgb) * 2.0;\n"
    "  c += texture(uSrc, uv + t).rgb + texture(uSrc, uv - t).rgb\n"
    "      + texture(uSrc, uv + vec2(t.x, -t.y)).rgb + texture(uSrc, uv + vec2(-t.x, t.y)).rgb;\n"
    "  o = vec4(c / 16.0, 1.0);\n"
    "}\n";

/* Faithful up to ~0.8 (so the face shaders keep their look), soft shoulder
 * above.  uFlip: the target stores rows top-down (Vulkan swapchain). */
static const char *POST_FINAL_FS =
    "GFX_TEX(1) sampler2D uScene; GFX_TEX(2) sampler2D uBloom;\n"
    "#define uInvRes uP0.xy\n#define uBloomStr uP0.z\n#define uFlip uP0.w\n"
    "layout(location=0) out vec4 o;\n"
    "vec3 shoulder(vec3 c){\n"
    "  vec3 k = 0.8 + 0.2 * (1.0 - exp(-(c - 0.8) / 0.2));\n"
    "  return mix(c, k, step(0.8, c));\n"
    "}\n"
    "void main(){\n"
    "  vec2 uv = gl_FragCoord.xy * uInvRes;\n"
    "  if (uFlip > 0.5) uv.y = 1.0 - uv.y;\n"
    "  vec3 s = texture(uScene, uv).rgb, b = texture(uBloom, uv).rgb;\n"
    "  if (any(isnan(s)) || any(isinf(s))) s = vec3(0.0);\n"
    "  if (any(isnan(b)) || any(isinf(b))) b = vec3(0.0);\n"
    "  vec3 c = s + b * uBloomStr;\n"
    "  c = shoulder(max(c, 0.0));\n"
    "  float dither = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) / 255.0;\n"
    "  o = vec4(pow(c, vec3(1.0 / 2.2)) + dither, 1.0);\n"
    "}\n";

/* Shows one texture full-window (aspect-fit): a face shader, or the
 * offline frame in the preview window. */
static const char *POST_VIEW_FS =
    "GFX_TEX(1) sampler2D uTex;\n"
    "#define uInvRes uP0.xy\n#define uFlip uP0.w\n#define uScale uP1.xy\n"
    "layout(location=0) out vec4 o;\n"
    "void main(){\n"
    "  vec2 uv = (gl_FragCoord.xy * uInvRes - 0.5) * uScale + 0.5;\n"
    "  if (uFlip > 0.5) uv.y = 1.0 - uv.y;\n"
    "  if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { o = vec4(0,0,0,1); return; }\n"
    "  o = vec4(textureLod(uTex, uv, 0.0).rgb, 1.0);\n"
    "}\n";

#define BLOOM_LEVELS 6

typedef struct {
    int w, h;
    GfxTex *msaa, *depth, *res; /* msaa NULL: no multisampling, draw into res */
    GfxTex *bl[BLOOM_LEVELS + 1];
    int bl_w[BLOOM_LEVELS + 1], bl_h[BLOOM_LEVELS + 1];
} HDR;

static HDR g_hdr;

static void hdr_free(HDR *h) {
    if (!h->w) return;
    gfx->wait_idle();
    gfx->tex_free(h->msaa);
    gfx->tex_free(h->depth);
    for (int k = 0; k <= BLOOM_LEVELS; k++) gfx->tex_free(h->bl[k]); /* bl[0] is res */
    memset(h, 0, sizeof *h);
}

static void hdr_create(HDR *h, int w, int hgt) {
    hdr_free(h);
    h->w = w; h->h = hgt;
    int samples = gfx->max_samples() >= 4 ? 4 : gfx->max_samples();
    if (samples > 1) h->msaa = gfx->texture(GFX_RGBA16F, w, hgt, 1, 0, samples);
    h->depth = gfx->texture(GFX_DEPTH, w, hgt, 1, 0, samples);
    h->res = gfx->texture(GFX_RGBA16F, w, hgt, 1, 0, 1);
    h->bl[0] = h->res; h->bl_w[0] = w; h->bl_h[0] = hgt;
    for (int k = 1; k <= BLOOM_LEVELS; k++) {
        h->bl_w[k] = h->bl_w[k - 1] / 2 > 1 ? h->bl_w[k - 1] / 2 : 1;
        h->bl_h[k] = h->bl_h[k - 1] / 2 > 1 ? h->bl_h[k - 1] / 2 : 1;
        h->bl[k] = gfx->texture(GFX_RGBA16F, h->bl_w[k], h->bl_h[k], 1, 0, 1);
    }
}

/* ---------------------------------------------------------------- meshes */

typedef struct { float p[3], n[3], uv[2]; } Vtx;

static void build_box(Vtx *out, v3 h, int inward) {
    static const float quad[6][2] = {{0,0},{1,0},{1,1},{0,0},{1,1},{0,1}};
    float he[3] = {h.x, h.y, h.z};
    for (int f = 0; f < 6; f++)
        for (int k = 0; k < 6; k++) {
            int q = inward ? 5 - k : k;
            float u = quad[q][0], v = quad[q][1];
            Vtx *o = &out[f * 6 + k];
            for (int a = 0; a < 3; a++) {
                o->p[a] = (FACE_N[f][a] + (2*u - 1) * FACE_T[f][a] + (2*v - 1) * FACE_B[f][a]) * he[a];
                o->n[a] = inward ? -FACE_N[f][a] : FACE_N[f][a];
            }
            o->uv[0] = u; o->uv[1] = v;
        }
}

static int build_sphere(Vtx **out, int slices, int stacks) {
    int n = slices * stacks * 6;
    Vtx *v = malloc(sizeof(Vtx) * (size_t)n);
    int k = 0;
    for (int i = 0; i < stacks; i++)
        for (int j = 0; j < slices; j++) {
            int idx[6][2] = {{i,j},{i+1,j},{i+1,j+1},{i,j},{i+1,j+1},{i,j+1}};
            for (int c = 0; c < 6; c++) {
                float th = (float)idx[c][0] / (float)stacks * 3.14159265f;
                float ph = (float)idx[c][1] / (float)slices * 6.2831853f;
                float x = sinf(th) * cosf(ph), y = cosf(th), z = -sinf(th) * sinf(ph);
                Vtx *o = &v[k++];
                o->p[0] = o->n[0] = x; o->p[1] = o->n[1] = y; o->p[2] = o->n[2] = z;
                o->uv[0] = (float)idx[c][1] / (float)slices;
                o->uv[1] = (float)idx[c][0] / (float)stacks;
            }
        }
    *out = v;
    return n;
}

/* ---------------------------------------------------------------- simulation */

typedef struct {
    v3 cpos, cvel, cang;
    quat crot;
    v3 lpos, lvel;
    unsigned int rng;
} Sim;

static Sim g_sim;

static float frand(Sim *s) {
    s->rng = s->rng * 1664525u + 1013904223u;
    return (float)(s->rng >> 8) / 16777216.0f;
}

static void sim_init(Sim *s) {
    memset(s, 0, sizeof *s);
    s->rng = 0xC0FFEEu;
    s->cpos = V3(0, 1.5f, 0);
    s->cvel = V3(3.1f, 4.0f, 2.3f);
    s->cang = V3(0.9f, 1.3f, 0.4f);
    s->crot.w = 1;
    s->lpos = V3(-4, 3, 3);
    s->lvel = V3(3.7f, 2.1f, -2.9f);
}

static void sim_step(Sim *s, float dt, int cube_frozen) {
    const float *room = &ROOM_HALF.x;
    if (!cube_frozen) {
        /* Cube: ballistic with gravity, bounces off all six walls. */
        s->cvel.y -= GRAVITY * dt;
        s->cpos = v3add(s->cpos, v3scale(s->cvel, dt));
        s->crot = qintegrate(s->crot, s->cang, dt);

        float R[9];
        qtomat3(s->crot, R);
        float ext[3]; /* exact extent of the rotated box along each world axis */
        for (int a = 0; a < 3; a++)
            ext[a] = CUBE_HALF * (fabsf(R[0 + a]) + fabsf(R[3 + a]) + fabsf(R[6 + a]));
        float *p = &s->cpos.x, *v = &s->cvel.x, *w = &s->cang.x;
        for (int a = 0; a < 3; a++) {
            float lim = room[a] - ext[a];
            int hit = 0;
            if (p[a] < -lim) { p[a] = -lim; if (v[a] < 0) { v[a] = -v[a]; hit = 1; } }
            if (p[a] > lim) { p[a] = lim; if (v[a] > 0) { v[a] = -v[a]; hit = 1; } }
            if (hit) {
                if (a == 1 && v[1] > 0) {
                    /* Floor: relaunch to a random height (never dies down). */
                    float hgt = 2.0f * room[1] - 2.0f * ext[1] - 0.5f - 2.5f * frand(s);
                    v[1] = sqrtf(2.0f * GRAVITY * (hgt > 1.0f ? hgt : 1.0f));
                }
                for (int k = 0; k < 3; k++) w[k] = w[k] * 0.8f + (frand(s) - 0.5f) * 2.5f;
            }
        }
    }

    /* Light: constant speed, bounces off walls and off the cube. */
    s->lpos = v3add(s->lpos, v3scale(s->lvel, dt));
    float *lp = &s->lpos.x, *lv = &s->lvel.x;
    for (int a = 0; a < 3; a++) {
        float lim = room[a] - LIGHT_RADIUS - 0.05f;
        if (lp[a] < -lim) { lp[a] = -lim; if (lv[a] < 0) lv[a] = -lv[a]; }
        if (lp[a] > lim) { lp[a] = lim; if (lv[a] > 0) lv[a] = -lv[a]; }
    }
    v3 d = v3sub(s->lpos, s->cpos);
    float dist = v3len(d), minr = CUBE_HALF * 1.732f + LIGHT_RADIUS;
    if (dist < minr && dist > 1e-4f) {
        v3 n = v3scale(d, 1.0f / dist);
        s->lpos = v3add(s->cpos, v3scale(n, minr));
        v3 rel = v3sub(s->lvel, s->cvel);
        float vn = v3dot(rel, n);
        if (vn < 0) s->lvel = v3sub(s->lvel, v3scale(n, 2.0f * vn));
        float sp = v3len(s->lvel);
        s->lvel = v3scale(s->lvel, 5.3f / (sp > 1e-4f ? sp : 1.0f));
    }
}

/* ---------------------------------------------------------------- camera & picking */

static v3 g_cam_eye, g_cam_at = {0, -0.5f, 0};

static void update_camera(double t) {
    if (!g_user_cam) {
        g_cam_yaw = 0.785 + 0.25 * sin(t * 0.11);
        g_cam_pitch = -0.22 + 0.06 * sin(t * 0.07);
    }
    float cdist = 9.0f;
    v3 cam = V3(cdist * (float)(cos(g_cam_pitch) * sin(g_cam_yaw)),
                0.5f + cdist * (float)sin(-g_cam_pitch),
                cdist * (float)(cos(g_cam_pitch) * cos(g_cam_yaw)));
    float *cp = &cam.x;
    const float *rh = &ROOM_HALF.x;
    for (int a = 0; a < 3; a++) {
        float lim = rh[a] - 0.3f;
        if (cp[a] > lim) cp[a] = lim;
        if (cp[a] < -lim) cp[a] = -lim;
    }
    g_cam_eye = cam;
}

/* World ray through the cursor. */
static v3 cursor_ray(GLFWwindow *win) {
    double mx, my;
    int ww, wh;
    glfwGetCursorPos(win, &mx, &my);
    glfwGetWindowSize(win, &ww, &wh);
    float nx = (float)(2.0 * mx / ww - 1.0), ny = (float)(1.0 - 2.0 * my / wh);
    v3 f = v3norm(v3sub(g_cam_at, g_cam_eye));
    v3 s = v3norm(v3cross(f, V3(0, 1, 0)));
    v3 u = v3cross(s, f);
    float th = tanf(FOVY * 0.5f), aspect = (float)ww / (float)(wh ? wh : 1);
    return v3norm(v3add(f, v3add(v3scale(s, nx * th * aspect), v3scale(u, ny * th))));
}

static void cube_frame(float R[9], m4 *model, m4 *inv) {
    qtomat3(g_sim.crot, R);
    m4trs(g_sim.cpos, R, CUBE_HALF, model, inv);
}

static v3 xform(const m4 *m, v3 p, float w) {
    return V3(m->m[0] * p.x + m->m[4] * p.y + m->m[8] * p.z + m->m[12] * w,
              m->m[1] * p.x + m->m[5] * p.y + m->m[9] * p.z + m->m[13] * w,
              m->m[2] * p.x + m->m[6] * p.y + m->m[10] * p.z + m->m[14] * w);
}

/* Ray vs cube; returns cube face index and uv, or -1. If force_face >= 0,
 * intersects that face's plane instead (for dragging off the edge). */
static int pick_cube(v3 eye, v3 dir, int force_face, float uv[2]) {
    float R[9];
    m4 model, inv;
    cube_frame(R, &model, &inv);
    v3 ro = xform(&inv, eye, 1), rd = xform(&inv, dir, 0);
    float *o = &ro.x, *d = &rd.x;
    v3 lp;
    int face = -1;
    if (force_face >= 0) {
        int a = force_face / 2;
        float sgn = (force_face & 1) ? -1.0f : 1.0f;
        if (fabsf(d[a]) < 1e-6f) return -1;
        float t = (sgn - o[a]) / d[a];
        if (t <= 0) return -1;
        lp = v3add(ro, v3scale(rd, t));
        face = force_face;
    } else {
        float tn = -1e30f, tf = 1e30f;
        for (int a = 0; a < 3; a++) {
            float dd = fabsf(d[a]) < 1e-8f ? 1e-8f : d[a];
            float t0 = (-1 - o[a]) / dd, t1 = (1 - o[a]) / dd;
            if (t0 > t1) { float tmp = t0; t0 = t1; t1 = tmp; }
            if (t0 > tn) tn = t0;
            if (t1 < tf) tf = t1;
        }
        if (!(tn < tf && tn > 0)) return -1;
        lp = v3add(ro, v3scale(rd, tn));
        float a0 = fabsf(lp.x), a1 = fabsf(lp.y), a2 = fabsf(lp.z);
        if (a0 >= a1 && a0 >= a2) face = lp.x > 0 ? 0 : 1;
        else if (a1 >= a2) face = lp.y > 0 ? 2 : 3;
        else face = lp.z > 0 ? 4 : 5;
    }
    v3 T = V3(FACE_T[face][0], FACE_T[face][1], FACE_T[face][2]);
    v3 B = V3(FACE_B[face][0], FACE_B[face][1], FACE_B[face][2]);
    uv[0] = fminf(fmaxf(v3dot(lp, T) * 0.5f + 0.5f, 0.0f), 1.0f);
    uv[1] = fminf(fmaxf(v3dot(lp, B) * 0.5f + 0.5f, 0.0f), 1.0f);
    return face;
}

static void face_uv_to_pixel(const Face *f, const float uv[2], float px[2]) {
    float us = face_uscale(f);
    px[0] = (0.5f + (uv[0] - 0.5f) * us) * (float)f->w;
    px[1] = uv[1] * (float)f->h;
}

/* ---------------------------------------------------------------- input */

static void set_title(GLFWwindow *w) {
    if (!w) return;
    char t[512];
    size_t n = (size_t)snprintf(t, sizeof t, "shader-cube  [%s · %.0f fps]  —  ", g_api_label, g_fps_shown);
    if (g_focus_face >= 0)
        n += (size_t)snprintf(t + n, sizeof t - n, "keyboard → %s  (click off the cube to release)",
                              g_faces[g_focus_face].title);
    else if (g_view_face >= 0)
        n += (size_t)snprintf(t + n, sizeof t - n, "viewing %s  (F6: next, F7: back to room)",
                              g_faces[g_view_face].title);
    else
        n += (size_t)snprintf(t + n, sizeof t - n, "keys 1-%d stop/start a face", g_nfaces);
    int first = 1;
    for (int i = 0; i < g_nfaces && n < sizeof t; i++)
        if (g_faces[i].stopped) {
            n += (size_t)snprintf(t + n, sizeof t - n, "%s%d", first ? "  |  stopped: " : " ", i + 1);
            first = 0;
        }
    glfwSetWindowTitle(w, t);
}

/* GLFW key -> JavaScript keyCode (what Shadertoy's keyboard texture uses). */
static int js_keycode(int key) {
    if ((key >= GLFW_KEY_A && key <= GLFW_KEY_Z) || (key >= GLFW_KEY_0 && key <= GLFW_KEY_9)) return key;
    if (key >= GLFW_KEY_KP_0 && key <= GLFW_KEY_KP_9) return 96 + key - GLFW_KEY_KP_0;
    if (key >= GLFW_KEY_F1 && key <= GLFW_KEY_F12) return 112 + key - GLFW_KEY_F1;
    switch (key) {
    case GLFW_KEY_SPACE: return 32;
    case GLFW_KEY_ENTER: case GLFW_KEY_KP_ENTER: return 13;
    case GLFW_KEY_TAB: return 9;
    case GLFW_KEY_BACKSPACE: return 8;
    case GLFW_KEY_LEFT_SHIFT: case GLFW_KEY_RIGHT_SHIFT: return 16;
    case GLFW_KEY_LEFT_CONTROL: case GLFW_KEY_RIGHT_CONTROL: return 17;
    case GLFW_KEY_LEFT_ALT: case GLFW_KEY_RIGHT_ALT: return 18;
    case GLFW_KEY_PAGE_UP: return 33;
    case GLFW_KEY_PAGE_DOWN: return 34;
    case GLFW_KEY_END: return 35;
    case GLFW_KEY_HOME: return 36;
    case GLFW_KEY_LEFT: return 37;
    case GLFW_KEY_UP: return 38;
    case GLFW_KEY_RIGHT: return 39;
    case GLFW_KEY_DOWN: return 40;
    case GLFW_KEY_INSERT: return 45;
    case GLFW_KEY_DELETE: return 46;
    case GLFW_KEY_KP_MULTIPLY: return 106;
    case GLFW_KEY_KP_ADD: return 107;
    case GLFW_KEY_KP_SUBTRACT: return 109;
    case GLFW_KEY_KP_DECIMAL: return 110;
    case GLFW_KEY_KP_DIVIDE: return 111;
    case GLFW_KEY_SEMICOLON: return 186;
    case GLFW_KEY_EQUAL: return 187;
    case GLFW_KEY_COMMA: return 188;
    case GLFW_KEY_MINUS: return 189;
    case GLFW_KEY_PERIOD: return 190;
    case GLFW_KEY_SLASH: return 191;
    case GLFW_KEY_GRAVE_ACCENT: return 192;
    case GLFW_KEY_LEFT_BRACKET: return 219;
    case GLFW_KEY_BACKSLASH: return 220;
    case GLFW_KEY_RIGHT_BRACKET: return 221;
    case GLFW_KEY_APOSTROPHE: return 222;
    }
    return -1;
}

static void on_key(GLFWwindow *w, int key, int sc, int action, int mods) {
    (void)sc; (void)mods;
    /* 1-6: stop / restart that face's shader (all cube faces using it). */
    if (key >= GLFW_KEY_1 && key <= GLFW_KEY_6) {
        int i = key - GLFW_KEY_1;
        if (action == GLFW_PRESS && i < g_nfaces) {
            g_faces[i].stopped = !g_faces[i].stopped;
            printf("face %d (%s): %s\n", i + 1, g_faces[i].title, g_faces[i].stopped ? "stopped" : "running");
            fflush(stdout);
            set_title(w);
        }
        return;
    }
    if (action == GLFW_PRESS) {
        switch (key) {
        case GLFW_KEY_ESCAPE: glfwSetWindowShouldClose(w, 1); return;
        case GLFW_KEY_F2: g_paused = !g_paused; return;
        case GLFW_KEY_F3: g_user_cam = 0; return;
        case GLFW_KEY_F5: g_reload = 1; return;
        case GLFW_KEY_F6:
            g_view_face = (g_view_face + 1) % g_nfaces; set_title(w); return;
        case GLFW_KEY_F7: g_view_face = -1; set_title(w); return;
        case GLFW_KEY_F8: g_blast = 1; return;
        }
    }
    if (g_focus_face < 0) return;
    int k = js_keycode(key);
    if (k < 0 || k > 255) return;
    if (action == GLFW_PRESS) {
        g_kbd[0][k] = 255;
        g_kbd[1][k] = 255;
        g_kbd[2][k] ^= 255;
    } else if (action == GLFW_RELEASE) {
        g_kbd[0][k] = 0;
    }
}

static void on_button(GLFWwindow *w, int button, int action, int mods) {
    (void)mods;
    if (action == GLFW_PRESS) {
        glfwGetCursorPos(w, &g_last_mx, &g_last_my);
        if (button == GLFW_MOUSE_BUTTON_LEFT && g_view_face < 0) {
            float uv[2];
            int cf = pick_cube(g_cam_eye, cursor_ray(w), -1, uv);
            if (cf >= 0) {
                Face *f = &g_faces[cf % g_nfaces];
                float px[2];
                face_uv_to_pixel(f, uv, px);
                f->mouse[0] = f->mouse[2] = px[0];
                f->mouse[1] = f->mouse[3] = px[1];
                g_grab_face = cf;
                if (g_focus_face != cf % g_nfaces) memset(g_kbd, 0, sizeof g_kbd);
                g_focus_face = cf % g_nfaces;
                set_title(w);
                return;
            }
            if (g_focus_face >= 0) { g_focus_face = -1; memset(g_kbd, 0, sizeof g_kbd); set_title(w); }
        }
        g_orbiting = 1;
        g_user_cam = 1;
    } else if (action == GLFW_RELEASE) {
        if (g_grab_face >= 0 && button == GLFW_MOUSE_BUTTON_LEFT) {
            Face *f = &g_faces[g_grab_face % g_nfaces];
            f->mouse[2] = -fabsf(f->mouse[2]);
            g_grab_face = -1;
        }
        g_orbiting = 0;
    }
}

static void on_cursor(GLFWwindow *w, double x, double y) {
    if (g_grab_face >= 0) {
        float uv[2], px[2];
        if (pick_cube(g_cam_eye, cursor_ray(w), g_grab_face, uv) >= 0) {
            Face *f = &g_faces[g_grab_face % g_nfaces];
            face_uv_to_pixel(f, uv, px);
            f->mouse[0] = px[0];
            f->mouse[1] = px[1];
        }
        return;
    }
    if (!g_orbiting) return;
    g_cam_yaw -= (x - g_last_mx) * 0.005;
    g_cam_pitch -= (y - g_last_my) * 0.005;
    if (g_cam_pitch > 0.6) g_cam_pitch = 0.6;
    if (g_cam_pitch < -0.6) g_cam_pitch = -0.6;
    g_last_mx = x; g_last_my = y;
}

/* ---------------------------------------------------------------- frame rendering */

typedef struct {
    GfxProg *room, *cube, *light, *debris, *down, *up, *final, *view;
    GfxBuf *cube_vb, *room_vb, *sphere_vb;
    int nsphere;
} Scene;

static GfxProg *scene_program(const char *label, const char *fs, const char *lib, int instanced) {
    GfxProgDesc d = {.label = label, .vtx = instanced ? GFX_VTX_MESH_INST : GFX_VTX_MESH,
                     .tex = {"uF0", "uF1", "uF2", "uF3", "uF4", "uF5"}, .ntex = 6};
    if (!lib) { d.tex[0] = "uTex"; d.ntex = 1; }
    if (instanced) d.vs[d.nvs++] = "#define INSTANCED 1\n";
    d.vs[d.nvs++] = SCENE_UBO;
    d.vs[d.nvs++] = SCENE_VS;
    d.fs[d.nfs++] = SCENE_UBO;
    if (lib) d.fs[d.nfs++] = lib;
    d.fs[d.nfs++] = fs;
    return gfx->program(&d);
}

static GfxProg *post_program(const char *label, const char *fs, const char *t0, const char *t1) {
    GfxProgDesc d = {.label = label, .vs = {FS_TRI_VS}, .nvs = 1, .fs = {POST_UBO, fs}, .nfs = 2,
                     .tex = {t0, t1}, .ntex = t1 ? 2 : 1, .vtx = GFX_VTX_NONE};
    return gfx->program(&d);
}

static void make_scene(Scene *s) {
    s->room = scene_program("room", ROOM_FS, LIGHTING_FS, 0);
    s->debris = scene_program("debris", DEBRIS_FS, LIGHTING_FS, 1);
    s->cube = scene_program("cube", CUBE_FS, NULL, 0);
    s->light = scene_program("light", LIGHT_FS, NULL, 0);
    s->down = post_program("bloom-down", POST_DOWN_FS, "uSrc", NULL);
    s->up = post_program("bloom-up", POST_UP_FS, "uSrc", NULL);
    s->final = post_program("final", POST_FINAL_FS, "uScene", "uBloom");
    s->view = post_program("view", POST_VIEW_FS, "uTex", NULL);
    if (!s->room || !s->debris || !s->cube || !s->light || !s->down || !s->up || !s->final || !s->view) exit(1);

    Vtx box[36], room[36], *sphere;
    build_box(box, V3(1, 1, 1), 0);
    build_box(room, ROOM_HALF, 1);
    s->nsphere = build_sphere(&sphere, 24, 16);
    s->cube_vb = gfx->buffer(box, sizeof box);
    s->room_vb = gfx->buffer(room, sizeof room);
    s->sphere_vb = gfx->buffer(sphere, sizeof(Vtx) * (size_t)s->nsphere);
    free(sphere);
}

static void free_scene(Scene *s) {
    GfxProg *progs[] = {s->room, s->cube, s->light, s->debris, s->down, s->up, s->final, s->view};
    for (size_t i = 0; i < sizeof progs / sizeof *progs; i++) gfx->prog_free(progs[i]);
    gfx->buf_free(s->cube_vb);
    gfx->buf_free(s->room_vb);
    gfx->buf_free(s->sphere_vb);
}

/* Draws `tex` aspect-fit into `dst` (NULL: the window). */
static void draw_view(const Scene *s, GfxTex *dst, GfxTex *tex, int tw, int th) {
    GfxPass pp = {.color = dst};
    gfx->begin_pass(&pp);
    int w, h;
    gfx->pass_size(&w, &h);
    float wa = (float)w / (float)h, fa = (float)tw / (float)th;
    PostUniforms u = {{1.0f / (float)w, 1.0f / (float)h, 0, (!dst && gfx->flip_y()) ? 1.0f : 0.0f},
                      {wa > fa ? wa / fa : 1.0f, wa > fa ? 1.0f : fa / wa, 0, 0}};
    GfxDraw d = {.prog = s->view, .ubo = &u, .ubo_size = sizeof u, .tex = {tex}, .filter = {GFX_LINEAR},
                 .count = 3};
    gfx->draw(&d);
    gfx->end_pass();
}

/* The room, cube, light and debris into g_hdr, then bloom and tonemap into
 * `dst` (NULL: the window). */
static void draw_room(const Scene *s, GfxTex *dst, double sim_time, const float *debris, int ndebris) {
    int w = g_hdr.w, h = g_hdr.h;
    GfxPass scene = {.color = g_hdr.res, .msaa = g_hdr.msaa, .depth = g_hdr.depth, .clear = 1,
                     .clear_color = {0, 0, 0, 1}};
    gfx->begin_pass(&scene);

    v3 cam = g_cam_eye;
    m4 view = m4lookat(cam, g_cam_at, V3(0, 1, 0));
    m4 proj = m4perspective(FOVY, (float)w / (float)(h ? h : 1), 0.05f, 100.0f);
    m4 vp = m4mul(proj, view);

    float t = (float)sim_time, hue = t * 0.15f;
    v3 lcol = V3(0.75f + 0.25f * cosf(hue), 0.75f + 0.25f * cosf(hue + 2.1f), 0.75f + 0.25f * cosf(hue + 4.2f));

    float R[9];
    m4 cube_model, cube_inv;
    cube_frame(R, &cube_model, &cube_inv);
    m4 ident = m4identity();

    SceneUniforms u;
    memset(&u, 0, sizeof u);
    memcpy(u.viewproj, vp.m, sizeof u.viewproj);
    memcpy(u.model, ident.m, sizeof u.model);
    memcpy(u.cube_inv, cube_inv.m, sizeof u.cube_inv);
    for (int c = 0; c < 3; c++)
        for (int r = 0; r < 3; r++) u.cube_rot[c * 4 + r] = R[c * 3 + r];
    u.cube_rot[15] = 1;
    u.light_pos[0] = g_sim.lpos.x; u.light_pos[1] = g_sim.lpos.y; u.light_pos[2] = g_sim.lpos.z;
    u.light_pos[3] = LIGHT_RADIUS * 2.0f; /* soft shadow radius */
    u.light_col[0] = lcol.x; u.light_col[1] = lcol.y; u.light_col[2] = lcol.z;
    u.cam_pos[0] = cam.x; u.cam_pos[1] = cam.y; u.cam_pos[2] = cam.z; u.cam_pos[3] = CUBE_HALF;
    u.cube_pos[0] = g_sim.cpos.x; u.cube_pos[1] = g_sim.cpos.y; u.cube_pos[2] = g_sim.cpos.z; u.cube_pos[3] = 16.0f;
    for (int f = 0; f < 6; f++) {
        const Face *fc = &g_faces[f % g_nfaces];
        u.face[f][0] = face_uscale(fc);
        u.face[f][1] = log2f((float)fc->h / 4.0f); /* EN = 4 in LIGHTING_FS */
    }

    GfxDraw d = {.ubo = &u, .ubo_size = sizeof u, .depth = 1, .cull = 1};
    for (int f = 0; f < 6; f++) {
        d.tex[f] = g_faces[f % g_nfaces].img;
        d.filter[f] = GFX_MIPMAP;
        d.wrap[f] = GFX_CLAMP;
    }

    /* Room */
    d.prog = s->room;
    d.vbuf = s->room_vb;
    d.count = 36;
    gfx->draw(&d);

    /* PhysX debris, instanced */
    if (ndebris > 0) {
        d.prog = s->debris;
        d.vbuf = s->cube_vb;
        d.inst = debris;
        d.ninst = ndebris;
        gfx->draw(&d);
        d.inst = NULL;
        d.ninst = 0;
    }

    /* Cube: one draw per face with that face's shader output. */
    memcpy(u.model, cube_model.m, sizeof u.model);
    GfxDraw cd = {.prog = s->cube, .ubo = &u, .ubo_size = sizeof u, .vbuf = s->cube_vb, .count = 6, .depth = 1,
                  .cull = 1, .filter = {GFX_MIPMAP}, .wrap = {GFX_CLAMP}};
    for (int f = 0; f < 6; f++) {
        cd.tex[0] = g_faces[f % g_nfaces].img;
        cd.first = f * 6;
        u.misc[0] = face_uscale(&g_faces[f % g_nfaces]);
        u.misc[1] = (g_focus_face == f % g_nfaces) ? 1.0f : 0.0f;
        gfx->draw(&cd);
    }

    /* Light bulb */
    float I[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
    m4 lmodel, linv;
    m4trs(g_sim.lpos, I, LIGHT_RADIUS, &lmodel, &linv);
    memcpy(u.model, lmodel.m, sizeof u.model);
    GfxDraw ld = {.prog = s->light, .ubo = &u, .ubo_size = sizeof u, .vbuf = s->sphere_vb, .count = s->nsphere,
                  .depth = 1, .cull = 1};
    gfx->draw(&ld);
    gfx->end_pass(); /* resolves MSAA into g_hdr.res */

    /* Bloom: downsample chain, then additive upsample. */
    PostUniforms pu;
    for (int k = 1; k <= BLOOM_LEVELS; k++) {
        GfxPass pp = {.color = g_hdr.bl[k]};
        gfx->begin_pass(&pp);
        pu = (PostUniforms){{1.0f / (float)g_hdr.bl_w[k - 1], 1.0f / (float)g_hdr.bl_h[k - 1],
                             1.0f / (float)g_hdr.bl_w[k], 1.0f / (float)g_hdr.bl_h[k]},
                            {k == 1 ? 1.0f : 0.0f, 0, 0, 0}};
        GfxDraw bd = {.prog = s->down, .ubo = &pu, .ubo_size = sizeof pu, .tex = {g_hdr.bl[k - 1]},
                      .filter = {GFX_LINEAR}, .count = 3};
        gfx->draw(&bd);
        gfx->end_pass();
    }
    for (int k = BLOOM_LEVELS - 1; k >= 1; k--) {
        GfxPass pp = {.color = g_hdr.bl[k]};
        gfx->begin_pass(&pp);
        pu = (PostUniforms){{1.0f / (float)g_hdr.bl_w[k + 1], 1.0f / (float)g_hdr.bl_h[k + 1],
                             1.0f / (float)g_hdr.bl_w[k], 1.0f / (float)g_hdr.bl_h[k]},
                            {0, 0, 0, 0}};
        GfxDraw bd = {.prog = s->up, .ubo = &pu, .ubo_size = sizeof pu, .tex = {g_hdr.bl[k + 1]},
                      .filter = {GFX_LINEAR}, .count = 3, .blend_add = 1};
        gfx->draw(&bd);
        gfx->end_pass();
    }

    /* Composite + tonemap. */
    GfxPass fp = {.color = dst};
    gfx->begin_pass(&fp);
    int ow, oh;
    gfx->pass_size(&ow, &oh);
    pu = (PostUniforms){{1.0f / (float)ow, 1.0f / (float)oh, 0.35f, (!dst && gfx->flip_y()) ? 1.0f : 0.0f},
                        {0, 0, 0, 0}};
    GfxDraw fd = {.prog = s->final, .ubo = &pu, .ubo_size = sizeof pu, .tex = {g_hdr.res, g_hdr.bl[1]},
                  .filter = {GFX_LINEAR, GFX_LINEAR}, .count = 3};
    gfx->draw(&fd);
    gfx->end_pass();
}

/* ---------------------------------------------------------------- main */

enum { PHYSX_AUTO, PHYSX_GPU, PHYSX_CPU, PHYSX_OFF };

static void usage(const char *argv0) {
    printf("usage: %s [options]\n"
           "\n"
           "rendering:\n"
           "  --api gles|gl|vulkan   graphics API (default gles: OpenGL ES 3.0; gl: OpenGL 4.3 core)\n"
           "  --vsync on|off         sync to the display (default on)\n"
           "  --fps-limit N          cap the frame rate at N frames per second (0 = no cap)\n"
           "  --quit-after SECONDS   exit after this long and print the average frame rate\n"
           "  --size WxH             window size, or output size when rendering offline (default 1600x900)\n"
           "  --gfx-debug            OpenGL debug output / Vulkan validation layer\n"
           "  The GPU is chosen by the system: run under `prime-run` for the NVIDIA GPU.\n"
           "\n"
           "offline (non-realtime) rendering, fixed time step:\n"
           "  --record DIR           write numbered frames to DIR (created if missing)\n"
           "  --frames N             number of frames to write (default: 10 seconds' worth)\n"
           "  --duration SECONDS     alternative to --frames\n"
           "  --rate FPS             frames per simulated second (default 60)\n"
           "  --start SECONDS        simulate up to this time before writing the first frame\n"
           "  --format png|ppm       image format (default png)\n"
           "  --preview              show the frames in a window while recording\n"
           "  --screenshot FILE [--at SECONDS]   write a single frame (.png or .ppm)\n"
           "\n"
           "physics:\n"
           "  --physx auto|gpu|cpu|off  PhysX debris (default auto: GPU/CUDA when rendering on NVIDIA, else CPU)\n"
           "  --debris N             number of debris bodies (default 600)\n"
           "\n"
           "scene:\n"
           "  --shaders DIR  --res N  --view FACE  --stop 1,3\n"
           "\n"
           "  left-click a cube face : mouse + keyboard go to that face's shader\n"
           "  drag elsewhere / right-drag : orbit camera   F3: auto camera\n"
           "  F2 pause  F5 reload shaders  F6 view faces full-window  F7 back  F8 blast the debris  Esc quit\n",
           argv0);
}

int main(int argc, char **argv) {
    GfxConfig cfg = {.api = GFX_GLES, .vsync = 1};
    int size_w = 1600, size_h = 900, size_given = 0;
    double fps_limit = 0, quit_after = 0;
    const char *record_dir = NULL, *shot = NULL;
    double shot_time = 3.0, rate = 60.0, start = 0.0, duration = 10.0;
    int frames = -1, fmt = IMG_PNG, fmt_given = 0, preview = 0;
    int physx_mode = PHYSX_AUTO, ndebris = 600;
    const char *stop_list = NULL;
    int shaders_given = 0;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i], *v = i + 1 < argc ? argv[i + 1] : NULL;
#define ARG(name) (!strcmp(a, name) && v && (i++, 1))
        if (ARG("--shaders")) { g_shader_root = v; shaders_given = 1; }
        else if (ARG("--res")) g_default_res = atoi(v);
        else if (ARG("--view")) g_view_face = atoi(v);
        else if (ARG("--stop")) stop_list = v;
        else if (ARG("--api")) {
            if (!strcmp(v, "gles")) cfg.api = GFX_GLES;
            else if (!strcmp(v, "gl") || !strcmp(v, "opengl")) cfg.api = GFX_GL;
            else if (!strcmp(v, "vulkan") || !strcmp(v, "vk")) cfg.api = GFX_VULKAN;
            else { fprintf(stderr, "unknown --api %s (gles, gl, vulkan)\n", v); return 2; }
        }
        else if (!strcmp(a, "--gles")) cfg.api = GFX_GLES;
        else if (!strcmp(a, "--gl")) cfg.api = GFX_GL;
        else if (!strcmp(a, "--vulkan")) cfg.api = GFX_VULKAN;
        else if (ARG("--vsync")) cfg.vsync = strcmp(v, "off") && strcmp(v, "0");
        else if (ARG("--fps-limit")) fps_limit = atof(v);
        else if (ARG("--quit-after")) quit_after = atof(v);
        else if (ARG("--size")) {
            if (sscanf(v, "%dx%d", &size_w, &size_h) != 2 || size_w < 16 || size_h < 16) {
                fprintf(stderr, "--size wants WxH, e.g. 1920x1080\n");
                return 2;
            }
            size_given = 1;
        }
        else if (!strcmp(a, "--gfx-debug")) cfg.debug = 1;
        else if (ARG("--record")) record_dir = v;
        else if (ARG("--frames")) frames = atoi(v);
        else if (ARG("--duration")) duration = atof(v);
        else if (ARG("--rate")) rate = atof(v);
        else if (ARG("--start")) start = atof(v);
        else if (ARG("--format")) { fmt = strcmp(v, "ppm") ? IMG_PNG : IMG_PPM; fmt_given = 1; }
        else if (!strcmp(a, "--preview")) preview = 1;
        else if (ARG("--screenshot")) shot = v;
        else if (ARG("--at")) shot_time = atof(v);
        else if (ARG("--physx")) {
            if (!strcmp(v, "auto")) physx_mode = PHYSX_AUTO;
            else if (!strcmp(v, "gpu")) physx_mode = PHYSX_GPU;
            else if (!strcmp(v, "cpu")) physx_mode = PHYSX_CPU;
            else if (!strcmp(v, "off")) physx_mode = PHYSX_OFF;
            else { fprintf(stderr, "unknown --physx %s (auto, gpu, cpu, off)\n", v); return 2; }
        }
        else if (ARG("--debris")) ndebris = atoi(v);
        else { usage(argv[0]); return !strcmp(a, "--help") || !strcmp(a, "-h") ? 0 : 2; }
#undef ARG
    }
    if (rate <= 0) rate = 60;
    if (!shaders_given) g_shader_root = default_shader_root();

    /* Offline: fixed time step, frames rendered into out_tex and saved. */
    int offline = record_dir || shot;
    if (shot) {
        start = shot_time;
        frames = 1;
        if (!fmt_given) fmt = img_format_from_name(shot);
    } else if (frames < 0) {
        frames = (int)(duration * rate + 0.5);
    }
    if (offline && !size_given && record_dir) { size_w = 1920; size_h = 1080; }
    if (record_dir && !mkdir_p(record_dir)) { perror(record_dir); return 1; }
    if (offline) cfg.vsync = 0;

    gfx = cfg.api == GFX_VULKAN ? &gfx_vk_backend : &gfx_gl_backend;
    /* Vulkan can render offline without any window system. */
    int need_window = !offline || preview || cfg.api != GFX_VULKAN;
    GLFWwindow *win = NULL;
    if (need_window) {
        if (!glfwInit()) { fprintf(stderr, "glfwInit failed\n"); return 1; }
        gfx->window_hints(&cfg);
        int ww = size_w, wh = size_h;
        if (offline) { /* preview window: fit inside 1280x720 */
            float s = fminf(1.0f, fminf(1280.0f / (float)ww, 720.0f / (float)wh));
            ww = (int)((float)ww * s);
            wh = (int)((float)wh * s);
        }
        glfwWindowHint(GLFW_VISIBLE, offline && !preview ? GLFW_FALSE : GLFW_TRUE);
        win = glfwCreateWindow(ww, wh, "shader-cube", NULL, NULL);
        if (!win) {
            fprintf(stderr, "could not create a %s window\n",
                    cfg.api == GFX_GLES ? "OpenGL ES 3.0" : cfg.api == GFX_GL ? "OpenGL 4.3" : "Vulkan");
            return 1;
        }
    }
    if (!gfx->init(&cfg, win)) return 1;
    snprintf(g_api_label, sizeof g_api_label, "%s · %s",
             cfg.api == GFX_GLES ? "OpenGL ES" : cfg.api == GFX_GL ? "OpenGL" : "Vulkan", gfx->device_name());
    if (win && !offline) {
        glfwSetKeyCallback(win, on_key);
        glfwSetMouseButtonCallback(win, on_button);
        glfwSetCursorPosCallback(win, on_cursor);
    }

    if (!gfx->float32_filterable()) {
        fprintf(stderr, "note: no linear filtering of 32-bit float textures, using RGBA16F buffers\n");
        g_float_fmt = GFX_RGBA16F;
    }

    make_builtin_textures();
    load_all_faces();
    for (const char *c = stop_list; c && *c; c++)
        if (*c >= '1' && *c - '1' < g_nfaces) g_faces[*c - '1'].stopped = 1;

    Scene scene;
    make_scene(&scene);

    /* PhysX: on the GPU when we are rendering on NVIDIA (i.e. prime-run),
     * so plain runs leave the dGPU alone. */
    Phys *phys = NULL;
    float *debris = NULL;
    int nd = 0;
    if (physx_mode != PHYSX_OFF && ndebris > 0) {
        int use_gpu = physx_mode == PHYSX_GPU || (physx_mode == PHYSX_AUTO && gfx->is_nvidia());
        PhysDesc pd = {.room_half = {ROOM_HALF.x, ROOM_HALF.y, ROOM_HALF.z}, .cube_half = CUBE_HALF,
                       .light_radius = LIGHT_RADIUS, .debris = ndebris, .gpu = use_gpu, .seed = 0xD1CEu};
        char info[256];
        phys = phys_create(&pd, info, sizeof info);
        printf("%s\n", info);
        if (phys) debris = calloc((size_t)ndebris, GFX_INST_STRIDE);
    }

    GfxTex *out_tex = offline ? gfx->texture(GFX_RGBA8, size_w, size_h, 1, 0, 1) : NULL;
    ImgWriter *writer = NULL;
    if (offline) {
        long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
        writer = imgw_create(ncpu > 8 ? 6 : ncpu > 2 ? (int)ncpu - 2 : 1, 12);
        if (record_dir)
            printf("recording %d frames of %dx%d at %g fps into %s/\n", frames, size_w, size_h, rate, record_dir);
    }

    sim_init(&g_sim);
    set_title(win);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    double prev = now_s(), sim_time = 0.0, fps = 60.0, deadline = prev, title_at = prev, progress_at = prev;
    double rec_t0 = prev, run_t0 = prev;
    long drawn = 0;
    float acc = 0.0f;
    const float STEP = 1.0f / 240.0f;
    int substep = 0, written = 0;

    for (;;) {
        if (g_quit || (win && glfwWindowShouldClose(win))) {
            if (offline) fprintf(stderr, "%s: stopping after %d frames\n", g_quit ? "interrupted" : "preview closed",
                                 written);
            break;
        }
        if (quit_after > 0 && now_s() - run_t0 >= quit_after) break;
        if (!offline && fps_limit > 0) limit_frame_rate(&deadline, 1.0 / fps_limit);
        if (win) glfwPollEvents();
        double now = now_s();
        float dt = (float)(now - prev);
        prev = now;
        if (dt > 0) fps = fps * 0.95 + 0.05 / dt;
        if (dt > 0.1f) dt = 0.1f;
        if (offline) dt = (float)(1.0 / rate);

        if (g_reload) {
            g_reload = 0;
            g_focus_face = g_grab_face = -1;
            load_all_faces();
            set_title(win);
        }
        int sw = size_w, sh = size_h;
        if (!offline) {
            glfwGetFramebufferSize(win, &sw, &sh);
            if (sw <= 0 || sh <= 0) { glfwWaitEventsTimeout(0.1); continue; } /* minimised */
        }
        if (sw != g_hdr.w || sh != g_hdr.h) hdr_create(&g_hdr, sw, sh);

        if (!g_paused) {
            sim_time += dt;
            acc += dt;
            while (acc >= STEP) {
                sim_step(&g_sim, STEP, g_grab_face >= 0);
                acc -= STEP;
                if (phys && ++substep == 2) { /* PhysX at 120 Hz */
                    substep = 0;
                    float cp[3] = {g_sim.cpos.x, g_sim.cpos.y, g_sim.cpos.z};
                    float cq[4] = {g_sim.crot.w, g_sim.crot.x, g_sim.crot.y, g_sim.crot.z};
                    float lp[3] = {g_sim.lpos.x, g_sim.lpos.y, g_sim.lpos.z};
                    float lq[4] = {1, 0, 0, 0};
                    phys_set_kinematic(phys, PHYS_CUBE, cp, cq);
                    phys_set_kinematic(phys, PHYS_LIGHT, lp, lq);
                    phys_step(phys, 2 * STEP);
                }
            }
        }
        if (phys && g_blast) {
            float c[3] = {g_sim.cpos.x, -ROOM_HALF.y, g_sim.cpos.z};
            phys_blast(phys, c, 7.0f);
        }
        g_blast = 0;
        if (phys) nd = phys_debris(phys, debris);

        Clock ck = {(float)sim_time, dt, offline ? (float)rate : (float)fps, {0}};
        time_t tt = time(NULL);
        struct tm *lt = localtime(&tt);
        ck.date[0] = (float)(lt->tm_year + 1900);
        ck.date[1] = (float)lt->tm_mon;
        ck.date[2] = (float)lt->tm_mday;
        ck.date[3] = (float)(lt->tm_hour * 3600 + lt->tm_min * 60 + lt->tm_sec);

        gfx->begin_frame();

        /* Keyboard texture (rows: held, pressed this frame, toggled). */
        gfx->upload(g_kbd_tex, g_kbd);
        memset(g_kbd[1], 0, 256);

        /* 1. Run each face's Shadertoy passes. */
        if (!g_paused)
            for (int i = 0; i < g_nfaces; i++)
                if (!g_faces[i].stopped) render_face(&g_faces[i], &ck);

        update_camera(sim_time);

        /* 2. The room (or one face full-window) into the output. */
        if (g_view_face >= 0) {
            Face *f = &g_faces[g_view_face % g_nfaces];
            draw_view(&scene, out_tex, f->img, f->w, f->h);
        } else {
            draw_room(&scene, out_tex, sim_time, debris, nd);
        }

        int write = offline && sim_time > start - 0.5 / rate; /* tolerate float drift */
        unsigned char *pixels = NULL;
        if (write) {
            pixels = malloc((size_t)size_w * (size_t)size_h * 4);
            gfx->readback(out_tex, pixels);
        }
        if (offline && preview) draw_view(&scene, NULL, out_tex, size_w, size_h);
        gfx->end_frame();
        drawn++;

        if (write) {
            char *path = malloc(1100);
            if (shot) snprintf(path, 1100, "%s", shot);
            else snprintf(path, 1100, "%s/frame_%06d.%s", record_dir, written, fmt == IMG_PPM ? "ppm" : "png");
            imgw_push(writer, path, pixels, size_w, size_h, fmt);
            if (!written) rec_t0 = progress_at = now_s();
            written++;
            if (shot) printf("wrote %s (t = %.2f s)\n", shot, sim_time);
            else if (now_s() - progress_at > 1.0 || written == frames) {
                progress_at = now_s();
                printf("frame %d/%d  t = %.2f s  (%.1f frames/s)\n", written, frames, sim_time,
                       written / fmax(progress_at - rec_t0, 1e-3));
                fflush(stdout);
            }
            if (written >= frames) break;
        }

        if (win && now - title_at > 0.5) {
            title_at = now;
            g_fps_shown = fps;
            if (offline) {
                char t[320];
                snprintf(t, sizeof t, "shader-cube  [%s]  —  recording %d/%d", g_api_label, written, frames);
                glfwSetWindowTitle(win, t);
            } else {
                set_title(win);
            }
        }
    }

    double elapsed = now_s() - run_t0;
    if (!offline && elapsed > 0)
        printf("%ld frames in %.1f s: %.1f fps average\n", drawn, elapsed, (double)drawn / elapsed);
    int failed = 0;
    if (writer) {
        failed = imgw_finish(writer);
        if (record_dir) printf("wrote %d frames to %s/\n", written - failed, record_dir);
    }
    gfx->wait_idle();
    phys_destroy(phys);
    free(debris);
    for (int i = 0; i < g_nfaces; i++) free_face(&g_faces[i]);
    hdr_free(&g_hdr);
    gfx->tex_free(out_tex);
    gfx->tex_free(g_noise_tex);
    gfx->tex_free(g_kbd_tex);
    gfx->tex_free(g_black_tex);
    gfx->tex_free(g_black3d_tex);
    free_scene(&scene);
    gfx->shutdown();
    if (win) glfwDestroyWindow(win);
    if (need_window) glfwTerminate();
    return failed ? 1 : 0;
}
