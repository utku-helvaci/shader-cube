// SPDX-License-Identifier: MIT
/*
 * The Galton board.  Steel balls wait in a hopper; a gate opens and they run
 * down through rows of pegs, between two glass panes, into bins, where they
 * pile up into a binomial distribution: the normal curve drawn on the front
 * pane is where the piles should end up.
 *
 * The balls are simulated by PhysX (GPU or CPU) or by the compute-shader
 * engine in gpuphys.c, from the same description of the board (PhysShape).
 * Everything is drawn with this file's own shaders: a studio lit by
 * softboxes, which the steel, brass and glass reflect.
 */
#include "app.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gpuphys.h"
#include "physics.h"
#include "plat.h"
#include "ui.h"

/* ---------------------------------------------------------------- dimensions (metres) */

#define BALL_R 0.03f
#define BIN_W 0.15f                  /* bin width = horizontal peg spacing: 2.5 balls */
#define ROW_H (BIN_W * 0.866f)       /* vertical peg spacing */
#define PEG_R 0.022f                 /* pins: 1.8 balls between two of them */
#define ZHALF (BALL_R * 1.2f)        /* half the gap between the panes */
#define OUTLET_W (BALL_R * 14.0f)    /* 7 balls: a narrow stream that does not jam */
#define FUNNEL_SLOPE 0.8391f         /* tan(40 degrees) */
#define WALL_T 0.04f                 /* half thickness of the walls */
#define DIVIDER_T 0.010f
#define PACKING 0.78f                /* fraction of a bin's area the balls fill */
#define PIN_LOSSES 20.0f             /* compute engine: rolling losses on a pin, 1/s */
#define SPREAD 1.6f                  /* the piles come out this much wider than the binomial */

enum { MAT_WOOD, MAT_ALU, MAT_BRASS, MAT_GATE, MAT_FLOOR, MAT_RUBBER, MAT_BALL = 10 };
enum { ENGINE_PHYSX_GPU, ENGINE_PHYSX_CPU, ENGINE_COMPUTE };

typedef struct {
    int rows, bins, nballs;
    float hw, bins_h, y_last, y_top_peg, y_out, y_funnel, y_top;
    PhysShape *shapes;
    int nshapes, gate;
    float *ball_pos, *ball_key;
    float *boxes;   /* instances: frame, walls, dividers, funnel, gate (the gate last) */
    int nboxes;
    float *pegs;
    int npegs;
} Board;

static Board B;

/* settings (the menu) and their applied values */
static int g_engine, g_engine_want, g_rows_want = 14, g_balls_want = 1200;
static float g_gravity = 9.81f, g_restitution = 0.1f, g_friction = 2.0f, g_speed = 1.0f;
static int g_auto_release = 1, g_rainbow, g_curve = 1, g_orbit;
enum { CURVE_OFF, CURVE_FIT, CURVE_BINOMIAL };

/* The balls in the bins, measured a few times a second: the fitted curve. */
static int g_fit_n;
static float g_fit_mean, g_fit_sd;
static double g_measure_at;
static double g_rebuild_at;
static int g_rebuild_now, g_release_now, g_refill_now;
static double g_release_at;
static int g_gate_open;
static double g_open_time;

/* simulation */
static PhysBalls *g_px;
static GpuPhys *g_gp;
static float *g_inst;   /* PhysX: instance data read back each frame */
static float g_pending_dt;
static char g_info[256];

/* camera */
static double g_yaw = 0.32, g_pitch = -0.06, g_dist;
static int g_dragging, g_user_cam;
static double g_last_mx, g_last_my;
static v3 g_eye, g_at;
static const float FOVY = 0.78f;

/* rendering */
static struct {
    GfxProg *obj, *glass, *sky;
    GfxBuf *box_vb, *peg_vb, *ball_vb, *quad_vb;
    int npeg_v, nball_v;
} R;

/* ---------------------------------------------------------------- the board */

static void add_shape(int type, float x, float y, float angle, float hx, float hy, float hz, int glass) {
    PhysShape *s = &B.shapes[B.nshapes++];
    memset(s, 0, sizeof *s);
    s->type = type;
    s->pos[0] = x; s->pos[1] = y;
    s->angle = angle;
    s->half[0] = hx; s->half[1] = hy; s->half[2] = hz;
    s->glass = glass;
}

/* An instance in the GFX_INST_STRIDE layout: pos + material, rotation about z, half extents. */
static void put_instance(float *o, float x, float y, float z, int mat, float angle, float hx, float hy, float hz) {
    o[0] = x; o[1] = y; o[2] = z; o[3] = (float)mat;
    o[4] = 0; o[5] = 0; o[6] = sinf(angle * 0.5f); o[7] = cosf(angle * 0.5f);
    o[8] = hx; o[9] = hy; o[10] = hz; o[11] = 0;
}

static void board_free(void) {
    free(B.shapes);
    free(B.ball_pos);
    free(B.ball_key);
    free(B.boxes);
    free(B.pegs);
    memset(&B, 0, sizeof B);
}

/* Lowest point a ball may sit at height y inside the hopper: |x| <= limit. */
static float hopper_limit(float y) {
    float funnel = OUTLET_W * 0.5f + (y - B.y_out) / FUNNEL_SLOPE - BALL_R / 0.6428f - 0.006f;
    float wall = B.hw - BALL_R - 0.005f;
    return fminf(funnel, wall); /* also above the funnel: clear of the walls' ends */
}

/* Expected height of the tallest pile: a normal distribution SPREAD times
 * as wide as binomial(rows, 1/2), which is what the physics produces. */
static float peak_height(int rows, int nballs) {
    double sigma = SPREAD * 0.5 * sqrt((double)rows) * BIN_W;
    return (float)(nballs * BIN_W / (sigma * 2.5066283) * 3.14159265 * BALL_R * BALL_R / PACKING / BIN_W);
}

