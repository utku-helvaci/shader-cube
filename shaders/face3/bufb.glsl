// 相机与观者逻辑
// Camera and observer logic

// --------------------------------------------------------------------------------

// 读取 Shadertoy 键盘纹理中的按键状态。
bool isKeyPressed(int key) {
    return texelFetch(iChannel3, ivec2(key, 0), 0).x > 0.5;
}

// 围绕给定轴旋转视角。
mat3 rotAxis(vec3 axis, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    return mat3(
        oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
        oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
        oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c
    );
}

// =============================================================================
// 类时观者：事件、四速与 Fermi-Walker 标架
// =============================================================================
struct CameraEvent {
    vec4 X;
    vec4 U;
    vec4 E1;
    vec4 E2;
    vec4 E3;
};

float CameraRadius(vec3 p, float side) {
    float a = 0.5 * iSpin;
    float a2 = a * a;
    float b = dot(p, p) - a2;
    float d = sqrt(b * b + 4.0 * a2 * p.y * p.y);
    float r2 = b >= 0.0 ? 0.5 * (b + d)
        : (2.0 * a2 * p.y * p.y) / max(d - b, 1e-20);
    return side * sign(iBlackHoleMassSol) * sqrt(max(r2, 0.0));
}

void CameraMetric(vec4 X, float side, bool outgoing,
                   out mat4 g, out mat4 invg, out float r, out vec4 l) {
    float a = 0.5 * iSpin;
    float q2 = 0.25 * iQ2;
    r = CameraRadius(X.xyz, side);
    float r2 = r * r;
    float a2 = a * a;
    float yOverR = 0.0;
    if (abs(r) > 1e-7) yOverR = X.y / r;
    else if (abs(a) > 1e-10) {
        float u = dot(X.xyz, X.xyz) - a2;
        yOverR = sign(X.y >= 0.0 ? 1.0 : -1.0) * side * sign(iBlackHoleMassSol)
               * sqrt(max(0.0, r2 - u)) / abs(a);
    }
    float dir = outgoing ? -1.0 : 1.0;
    float inv = 1.0 / max(1e-20, r2 + a2);
    l = vec4((dir * r * X.x - a * X.z) * inv,
             dir * yOverR,
             (dir * r * X.z + a * X.x) * inv, 1.0);
    float f = (r * r2 - q2 * r2) / max(1e-20, r2 * r2 + a2 * X.y * X.y);
    vec4 lup = vec4(l.xyz, -1.0);
    mat4 eta = mat4(1.0);
    eta[3][3] = -1.0;
    g = eta + f * mat4(l * l.x, l * l.y, l * l.z, l * l.w);
    invg = eta - f * mat4(lup * lup.x, lup * lup.y, lup * lup.z, lup * lup.w);
}

// 能静止时尽量以静止观者为参照，接近无限红移面才转为 KS 时间切片的法向观者。
// KS 切片法向观者在两层视界之间仍为类时；内视界以内若允许静止，再切回静止参考。
vec4 CameraReferenceVelocity(mat4 g, vec4 l) {
    float f = 1.0 + g[3][3];
    vec4 reference;
    if (f <= 0.95) {
        reference = vec4(0.0, 0.0, 0.0, inversesqrt(1.0 - f));
    } else {
        float root = sqrt(1.0 + f);
        vec4 normal = vec4(-f * l.xyz / root, root);
        if (f >= 1.0) {
            reference = normal;
        } else {
            vec4 stationary = vec4(0.0, 0.0, 0.0,
                                   inversesqrt(1.0 - f));
            reference = mix(stationary, normal,
                            smoothstep(0.95, 1.0, f));
        }
    }
    return reference * inversesqrt(max(1e-12, -dot(reference, g * reference)));
}

// 对 Kerr-Schild 半径、度规和单位电磁势求空间导数。
// 相机世界线每个 RK4 子步都要用到它们，因此直接求导，避免重复采样六次度规。
void CameraMetricGradient(vec4 X, float r, vec4 l, bool outgoing,
                          vec3 gradR, vec3 gradF, vec3 gradDen,
                          float f, float invDen, vec3 axis,
                          out mat4 dg, out vec4 dA) {
    float a = 0.5 * iSpin;
    float r2 = r * r;
    float dr = dot(gradR, axis);
    float df = dot(gradF, axis);
    float dDen = dot(gradDen, axis);
    float dir = outgoing ? -1.0 : 1.0;
    float invL = 1.0 / max(r2 + a * a, 1e-20);
    float dInvL = -2.0 * r * dr * invL * invL;
    vec4 dl;
    dl.x = (dir * (dr * X.x + r * axis.x) - a * axis.z) * invL
         + (dir * r * X.x - a * X.z) * dInvL;
    dl.y = abs(r) > 1e-7 ? dir * (axis.y / r - X.y * dr / r2) : 0.0;
    dl.z = (dir * (dr * X.z + r * axis.z) + a * axis.x) * invL
         + (dir * r * X.z + a * X.x) * dInvL;
    dl.w = 0.0;
    dg = df * mat4(l * l.x, l * l.y, l * l.z, l * l.w)
       + f * mat4(dl * l.x + l * dl.x, dl * l.y + l * dl.y,
                  dl * l.z + l * dl.z, dl * l.w + l * dl.w);
    float potential = r * r2 * invDen;
    float dPotential = (3.0 * r2 * dr - potential * dDen) * invDen;
    dA = -dPotential * l - potential * dl;
}

vec4 CameraConnection(mat4 invg, mat4 dg[3], vec4 U, vec4 V) {
    vec4 d0V = dg[0] * V, d1V = dg[1] * V, d2V = dg[2] * V;
    vec4 d0U = dg[0] * U, d1U = dg[1] * U, d2U = dg[2] * U;
    vec4 c = U.x * d0V + U.y * d1V + U.z * d2V
           + V.x * d0U + V.y * d1U + V.z * d2U;
    c.xyz -= vec3(dot(U, d0V), dot(U, d1V), dot(U, d2V));
    return 0.5 * invg * c;
}

