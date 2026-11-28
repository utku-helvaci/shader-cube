// SPDX-License-Identifier: MIT
/*
 * Compute-shader ball physics (see gpuphys.h).  Per substep:
 *
 *   integrate  v += g dt; predicted p = x + v dt          (balls -> A)
 *   clear      empty the grid
 *   insert     each ball into its grid cell (atomics)      (A -> grid)
 *   solve x2   Jacobi: push overlapping balls apart, push   (A -> B -> A)
 *              out of the statics, clamp between the panes
 *   finalize   v = (p - x) / dt, restitution and friction   (A -> balls,
 *              against the statics, freezing, rotation      instances)
 *
 * Every pass binds at most four storage buffers (the OpenGL ES 3.1 minimum).
 * The statics are looked up through a coarse grid built here on the CPU.
 */
#include "gpuphys.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "app.h"

#define SLOTS 6       /* balls per grid cell (cells are one ball diameter wide) */
#define GROUP 64

enum { B_BALLS, B_PA, B_PB, B_GRID, B_STATIC, B_INST }; /* GFX_SSBO(1 + index) */

struct GpuPhys {
    GfxProg *integrate, *clear, *insert, *solve, *finalize;
    GfxBuf *balls, *pa, *pb, *grid, *sdata, *inst;
    int n, nx, ny, ncells, snx, sny, sbase, gate;
    float radius, gravity, restitution, friction, pin_damping, zlimit, freeze_y;
    float gx0, gy0, ginv, sx0, sy0, sinv;
    int nshapes;
};

typedef struct {
    float sim[4];     /* dt, gravity, radius, n */
    float mat[4];     /* restitution, pin friction, z limit, freeze below y */
    float grid[4];    /* xmin, ymin, 1 / cell, cells */
    int32_t dims[4];  /* nx, ny, slots, solve parity */
    float sgrid[4];   /* static grid: xmin, ymin, 1 / cell, rolling losses on pins (1/s) */
    int32_t sdims[4]; /* static grid: nx, ny, offset of the shapes in sdata, - */
} CsUniforms;

static const char *CS_COMMON =
    "layout(local_size_x = 64) in;\n"
    "GFX_UBO(0) st_Uniforms {\n"
    "  vec4 uSim; vec4 uMat; vec4 uGrid; ivec4 uDims; vec4 uSgrid; ivec4 uSdims;\n"
    "};\n"
    "struct Ball { vec4 x; vec4 v; vec4 q; vec4 w; };\n" /* x: pos, colour key; v: vel, rest; q: rotation; w: spin */
    "int ballCount(){ return int(uSim.w); }\n"
    "ivec2 cellOf(vec2 p){ return clamp(ivec2(floor((p - uGrid.xy) * uGrid.z)), ivec2(0), uDims.xy - 1); }\n";

