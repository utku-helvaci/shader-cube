// SPDX-License-Identifier: MIT
/*
 * OpenGL ES 3.1 (3.0 without compute shaders) and OpenGL 4.3 core backend.
 * Functions are loaded through libepoxy, so one binary can drive either
 * kind of context.
 */
#include <epoxy/gl.h>
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gfx.h"

struct GfxTex {
    GfxFormat fmt;
    GLenum target; /* GL_TEXTURE_2D / GL_TEXTURE_3D, or GL_RENDERBUFFER */
    GLuint id, fbo;
    int w, h, d, levels, samples;
};

struct GfxBuf {
    GLuint vbo, vao, vao_inst;
    size_t size;
};

struct GfxProg {
    GLuint prog;
    int vtx, compute;
};

static struct {
    GfxConfig cfg;
    GLFWwindow *win;
    int es, version, compute;
    GLuint samplers[3][2];
    GLuint empty_vao, inst_vbo, stream_vbo, stream_mesh_vao, stream_ui_vao;
    GLuint ubo;
    GLint ubo_align;
    GLsizeiptr ubo_size, ubo_off;
    GfxPass pass;
    int pass_w, pass_h, drew_window;
    GLuint cur_prog;
    int float_linear, max_samples, nvidia;
    char device[256];
} G;

#define UBO_RING (1 << 20)

static const char *PRELUDE_ES =
    "#version 300 es\n"
    "precision highp float; precision highp int;\n"
    "precision highp sampler2D; precision highp sampler3D;\n"
    "#define GFX_GLES 1\n";
static const char *PRELUDE_ES_CS =
    "#version 310 es\n"
    "precision highp float; precision highp int;\n"
    "#define GFX_GLES 1\n";
static const char *PRELUDE_GL =
    "#version 430 core\n"
    "#define GFX_GL 1\n";
static const char *PRELUDE_COMMON =
    "#define GFX_UBO(n) layout(std140) uniform\n"
    "#define GFX_TEX(n) uniform\n"
    "#define GFX_SSBO(n) layout(std430, binding = n) buffer\n"
    "#define GFX_VERTEX_ID gl_VertexID\n"
    "#define GFX_CLIP(p) (p)\n";

/* ---------------------------------------------------------------- setup */

static void APIENTRY on_gl_debug(GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei len,
                                 const GLchar *msg, const void *user) {
    (void)source; (void)id; (void)len; (void)user;
    if (severity == GL_DEBUG_SEVERITY_NOTIFICATION) return;
    fprintf(stderr, "GL %s: %s\n", type == GL_DEBUG_TYPE_ERROR ? "error" : "debug", msg);
}

static void gl_window_hints(const GfxConfig *cfg) {
    if (cfg->api == GFX_GLES) {
        /* 3.1 for compute shaders; the fallback attempt settles for 3.0. */
        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, cfg->fallback ? 0 : 1);
    } else {
        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
    }
    glfwWindowHint(GLFW_CONTEXT_DEBUG, cfg->debug ? GLFW_TRUE : GLFW_FALSE);
}

static int has_ext(const char *name) {
    GLint n = 0;
    glGetIntegerv(GL_NUM_EXTENSIONS, &n);
    for (GLint i = 0; i < n; i++)
        if (!strcmp((const char *)glGetStringi(GL_EXTENSIONS, (GLuint)i), name)) return 1;
    return 0;
}

static void ui_attribs(void) {
    for (GLuint i = 0; i < 4; i++) glEnableVertexAttribArray(i);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, GFX_UI_STRIDE, (void *)0);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, GFX_UI_STRIDE, (void *)8);
    glVertexAttribPointer(2, 4, GL_UNSIGNED_BYTE, GL_TRUE, GFX_UI_STRIDE, (void *)16);
    glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE, GFX_UI_STRIDE, (void *)20);
}

