/*
 * ============================================================================
 * SHADER: Metamorphosis Volume
 * AUTHOR: dathor
 *
 *  ADDITIONAL CREDITS:   
 * -Based in the fantatic Volumetric Perlin to exact SDF by FabriceNeyret2
 *     https://www.shadertoy.com/view/NXGSRK
 * 
 *
 * 
 * ----------------------------------------------------------------------------
 * DESCRIPTION:
 * A volumetric shape that slowly morphs between a turbulent Perlin cloud and
 * a lotus flower, floating on reflective water at sunset. Both shapes are
 * baked into a 128^3 distance-field volume, so rays can sphere-march up to
 * the surface and then step through the shape for soft, translucent shading.
 *
 * A keyframed camera orbits, skims the water, swoops over the bloom and
 * pulls back in a 40 second loop. The morph is timed to the shots.
 * The water has swells, ripples and rings spreading from the flower, and it
 * reflects both the shape and the sky.
 *
 * A post-process pass adds depth of field, bloom, atmospheric haze and sun
 * god rays, plus a film grade and letterbox bars.
 * ----------------------------------------------------------------------------
 * DEVELOPER NOTES:
     
      Based on the fantatic Volumetric Perlin to exact SDF by FabriceNeyret2
      https://www.shadertoy.com/view/NXGSRK

      The rest is kind of a mashup of prior work.  

      
*/

const float SHOT_LEN = 40.0;
const float FADE = 1.5;

const float EXPOSURE = 0.9;

const float BLOOM_RADIUS = .02;
const float BLOOM_GAIN = 1.5;
// const vec3  BLOOM_TINT   = vec3(1.0, 0.82, 0.95);
const vec3 BLOOM_TINT = vec3(1.0, 0.72, 0.45);

const float MIST_GAIN = 0.5;
const float MIST_VEIL = 0.30;
const vec3 MIST_TINT = vec3(0.55, 0.75, 1.0);
const vec3 VEIL_COL = vec3(0.10, 0.18, 0.30);

const float RAYS_GAIN = 1.1;
const float RAYS_DECAY = 0.965;
const float RAYS_DENSITY = 0.95;
const vec3 RAYS_TINT = vec3(1.0, 0.70, 0.42);
const float SUN_CORE = 0.012;
const float SUN_HALO = 3.0;

float luma(vec3 color) { return dot(color, vec3(0.299, 0.587, 0.114)); }

float hash12(vec2 p)
{
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p)
{
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += a * vnoise2(p);
        p = p * 2.02 + vec2(3.1, 1.7);
        a *= 0.5;
    }
    return s;
}

float shotFade(float T)
{
    float lt = mod(T, SHOT_LEN);
    float fin = (T < FADE) ? 1.0 : smoothstep(0.0, FADE, lt);
    float fout = smoothstep(0.0, FADE, SHOT_LEN - lt);
    return fin * fout;
}

vec3 karisTap(vec2 uv, vec2 ts)
{
    vec3 c0 = texture(iChannel0, uv).rgb;
    vec3 c1 = texture(iChannel0, uv + vec2(-0.75, -0.75) * ts).rgb;
    vec3 c2 = texture(iChannel0, uv + vec2(0.75, -0.75) * ts).rgb;
    vec3 c3 = texture(iChannel0, uv + vec2(-0.75, 0.75) * ts).rgb;
    vec3 c4 = texture(iChannel0, uv + vec2(0.75, 0.75) * ts).rgb;
    float w0 = 2.0 / (1.0 + luma(c0));
    float w1 = 1.0 / (1.0 + luma(c1));
    float w2 = 1.0 / (1.0 + luma(c2));
    float w3 = 1.0 / (1.0 + luma(c3));
    float w4 = 1.0 / (1.0 + luma(c4));
    return (c0 * w0 + c1 * w1 + c2 * w2 + c3 * w3 + c4 * w4) / (w0 + w1 + w2 + w3 + w4);
}

float cocOf(float depth)
{
    float c = smoothstep(20.0, 70.0, abs(depth - 25.0)) * 0.6;
    c *= 1.0 - smoothstep(85.0, 105.0, depth);
    return max(c, smoothstep(12.0, 0.0, depth));
}