/* Closest-point push-out from the statics, through the static grid. */
static const char *CS_STATICS =
    "GFX_SSBO(5) StaticBuf { uint sdata[]; };\n"
    "float sf(int o){ return uintBitsToFloat(sdata[o]); }\n"
    /* penetration of a ball of radius r at p into static s (> 0), normal out of the shape */
    "float pushOut(int s, vec2 p, float r, out vec2 n){\n"
    "  int o = uSdims.z + 8 * s;\n"
    "  vec4 a = vec4(sf(o), sf(o + 1), sf(o + 2), sf(o + 3));\n"   /* centre, half size (radius) */
    "  vec4 b = vec4(sf(o + 4), sf(o + 5), sf(o + 6), sf(o + 7));\n" /* cos, sin, circle, enabled */
    "  n = vec2(0.0);\n"
    "  if (b.w < 0.5) return 0.0;\n"
    "  vec2 d = p - a.xy;\n"
    "  if (b.z > 0.5) {\n"
    "    float l = length(d);\n"
    "    if (l >= a.z + r || l < 1e-9) return 0.0;\n"
    "    n = d / l; return a.z + r - l;\n"
    "  }\n"
    "  vec2 l = vec2(b.x * d.x + b.y * d.y, -b.y * d.x + b.x * d.y);\n"
    "  vec2 q = clamp(l, -a.zw, a.zw), e = l - q, nl;\n"
    "  float dist = length(e), pen;\n"
    "  if (dist > 1e-7) {\n"
    "    if (dist >= r) return 0.0;\n"
    "    nl = e / dist; pen = r - dist;\n"
    "  } else {\n"                                                  /* centre inside: shallowest side */
    "    vec2 m = a.zw - abs(l);\n"
    "    if (m.x < m.y) { nl = vec2(l.x >= 0.0 ? 1.0 : -1.0, 0.0); pen = m.x + r; }\n"
    "    else { nl = vec2(0.0, l.y >= 0.0 ? 1.0 : -1.0); pen = m.y + r; }\n"
    "  }\n"
    "  n = vec2(b.x * nl.x - b.y * nl.y, b.y * nl.x + b.x * nl.y);\n"
    "  return pen;\n"
    "}\n"
    "bool isPin(int s){ return sf(uSdims.z + 8 * s + 6) > 0.5; }\n"
    "ivec2 staticRange(vec2 p){\n"
    "  ivec2 c = clamp(ivec2(floor((p - uSgrid.xy) * uSgrid.z)), ivec2(0), uSdims.xy - 1);\n"
    "  int cell = c.y * uSdims.x + c.x;\n"
    "  return ivec2(int(sdata[cell]), int(sdata[cell + 1]));\n"
    "}\n"
    "int staticAt(int k){ return int(sdata[uSdims.x * uSdims.y + 1 + k]); }\n";

static const char *CS_INTEGRATE =
    "GFX_SSBO(1) BallBuf { Ball balls[]; };\n"
    "GFX_SSBO(2) PredA { vec4 pa[]; };\n"
    "void main(){\n"
    "  int i = int(gl_GlobalInvocationID.x);\n"
    "  if (i >= ballCount()) return;\n"
    "  Ball b = balls[i];\n"
    "  if (b.v.w >= 1.0) { pa[i] = vec4(b.x.xyz, 0.0); return; }\n" /* frozen: w = 0 (immovable) */
    "  vec3 v = b.v.xyz;\n"
    "  v.y -= uSim.y * uSim.x;\n"
    "  balls[i].v.xyz = v;\n"                                       /* kept for restitution */
    "  pa[i] = vec4(b.x.xyz + v * uSim.x, 1.0);\n"
    "}\n";

static const char *CS_CLEAR =
    "GFX_SSBO(4) GridBuf { uint grid[]; };\n"
    "void main(){\n"
    "  int c = int(gl_GlobalInvocationID.x);\n"
    "  if (c < int(uGrid.w)) grid[c] = 0u;\n"
    "}\n";

static const char *CS_INSERT =
    "GFX_SSBO(2) PredA { vec4 pa[]; };\n"
    "GFX_SSBO(4) GridBuf { uint grid[]; };\n"
    "void main(){\n"
    "  int i = int(gl_GlobalInvocationID.x);\n"
    "  if (i >= ballCount()) return;\n"
    "  ivec2 c = cellOf(pa[i].xy);\n"
    "  int ci = c.y * uDims.x + c.x;\n"
    "  uint k = atomicAdd(grid[ci], 1u);\n"
    "  if (int(k) < uDims.z) grid[int(uGrid.w) + ci * uDims.z + int(k)] = uint(i);\n"
    "}\n";