static void board_build(int rows, int nballs) {
    board_free();
    B.rows = rows;
    B.bins = rows + 1;
    B.hw = 0.5f * BIN_W * (float)B.bins;
    B.bins_h = fmaxf(1.2f, 1.12f * peak_height(rows, nballs) + 0.25f);
    B.y_last = B.bins_h + 0.15f;
    B.y_top_peg = B.y_last + (float)(rows - 1) * ROW_H;
    B.y_out = B.y_top_peg + 0.14f;
    B.y_funnel = B.y_out + (B.hw - OUTLET_W * 0.5f) * FUNNEL_SLOPE;
    float hw = B.hw;

    /* The balls, on a hexagonal lattice filling the hopper from the bottom;
     * the hopper is as tall as they need. */
    B.ball_pos = calloc((size_t)nballs * 3, sizeof(float));
    B.ball_key = calloc((size_t)nballs, sizeof(float));
    float a = 2.0f * BALL_R * 1.02f, dy = a * 0.866f, ylast = B.y_out;
    int n = 0;
    unsigned rng = 0x9E3779B9u;
    for (int row = 0; n < nballs && row < 100000; row++) {
        float y = B.y_out + BALL_R + 0.01f + (float)row * dy;
        float lim = hopper_limit(y), x0 = row % 2 ? a * 0.5f : 0.0f;
        int kmax = (int)((lim + x0) / a) + 1;
        for (int k = -kmax; k <= kmax && n < nballs; k++) {
            float x = x0 + (float)k * a;
            if (fabsf(x) > lim) continue;
            rng = rng * 1664525u + 1013904223u;
            B.ball_pos[n * 3] = x;
            B.ball_pos[n * 3 + 1] = y;
            B.ball_pos[n * 3 + 2] = ((float)(rng >> 8) / 16777216.0f - 0.5f) * 0.002f;
            n++;
            ylast = y;
        }
    }
    B.nballs = n;
    for (int i = 0; i < n; i++) B.ball_key[i] = MAT_BALL + 0.999f * (float)i / (float)(n > 1 ? n - 1 : 1);
    B.y_top = fmaxf(B.y_funnel + 0.25f, ylast + BALL_R + 0.12f);
    float ytop = B.y_top;

    B.shapes = calloc((size_t)(16 + B.bins + rows * (B.bins + 1)), sizeof *B.shapes);
    B.boxes = calloc((size_t)(16 + B.bins), GFX_INST_STRIDE);
    B.pegs = calloc((size_t)(rows * (B.bins + 1)), GFX_INST_STRIDE);
    float *bx = B.boxes;
#define BOX(...) (put_instance(bx + 12 * B.nboxes++, __VA_ARGS__))

    /* floor of the bins, side walls, lid */
    add_shape(PHYS_BOX, 0, -0.1f, 0, hw + 0.2f, 0.1f, ZHALF + 0.05f, 0);
    add_shape(PHYS_BOX, -hw - WALL_T, ytop * 0.5f, 0, WALL_T, ytop * 0.5f + 0.2f, ZHALF + 0.05f, 0);
    add_shape(PHYS_BOX, hw + WALL_T, ytop * 0.5f, 0, WALL_T, ytop * 0.5f + 0.2f, ZHALF + 0.05f, 0);
    add_shape(PHYS_BOX, 0, ytop + WALL_T, 0, hw + 0.2f, WALL_T, ZHALF + 0.05f, 0);
    /* the panes */
    add_shape(PHYS_BOX, 0, ytop * 0.5f, 0, hw + 0.2f, ytop * 0.5f + 0.2f, 0.01f, 1);
    B.shapes[B.nshapes - 1].pos[2] = ZHALF + 0.01f;
    add_shape(PHYS_BOX, 0, ytop * 0.5f, 0, hw + 0.2f, ytop * 0.5f + 0.2f, 0.01f, 1);
    B.shapes[B.nshapes - 1].pos[2] = -ZHALF - 0.01f;

    /* the frame (walnut) around all that, standing on a base */
    float post = 0.12f, depth = 0.13f;
    BOX(-hw - post, ytop * 0.5f - 0.05f, 0, MAT_WOOD, 0, post, ytop * 0.5f + 0.31f, depth);
    BOX(hw + post, ytop * 0.5f - 0.05f, 0, MAT_WOOD, 0, post, ytop * 0.5f + 0.31f, depth);
    BOX(0, ytop + 0.13f, 0, MAT_WOOD, 0, hw + 2 * post, 0.13f, depth);
    BOX(0, -0.3f, 0, MAT_WOOD, 0, hw + 2 * post + 0.1f, 0.3f, 0.36f);
    BOX(0, -0.01f, 0, MAT_RUBBER, 0, hw, 0.01f, ZHALF);

    /* dividers */
    for (int k = 1; k < B.bins; k++) {
        float x = -hw + (float)k * BIN_W;
        add_shape(PHYS_BOX, x, B.bins_h * 0.5f, 0, DIVIDER_T, B.bins_h * 0.5f, ZHALF, 0);
        BOX(x, B.bins_h * 0.5f, 0, MAT_ALU, 0, DIVIDER_T, B.bins_h * 0.5f, ZHALF);
    }
    /* pegs: the last row sits on the dividers, rows alternate by half a bin */
    for (int i = 0; i < rows; i++) {
        float y = B.y_top_peg - (float)i * ROW_H;
        int aligned = (rows - 1 - i) % 2 == 0;
        for (int k = aligned ? 1 : 0; k < B.bins; k++) {
            float x = -hw + ((float)k + (aligned ? 0.0f : 0.5f)) * BIN_W;
            add_shape(PHYS_CAPSULE_Z, x, y, 0, PEG_R, ZHALF + 0.02f, 0, 0);
            put_instance(B.pegs + 12 * B.npegs++, x, y, 0, MAT_BRASS, 0, PEG_R, PEG_R, ZHALF);
        }
    }
    /* the funnel: walls at 40 degrees from the outlet's edges up into the side
     * walls, their inner faces on the line (the box centres are moved out of
     * the funnel by the half thickness) */
    float run = hw - OUTLET_W * 0.5f, rise = run * FUNNEL_SLOPE, len = sqrtf(run * run + rise * rise);
    float ang = atan2f(rise, run), nx = -sinf(ang), ny = cosf(ang); /* right wall's normal into the funnel */
    float ext = 3.0f * WALL_T, half = (len + ext) * 0.5f;          /* past the top, into the side wall */
    for (int side = -1; side <= 1; side += 2) {
        float mx = OUTLET_W * 0.5f + (run + ext * cosf(ang)) * 0.5f, my = B.y_out + (rise + ext * sinf(ang)) * 0.5f;
        float cx = (float)side * (mx - nx * WALL_T), cy = my - ny * WALL_T;
        float ra = side > 0 ? ang : -ang;
        add_shape(PHYS_BOX, cx, cy, ra, half, WALL_T, ZHALF, 0);
        BOX(cx, cy, 0, MAT_ALU, ra, half, WALL_T, ZHALF);
    }
    /* the gate under the outlet, last among the boxes so it can be left out */
    B.gate = B.nshapes;
    add_shape(PHYS_BOX, 0, B.y_out - 0.03f, 0, OUTLET_W * 0.5f + 0.08f, 0.03f, ZHALF, 0);
    BOX(0, B.y_out - 0.03f, 0, MAT_GATE, 0, OUTLET_W * 0.5f + 0.08f, 0.03f, ZHALF);
#undef BOX
}

