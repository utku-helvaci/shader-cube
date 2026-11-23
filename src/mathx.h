// SPDX-License-Identifier: MIT
/* Minimal column-major vector / matrix / quaternion helpers. */
#ifndef MATHX_H
#define MATHX_H

#include <math.h>
#include <string.h>

typedef struct { float x, y, z; } v3;
typedef struct { float m[16]; } m4; /* column-major, m[col*4+row] */
typedef struct { float w, x, y, z; } quat;

static inline v3 V3(float x, float y, float z) { v3 r = {x, y, z}; return r; }
static inline v3 v3add(v3 a, v3 b) { return V3(a.x + b.x, a.y + b.y, a.z + b.z); }
static inline v3 v3sub(v3 a, v3 b) { return V3(a.x - b.x, a.y - b.y, a.z - b.z); }
static inline v3 v3scale(v3 a, float s) { return V3(a.x * s, a.y * s, a.z * s); }
static inline float v3dot(v3 a, v3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static inline v3 v3cross(v3 a, v3 b) {
    return V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
static inline float v3len(v3 a) { return sqrtf(v3dot(a, a)); }
static inline v3 v3norm(v3 a) { float l = v3len(a); return l > 0 ? v3scale(a, 1.0f / l) : a; }

static inline m4 m4identity(void) {
    m4 r; memset(&r, 0, sizeof r);
    r.m[0] = r.m[5] = r.m[10] = r.m[15] = 1.0f;
    return r;
}

static inline m4 m4mul(m4 a, m4 b) {
    m4 r;
    for (int c = 0; c < 4; c++)
        for (int rr = 0; rr < 4; rr++) {
            float s = 0;
            for (int k = 0; k < 4; k++) s += a.m[k * 4 + rr] * b.m[c * 4 + k];
            r.m[c * 4 + rr] = s;
        }
    return r;
}

static inline m4 m4perspective(float fovy, float aspect, float n, float f) {
    float t = 1.0f / tanf(fovy * 0.5f);
    m4 r; memset(&r, 0, sizeof r);
    r.m[0] = t / aspect;
    r.m[5] = t;
    r.m[10] = (f + n) / (n - f);
    r.m[11] = -1.0f;
    r.m[14] = 2.0f * f * n / (n - f);
    return r;
}

static inline m4 m4lookat(v3 eye, v3 at, v3 up) {
    v3 f = v3norm(v3sub(at, eye));
    v3 s = v3norm(v3cross(f, up));
    v3 u = v3cross(s, f);
    m4 r = m4identity();
    r.m[0] = s.x; r.m[4] = s.y; r.m[8] = s.z;
    r.m[1] = u.x; r.m[5] = u.y; r.m[9] = u.z;
    r.m[2] = -f.x; r.m[6] = -f.y; r.m[10] = -f.z;
    r.m[12] = -v3dot(s, eye);
    r.m[13] = -v3dot(u, eye);
    r.m[14] = v3dot(f, eye);
    return r;
}

static inline quat qmul(quat a, quat b) {
    quat r = {
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    };
    return r;
}

static inline quat qnorm(quat q) {
    float l = sqrtf(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z);
    quat r = {q.w / l, q.x / l, q.y / l, q.z / l};
    return r;
}

/* Integrate world-space angular velocity w over dt. */
static inline quat qintegrate(quat q, v3 w, float dt) {
    quat wq = {0, w.x, w.y, w.z};
    quat d = qmul(wq, q);
    quat r = {q.w + 0.5f * dt * d.w, q.x + 0.5f * dt * d.x,
              q.y + 0.5f * dt * d.y, q.z + 0.5f * dt * d.z};
    return qnorm(r);
}

/* Rotation matrix (3x3, column-major, columns = local axes in world). */
static inline void qtomat3(quat q, float r[9]) {
    float w = q.w, x = q.x, y = q.y, z = q.z;
    r[0] = 1 - 2 * (y * y + z * z); r[1] = 2 * (x * y + w * z);     r[2] = 2 * (x * z - w * y);
    r[3] = 2 * (x * y - w * z);     r[4] = 1 - 2 * (x * x + z * z); r[5] = 2 * (y * z + w * x);
    r[6] = 2 * (x * z + w * y);     r[7] = 2 * (y * z - w * x);     r[8] = 1 - 2 * (x * x + y * y);
}

/* model = T(p) * R * S(s); also returns its inverse. */
static inline void m4trs(v3 p, const float R[9], float s, m4 *model, m4 *inv) {
    m4 a = m4identity();
    for (int c = 0; c < 3; c++)
        for (int r = 0; r < 3; r++) a.m[c * 4 + r] = R[c * 3 + r] * s;
    a.m[12] = p.x; a.m[13] = p.y; a.m[14] = p.z;
    *model = a;

    m4 b = m4identity(); /* inv = S^-1 R^T T^-1 */
    float is = 1.0f / s;
    for (int c = 0; c < 3; c++)
        for (int r = 0; r < 3; r++) b.m[c * 4 + r] = R[r * 3 + c] * is;
    for (int r = 0; r < 3; r++)
        b.m[12 + r] = -(b.m[0 + r] * p.x + b.m[4 + r] * p.y + b.m[8 + r] * p.z);
    *inv = b;
}

#endif
