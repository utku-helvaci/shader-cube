// SPDX-License-Identifier: MIT
/*
 * OpenGL ES 3.0 and OpenGL 4.3 core backend.  Functions are loaded through
 * libepoxy, so one binary can drive either kind of context.
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
};

struct GfxProg {
    GLuint prog;
    int vtx;
};

static struct {
    GfxConfig cfg;
    GLFWwindow *win;
    int es;
    GLuint samplers[3][2];
    GLuint empty_vao, inst_vbo;
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
static const char *PRELUDE_GL =
    "#version 430 core\n"
    "#define GFX_GL 1\n";
static const char *PRELUDE_COMMON =
    "#define GFX_UBO(n) layout(std140) uniform\n"
    "#define GFX_TEX(n) uniform\n"
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
        glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
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
    printf("%s: %s | %s\n", G.es ? "OpenGL ES" : "OpenGL", ver, ren);

    if (cfg->debug && (epoxy_gl_version() >= 43 || has_ext("GL_KHR_debug"))) {
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
    glDeleteVertexArrays(1, &G.empty_vao);
    glDeleteBuffers(1, &G.inst_vbo);
    glDeleteBuffers(1, &G.ubo);
}

static const char *gl_device_name(void) { return G.device; }
static int gl_is_nvidia(void) { return G.nvidia; }
static int gl_float32_filterable(void) { return G.float_linear; }
static int gl_max_samples(void) { return G.max_samples; }
static int gl_flip_y(void) { return 0; }

/* ---------------------------------------------------------------- textures */

static void fmt_gl(GfxFormat f, GLenum *ifmt, GLenum *fmt, GLenum *type) {
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

/* ---------------------------------------------------------------- buffers & programs */

static GfxBuf *gl_buffer(const void *data, size_t size) {
    GfxBuf *b = calloc(1, sizeof *b);
    glGenBuffers(1, &b->vbo);
    glBindBuffer(GL_ARRAY_BUFFER, b->vbo);
    glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)size, data, GL_STATIC_DRAW);
    return b;
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
    for (int i = 0; i < 3; i++) glEnableVertexAttribArray((GLuint)i);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, GFX_VTX_STRIDE, (void *)0);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, GFX_VTX_STRIDE, (void *)12);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, GFX_VTX_STRIDE, (void *)24);
    if (inst) {
        glBindBuffer(GL_ARRAY_BUFFER, G.inst_vbo);
        for (int i = 0; i < 3; i++) {
            glEnableVertexAttribArray((GLuint)(3 + i));
            glVertexAttribPointer((GLuint)(3 + i), 4, GL_FLOAT, GL_FALSE, GFX_INST_STRIDE, (void *)(size_t)(16 * i));
            glVertexAttribDivisor((GLuint)(3 + i), 1);
        }
    }
    return *vao;
}