/* Where the balls in the bins are: count, mean and spread of x, for the
 * fitted curve.  The compute engine's balls are read back from the GPU
 * (outside the frame), a few times a second.  GALTON_STATS=1 also prints
 * the counts per bin every 2 s, against the binomial distribution. */
static void measure(void) {
    if (app.time < g_measure_at || !B.nballs || (!g_px && !g_gp)) return;
    g_measure_at = app.time + 0.25;
    float *inst = g_inst;
    if (g_gp) {
        inst = malloc((size_t)B.nballs * GFX_INST_STRIDE);
        gfx->buf_read(gpuphys_instances(g_gp), 0, inst, (size_t)B.nballs * GFX_INST_STRIDE);
    }
    int count[64] = {0}, n = 0, out = 0;
    double sx = 0, sxx = 0, sk = 0, skk = 0;
    for (int i = 0; i < B.nballs; i++) {
        float x = inst[i * 12], y = inst[i * 12 + 1], z = inst[i * 12 + 2];
        if (y < -0.1f || fabsf(x) > B.hw + 0.01f || fabsf(z) > ZHALF + 0.01f || y > B.y_top + 0.1f) {
            out++;
            continue;
        }
        if (y > B.bins_h) continue;
        int k = (int)floorf((x + B.hw) / BIN_W);
        k = k < 0 ? 0 : k >= B.bins ? B.bins - 1 : k;
        if (k < 64) count[k]++;
        n++;
        sx += x;
        sxx += (double)x * x;
        sk += k;
        skk += (double)k * k;
    }
    g_fit_n = n;
    g_fit_mean = n ? (float)(sx / n) : 0.0f;
    g_fit_sd = n ? (float)sqrt(fmax(sxx / n - (sx / n) * (sx / n), 0.0)) : 0.0f;
    static double print_at;
    if (getenv("GALTON_STATS") && app.time >= print_at) {
        print_at = app.time + 2.0;
        double mk = n ? sk / n : 0, sdk = n ? sqrt(fmax(skk / n - mk * mk, 0)) : 0;
        if (out) printf("t=%5.1f  %d balls outside the board\n", app.time, out);
        printf("t=%5.1f  in bins %4d/%d  mean %.2f (binomial %.2f)  sd %.2f (binomial %.2f)  |", app.time, n,
               B.nballs, mk, B.rows * 0.5, sdk, sqrt(B.rows) * 0.5);
        for (int k = 0; k < B.bins && k < 64; k++) printf(" %d", count[k]);
        printf("\n");
        fflush(stdout);
    }
    if (inst != g_inst) free(inst);
}

/* ---------------------------------------------------------------- physics */

static int engine_for_pref(int pref) {
    int have_physx = phys_available();
    if (pref == PHYS_PREF_COMPUTE) return ENGINE_COMPUTE;
    if (pref == PHYS_PREF_CPU && have_physx) return ENGINE_PHYSX_CPU;
    if (pref == PHYS_PREF_GPU && have_physx) return ENGINE_PHYSX_GPU;
    if (!have_physx) return ENGINE_COMPUTE;
    return gfx->is_nvidia() ? ENGINE_PHYSX_GPU : ENGINE_COMPUTE; /* auto */
}

static void physics_free(void) {
    if (g_px) phys_balls_destroy(g_px);
    if (g_gp) gpuphys_destroy(g_gp);
    g_px = NULL;
    g_gp = NULL;
    free(g_inst);
    g_inst = NULL;
}