static void mesh_attribs(void) {
    for (GLuint i = 0; i < 3; i++) glEnableVertexAttribArray(i);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, GFX_VTX_STRIDE, (void *)0);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, GFX_VTX_STRIDE, (void *)12);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, GFX_VTX_STRIDE, (void *)24);
}

static int gl_init(const GfxConfig *cfg, GLFWwindow *win) {
    memset(&G, 0, sizeof G);
    G.cfg = *cfg;
    G.win = win;
    G.es = cfg->api == GFX_GLES;
    if (!win) return 0;
    glfwMakeContextCurrent(win);
    glfwSwapInterval(cfg->vsync ? 1 : 0);

    const char *ver = (const char *)glGetString(GL_VERSION);
    const char *ren = (const char *)glGetString(GL_RENDERER);
    const char *ven = (const char *)glGetString(GL_VENDOR);
    snprintf(G.device, sizeof G.device, "%s", ren ? ren : "?");
    G.nvidia = (ven && strstr(ven, "NVIDIA")) || (ren && strstr(ren, "NVIDIA"));
    G.version = epoxy_gl_version();
    G.compute = G.es ? G.version >= 31 : G.version >= 43;
    printf("%s: %s | %s\n", G.es ? "OpenGL ES" : "OpenGL", ver, ren);

    if (cfg->debug && (G.version >= 43 || has_ext("GL_KHR_debug"))) {
        glEnable(GL_DEBUG_OUTPUT);
        glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
        glDebugMessageCallback(on_gl_debug, NULL);
    }

    if (G.es) {
        if (!has_ext("GL_EXT_color_buffer_float"))
            fprintf(stderr, "warning: GL_EXT_color_buffer_float missing; float buffers may not work\n");
        G.float_linear = has_ext("GL_OES_texture_float_linear");
    } else {
        G.float_linear = 1;
    }
    GLint maxs = 0;
    glGetInternalformativ(GL_RENDERBUFFER, GL_RGBA16F, GL_SAMPLES, 1, &maxs);
    G.max_samples = maxs > 0 ? maxs : 1;

    static const GLint mins[3] = {GL_NEAREST, GL_LINEAR, GL_LINEAR_MIPMAP_LINEAR};
    static const GLint mags[3] = {GL_NEAREST, GL_LINEAR, GL_LINEAR};
    static const GLint wraps[2] = {GL_CLAMP_TO_EDGE, GL_REPEAT};
    for (int f = 0; f < 3; f++)
        for (int w = 0; w < 2; w++) {
            GLuint s;
            glGenSamplers(1, &s);
            glSamplerParameteri(s, GL_TEXTURE_MIN_FILTER, mins[f]);
            glSamplerParameteri(s, GL_TEXTURE_MAG_FILTER, mags[f]);
            glSamplerParameteri(s, GL_TEXTURE_WRAP_S, wraps[w]);
            glSamplerParameteri(s, GL_TEXTURE_WRAP_T, wraps[w]);
            glSamplerParameteri(s, GL_TEXTURE_WRAP_R, wraps[w]);
            G.samplers[f][w] = s;
        }
    glGenVertexArrays(1, &G.empty_vao);
    glGenBuffers(1, &G.inst_vbo);
    glGenBuffers(1, &G.stream_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, G.stream_vbo);
    glGenVertexArrays(1, &G.stream_mesh_vao);
    glBindVertexArray(G.stream_mesh_vao);
    mesh_attribs();
    glGenVertexArrays(1, &G.stream_ui_vao);
    glBindVertexArray(G.stream_ui_vao);
    ui_attribs();
    glBindVertexArray(0);
    glGetIntegerv(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT, &G.ubo_align);
    if (G.ubo_align < 16) G.ubo_align = 16;
    G.ubo_size = UBO_RING;
    glGenBuffers(1, &G.ubo);
    glBindBuffer(GL_UNIFORM_BUFFER, G.ubo);
    glBufferData(GL_UNIFORM_BUFFER, G.ubo_size, NULL, GL_STREAM_DRAW);
    return 1;
}