void CameraDerivatives(CameraEvent s, vec3 thrust, float side, bool outgoing,
                       out CameraEvent d) {
    mat4 g, invg;
    float r;
    vec4 l;
    CameraMetric(s.X, side, outgoing, g, invg, r, l);
    float aSpin = 0.5 * iSpin, a2 = aSpin * aSpin, q2 = 0.25 * iQ2;
    float r2 = r * r;
    float invDen = 1.0 / max(r2 * r2 + a2 * s.X.y * s.X.y, 1e-20);
    vec3 gradR = vec3(s.X.x * r2, s.X.y * (r2 + a2), s.X.z * r2)
               * (r * invDen);
    vec3 gradDen = 4.0 * r * r2 * gradR + vec3(0.0, 2.0 * a2 * s.X.y, 0.0);
    float f = (r * r2 - q2 * r2) * invDen;
    vec3 gradF = ((3.0 * r2 - 2.0 * q2 * r) * gradR - f * gradDen) * invDen;
    mat4 dg[3];
    vec4 dA[3];
    CameraMetricGradient(s.X, r, l, outgoing, gradR, gradF, gradDen,
                         f, invDen, vec3(1.0, 0.0, 0.0), dg[0], dA[0]);
    CameraMetricGradient(s.X, r, l, outgoing, gradR, gradF, gradDen,
                         f, invDen, vec3(0.0, 1.0, 0.0), dg[1], dA[1]);
    CameraMetricGradient(s.X, r, l, outgoing, gradR, gradF, gradDen,
                         f, invDen, vec3(0.0, 0.0, 1.0), dg[2], dA[2]);

    vec4 a = thrust.x * s.E1 + thrust.y * s.E2 + thrust.z * s.E3;
    if (CAMERA_MODE == 4 && CAMERA_SPECIFIC_CHARGE != 0.0) {
        mat4 F = mat4(0.0);
        for (int mu = 0; mu < 4; mu++) for (int nu = 0; nu < 4; nu++) {
            float first = mu < 3 ? dA[mu][nu] : 0.0;
            float second = nu < 3 ? dA[nu][mu] : 0.0;
            F[nu][mu] = first - second;
        }
        mat4 magnetic = mat4(0.0);
        if (CAMERA_MAGNETIC_CHARGE != 0.0) {
            mat4 Fu = invg * F * invg;
            magnetic[1][0] = Fu[3][2];
            magnetic[2][0] = -Fu[3][1];
            magnetic[3][0] = Fu[2][1];
            magnetic[2][1] = Fu[3][0];
            magnetic[3][1] = -Fu[2][0];
            magnetic[3][2] = Fu[1][0];
            for (int mu = 0; mu < 4; mu++) for (int nu = mu + 1; nu < 4; nu++)
                magnetic[mu][nu] = -magnetic[nu][mu];
        }
        float charge = iQ2 < 0.0 ? -CAMERA_SPECIFIC_CHARGE : CAMERA_SPECIFIC_CHARGE;
        vec4 force = charge * (CAMERA_ELECTRIC_CHARGE * F
                           + CAMERA_MAGNETIC_CHARGE * magnetic) * s.U;
        a += invg * force;
    }

    d.X = s.U;
    d.U = -CameraConnection(invg, dg, s.U, s.U) + a;
    d.E1 = -CameraConnection(invg, dg, s.U, s.E1) + s.U * dot(a, g * s.E1);
    d.E2 = -CameraConnection(invg, dg, s.U, s.E2) + s.U * dot(a, g * s.E2);
    d.E3 = -CameraConnection(invg, dg, s.U, s.E3) + s.U * dot(a, g * s.E3);
}

CameraEvent CameraAdd(CameraEvent s, CameraEvent d, float h) {
    s.X += h * d.X;
    s.U += h * d.U;
    s.E1 += h * d.E1;
    s.E2 += h * d.E2;
    s.E3 += h * d.E3;
    return s;
}

void CameraOrthonormalize(inout CameraEvent s, float side, bool outgoing) {
    mat4 g, invg;
    float r;
    vec4 l;
    CameraMetric(s.X, side, outgoing, g, invg, r, l);
    s.U *= inversesqrt(max(1e-12, -dot(s.U, g * s.U)));
    s.E1 += dot(s.E1, g * s.U) * s.U;
    s.E1 *= inversesqrt(max(1e-12, dot(s.E1, g * s.E1)));
    s.E2 += dot(s.E2, g * s.U) * s.U;
    s.E2 -= dot(s.E2, g * s.E1) * s.E1;
    s.E2 *= inversesqrt(max(1e-12, dot(s.E2, g * s.E2)));
    s.E3 += dot(s.E3, g * s.U) * s.U;
    s.E3 -= dot(s.E3, g * s.E1) * s.E1;
    s.E3 -= dot(s.E3, g * s.E2) * s.E2;
    s.E3 *= inversesqrt(max(1e-12, dot(s.E3, g * s.E3)));
}

CameraEvent CameraInitial(vec3 pos, float side) {
    CameraEvent s;
    s.X = vec4(pos, 0.0);
    mat4 g, invg;
    float r;
    vec4 l;
    CameraMetric(s.X, side, false, g, invg, r, l);
    vec3 v = CAMERA_INIT_VELOCITY;
    float A = g[3][3];
    float B = 2.0 * dot(g[3].xyz, v);
    float C = 1.0 + dot(v, mat3(g) * v);
    float discriminant = B * B - 4.0 * A * C;
    float ut = 1.0;
    if (discriminant >= 0.0 && abs(A) > 1e-9) {
        float root1 = (-B - sqrt(discriminant)) / (2.0 * A);
        float root2 = (-B + sqrt(discriminant)) / (2.0 * A);
        float energy1 = dot(g[3].xyz, v) + A * root1;
        float energy2 = dot(g[3].xyz, v) + A * root2;
        ut = energy1 < 0.0 && energy2 >= 0.0 ? root1
           : energy2 < 0.0 && energy1 >= 0.0 ? root2 : max(root1, root2);
    } else {
        // 给定空间分量若超出类时域，退回静止初值。
        v = vec3(0.0);
        float restDiscriminant = 4.0 * max(0.0, -A);
        ut = abs(A) > 1e-9 ? sqrt(restDiscriminant) / (-2.0 * A) : 1.0;
    }
    s.U = vec4(v, ut);
    s.E1 = vec4(1.0, 0.0, 0.0, 0.0);
    s.E2 = vec4(0.0, 1.0, 0.0, 0.0);
    s.E3 = vec4(0.0, 0.0, 1.0, 0.0);
    CameraOrthonormalize(s, side, false);
    return s;
}

