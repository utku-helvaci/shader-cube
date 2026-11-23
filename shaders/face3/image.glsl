/*
================================================================================
Kerr–Newman 黑洞实时可交互广义相对论渲染
Interactive Kerr–Newman spacetime Real-time General Relativity Renderer
https://github.com/baopinshui/NPGS/blob/master/NPGS/Sources/Engine/Shaders/BlackHole_common.glsl
================================================================================

[ 简介 / Introduction ]

这个Shader是基于物理的KN时空（带电旋转黑洞）的光线步进。
This shader implements physically based raymarching in KN spacetime (charged rotating black hole).

实现了完整的最大延拓，包括外视界、内视界、内外能层、奇环、反宇宙、
平行宇宙、白洞区、上一宇宙、下一宇宙，还有虚电荷和负质量之类的奇异度规。
Implements the complete maximal extension: outer/inner event horizons and ergospheres, 
ringularity, antiverses, parallel universe, white hole region, previous and next universes,
as well as exotic metric such as imaginary charges and negative mass.

可以切换静态观者、自由落体观者、自定义速度观者，还有受到引力、电磁力并且可以自己加减速的观者。
你可以在拓扑图和彭罗斯图里观察自己的位置。
Supports Static, Free-falling, Custom-velocity observers, and observers subject to gravitational
and electromagnetic forces that is capable of self-acceleration and deceleration.
You can observe your position on the topology map and the Penrose diagram.

考虑了各种效应，包含吸积盘和喷流光子的四动量&引力红移&观者四速产生的频移、引力透镜立体角增亮、
热浪折射，还有基于物理的偏振模拟（在弯曲时空中计算Walker-Penrose常数）。
Implements physically-based polarization simulation by calculating Walker-Penrose constants
in curved spacetime.

--------------------------------------------------------------------------------

[ 操作方式 / Controls ]

鼠标拖动控制视角，键盘控制移动。
Mouse controls camera angle, keyboard controls movement.

[W] / [S] : 前进 / 后退 (Forward / Backward)
[A] / [D] : 向左 / 向右 (Left / Right)
[R] / [F] : 上升 / 下降 (Up / Down - Relative to View)
[Q] / [E] : 镜头翻滚 (Camera Roll)
[+] / [-] : 加速/减速 (Increase/decrease velocity or acceleration)
[[] / []] : 加快/减慢时间流逝 (Speed up/slow down the time)
[G] : 让相机回到初始状态 (Reset the camera to initial)

--------------------------------------------------------------------------------

[ 参数调整 / Configs ]

请在 Common 调整各种参数，所有配置参数都在那里，包括物理、渲染、相机控制。
Please adjust parameters in "Common". All configs are located there,
including physics, rendering, and camera controls.

--------------------------------------------------------------------------------
*/

// Buffer B/C/D 与 Image 来自 sonicether 的作品 "Gargantua With HDR Bloom"。
// Buffer B/C/D and Image  are adapted from sonicether's "Gargantua With HDR Bloom".

const int mapShowTopologyMap = iShowTopologyMap, mapShowPenroseMap = iShowPenroseMap;
const float mapBlackHoleMassSol = sign(iBlackHoleMassSol), mapSpin = iSpin, mapQ2 = iQ2;
float mapUniverseSign;
float iPenroseRollingT, iPenroseBranch;
float MapKerrSchildRadius(vec3 p, float PhysicalSpinA, float r_sign) {
    float r_sign_len = r_sign * length(p);
    if (PhysicalSpinA == 0.0) return r_sign_len; 

    float a2 = PhysicalSpinA * PhysicalSpinA;
    float rho2 = dot(p.xz, p.xz); // x^2 + z^2
    float y2 = p.y * p.y;
    
    float b = rho2 + y2 - a2;
    float det = sqrt(b * b + 4.0 * a2 * y2);
    
    float r2;
    if (b >= 0.0) {
        r2 = 0.5 * (b + det);
    } else {
        r2 = (2.0 * a2 * y2) / max(1e-20, det - b);
    }
    return r_sign * sqrt(r2);
}
// 拓扑截面与 Carter-Penrose 图
float MapSegment(vec2 p, vec2 a, vec2 b) {
    vec2 v = b - a;
    return length(p - a - v * clamp(dot(p - a, v) / max(dot(v, v), 1e-12), 0.0, 1.0));
}

float MapRing(vec2 p, vec2 c, float radius) {
    return abs(length(p - c) - radius);
}

vec4 MapStroke(vec4 base, vec4 ink, float dist, float width) {
    float cov = 1.0 - smoothstep(0.5 * width, width, dist);
    float a = cov * ink.a;
    return vec4(mix(base.rgb, ink.rgb, a), base.a + a * (1.0 - base.a));
}