static const char *CS_SOLVE =
    "GFX_SSBO(2) PredA { vec4 pa[]; };\n"
    "GFX_SSBO(3) PredB { vec4 pb[]; };\n"
    "GFX_SSBO(4) GridBuf { uint grid[]; };\n"
    "vec4 rd(int i){ return uDims.w == 0 ? pa[i] : pb[i]; }\n"
    "void main(){\n"
    "  int i = int(gl_GlobalInvocationID.x);\n"
    "  if (i >= ballCount()) return;\n"
    "  vec4 me = rd(i);\n"
    "  vec3 p = me.xyz;\n"
    "  if (me.w > 0.0) {\n"
    "    float r = uSim.z, d2 = 4.0 * r * r;\n"
    "    vec3 corr = vec3(0.0); float cnt = 0.0;\n"
    "    ivec2 c = cellOf(p.xy);\n"
    "    for (int y = max(c.y - 1, 0); y <= min(c.y + 1, uDims.y - 1); y++)\n"
    "    for (int x = max(c.x - 1, 0); x <= min(c.x + 1, uDims.x - 1); x++) {\n"
    "      int ci = y * uDims.x + x;\n"
    "      int m = min(int(grid[ci]), uDims.z);\n"
    "      for (int k = 0; k < m; k++) {\n"
    "        int j = int(grid[int(uGrid.w) + ci * uDims.z + k]);\n"
    "        if (j == i) continue;\n"
    "        vec4 q = rd(j);\n"
    "        vec3 d = p - q.xyz;\n"
    "        float l2 = dot(d, d);\n"
    "        if (l2 >= d2 || l2 < 1e-12) continue;\n"
    "        float l = sqrt(l2);\n"
    "        corr += d / l * (2.0 * r - l) * (q.w > 0.0 ? 0.5 : 1.0);\n" /* a frozen ball doesn't give way */
    "        cnt += 1.0;\n"
    "      }\n"
    "    }\n"
    "    if (cnt > 0.0) p += corr * (1.2 / cnt);\n"
    "    ivec2 range = staticRange(me.xy);\n"
    "    for (int pass = 0; pass < 2; pass++)\n"
    "      for (int k = range.x; k < range.y; k++) {\n"
    "        vec2 n; float pen = pushOut(staticAt(k), p.xy, r, n);\n"
    "        if (pen > 0.0) p.xy += n * pen;\n"
    "      }\n"
    "    p.z = clamp(p.z, -uMat.z, uMat.z);\n"
    "  }\n"
    "  if (uDims.w == 0) pb[i] = vec4(p, me.w); else pa[i] = vec4(p, me.w);\n"
    "}\n";

static const char *CS_FINALIZE =
    "GFX_SSBO(1) BallBuf { Ball balls[]; };\n"
    "GFX_SSBO(2) PredA { vec4 pa[]; };\n"
    "GFX_SSBO(6) InstBuf { vec4 inst[]; };\n"
    "vec4 qmul(vec4 a, vec4 b){ return vec4(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz), a.w * b.w - dot(a.xyz, b.xyz)); }\n"
    "void main(){\n"
    "  int i = int(gl_GlobalInvocationID.x);\n"
    "  if (i >= ballCount()) return;\n"
    "  Ball b = balls[i];\n"
    "  if (b.v.w >= 1.0) return;\n"                                 /* frozen: nothing changes */
    "  float dt = uSim.x, r = uSim.z;\n"
    "  vec3 p = pa[i].xyz, vOld = b.v.xyz;\n"
    "  vec3 v = (p - b.x.xyz) / dt;\n"
    "  vec3 rollN = vec3(0.0);\n"
    "  vec2 pinN = vec2(0.0);\n"
    "  ivec2 range = staticRange(p.xy);\n"
    "  for (int k = range.x; k < range.y; k++) {\n"                /* bounce and friction off the statics */
    "    int s = staticAt(k);\n"
    "    vec2 n; float pen = pushOut(s, p.xy, r * 1.05, n);\n"
    "    if (pen <= 0.0) continue;\n"
    "    bool pin = isPin(s);\n"
    "    if (pin) pinN = n;\n"
    "    rollN = vec3(n, 0.0);\n"
    "    float vnOld = dot(vOld.xy, n);\n"
    "    if (vnOld >= 0.0) continue;\n"
    "    float target = vnOld < -0.3 ? -uMat.x * vnOld : 0.0;\n"  /* slow contacts don't bounce */
    "    v.xy += n * (target - dot(v.xy, n));\n"
    "    vec2 t = v.xy - n * dot(v.xy, n);\n"
    "    float tl = length(t), mu = pin ? uMat.y : 0.1;\n"         /* the walls are slippery */
    "    if (tl > 1e-6) v.xy -= t / tl * min(tl, mu * (target - vnOld));\n" /* Coulomb */
    "  }\n"
    "  if (pinN != vec2(0.0)) {\n"                                 /* rolling losses on a pin */
    "    vec2 t = v.xy - pinN * dot(v.xy, pinN);\n"
    "    v.xy -= t * min(1.0, uSgrid.w * dt);\n"
    "  }\n"
    "  if (abs(p.z) >= uMat.z - 1e-5) {\n"                         /* against a pane */
    "    v.z = 0.0;\n"
    "    if (rollN == vec3(0.0)) rollN = vec3(0.0, 0.0, p.z > 0.0 ? -1.0 : 1.0);\n"
    "  }\n"
    "  float rest = b.v.w;\n"                                       /* settled in a bin: freeze */
    "  if (p.y < uMat.w && dot(v, v) < 0.0025) rest += dt / 0.4; else rest = 0.0;\n"
    "  if (rest >= 1.0) { v = vec3(0.0); rest = 1.0; }\n"
    "  vec3 w = rollN != vec3(0.0) ? cross(rollN, v) / r : b.w.xyz;\n" /* rolling */
    "  vec4 q = b.q;\n"
    "  float wl = length(w);\n"
    "  if (wl > 1e-5) {\n"
    "    float h = 0.5 * wl * dt;\n"
    "    q = normalize(qmul(vec4(w / wl * sin(h), cos(h)), q));\n"
    "  }\n"
    "  balls[i].x = vec4(p, b.x.w);\n"
    "  balls[i].v = vec4(v, rest);\n"
    "  balls[i].q = q;\n"
    "  balls[i].w = vec4(w, 0.0);\n"
    "  inst[i * 3] = vec4(p, b.x.w);\n"
    "  inst[i * 3 + 1] = q;\n"
    "  inst[i * 3 + 2] = vec4(r, r, r, 0.0);\n"
    "}\n";