static void gl_shutdown(void) {
    if (!G.win) return;
    for (int f = 0; f < 3; f++) glDeleteSamplers(2, G.samplers[f]);
    GLuint vaos[3] = {G.empty_vao, G.stream_mesh_vao, G.stream_ui_vao};
    glDeleteVertexArrays(3, vaos);
    GLuint bufs[3] = {G.inst_vbo, G.stream_vbo, G.ubo};
    glDeleteBuffers(3, bufs);
}

static const char *gl_device_name(void) { return G.device; }
static int gl_is_nvidia(void) { return G.nvidia; }
static int gl_float32_filterable(void) { return G.float_linear; }
static int gl_max_samples(void) { return G.max_samples; }
static int gl_flip_y(void) { return 0; }
static int gl_has_compute(void) { return G.compute; }
static void gl_set_vsync(int on) { glfwSwapInterval(on ? 1 : 0); }

/* ---------------------------------------------------------------- textures */

static void fmt_gl(GfxFormat f, GLenum *ifmt, GLenum *fmt, GLenum *type) {
    *ifmt = GL_RGBA8; *fmt = GL_RGBA; *type = GL_UNSIGNED_BYTE;
    switch (f) {
    case GFX_R8: *ifmt = GL_R8; *fmt = GL_RED; *type = GL_UNSIGNED_BYTE; break;
    case GFX_RGBA8: *ifmt = GL_RGBA8; *fmt = GL_RGBA; *type = GL_UNSIGNED_BYTE; break;
    case GFX_RGBA16F: *ifmt = GL_RGBA16F; *fmt = GL_RGBA; *type = GL_HALF_FLOAT; break;
    case GFX_RGBA32F: *ifmt = GL_RGBA32F; *fmt = GL_RGBA; *type = GL_FLOAT; break;
    case GFX_DEPTH: *ifmt = GL_DEPTH_COMPONENT24; *fmt = GL_DEPTH_COMPONENT; *type = GL_UNSIGNED_INT; break;
    }
}

static GfxTex *gl_texture(GfxFormat fmt, int w, int h, int d, int mips, int samples) {
    GfxTex *t = calloc(1, sizeof *t);
    t->fmt = fmt; t->w = w; t->h = h; t->d = d < 1 ? 1 : d;
    t->samples = samples < 1 ? 1 : samples;
    GLenum ifmt, f, ty;
    fmt_gl(fmt, &ifmt, &f, &ty);
    if (t->samples > 1 || fmt == GFX_DEPTH) {
        t->target = GL_RENDERBUFFER;
        t->levels = 1;
        glGenRenderbuffers(1, &t->id);
        glBindRenderbuffer(GL_RENDERBUFFER, t->id);
        glRenderbufferStorageMultisample(GL_RENDERBUFFER, t->samples > 1 ? t->samples : 0, ifmt, w, h);
        return t;
    }
    t->levels = 1;
    if (mips)
        for (int m = w > h ? w : h; m > 1; m >>= 1) t->levels++;
    glGenTextures(1, &t->id);
    if (t->d > 1) {
        t->target = GL_TEXTURE_3D;
        glBindTexture(GL_TEXTURE_3D, t->id);
        glTexStorage3D(GL_TEXTURE_3D, 1, ifmt, w, h, t->d);
    } else {
        t->target = GL_TEXTURE_2D;
        glBindTexture(GL_TEXTURE_2D, t->id);
        glTexStorage2D(GL_TEXTURE_2D, t->levels, ifmt, w, h);
    }
    /* Sampler objects override these; they matter for blits only. */
    glTexParameteri(t->target, GL_TEXTURE_MIN_FILTER, mips ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR);
    glTexParameteri(t->target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    /* Start out zeroed, like Shadertoy buffers. */
    GLuint fbo;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glClearColor(0, 0, 0, 0);
    for (int z = 0; z < t->d; z++) {
        if (t->target == GL_TEXTURE_3D) glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, t->id, 0, z);
        else glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t->id, 0);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDeleteFramebuffers(1, &fbo);
    return t;
}