vec4 MapStroke(vec4 base, vec3 ink, float dist, float width) {
    return MapStroke(base, vec4(ink, 1.0), dist, width);
}

float MapFeatureLinePx() {
    return min(0.28 * iResolution.x / 600.0,
               0.25 * iResolution.y / 300.0);
}

vec4 RenderTopologyMap(vec2 pixel, vec3 camPos, vec3 camDir) {
    vec2 size = 0.28 * iResolution.xy;
    size.y = 0.25 * iResolution.y;
    vec2 origin = iResolution.xy * 0.98 - size;
    if (any(lessThan(pixel, origin)) || any(greaterThan(pixel, origin + size))) return vec4(0.0);

    float a = 0.5 * mapSpin, a2 = a * a, Q2 = 0.25 * mapQ2;
    float disc = 0.25 - a2 - Q2;
    float rp = 0.5 + sqrt(max(0.0, disc));
    float rm = 0.5 - sqrt(max(0.0, disc));
    float radius = max(1.5, 1.2 * length(camPos));
    float scale = min(size.x * 0.23, size.y * 0.43) / radius;
    // 按 600×300 虚拟画布规定线宽，再换算成实际屏幕像素。
    float linePx = MapFeatureLinePx();
    vec2 sideCenter = origin + vec2(size.x * 0.25, size.y * 0.5);
    vec2 topCenter = origin + vec2(size.x * 0.75, size.y * 0.5);
    bool top = pixel.x > origin.x + size.x * 0.5;
    vec2 center = top ? topCenter : sideCenter;
    vec2 q = (pixel - center) / scale;
    vec4 color = vec4(0.06, 0.08, 0.12, 0.28);
    color = MapStroke(color, vec4(1.0, 1.0, 1.0, 0.18), abs(pixel.x - center.x), 1.0 * linePx);
    color = MapStroke(color, vec4(1.0, 1.0, 1.0, 0.18), abs(pixel.y - center.y), 1.0 * linePx);
    color = MapStroke(color, vec4(1.0, 1.0, 1.0, 0.45), abs(pixel.x - origin.x - size.x * 0.5), 1.5 * linePx);

    // 内视界和内无限红移面在虚电荷下可能位于负 r 侧。
    float physicalSide = mapUniverseSign * sign(mapBlackHoleMassSol);
    float outerAlpha = physicalSide > 0.0 ? 1.0 : 0.16;
    float innerAlpha = physicalSide * rm > 0.0 ? 1.0 : 0.16;
    vec4 horizonOuter = vec4(1.0, 0.39, 0.39, outerAlpha);
    vec4 horizonInner = vec4(0.39, 0.59, 1.0, innerAlpha);
    vec4 ergoOuter = vec4(0.59, 1.0, 0.59, outerAlpha);
    vec4 ergoInner = vec4(1.0, 0.78, 0.20, 0.16);
    vec3 ringColor = vec3(1.0, 0.0, 1.0);
    if (top) {
        float rho = length(q);
        float ergoDisc = 0.25 - Q2;
        if (ergoDisc >= 0.0) {
            float innerErgoR = 0.5 - sqrt(ergoDisc);
            ergoInner.a = physicalSide * innerErgoR > 0.0 ? 1.0 : 0.16;
            color = MapStroke(color, ergoOuter, abs(rho - sqrt(pow(0.5 + sqrt(ergoDisc), 2.0) + a2)) * scale, 1.5 * linePx);
            color = MapStroke(color, ergoInner, abs(rho - sqrt(innerErgoR * innerErgoR + a2)) * scale, 1.5 * linePx);
        }
        if (disc >= 0.0) {
            color = MapStroke(color, horizonOuter, abs(rho - sqrt(rp * rp + a2)) * scale, 2.0 * linePx);
            if (rm != 0.0) color = MapStroke(color, horizonInner, abs(rho - sqrt(rm * rm + a2)) * scale, 2.0 * linePx);
        }
        color = MapStroke(color, ringColor, abs(rho - abs(a)) * scale, 2.0 * linePx);
        vec2 p = topCenter + camPos.xz * scale;
        vec2 tip = p + camDir.xz * max(1.5, 0.15 * length(camPos)) * scale;
        color = MapStroke(color, vec3(1.0, 0.9, 0.2), MapSegment(pixel, p, tip), 2.0 * linePx);
        color = MapStroke(color, vec3(1.0), length(pixel - p), 4.0 * linePx);
    } else {
        float rho = abs(q.x), y = q.y;
        float b = rho * rho + y * y - a2;
        float det = sqrt(b * b + 4.0 * a2 * y * y);
        float r2 = b >= 0.0 ? 0.5 * (b + det) : 2.0 * a2 * y * y / max(det - b, 1e-12);
        float r = sqrt(max(r2, 0.0));
        float cosT2 = clamp(y * y / max(r2, 1e-12), 0.0, 1.0);
        float ergoDisc = 0.25 - a2 * cosT2 - Q2;
        if (ergoDisc >= 0.0) {
            float innerErgoR = 0.5 - sqrt(ergoDisc);
            ergoInner.a = physicalSide * innerErgoR > 0.0 ? 1.0 : 0.16;
            color = MapStroke(color, ergoOuter, abs(r - 0.5 - sqrt(ergoDisc)) * scale, 1.5 * linePx);
            color = MapStroke(color, ergoInner, abs(r - abs(innerErgoR)) * scale, 1.5 * linePx);
        }
        if (disc >= 0.0) {
            color = MapStroke(color, horizonOuter, abs(r - rp) * scale, 2.0 * linePx);
            if (rm != 0.0) color = MapStroke(color, horizonInner, abs(r - abs(rm)) * scale, 2.0 * linePx);
        }
        if (mapUniverseSign * sign(mapBlackHoleMassSol) < 0.0) {
            float G = (r2 + a2) * (r2 + a2 * cosT2) + a2 * (1.0 - cosT2) * (-r - Q2);
            float derivative = max(1e-7, abs(4.0 * r * r2 + 2.0 * a2 * r * (1.0 + cosT2) - a2 * (1.0 - cosT2)));
            color = MapStroke(color, vec3(0.78, 0.39, 1.0), abs(G / derivative) * scale, 1.5 * linePx);
        }
        color = MapStroke(color, ringColor, length(q - vec2(abs(a), 0.0)) * scale, 4.0 * linePx);
        color = MapStroke(color, ringColor, length(q - vec2(-abs(a), 0.0)) * scale, 4.0 * linePx);
        float camRho = length(camPos.xz);
        float radialDir = camRho > 1e-6 ? dot(camPos.xz, camDir.xz) / camRho : length(camDir.xz);
        vec2 p = sideCenter + vec2(camRho, camPos.y) * scale;
        vec2 tip = p + vec2(radialDir, camDir.y) * max(1.5, 0.15 * length(camPos)) * scale;
        color = MapStroke(color, vec3(1.0, 0.9, 0.2), MapSegment(pixel, p, tip), 2.0 * linePx);
        color = MapStroke(color, vec3(1.0), length(pixel - p), 4.0 * linePx);
    }
    return color;
}

