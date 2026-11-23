// ============================================================
//  Adapted from Volumetric Perlin to exact SDF by FabriceNeyret2
//  https://www.shadertoy.com/view/NXGSRK
// ============================================================

const float EPS = .1;
const float VOXEL = 2. / 128.;
const int OCTAVES = 6;
const float LOTUS_NOISE = .15;
const float LOTUS_BASE = -.5;
const vec3 HASH_SEED = vec3(467., 581., 389.);

const int UPDATE_EVERY = 1;

const float SECONDS_PER_KEY = 5.;
const int KEY_COUNT = 8;
const float DEBUG_MORPH = -1.;

float morphAmount(float t)
{
    float p = fract(t / (float(KEY_COUNT) * SECONDS_PER_KEY));
    return smoothstep(.20, .40, p) - smoothstep(.75, .95, p);
}
float currentMorph(float t) { return DEBUG_MORPH >= 0. ? DEBUG_MORPH : morphAmount(t); }

vec3 gradientAt(vec3 cell)
{
    mat3 seeds = mat3(HASH_SEED, 73. - HASH_SEED, HASH_SEED.zxy);
    return 2. * fract(sin(cell * seeds) * 3758.54) - 1.;
}

float cornerValue(vec3 x, vec3 cell, vec3 offset)
{
    vec3 corner = cell + offset;
    return dot(gradientAt(corner), x - corner);
}

float perlinAbs(vec3 x)
{
    vec3 cell = floor(x);
    vec3 w = smoothstep(0., 1., fract(x));

    float n000 = cornerValue(x, cell, vec3(0, 0, 0));
    float n100 = cornerValue(x, cell, vec3(1, 0, 0));
    float n010 = cornerValue(x, cell, vec3(0, 1, 0));
    float n110 = cornerValue(x, cell, vec3(1, 1, 0));
    float n001 = cornerValue(x, cell, vec3(0, 0, 1));
    float n101 = cornerValue(x, cell, vec3(1, 0, 1));
    float n011 = cornerValue(x, cell, vec3(0, 1, 1));
    float n111 = cornerValue(x, cell, vec3(1, 1, 1));

    float nx00 = mix(n000, n100, w.x);
    float nx10 = mix(n010, n110, w.x);
    float nx01 = mix(n001, n101, w.x);
    float nx11 = mix(n011, n111, w.x);

    float nxy0 = mix(nx00, nx10, w.y);
    float nxy1 = mix(nx01, nx11, w.y);

    return 2. * abs(mix(nxy0, nxy1, w.z));
}

float turbulence(vec3 x)
{
    float sum = 0.;
    float scale = 1.;
    for (int i = 0; i < OCTAVES; i++) {
        sum += perlinAbs(x) / scale;
        x *= 2.;
        scale *= 2.;
    }
    return sum;
}

float hash11(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

// IQ's approximate ellipsoid distance formula
float ellipsoid(vec3 p, vec3 radii)
{
    float k0 = length(p / radii);
    float k1 = length(p / (radii * radii));
    return k0 * (k0 - 1.) / max(k1, 1e-4);
}

float petalRing(vec3 q, float count, float rotation, float baseRadius, float baseHeight,
    float tilt, float petalLength, float petalWidth, float thickness,
    float bend, float cup, float seed)
{
    float radius = length(q.xz);
    float angle = atan(q.z, q.x) - rotation;
    float sector = 6.2831853 / count;
    float petalIndex = round(angle / sector);
    float localAngle = angle - petalIndex * sector;

    float d = 1e9;

    for (int j = -1; j <= 1; j++) {
        float a = localAngle + float(j) * sector;
        float petalId = mod(petalIndex - float(j), count);
        float h = hash11(petalId + seed * 31.);

        float petalTilt = tilt + .12 * (h - .5);
        float len = petalLength * (.9 + .2 * h);

        vec3 p = vec3(radius * cos(a) - baseRadius,
            q.y - baseHeight,
            radius * sin(a));

        float c = cos(petalTilt), s = sin(petalTilt);
        float u = p.x * c + p.y * s;
        float v = -p.x * s + p.y * c;
        v -= bend * u * u + cup * p.z * p.z;

        d = min(d, ellipsoid(vec3(u - .5 * len, v, p.z), vec3(.5 * len, thickness, petalWidth)));
    }
    return d;
}
float lotusShape(vec3 q)
{
    float b = LOTUS_BASE;
    float d = 1e9;
    // Did try procedual generation.But did not manage
    // to get the lotus shape i wanted.
    d = min(d, petalRing(q, 9., 0., .10, b, .45, .85, .17, .075, .25, 2.0, 1.)); // outer, spreading
    d = min(d, petalRing(q, 9., .349, .10, b + .02, .75, .85, .16, .075, .30, 2.5, 2.));
    d = min(d, petalRing(q, 8., 0., .11, b + .04, 1.00, .80, .15, .07, .30, 2.5, 3.));
    d = min(d, petalRing(q, 7., .449, .12, b + .06, 1.20, .65, .13, .07, .30, 3.0, 4.));
    d = min(d, petalRing(q, 6., 0., .14, b + .08, 1.38, .48, .10, .065, .20, 3.0, 5.)); // inner, upright

    vec3 p = q - vec3(0., b + .28, 0.);
    vec2 w = vec2(length(p.xz) - .10, abs(p.y) - .03);
    float pod = min(max(w.x, w.y), 0.) + length(max(w, 0.)) - .03;
    d = min(d, pod);

    d = min(d, length(q - vec3(0., b + .04, 0.)) - .12);

    return d;
}

float targetField(vec3 voxel, float m)
{
    vec3 q = voxel / 64. - 1.;
    float n = turbulence(q) / 2. - .274;

    float sphere = 0., lotus = 0.;
    if (m < 1.)
        sphere = length(q) - .6 + 2. * n - .1;
    if (m > 0.)
        lotus = lotusShape(q) + LOTUS_NOISE * n;
    return mix(sphere, lotus, m);
}

void mainVolume(out vec4 O, vec3 V)
{
    float m = currentMorph(iTime);

    bool changing = abs(m - currentMorph(iTime - 2.)) > 1e-5;
    bool needsUpdate = iFrame < 100 || (changing && iFrame % UPDATE_EVERY == 0);

    if (iFrame >= 1 && !needsUpdate) {
        O = texelFetch(iChannel0, ivec3(V), 0);
    }

    float field = targetField(V, m);
    if (field <= EPS) {
        O = vec4(field, 0., 0., 0.);
        return;
    }

  

    float best = 1e9;
    float bestLen = 0.;
    for (int k = 0; k < 27; k++) {
        if (k == 13)
            continue;
        vec3 offset = vec3(k % 3, (k / 3) % 3, k / 9) - 1.;
        ivec3 nb = clamp(ivec3(V) + ivec3(offset), ivec3(0), ivec3(127));
        float value = texelFetch(iChannel0, nb, 0).r;
        if (value < best) {
            best = value;
            bestLen = length(offset);
        }
    }
    O = vec4(best + bestLen * VOXEL, 0., 0., 0.);
}
