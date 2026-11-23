// SPDX-License-Identifier: MIT
/*
 * NVIDIA PhysX backend for physics.h.
 *
 * With `gpu` set and a working CUDA device the scene uses the GPU pipeline:
 * PxSceneFlag::eENABLE_GPU_DYNAMICS + PxBroadPhaseType::eGPU, i.e. broad
 * phase, contact generation and the solver all run as CUDA kernels in
 * libPhysXGpu_64.so.  PHYSX_GPU_DEVICE picks the CUDA device (default 0).
 */
#include <PxPhysicsAPI.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>

#include "physics.h"

using namespace physx;

namespace {

struct ErrorCallback : PxErrorCallback {
    void reportError(PxErrorCode::Enum code, const char *msg, const char *file, int line) override {
        if (code == PxErrorCode::eDEBUG_INFO) return;
        fprintf(stderr, "PhysX: %s (%s:%d)\n", msg, file, line);
    }
};

PxDefaultAllocator g_alloc;
ErrorCallback g_err;
PxFoundation *g_foundation; /* one per process */

struct Rng {
    unsigned s;
    float next() {
        s = s * 1664525u + 1013904223u;
        return (float)(s >> 8) / 16777216.0f;
    }
    float range(float a, float b) { return a + (b - a) * next(); }
};

} // namespace

struct Phys {
    PxPhysics *physics;
    PxDefaultCpuDispatcher *dispatcher;
    PxCudaContextManager *cuda;
    PxScene *scene;
    PxMaterial *mat;
    PxRigidDynamic *kin[2];
    PxRigidDynamic **body;
    float *shape; /* per body: half extents xyz, material */
    int n;
    Rng rng;
};

extern "C" int phys_available(void) { return 1; }

static PxScene *make_scene(Phys *p, bool gpu) {
    PxSceneDesc sd(p->physics->getTolerancesScale());
    sd.gravity = PxVec3(0.0f, -9.8f, 0.0f);
    sd.cpuDispatcher = p->dispatcher;
    sd.filterShader = PxDefaultSimulationFilterShader;
    if (gpu) {
        sd.cudaContextManager = p->cuda;
        sd.flags |= PxSceneFlag::eENABLE_GPU_DYNAMICS;
        sd.broadPhaseType = PxBroadPhaseType::eGPU;
    }
    return p->physics->createScene(sd);
}