static void gl_upload(GfxTex *t, const void *px) {
    GLenum ifmt, f, ty;
    fmt_gl(t->fmt, &ifmt, &f, &ty);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glBindTexture(t->target, t->id);
    if (t->target == GL_TEXTURE_3D)
        glTexSubImage3D(GL_TEXTURE_3D, 0, 0, 0, 0, t->w, t->h, t->d, f, ty, px);
    else
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, t->w, t->h, f, ty, px);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
}

static void gl_gen_mips(GfxTex *t) {
    if (t->levels < 2) return;
    glBindTexture(t->target, t->id);
    glGenerateMipmap(t->target);
}

static GLuint tex_fbo(GfxTex *t) {
    if (!t->fbo) {
        glGenFramebuffers(1, &t->fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, t->fbo);
        if (t->target == GL_RENDERBUFFER)
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, t->id);
        else if (t->target == GL_TEXTURE_2D)
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t->id, 0);
    }
    return t->fbo;
}

static void gl_readback(GfxTex *t, void *dst) {
    glBindFramebuffer(GL_FRAMEBUFFER, tex_fbo(t));
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, t->w, t->h, GL_RGBA, GL_UNSIGNED_BYTE, dst);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
}

static void gl_tex_free(GfxTex *t) {
    if (!t) return;
    if (t->fbo) glDeleteFramebuffers(1, &t->fbo);
    if (t->target == GL_RENDERBUFFER) glDeleteRenderbuffers(1, &t->id);
    else glDeleteTextures(1, &t->id);
    free(t);
}

/* ---------------------------------------------------------------- buffers */

static GfxBuf *make_buf(const void *data, size_t size, GLenum usage) {
    GfxBuf *b = calloc(1, sizeof *b);
    b->size = size;
    void *zero = data ? NULL : calloc(1, size ? size : 1);
    glGenBuffers(1, &b->vbo);
    glBindBuffer(GL_ARRAY_BUFFER, b->vbo);
    glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)size, data ? data : zero, usage);
    free(zero);
    return b;
}

static GfxBuf *gl_buffer(const void *data, size_t size) { return make_buf(data, size, GL_STATIC_DRAW); }
static GfxBuf *gl_storage(const void *data, size_t size) { return make_buf(data, size, GL_DYNAMIC_DRAW); }

static void gl_buf_write(GfxBuf *b, size_t off, const void *data, size_t size) {
    glBindBuffer(GL_ARRAY_BUFFER, b->vbo);
    glBufferSubData(GL_ARRAY_BUFFER, (GLintptr)off, (GLsizeiptr)size, data);
}

static void gl_buf_read(GfxBuf *b, size_t off, void *dst, size_t size) {
    if (G.compute) glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT);
    glBindBuffer(GL_ARRAY_BUFFER, b->vbo);
    void *p = glMapBufferRange(GL_ARRAY_BUFFER, (GLintptr)off, (GLsizeiptr)size, GL_MAP_READ_BIT);
    if (p) memcpy(dst, p, size);
    else memset(dst, 0, size);
    glUnmapBuffer(GL_ARRAY_BUFFER);
}

static void gl_buf_free(GfxBuf *b) {
    if (!b) return;
    glDeleteBuffers(1, &b->vbo);
    if (b->vao) glDeleteVertexArrays(1, &b->vao);
    if (b->vao_inst) glDeleteVertexArrays(1, &b->vao_inst);
    free(b);
}

static GLuint mesh_vao(GfxBuf *b, int inst) {
    GLuint *vao = inst ? &b->vao_inst : &b->vao;
    if (*vao) return *vao;
    glGenVertexArrays(1, vao);
    glBindVertexArray(*vao);
    glBindBuffer(GL_ARRAY_BUFFER, b->vbo);
    mesh_attribs();
    if (inst)
        for (int i = 0; i < 3; i++) {
            glEnableVertexAttribArray((GLuint)(3 + i));
            glVertexAttribDivisor((GLuint)(3 + i), 1);
        }
    return *vao;
}

