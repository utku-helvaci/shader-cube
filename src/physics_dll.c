// SPDX-License-Identifier: MIT
/*
 * Windows: the program is built with MinGW, PhysX with MSVC, so PhysX and
 * physics_physx.cpp live in shader-cube-physx.dll (next to the executable)
 * and this file forwards physics.h to it.  Without the DLL the program
 * still runs: PhysX is reported as unavailable and the Galton board uses
 * the compute-shader engine.
 */
#include "physics.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdio.h>
#include <string.h>

static HMODULE g_dll;
static int g_tried;
static char g_why[600];

static struct {
    int (*available)(void);
    Phys *(*create)(const PhysDesc *, char *, int);
    int (*on_gpu)(const Phys *);
    void (*set_kinematic)(Phys *, int, const float *, const float *);
    void (*step)(Phys *, float);
    int (*debris)(Phys *, float *);
    void (*blast)(Phys *, const float *, float);
    void (*destroy)(Phys *);
    PhysBalls *(*balls_create)(const PhysBallsDesc *, char *, int);
    int (*balls_on_gpu)(const PhysBalls *);
    void (*balls_open_gate)(PhysBalls *);
    void (*balls_tune)(PhysBalls *, float, float, float);
    void (*balls_step)(PhysBalls *, float);
    int (*balls_read)(PhysBalls *, float *);
    void (*balls_destroy)(PhysBalls *);
} F;

static int get(void *field, const char *name) {
    FARPROC f = GetProcAddress(g_dll, name);
    memcpy(field, &f, sizeof f);
    return f != NULL;
}

static int load(void) {
    if (g_tried) return g_dll != NULL;
    g_tried = 1;
    char path[MAX_PATH + 32];
    DWORD n = GetModuleFileNameA(NULL, path, MAX_PATH);
    char *slash = n ? strrchr(path, '\\') : NULL;
    snprintf(slash ? slash + 1 : path, sizeof path - (size_t)(slash ? slash + 1 - path : 0), "shader-cube-physx.dll");
    g_dll = LoadLibraryA(path);
    if (!g_dll) {
        snprintf(g_why, sizeof g_why, "PhysX unavailable: %s not found (error %lu)", path, (unsigned long)GetLastError());
        return 0;
    }
    int ok = get(&F.available, "phys_available") && get(&F.create, "phys_create") && get(&F.on_gpu, "phys_on_gpu") &&
             get(&F.set_kinematic, "phys_set_kinematic") && get(&F.step, "phys_step") &&
             get(&F.debris, "phys_debris") && get(&F.blast, "phys_blast") && get(&F.destroy, "phys_destroy") &&
             get(&F.balls_create, "phys_balls_create") && get(&F.balls_on_gpu, "phys_balls_on_gpu") &&
             get(&F.balls_open_gate, "phys_balls_open_gate") && get(&F.balls_tune, "phys_balls_tune") &&
             get(&F.balls_step, "phys_balls_step") && get(&F.balls_read, "phys_balls_read") &&
             get(&F.balls_destroy, "phys_balls_destroy");
    if (!ok) {
        snprintf(g_why, sizeof g_why, "PhysX unavailable: %s is from another version", path);
        FreeLibrary(g_dll);
        g_dll = NULL;
        memset(&F, 0, sizeof F);
        return 0;
    }
    return 1;
}

int phys_available(void) { return load() && F.available(); }

Phys *phys_create(const PhysDesc *d, char *info, int infolen) {
    if (!load()) {
        snprintf(info, (size_t)infolen, "%s", g_why);
        return NULL;
    }
    return F.create(d, info, infolen);
}

int phys_on_gpu(const Phys *p) { return p && F.on_gpu(p); }
void phys_set_kinematic(Phys *p, int which, const float pos[3], const float q[4]) { if (p) F.set_kinematic(p, which, pos, q); }
void phys_step(Phys *p, float dt) { if (p) F.step(p, dt); }
int phys_debris(Phys *p, float *out) { return p ? F.debris(p, out) : 0; }
void phys_blast(Phys *p, const float c[3], float s) { if (p) F.blast(p, c, s); }
void phys_destroy(Phys *p) { if (p) F.destroy(p); }

PhysBalls *phys_balls_create(const PhysBallsDesc *d, char *info, int infolen) {
    if (!load()) {
        snprintf(info, (size_t)infolen, "%s", g_why);
        return NULL;
    }
    return F.balls_create(d, info, infolen);
}

int phys_balls_on_gpu(const PhysBalls *p) { return p && F.balls_on_gpu(p); }
void phys_balls_open_gate(PhysBalls *p) { if (p) F.balls_open_gate(p); }
void phys_balls_tune(PhysBalls *p, float g, float e, float f) { if (p) F.balls_tune(p, g, e, f); }
void phys_balls_step(PhysBalls *p, float dt) { if (p) F.balls_step(p, dt); }
int phys_balls_read(PhysBalls *p, float *out) { return p ? F.balls_read(p, out) : 0; }
void phys_balls_destroy(PhysBalls *p) { if (p) F.balls_destroy(p); }