static void physics_create(void) {
    gfx->wait_idle();
    physics_free();
    board_build(g_rows_want, g_balls_want);
    g_engine = g_engine_want;
    g_gate_open = 0;
    g_pending_dt = 0;
    g_fit_n = 0;
    g_measure_at = 0;
    g_release_at = g_auto_release ? app.time + 1.0 : -1.0;
    if (g_engine == ENGINE_COMPUTE) {
        GpuPhysDesc d = {.shapes = B.shapes, .nshapes = B.nshapes, .gate = B.gate, .ball_pos = B.ball_pos,
                         .ball_key = B.ball_key, .nballs = B.nballs, .radius = BALL_R, .gravity = g_gravity,
                         .restitution = g_restitution, .friction = g_friction,
                         .pin_damping = PIN_LOSSES, .zhalf = ZHALF,
                         .freeze_y = B.bins_h - 0.05f, .bounds = {-B.hw, 0.0f, B.hw, B.y_top}};
        g_gp = gpuphys_create(&d, g_info, sizeof g_info);
        if (!g_gp && phys_available()) { /* no compute shaders here: PhysX instead */
            printf("%s; using PhysX\n", g_info);
            g_engine = g_engine_want = gfx->is_nvidia() ? ENGINE_PHYSX_GPU : ENGINE_PHYSX_CPU;
        }
    }
    if (g_engine != ENGINE_COMPUTE) {
        PhysBallsDesc d = {.shapes = B.shapes, .nshapes = B.nshapes, .gate = B.gate, .ball_pos = B.ball_pos,
                           .ball_key = B.ball_key, .nballs = B.nballs, .radius = BALL_R, .gravity = g_gravity,
                           .restitution = g_restitution, .friction = g_friction,
                           .gpu = g_engine == ENGINE_PHYSX_GPU};
        g_px = phys_balls_create(&d, g_info, sizeof g_info);
        g_inst = calloc((size_t)(B.nballs ? B.nballs : 1), GFX_INST_STRIDE);
        if (g_px) phys_balls_read(g_px, g_inst);
    }
    printf("%s\n", g_info);
    fflush(stdout);
    app_set_title_dirty();
}

static void open_gate(void) {
    if (g_gate_open) return;
    g_gate_open = 1;
    g_open_time = app.time;
    g_release_at = -1;
    if (g_px) phys_balls_open_gate(g_px);
    if (g_gp) gpuphys_open_gate(g_gp);
}

/* ---------------------------------------------------------------- shaders */

static const char *GB_UBO =
    "GFX_UBO(0) st_Uniforms {\n"
    "  mat4 uViewProj; mat4 uInvViewProj;\n"
    "  vec4 uCam;\n"      /* xyz eye, w time */
    "  vec4 uLight;\n"    /* xyz key light direction, w intensity */
    "  vec4 uBoard;\n"    /* half width, top, pane half gap, bin height */
    "  vec4 uCurve;\n"    /* sigma, height at the mean, shown (0..1), mean */
    "  vec4 uMisc;\n"     /* ball style, target w, target h, ball radius */
    "};\n";

/* The studio: dark, with a large softbox above the camera and two strip
 * lights behind the board.  env() is what reflections see; `soft` widens
 * the lights for rough surfaces. */
static const char *GB_LIGHTING =
    "float rectLight(vec3 d, vec3 c, vec2 size, float soft){\n"
    "  float k = dot(d, c);\n"
    "  if (k <= 0.0) return 0.0;\n"
    "  vec3 t = normalize(cross(c, abs(c.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));\n"
    "  vec3 b = cross(c, t);\n"
    "  vec2 uv = vec2(dot(d, t), dot(d, b)) / k;\n"
    "  vec2 e = smoothstep(size + soft, size - soft * 0.5, abs(uv));\n"
    "  return e.x * e.y;\n"
    "}\n"
    "vec3 env(vec3 d, float rough){\n"
    "  float soft = 0.01 + rough * 0.9, dim = 1.0 / (1.0 + rough * 6.0);\n"
    "  vec3 c = mix(vec3(0.006, 0.006, 0.008), vec3(0.030, 0.032, 0.040), smoothstep(-0.3, 0.8, d.y));\n"
    "  c += vec3(0.020, 0.016, 0.012) * smoothstep(0.0, -0.4, d.y);\n"         /* floor bounce */
    "  c += rectLight(d, normalize(vec3(-0.30, 0.80, 0.52)), vec2(0.34, 0.20), soft) * vec3(5.0, 4.8, 4.5) * dim;\n"
    "  c += rectLight(d, normalize(vec3(0.92, 0.25, -0.30)), vec2(0.05, 0.55), soft) * vec3(1.6, 1.9, 2.6) * dim;\n"
    "  c += rectLight(d, normalize(vec3(-0.92, 0.30, -0.25)), vec2(0.05, 0.55), soft) * vec3(2.6, 1.9, 1.3) * dim;\n"
    "  c += rectLight(d, normalize(vec3(0.15, 0.10, 1.0)), vec2(0.9, 0.45), 0.35 + rough) * vec3(0.16, 0.17, 0.19);\n" /* fill */
    "  return c;\n"
    "}\n"
    "vec3 backdrop(vec3 d){ return env(d, 0.6) * 0.35; }\n"
    "vec3 shade(vec3 P, vec3 N, vec3 V, vec3 alb, float metal, float rough, float ao){\n"
    "  vec3 L = uLight.xyz, H = normalize(L + V);\n"
    "  float nl = max(dot(N, L), 0.0), nv = max(dot(N, V), 1e-3), nh = max(dot(N, H), 0.0), vh = max(dot(V, H), 0.0);\n"
    "  vec3 f0 = mix(vec3(0.04), alb, metal);\n"
    "  vec3 F = f0 + (1.0 - f0) * pow(1.0 - vh, 5.0);\n"
    "  float a = max(rough * rough, 0.002), a2 = a * a;\n"
    "  float dd = nh * nh * (a2 - 1.0) + 1.0, D = a2 / (3.14159 * dd * dd);\n"
    "  float k = a * 0.5, G = (nl / (nl * (1.0 - k) + k)) * (nv / (nv * (1.0 - k) + k));\n"
    "  vec3 spec = D * G * F / max(4.0 * nl * nv, 1e-4);\n"
    "  vec3 kd = (1.0 - F) * (1.0 - metal);\n"
    "  vec3 direct = (kd * alb / 3.14159 + spec) * nl * uLight.w * vec3(1.0, 0.96, 0.9);\n"
    "  vec3 Fa = f0 + (max(vec3(1.0 - rough), f0) - f0) * pow(1.0 - nv, 5.0);\n"
    "  vec3 amb = mix(vec3(0.010, 0.010, 0.012), vec3(0.045, 0.046, 0.050), N.y * 0.5 + 0.5)\n"
    "           + vec3(0.10, 0.096, 0.09) * max(dot(N, normalize(vec3(-0.30, 0.80, 0.52))), 0.0);\n"
    "  return direct + (alb * (1.0 - metal) * amb + env(reflect(-V, N), rough) * Fa) * ao;\n"
    "}\n"
    "vec3 hue(float h){ return clamp(abs(fract(h + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0); }\n"
    "float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }\n"
    "float vnoise(vec2 p){\n"
    "  vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);\n"
    "  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);\n"
    "}\n";