// 沿自旋轴的 (t,r) 截面。r* 把径向零测地线写成 t±r* 常数。
float PenTortoise(float r, float a, float Q2) {
    float disc = 0.25 - a * a - Q2;
    if (disc < -1e-7) {
        float root = sqrt(-disc);
        float delta = (r - 0.5) * (r - 0.5) + root * root;
        return r + 0.5 * log(delta)
                 + (0.5 - Q2) / root * atan((r - 0.5) / root);
    }
    if (disc <= 1e-7) {
        float s = r - 0.5;
        float safeS = sign(s == 0.0 ? 1.0 : s) * max(abs(s), 1e-8);
        return r + log(abs(safeS)) - (0.5 - Q2) / safeS;
    }
    float root = sqrt(disc);
    float rp = 0.5 + root, rm = 0.5 - root;
    float gap = rp - rm;
    float ap = (rp * rp + a * a) / gap;
    float am = (rm * rm + a * a) / gap;
    return r + ap * log(max(abs(r - rp), 1e-12))
             - am * log(max(abs(r - rm), 1e-12));
}

float PenExpCompact(float logValue) {
    return 0.6366197723675814 * atan(exp(clamp(logValue, -25.0, 25.0)));
}

float PenLogTan(float compact) {
    return log(max(tan(1.5707963267948966 * clamp(compact, 1e-6, 0.999999)), 1e-12));
}

vec2 PenCenter(int region, float cycle) {
    float y = 4.0 * cycle;
    if (region == 0) return vec2( 1.0, y - 1.0); // I
    if (region == 1) return vec2(-1.0, y - 1.0); // I'
    if (region == 2) return vec2( 0.0, y);       // II
    if (region == 3) return vec2(-1.0, y + 1.0); // 内视界左侧
    if (region == 4) return vec2( 1.0, y + 1.0); // 内视界右侧
    return vec2(0.0, y - 2.0);                    // 白洞
}