extern "C" Phys *phys_create(const PhysDesc *d, char *info, int infolen) {
    if (!g_foundation) g_foundation = PxCreateFoundation(PX_PHYSICS_VERSION, g_alloc, g_err);
    if (!g_foundation) {
        snprintf(info, (size_t)infolen, "PxCreateFoundation failed");
        return nullptr;
    }
    Phys *p = (Phys *)calloc(1, sizeof(Phys));
    p->rng.s = d->seed ? d->seed : 0x5EEDu;
    PxTolerancesScale scale;
    p->physics = PxCreatePhysics(PX_PHYSICS_VERSION, *g_foundation, scale);
    if (!p->physics) {
        snprintf(info, (size_t)infolen, "PxCreatePhysics failed");
        free(p);
        return nullptr;
    }

    char why[160] = "";
    if (d->gpu) {
        PxCudaContextManagerDesc cd;
        p->cuda = PxCreateCudaContextManager(*g_foundation, cd);
        if (p->cuda && !p->cuda->contextIsValid()) {
            p->cuda->release();
            p->cuda = nullptr;
        }
        if (!p->cuda) snprintf(why, sizeof why, " (CUDA unavailable, fell back to CPU)");
    }
    unsigned hw = std::thread::hardware_concurrency();
    PxU32 threads = hw > 8 ? 4 : hw > 2 ? 2 : 1;
    p->dispatcher = PxDefaultCpuDispatcherCreate(threads);
    p->scene = make_scene(p, p->cuda != nullptr);
    if (!p->scene && p->cuda) {
        p->cuda->release();
        p->cuda = nullptr;
        snprintf(why, sizeof why, " (GPU scene creation failed, fell back to CPU)");
        p->scene = make_scene(p, false);
    }
    if (!p->scene) {
        snprintf(info, (size_t)infolen, "createScene failed");
        phys_destroy(p);
        return nullptr;
    }

    p->mat = p->physics->createMaterial(0.55f, 0.45f, 0.3f);

    /* Room: six planes, normals pointing inwards. */
    for (int a = 0; a < 3; a++)
        for (int s = -1; s <= 1; s += 2) {
            PxVec3 n(0, 0, 0);
            n[(PxU32)a] = (float)-s;
            p->scene->addActor(*PxCreatePlane(*p->physics, PxPlane(n, d->room_half[a]), *p->mat));
        }

    /* The cube and the light are driven by the app: kinematic bodies. */
    PxGeometryHolder kg[2] = {PxBoxGeometry(d->cube_half, d->cube_half, d->cube_half),
                              PxSphereGeometry(d->light_radius)};
    for (int k = 0; k < 2; k++) {
        p->kin[k] = p->physics->createRigidDynamic(PxTransform(PxVec3(0, 100.0f + 10.0f * (float)k, 0)));
        PxRigidActorExt::createExclusiveShape(*p->kin[k], kg[k].any(), *p->mat);
        p->kin[k]->setRigidBodyFlag(PxRigidBodyFlag::eKINEMATIC, true);
        p->scene->addActor(*p->kin[k]);
    }

    /* Debris: bricks on a shuffled jittered grid in the air, so they rain
     * down at start-up, keeping clear of where the cube and light begin. */
    const float cell = 0.5f;
    int nx = (int)((2.0f * d->room_half[0] - 0.8f) / cell), nz = (int)((2.0f * d->room_half[2] - 0.8f) / cell);
    int layers = 1 + d->debris / (nx * nz > 0 ? nx * nz : 1);
    int ncells = nx * nz * (layers + 2);
    int *cells = (int *)malloc(sizeof(int) * (size_t)ncells);
    int nc = 0;
    for (int i = 0; i < nx * nz * (layers + 2); i++) {
        int ix = i % nx, iz = (i / nx) % nz, iy = i / (nx * nz);
        float x = -d->room_half[0] + 0.4f + (ix + 0.5f) * cell, z = -d->room_half[2] + 0.4f + (iz + 0.5f) * cell;
        float y = -d->room_half[1] + 1.2f + (float)iy * cell;
        float dc = sqrtf(x * x + (y - 1.5f) * (y - 1.5f) + z * z);
        float dl = sqrtf((x + 4) * (x + 4) + (y - 3) * (y - 3) + (z - 3) * (z - 3));
        if (dc > 2.6f && dl > 0.9f) cells[nc++] = i;
    }
    for (int i = nc - 1; i > 0; i--) { /* Fisher-Yates */
        int j = (int)(p->rng.next() * (float)(i + 1)) % (i + 1);
        int t = cells[i]; cells[i] = cells[j]; cells[j] = t;
    }
    p->n = d->debris < nc ? d->debris : nc;
    p->body = (PxRigidDynamic **)calloc((size_t)(p->n ? p->n : 1), sizeof *p->body);
    p->shape = (float *)calloc((size_t)(p->n ? p->n : 1) * 4, sizeof(float));
    PxActor **actors = (PxActor **)malloc(sizeof(PxActor *) * (size_t)(p->n ? p->n : 1));
    for (int b = 0; b < p->n; b++) {
        int i = cells[b];
        int ix = i % nx, iz = (i / nx) % nz, iy = i / (nx * nz);
        PxVec3 pos(-d->room_half[0] + 0.4f + (ix + p->rng.range(0.3f, 0.7f)) * cell,
                   -d->room_half[1] + 1.2f + (float)iy * cell,
                   -d->room_half[2] + 0.4f + (iz + p->rng.range(0.3f, 0.7f)) * cell);
        PxVec3 axis(p->rng.range(-1, 1), p->rng.range(-1, 1), p->rng.range(-1, 1));
        PxQuat rot = axis.magnitude() > 1e-3f ? PxQuat(p->rng.range(0, 6.2831853f), axis.getNormalized())
                                               : PxQuat(PxIdentity);
        PxVec3 he(p->rng.range(0.05f, 0.16f), p->rng.range(0.05f, 0.12f), p->rng.range(0.05f, 0.16f));
        PxRigidDynamic *body = p->physics->createRigidDynamic(PxTransform(pos, rot));
        PxRigidActorExt::createExclusiveShape(*body, PxBoxGeometry(he), *p->mat);
        PxRigidBodyExt::updateMassAndInertia(*body, 600.0f);
        body->setRigidBodyFlag(PxRigidBodyFlag::eENABLE_SPECULATIVE_CCD, true);
        body->setMaxDepenetrationVelocity(3.0f);
        body->setAngularDamping(0.15f);
        body->setSolverIterationCounts(6, 1);
        p->body[b] = body;
        p->shape[b * 4 + 0] = he.x;
        p->shape[b * 4 + 1] = he.y;
        p->shape[b * 4 + 2] = he.z;
        p->shape[b * 4 + 3] = (float)((int)(p->rng.next() * 4.0f) & 3);
        actors[b] = body;
    }
    if (p->n) p->scene->addActors(actors, (PxU32)p->n);
    free(actors);
    free(cells);

    if (p->cuda)
        snprintf(info, (size_t)infolen, "PhysX %d.%d.%d: %d bodies on the GPU (CUDA: %s, %d SMs)",
                 PX_PHYSICS_VERSION_MAJOR, PX_PHYSICS_VERSION_MINOR, PX_PHYSICS_VERSION_BUGFIX, p->n,
                 p->cuda->getDeviceName(), p->cuda->getMultiprocessorCount());
    else
        snprintf(info, (size_t)infolen, "PhysX %d.%d.%d: %d bodies on the CPU (%u threads)%s",
                 PX_PHYSICS_VERSION_MAJOR, PX_PHYSICS_VERSION_MINOR, PX_PHYSICS_VERSION_BUGFIX, p->n,
                 (unsigned)threads, why);
    return p;
}

