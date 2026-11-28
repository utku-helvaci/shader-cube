// SPDX-License-Identifier: MIT
/*
 * NVIDIA PhysX backend for physics.h.
 *
 * With `gpu` set and a working CUDA device a world uses the GPU pipeline:
 * PxSceneFlag::eENABLE_GPU_DYNAMICS + PxBroadPhaseType::eGPU, i.e. broad
 * phase, contact generation and the solver all run as CUDA kernels in
 * libPhysXGpu_64.so (PhysXGpu_64.dll).  PHYSX_GPU_DEVICE picks the CUDA
 * device (default 0).
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
PxFoundation *g_foundation; /* one per process, shared by the worlds */
int g_foundation_refs;

bool foundation_acquire() {
    if (!g_foundation) g_foundation = PxCreateFoundation(PX_PHYSICS_VERSION, g_alloc, g_err);
    if (!g_foundation) return false;
    g_foundation_refs++;
    return true;
}

void foundation_release() {
    if (g_foundation_refs > 0 && --g_foundation_refs == 0) {
        g_foundation->release();
        g_foundation = nullptr;
    }
}

/* A CUDA context for GPU dynamics, or null (`why` says what went wrong). */
PxCudaContextManager *make_cuda(char *why, size_t n) {
    PxCudaContextManagerDesc cd;
    PxCudaContextManager *cuda = PxCreateCudaContextManager(*g_foundation, cd);
    if (cuda && !cuda->contextIsValid()) {
        cuda->release();
        cuda = nullptr;
    }
    if (!cuda) snprintf(why, n, " (CUDA unavailable, fell back to CPU)");
    return cuda;
}

PxU32 cpu_threads() {
    unsigned hw = std::thread::hardware_concurrency();
    return hw > 8 ? 4 : hw > 2 ? 2 : 1;
}

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
    if (!foundation_acquire()) {
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
        foundation_release();
        return nullptr;
    }

    char why[160] = "";
    if (d->gpu) p->cuda = make_cuda(why, sizeof why);
    PxU32 threads = cpu_threads();
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
    foundation_release();
}

/* ---------------------------------------------------------------- balls (Galton board) */

struct PhysBalls {
    PxPhysics *physics;
    PxDefaultCpuDispatcher *dispatcher;
    PxCudaContextManager *cuda;
    PxScene *scene;
    PxMaterial *mat, *wall_mat, *ball_mat, *glass_mat;
    PxRigidStatic *frame;
    PxShape *gate;
    PxRigidDynamic **ball;
    float *key;
    int n;
    float radius;
};

