// SPDX-License-Identifier: MIT
/*
 * gfx: the small rendering interface shader-cube draws through.  Backends:
 * OpenGL ES 3.0 / OpenGL 4.3 core (gfx_gl.c) and Vulkan 1.3 (gfx_vk.c).
 *
 * Conventions shared by every backend, so the shaders are identical:
 *  - Row 0 of every texture / render target is the bottom row (GL style);
 *    gl_FragCoord.y counts rows from there.  Only the Vulkan swapchain is
 *    stored top-down: draws into it must flip (see flip_y).
 *  - Shaders get an API prelude, then use GFX_UBO(0) for their one std140
 *    uniform block (named st_Uniforms) and GFX_TEX(1+i) for sampler i.
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

enum { GFX_NEAREST, GFX_LINEAR, GFX_MIPMAP };          /* sampler filter */
enum { GFX_CLAMP, GFX_REPEAT };                        /* sampler wrap */
enum { GFX_VTX_NONE, GFX_VTX_MESH, GFX_VTX_MESH_INST }; /* vertex inputs */

#define GFX_MAX_TEX 8
#define GFX_VTX_STRIDE 32  /* location 0 vec3 pos, 1 vec3 normal, 2 vec2 uv */
#define GFX_INST_STRIDE 48 /* locations 3, 4, 5: vec4 each, per instance */

typedef struct GfxTex GfxTex;
typedef struct GfxBuf GfxBuf;
typedef struct GfxProg GfxProg;

typedef struct {
    GfxApi api;
    int vsync;
    int debug; /* GL debug output / Vulkan validation layer */
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
    GfxBuf *vbuf;          /* NULL: `count` vertices with no inputs */
    int first, count;
    const void *inst;      /* ninst * GFX_INST_STRIDE bytes */
    int ninst;
    unsigned char depth;   /* depth test + write */
    unsigned char cull;    /* cull back faces (counter-clockwise = front) */
    unsigned char blend_add;
} GfxDraw;

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

    GfxTex *(*texture)(GfxFormat fmt, int w, int h, int depth, int mips, int samples);
    void (*upload)(GfxTex *t, const void *pixels); /* level 0; outside passes */
    void (*gen_mips)(GfxTex *t);                    /* outside passes */
    void (*readback)(GfxTex *t, void *rgba8);       /* RGBA8 only; filled by end_frame */
    void (*tex_free)(GfxTex *t);

    GfxBuf *(*buffer)(const void *data, size_t size); /* static vertex data */
    void (*buf_free)(GfxBuf *b);

    GfxProg *(*program)(const GfxProgDesc *d); /* NULL on compile error */
    void (*prog_free)(GfxProg *p);

    void (*begin_frame)(void);
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
