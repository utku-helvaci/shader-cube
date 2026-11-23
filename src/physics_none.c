// SPDX-License-Identifier: MIT
/* Used when shader-cube is built without the PhysX SDK (see tools/build_physx.sh). */
#include <stdio.h>

#include "physics.h"

int phys_available(void) { return 0; }

Phys *phys_create(const PhysDesc *d, char *info, int infolen) {
    (void)d;
    snprintf(info, (size_t)infolen, "built without PhysX (run tools/build_physx.sh, then make)");
    return NULL;
}

int phys_on_gpu(const Phys *p) { (void)p; return 0; }
void phys_set_kinematic(Phys *p, int which, const float pos[3], const float q[4]) { (void)p; (void)which; (void)pos; (void)q; }
void phys_step(Phys *p, float dt) { (void)p; (void)dt; }
int phys_debris(Phys *p, float *out) { (void)p; (void)out; return 0; }
void phys_blast(Phys *p, const float c[3], float s) { (void)p; (void)c; (void)s; }
void phys_destroy(Phys *p) { (void)p; }