static GLuint compile(GLenum type, const char *const *chunks, int n, const char *label) {
    const char *src[20];
    int k = 0;
    src[k++] = G.es ? PRELUDE_ES : PRELUDE_GL;
    src[k++] = PRELUDE_COMMON;
    src[k++] = type == GL_VERTEX_SHADER ? "#define GFX_VS 1\n" : "#define GFX_FS 1\n";
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

static GfxProg *gl_program(const GfxProgDesc *d) {
    GLuint v = compile(GL_VERTEX_SHADER, d->vs, d->nvs, d->label);
    GLuint f = v ? compile(GL_FRAGMENT_SHADER, d->fs, d->nfs, d->label) : 0;
    if (!v || !f) {
        if (v) glDeleteShader(v);
        return NULL;
    }
    GLuint p = glCreateProgram();
    glAttachShader(p, v);
    glAttachShader(p, f);
    glLinkProgram(p);
    glDeleteShader(v);
    glDeleteShader(f);
    GLint ok;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[16384];
        glGetProgramInfoLog(p, sizeof log, NULL, log);
        fprintf(stderr, "[%s] link error:\n%s\n", d->label, log);
        glDeleteProgram(p);
        return NULL;
    }
    GLuint blk = glGetUniformBlockIndex(p, "st_Uniforms");
    if (blk != GL_INVALID_INDEX) glUniformBlockBinding(p, blk, 0);
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
    if (G.cur_prog != d->prog->prog) {
        glUseProgram(d->prog->prog);
        G.cur_prog = d->prog->prog;
    }
    if (d->ubo_size > 0) {
        GLsizeiptr off = (G.ubo_off + G.ubo_align - 1) / G.ubo_align * G.ubo_align;
        if (off + d->ubo_size > G.ubo_size) { /* ring full: start a new buffer store */
            glBindBuffer(GL_UNIFORM_BUFFER, G.ubo);
            glBufferData(GL_UNIFORM_BUFFER, G.ubo_size, NULL, GL_STREAM_DRAW);
            off = 0;
        }
        glBindBuffer(GL_UNIFORM_BUFFER, G.ubo);
        glBufferSubData(GL_UNIFORM_BUFFER, off, d->ubo_size, d->ubo);
        glBindBufferRange(GL_UNIFORM_BUFFER, 0, G.ubo, off, d->ubo_size);
        G.ubo_off = off + d->ubo_size;
    }
    for (int i = 0; i < GFX_MAX_TEX; i++) {
        GfxTex *t = d->tex[i];
        if (!t) continue;
        glActiveTexture(GL_TEXTURE0 + (GLenum)i);
        glBindTexture(t->target, t->id);
        int filt = d->filter[i];
        if (filt == GFX_MIPMAP && t->levels < 2) filt = GFX_LINEAR;
        glBindSampler((GLuint)i, G.samplers[filt][d->wrap[i]]);
    }
    if (d->depth) { glEnable(GL_DEPTH_TEST); glDepthMask(GL_TRUE); glDepthFunc(GL_LESS); }
    else glDisable(GL_DEPTH_TEST);
    if (d->cull) { glEnable(GL_CULL_FACE); glCullFace(GL_BACK); glFrontFace(GL_CCW); }
    else glDisable(GL_CULL_FACE);
    if (d->blend_add) { glEnable(GL_BLEND); glBlendFunc(GL_ONE, GL_ONE); }
    else glDisable(GL_BLEND);

    if (d->vbuf) {
        int inst = d->prog->vtx == GFX_VTX_MESH_INST;
        glBindVertexArray(mesh_vao(d->vbuf, inst));
        if (inst) {
            glBindBuffer(GL_ARRAY_BUFFER, G.inst_vbo);
            glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)d->ninst * GFX_INST_STRIDE, d->inst, GL_STREAM_DRAW);
            if (d->ninst > 0) glDrawArraysInstanced(GL_TRIANGLES, d->first, d->count, d->ninst);
        } else {
            glDrawArrays(GL_TRIANGLES, d->first, d->count);
        }
    } else {
        glBindVertexArray(G.empty_vao);
        glDrawArrays(GL_TRIANGLES, d->first, d->count);
    }
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
}

static void gl_end_frame(void) {
    if (G.drew_window) glfwSwapBuffers(G.win);
    else glFlush();
}

static void gl_wait_idle(void) { glFinish(); }

const GfxBackend gfx_gl_backend = {
    "OpenGL",
    gl_window_hints, gl_init, gl_shutdown, gl_device_name, gl_is_nvidia,
    gl_float32_filterable, gl_max_samples, gl_flip_y,
    gl_texture, gl_upload, gl_gen_mips, gl_readback, gl_tex_free,
    gl_buffer, gl_buf_free,
    gl_program, gl_prog_free,
    gl_begin_frame, gl_begin_pass, gl_pass_size, gl_draw, gl_end_pass, gl_end_frame, gl_wait_idle,
};