// 在 KS 时间下，v=tKS+r 或 u=tKS-r 在相应的未来/过去视界保持有限。
vec2 PenCameraPoint(float r, float tKS, float rollingT, float a, float Q2,
                    bool outgoing, bool regionOutgoing, float side, int cycle,
                    bool pointPatch) {
    float disc = 0.25 - a * a - Q2;
    float tortoise = PenTortoise(r, a, Q2);
    float shifted = tKS - rollingT;
    float u = outgoing ? shifted - r : shifted + r - 2.0 * tortoise;
    float v = outgoing ? shifted - r + 2.0 * tortoise : shifted + r;
    if (disc <= 1e-7 || pointPatch) {
        float offset = PenTortoise(0.0, a, Q2);
        float A = 0.6366197723675814 * atan((u + offset) * 0.25);
        float B = 0.6366197723675814 * atan((v - offset) * 0.25);
        return vec2(B - A, B + A);
    }
    float root = sqrt(disc);
    float rp = 0.5 + root, rm = 0.5 - root;
    float kp = root / (rp * rp + a * a);
    float A, B;
    if (r >= rp) {
        A = -PenExpCompact(-kp * u);
        B =  PenExpCompact( kp * v);
    } else if (r >= rm) {
        A = (regionOutgoing ? -1.0 : 1.0) * PenExpCompact(-kp * u);
        B = (regionOutgoing ? -1.0 : 1.0) * PenExpCompact( kp * v);
    } else {
        // 两条内视界沿用相邻区域的 u、v 紧化，使相机点跨界连续。
        A = 1.0 + PenExpCompact(kp * u);
        B = PenExpCompact(kp * v);
    }
    float x = B - A;
    if (side < 0.0 && r >= rp) x = -x;
    int shownCycle = cycle > 0 && r < rm ? cycle - 1 : cycle;
    return vec2(x, B + A - 1.0 + 4.0 * float(shownCycle));
}

// 从菱形中的共形坐标恢复 BL 时间与 r*，用同一变换绘制网格和相机。
vec2 PenInverse(vec2 q, int region, float kp) {
    float A = 0.5 * (q.y + 1.0 - q.x);
    float B = 0.5 * (q.y + 1.0 + q.x);
    float u = -PenLogTan(abs(A)) / kp;
    float v =  PenLogTan(abs(B)) / kp;
    if (region == 3) {
        u = PenLogTan(clamp(A - 1.0, 1e-6, 0.999999)) / kp;
        v = PenLogTan(clamp(B, 1e-6, 0.999999)) / kp;
    }
    if (region == 4) {
        u = -PenLogTan(clamp(A, 1e-6, 0.999999)) / kp;
        v = -PenLogTan(clamp(B - 1.0, 1e-6, 0.999999)) / kp;
    }
    return vec2(0.5 * (u + v), 0.5 * (v - u));
}

vec2 PenNakedInverse(vec2 q) {
    float U = clamp(0.5 * (q.y - q.x), -0.999, 0.999);
    float V = clamp(0.5 * (q.y + q.x), -0.999, 0.999);
    float u = 4.0 * tan(1.5707963267948966 * U);
    float v = 4.0 * tan(1.5707963267948966 * V);
    return vec2(0.5 * (u + v), 0.5 * (v - u));
}

vec4 PenGridLine(vec4 base, vec4 ink, float field, float level,
                 float fieldPerPixel, float width) {
    float distancePx = abs(field - level) / max(fieldPerPixel, 1e-5);
    return MapStroke(base, ink, distancePx, width);
}

vec4 PenGridLine(vec4 base, vec3 ink, float field, float level,
                 float fieldPerPixel, float width) {
    return PenGridLine(base, vec4(ink, 1.0), field, level, fieldPerPixel, width);
}

vec4 PenTimeLines(vec4 base, vec4 ink, float time,
                   float timePerPixel, float spacing, float centerTime) {
    float nearest = spacing * round(time / spacing);
    if (abs(nearest - centerTime) > 2.5 * spacing) return base;
    return PenGridLine(base, ink, time, nearest, timePerPixel, 0.8);
}

float PenRegionMark(vec2 p, int region) {
    int count = region == 2 ? 2 : (region == 3 || region == 4 ? 3 : 1);
    float d = 1e3;
    for (int i = 0; i < 3; i++) {
        if (i >= count) break;
        float x = (float(i) - 0.5 * float(count - 1)) * 0.07;
        d = min(d, MapSegment(p, vec2(x, -0.06), vec2(x, 0.06)));
    }
    if (region == 5) {
        d = min(d, MapSegment(p, vec2(0.06, 0.06), vec2(0.12, -0.06)));
        d = min(d, MapSegment(p, vec2(0.12, -0.06), vec2(0.18, 0.06)));
    }
    if (region == 1 || region == 4) d = min(d, MapSegment(p, vec2(0.13, 0.10), vec2(0.17, 0.16)));
    return d;
}

vec3 PenUniverseTint(int tile) {
    int phase = int(mod(float(tile), 3.0));
    if (phase == 1) return vec3(0.0, 0.5, 1.0);
    if (phase == 2) return vec3(1.0, 0.0, 0.0);
    return vec3(0.0);
}