float CameraIntermediateSign(vec4 before, vec4 after, float side) {
    if (before.y * after.y < 0.0) {
        float t = before.y / (before.y - after.y);
        if (length(mix(before.xz, after.xz, t)) < 0.5 * abs(iSpin)) return -side;
    }
    return side;
}

// 在 ingoing / outgoing Kerr-Schild 坐标之间变换事件与协向量。
// 接近视界时只在另一坐标系的四速明显更温和时换系。
void CameraTransformChart(inout vec4 X, inout vec4 P, float side, bool outToIn) {
    float a = 0.5 * iSpin, a2 = a * a, q2 = 0.25 * iQ2;
    float r = CameraRadius(X.xyz, side);
    float delta = r * r - r + a2 + q2;
    float safeDelta = sign(delta == 0.0 ? 1.0 : delta) * max(abs(delta), 1e-8);
    float D = max(r * r * r * r + a2 * X.y * X.y, 1e-12);
    vec3 gradR = vec3(r * r * r * X.x, r * (r * r + a2) * X.y,
                      r * r * r * X.z) / D;
    float disc = 0.25 - a2 - q2;
    float F, G;
    if (disc > 1e-8) {
        float k = sqrt(disc);
        float frac = abs(r - 0.5 - k) / max(abs(r - 0.5 + k), 1e-8);
        F = log(max(abs(delta), 1e-8)) + (0.5 - q2) / k * log(max(frac, 1e-8));
        G = a / k * log(max(frac, 1e-8));
    } else if (disc < -1e-8) {
        float k = sqrt(-disc);
        float angle = atan((r - 0.5) / k);
        F = log(max(abs(delta), 1e-8)) + (1.0 - 2.0 * q2) / k * angle;
        G = 2.0 * a / k * angle;
    } else {
        float rm = r - 0.5;
        float safeRm = sign(rm == 0.0 ? 1.0 : rm) * max(abs(rm), 1e-8);
        F = 2.0 * log(max(abs(rm), 1e-8)) - (0.5 - 2.0 * q2) / safeRm;
        G = -2.0 * a / safeRm;
    }
    G += 2.0 * atan(a, r);
    float fPrime = 2.0 * (r - q2) / safeDelta;
    float gPrime = 2.0 * a / safeDelta - 2.0 * a / (r * r + a2);
    float kp = fPrime * P.w + gPrime * (X.z * P.x - X.x * P.z);
    float dir = outToIn ? -1.0 : 1.0;
    float angle = -dir * G;
    vec3 pTilde = P.xyz + dir * gradR * kp;
    float ca = cos(angle), sa = sin(angle);
    X = vec4(X.x * ca + X.z * sa, X.y, X.z * ca - X.x * sa, X.w - dir * F);
    P = vec4(pTilde.z * sa + pTilde.x * ca, pTilde.y,
             -pTilde.x * sa + pTilde.z * ca, P.w);
}

void CameraTrySwitch(inout CameraEvent s, float side, inout bool outgoing) {
    mat4 g, invg;
    float r;
    vec4 l;
    CameraMetric(s.X, side, outgoing, g, invg, r, l);
    CameraEvent trial = s;
    trial.U = g * s.U;
    trial.E1 = g * s.E1;
    trial.E2 = g * s.E2;
    trial.E3 = g * s.E3;
    vec4 originalX = s.X;
    CameraTransformChart(trial.X, trial.U, side, outgoing);
    vec4 dummyX = originalX;
    CameraTransformChart(dummyX, trial.E1, side, outgoing);
    dummyX = originalX;
    CameraTransformChart(dummyX, trial.E2, side, outgoing);
    dummyX = originalX;
    CameraTransformChart(dummyX, trial.E3, side, outgoing);
    CameraMetric(trial.X, side, !outgoing, g, invg, r, l);
    trial.U = invg * trial.U;
    trial.E1 = invg * trial.E1;
    trial.E2 = invg * trial.E2;
    trial.E3 = invg * trial.E3;
    float oldSum = dot(abs(s.U), vec4(1.0));
    float newSum = dot(abs(trial.U), vec4(1.0));
    float outerDisc = 0.25 * (1.0 - iSpin * iSpin - iQ2);
    float outer = 0.5 + sqrt(max(0.0, outerDisc));
    float inner = 0.5 - sqrt(max(0.0, outerDisc));
    float radial = dot(vec3(r * r * r * s.X.x,
                             r * (r * r + 0.25 * iSpin * iSpin) * s.X.y,
                             r * r * r * s.X.z), s.U.xyz)
                 / max(r * r * r * r + 0.25 * iSpin * iSpin * s.X.y * s.X.y, 1e-12);
    // 从白洞区进入外部宇宙后若再下落，入射 KS 系能平滑穿过未来外视界。
    bool fallingFromExterior = outgoing && outerDisc >= 0.0 &&
                               r > outer + 0.02 && radial < -1e-5;
    // 在内视界另一侧朝 r 增大方向行进时，outgoing KS 系更平滑。
    bool risingFromInterior = CAMERA_MODE == 2 && !outgoing &&
                              outerDisc > 0.0 && abs(inner) > 1e-6 &&
                              r < inner - 0.02 && radial > 1e-5;
    if ((oldSum > 2.0 * newSum || fallingFromExterior || risingFromInterior) &&
        !any(isnan(trial.U)) && !any(isinf(trial.U))) {
        s = trial;
        outgoing = !outgoing;
    }
}

// 模式 2 的按键直接给出相对于当地参考观者的速度。
// 每次积分后重新指定四速，转向无需等待加速度逐渐追上目标。
vec4 CameraMode2Velocity(vec4 X, float side, bool outgoing, vec3 control) {
    mat4 g, invg;
    float r;
    vec4 l;
    CameraMetric(X, side, outgoing, g, invg, r, l);
    vec4 reference = CameraReferenceVelocity(g, l);
    float beta = length(control);
    vec4 target = reference;
    if (beta > 1e-7 && beta < 1.0) {
        vec4 direction = vec4(control, 0.0);
        direction += dot(direction, g * reference) * reference;
        direction *= inversesqrt(max(1e-12, dot(direction, g * direction)));
        target = (reference + beta * direction) * inversesqrt(1.0 - beta * beta);
    }
    return target;
}