extern "C" PhysBalls *phys_balls_create(const PhysBallsDesc *d, char *info, int infolen) {
    if (!foundation_acquire()) {
        snprintf(info, (size_t)infolen, "PxCreateFoundation failed");
        return nullptr;
    }
    PhysBalls *p = (PhysBalls *)calloc(1, sizeof(PhysBalls));
    p->n = d->nballs;
    p->radius = d->radius;
    p->physics = PxCreatePhysics(PX_PHYSICS_VERSION, *g_foundation, PxTolerancesScale());
    if (!p->physics) {
        snprintf(info, (size_t)infolen, "PxCreatePhysics failed");
        free(p);
        foundation_release();
        return nullptr;
    }
    char why[160] = "";
    if (d->gpu) p->cuda = make_cuda(why, sizeof why);
    PxU32 threads = cpu_threads();
    p->dispatcher = PxDefaultCpuDispatcherCreate(threads);

    for (int attempt = 0; attempt < 2 && !p->scene; attempt++) {
        PxSceneDesc sd(p->physics->getTolerancesScale());
        sd.gravity = PxVec3(0.0f, -d->gravity, 0.0f);
        sd.cpuDispatcher = p->dispatcher;
        sd.filterShader = PxDefaultSimulationFilterShader;
        sd.solverType = PxSolverType::eTGS; /* steadier piles */
        if (p->cuda) {
            sd.cudaContextManager = p->cuda;
            sd.flags |= PxSceneFlag::eENABLE_GPU_DYNAMICS;
            sd.broadPhaseType = PxBroadPhaseType::eGPU;
            /* room for every ball touching several others in the bins */
            sd.gpuDynamicsConfig.maxRigidContactCount = 1u << 21;
            sd.gpuDynamicsConfig.maxRigidPatchCount = 1u << 19;
        }
        p->scene = p->physics->createScene(sd);
        if (!p->scene && p->cuda) {
            p->cuda->release();
            p->cuda = nullptr;
            snprintf(why, sizeof why, " (GPU scene creation failed, fell back to CPU)");
        }
    }
    if (!p->scene) {
        snprintf(info, (size_t)infolen, "createScene failed");
        phys_balls_destroy(p);
        return nullptr;
    }
    /* What makes the board a Galton board: a ball that hits a pin loses
     * most of its speed (friction turns it into spin, which the angular
     * damping takes away), so it drops off one side or the other instead of
     * carrying on sideways.  The walls, the funnel and the dividers are
     * slippery; the balls barely rub on each other (so they don't arch over
     * the outlet).  The board's materials win over the balls' (MAX). */
    p->mat = p->physics->createMaterial(d->friction, d->friction * 0.8f, d->restitution);
    p->mat->setFrictionCombineMode(PxCombineMode::eMAX);
    p->mat->setRestitutionCombineMode(PxCombineMode::eMAX); /* over the balls' MIN */
    p->wall_mat = p->physics->createMaterial(0.1f, 0.08f, d->restitution);
    p->wall_mat->setFrictionCombineMode(PxCombineMode::eMAX);
    p->wall_mat->setRestitutionCombineMode(PxCombineMode::eMAX);
    p->ball_mat = p->physics->createMaterial(0.02f, 0.02f, 0.0f); /* a crowd of balls doesn't spray */
    p->ball_mat->setRestitutionCombineMode(PxCombineMode::eMIN);
    /* The panes only hold the balls in their plane: no friction, no bounce. */
    p->glass_mat = p->physics->createMaterial(0.0f, 0.0f, 0.0f);
    p->glass_mat->setFrictionCombineMode(PxCombineMode::eMIN);
    p->glass_mat->setRestitutionCombineMode(PxCombineMode::eMIN);

    /* Everything static is one actor: boxes, and capsules turned to lie
     * along z (PhysX capsules lie along x), which are the pegs. */
    p->frame = p->physics->createRigidStatic(PxTransform(PxIdentity));
    const float offset = d->radius * 0.4f;
    for (int i = 0; i < d->nshapes; i++) {
        const PhysShape *s = &d->shapes[i];
        PxQuat rz(s->angle, PxVec3(0, 0, 1));
        PxShape *shape;
        PxMaterial *m = s->glass ? p->glass_mat : s->type == PHYS_CAPSULE_Z ? p->mat : p->wall_mat;
        if (s->type == PHYS_CAPSULE_Z)
            shape = PxRigidActorExt::createExclusiveShape(*p->frame, PxCapsuleGeometry(s->half[0], s->half[1]), *m);
        else
            shape = PxRigidActorExt::createExclusiveShape(*p->frame, PxBoxGeometry(s->half[0], s->half[1], s->half[2]), *m);
        PxQuat q = s->type == PHYS_CAPSULE_Z ? rz * PxQuat(PxHalfPi, PxVec3(0, 1, 0)) : rz;
        shape->setLocalPose(PxTransform(PxVec3(s->pos[0], s->pos[1], s->pos[2]), q));
        shape->setContactOffset(offset);
        shape->setRestOffset(0.0f);
        if (i == d->gate) p->gate = shape;
    }
    p->scene->addActor(*p->frame);

    p->ball = (PxRigidDynamic **)calloc((size_t)(p->n ? p->n : 1), sizeof *p->ball);
    p->key = (float *)calloc((size_t)(p->n ? p->n : 1), sizeof(float));
    PxActor **actors = (PxActor **)malloc(sizeof(PxActor *) * (size_t)(p->n ? p->n : 1));
    for (int b = 0; b < p->n; b++) {
        const float *x = d->ball_pos + b * 3;
        PxRigidDynamic *body = p->physics->createRigidDynamic(PxTransform(PxVec3(x[0], x[1], x[2])));
        PxShape *shape = PxRigidActorExt::createExclusiveShape(*body, PxSphereGeometry(d->radius), *p->ball_mat);
        shape->setContactOffset(offset);
        shape->setRestOffset(0.0f);
        PxRigidBodyExt::updateMassAndInertia(*body, 7800.0f); /* steel */
        body->setRigidBodyFlag(PxRigidBodyFlag::eENABLE_SPECULATIVE_CCD, true);
        body->setMaxDepenetrationVelocity(1.0f);
        body->setAngularDamping(150.0f); /* takes the spin a pin's friction gives (see the materials) */
        body->setSolverIterationCounts(4, 1);
        body->setSleepThreshold(0.0f); /* a ball that slows down in the hopper must not freeze an arch */
        p->ball[b] = body;
        p->key[b] = d->ball_key ? d->ball_key[b] : 0.0f;
        actors[b] = body;
    }
    if (p->n) p->scene->addActors(actors, (PxU32)p->n);
    free(actors);

    if (p->cuda)
        snprintf(info, (size_t)infolen, "PhysX %d.%d.%d: %d balls on the GPU (CUDA: %s)", PX_PHYSICS_VERSION_MAJOR,
                 PX_PHYSICS_VERSION_MINOR, PX_PHYSICS_VERSION_BUGFIX, p->n, p->cuda->getDeviceName());
    else
        snprintf(info, (size_t)infolen, "PhysX %d.%d.%d: %d balls on the CPU (%u threads)%s", PX_PHYSICS_VERSION_MAJOR,
                 PX_PHYSICS_VERSION_MINOR, PX_PHYSICS_VERSION_BUGFIX, p->n, (unsigned)threads, why);
    return p;
}