vec3 farBloom(vec2 uv, float dither, float bar, float aspect)
{
    const int N = 24;
    const float GOLDEN = 2.39996323;
    vec3 acc = vec3(0.0);
    for (int i = 0; i < N; i++) {
        float r = sqrt((float(i) + 0.5) / float(N)) * BLOOM_RADIUS;
        float th = float(i) * GOLDEN + dither * 6.28318;
        vec2 off = vec2(cos(th), sin(th)) * r;
        off.x /= aspect;
        vec2 q = vec2(clamp(uv.x + off.x, 0.0, 1.0), clamp(uv.y + off.y, bar, 1.0 - bar));
        vec4 s = texture(iChannel0, q);
        float far = smoothstep(30.0, 60.0, s.a) * (1.0 - smoothstep(105.0, 115.0, s.a));
        float L = luma(s.rgb);
        float hot = max(L - 0.25, 0.0);
        acc += s.rgb * (hot * far / (1.0 + L));
    }
    return acc / float(N) * BLOOM_GAIN * BLOOM_TINT;
}

vec3 sampleAtmosphere(vec2 uv, float dither, float aspect, float depth)
{
    float isSky = smoothstep(90.0, 110.0, depth);
    float surf = 1.0 - isSky;

    vec2 q = vec2(uv.x * aspect, uv.y) * 2.0;
    float n = fbm2(q + vec2(iTime * 0.012, -iTime * 0.008));
    float n2 = fbm2(q * 2.2 + vec2(-iTime * 0.02, iTime * 0.01) + 5.2);
    float wisps = smoothstep(0.35, 0.75, n * 0.65 + n2 * 0.35);

    float farFog = smoothstep(30.0, 52.0, depth) * surf;
    vec3 hazeCol = VEIL_COL * MIST_VEIL * farFog * (0.4 + 0.6 * wisps);

    vec3 halo = vec3(0.0);
    if (isSky > 0.01) {
        const int TAPS = 16;
        const float GOLDEN_ANGLE = 2.39996323;
        const float maxRad = 0.07;
        vec3 acc = vec3(0.0);
        float wsum = 0.0;
        for (int j = 0; j < TAPS; j++) {
            float r = sqrt((float(j) + 0.5) / float(TAPS)) * maxRad;
            float a = float(j) * GOLDEN_ANGLE + dither * 6.28318;
            vec2 off = vec2(cos(a), sin(a)) * r;
            off.x /= aspect;
            vec4 s = texture(iChannel0, clamp(uv + off, 0.0, 1.0));
            float sSurf = 1.0 - smoothstep(90.0, 110.0, s.a);
            float wg = 1.0 - 0.7 * (r / maxRad);
            acc += s.rgb * sSurf * wg / (1.0 + luma(s.rgb));
            wsum += wg;
        }
        halo = (acc / wsum) * MIST_GAIN * MIST_TINT * (0.5 + 0.8 * wisps);
    }

    return hazeCol + halo * isSky;
}

vec3 godRays(vec2 uv, vec2 sunUV, float facing, float dither, float aspect)
{
    if (facing <= 0.0)
        return vec3(0.0);

    const int N = 48;
    vec2 delta = (sunUV - uv) * RAYS_DENSITY / float(N);
    vec2 pos = uv + delta * dither;
    float illum = 1.0;
    float sum = 0.0;

    for (int i = 0; i < N; i++) {

        vec2 dv = (pos - sunUV) * vec2(aspect, 1.0);
        float d2 = dot(dv, dv);
        float glow = exp(-d2 / SUN_CORE) + 0.15 * exp(-sqrt(d2) * SUN_HALO);

        float open = 1.0;
        if (pos.x >= 0.0 && pos.x <= 1.0 && pos.y >= 0.0 && pos.y <= 1.0)
            open = smoothstep(90.0, 110.0, texture(iChannel0, pos).a);

        sum += glow * open * illum;
        illum *= RAYS_DECAY;
        pos += delta;
    }

    float s = sum / float(N);
    s = pow(s, 0.8);
    return RAYS_TINT * s * RAYS_GAIN * facing;
}