float CameraPenroseChartShift(float r) {
    float a = 0.5 * iSpin, q2 = 0.25 * iQ2;
    float delta = r * r - r + a * a + q2;
    float disc = 0.25 - a * a - q2;
    if (disc > 1e-8) {
        float k = sqrt(disc);
        float frac = abs(r - 0.5 - k) / max(abs(r - 0.5 + k), 1e-8);
        return log(max(abs(delta), 1e-8))
             + (0.5 - q2) / k * log(max(frac, 1e-8));
    }
    if (disc < -1e-8) {
        float k = sqrt(-disc);
        return log(max(abs(delta), 1e-8))
             + (1.0 - 2.0 * q2) / k * atan((r - 0.5) / k);
    }
    float rm = r - 0.5;
    float safeRm = sign(rm == 0.0 ? 1.0 : rm) * max(abs(rm), 1e-8);
    return 2.0 * log(max(abs(rm), 1e-8)) - (0.5 - 2.0 * q2) / safeRm;
}

int CameraInnerHorizonOffset(CameraEvent start, CameraEvent end,
                             float startSide, float endSide, bool outgoing) {
    float a = 0.5 * iSpin;
    float disc = 0.25 - a * a - 0.25 * iQ2;
    if (disc < 0.0) return 0;
    float inner = 0.5 - sqrt(disc);
    if (abs(inner) <= 1e-6) return 0;
    float r0 = CameraRadius(start.X.xyz, startSide);
    float r1 = CameraRadius(end.X.xyz, endSide);
    bool wasInside = r0 < inner, isInside = r1 < inner;
    if (wasInside == isInside) return 0;

    // 内视界是 KS 椭球；在子步弦上解析求交，再由未来向四速判定周期方向。
    float r2 = inner * inner;
    vec3 weight = vec3(1.0 / (r2 + a * a), 1.0 / r2, 1.0 / (r2 + a * a));
    vec3 delta = end.X.xyz - start.X.xyz;
    float A = dot(weight * delta, delta);
    float B = dot(weight * start.X.xyz, delta);
    float C = dot(weight * start.X.xyz, start.X.xyz) - 1.0;
    float determinant = B * B - A * C;
    if (A <= 0.0 || determinant < 0.0) return 0;
    float root = -B - sign(B == 0.0 ? 1.0 : B) * sqrt(determinant);
    vec2 fractions = vec2(root / A, abs(root) > 1e-12 ? C / root : -B / A);
    for (int i = 0; i < 2; i++) {
        float t = fractions[i];
        if (t < -1e-5 || t > 1.0 + 1e-5) continue;
        t = clamp(t, 0.0, 1.0);
        CameraEvent event = CameraAdd(start, CameraAdd(end, start, -1.0), t);
        float eventSide = CameraIntermediateSign(start.X, event.X, startSide);
        float radialDirection = inner * dot(weight * event.X.xyz, delta);
        if (eventSide * sign(iBlackHoleMassSol) * sign(inner) <= 0.0 ||
            (radialDirection < 0.0) != isInside) continue;
        mat4 g, invg;
        float r;
        vec4 l;
        CameraMetric(event.X, eventSide, outgoing, g, invg, r, l);
        float denom = r2 * r2 + a * a * event.X.y * event.X.y;
        vec3 gradient = vec3(inner * r2 * event.X.x,
                             inner * (r2 + a * a) * event.X.y,
                             inner * r2 * event.X.z) / max(denom, 1e-12);
        float radial = dot(gradient, event.U.xyz);
        float scale = dot(abs(gradient), abs(event.U.xyz));
        if (-dot(event.U, g * event.U) < 0.01 ||
            abs(radial) <= 1e-6 * max(1.0, scale)) return 0;
        return radial < 0.0 ? (isInside ? 1 : -1) : 0;
    }
    return 0;
}

float CameraAdvance(inout CameraEvent s, vec3 thrust, inout float side,
                     inout bool outgoing, inout float universeIndex,
                     inout float penroseCycle, inout float penroseRollingT,
                     inout float penroseBranch,
                     float realDt) {
    float extraRate = CAMERA_MODE == 4 ? CAMERA_TIME_RATE : 1.0;
    float remaining = min(max(realDt * extraRate * WORLD_TIME_UNITS_PER_SECOND, 0.0), 1.0);
    float elapsedProperTime = 0.0;
    float stepFactor = 1.0;
    int step = 0;
    while (remaining > 1e-6 && step < 96) {
        step++;
        // 无旋转时 r=0 是点奇点，世界线在此终止。
        if (abs(iSpin) < 1e-6 && length(s.X.xyz) <= 0.01) break;
        CameraTrySwitch(s, side, outgoing);
        float chartStartTime = s.X.w;
        if (CAMERA_MODE == 2) {
            s.U = CameraMode2Velocity(s.X, side, outgoing, thrust);
            CameraOrthonormalize(s, side, outgoing);
        }
        vec3 localThrust = CAMERA_MODE == 2 ? vec3(0.0) : thrust;
        float ring = length(vec2(length(s.X.xz) - abs(0.5 * iSpin), s.X.y));
        float scale = max(0.5 * ring, 1.0);
        float safe = min(0.005 * scale * sqrt(scale),
                         0.05 * max(ring, 1e-4) / max(length(s.U.xyz), 1e-6));
        float h = min(remaining, max(safe, 1e-5) * stepFactor);
        // 中心减速同时作用于参考观者和操控速度，不削弱按键的局部速度。
        float centerR = abs(CameraRadius(s.X.xyz, side));
        float nearCenter = 0.1 + 0.9 * smoothstep(0.05, 0.45, centerR);
        float moveH = CAMERA_MODE == 2 ? h * nearCenter : h;
        CameraEvent k1, k2, k3, k4;
        CameraDerivatives(s, localThrust, side, outgoing, k1);
        CameraEvent s2 = CameraAdd(s, k1, 0.5 * moveH);
        CameraDerivatives(s2, localThrust, CameraIntermediateSign(s.X, s2.X, side), outgoing, k2);
        CameraEvent s3 = CameraAdd(s, k2, 0.5 * moveH);
        CameraDerivatives(s3, localThrust, CameraIntermediateSign(s.X, s3.X, side), outgoing, k3);
        CameraEvent s4 = CameraAdd(s, k3, moveH);
        CameraDerivatives(s4, localThrust, CameraIntermediateSign(s.X, s4.X, side), outgoing, k4);
        CameraEvent next = CameraAdd(s, k1, moveH / 6.0);
        next = CameraAdd(next, k2, moveH / 3.0);
        next = CameraAdd(next, k3, moveH / 3.0);
        next = CameraAdd(next, k4, moveH / 6.0);
        float nextSide = CameraIntermediateSign(s.X, next.X, side);
        mat4 nextMetric, nextInverse;
        float nextR;
        vec4 nextL;
        CameraMetric(next.X, nextSide, outgoing, nextMetric, nextInverse, nextR, nextL);
        float norm = -dot(next.U, nextMetric * next.U);
        bool pointSingularity = abs(iSpin) < 1e-6 &&
                                length(next.X.xyz) <= 0.01;
        bool invalid = pointSingularity ||
                       any(isnan(next.X)) || any(isinf(next.X)) ||
                       any(isnan(next.U)) || any(isinf(next.U)) ||
                       isnan(norm) || isinf(norm) || norm < 0.5 || norm > 1.5;
        if (invalid) {
            stepFactor *= 0.5;
            if (stepFactor < 0.001) break;
        } else {
            stepFactor = min(1.0, 1.3 * stepFactor);
            if (MAX_EXTENSION == 1) {
                float crossed = float(CameraInnerHorizonOffset(s, next,
                                      side, nextSide, outgoing));
                universeIndex = mod(universeIndex + crossed + 3.0, 3.0);
                penroseCycle += crossed;
                float disc = 0.25 * (1.0 - iSpin * iSpin - iQ2);
                if (disc > 0.0) {
                    float inner = 0.5 - sqrt(disc);
                    float outer = 0.5 + sqrt(disc);
                    float oldR = CameraRadius(s.X.xyz, side);
                    float newR = CameraRadius(next.X.xyz, nextSide);
                    if (abs(inner) > 1e-6 && newR < inner &&
                        newR > oldR + 1e-7 && penroseBranch < 0.5)
                        penroseBranch = 1.0;
                    if (newR > outer && newR < oldR - 1e-7 &&
                        penroseBranch > 0.5)
                        penroseBranch = 0.0;
                }
            }
            penroseRollingT += next.X.w - chartStartTime;
            side = nextSide;
            s = next;
            if (CAMERA_MODE == 2)
                s.U = CameraMode2Velocity(s.X, side, outgoing, thrust);
            CameraOrthonormalize(s, side, outgoing);
            remaining -= h;
            elapsedProperTime += moveH;
        }
    }
    return elapsedProperTime;
}