/* ---------------------------------------------------------------- programs */

static GLuint compile(GLenum type, const char *const *chunks, int n, const char *label) {
    const char *src[20];
    int k = 0;
    if (type == GL_COMPUTE_SHADER) src[k++] = G.es ? PRELUDE_ES_CS : PRELUDE_GL;
    else src[k++] = G.es ? PRELUDE_ES : PRELUDE_GL;
    src[k++] = PRELUDE_COMMON;
    src[k++] = type == GL_VERTEX_SHADER ? "#define GFX_VS 1\n"
             : type == GL_FRAGMENT_SHADER ? "#define GFX_FS 1\n" : "#define GFX_CS 1\n";
    for (int i = 0; i < n && k < 20; i++) src[k++] = chunks[i];
    GLuint s = glCreateShader(type);
    glShaderSource(s, k, src, NULL);
    glCompileShader(s);
    GLint ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[16384];
        glGetShaderInfoLog(s, sizeof log, NULL, log);
        fprintf(stderr, "[%s] compile error:\n%s\n", label, log);
        glDeleteShader(s);
        return 0;
    }
    return s;
}

static GLuint link(GLuint a, GLuint b, const char *label) {
    GLuint p = glCreateProgram();
    glAttachShader(p, a);
    if (b) glAttachShader(p, b);
    glLinkProgram(p);
    glDeleteShader(a);
    if (b) glDeleteShader(b);
    GLint ok;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[16384];
        glGetProgramInfoLog(p, sizeof log, NULL, log);
        fprintf(stderr, "[%s] link error:\n%s\n", label, log);
        glDeleteProgram(p);
        return 0;
    }
    GLuint blk = glGetUniformBlockIndex(p, "st_Uniforms");
    if (blk != GL_INVALID_INDEX) glUniformBlockBinding(p, blk, 0);
    return p;
}

static GfxProg *gl_program(const GfxProgDesc *d) {
    GLuint v = compile(GL_VERTEX_SHADER, d->vs, d->nvs, d->label);
    GLuint f = v ? compile(GL_FRAGMENT_SHADER, d->fs, d->nfs, d->label) : 0;
    if (!v || !f) {
        if (v) glDeleteShader(v);
        return NULL;
    }
    GLuint p = link(v, f, d->label);
    if (!p) return NULL;
    glUseProgram(p);
    for (int i = 0; i < d->ntex; i++) {
        GLint loc = glGetUniformLocation(p, d->tex[i]);
        if (loc >= 0) glUniform1i(loc, i);
    }
    glUseProgram(0);
    G.cur_prog = 0;
    GfxProg *g = calloc(1, sizeof *g);
    g->prog = p;
    g->vtx = d->vtx;
    return g;
}

static GfxProg *gl_compute(const char *label, const char *const *src, int n) {
    if (!G.compute) return NULL;
    GLuint c = compile(GL_COMPUTE_SHADER, src, n, label);
    GLuint p = c ? link(c, 0, label) : 0;
    if (!p) return NULL;
    GfxProg *g = calloc(1, sizeof *g);
    g->prog = p;
    g->compute = 1;
    return g;
}

static void gl_prog_free(GfxProg *p) {
    if (!p) return;
    glDeleteProgram(p->prog);
    if (G.cur_prog == p->prog) G.cur_prog = 0;
    free(p);
}

/* ---------------------------------------------------------------- frame */

static void gl_begin_frame(void) {
    G.ubo_off = 0;
    G.drew_window = 0;
    /* Fresh storage each frame, so writes never wait on the GPU. */
    glBindBuffer(GL_UNIFORM_BUFFER, G.ubo);
    glBufferData(GL_UNIFORM_BUFFER, G.ubo_size, NULL, GL_STREAM_DRAW);
}