static const char *GB_OBJ_VS =
    "layout(location=0) in vec3 aPos; layout(location=1) in vec3 aNrm; layout(location=2) in vec2 aUV;\n"
    "layout(location=3) in vec4 iPosMat; layout(location=4) in vec4 iRot; layout(location=5) in vec4 iHalf;\n"
    "out vec3 vPos; out vec3 vNrm; out vec3 vLocal; flat out float vMat;\n"
    "vec3 qrot(vec4 q, vec3 v){ vec3 t = 2.0 * cross(q.xyz, v); return v + q.w * t + cross(q.xyz, t); }\n"
    "void main(){\n"
    "  vec3 wp = iPosMat.xyz + qrot(iRot, aPos * iHalf.xyz);\n"
    "  vPos = wp; vNrm = qrot(iRot, aNrm); vLocal = aPos * iHalf.xyz; vMat = iPosMat.w;\n"
    "  gl_Position = GFX_CLIP(uViewProj * vec4(wp, 1.0));\n"
    "}\n";

static const char *GB_OBJ_FS =
    "in vec3 vPos; in vec3 vNrm; in vec3 vLocal; flat in float vMat;\n"
    "layout(location=0) out vec4 oColor;\n"
    "void main(){\n"
    "  vec3 N = normalize(vNrm), V = normalize(uCam.xyz - vPos);\n"
    "  vec3 alb; float metal = 0.0, rough = 0.5, ao = 1.0;\n"
    "  if (vMat >= 9.5) {\n"                                     /* a ball */
    "    float key = vMat - 10.0;\n"
    "    ao = 0.55 + 0.45 * smoothstep(-0.9, 0.5, N.y);\n"         /* resting on others */
    "    if (uMisc.x > 0.5) { alb = hue(key * 0.85) * 0.75 + 0.03; rough = 0.25; }\n"
    "    else { alb = vec3(0.62, 0.63, 0.65); metal = 1.0; rough = 0.24; }\n"
    "  } else {\n"
    "    int m = int(vMat + 0.5);\n"
    "    if (m == 0) {\n"                                           /* walnut, grain along the longest side */
    "      vec3 h = abs(vLocal);\n"
    "      float along = h.y > h.x ? vPos.y : vPos.x, across = (h.y > h.x ? vPos.x : vPos.y) + vPos.z;\n"
    "      float w = across * 22.0 + vnoise(vec2(along * 0.9, across * 3.0)) * 4.0 + vnoise(vec2(along * 6.0, across * 40.0)) * 0.6;\n"
    "      float grain = smoothstep(0.15, 0.85, 0.5 + 0.5 * sin(w * 3.14159));\n"
    "      alb = mix(vec3(0.075, 0.036, 0.018), vec3(0.20, 0.105, 0.052), grain) * (0.85 + 0.3 * vnoise(vec2(along * 2.0, across * 2.0)));\n"
    "      rough = 0.38;\n"
    "    } else if (m == 1) { alb = vec3(0.85, 0.86, 0.88); metal = 1.0; rough = 0.32; }\n" /* aluminium */
    "    else if (m == 2) { alb = vec3(0.95, 0.74, 0.36); metal = 1.0; rough = 0.24; }\n"   /* brass */
    "    else if (m == 3) { alb = vec3(0.65, 0.06, 0.03); metal = 0.4; rough = 0.35; }\n"   /* the gate */
    "    else if (m == 4) {\n"                                      /* studio floor, fading into the backdrop */
    "      float r = length(vPos.xz * vec2(0.16, 0.22));\n"
    "      alb = vec3(0.06, 0.06, 0.065) * (0.4 + 0.6 * exp(-r * r));\n"
    "      rough = 0.7; ao = 0.55 + 0.45 * smoothstep(0.25, 1.4, length(vPos.xz * vec2(0.3, 1.6)));\n"
    "      vec3 col = shade(vPos, N, V, alb, metal, rough, ao);\n"
    "      float fog = smoothstep(5.0, 16.0, length(vPos.xz));\n"
    "      oColor = vec4(mix(col, backdrop(-V), fog), 1.0);\n"
    "      return;\n"
    "    } else { alb = vec3(0.025); rough = 0.8; }\n"
    "  }\n"
    "  oColor = vec4(shade(vPos, N, V, alb, metal, rough, ao), 1.0);\n"
    "}\n";

static const char *GB_SKY_FS =
    "layout(location=0) out vec4 oColor;\n"
    "void main(){\n"
    "  vec2 ndc = gl_FragCoord.xy / uMisc.yz * 2.0 - 1.0;\n"
    "  vec4 w = uInvViewProj * vec4(ndc, 1.0, 1.0);\n"
    "  vec3 d = normalize(w.xyz / w.w - uCam.xyz);\n"
    "  vec3 c = backdrop(d);\n"
    "  c *= 1.0 - 0.35 * dot(ndc, ndc);\n"                         /* vignette */
    "  oColor = vec4(c, 1.0);\n"
    "}\n";