// =============================================================================
// Bloom 的多尺度采样
// =============================================================================

vec3 ColorFetch(vec2 coord)
{
 	return textureLod(iChannel0, coord, 0.0).rgb;   
}

vec3 Grab1(vec2 coord, const float octave, const vec2 offset)
{
 	float scale = exp2(octave);
    coord += offset;
    coord *= scale;
   	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);   
    return ColorFetch(coord);
}

vec3 Grab4(vec2 coord, const float octave, const vec2 offset)
{
 	float scale = exp2(octave);
    coord += offset;
    coord *= scale;
   	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);   
    
    vec3 color = vec3(0.0);
    float weights = 0.0;
    const int oversampling = 4;
    for (int i = 0; i < oversampling; i++) {    	    
        for (int j = 0; j < oversampling; j++) {
			vec2 off = (vec2(i, j) / iResolution.xy + vec2(-float(oversampling)*0.5) / iResolution.xy) * scale / float(oversampling);
            color += ColorFetch(coord + off);
            weights += 1.0;
        }
    }
    return color / weights;
}

vec3 Grab8(vec2 coord, const float octave, const vec2 offset)
{
 	float scale = exp2(octave);
    coord += offset;
    coord *= scale;
   	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);   
    
    vec3 color = vec3(0.0);
    float weights = 0.0;
    const int oversampling = 8;
    for (int i = 0; i < oversampling; i++) {    	    
        for (int j = 0; j < oversampling; j++) {
			vec2 off = (vec2(i, j) / iResolution.xy + vec2(-float(oversampling)*0.5) / iResolution.xy) * scale / float(oversampling);
            color += ColorFetch(coord + off);
            weights += 1.0;
        }
    }
    return color / weights;
}

vec3 Grab16(vec2 coord, const float octave, const vec2 offset)
{
 	float scale = exp2(octave);
    coord += offset;
    coord *= scale;
   	if (coord.x < 0.0 || coord.x > 1.0 || coord.y < 0.0 || coord.y > 1.0) return vec3(0.0);   
    
    vec3 color = vec3(0.0);
    float weights = 0.0;
    const int oversampling = 16;
    for (int i = 0; i < oversampling; i++) {    	    
        for (int j = 0; j < oversampling; j++) {
			vec2 off = (vec2(i, j) / iResolution.xy + vec2(-float(oversampling)*0.5) / iResolution.xy) * scale / float(oversampling);
            color += ColorFetch(coord + off);
            weights += 1.0;
        }
    }
    return color / weights;
}

vec2 CalcOffset(float octave)
{
    vec2 offset = vec2(0.0);
    vec2 padding = vec2(10.0) / iResolution.xy;
    offset.x = -min(1.0, floor(octave / 3.0)) * (0.25 + padding.x);
    offset.y = -(1.0 - (1.0 / exp2(octave))) - padding.y * octave;
	offset.y += min(1.0, floor(octave / 3.0)) * 0.35;
 	return offset;   
}

// =============================================================================
// Camera & State Logic
// =============================================================================

#define OFFSET_UP    0  // 相机上方向
#define OFFSET_RIGHT 1  // 相机右方向
#define OFFSET_POS   2  // 相机位置
#define OFFSET_FWD   3  // 相机前方向
#define OFFSET_MOUSE 4  // 上一帧鼠标
#define OFFSET_TIME  5  // 游戏时间、空间侧与宇宙编号
#define OFFSET_VELOCITY 6
#define OFFSET_SMOOTH_MOVE 7
#define OFFSET_EVENT 8
#define OFFSET_U 9
#define OFFSET_E1 10
#define OFFSET_E2 11
#define OFFSET_E3 12
#define OFFSET_GEODESIC_META 13
#define OFFSET_PARAMETERS 14
#define OFFSET_SMOOTH_TURN 16
#define OFFSET_PENROSE_META 17
#define OFFSET_PENROSE_EVENT 18

