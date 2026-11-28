// SPDX-License-Identifier: MIT
/*
 * shader-cube: two scenes rendered through OpenGL ES 3.x, OpenGL 4.3 or
 * Vulkan 1.3 (gfx.h), in real time or offline into numbered image files.
 *
 *   cube    a cube with a Shadertoy shader on each face, bouncing around a
 *           room with a moving light and PhysX debris (scene_cube.c)
 *   galton  a Galton board: balls drop from a hopper through rows of pegs
 *           into bins and pile up into a normal distribution, simulated by
 *           PhysX or by compute shaders (scene_galton.c, gpuphys.c)
 *
 * This file is the application around them: options, the window, the frame
 * loop, bloom and tone mapping, offline recording and the F1 menu (ui.c).
 * The GPU is whatever the system hands us: `prime-run shader-cube` renders
 * on the NVIDIA dGPU, plain `shader-cube` on the default (integrated) GPU.
 */
#include "app.h"

#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "imgout.h"
#include "plat.h"
#include "ui.h"

const GfxBackend *gfx;
App app;

static const Scene *const SCENES[] = {&scene_cube, &scene_galton};
#define NSCENES 2
static const char *const SCENE_NAMES[NSCENES] = {"Shader cube", "Galton board"};
static const Scene *g_scene;
static int g_scene_index, g_scene_next = -1;

static volatile sig_atomic_t g_quit; /* SIGINT / SIGTERM */
static int g_title_dirty = 1;

static void on_signal(int sig) { (void)sig; g_quit = 1; }
void app_set_title_dirty(void) { g_title_dirty = 1; }

/* ---------------------------------------------------------------- utilities */

char *read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) { fclose(f); return NULL; }
    char *s = malloc((size_t)n + 1);
    if (fread(s, 1, (size_t)n, f) != (size_t)n) { free(s); fclose(f); return NULL; }
    s[n] = 0;
    fclose(f);
    return s;
}

/* Sleeps until *deadline (absolute, plat_time clock), then schedules the next. */
static void limit_frame_rate(double *deadline, double period) {
    double t = plat_time();
    if (*deadline > t) plat_sleep_until(*deadline);
    t = plat_time();
    *deadline += period;
    if (*deadline < t) *deadline = t + period; /* fell behind: don't try to catch up */
}

/* The directory holding shaders/ and assets/: the current directory when
 * run from the source tree, else next to the executable:
 * <exe>/../share/shader-cube (AppImage, installs) or <exe> (Windows). */
static void find_data_dir(void) {
    snprintf(app.data_dir, sizeof app.data_dir, ".");
    if (plat_is_file("shaders/face0/image.glsl") || plat_is_file("assets/fonts/OFL.txt")) return;
    char exe[900];
    if (!plat_exe_dir(exe, sizeof exe)) return;
    static const char *const rel[] = {"%s/../share/shader-cube", "%s"};
    for (size_t i = 0; i < sizeof rel / sizeof *rel; i++) {
        char dir[1000], probe[1100];
        snprintf(dir, sizeof dir, rel[i], exe);
        snprintf(probe, sizeof probe, "%s/assets/fonts/OFL.txt", dir);
        if (plat_is_file(probe)) {
            snprintf(app.data_dir, sizeof app.data_dir, "%s", dir);
            return;
        }
    }
}

/* ---------------------------------------------------------------- meshes */

/* Face order: +X -X +Y -Y +Z -Z.  T x B = N, uv (0,0) at -T,-B. */
const float FACE_N[6][3] = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
const float FACE_T[6][3] = {{0,0,-1},{0,0,1},{1,0,0},{1,0,0},{1,0,0},{-1,0,0}};
const float FACE_B[6][3] = {{0,1,0},{0,1,0},{0,0,-1},{0,0,1},{0,1,0},{0,1,0}};