static GfxProg *cs(const char *label, const char *body, int statics) {
    const char *src[3] = {CS_COMMON, statics ? CS_STATICS : "", body};
    return gfx->compute(label, src, 3);
}

/* Bounding box of a static shape in the xy plane. */
static void shape_bounds(const PhysShape *s, float b[4]) {
    float ex, ey;
    if (s->type == PHYS_CAPSULE_Z) {
        ex = ey = s->half[0];
    } else {
        float c = fabsf(cosf(s->angle)), sn = fabsf(sinf(s->angle));
        ex = c * s->half[0] + sn * s->half[1];
        ey = sn * s->half[0] + c * s->half[1];
    }
    b[0] = s->pos[0] - ex; b[1] = s->pos[1] - ey;
    b[2] = s->pos[0] + ex; b[3] = s->pos[1] + ey;
}

static uint32_t fbits(float f) {
    uint32_t u;
    memcpy(&u, &f, 4);
    return u;
}

/* The static-grid cells shape s (grown by margin) touches. */
static int shape_cells(const GpuPhys *g, const PhysShape *s, float margin, int *cells, int max) {
    float b[4];
    shape_bounds(s, b);
    int x0 = (int)floorf((b[0] - margin - g->sx0) * g->sinv), x1 = (int)floorf((b[2] + margin - g->sx0) * g->sinv);
    int y0 = (int)floorf((b[1] - margin - g->sy0) * g->sinv), y1 = (int)floorf((b[3] + margin - g->sy0) * g->sinv);
    int n = 0;
    for (int y = y0 < 0 ? 0 : y0; y <= y1 && y < g->sny; y++)
        for (int x = x0 < 0 ? 0 : x0; x <= x1 && x < g->snx; x++)
            if (n < max) cells[n++] = y * g->snx + x;
    return n;
}

/* sdata: static grid cell starts [ncells + 1], shape indices, then 8 floats
 * per shape (centre, half size / radius, cos, sin, circle, enabled). */
