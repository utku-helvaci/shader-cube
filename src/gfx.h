// SPDX-License-Identifier: MIT
/*
 * gfx: the small rendering interface shader-cube draws through.  Backends:
 * OpenGL ES 3.1 (3.0 without compute) / OpenGL 4.3 core (gfx_gl.c) and
 * Vulkan 1.3 (gfx_vk.c).
 *
 * Conventions shared by every backend, so the shaders are identical:
 *  - Row 0 of every texture / render target is the bottom row (GL style);
 *    gl_FragCoord.y counts rows from there.  Only the Vulkan swapchain is
 *    stored top-down: draws into it must flip (see flip_y).
 *  - Shaders get an API prelude, then use GFX_UBO(0) for their one std140
 *    uniform block (named st_Uniforms) and GFX_TEX(1+i) for sampler i.
 *    Compute shaders use GFX_SSBO(1+i) for storage buffer i.
 *  - Clip space is GL's (z in -w..w); vertex shaders wrap gl_Position in
 *    GFX_CLIP() and Vulkan remaps depth.
 *  - Device selection is left entirely to the system (prime-run,
 *    DRI_PRIME, __NV_PRIME_RENDER_OFFLOAD, MESA_VK_DEVICE_SELECT, ...): the
 *    backends use the first device they are given.
 */
#ifndef GFX_H
#define GFX_H

#include <stddef.h>

typedef struct GLFWwindow GLFWwindow;

typedef enum { GFX_GLES, GFX_GL, GFX_VULKAN } GfxApi;
typedef enum { GFX_R8, GFX_RGBA8, GFX_RGBA16F, GFX_RGBA32F, GFX_DEPTH } GfxFormat;

enum { GFX_NEAREST, GFX_LINEAR, GFX_MIPMAP };                     /* sampler filter */
enum { GFX_CLAMP, GFX_REPEAT };                                   /* sampler wrap */
enum { GFX_VTX_NONE, GFX_VTX_MESH, GFX_VTX_MESH_INST, GFX_VTX_UI }; /* vertex inputs */
enum { GFX_BLEND_NONE, GFX_BLEND_ADD, GFX_BLEND_ALPHA };          /* ALPHA: premultiplied */
enum { GFX_DEPTH_OFF, GFX_DEPTH_RW, GFX_DEPTH_TEST };             /* TEST: compare, don't write */

#define GFX_MAX_TEX 8
#define GFX_MAX_SSBO 6
#define GFX_VTX_STRIDE 32  /* MESH: location 0 vec3 pos, 1 vec3 normal, 2 vec2 uv */
#define GFX_INST_STRIDE 48 /* MESH_INST adds locations 3, 4, 5: vec4 each, per instance */
#define GFX_UI_STRIDE 32   /* UI: 0 vec2 pos, 1 vec2 uv, 2 vec4 colour (RGBA8), 3 vec3 params */

typedef struct {
    float pos[2], uv[2];
    unsigned char col[4];
    float p[3];
} GfxUiVtx;

typedef struct GfxTex GfxTex;
typedef struct GfxBuf GfxBuf;
typedef struct GfxProg GfxProg;

typedef struct {
    GfxApi api;
    int vsync;
    int debug;    /* GL debug output / Vulkan validation layer */
    int fallback; /* window hints for a second attempt: GLES 3.0 instead of 3.1 */
} GfxConfig;

typedef struct {
    const char *label;
    const char *vs[8];
    int nvs;
    const char *fs[16];
    int nfs;
    const char *tex[GFX_MAX_TEX]; /* sampler names, in binding order */
    int ntex;
    int vtx; /* GFX_VTX_* */
} GfxProgDesc;

typedef struct {
    GfxTex *color;  /* NULL: the window */
    int layer;      /* slice of a 3D colour texture (render slices 0..n-1 in order) */
    GfxTex *msaa;   /* if set: draw into this, resolve into color at end_pass */
    GfxTex *depth;
    int clear;
    float clear_color[4];
} GfxPass;

typedef struct {
    GfxProg *prog;
    const void *ubo;
    int ubo_size;
    GfxTex *tex[GFX_MAX_TEX];
    unsigned char filter[GFX_MAX_TEX], wrap[GFX_MAX_TEX];
    GfxBuf *vbuf;          /* static vertices, */
    const void *vdata;     /* or `count` vertices streamed from memory, or neither: no inputs */
    int first, count;
    const void *inst;      /* ninst * GFX_INST_STRIDE bytes from memory, */
    GfxBuf *inst_buf;      /* or from a storage buffer (written by compute shaders) */
    int ninst;
    unsigned char depth;   /* GFX_DEPTH_* */
    unsigned char cull;    /* cull back faces (counter-clockwise = front) */
    unsigned char blend;   /* GFX_BLEND_* */
} GfxDraw;

typedef struct {
    GfxProg *prog; /* from compute() */
    const void *ubo;
    int ubo_size;
    GfxBuf *buf[GFX_MAX_SSBO]; /* bound to GFX_SSBO(1 + i) */
    int groups[3];
} GfxDispatch;

typedef struct {
    const char *name;
    void (*window_hints)(const GfxConfig *cfg);           /* before glfwCreateWindow */
    int (*init)(const GfxConfig *cfg, GLFWwindow *win);   /* win may be NULL (Vulkan, offscreen) */
    void (*shutdown)(void);
    const char *(*device_name)(void);
    int (*is_nvidia)(void);
    int (*float32_filterable)(void);
    int (*max_samples)(void);
    int (*flip_y)(void); /* the window's rows are stored top-down */
    int (*has_compute)(void);
    void (*set_vsync)(int on);

    GfxTex *(*texture)(GfxFormat fmt, int w, int h, int depth, int mips, int samples);
    void (*upload)(GfxTex *t, const void *pixels); /* level 0; outside passes */
    void (*gen_mips)(GfxTex *t);                    /* outside passes */
    void (*readback)(GfxTex *t, void *rgba8);       /* RGBA8 only; filled by end_frame */
    void (*tex_free)(GfxTex *t);

    GfxBuf *(*buffer)(const void *data, size_t size);  /* static vertex data */
    GfxBuf *(*storage)(const void *data, size_t size); /* GPU buffer: storage, vertex/instance input;
                                                          data may be NULL (zeroed) */
    void (*buf_write)(GfxBuf *b, size_t off, const void *data, size_t size); /* outside passes */
    void (*buf_read)(GfxBuf *b, size_t off, void *dst, size_t size);         /* outside frames; waits */
    void (*buf_free)(GfxBuf *b);

    GfxProg *(*program)(const GfxProgDesc *d); /* NULL on compile error */
    GfxProg *(*compute)(const char *label, const char *const *src, int n); /* NULL: error / no compute */
    void (*prog_free)(GfxProg *p);

    void (*begin_frame)(void);
    void (*dispatch)(const GfxDispatch *d); /* inside a frame, outside passes; later work sees its writes */
    void (*begin_pass)(const GfxPass *p);
    void (*pass_size)(int *w, int *h);
    void (*draw)(const GfxDraw *d);
    void (*end_pass)(void);
    void (*end_frame)(void); /* submits; presents if the window was drawn */
    void (*wait_idle)(void); /* before freeing resources that may be in flight */
} GfxBackend;

extern const GfxBackend gfx_gl_backend;
extern const GfxBackend gfx_vk_backend;

#endif