void UpdateCameraState(out vec4 fragColor, in vec2 fragCoord)
{
    int pxIndex = int(fragCoord.x);
    vec3  up      = texelFetch(iChannel1, ivec2(OFFSET_UP, 0), 0).xyz;
    vec3  right   = texelFetch(iChannel1, ivec2(OFFSET_RIGHT, 0), 0).xyz;
    vec3  pos     = texelFetch(iChannel1, ivec2(OFFSET_POS, 0), 0).xyz;
    vec3  fwd     = texelFetch(iChannel1, ivec2(OFFSET_FWD, 0), 0).xyz;
    vec4  lastMouse = texelFetch(iChannel1, ivec2(OFFSET_MOUSE, 0), 0);
    vec4  timeData = texelFetch(iChannel1, ivec2(OFFSET_TIME, 0), 0);
    vec4  geoMeta = texelFetch(iChannel1, ivec2(OFFSET_GEODESIC_META, 0), 0);
    vec4  smoothMove = texelFetch(iChannel1, ivec2(OFFSET_SMOOTH_MOVE, 0), 0);
    vec4  smoothTurn = texelFetch(iChannel1, ivec2(OFFSET_SMOOTH_TURN, 0), 0);
    vec4  parameters = texelFetch(iChannel1, ivec2(OFFSET_PARAMETERS, 0), 0);
    vec4  penroseMeta = texelFetch(iChannel1, ivec2(OFFSET_PENROSE_META, 0), 0);
    vec4  penroseEvent = texelFetch(iChannel1, ivec2(OFFSET_PENROSE_EVENT, 0), 0);
    float speedScale = texelFetch(iChannel1, ivec2(15, 0), 0).x;
    float gTime   = timeData.x;
    float timeRate = timeData.w;
    float uniSign = timeData.y; 
    float oldSign = uniSign;
    float universeIndex = timeData.z;
    float penroseCycle = parameters.w - 1024.0;
    float penroseRollingT = penroseMeta.z;
    float penroseBranch = penroseMeta.w;
    float penroseTime = penroseEvent.x;
    float penroseOutgoing = penroseEvent.y;
    vec3 oldPos = pos; 
    bool initialize = iFrame <= 5 || isKeyPressed(KEY_G) || length(fwd) < 0.1 ||
                      geoMeta.w != float(CAMERA_MODE + 1) || geoMeta.y != float(CAMERA_CONTROL_MODE) ||
                      parameters.w < 100.0 || penroseMeta.x < 9.0;
    if (initialize) {
        pos = CAMERA_INIT_POSITION;
        fwd = CAMERA_INIT_DIRECTION;
        fwd = normalize(fwd);
        right = normalize(cross(fwd, CAMERA_INIT_UP));
        up    = normalize(cross(right, fwd));
        if (CAMERA_CONTROL_MODE == 1 && CAMERA_MODE != 4) {
            fwd = normalize(-pos);
            vec3 pole = abs(fwd.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
            right = normalize(cross(fwd, pole));
            up = normalize(cross(right, fwd));
        }
        gTime = 0.0;
        lastMouse = iMouse;
        uniSign = 1.0; 
        universeIndex = 0.0;
        penroseCycle = 0.0;
        penroseRollingT = 0.0;
        penroseBranch = 0.0;
        penroseTime = 0.0;
        penroseOutgoing = 0.0;
        oldPos = pos;
        speedScale = 1.0;
        timeRate = 1.0;
        smoothMove = vec4(0.0);
        smoothTurn = vec4(0.0);
        geoMeta = vec4(0.0, float(CAMERA_CONTROL_MODE), 0.0, float(CAMERA_MODE + 1));
    }

    // 暂停后鼠标仍可触发重绘；只有播放器时间推进时才推进场景时钟。
    float sceneDelta = initialize || iTime != smoothTurn.w ? iTimeDelta : 0.0;
    smoothTurn.w = iTime;
    float dt = clamp(iTimeDelta, 0.0, 0.05);
    float moveBlend = 1.0 - exp(-dt / max(CAMERA_MOVE_RESPONSE, 1e-5));
    float turnBlend = 1.0 - exp(-dt / max(CAMERA_TURN_RESPONSE, 1e-5));

    // 鼠标位移先变成角速度，松开后角速度再逐渐归零。
    vec2 targetTurn = vec2(0.0);
    if (iMouse.z > 0.0) {
        vec2 mouseDelta = iMouse.xy - lastMouse.xy;
        if (lastMouse.z < 0.0) mouseDelta = vec2(0.0);
        targetTurn = vec2(-mouseDelta.x, mouseDelta.y) *
                     MOUSE_SENSITIVITY / max(dt, 1e-5);
    }
    smoothTurn.xy = mix(smoothTurn.xy, targetTurn, turnBlend);
    float yaw = smoothTurn.x * dt;
    float pitch = smoothTurn.y * dt;
    if (abs(yaw) + abs(pitch) > 1e-8) {
        if (CAMERA_CONTROL_MODE == 1 && CAMERA_MODE != 4) {
            float radius = length(pos);
            pos = rotAxis(vec3(0.0, 1.0, 0.0), yaw) * pos;
            vec3 orbitForward = normalize(-pos);
            vec3 pole = abs(orbitForward.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
            vec3 orbitRight = normalize(cross(orbitForward, pole));
            pos = rotAxis(orbitRight, -pitch) * pos;
            pos.y = clamp(pos.y, -0.999 * radius, 0.999 * radius);
            pos = normalize(pos) * radius;
        } else {
            fwd = rotAxis(up, yaw) * fwd;
            right = rotAxis(up, yaw) * right;
            fwd = rotAxis(right, pitch) * fwd;
            up = normalize(cross(right, fwd));
            right = normalize(cross(fwd, up));
        }
    }
    
    float targetRoll = 0.0;
    if (CAMERA_CONTROL_MODE != 1 || CAMERA_MODE == 4) {
        if (isKeyPressed(KEY_Q)) targetRoll -= ROLL_SPEED;
        if (isKeyPressed(KEY_E)) targetRoll += ROLL_SPEED;
    }
    smoothTurn.z = mix(smoothTurn.z, targetRoll, turnBlend);
    float roll = smoothTurn.z * dt;
    if (roll != 0.0) {
        right = rotAxis(fwd, roll) * right;
        up = normalize(cross(right, fwd));
    }

    if (isKeyPressed(KEY_PLUS) || isKeyPressed(KEY_NUMPAD_PLUS))
        speedScale *= exp2(2.0 * iTimeDelta);
    if (isKeyPressed(KEY_MINUS) || isKeyPressed(KEY_NUMPAD_MINUS))
        speedScale *= exp2(-2.0 * iTimeDelta);
    speedScale = max(speedScale, 0.02);
    if (isKeyPressed(KEY_TIME_FASTER)) timeRate *= exp2(2.0 * iTimeDelta);
    if (isKeyPressed(KEY_TIME_SLOWER)) timeRate *= exp2(-2.0 * iTimeDelta);
    timeRate = clamp(timeRate, 0.02, 100.0);

    // 移动方向、环绕缩放和本征加速度共用逐渐响应的输入。
    vec3 moveDir = vec3(0.0);
    if (isKeyPressed(KEY_W)) moveDir += fwd;
    if (isKeyPressed(KEY_S)) moveDir -= fwd;
    if (isKeyPressed(KEY_A)) moveDir -= right;
    if (isKeyPressed(KEY_D)) moveDir += right;
    if (isKeyPressed(KEY_R)) moveDir += up; // 上浮
    if (isKeyPressed(KEY_F)) moveDir -= up; // 下沉
    vec3 targetMove = length(moveDir) > 0.0 ? normalize(moveDir) : vec3(0.0);
    smoothMove.xyz = mix(smoothMove.xyz, targetMove, moveBlend);
    float targetZoom = float(isKeyPressed(KEY_S)) - float(isKeyPressed(KEY_W));
    smoothMove.w = mix(smoothMove.w, targetZoom, moveBlend);

    CameraEvent camera;
    camera.X = vec4(0.0); camera.U = vec4(0.0);
    camera.E1 = vec4(0.0); camera.E2 = vec4(0.0); camera.E3 = vec4(0.0);
    bool mode2Invalid = false;
    if (CAMERA_MODE == 4 ||
        (CAMERA_MODE == 2 && CAMERA_CONTROL_MODE == 0)) {
        if (initialize) {
            if (CAMERA_MODE == 4) {
                camera = CameraInitial(pos, uniSign);
            } else {
                camera.X = vec4(pos, 0.0);
                mat4 g, invg;
                float r;
                vec4 l;
                CameraMetric(camera.X, uniSign, false, g, invg, r, l);
                camera.U = CameraReferenceVelocity(g, l);
                camera.E1 = vec4(1.0, 0.0, 0.0, 0.0);
                camera.E2 = vec4(0.0, 1.0, 0.0, 0.0);
                camera.E3 = vec4(0.0, 0.0, 1.0, 0.0);
                CameraOrthonormalize(camera, uniSign, false);
            }
            geoMeta = vec4(0.0, float(CAMERA_CONTROL_MODE), 0.0, float(CAMERA_MODE + 1));
        } else {
            camera.X = texelFetch(iChannel1, ivec2(OFFSET_EVENT, 0), 0);
            camera.U = texelFetch(iChannel1, ivec2(OFFSET_U, 0), 0);
            camera.E1 = texelFetch(iChannel1, ivec2(OFFSET_E1, 0), 0);
            camera.E2 = texelFetch(iChannel1, ivec2(OFFSET_E2, 0), 0);
            camera.E3 = texelFetch(iChannel1, ivec2(OFFSET_E3, 0), 0);
        }
        vec3 thrust = smoothMove.xyz *
                      (CAMERA_MODE == 2 ? 0.4 : CAMERA_THRUST) * speedScale;
        bool outgoing = geoMeta.x > 0.5;
        float properTime = CameraAdvance(camera, thrust, uniSign, outgoing, universeIndex,
                                         penroseCycle, penroseRollingT, penroseBranch,
                                         sceneDelta * timeRate);
        geoMeta.x = outgoing ? 1.0 : 0.0;
        pos = camera.X.xyz;
        geoMeta.z += properTime;
        penroseRollingT = mix(penroseRollingT, camera.X.w,
                              1.0 - exp(-dt / 2.0));
        penroseTime = camera.X.w;
        penroseOutgoing = outgoing ? 1.0 : 0.0;
        if (CAMERA_MODE == 2) {
            float beta = length(thrust);
            mode2Invalid = beta >= 1.0 || isnan(beta) || isinf(beta);
        }
    } else if (CAMERA_CONTROL_MODE == 1) {
        // 环绕模式始终看向世界原点。W/S 只改半径，鼠标只改经纬度。
        float radius = max(0.05, length(pos) * exp(smoothMove.w * ORBIT_ZOOM_SPEED * speedScale * dt * timeRate));
        pos = normalize(pos) * radius;
        fwd = normalize(-pos);
        vec3 pole = abs(fwd.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
        right = normalize(cross(fwd, pole));
        up = normalize(cross(right, fwd));
    } else {
        float centerR = abs(CameraRadius(pos, uniSign));
        float nearCenter = 0.1 + 0.9 * smoothstep(0.05, 0.45, centerR);
        pos += smoothMove.xyz * MOVE_SPEED * speedScale *
               iTimeDelta * timeRate * nearCenter;
    }

    vec3 observedVelocity = (pos - oldPos) /
        max(iTimeDelta * timeRate * WORLD_TIME_UNITS_PER_SECOND, 1e-6);
    if (CAMERA_MODE == 2 && CAMERA_CONTROL_MODE == 0) {
        float timeSign = camera.U.w < 0.0 ? -1.0 : 1.0;
        observedVelocity = camera.U.xyz /
            (timeSign * max(abs(camera.U.w), 1e-8));
    }
    
    float spinRadius = abs(iSpin * CONST_M);
    if (CAMERA_MODE != 4 &&
        (CAMERA_MODE != 2 || CAMERA_CONTROL_MODE == 1) &&
        oldPos.y * pos.y < 0.0)
    {
        float t = oldPos.y / (oldPos.y - pos.y);
        vec3 crossPoint = mix(oldPos, pos, t);
        
        if (length(crossPoint.xz) < spinRadius) {
            uniSign *= -1.0;
        }
    }
    if (MAX_EXTENSION == 1 && CAMERA_MODE != 4 &&
        (CAMERA_MODE != 2 || CAMERA_CONTROL_MODE == 1)) {
        float discriminant = 0.25 * (1.0 - iSpin * iSpin - iQ2);
        if (discriminant >= 0.0) {
            float inner = 0.5 - sqrt(discriminant);
            if (CameraRadius(oldPos, oldSign) > inner && CameraRadius(pos, uniSign) <= inner) {
                universeIndex = mod(universeIndex + 1.0, 3.0);
                penroseCycle += 1.0;
            }
        }
    }
    // 6. 更新时间
    gTime += sceneDelta * timeRate;
    if (CAMERA_MODE != 4 &&
        (CAMERA_MODE != 2 || CAMERA_CONTROL_MODE == 1)) {
        penroseTime += sceneDelta * timeRate * WORLD_TIME_UNITS_PER_SECOND;
        penroseRollingT = WORLD_TIME_UNITS_PER_SECOND * gTime;
    }

    float diagramDisc = 0.25 * (1.0 - iSpin * iSpin - iQ2);
    if (MAX_EXTENSION == 1 && CAMERA_MODE != 4 &&
        (CAMERA_MODE != 2 || CAMERA_CONTROL_MODE == 1) &&
        diagramDisc > 0.0) {
        float inner = 0.5 - sqrt(diagramDisc);
        float outer = 0.5 + sqrt(diagramDisc);
        float oldR = CameraRadius(oldPos, oldSign);
        float newR = CameraRadius(pos, uniSign);
        if (abs(inner) > 1e-6 && newR < inner && newR > oldR + 1e-7 && penroseBranch < 0.5) {
            penroseBranch = 1.0;
            penroseTime -= CameraPenroseChartShift(newR);
            penroseOutgoing = 1.0;
        }
        if (newR > outer && newR < oldR - 1e-7 && penroseBranch > 0.5) {
            penroseBranch = 0.0;
            penroseTime += CameraPenroseChartShift(newR);
            penroseOutgoing = 0.0;
        }
    }

    if (CAMERA_MODE == 2 && CAMERA_CONTROL_MODE == 1) {
        // 环绕相机直接指定位置；用实际位移判断观者四速是否仍为类时。
        camera.X = vec4(pos, penroseTime);
        mat4 g, invg;
        float r;
        vec4 l;
        CameraMetric(camera.X, uniSign, false, g, invg, r, l);
        vec4 rawU = vec4(observedVelocity, 1.0);
        float norm = -dot(rawU, g * rawU);
        mode2Invalid = norm <= 0.0 || isnan(norm) || isinf(norm);
        camera.U = mode2Invalid ? CameraReferenceVelocity(g, l)
                                : rawU * inversesqrt(norm);
        camera.E1 = vec4(1.0, 0.0, 0.0, 0.0);
        camera.E2 = vec4(0.0, 1.0, 0.0, 0.0);
        camera.E3 = vec4(0.0, 0.0, 1.0, 0.0);
        CameraOrthonormalize(camera, uniSign, false);
    }

    // 7. 写入数据 (根据 pxIndex 匹配 Common 中 LoadRayCamera 的读取位置)
    fragColor = vec4(0.0);
    
    if (pxIndex == OFFSET_UP)    fragColor = vec4(up, 1.0);
    if (pxIndex == OFFSET_RIGHT) fragColor = vec4(right, 1.0);
    if (pxIndex == OFFSET_POS)   fragColor = vec4(pos, 1.0);
    if (pxIndex == OFFSET_FWD)   fragColor = vec4(fwd, 1.0);
    if (pxIndex == OFFSET_MOUSE) fragColor = iMouse;
    if (pxIndex == OFFSET_TIME)  fragColor = vec4(gTime, uniSign, universeIndex, timeRate);
    if (pxIndex == OFFSET_VELOCITY)
        fragColor = vec4(observedVelocity, mode2Invalid ? 1.0 : 0.0);
    if (pxIndex == OFFSET_SMOOTH_MOVE) fragColor = smoothMove;
    if (pxIndex == OFFSET_EVENT) fragColor = camera.X;
    if (pxIndex == OFFSET_U) fragColor = camera.U;
    if (pxIndex == OFFSET_E1) fragColor = camera.E1;
    if (pxIndex == OFFSET_E2) fragColor = camera.E2;
    if (pxIndex == OFFSET_E3) fragColor = camera.E3;
    if (pxIndex == OFFSET_GEODESIC_META) fragColor = vec4(geoMeta.xyz, float(CAMERA_MODE + 1));
    // 宇宙编号仍在 0、1、2 间循环；这里只保存图的连续纵向层号。
    if (pxIndex == OFFSET_PARAMETERS) fragColor = vec4(iSpin, iQ2, float(MAX_EXTENSION), 1024.0 + penroseCycle);
    if (pxIndex == 15) fragColor = vec4(speedScale, WORLD_TIME_UNITS_PER_SECOND,
                                       sign(iBlackHoleMassSol), 1.0);
    if (pxIndex == OFFSET_SMOOTH_TURN) fragColor = smoothTurn;
    if (pxIndex == OFFSET_PENROSE_META)
        fragColor = vec4(10.0 + float(iShowTopologyMap),
                         10.0 + float(iShowPenroseMap),
                         penroseRollingT, penroseBranch);
    if (pxIndex == OFFSET_PENROSE_EVENT)
        fragColor = vec4(penroseTime, penroseOutgoing, 0.0, 1.0);
}

// =============================================================================
// 相机状态与 Bloom 输出
// =============================================================================

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // 左下角 19 个像素保存相机状态，其余像素用于 Bloom。
    // 固定在左下角可避免窗口尺寸变化时读到错误的状态。
    bool isDataPixel = (fragCoord.y < 1.0 && fragCoord.x < 19.0);

    if (isDataPixel) {
        UpdateCameraState(fragColor, fragCoord);
    } else {
        // 从 iChannel0 的 Buffer A 采样多尺度 Bloom。
        vec2 uv = fragCoord.xy / iResolution.xy;
        vec3 color = vec3(0.0);
        
        color += Grab1(uv, 1.0, vec2(0.0,  0.0)   );
        color += Grab4(uv, 2.0, vec2(CalcOffset(1.0))   );
        color += Grab8(uv, 3.0, vec2(CalcOffset(2.0))   );
        color += Grab16(uv, 4.0, vec2(CalcOffset(3.0))   );
        color += Grab16(uv, 5.0, vec2(CalcOffset(4.0))   );
        color += Grab16(uv, 6.0, vec2(CalcOffset(5.0))   );
        color += Grab16(uv, 7.0, vec2(CalcOffset(6.0))   );
        color += Grab16(uv, 8.0, vec2(CalcOffset(7.0))   );

        fragColor = vec4(color, 1.0);
    }
}