static uint32_t *build_statics(GpuPhys *g, const GpuPhysDesc *d, size_t *len) {
    float cell = 0.25f, margin = d->radius * 1.5f;
    g->sx0 = d->bounds[0] - 1.0f;
    g->sy0 = d->bounds[1] - 1.0f;
    g->sinv = 1.0f / cell;
    g->snx = (int)ceilf((d->bounds[2] - d->bounds[0] + 2.0f) / cell) + 1;
    g->sny = (int)ceilf((d->bounds[3] - d->bounds[1] + 2.0f) / cell) + 1;
    int ncell = g->snx * g->sny, maxc = ncell;
    int *start = calloc((size_t)ncell + 1, sizeof *start), *cells = malloc(sizeof *cells * (size_t)maxc);
    for (int s = 0; s < d->nshapes; s++) { /* count per cell */
        if (d->shapes[s].glass) continue;
        int n = shape_cells(g, &d->shapes[s], margin, cells, maxc);
        for (int k = 0; k < n; k++) start[cells[k]]++;
    }
    int total = 0;
    for (int c = 0; c < ncell; c++) { /* counts -> starts */
        int k = start[c];
        start[c] = total;
        total += k;
    }
    start[ncell] = total;
    g->sbase = ncell + 1 + total;
    *len = (size_t)g->sbase + 8 * (size_t)d->nshapes;
    uint32_t *out = calloc(*len, sizeof *out);
    int *fill = calloc((size_t)ncell, sizeof *fill);
    for (int s = 0; s < d->nshapes; s++) { /* fill */
        if (d->shapes[s].glass) continue;
        int n = shape_cells(g, &d->shapes[s], margin, cells, maxc);
        for (int k = 0; k < n; k++) out[ncell + 1 + start[cells[k]] + fill[cells[k]]++] = (uint32_t)s;
    }
    for (int c = 0; c <= ncell; c++) out[c] = (uint32_t)start[c];
    for (int s = 0; s < d->nshapes; s++) {
        const PhysShape *sh = &d->shapes[s];
        float f[8] = {sh->pos[0], sh->pos[1], sh->half[0], sh->half[1], cosf(sh->angle), sinf(sh->angle),
                      sh->type == PHYS_CAPSULE_Z ? 1.0f : 0.0f, sh->glass ? 0.0f : 1.0f};
        for (int k = 0; k < 8; k++) out[g->sbase + 8 * s + k] = fbits(f[k]);
    }
    free(start);
    free(cells);
    free(fill);
    return out;
}

GpuPhys *gpuphys_create(const GpuPhysDesc *d, char *info, int infolen) {
    if (!gfx->has_compute()) {
        snprintf(info, (size_t)infolen, "compute shaders need OpenGL 4.3, OpenGL ES 3.1 or Vulkan");
        return NULL;
    }
    GpuPhys *g = calloc(1, sizeof *g);
    g->n = d->nballs;
    g->radius = d->radius;
    g->gravity = d->gravity;
    g->restitution = d->restitution;
    g->friction = d->friction;
    g->pin_damping = d->pin_damping;
    g->zlimit = fmaxf(d->zhalf - d->radius, 0.0f);
    g->freeze_y = d->freeze_y;
    g->gate = d->gate;
    g->nshapes = d->nshapes;

    g->integrate = cs("phys-integrate", CS_INTEGRATE, 0);
    g->clear = cs("phys-clear", CS_CLEAR, 0);
    g->insert = cs("phys-insert", CS_INSERT, 0);
    g->solve = cs("phys-solve", CS_SOLVE, 1);
    g->finalize = cs("phys-finalize", CS_FINALIZE, 1);
    if (!g->integrate || !g->clear || !g->insert || !g->solve || !g->finalize) {
        snprintf(info, (size_t)infolen, "compute shaders failed to compile");
        gpuphys_destroy(g);
        return NULL;
    }

    float cell = 2.0f * d->radius, margin = 4.0f * d->radius;
    g->gx0 = d->bounds[0] - margin;
    g->gy0 = d->bounds[1] - margin;
    g->ginv = 1.0f / cell;
    g->nx = (int)ceilf((d->bounds[2] - d->bounds[0] + 2 * margin) / cell);
    g->ny = (int)ceilf((d->bounds[3] - d->bounds[1] + 2 * margin) / cell);
    g->ncells = g->nx * g->ny;

    size_t n = (size_t)(g->n ? g->n : 1);
    float *balls = calloc(n * 16, sizeof(float));
    float *inst = calloc(n * 12, sizeof(float));
    for (int i = 0; i < g->n; i++) {
        float *b = balls + i * 16, *o = inst + i * 12;
        for (int k = 0; k < 3; k++) b[k] = o[k] = d->ball_pos[i * 3 + k];
        b[3] = o[3] = d->ball_key ? d->ball_key[i] : 0.0f;
        b[11] = o[7] = 1.0f; /* identity rotation (xyzw) */
        o[8] = o[9] = o[10] = d->radius;
    }
    size_t slen = 0;
    uint32_t *sdata = build_statics(g, d, &slen);
    g->balls = gfx->storage(balls, n * 64);
    g->pa = gfx->storage(NULL, n * 16);
    g->pb = gfx->storage(NULL, n * 16);
    g->grid = gfx->storage(NULL, sizeof(uint32_t) * (size_t)g->ncells * (1 + SLOTS));
    g->sdata = gfx->storage(sdata, slen * sizeof *sdata);
    g->inst = gfx->storage(inst, n * GFX_INST_STRIDE);
    free(balls);
    free(inst);
    free(sdata);
    snprintf(info, (size_t)infolen, "compute shaders: %d balls on the GPU (%dx%d grid)", g->n, g->nx, g->ny);
    return g;
}

