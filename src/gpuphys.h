// SPDX-License-Identifier: MIT
/*
 * The compute-shader physics engine: an alternative to PhysX for the Galton
 * board's balls, running entirely on the GPU through gfx compute shaders
 * (OpenGL 4.3, OpenGL ES 3.1, Vulkan).  Position-based dynamics with
 * substeps: balls are binned into a uniform grid with atomics, overlaps are
 * resolved with Jacobi iterations, statics (boxes, pegs) are pushed out of,
 * and velocities follow from the corrected positions, with restitution and
 * Coulomb friction against the statics.  Balls that come to rest in the bins
 * freeze and act as static support, which keeps tall piles stable.
 *
 * It is made for the board: balls move between two glass panes, so the
 * statics are 2D shapes extruded along z and the panes are z limits.
 */
#ifndef GPUPHYS_H
#define GPUPHYS_H

#include "gfx.h"
#include "physics.h"

typedef struct GpuPhys GpuPhys;

typedef struct {
    const PhysShape *shapes; /* glass panes among them are skipped: zhalf is the pane gap */
    int nshapes, gate;
    const float *ball_pos, *ball_key;
    int nballs;
    float radius, gravity, restitution;
    float friction;     /* of the pins (circles); the walls are slippery */
    float pin_damping;  /* rolling losses while touching a pin, 1/s */
    float zhalf;        /* half the gap between the panes */
    float freeze_y;     /* balls resting below this freeze */
    float bounds[4];    /* region the balls stay in: xmin, ymin, xmax, ymax */
} GpuPhysDesc;

/* NULL when compute shaders are unavailable (OpenGL ES 3.0); `info` says. */
GpuPhys *gpuphys_create(const GpuPhysDesc *d, char *info, int infolen);
void gpuphys_open_gate(GpuPhys *g);                 /* outside passes */
void gpuphys_tune(GpuPhys *g, float gravity, float restitution, float friction);
void gpuphys_step(GpuPhys *g, float dt, int substeps); /* records compute work: inside a frame */
GfxBuf *gpuphys_instances(GpuPhys *g);              /* GFX_INST_STRIDE per ball, for instanced draws */
void gpuphys_destroy(GpuPhys *g);

#endif