extern "C" int phys_balls_on_gpu(const PhysBalls *p) { return p && p->cuda; }

extern "C" void phys_balls_open_gate(PhysBalls *p) {
    if (!p || !p->gate) return;
    p->frame->detachShape(*p->gate);
    p->gate = nullptr;
    for (int b = 0; b < p->n; b++) p->ball[b]->wakeUp(); /* asleep on the gate */
}

extern "C" void phys_balls_tune(PhysBalls *p, float gravity, float restitution, float friction) {
    if (!p) return;
    p->scene->setGravity(PxVec3(0.0f, -gravity, 0.0f));
    p->mat->setRestitution(restitution);
    p->wall_mat->setRestitution(restitution);
    p->mat->setStaticFriction(friction);
    p->mat->setDynamicFriction(friction * 0.8f);
    for (int b = 0; b < p->n; b++) p->ball[b]->wakeUp();
}

extern "C" void phys_balls_step(PhysBalls *p, float dt) {
    if (!p) return;
    p->scene->simulate(dt);
    p->scene->fetchResults(true);
}

extern "C" int phys_balls_read(PhysBalls *p, float *out) {
    if (!p) return 0;
    for (int b = 0; b < p->n; b++) {
        PxTransform t = p->ball[b]->getGlobalPose();
        float *o = out + b * 12;
        o[0] = t.p.x; o[1] = t.p.y; o[2] = t.p.z; o[3] = p->key[b];
        o[4] = t.q.x; o[5] = t.q.y; o[6] = t.q.z; o[7] = t.q.w;
        o[8] = o[9] = o[10] = p->radius; o[11] = 0.0f;
    }
    return p->n;
}

extern "C" void phys_balls_destroy(PhysBalls *p) {
    if (!p) return;
    if (p->scene) p->scene->release();
    if (p->dispatcher) p->dispatcher->release();
    if (p->cuda) p->cuda->release();
    if (p->physics) p->physics->release();
    free(p->ball);
    free(p->key);
    free(p);
    foundation_release();
}