static const char *GB_GLASS_VS =
    "layout(location=0) in vec3 aPos; layout(location=1) in vec3 aNrm; layout(location=2) in vec2 aUV;\n"
    "out vec3 vPos; out vec3 vNrm;\n"
    "void main(){ vPos = aPos; vNrm = aNrm; gl_Position = GFX_CLIP(uViewProj * vec4(aPos, 1.0)); }\n";

/* Thin glass: Fresnel reflection of the studio and a faint haze; on the
 * front pane, the expected heights of the piles as a glowing curve. */
static const char *GB_GLASS_FS =
    "in vec3 vPos; in vec3 vNrm;\n"
    "layout(location=0) out vec4 oColor;\n"
    "void main(){\n"
    "  vec3 V = normalize(uCam.xyz - vPos), N = normalize(vNrm);\n"
    "  if (dot(N, V) < 0.0) N = -N;\n"
    "  float F = 0.04 + 0.96 * pow(1.0 - dot(N, V), 5.0);\n"
    "  vec3 col = env(reflect(-V, N), 0.02) * F + vec3(0.010, 0.013, 0.014);\n"
    "  float a = F + 0.035;\n"
    "  if (uCurve.z > 0.0 && vPos.z > 0.0 && abs(vPos.x) < uBoard.x) {\n"
    "    float s = uCurve.x, x = vPos.x - uCurve.w, g = exp(-0.5 * x * x / (s * s));\n"
    "    float f = uCurve.y * g, fp = -f * x / (s * s);\n"
    "    float dist = abs(vPos.y - f) / sqrt(1.0 + fp * fp);\n"
    "    float px = max(length(vec2(dFdx(vPos.y), dFdy(vPos.y))), 1e-5);\n"
    "    float line = 1.0 - smoothstep(0.006, 0.006 + px * 1.5, dist);\n"
    "    float glow = exp(-dist / max(px * 6.0, 0.02)) * 0.25;\n"
    "    line *= smoothstep(uBoard.w + 0.3, uBoard.w - 0.2, vPos.y) * uCurve.z;\n"
    "    glow *= uCurve.z;\n"
    "    col += vec3(1.0, 0.52, 0.12) * (line * 3.0 + glow);\n"
    "    a = max(a, line * 0.6);\n"
    "  }\n"
    "  oColor = vec4(col, a);\n"
    "}\n";

typedef struct {
    float viewproj[16], inv_viewproj[16];
    float cam[4], light[4], board[4], curve[4], misc[4];
} GbUniforms;

static GfxProg *gb_program(const char *label, const char *vs, const char *fs, int vtx) {
    GfxProgDesc d = {.label = label, .vtx = vtx};
    d.vs[d.nvs++] = GB_UBO;
    d.vs[d.nvs++] = vs;
    d.fs[d.nfs++] = GB_UBO;
    d.fs[d.nfs++] = GB_LIGHTING;
    d.fs[d.nfs++] = fs;
    return gfx->program(&d);
}

static int make_gfx(void) {
    R.obj = gb_program("galton-objects", GB_OBJ_VS, GB_OBJ_FS, GFX_VTX_MESH_INST);
    R.glass = gb_program("galton-glass", GB_GLASS_VS, GB_GLASS_FS, GFX_VTX_MESH);
    R.sky = gb_program("galton-sky", FULLSCREEN_VS, GB_SKY_FS, GFX_VTX_NONE);
    if (!R.obj || !R.glass || !R.sky) return 0;
    Vtx box[36], *cyl, *sph;
    mesh_box(box, V3(1, 1, 1), 0);
    R.npeg_v = mesh_cylinder(&cyl, 20);
    R.nball_v = mesh_sphere(&sph, 16, 10);
    R.box_vb = gfx->buffer(box, sizeof box);
    R.peg_vb = gfx->buffer(cyl, sizeof(Vtx) * (size_t)R.npeg_v);
    R.ball_vb = gfx->buffer(sph, sizeof(Vtx) * (size_t)R.nball_v);
    free(cyl);
    free(sph);
    return 1;
}

static void free_gfx(void) {
    gfx->prog_free(R.obj);
    gfx->prog_free(R.glass);
    gfx->prog_free(R.sky);
    gfx->buf_free(R.box_vb);
    gfx->buf_free(R.peg_vb);
    gfx->buf_free(R.ball_vb);
    memset(&R, 0, sizeof R);
}

/* ---------------------------------------------------------------- camera */

static void frame_camera(void) {
    float h = B.y_top + 0.9f;
    g_at = V3(0, h * 0.5f - 0.35f, 0);
    if (g_dist <= 0) g_dist = (double)(h * 0.5f + 0.4f) / tan(FOVY * 0.5);
}

static void update_camera(double t) {
    double yaw = g_yaw, pitch = g_pitch;
    if (g_orbit && !g_user_cam) yaw += 0.35 * sin(t * 0.15);
    g_eye = V3(g_at.x + (float)(g_dist * cos(pitch) * sin(yaw)), g_at.y + (float)(g_dist * sin(-pitch)),
               g_at.z + (float)(g_dist * cos(pitch) * cos(yaw)));
}

/* ---------------------------------------------------------------- scene interface */

static int galton_enter(void) {
    if (!make_gfx()) return 0;
    g_rows_want = app.rows < 4 ? 4 : app.rows > 24 ? 24 : app.rows;
    g_balls_want = app.balls < 1 ? 1 : app.balls > 20000 ? 20000 : app.balls;
    g_engine_want = engine_for_pref(app.physics);
    g_dist = 0;
    g_user_cam = 0;
    g_rebuild_at = 0;
    physics_create();
    frame_camera();
    return 1;
}

