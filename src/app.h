// SPDX-License-Identifier: MIT
/*
 * What main.c (the application: window, frame loop, post-processing, F1
 * menu) shares with the scenes.  A scene renders through gfx into the HDR
 * target that post_scene_pass() sets up, then hands it to post_finish() for
 * bloom and tone mapping.
 */
#ifndef APP_H
#define APP_H

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <stddef.h>

#include "gfx.h"
#include "mathx.h"

extern const GfxBackend *gfx;

/* Physics engine choice (--physics, and the scenes' menus). */
enum { PHYS_PREF_AUTO, PHYS_PREF_GPU, PHYS_PREF_CPU, PHYS_PREF_COMPUTE, PHYS_PREF_OFF };

typedef struct {
    GLFWwindow *win;        /* NULL: offline without a window */
    int offline;            /* rendering to files: fixed time step, no input */
    int paused;
    double time;            /* simulated seconds */
    float fps;
    int fb_w, fb_h;         /* size of the frame being rendered */
    char api_label[200];    /* "Vulkan · <GPU>" */
    char data_dir[1024];    /* holds shaders/ and assets/ */
    const char *shader_root;
    /* start-up options for the scenes */
    int physics;            /* PHYS_PREF_* */
    int debris, balls, rows, face_res, view_face;
    const char *stop_list;
} App;

extern App app;

typedef struct {
    const char *id, *name;
    int (*enter)(void);                /* create resources; 0 on failure */
    void (*leave)(void);               /* free them */
    void (*update)(float dt);          /* simulation on the CPU, before the frame */
    void (*render)(GfxTex *dst, float dt); /* inside the frame: GPU work, then the image into dst */
    void (*menu)(void);                /* its settings in the F1 menu */
    void (*status)(char *buf, size_t n); /* for the window title */
    int (*key)(int key, int action, int mods); /* 1: used */
    void (*button)(int button, int action, double x, double y);
    void (*cursor)(double x, double y);
    void (*scroll)(double dy);
} Scene;

extern const Scene scene_cube, scene_galton;

/* main.c */
char *read_file(const char *path);
void app_set_title_dirty(void);
GfxPass post_scene_pass(int w, int h, const float clear[4]); /* HDR target sized w x h */
void post_finish(GfxTex *dst, float bloom, float exposure);  /* bloom + tone mapping */
void post_view(GfxTex *dst, GfxTex *tex, int tw, int th);    /* tex aspect-fit into dst */
extern const char *const FULLSCREEN_VS; /* one triangle covering the target, `count` 3 */

/* Meshes (counter-clockwise front faces). */
typedef struct { float p[3], n[3], uv[2]; } Vtx;
extern const float FACE_N[6][3], FACE_T[6][3], FACE_B[6][3]; /* +X -X +Y -Y +Z -Z */
void mesh_box(Vtx *out, v3 half, int inward); /* 36 vertices */
int mesh_sphere(Vtx **out, int slices, int stacks);
int mesh_cylinder(Vtx **out, int slices); /* radius 1, z from -1 to 1, capped */

/* Orbit camera helpers. */
v3 camera_ray(v3 eye, v3 at, float fovy, double mx, double my, int ww, int wh);

#endif