extern "C" int phys_on_gpu(const Phys *p) { return p && p->cuda; }

extern "C" void phys_set_kinematic(Phys *p, int which, const float pos[3], const float q[4]) {
    if (!p) return;
    p->kin[which]->setKinematicTarget(PxTransform(PxVec3(pos[0], pos[1], pos[2]), PxQuat(q[1], q[2], q[3], q[0])));
}

extern "C" void phys_step(Phys *p, float dt) {
    if (!p) return;
    p->scene->simulate(dt);
    p->scene->fetchResults(true);
}

extern "C" int phys_debris(Phys *p, float *out) {
    if (!p) return 0;
    for (int b = 0; b < p->n; b++) {
        PxTransform t = p->body[b]->getGlobalPose();
        float *o = out + b * 12;
        o[0] = t.p.x; o[1] = t.p.y; o[2] = t.p.z; o[3] = p->shape[b * 4 + 3];
        o[4] = t.q.x; o[5] = t.q.y; o[6] = t.q.z; o[7] = t.q.w;
        o[8] = p->shape[b * 4 + 0]; o[9] = p->shape[b * 4 + 1]; o[10] = p->shape[b * 4 + 2]; o[11] = 0.0f;
    }
    return p->n;
}

extern "C" void phys_blast(Phys *p, const float c[3], float strength) {
    if (!p) return;
    for (int b = 0; b < p->n; b++) {
        PxRigidDynamic *body = p->body[b];
        PxVec3 d = body->getGlobalPose().p - PxVec3(c[0], c[1], c[2]);
        float dist = d.magnitude();
        PxVec3 dir = (dist > 1e-3f ? d / dist : PxVec3(0, 1, 0)) * 0.7f + PxVec3(0, 1.0f, 0);
        float s = strength * p->rng.range(0.6f, 1.2f) / (1.0f + 0.25f * dist);
        body->addForce(dir * s, PxForceMode::eVELOCITY_CHANGE);
        body->addTorque(PxVec3(p->rng.range(-1, 1), p->rng.range(-1, 1), p->rng.range(-1, 1)) * 12.0f,
                        PxForceMode::eVELOCITY_CHANGE);
    }
}

extern "C" void phys_destroy(Phys *p) {
    if (!p) return;
    if (p->scene) p->scene->release();
    if (p->dispatcher) p->dispatcher->release();
    if (p->cuda) p->cuda->release();
    if (p->physics) p->physics->release();
    free(p->body);
    free(p->shape);
    free(p);
    if (g_foundation) {
        g_foundation->release();
        g_foundation = nullptr;
    }
}