vec4 RenderPenroseMap(vec2 pixel, vec3 camPos, float tKS,
                      float side, bool outgoing, int cycle, bool extended) {
    vec2 size = vec2(0.28 * iResolution.x, 0.56 * iResolution.y);
    float top = mapShowTopologyMap == 1 ? 0.71 : 0.98;
    vec2 origin = vec2(0.98 * iResolution.x - size.x, top * iResolution.y - size.y);
    if (any(lessThan(pixel, origin)) || any(greaterThan(pixel, origin + size))) return vec4(0.0);
    float a = 0.5 * mapSpin, Q2 = 0.25 * mapQ2;
    float effectiveSide = side * sign(mapBlackHoleMassSol);
    float r = MapKerrSchildRadius(camPos, a, effectiveSide);
    float disc = 0.25 - a * a - Q2;
    float rm = 0.5 - sqrt(max(disc, 0.0));
    // 无旋转负质量且负 r 侧无视界时，r=0 的点奇点截断了其余宇宙。
    bool negativePoint = mapBlackHoleMassSol < 0.0 && abs(a) < 1e-6 &&
                         disc > 1e-7 && rm >= -1e-6;
    bool negativeHorizonPatch = mapBlackHoleMassSol < 0.0 && abs(a) < 1e-6 &&
                                disc > 1e-7 && rm < -1e-6;
    bool scroll = extended && !negativePoint && !negativeHorizonPatch;
    float rollingT = scroll ? iPenroseRollingT : tKS;
    bool singleHorizon = disc > 1e-7 && abs(rm) <= 1e-6;
    bool negativeInner = disc > 1e-7 && rm < -1e-6;
    bool rn = disc > 1e-7 && abs(a) < 1e-6 && Q2 > 1e-8;
    bool nakedPoint = disc < -1e-7 && abs(a) < 1e-6 && Q2 > 0.0;
    int baseCycle = !singleHorizon && cycle > 0 && r < rm ? cycle - 1 : cycle;
    float scale = disc <= 1e-7 || singleHorizon || negativePoint || negativeHorizonPatch
                ? min(size.x / 4.3, size.y / 4.3)
                : min(size.x / 4.3, size.y / 10.3);
    float linePx = MapFeatureLinePx();
    vec2 center = origin + 0.5 * size;
    vec2 marker = PenCameraPoint(r, tKS, rollingT, a, Q2,
                                 outgoing, negativeHorizonPatch ? false
                                   : extended ? iPenroseBranch > 0.5 : outgoing,
                                 effectiveSide, negativeHorizonPatch ? 0 : cycle,
                                 negativePoint);
    vec2 q = negativeHorizonPatch
           ? vec2(0.0, 1.0) + (pixel - center) / scale * vec2(-1.0, -1.0)
           : negativePoint
           ? (pixel - center) / scale * vec2(-1.0, 1.0)
           : (pixel - center) / scale
           + vec2(0.0, scroll ? marker.y
                   : (disc <= 1e-7 || negativePoint ? 0.0 : 4.0 * float(baseCycle) - 1.0));
    vec4 color = vec4(0.06, 0.08, 0.12, 0.28);
    vec4 gridColor = vec4(1.0, 1.0, 1.0, 0.18);
    vec3 outerColor = vec3(1.0, 0.39, 0.39);
    vec3 innerColor = vec3(80.0 / 255.0, 125.0 / 255.0, 1.0);
    if (disc <= 1e-7 || negativePoint) {
        float diamond = abs(q.x) + abs(q.y) - 2.0;
        // 无旋转的点奇点截断 r=0 两侧，只画观者所在的时空区域。
        if (diamond < 0.0 &&
            (negativePoint ? q.x <= 0.0 : (!nakedPoint || q.x >= 0.0))) {
            if (negativePoint) {
                color.rgb = mix(color.rgb, vec3(0.0, 1.0, 0.0), 0.32);
                color.a = max(color.a, 0.5);
            } else {
                color = mix(color, vec4(q.x < 0.0 ? vec3(0.0, 1.0, 0.0) : vec3(0.0), color.a),
                            q.x < 0.0 ? 0.08 : 0.0);
            }
            float gridFade = smoothstep(1.0, 3.0,
                                        -diamond * scale / 1.41421356);
            vec4 lineColor = vec4(gridColor.rgb, gridColor.a * gridFade);
            vec2 field = PenNakedInverse(q);
            vec2 dx = PenNakedInverse(q + vec2(1.0 / scale, 0.0)) - field;
            vec2 dy = PenNakedInverse(q + vec2(0.0, 1.0 / scale)) - field;
            vec2 fieldPx = vec2(length(vec2(dx.x, dy.x)), length(vec2(dx.y, dy.y)));
            color = PenTimeLines(color, lineColor, field.x + rollingT,
                                 fieldPx.x, 2.0, rollingT);
            for (int k = -3; k <= 3; k++) {
                if (!negativePoint && (k == 0 || (nakedPoint && k < 0))) continue;
                float rr = negativePoint ? -exp2(float(k + 2))
                                         : sign(float(k)) * exp2(float(abs(k) - 1));
                float star = PenTortoise(rr, a, Q2) - PenTortoise(0.0, a, Q2);
                color = PenGridLine(color, lineColor, field.y, star, fieldPx.y, 0.8);
            }
            if (!nakedPoint && !negativePoint)
                color = MapStroke(color, vec3(1.0, 0.0, 1.0),
                                  abs(q.x) * scale, 2.0 * linePx);
        }
        if ((nakedPoint || negativePoint) && abs(q.y) <= 2.0)
            color = MapStroke(color, vec3(1.0, 0.0, 1.0),
                              abs(q.x) * scale, 2.0 * linePx);
    } else {
        float root = sqrt(disc);
        float rp = 0.5 + root;
        float kp = root / (rp * rp + a * a);
        // 等时线的间距随外视界的时间尺度变化，并取成 2 的整数次幂。
        float timeSpacing = exp2(round(log2(1.0 / kp)));
        float ringStar = PenTortoise(0.0, a, Q2);
        int visibleTile = int(floor(q.y * 0.25));
        for (int dc = -1; dc <= 1; dc++) {
            if (singleHorizon && dc != 0) continue;
            int tile = singleHorizon ? 0 : visibleTile + dc;
            for (int region = 0; region < 6; region++) {
                if (singleHorizon && (region == 3 || region == 4)) continue;
                if (negativeHorizonPatch &&
                    !((tile == 0 && (region == 2 || region == 3 || region == 4)) ||
                      (tile == 1 && region == 5))) continue;
                vec2 c = PenCenter(region, float(tile));
                vec2 local = q - c;
                float diamond = abs(local.x) + abs(local.y) - 1.0;
                if (diamond > 0.04) continue;
                // 单视界时，黑洞与白洞都止于 r=0 的类空奇点线。
                if (singleHorizon &&
                    ((region == 2 && local.y > 0.0) ||
                     (region == 5 && local.y < 0.0))) continue;
                if (diamond < 0.0) {
                    // 无穷远旁的反变换趋于发散，差分线距只在图内侧可靠。
                    bool infinitySide = (region == 0 && local.x > 0.0) ||
                                        (region == 1 && local.x < 0.0) ||
                                        (region == 3 && local.x < 0.0) ||
                                        (region == 4 && local.x > 0.0);
                    float gridFade = infinitySide
                                   ? smoothstep(1.0, 3.0,
                                       -diamond * scale / 1.41421356) : 1.0;
                    vec4 lineColor = vec4(gridColor.rgb, gridColor.a * gridFade);
                    vec2 tilePoint = q - vec2(0.0, 4.0 * float(tile));
                    vec2 field = PenInverse(tilePoint, region, kp);
                    vec2 dx = PenInverse(tilePoint + vec2(1.0 / scale, 0.0),
                                         region, kp) - field;
                    vec2 dy = PenInverse(tilePoint + vec2(0.0, 1.0 / scale),
                                         region, kp) - field;
                    vec2 fieldPx = vec2(length(vec2(dx.x, dy.x)), length(vec2(dx.y, dy.y)));
                    float radialField = field.y;
                    bool innerRegion = region == 3 || region == 4;
                    // 无旋转时 r=0 是点奇点，负质量视界后的时空止于这条线。
                    if (negativeHorizonPatch && (region == 2 || region == 5) &&
                        radialField < ringStar) {
                        color = PenGridLine(color, vec3(1.0, 0.0, 1.0),
                                            radialField, ringStar, fieldPx.y,
                                            2.0 * linePx);
                        continue;
                    }
                    // RN 的 r=0 是边界，奇点线另一侧不属于图中的时空。
                    if (rn && innerRegion && radialField < ringStar) continue;
                    // 内视界落在负 r 时，负 r 外部占满 III 区，II 区也有一段属于反宇宙。
                    bool isAntiverse = negativeInner
                        ? innerRegion || ((region == 2 || region == 5) && radialField > ringStar)
                        : innerRegion && radialField < ringStar;
                    
                    vec3 tint = vec3(0.0);
                    if (negativeHorizonPatch && region == 4) {
                        tint = vec3(1.0, 1.0, 0.0);
                    } else if (region == 1) {
                        tint = int(mod(float(tile), 3.0)) == 0
                             ? vec3(1.0, 1.0, 0.0) : PenUniverseTint(tile);
                    } else if (isAntiverse) {
                        tint = vec3(0.0, 1.0, 0.0); // 负 r 反宇宙为绿色
                    } else if (region == 0 || region == 2 || region == 5 || innerRegion) {
                        tint = PenUniverseTint(tile);
                    }
                    
                    if (region == 2) {
                        color.rgb = vec3(0.008, 0.012, 0.018) + 0.08 * tint; // II区保留所属宇宙的暗色相
                        color.a = 0.78;                        // 大幅提高不透明度，表现黑洞吞噬感
                    } else {
                        float hasTint = dot(tint, vec3(1.0)) > 0.01 ? 1.0 : 0.0;
                        color.rgb = mix(vec3(0.06, 0.08, 0.12), tint, hasTint * 0.32);
                        if (hasTint > 0.5) color.a = max(color.a, 0.5);
                    }
                    color = PenTimeLines(color, lineColor,
                                         field.x + rollingT, fieldPx.x,
                                         timeSpacing, rollingT);
                    if (region == 0 || region == 1) {
                        for (int k = 0; k < 6; k++) {
                            float rr = rp + exp2(float(k) - 2.0);
                            color = PenGridLine(color, lineColor, radialField,
                                                PenTortoise(rr, a, Q2), fieldPx.y, 0.8);
                        }
                    } else if (region == 2 || region == 5) {
                        for (int k = 1; k <= 4; k++) {
                            float rr = mix(rm, rp, float(k) / 5.0);
                            color = PenGridLine(color, lineColor, radialField,
                                                PenTortoise(rr, a, Q2), fieldPx.y, 0.8);
                        }
                        if (negativeInner)
                            color = PenGridLine(color, vec4(1.0, 0.0, 1.0, gridFade),
                                                radialField, ringStar, fieldPx.y,
                                                2.0 * linePx);
                    } else {
                        for (int k = 0; k < 4; k++) {
                            float rr = rn ? rm * float(k + 1) / 5.0
                                      : negativeInner ? rm - exp2(float(k) - 2.0)
                                                      : -0.5 * float(k);
                            color = PenGridLine(color, lineColor, radialField,
                                                PenTortoise(rr, a, Q2), fieldPx.y, 0.8);
                        }
                        if (!negativeInner)
                            color = PenGridLine(color, vec4(1.0, 0.0, 1.0, gridFade),
                                                radialField, ringStar, fieldPx.y,
                                                2.0 * linePx);
                    }
                    color = MapStroke(color, vec3(0.7, 0.76, 0.85),
                                      PenRegionMark(local - vec2(0.0, 0.62), region) * scale, 0.9);
                }
                bool isTop = local.y > 0.0;
                bool isRight = local.x > 0.0;
                bool infinityEdge = (region == 0 && isRight) ||
                                    (region == 1 && !isRight) ||
                                    (region == 3 && !isRight) ||
                                    (region == 4 && isRight);
                vec3 edgeColor = outerColor;
                if (region == 2) {
                    edgeColor = isTop ? innerColor : outerColor;
                } else if (region == 5) {
                    edgeColor = !isTop ? innerColor : outerColor;
                } else if (region == 3 || region == 4) {
                    edgeColor = innerColor;
                }
                if (!infinityEdge &&
                    !(negativeHorizonPatch && (region == 2 || region == 5)))
                    color = MapStroke(color, edgeColor,
                                      abs(diamond) * scale / 1.41421356,
                                      2.0 * linePx);
            }
        }
        if (singleHorizon) {
            float singularity = min(MapSegment(q, vec2(-1.0, 0.0), vec2(1.0, 0.0)),
                                    MapSegment(q, vec2(-1.0, -2.0), vec2(1.0, -2.0)));
            color = MapStroke(color, vec3(1.0, 0.0, 1.0),
                              singularity * scale, 2.0 * linePx);
        }
    }
    color = MapStroke(color, vec3(1.0), length(q - marker) * scale, 3.0);
    return color;
}

