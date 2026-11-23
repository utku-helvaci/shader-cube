const float WATER = -.62;
const float SIG = 9.0; 

const float SECONDS_PER_KEY = 5.;
const float DEPTH_SCALE = 10.;
const float SKY_DEPTH = 120.;
const float WATER_MAX_DEPTH = 80.;

const vec3 L = vec3(-.738, .422, .527);

float gMorph;

const int NK = 8;
const vec4 KEYS[NK] = vec4[NK](
    vec4(4.5, 1.20, .00, 2.4),
    vec4(3.0, .60, .00, 2.6),
    vec4(1.9, -.30, .10, 1.9),
    vec4(1.5, -.35, .20, 1.7),
    vec4(1.6, .50, .30, 2.0),
    vec4(1.5, 1.60, .00, 1.6),
    vec4(2.5, 1.00, .00, 2.4),
    vec4(3.8, .30, .00, 3.0));

vec4 key(int i) { return KEYS[((i % NK) + NK) % NK]; }

vec4 camPath(float u)
{
    int i = int(floor(u));
    float f = fract(u);
    vec4 p0 = key(i - 1), p1 = key(i), p2 = key(i + 1), p3 = key(i + 2);
    return .5 * (2. * p1 + (-p0 + p2) * f + (2. * p0 - 5. * p1 + 4. * p2 - p3) * f * f + (-p0 + 3. * p1 - 3. * p2 + p3) * f * f * f);
}

float morphAmount(float t)
{
    float p = fract(t / (float(NK) * SECONDS_PER_KEY));
    return smoothstep(.20, .40, p) - smoothstep(.75, .95, p);
}

float volS(vec3 p)
{
    return texture(iChannel0, .5 + .5 * p).r;
}

vec2 box(vec3 P, vec3 D)
{
    vec3 t0 = (-1. - P) / D, t1 = (1. - P) / D,
         m = min(t0, t1), M = max(t0, t1);
    return vec2(max(max(m.x, m.y), m.z), min(min(M.x, M.y), M.z));
}

vec3 sky(vec3 D)
{
    float y = max(D.y, 0.);
    vec3 c = mix(vec3(1., .62, .42), vec3(.08, .18, .42), pow(y, .45));
    float s = max(dot(D, L), 0.);
    c += vec3(1., .6, .3) * (pow(s, 8.) * .35 + pow(s, 400.) * 6.);
    return c;
}

vec3 albedo(vec3 p)
{
    vec3 sphereAlb = mix(vec3(.55, .08, .04), vec3(1., .55, .2), smoothstep(-.7, .5, p.y));

    float rad = length(p.xz);
    float tip = clamp(rad * .8 + (p.y + .5) * .45, 0., 1.);
    vec3 petalAlb = mix(vec3(1., .90, .86), vec3(.95, .28, .50), smoothstep(.15, .85, tip));
    float pod = smoothstep(.18, .12, rad) * smoothstep(-.34, -.28, p.y) * smoothstep(-.12, -.20, p.y);
    petalAlb = mix(petalAlb, vec3(.85, .70, .15), pod);

    return mix(sphereAlb, petalAlb, gMorph);
}

vec3 shade(vec3 p, vec3 N, vec3 D, float d)
{
    vec3 alb = albedo(p);
    float nl = dot(N, L);
    float dif = max(nl, 0.);
    float wrap = .5 + .5 * nl;
    wrap *= wrap;
    float ao = mix(.35, 1., clamp(volS(p + N * .06) / .06, 0., 1.));
    vec3 H = normalize(L - D);
    float spec = pow(max(dot(N, H), 0.), 60.);
    float fre = pow(1. - max(dot(N, -D), 0.), 3.);
    vec3 amb = mix(vec3(.04, .09, .10), vec3(.25, .30, .45), .5 + .5 * N.y);
    

    float tr = pow(max(dot(D, L), 0.), 3.) * exp(d * 15.0);
    vec3 trCol = mix(vec3(1., .6, .3), vec3(1., .65, .7), gMorph);

    vec3 c = alb * (vec3(1., .85, .7) * (dif * 1.2 + wrap * .3) + amb) * ao;
    c += spec * vec3(1., .8, .6) * 0.5 * ao;
    c += fre * sky(reflect(D, N)) * .35 * ao;
    c += alb * trCol * tr * 0.8; 
    return c;
}

vec4 volume(vec3 p, vec3 D, float l, float lmax, out float depth)
{
    const vec3 h = vec3(.03, 0, 0);
    vec3 col = vec3(0);
    float T = 1., r = 1., i = 0., dl = 1. / 128.;
    depth = 1e9;
    p += l * D;

    for (; l < lmax && r > .01 && i < 30.; i++, p += r * D, l += r)
        r = volS(p);

    for (; l < lmax && T > .01 && i < 1200.; i++, p += dl * D, l += dl) {
        float d = volS(p);
        float a = smoothstep(0., -1. / 128., d);
        if (a > 0.) {
            vec3 N = normalize(vec3(volS(p + h.xyy) - volS(p - h.xyy),
                volS(p + h.yxy) - volS(p - h.yxy),
                volS(p + h.yyx) - volS(p - h.yyx)));
            
            col += shade(p, N, D, d) * T * a * dl * 9.0;
            T *= exp(-9.0 * a * dl);
            
            if (depth > 1e8 && T < .5)
                depth = l;
        }
    }
    return vec4(col, T);
}

