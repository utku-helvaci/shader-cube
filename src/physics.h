// SPDX-License-Identifier: MIT
/*
 * Rigid-body debris simulated by NVIDIA PhysX.  On an NVIDIA GPU the scene
 * runs PhysX's CUDA pipeline (GPU broad phase + GPU dynamics); otherwise the
 * CPU solver.  The bouncing cube and the light are kinematic bodies that
 * plough through the debris.  physics_none.c stands in when the program is
 * built without PhysX.
 */
#ifndef PHYSICS_H
#define PHYSICS_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Phys Phys;

enum { PHYS_CUBE = 0, PHYS_LIGHT = 1 };

typedef struct {
    float room_half[3];
    float cube_half, light_radius;
    int debris;     /* number of debris bodies */
    int gpu;        /* use the CUDA pipeline (falls back to CPU if unavailable) */
    unsigned seed;
} PhysDesc;

int phys_available(void);
/* NULL on failure; `info` describes what was created (or why not). */
Phys *phys_create(const PhysDesc *d, char *info, int infolen);
int phys_on_gpu(const Phys *p);
void phys_set_kinematic(Phys *p, int which, const float pos[3], const float quat_wxyz[4]);
void phys_step(Phys *p, float dt);
/* 12 floats per body: pos.xyz, material; rotation quaternion xyzw; half extents xyz, 0.
 * Returns the number of bodies written. */
int phys_debris(Phys *p, float *out);
/* Outward + upward kick from `center`. */
void phys_blast(Phys *p, const float center[3], float strength);
void phys_destroy(Phys *p);

#ifdef __cplusplus
}
#endif

#endif
