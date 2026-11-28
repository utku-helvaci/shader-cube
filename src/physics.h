// SPDX-License-Identifier: MIT
/*
 * NVIDIA PhysX for both scenes.  On an NVIDIA GPU a world runs PhysX's CUDA
 * pipeline (GPU broad phase + GPU dynamics); otherwise the CPU solver.
 *
 *  - Phys: the cube scene's debris.  The bouncing cube and the light are
 *    kinematic bodies that plough through it.
 *  - PhysBalls: the Galton board.  Static boxes and z-axis capsules (the
 *    pegs: cylinders between the glass panes), dynamic spheres.
 *
 * physics_physx.cpp implements this; physics_none.c stands in when the
 * program is built without PhysX.  On Windows the program is built with
 * MinGW and PhysX with MSVC, so PhysX lives in shader-cube-physx.dll (built
 * from physics_physx.cpp, exporting exactly these functions) and
 * physics_dll.c loads it at runtime.
 */
#ifndef PHYSICS_H
#define PHYSICS_H

#if defined(_WIN32) && defined(PHYS_DLL_EXPORT)
#define PHYS_API __declspec(dllexport)
#else
#define PHYS_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ---- debris (cube scene) */

typedef struct Phys Phys;

enum { PHYS_CUBE = 0, PHYS_LIGHT = 1 };

typedef struct {
    float room_half[3];
    float cube_half, light_radius;
    int debris;     /* number of debris bodies */
    int gpu;        /* use the CUDA pipeline (falls back to CPU if unavailable) */
    unsigned seed;
} PhysDesc;

PHYS_API int phys_available(void);
/* NULL on failure; `info` describes what was created (or why not). */
PHYS_API Phys *phys_create(const PhysDesc *d, char *info, int infolen);
PHYS_API int phys_on_gpu(const Phys *p);
PHYS_API void phys_set_kinematic(Phys *p, int which, const float pos[3], const float quat_wxyz[4]);
PHYS_API void phys_step(Phys *p, float dt);
/* 12 floats per body: pos.xyz, material; rotation quaternion xyzw; half extents xyz, 0.
 * Returns the number of bodies written. */
PHYS_API int phys_debris(Phys *p, float *out);
/* Outward + upward kick from `center`. */
PHYS_API void phys_blast(Phys *p, const float center[3], float strength);
PHYS_API void phys_destroy(Phys *p);

/* ---- balls (Galton board) */

typedef struct PhysBalls PhysBalls;

enum { PHYS_BOX = 0, PHYS_CAPSULE_Z = 1 };

typedef struct {
    int type;
    float pos[3];
    float angle;   /* rotation about z, radians */
    float half[3]; /* box: half extents; capsule: radius, half length along z */
    int glass;     /* a glass pane (the compute engine handles these as z limits) */
} PhysShape;

typedef struct {
    const PhysShape *shapes; /* static */
    int nshapes;
    int gate;                /* shapes[gate] is removed by open_gate (-1: none) */
    const float *ball_pos;   /* nballs * 3 */
    const float *ball_key;   /* nballs: passed through to the instance data (colour) */
    int nballs;
    float radius, gravity, restitution;
    float friction;          /* of the pins (capsules); the boxes are slippery */
    int gpu;
} PhysBallsDesc;

PHYS_API PhysBalls *phys_balls_create(const PhysBallsDesc *d, char *info, int infolen);
PHYS_API int phys_balls_on_gpu(const PhysBalls *p);
PHYS_API void phys_balls_open_gate(PhysBalls *p);
PHYS_API void phys_balls_tune(PhysBalls *p, float gravity, float restitution, float friction);
PHYS_API void phys_balls_step(PhysBalls *p, float dt);
/* 12 floats per ball, as phys_debris: pos.xyz, key; rotation xyzw; radius x3, 0. */
PHYS_API int phys_balls_read(PhysBalls *p, float *out);
PHYS_API void phys_balls_destroy(PhysBalls *p);

#ifdef __cplusplus
}
#endif

#endif