vec2 waterSlope(vec2 q, float t, float dist)
{
    vec2 swell = vec2(0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec2 dr = vec2(cos(fi * 2.4 + .3), sin(fi * 2.4 + .3));
        float f = 1.4 * pow(1.6, fi);
        swell += dr * cos(dot(q, dr) * f + t * (.5 + .2 * fi)) * .035 / (1. + .6 * fi);
    }

    vec2 ripple = vec2(0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        vec2 dr = vec2(cos(fi * 2.1 + 1.2), sin(fi * 2.1 + 1.2));
        float f = 9. * pow(1.5, fi);
        ripple += dr * cos(dot(q, dr) * f + t * (1.6 + .5 * fi)) * .018 / (1. + fi);
    }

    float rad = length(q);
    vec2 radial = q / max(rad, 1e-3);
    float env = smoothstep(.5, .9, rad) * exp(-max(rad - .8, 0.) * .9);
    float rings = (cos(rad * 16. - t * 2.2) * .06
                    + cos(rad * 27. - t * 3.1) * .025)
        * env;

    return swell / (1. + .05 * dist)
        + ripple / (1. + .25 * dist)
        + radial * rings / (1. + .15 * dist);
}

void mainImage(out vec4 fragColor, vec2 fragCoord)
{
    float t = iTime;
    vec2 uv = (2. * fragCoord - iResolution.xy) / iResolution.y;

    gMorph = morphAmount(t);

    vec4 k = camPath(t / SECONDS_PER_KEY);
    float theta = .22 * t + .35 * sin(.17 * t);
    float height = max(k.y, WATER + .2);

    vec3 P = vec3(k.x * sin(theta), height, k.x * cos(theta));
    vec3 T3 = vec3(0., k.z - .1, 0.);

    P += .02 * vec3(sin(t * 1.3), sin(t * 1.7 + 1.), sin(t * 1.1 + 2.));
    T3 += .015 * vec3(sin(t * 1.9 + 3.), sin(t * 1.5), sin(t * 1.2 + 1.));

    float roll = .03 * sin(.4 * t);
    vec3 up = vec3(sin(roll), cos(roll), 0.);

    vec3 ww = normalize(T3 - P),
         uu = normalize(cross(ww, up)),
         vv = cross(uu, ww),
         D = normalize(uv.x * uu + uv.y * vv + k.w * ww);

    if (fragCoord.x < 1. && fragCoord.y < 1.) {
        vec3 s = vec3(dot(L, uu), dot(L, vv), dot(L, ww));
        vec2 sUv = s.xy * k.w / max(s.z, 1e-3);
        vec2 sTex = .5 + .5 * sUv * vec2(iResolution.y / iResolution.x, 1.);
        float facing = smoothstep(0., .3, s.z) * .99;
        fragColor = vec4(sTex, facing, SKY_DEPTH);
        return;
    }

    vec2 B = box(P, D);
    float tw = D.y < -1e-3 ? (WATER - P.y) / D.y : 1e9;
    vec4 V = vec4(0, 0, 0, 1);
    float volDepth = 1e9;
    if (B.x < B.y && B.y > 0.)
        V = volume(P, D, max(B.x, 0.), min(B.y, tw), volDepth);

    vec3 bg;
    float depth = SKY_DEPTH;
    if (tw < 1e8) {
        vec3 ph = P + tw * D;
        depth = min(tw * DEPTH_SCALE, WATER_MAX_DEPTH);

        vec2 g = waterSlope(ph.xz, t, tw);
        vec3 Nw = normalize(vec3(-g.x, 1., -g.y));

        vec3 Rf = reflect(D, Nw);
        Rf.y = abs(Rf.y);
        vec2 B2 = box(ph, Rf);
        vec4 V2 = vec4(0, 0, 0, 1);
        float unusedDepth;
        if (B2.x < B2.y && B2.y > 0.)
            V2 = volume(ph, Rf, max(B2.x, 0.), B2.y, unusedDepth);
        vec3 refl = V2.rgb + V2.a * sky(Rf);

        float F = .10 + .90 * pow(1. - max(dot(Nw, -D), 0.), 4.);
        vec3 deep = vec3(.004, .022, .035) + vec3(0, .02, .02) * (.5 + .5 * Nw.x);
        vec3 wc = mix(deep, refl, F);
        bg = mix(sky(normalize(vec3(D.x, 0., D.z))), wc, exp(-.03 * tw));
    } else
        bg = sky(D);

    if (volDepth < 1e8)
        depth = volDepth * DEPTH_SCALE;

    fragColor = vec4(V.rgb + V.a * bg, depth);
}