void mesh_box(Vtx *out, v3 h, int inward) {
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

int mesh_sphere(Vtx **out, int slices, int stacks) {
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

int mesh_cylinder(Vtx **out, int slices) {
    int n = slices * 12;
    Vtx *v = malloc(sizeof(Vtx) * (size_t)n);
    int k = 0;
    for (int j = 0; j < slices; j++) {
        float a0 = 6.2831853f * (float)j / (float)slices, a1 = 6.2831853f * (float)(j + 1) / (float)slices;
        float c0 = cosf(a0), s0 = sinf(a0), c1 = cosf(a1), s1 = sinf(a1);
        float u0 = (float)j / (float)slices, u1 = (float)(j + 1) / (float)slices;
        /* side: two triangles, outward normals */
        Vtx side[6] = {
            {{c0, s0, -1}, {c0, s0, 0}, {u0, 0}}, {{c1, s1, -1}, {c1, s1, 0}, {u1, 0}},
            {{c1, s1, 1}, {c1, s1, 0}, {u1, 1}},  {{c0, s0, -1}, {c0, s0, 0}, {u0, 0}},
            {{c1, s1, 1}, {c1, s1, 0}, {u1, 1}},  {{c0, s0, 1}, {c0, s0, 0}, {u0, 1}},
        };
        /* caps: fans around the axis */
        Vtx caps[6] = {
            {{0, 0, 1}, {0, 0, 1}, {0.5f, 0.5f}}, {{c0, s0, 1}, {0, 0, 1}, {u0, 1}}, {{c1, s1, 1}, {0, 0, 1}, {u1, 1}},
            {{0, 0, -1}, {0, 0, -1}, {0.5f, 0.5f}}, {{c1, s1, -1}, {0, 0, -1}, {u1, 0}}, {{c0, s0, -1}, {0, 0, -1}, {u0, 0}},
        };
        memcpy(v + k, side, sizeof side);
        k += 6;
        memcpy(v + k, caps, sizeof caps);
        k += 6;
    }
    *out = v;
    return n;
}

/* World-space direction through window position (mx, my). */
v3 camera_ray(v3 eye, v3 at, float fovy, double mx, double my, int ww, int wh) {
    float nx = (float)(2.0 * mx / (ww ? ww : 1) - 1.0), ny = (float)(1.0 - 2.0 * my / (wh ? wh : 1));
    v3 f = v3norm(v3sub(at, eye));
    v3 s = v3norm(v3cross(f, V3(0, 1, 0)));
    v3 u = v3cross(s, f);
    float th = tanf(fovy * 0.5f), aspect = (float)ww / (float)(wh ? wh : 1);
    return v3norm(v3add(f, v3add(v3scale(s, nx * th * aspect), v3scale(u, ny * th))));
}

/* ---------------------------------------------------------------- post: bloom + tone mapping */

const char *const FULLSCREEN_VS =
    "void main(){\n"
    "  vec2 p = vec2(float((GFX_VERTEX_ID << 1) & 2), float(GFX_VERTEX_ID & 2));\n"
    "  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);\n"
    "}\n";

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
    "#define uInvRes uP0.xy\n#define uBloomStr uP0.z\n#define uFlip uP0.w\n#define uExposure uP1.x\n"
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
    "  vec3 c = (s + b * uBloomStr) * uExposure;\n"
    "  c = shoulder(max(c, 0.0));\n"
    "  float dither = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) / 255.0;\n"
    "  o = vec4(pow(c, vec3(1.0 / 2.2)) + dither, 1.0);\n"
    "}\n";

/* One texture full-target (aspect-fit): a face shader, or the offline frame
 * in the preview window. */
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

typedef struct { float p0[4], p1[4]; } PostUniforms;

#define BLOOM_LEVELS 6

static struct {
    int w, h;
    GfxTex *msaa, *depth, *res; /* msaa NULL: no multisampling, draw into res */
    GfxTex *bl[BLOOM_LEVELS + 1];
    int bl_w[BLOOM_LEVELS + 1], bl_h[BLOOM_LEVELS + 1];
    GfxProg *down, *up, *final, *view;
} P;

static GfxProg *post_program(const char *label, const char *fs, const char *t0, const char *t1) {
    GfxProgDesc d = {.label = label, .vs = {FULLSCREEN_VS}, .nvs = 1, .fs = {POST_UBO, fs}, .nfs = 2,
                     .tex = {t0, t1}, .ntex = t1 ? 2 : 1, .vtx = GFX_VTX_NONE};
    return gfx->program(&d);
}

static int post_init(void) {
    P.down = post_program("bloom-down", POST_DOWN_FS, "uSrc", NULL);
    P.up = post_program("bloom-up", POST_UP_FS, "uSrc", NULL);
    P.final = post_program("final", POST_FINAL_FS, "uScene", "uBloom");
    P.view = post_program("view", POST_VIEW_FS, "uTex", NULL);
    return P.down && P.up && P.final && P.view;
}

static void post_targets_free(void) {
    if (!P.w) return;
    gfx->wait_idle();
    gfx->tex_free(P.msaa);
    gfx->tex_free(P.depth);
    for (int k = 0; k <= BLOOM_LEVELS; k++) gfx->tex_free(P.bl[k]); /* bl[0] is res */
    P.msaa = P.depth = P.res = NULL;
    memset(P.bl, 0, sizeof P.bl);
    P.w = P.h = 0;
}

static void post_free(void) {
    post_targets_free();
    gfx->prog_free(P.down);
    gfx->prog_free(P.up);
    gfx->prog_free(P.final);
    gfx->prog_free(P.view);
}

GfxPass post_scene_pass(int w, int h, const float clear[4]) {
    if (w != P.w || h != P.h) {
        post_targets_free();
        P.w = w; P.h = h;
        int samples = gfx->max_samples() >= 4 ? 4 : gfx->max_samples();
        if (samples > 1) P.msaa = gfx->texture(GFX_RGBA16F, w, h, 1, 0, samples);
        P.depth = gfx->texture(GFX_DEPTH, w, h, 1, 0, samples);
        P.res = gfx->texture(GFX_RGBA16F, w, h, 1, 0, 1);
        P.bl[0] = P.res; P.bl_w[0] = w; P.bl_h[0] = h;
        for (int k = 1; k <= BLOOM_LEVELS; k++) {
            P.bl_w[k] = P.bl_w[k - 1] / 2 > 1 ? P.bl_w[k - 1] / 2 : 1;
            P.bl_h[k] = P.bl_h[k - 1] / 2 > 1 ? P.bl_h[k - 1] / 2 : 1;
            P.bl[k] = gfx->texture(GFX_RGBA16F, P.bl_w[k], P.bl_h[k], 1, 0, 1);
        }
    }
    GfxPass p = {.color = P.res, .msaa = P.msaa, .depth = P.depth, .clear = 1,
                 .clear_color = {clear[0], clear[1], clear[2], clear[3]}};
    return p;
}

void post_finish(GfxTex *dst, float bloom, float exposure) {
    PostUniforms pu;
    for (int k = 1; k <= BLOOM_LEVELS; k++) { /* downsample chain, then additive upsample */
        GfxPass pp = {.color = P.bl[k]};
        gfx->begin_pass(&pp);
        pu = (PostUniforms){{1.0f / (float)P.bl_w[k - 1], 1.0f / (float)P.bl_h[k - 1],
                             1.0f / (float)P.bl_w[k], 1.0f / (float)P.bl_h[k]},
                            {k == 1 ? 1.0f : 0.0f, 0, 0, 0}};
        GfxDraw bd = {.prog = P.down, .ubo = &pu, .ubo_size = sizeof pu, .tex = {P.bl[k - 1]},
                      .filter = {GFX_LINEAR}, .count = 3};
        gfx->draw(&bd);
        gfx->end_pass();
    }
    for (int k = BLOOM_LEVELS - 1; k >= 1; k--) {
        GfxPass pp = {.color = P.bl[k]};
        gfx->begin_pass(&pp);
        pu = (PostUniforms){{1.0f / (float)P.bl_w[k + 1], 1.0f / (float)P.bl_h[k + 1],
                             1.0f / (float)P.bl_w[k], 1.0f / (float)P.bl_h[k]},
                            {0, 0, 0, 0}};
        GfxDraw bd = {.prog = P.up, .ubo = &pu, .ubo_size = sizeof pu, .tex = {P.bl[k + 1]},
                      .filter = {GFX_LINEAR}, .count = 3, .blend = GFX_BLEND_ADD};
        gfx->draw(&bd);
        gfx->end_pass();
    }
    GfxPass fp = {.color = dst};
    gfx->begin_pass(&fp);
    int ow, oh;
    gfx->pass_size(&ow, &oh);
    pu = (PostUniforms){{1.0f / (float)ow, 1.0f / (float)oh, bloom, (!dst && gfx->flip_y()) ? 1.0f : 0.0f},
                        {exposure, 0, 0, 0}};
    GfxDraw fd = {.prog = P.final, .ubo = &pu, .ubo_size = sizeof pu, .tex = {P.res, P.bl[1]},
                  .filter = {GFX_LINEAR, GFX_LINEAR}, .count = 3};
    gfx->draw(&fd);
    gfx->end_pass();
}

void post_view(GfxTex *dst, GfxTex *tex, int tw, int th) {
    GfxPass pp = {.color = dst};
    gfx->begin_pass(&pp);
    int w, h;
    gfx->pass_size(&w, &h);
    float wa = (float)w / (float)h, fa = (float)tw / (float)th;
    PostUniforms u = {{1.0f / (float)w, 1.0f / (float)h, 0, (!dst && gfx->flip_y()) ? 1.0f : 0.0f},
                      {wa > fa ? wa / fa : 1.0f, wa > fa ? 1.0f : fa / wa, 0, 0}};
    GfxDraw d = {.prog = P.view, .ubo = &u, .ubo_size = sizeof u, .tex = {tex}, .filter = {GFX_LINEAR},
                 .count = 3};
    gfx->draw(&d);
    gfx->end_pass();
}

/* ---------------------------------------------------------------- scenes & menu */

static int g_vsync = 1, g_limit_index;
static double g_fps_limit;
static int g_limit_values[8] = {0, 30, 60, 90, 120, 144, 240};
static int g_nlimits = 7;
static char g_limit_names[8][32];
static const char *g_limit_ptrs[8];

static void init_limits(double cli_limit) {
    int v = (int)(cli_limit + 0.5);
    int found = -1;
    for (int i = 0; i < g_nlimits; i++)
        if (g_limit_values[i] == v) found = i;
    if (found < 0) { /* a --fps-limit that isn't in the list */
        g_limit_values[g_nlimits] = v;
        found = g_nlimits++;
    }
    g_limit_index = found;
    for (int i = 0; i < g_nlimits; i++) {
        if (g_limit_values[i]) snprintf(g_limit_names[i], sizeof g_limit_names[i], "%d fps", g_limit_values[i]);
        else snprintf(g_limit_names[i], sizeof g_limit_names[i], "Off");
        g_limit_ptrs[i] = g_limit_names[i];
    }
    g_fps_limit = g_limit_values[g_limit_index];
}

static int scene_enter(int i) {
    g_scene_index = i;
    g_scene = SCENES[i];
    if (!g_scene->enter()) {
        fprintf(stderr, "could not start the %s scene\n", g_scene->name);
        return 0;
    }
    g_title_dirty = 1;
    return 1;
}

static void scene_switch(int i) {
    if (i == g_scene_index) return;
    gfx->wait_idle();
    g_scene->leave();
    int prev = g_scene_index;
    if (!scene_enter(i) && !scene_enter(prev)) exit(1);
}

static void build_menu(float dt) {
    char sub[300];
    snprintf(sub, sizeof sub, "%s  ·  %.0f fps", app.api_label, app.fps);
    ui_begin(app.fb_w, app.fb_h, dt, "shader-cube", sub);
    ui_section("Scene");
    int s = g_scene_index;
    if (ui_choice("Scene", &s, SCENE_NAMES, NSCENES)) g_scene_next = s;
    g_scene->menu();
    ui_section("Display");
    if (ui_toggle("VSync", &g_vsync)) gfx->set_vsync(g_vsync);
    if (ui_choice("Frame limit", &g_limit_index, g_limit_ptrs, g_nlimits)) g_fps_limit = g_limit_values[g_limit_index];
    ui_toggle("Pause  (F2)", &app.paused);
    ui_section("Application");
    if (ui_button("Quit") && app.win) glfwSetWindowShouldClose(app.win, 1);
    ui_end();
}

static void update_title(void) {
    if (!app.win) return;
    char status[300] = "", t[600];
    g_scene->status(status, sizeof status);
    snprintf(t, sizeof t, "shader-cube — %s  [%s · %.0f fps]%s%s%s", g_scene->name, app.api_label, app.fps,
             status[0] ? "  —  " : "", status, ui_available() && !ui_is_open() ? "   (F1: menu)" : "");
    glfwSetWindowTitle(app.win, t);
}

/* ---------------------------------------------------------------- input */

static void fb_cursor(double *x, double *y) { /* window coordinates -> framebuffer pixels */
    int ww, wh, fw, fh;
    glfwGetWindowSize(app.win, &ww, &wh);
    glfwGetFramebufferSize(app.win, &fw, &fh);
    if (ww > 0 && wh > 0) { *x *= (double)fw / ww; *y *= (double)fh / wh; }
}

static void handle_key(int key, int action, int mods) {
    if (action == GLFW_PRESS && key == GLFW_KEY_F1) {
        ui_set_open(!ui_is_open());
        g_title_dirty = 1;
        return;
    }
    if (ui_is_open() && ui_on_key(key, action, mods)) return;
    if (action == GLFW_PRESS) {
        if (key == GLFW_KEY_ESCAPE) {
            if (app.win) glfwSetWindowShouldClose(app.win, 1);
            return;
        }
        if (key == GLFW_KEY_F2) { app.paused = !app.paused; return; }
    }
    if (g_scene->key) g_scene->key(key, action, mods);
}

static void on_key(GLFWwindow *w, int key, int sc, int action, int mods) {
    (void)w; (void)sc;
    handle_key(key, action, mods);
}

static void on_button(GLFWwindow *w, int button, int action, int mods) {
    (void)mods;
    if (ui_is_open() && ui_on_button(button, action)) return;
    double x, y;
    glfwGetCursorPos(w, &x, &y);
    if (g_scene->button) g_scene->button(button, action, x, y);
}

static void on_cursor(GLFWwindow *w, double x, double y) {
    (void)w;
    double fx = x, fy = y;
    fb_cursor(&fx, &fy);
    if (ui_is_open() && ui_on_cursor(fx, fy)) return;
    if (g_scene->cursor) g_scene->cursor(x, y);
}

static void on_scroll(GLFWwindow *w, double dx, double dy) {
    (void)w; (void)dx;
    if (ui_is_open() && ui_on_scroll(dy)) return;
    if (g_scene->scroll) g_scene->scroll(dy);
}

/* --inject "T:KEY,T:KEY,...": presses KEY at simulated time T (testing and
 * scripted recordings: works offline too). */
typedef struct { double t; int key; } Inject;
static Inject g_inject[64];
static int g_ninject, g_inject_next;

static int key_by_name(const char *s) {
    static const struct { const char *name; int key; } names[] = {
        {"UP", GLFW_KEY_UP}, {"DOWN", GLFW_KEY_DOWN}, {"LEFT", GLFW_KEY_LEFT}, {"RIGHT", GLFW_KEY_RIGHT},
        {"ENTER", GLFW_KEY_ENTER}, {"SPACE", GLFW_KEY_SPACE}, {"ESC", GLFW_KEY_ESCAPE}, {"TAB", GLFW_KEY_TAB},
        {"PGUP", GLFW_KEY_PAGE_UP}, {"PGDN", GLFW_KEY_PAGE_DOWN}, {"HOME", GLFW_KEY_HOME}, {"END", GLFW_KEY_END},
    };
    for (size_t i = 0; i < sizeof names / sizeof *names; i++)
        if (!strcmp(s, names[i].name)) return names[i].key;
    if (s[0] == 'F' && s[1] >= '1' && s[1] <= '9') return GLFW_KEY_F1 + atoi(s + 1) - 1;
    if (!s[1] && s[0] >= 'A' && s[0] <= 'Z') return GLFW_KEY_A + s[0] - 'A';
    if (!s[1] && s[0] >= '0' && s[0] <= '9') return GLFW_KEY_0 + s[0] - '0';
    return -1;
}

static void parse_inject(const char *spec) {
    char buf[1024];
    snprintf(buf, sizeof buf, "%s", spec);
    for (char *tok = strtok(buf, ","); tok && g_ninject < 64; tok = strtok(NULL, ",")) {
        char *colon = strchr(tok, ':');
        if (!colon) continue;
        *colon = 0;
        int key = key_by_name(colon + 1);
        if (key < 0) { fprintf(stderr, "--inject: unknown key %s\n", colon + 1); continue; }
        g_inject[g_ninject++] = (Inject){atof(tok), key};
    }
}

/* ---------------------------------------------------------------- main */

static void usage(const char *argv0) {
    printf("usage: %s [options]\n"
           "\n"
           "rendering:\n"
           "  --api gles|gl|vulkan   graphics API (default gles: OpenGL ES 3.1; gl: OpenGL 4.3 core)\n"
           "  --vsync on|off         sync to the display (default on)\n"
           "  --fps-limit N          cap the frame rate at N frames per second (0 = no cap)\n"
           "  --quit-after SECONDS   exit after this long and print the average frame rate\n"
           "  --size WxH             window size, or output size when rendering offline (default 1600x900)\n"
           "  --gfx-debug            OpenGL debug output / Vulkan validation layer\n"
           "  The GPU is chosen by the system: run under `prime-run` for the NVIDIA GPU.\n"
           "\n"
           "scenes:\n"
           "  --scene cube|galton    start in this scene (default cube); F1 switches\n"
           "  --physics auto|gpu|cpu|compute|off\n"
           "                         auto: PhysX on the GPU (CUDA) when rendering on NVIDIA, else on the CPU;\n"
           "                         compute: compute-shader physics (Galton board); --physx is the same\n"
           "  --debris N             cube: PhysX debris bodies (default 600)\n"
           "  --balls N  --rows N    Galton board: balls (default 1200) and rows of pegs (default 14)\n"
           "  --shaders DIR  --res N  --view FACE  --stop 1,3   cube: face shaders, their size, ...\n"
           "  --menu                 open the F1 menu at start\n"
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
           "  --inject T:KEY,...     press KEY at simulated time T (e.g. 1:F1,1.5:DOWN)\n"
           "\n"
           "  F1 settings menu   F2 pause   Esc quit; cube: click a face to drive its shader,\n"
           "  drag to orbit, F3 auto camera, F5 reload shaders, F6/F7 view faces, F8 blast the debris;\n"
           "  Galton board: drag to orbit, wheel to zoom, R refill, Space release\n",
           argv0);
}

static int parse_physics(const char *v) {
    if (!strcmp(v, "auto")) return PHYS_PREF_AUTO;
    if (!strcmp(v, "gpu")) return PHYS_PREF_GPU;
    if (!strcmp(v, "cpu")) return PHYS_PREF_CPU;
    if (!strcmp(v, "compute")) return PHYS_PREF_COMPUTE;
    if (!strcmp(v, "off")) return PHYS_PREF_OFF;
    return -1;
}

int main(int argc, char **argv) {
    plat_init();
    GfxConfig cfg = {.api = GFX_GLES, .vsync = 1};
    int size_w = 1600, size_h = 900, size_given = 0;
    double fps_limit = 0, quit_after = 0;
    const char *record_dir = NULL, *shot = NULL, *scene_id = "cube";
    double shot_time = 3.0, rate = 60.0, start = 0.0, duration = 10.0;
    int frames = -1, fmt = IMG_PNG, fmt_given = 0, preview = 0, open_menu = 0;
    app.physics = PHYS_PREF_AUTO;
    app.debris = 600;
    app.balls = 1200;
    app.rows = 14;
    app.face_res = 1024;
    app.view_face = -1;
    const char *shaders = NULL;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i], *v = i + 1 < argc ? argv[i + 1] : NULL;
#define ARG(name) (!strcmp(a, name) && v && (i++, 1))
        if (ARG("--shaders")) shaders = v;
        else if (ARG("--res")) app.face_res = atoi(v);
        else if (ARG("--view")) app.view_face = atoi(v);
        else if (ARG("--stop")) app.stop_list = v;
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
        else if (ARG("--physics") || ARG("--physx")) {
            if ((app.physics = parse_physics(v)) < 0) {
                fprintf(stderr, "unknown --physics %s (auto, gpu, cpu, compute, off)\n", v);
                return 2;
            }
        }
        else if (ARG("--debris")) app.debris = atoi(v);
        else if (ARG("--balls")) app.balls = atoi(v);
        else if (ARG("--rows")) app.rows = atoi(v);
        else if (ARG("--scene")) scene_id = v;
        else if (!strcmp(a, "--menu")) open_menu = 1;
        else if (ARG("--inject")) parse_inject(v);
        else { usage(argv[0]); return !strcmp(a, "--help") || !strcmp(a, "-h") ? 0 : 2; }
#undef ARG
    }
    if (rate <= 0) rate = 60;
    int scene_index = -1;
    for (int i = 0; i < NSCENES; i++)
        if (!strcmp(scene_id, SCENES[i]->id)) scene_index = i;
    if (scene_index < 0) { fprintf(stderr, "unknown --scene %s (cube, galton)\n", scene_id); return 2; }

    find_data_dir();
    static char shader_root[1100];
    if (shaders) snprintf(shader_root, sizeof shader_root, "%s", shaders);
    else snprintf(shader_root, sizeof shader_root, "%s/shaders", app.data_dir);
    app.shader_root = shader_root;

    /* Offline: fixed time step, frames rendered into out_tex and saved. */
    int offline = record_dir || shot;
    app.offline = offline;
    if (shot) {
        start = shot_time;
        frames = 1;
        if (!fmt_given) fmt = img_format_from_name(shot);
    } else if (frames < 0) {
        frames = (int)(duration * rate + 0.5);
    }
    if (offline && !size_given && record_dir) { size_w = 1920; size_h = 1080; }
    if (record_dir && !plat_mkdir_p(record_dir)) { perror(record_dir); return 1; }
    if (offline) cfg.vsync = 0;
    g_vsync = cfg.vsync;
    init_limits(fps_limit);

    gfx = cfg.api == GFX_VULKAN ? &gfx_vk_backend : &gfx_gl_backend;
    /* Vulkan can render offline without any window system. */
    int need_window = !offline || preview || cfg.api != GFX_VULKAN;
    GLFWwindow *win = NULL;
    if (need_window) {
        if (!glfwInit()) { fprintf(stderr, "glfwInit failed\n"); return 1; }
        int ww = size_w, wh = size_h;
        if (offline) { /* preview window: fit inside 1280x720 */
            float s = fminf(1.0f, fminf(1280.0f / (float)ww, 720.0f / (float)wh));
            ww = (int)((float)ww * s);
            wh = (int)((float)wh * s);
        }
        for (int attempt = 0; attempt < 2 && !win; attempt++) {
            if (attempt) {
                if (cfg.api != GFX_GLES) break;
                cfg.fallback = 1; /* no OpenGL ES 3.1: 3.0, without compute shaders */
                glfwDefaultWindowHints();
            }
            gfx->window_hints(&cfg);
            glfwWindowHint(GLFW_VISIBLE, offline && !preview ? GLFW_FALSE : GLFW_TRUE);
            win = glfwCreateWindow(ww, wh, "shader-cube", NULL, NULL);
        }
        if (!win) {
            fprintf(stderr, "could not create a %s window\n",
                    cfg.api == GFX_GLES ? "OpenGL ES 3.0" : cfg.api == GFX_GL ? "OpenGL 4.3" : "Vulkan");
            return 1;
        }
    }
    app.win = win;
    if (!gfx->init(&cfg, win)) return 1;
    snprintf(app.api_label, sizeof app.api_label, "%s · %s",
             cfg.api == GFX_GLES ? "OpenGL ES" : cfg.api == GFX_GL ? "OpenGL" : "Vulkan", gfx->device_name());
    if (win) {
        glfwSetKeyCallback(win, on_key);
        if (!offline) {
            glfwSetMouseButtonCallback(win, on_button);
            glfwSetCursorPosCallback(win, on_cursor);
            glfwSetScrollCallback(win, on_scroll);
        }
    }
    if (!post_init()) return 1;
    char fonts[1100];
    snprintf(fonts, sizeof fonts, "%s/assets/fonts", app.data_dir);
    ui_init(fonts);
    if (open_menu) ui_set_open(1);

    app.fb_w = size_w;
    app.fb_h = size_h;
    if (win && !offline) glfwGetFramebufferSize(win, &app.fb_w, &app.fb_h);
    if (!scene_enter(scene_index)) return 1;

    GfxTex *out_tex = offline ? gfx->texture(GFX_RGBA8, size_w, size_h, 1, 0, 1) : NULL;
    ImgWriter *writer = NULL;
    if (offline) {
        int ncpu = plat_cpu_count();
        writer = imgw_create(ncpu > 8 ? 6 : ncpu > 2 ? ncpu - 2 : 1, 12);
        if (record_dir)
            printf("recording %d frames of %dx%d at %g fps into %s/\n", frames, size_w, size_h, rate, record_dir);
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    double prev = plat_time(), fps = 60.0, deadline = prev, title_at = prev, progress_at = prev;
    double rec_t0 = prev, run_t0 = prev;
    long drawn = 0;
    int written = 0;

    for (;;) {
        if (g_quit || (win && glfwWindowShouldClose(win))) {
            if (offline) fprintf(stderr, "%s: stopping after %d frames\n", g_quit ? "interrupted" : "preview closed",
                                 written);
            break;
        }
        if (quit_after > 0 && plat_time() - run_t0 >= quit_after) break;
        if (!offline && g_fps_limit > 0) limit_frame_rate(&deadline, 1.0 / g_fps_limit);
        if (win) glfwPollEvents();
        double now = plat_time();
        float dt = (float)(now - prev);
        prev = now;
        if (dt > 0) fps = fps * 0.95 + 0.05 / dt;
        app.fps = (float)fps;
        if (dt > 0.1f) dt = 0.1f;
        if (offline) dt = (float)(1.0 / rate);

        while (g_inject_next < g_ninject && app.time >= g_inject[g_inject_next].t) {
            handle_key(g_inject[g_inject_next].key, GLFW_PRESS, 0);
            handle_key(g_inject[g_inject_next].key, GLFW_RELEASE, 0);
            g_inject_next++;
        }

        int sw = size_w, sh = size_h;
        if (!offline) {
            glfwGetFramebufferSize(win, &sw, &sh);
            if (sw <= 0 || sh <= 0) { glfwWaitEventsTimeout(0.1); continue; } /* minimised */
        }
        app.fb_w = sw;
        app.fb_h = sh;

        /* The menu first: its changes apply before this frame is built. */
        int menu = ui_is_open();
        if (menu) build_menu(offline ? (float)(1.0 / rate) : dt);
        if (g_scene_next >= 0) {
            scene_switch(g_scene_next);
            g_scene_next = -1;
        }
        if (!app.paused) {
            app.time += dt;
            g_scene->update(dt);
        }

        gfx->begin_frame();
        g_scene->render(out_tex, app.paused ? 0.0f : dt);
        if (menu || !offline) ui_draw(out_tex, sw, sh, offline ? (float)(1.0 / rate) : dt);

        int write = offline && app.time > start - 0.5 / rate; /* tolerate float drift */
        unsigned char *pixels = NULL;
        if (write) {
            pixels = malloc((size_t)size_w * (size_t)size_h * 4);
            gfx->readback(out_tex, pixels);
        }
        if (offline && preview) post_view(NULL, out_tex, size_w, size_h);
        gfx->end_frame();
        drawn++;

        if (write) {
            char *path = malloc(1100);
            if (shot) snprintf(path, 1100, "%s", shot);
            else snprintf(path, 1100, "%s/frame_%06d.%s", record_dir, written, fmt == IMG_PPM ? "ppm" : "png");
            imgw_push(writer, path, pixels, size_w, size_h, fmt);
            if (!written) rec_t0 = progress_at = plat_time();
            written++;
            if (shot) printf("wrote %s (t = %.2f s)\n", shot, app.time);
            else if (plat_time() - progress_at > 1.0 || written == frames) {
                progress_at = plat_time();
                printf("frame %d/%d  t = %.2f s  (%.1f frames/s)\n", written, frames, app.time,
                       written / fmax(progress_at - rec_t0, 1e-3));
                fflush(stdout);
            }
            if (written >= frames) break;
        }

        if (win && (now - title_at > 0.5 || g_title_dirty)) {
            title_at = now;
            g_title_dirty = 0;
            if (offline) {
                char t[320];
                snprintf(t, sizeof t, "shader-cube  [%s]  —  recording %d/%d", app.api_label, written, frames);
                glfwSetWindowTitle(win, t);
            } else {
                update_title();
            }
        }
    }

    double elapsed = plat_time() - run_t0;
    if (!offline && elapsed > 0)
        printf("%ld frames in %.1f s: %.1f fps average\n", drawn, elapsed, (double)drawn / elapsed);
    int failed = 0;
    if (writer) {
        failed = imgw_finish(writer);
        if (record_dir) printf("wrote %d frames to %s/\n", written - failed, record_dir);
    }
    gfx->wait_idle();
    g_scene->leave();
    ui_shutdown();
    post_free();
    gfx->tex_free(out_tex);
    gfx->shutdown();
    if (win) glfwDestroyWindow(win);
    if (need_window) glfwTerminate();
    return failed ? 1 : 0;
}