static void galton_leave(void) {
    gfx->wait_idle();
    physics_free();
    board_free();
    free_gfx();
}

static void galton_update(float dt) {
    if (g_rebuild_now || (g_rebuild_at > 0 && plat_time() >= g_rebuild_at)) {
        int rows = B.rows;
        g_rebuild_now = 0;
        g_rebuild_at = 0;
        physics_create();
        if (rows != B.rows) {
            g_dist = 0;
            frame_camera();
        }
    }
    if (g_refill_now) {
        g_refill_now = 0;
        physics_create();
    }
    if (g_release_now || (g_release_at >= 0 && app.time >= g_release_at)) {
        g_release_now = 0;
        open_gate();
    }
    measure();
    float sdt = dt * g_speed;
    if (g_px) {
        /* 120 Hz: a PhysX step costs much the same at any length (on the GPU
         * mostly launches and copies), and speculative CCD keeps the fast
         * balls from tunnelling. */
        int steps = (int)ceilf(sdt / (1.0f / 120.0f) - 0.01f);
        if (steps > 4) steps = 4;
        if (steps < 1) steps = 1;
        for (int i = 0; i < steps; i++) phys_balls_step(g_px, sdt / (float)steps);
        phys_balls_read(g_px, g_inst);
    }
    g_pending_dt += sdt;
}

static void galton_render(GfxTex *dst, float dt) {
    (void)dt;
    if (g_gp && g_pending_dt > 0) { /* compute physics: recorded into this frame */
        int sub = (int)ceilf(g_pending_dt / (1.0f / 480.0f));
        if (sub > 16) sub = 16;
        gpuphys_step(g_gp, g_pending_dt, sub);
    }
    g_pending_dt = 0;
    update_camera(app.time);

    int w = app.fb_w, h = app.fb_h;
    static const float clear[4] = {0, 0, 0, 1};
    GfxPass pass = post_scene_pass(w, h, clear);
    gfx->begin_pass(&pass);

    m4 view = m4lookat(g_eye, g_at, V3(0, 1, 0));
    m4 proj = m4perspective(FOVY, (float)w / (float)(h ? h : 1), 0.05f, 200.0f);
    m4 vp = m4mul(proj, view);
    GbUniforms u;
    memset(&u, 0, sizeof u);
    memcpy(u.viewproj, vp.m, sizeof u.viewproj);
    /* inverse view-projection for the sky: inverse(proj * view) = view^-1 * proj^-1 */
    m4 iv = m4identity(), ip;
    for (int c = 0; c < 3; c++)
        for (int r = 0; r < 3; r++) iv.m[c * 4 + r] = view.m[r * 4 + c];
    iv.m[12] = g_eye.x; iv.m[13] = g_eye.y; iv.m[14] = g_eye.z;
    memset(&ip, 0, sizeof ip);
    ip.m[0] = 1.0f / proj.m[0];
    ip.m[5] = 1.0f / proj.m[5];
    ip.m[11] = 1.0f / proj.m[14];
    ip.m[14] = -1.0f;
    ip.m[15] = proj.m[10] / proj.m[14];
    m4 ivp = m4mul(iv, ip);
    memcpy(u.inv_viewproj, ivp.m, sizeof u.inv_viewproj);
    u.cam[0] = g_eye.x; u.cam[1] = g_eye.y; u.cam[2] = g_eye.z; u.cam[3] = (float)app.time;
    v3 L = v3norm(V3(-0.30f, 0.80f, 0.52f));
    u.light[0] = L.x; u.light[1] = L.y; u.light[2] = L.z; u.light[3] = 2.6f;
    u.board[0] = B.hw; u.board[1] = B.y_top; u.board[2] = ZHALF; u.board[3] = B.bins_h;
    /* the expected heights of the piles: a normal curve, fitted to the balls
     * in the bins or predicted for the board (binomial, all the balls) */
    float area = 3.14159265f * BALL_R * BALL_R / PACKING, sigma, count, mean, show = 0;
    if (g_curve == CURVE_FIT) {
        sigma = fmaxf(g_fit_sd, BIN_W * 0.25f);
        count = (float)g_fit_n;
        mean = g_fit_mean;
        show = fminf(1.0f, (float)g_fit_n / 40.0f);
    } else {
        sigma = BIN_W * sqrtf((float)B.rows) * 0.5f;
        count = (float)B.nballs;
        mean = 0;
        show = g_curve == CURVE_BINOMIAL ? 1.0f : 0.0f;
    }
    u.curve[0] = sigma;
    u.curve[1] = count * area / (sigma * 2.50662827f);
    u.curve[2] = show;
    u.curve[3] = mean;
    u.misc[0] = g_rainbow ? 1.0f : 0.0f;
    u.misc[1] = (float)w;
    u.misc[2] = (float)h;
    u.misc[3] = BALL_R;

    GfxDraw sky = {.prog = R.sky, .ubo = &u, .ubo_size = sizeof u, .count = 3};
    gfx->draw(&sky);

    /* the studio floor, the frame and the board's insides, the pegs, the balls */
    float floor_inst[12];
    put_instance(floor_inst, 0, -0.72f, 0, MAT_FLOOR, 0, 40.0f, 0.06f, 40.0f);
    GfxDraw d = {.prog = R.obj, .ubo = &u, .ubo_size = sizeof u, .vbuf = R.box_vb, .count = 36,
                 .depth = GFX_DEPTH_RW, .cull = 1};
    d.inst = floor_inst;
    d.ninst = 1;
    gfx->draw(&d);
    d.inst = B.boxes;
    d.ninst = B.nboxes - (g_gate_open ? 1 : 0);
    gfx->draw(&d);
    d.vbuf = R.peg_vb;
    d.count = R.npeg_v;
    d.inst = B.pegs;
    d.ninst = B.npegs;
    gfx->draw(&d);
    d.vbuf = R.ball_vb;
    d.count = R.nball_v;
    d.inst = g_gp ? NULL : g_inst;
    d.inst_buf = g_gp ? gpuphys_instances(g_gp) : NULL;
    d.ninst = (g_gp || g_px) ? B.nballs : 0;
    gfx->draw(&d);

    /* the panes, back to front */
    float x0 = -B.hw, x1 = B.hw, y0 = 0.0f, y1 = B.y_top;
    Vtx panes[12];
    for (int p = 0; p < 2; p++) {
        float z = (p == 0) == (g_eye.z > 0) ? -ZHALF : ZHALF;
        float nz = z > 0 ? 1.0f : -1.0f;
        float q[6][2] = {{x0, y0}, {x1, y0}, {x1, y1}, {x0, y0}, {x1, y1}, {x0, y1}};
        for (int k = 0; k < 6; k++) {
            Vtx *v = &panes[p * 6 + k];
            v->p[0] = q[k][0]; v->p[1] = q[k][1]; v->p[2] = z;
            v->n[0] = 0; v->n[1] = 0; v->n[2] = nz;
            v->uv[0] = v->uv[1] = 0;
        }
    }
    GfxDraw gd = {.prog = R.glass, .ubo = &u, .ubo_size = sizeof u, .vdata = panes, .count = 6,
                  .depth = GFX_DEPTH_TEST, .blend = GFX_BLEND_ALPHA};
    gfx->draw(&gd);
    gd.vdata = panes + 6;
    gfx->draw(&gd);
    gfx->end_pass();

    post_finish(dst, 0.12f, 1.0f);
}