void mainImage(out vec4 fragColor, vec2 fragCoord)
{
    vec2 texelSize = 1.0 / iResolution.xy;
    vec2 uv = fragCoord * texelSize;

    float targetAspect = 2.35;
    float screenAspect = iResolution.x / iResolution.y;
    float barHeight = max(0.0, (1.0 - (screenAspect / targetAspect)) / 2.0);

    if (uv.y < barHeight || uv.y > 1.0 - barHeight) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    vec2 vUV = uv - 0.5;
    float distSq = dot(vUV, vUV);
    vec2 caOffset = vUV * 0.003 * distSq;

    vec3 sharpColor;
    sharpColor.r = karisTap(clamp(uv - caOffset, 0.0, 1.0), texelSize).r;
    sharpColor.g = karisTap(clamp(uv, 0.0, 1.0), texelSize).g;
    sharpColor.b = karisTap(clamp(uv + caOffset, 0.0, 1.0), texelSize).b;

    float pixelDepth = texture(iChannel0, uv).a;
    float coc = cocOf(pixelDepth);

    vec3 sceneCol = sharpColor;
    float dither = fract(sin(dot(fragCoord, vec2(12.9898, 78.233))) * 43758.5453);

    if (coc > 0.01) {
        const int TAPS = 16;
        const float GOLDEN_ANGLE = 2.39996323;
        float radius = coc * 0.0055;
        float randomAngle = dither * 6.28318;

        vec3 acc = vec3(0.0);
        float wSum = 0.0;
        for (int i = 0; i < TAPS; i++) {
            float r = sqrt(float(i) + 0.5) / sqrt(float(TAPS));
            float theta = float(i) * GOLDEN_ANGLE + randomAngle;
            vec2 offset = vec2(cos(theta), sin(theta)) * r * radius;
            offset.x /= screenAspect;

            vec4 tap = texture(iChannel0, clamp(uv + offset, 0.0, 1.0));

            float w = 1.0;
            if (tap.a < pixelDepth)
                w = clamp(cocOf(tap.a) / max(coc, 1e-3), 0.0, 1.0);
            w *= 1.0 / (1.0 + luma(tap.rgb));

            acc += tap.rgb * w;
            wSum += w;
        }
        vec3 blurredColor = (wSum > 0.001) ? acc / wSum : sharpColor;
        sceneCol = mix(sharpColor, blurredColor, smoothstep(0.01, 0.1, coc));
    }

    sceneCol += farBloom(uv, dither, barHeight, screenAspect);

    sceneCol += sampleAtmosphere(uv, dither, screenAspect, pixelDepth);

    vec4 sunInfo = texelFetch(iChannel0, ivec2(0, 0), 0);
    sceneCol += godRays(uv, sunInfo.xy, sunInfo.z, dither, screenAspect);

    vec3 finalColor = sceneCol * EXPOSURE;
    finalColor = finalColor / (1.0 + finalColor);
    finalColor = pow(max(finalColor, 0.0), vec3(1.0 / 2.2));

    float lum = luma(finalColor);
    // vec3 shadowTint = vec3(0.92, 0.96, 1.05);
    vec3 shadowTint = vec3(0.85, 0.97, 1.10);
    // vec3 highlightTint = vec3(1.05, 1.01, 0.95);
    vec3 highlightTint = vec3(1.10, 1.00, 0.88);
    finalColor *= mix(shadowTint, highlightTint, smoothstep(0.1, 0.8, lum));

    // finalColor = mix(vec3(lum), finalColor, 1.05);
    finalColor = mix(vec3(lum), finalColor, 1.15);
    finalColor = mix(finalColor, smoothstep(0.0, 1.0, finalColor), 0.5);

    float vignetteRadial = smoothstep(1.4, 0.35, length(vUV));
    finalColor *= mix(0.72, 1.0, vignetteRadial);

    finalColor += (dither - 0.5) * (1.5 / 255.0);
    finalColor *= shotFade(iTime);
    
    

    fragColor = vec4(clamp(finalColor, 0.0, 1.0), 1.0);
}