void gpuphys_open_gate(GpuPhys *g) {
    if (!g || g->gate < 0 || g->gate >= g->nshapes) return;
    uint32_t off = fbits(0.0f); /* "enabled" */
    gfx->buf_write(g->sdata, sizeof(uint32_t) * ((size_t)g->sbase + 8 * (size_t)g->gate + 7), &off, sizeof off);
    g->gate = -1;
}

void gpuphys_tune(GpuPhys *g, float gravity, float restitution, float friction) {
    if (!g) return;
    g->gravity = gravity;
    g->restitution = restitution;
    g->friction = friction;
}

static void run(GpuPhys *g, GfxProg *p, const CsUniforms *u, int items, int a, int b, int c, int d) {
    GfxDispatch dc = {.prog = p, .ubo = u, .ubo_size = sizeof *u, .groups = {(items + GROUP - 1) / GROUP, 1, 1}};
    GfxBuf *all[6] = {g->balls, g->pa, g->pb, g->grid, g->sdata, g->inst};
    int use[4] = {a, b, c, d};
    for (int k = 0; k < 4; k++)
        if (use[k] >= 0) dc.buf[use[k]] = all[use[k]];
    gfx->dispatch(&dc);
}

void gpuphys_step(GpuPhys *g, float dt, int substeps) {
    if (!g || dt <= 0 || substeps < 1) return;
    CsUniforms u = {
        .sim = {dt / (float)substeps, g->gravity, g->radius, (float)g->n},
        .mat = {g->restitution, g->friction, g->zlimit, g->freeze_y},
        .grid = {g->gx0, g->gy0, g->ginv, (float)g->ncells},
        .dims = {g->nx, g->ny, SLOTS, 0},
        .sgrid = {g->sx0, g->sy0, g->sinv, g->pin_damping},
        .sdims = {g->snx, g->sny, g->sbase, 0},
    };
    for (int s = 0; s < substeps; s++) {
        run(g, g->integrate, &u, g->n, B_BALLS, B_PA, -1, -1);
        run(g, g->clear, &u, g->ncells, B_GRID, -1, -1, -1);
        run(g, g->insert, &u, g->n, B_PA, B_GRID, -1, -1);
        for (int it = 0; it < 2; it++) {
            u.dims[3] = it; /* A -> B, then B -> A */
            run(g, g->solve, &u, g->n, B_PA, B_PB, B_GRID, B_STATIC);
        }
        u.dims[3] = 0;
        run(g, g->finalize, &u, g->n, B_BALLS, B_PA, B_STATIC, B_INST);
    }
}

GfxBuf *gpuphys_instances(GpuPhys *g) { return g ? g->inst : NULL; }

void gpuphys_destroy(GpuPhys *g) {
    if (!g) return;
    gfx->wait_idle();
    GfxProg *progs[] = {g->integrate, g->clear, g->insert, g->solve, g->finalize};
    for (int i = 0; i < 5; i++) gfx->prog_free(progs[i]);
    GfxBuf *bufs[] = {g->balls, g->pa, g->pb, g->grid, g->sdata, g->inst};
    for (int i = 0; i < 6; i++) gfx->buf_free(bufs[i]);
    free(g);
}