static void use_program(GfxProg *p) {
    if (G.cur_prog != p->prog) {
        glUseProgram(p->prog);
        G.cur_prog = p->prog;
    }
}

static void bind_ubo(const void *data, int size) {
    if (size <= 0) return;
    GLsizeiptr off = (G.ubo_off + G.ubo_align - 1) / G.ubo_align * G.ubo_align;
    if (off + size > G.ubo_size) { /* ring full: start a new buffer store */
        glBindBuffer(GL_UNIFORM_BUFFER, G.ubo);
        glBufferData(GL_UNIFORM_BUFFER, G.ubo_size, NULL, GL_STREAM_DRAW);
        off = 0;
    }
    glBindBuffer(GL_UNIFORM_BUFFER, G.ubo);
    glBufferSubData(GL_UNIFORM_BUFFER, off, size, data);
    glBindBufferRange(GL_UNIFORM_BUFFER, 0, G.ubo, off, size);
    G.ubo_off = off + size;
}

static void gl_dispatch(const GfxDispatch *d) {
    if (!d->prog || !d->prog->compute) return;
    use_program(d->prog);
    bind_ubo(d->ubo, d->ubo_size);
    for (int i = 0; i < GFX_MAX_SSBO; i++)
        if (d->buf[i]) glBindBufferBase(GL_SHADER_STORAGE_BUFFER, (GLuint)(1 + i), d->buf[i]->vbo);
    glDispatchCompute((GLuint)d->groups[0], (GLuint)(d->groups[1] ? d->groups[1] : 1),
                      (GLuint)(d->groups[2] ? d->groups[2] : 1));
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT | GL_VERTEX_ATTRIB_ARRAY_BARRIER_BIT |
                    GL_BUFFER_UPDATE_BARRIER_BIT);
}

static void gl_begin_pass(const GfxPass *p) {
    G.pass = *p;
    GLbitfield clear = GL_COLOR_BUFFER_BIT;
    if (!p->color) {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glfwGetFramebufferSize(G.win, &G.pass_w, &G.pass_h);
        G.drew_window = 1;
    } else {
        GfxTex *rt = p->msaa ? p->msaa : p->color;
        glBindFramebuffer(GL_FRAMEBUFFER, tex_fbo(rt));
        if (rt->target == GL_TEXTURE_3D)
            glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, rt->id, 0, p->layer);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, p->depth ? p->depth->id : 0);
        if (p->depth) clear |= GL_DEPTH_BUFFER_BIT;
        G.pass_w = rt->w;
        G.pass_h = rt->h;
    }
    glViewport(0, 0, G.pass_w, G.pass_h);
    if (p->clear) {
        glDepthMask(GL_TRUE);
        glClearColor(p->clear_color[0], p->clear_color[1], p->clear_color[2], p->clear_color[3]);
        glClear(clear);
    }
}

static void gl_pass_size(int *w, int *h) { *w = G.pass_w; *h = G.pass_h; }