// 光线追踪核心请查看 Common；全分辨率重建与合成在 Buffer A。
// See Common for ray tracing, and Buffer A for full-resolution reconstruction and composition.

// Buffer B/C/D 与 Image 来自 sonicether 的作品 "Gargantua With HDR Bloom"。
// Buffer B/C/D and Image  are adapted from sonicether's "Gargantua With HDR Bloom".

vec3 saturate(vec3 x)
{
    return clamp(x, vec3(0.0), vec3(1.0));
}

vec4 cubic(float x)
{
    float x2 = x * x;
    float x3 = x2 * x;
    vec4 w;
    w.x =   -x3 + 3.0*x2 - 3.0*x + 1.0;
    w.y =  3.0*x3 - 6.0*x2       + 4.0;
    w.z = -3.0*x3 + 3.0*x2 + 3.0*x + 1.0;
    w.w =  x3;
    return w / 6.0;
}

vec4 BicubicTexture(in sampler2D tex, in vec2 coord)
{
	vec2 resolution = iResolution.xy;

	coord *= resolution;

	float fx = fract(coord.x);
    float fy = fract(coord.y);
    coord.x -= fx;
    coord.y -= fy;

    fx -= 0.5;
    fy -= 0.5;

    vec4 xcubic = cubic(fx);
    vec4 ycubic = cubic(fy);

    vec4 c = vec4(coord.x - 0.5, coord.x + 1.5, coord.y - 0.5, coord.y + 1.5);
    vec4 s = vec4(xcubic.x + xcubic.y, xcubic.z + xcubic.w, ycubic.x + ycubic.y, ycubic.z + ycubic.w);
    vec4 offset = c + vec4(xcubic.y, xcubic.w, ycubic.y, ycubic.w) / s;

    vec4 sample0 = textureLod(tex, vec2(offset.x, offset.z) / resolution, 0.0);
    vec4 sample1 = textureLod(tex, vec2(offset.y, offset.z) / resolution, 0.0);
    vec4 sample2 = textureLod(tex, vec2(offset.x, offset.w) / resolution, 0.0);
    vec4 sample3 = textureLod(tex, vec2(offset.y, offset.w) / resolution, 0.0);

    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);

    return mix( mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

vec3 ColorFetch(vec2 coord)
{
 	return textureLod(iChannel0, coord, 0.0).rgb;   
}

vec3 BloomFetch(vec2 coord)
{
 	return BicubicTexture(iChannel3, coord).rgb;   
}

vec3 Grab(vec2 coord, const float octave, const vec2 offset)
{
 	float scale = exp2(octave);
    
    coord /= scale;
    coord -= offset;

    return BloomFetch(coord);
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

vec3 GetBloom(vec2 coord)
{
 	vec3 bloom = vec3(0.0);
    
    //Reconstruct bloom from multiple blurred images
    bloom += Grab(coord, 1.0, vec2(CalcOffset(0.0))) * 1.0;
    bloom += Grab(coord, 2.0, vec2(CalcOffset(1.0))) * 1.5;
	bloom += Grab(coord, 3.0, vec2(CalcOffset(2.0))) * 1.0;
    bloom += Grab(coord, 4.0, vec2(CalcOffset(3.0))) * 1.5;
    bloom += Grab(coord, 5.0, vec2(CalcOffset(4.0))) * 1.8;
    bloom += Grab(coord, 6.0, vec2(CalcOffset(5.0))) * 1.0;
    bloom += Grab(coord, 7.0, vec2(CalcOffset(6.0))) * 1.0;
    bloom += Grab(coord, 8.0, vec2(CalcOffset(7.0))) * 1.0;

	return bloom;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
#if SHADOW_CULL_DEBUG != 0
    fragColor = texelFetch(iChannel0, ivec2(fragCoord), 0);
    return;
#endif
    vec2 uv = fragCoord.xy / iResolution.xy;
    
    vec3 color = ColorFetch(uv);
    
    
    color += GetBloom(uv) * 0.08;
    

    //Tonemapping and color grading
    color = pow(color, vec3(1.5));
    color = color / (1.0 + color);
    color = pow(color, vec3(1.0 / 1.5));

    
    color = mix(color, color * color * (3.0 - 2.0 * color), vec3(1.0));
    color = pow(color, vec3(1.3, 1.20, 1.0));    

	color = saturate(color * 1.01);
    
    color = pow(color, vec3(0.7 / 2.2));

    fragColor = vec4(color, 1.0);
    vec4 parameters = texelFetch(iChannel1, ivec2(14, 0), 0);
    vec4 mapMeta = texelFetch(iChannel1, ivec2(17, 0), 0);
    iPenroseRollingT = mapMeta.z;
    iPenroseBranch = mapMeta.w;
    if (mapShowTopologyMap == 1 || mapShowPenroseMap == 1) {
        vec4 state = texelFetch(iChannel1, ivec2(5, 0), 0);
        vec3 camPos = texelFetch(iChannel1, ivec2(2, 0), 0).xyz;
        vec3 camDir = normalize(texelFetch(iChannel1, ivec2(3, 0), 0).xyz);
        mapUniverseSign = state.y;
        if (mapShowTopologyMap == 1) {
            vec4 overlay = RenderTopologyMap(fragCoord, camPos, camDir);
            fragColor.rgb = mix(fragColor.rgb, overlay.rgb, overlay.a);
        }
        if (mapShowPenroseMap == 1) {
            vec4 diagramEvent = texelFetch(iChannel1, ivec2(18, 0), 0);
            vec4 overlay = RenderPenroseMap(fragCoord, camPos, diagramEvent.x,
                                            state.y, diagramEvent.y > 0.5,
                                            int(round(parameters.w - 1024.0)),
                                            MAX_EXTENSION == 1);
            fragColor.rgb = mix(fragColor.rgb, overlay.rgb, overlay.a);
        }
    }


}