static void galton_menu(void) {
    static const char *const engines[] = {"PhysX · GPU (CUDA)", "PhysX · CPU", "Compute shaders"};
    static const char *const looks[] = {"Steel", "Rainbow"};
    ui_section("Physics");
    if (ui_choice("Engine", &g_engine_want, engines, 3)) g_rebuild_at = plat_time();
    int tuned = 0;
    tuned |= ui_slider("Gravity", &g_gravity, 1.0f, 30.0f, 0.5f, "%.1f m/s²");
    tuned |= ui_slider("Bounciness", &g_restitution, 0.0f, 0.9f, 0.05f, "%.2f");
    tuned |= ui_slider("Pin friction", &g_friction, 0.0f, 4.0f, 0.1f, "%.1f");
    if (tuned) {
        phys_balls_tune(g_px, g_gravity, g_restitution, g_friction);
        gpuphys_tune(g_gp, g_gravity, g_restitution, g_friction);
    }
    ui_slider("Speed", &g_speed, 0.1f, 2.0f, 0.05f, "%.2f×");
    ui_text("Status", g_info);

    ui_section("Board");
    if (ui_islider("Balls", &g_balls_want, 100, 6000, 100)) g_rebuild_at = plat_time() + 0.5;
    if (ui_islider("Rows of pegs", &g_rows_want, 4, 24, 1)) g_rebuild_at = plat_time() + 0.5;
    if (ui_button(g_gate_open ? "Refill the hopper  (R)" : "Open the gate  (Space)")) {
        if (g_gate_open) g_refill_now = 1;
        else g_release_now = 1;
    }
    ui_toggle("Open the gate by itself", &g_auto_release);

    ui_section("Look");
    static const char *const curves[] = {"Off", "Fitted to the balls", "Binomial prediction"};
    ui_choice("Balls", &g_rainbow, looks, 2);
    ui_choice("Normal curve", &g_curve, curves, 3);
    ui_toggle("Slow camera sway", &g_orbit);
}

static void galton_status(char *buf, size_t n) {
    if (!g_gate_open) snprintf(buf, n, "%d balls in the hopper (Space: open the gate)", B.nballs);
    else snprintf(buf, n, "%d of %d balls in the bins, spread %.1f bins (binomial %.1f)  (R: refill)", g_fit_n,
                  B.nballs, g_fit_sd / BIN_W, sqrtf((float)B.rows) * 0.5f);
}

static int galton_key(int key, int action, int mods) {
    (void)mods;
    if (action != GLFW_PRESS) return 0;
    switch (key) {
    case GLFW_KEY_SPACE: g_release_now = 1; return 1;
    case GLFW_KEY_R: g_refill_now = 1; return 1;
    case GLFW_KEY_F3: g_user_cam = 0; g_yaw = 0.32; g_pitch = -0.06; g_dist = 0; frame_camera(); return 1;
    }
    return 0;
}

static void galton_button(int button, int action, double x, double y) {
    (void)button;
    if (action == GLFW_PRESS) {
        g_dragging = 1;
        g_user_cam = 1;
        g_last_mx = x;
        g_last_my = y;
    } else {
        g_dragging = 0;
    }
}

static void galton_cursor(double x, double y) {
    if (!g_dragging) return;
    g_yaw -= (x - g_last_mx) * 0.005;
    g_pitch -= (y - g_last_my) * 0.005;
    if (g_pitch > 1.2) g_pitch = 1.2;
    if (g_pitch < -0.7) g_pitch = -0.7;
    g_last_mx = x;
    g_last_my = y;
}

static void galton_scroll(double dy) {
    g_dist *= pow(0.9, dy);
    if (g_dist < 1.0) g_dist = 1.0;
    if (g_dist > 60.0) g_dist = 60.0;
}

const Scene scene_galton = {
    .id = "galton", .name = "Galton board",
    .enter = galton_enter, .leave = galton_leave, .update = galton_update, .render = galton_render,
    .menu = galton_menu, .status = galton_status,
    .key = galton_key, .button = galton_button, .cursor = galton_cursor, .scroll = galton_scroll,
};