static void gl_draw(const GfxDraw *d) {
    use_program(d->prog);
    bind_ubo(d->ubo, d->ubo_size);
    for (int i = 0; i < GFX_MAX_TEX; i++) {
        GfxTex *t = d->tex[i];
        if (!t) continue;
        glActiveTexture(GL_TEXTURE0 + (GLenum)i);
        glBindTexture(t->target, t->id);
        int filt = d->filter[i];
        if (filt == GFX_MIPMAP && t->levels < 2) filt = GFX_LINEAR;
        glBindSampler((GLuint)i, G.samplers[filt][d->wrap[i]]);
    }
    if (d->depth) {
        glEnable(GL_DEPTH_TEST);
        glDepthMask(d->depth == GFX_DEPTH_RW ? GL_TRUE : GL_FALSE);
        glDepthFunc(GL_LESS);
    } else {
        glDisable(GL_DEPTH_TEST);
    }
    if (d->cull) { glEnable(GL_CULL_FACE); glCullFace(GL_BACK); glFrontFace(GL_CCW); }
    else glDisable(GL_CULL_FACE);
    if (d->blend == GFX_BLEND_ADD) { glEnable(GL_BLEND); glBlendFunc(GL_ONE, GL_ONE); }
    else if (d->blend == GFX_BLEND_ALPHA) { glEnable(GL_BLEND); glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA); }
    else glDisable(GL_BLEND);

    int inst = d->prog->vtx == GFX_VTX_MESH_INST;
    if (d->vbuf) {
        glBindVertexArray(mesh_vao(d->vbuf, inst));
    } else if (d->vdata) {
        int stride = d->prog->vtx == GFX_VTX_UI ? GFX_UI_STRIDE : GFX_VTX_STRIDE;
        glBindBuffer(GL_ARRAY_BUFFER, G.stream_vbo);
        glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)d->count * stride, d->vdata, GL_STREAM_DRAW);
        glBindVertexArray(d->prog->vtx == GFX_VTX_UI ? G.stream_ui_vao : G.stream_mesh_vao);
        glDrawArrays(GL_TRIANGLES, 0, d->count);
        return;
    } else {
        glBindVertexArray(G.empty_vao);
        glDrawArrays(GL_TRIANGLES, d->first, d->count);
        return;
    }
    if (!inst) {
        glDrawArrays(GL_TRIANGLES, d->first, d->count);
        return;
    }
    if (d->ninst <= 0) return;
    /* Instance attributes: point them at this draw's source every time. */
    if (d->inst_buf) {
        glBindBuffer(GL_ARRAY_BUFFER, d->inst_buf->vbo);
    } else {
        glBindBuffer(GL_ARRAY_BUFFER, G.inst_vbo);
        glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)d->ninst * GFX_INST_STRIDE, d->inst, GL_STREAM_DRAW);
    }
    for (int i = 0; i < 3; i++)
        glVertexAttribPointer((GLuint)(3 + i), 4, GL_FLOAT, GL_FALSE, GFX_INST_STRIDE, (void *)(size_t)(16 * i));
    glDrawArraysInstanced(GL_TRIANGLES, d->first, d->count, d->ninst);
}

static void gl_end_pass(void) {
    GfxPass *p = &G.pass;
    if (p->color && p->msaa) {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, tex_fbo(p->msaa));
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, tex_fbo(p->color));
        glBlitFramebuffer(0, 0, p->msaa->w, p->msaa->h, 0, 0, p->color->w, p->color->h,
                          GL_COLOR_BUFFER_BIT, GL_NEAREST);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glDisable(GL_BLEND);
    glDepthMask(GL_TRUE);
}

static void gl_end_frame(void) {
    if (G.drew_window) glfwSwapBuffers(G.win);
    else glFlush();
}

static void gl_wait_idle(void) { glFinish(); }

const GfxBackend gfx_gl_backend = {
    .name = "OpenGL",
    .window_hints = gl_window_hints, .init = gl_init, .shutdown = gl_shutdown,
    .device_name = gl_device_name, .is_nvidia = gl_is_nvidia, .float32_filterable = gl_float32_filterable,
    .max_samples = gl_max_samples, .flip_y = gl_flip_y, .has_compute = gl_has_compute,
    .set_vsync = gl_set_vsync,
    .texture = gl_texture, .upload = gl_upload, .gen_mips = gl_gen_mips, .readback = gl_readback,
    .tex_free = gl_tex_free,
    .buffer = gl_buffer, .storage = gl_storage, .buf_write = gl_buf_write, .buf_read = gl_buf_read,
    .buf_free = gl_buf_free,
    .program = gl_program, .compute = gl_compute, .prog_free = gl_prog_free,
    .begin_frame = gl_begin_frame, .dispatch = gl_dispatch, .begin_pass = gl_begin_pass,
    .pass_size = gl_pass_size, .draw = gl_draw, .end_pass = gl_end_pass, .end_frame = gl_end_frame,
    .wait_idle = gl_wait_idle,
};
