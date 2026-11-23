#if iUseImageDisk != 0
#define RAY_DISK_TEXTURE iChannel0
#else
#define RAY_DISK_TEXTURE iChannel1
#endif

// iChannel0: 盘贴图；1: D；2: B；3: A 自反馈。所有 Buffer 使用 RGBA32F。
void mainImage(out vec4 FragColor, in vec2 FragCoord)
{
    rayResolution = iResolution;
    vec2 Uv = FragCoord / iResolution.xy;
    if (!LoadRayCamera(iChannel2)) {
        FragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    iTraceTime = iTime;
    TraceResult res;
    bool retrace = true;
    if (RayPrepassEnabled() && all(equal(textureSize(iChannel1, 0), ivec2(iResolution.xy)))) {
        vec4 meta = texelFetch(iChannel1, RayAtlasPixel(0), 0);
        vec4 settings = texelFetch(iChannel1, RayAtlasPixel(1), 0);
        bool valid = all(equal(meta.xy, iResolution.xy)) && meta.w == float(iFrame - 1)
            && settings.x == float(RAY_DOWNSAMPLE) && settings.w == 7391.0;
        if (valid) {
            // B 的上一帧相机与 D 的上一帧预计算同属一个状态，随机采样时间也必须一致。
            iTraceTime = meta.z;
            vec2 low = (FragCoord - 0.5) / float(RAY_DOWNSAMPLE);
            ivec2 size = RayLowSize();
            ivec2 base = min(ivec2(floor(low)), size - 2);
            // 最后一列/行的锚点落在屏幕末端；奇数尺寸也无需外推或整条边界重算。
            vec2 start = vec2(base * RAY_DOWNSAMPLE);
            vec2 end = mix(vec2((base + 1) * RAY_DOWNSAMPLE), iResolution.xy - 1.0, equal(base, size - 2));
            vec2 weight = (FragCoord - 0.5 - start) / (end - start);
            TraceResult a = RayFetch(iChannel1, base);
            TraceResult b = RayFetch(iChannel1, base + ivec2(1, 0));
            TraceResult c = RayFetch(iChannel1, base + ivec2(0, 1));
            TraceResult d = RayFetch(iChannel1, base + ivec2(1, 1));
            retrace = RayNeedsTrace(a, b, c, d);
            if (!retrace) res = RayInterpolate(iChannel1, base, a, b, c, d, weight);
        }
    }
    // 单一追踪调用点；边界块整体重算，不按棋盘分支复用个别锚点。
    if (retrace) res = TraceRay(Uv, iResolution.xy, 0, RAY_DISK_TEXTURE);
#if SHADOW_CULL_DEBUG != 0
    FragColor = vec4(shadowCullDebugColor, 1.0);
    return;
#endif
    vec4 FinalColor = res.AccumColor;
    vec3 dDdx = dFdx(res.EscapeDir);
    vec3 dDdy = dFdy(res.EscapeDir);
    vec3 viewDir = FragUvToDir(Uv, tan(iFovRadians * 0.5), iResolution.xy);
    float screen = length(cross(dFdx(viewDir), dFdy(viewDir)));
    int skyStatus = int(round(res.Status)) % 3;
    if (skyStatus == 1 || skyStatus == 2) {
        float lensed = length(cross(dDdx, dDdy));
        float magnification = screen / max(lensed, 1e-12);
        vec4 Bg = SampleBackground(res.EscapeDir, res.FreqShift, res.Status,
                                   magnification, screen);
        float invA = 1.0 - FinalColor.a;
        FinalColor += 0.9999 * Bg * vec4(pow(invA, 1.0), pow(invA, 1.6), pow(invA, 2.5), 1.0);
    }
    // if (retrace) FinalColor = vec4(1.0, 0.0, 0.25, 1.0); // 重算区域 / Retraced pixels
    FinalColor = ApplyToneMapping(FinalColor, res.FreqShift);
    vec4 PrevColor = texelFetch(iChannel3, ivec2(FragCoord), 0);
    FragColor = iBlendWeight * FinalColor + (1.0 - iBlendWeight) * PrevColor;
}
