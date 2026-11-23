#if iUseImageDisk != 0
#define RAY_DISK_TEXTURE iChannel0
#else
#define RAY_DISK_TEXTURE iChannel1
#endif

//Vertical gaussian blur leveraging hardware filtering for fewer texture lookups.

vec3 ColorFetch(vec2 coord)
{
 	return textureLod(iChannel1, coord, 0.0).rgb;   
}

float weights[5];
float offsets[5];


void RenderBloom( out vec4 fragColor, in vec2 fragCoord )
{    
    
    weights[0] = 0.19638062;
    weights[1] = 0.29675293;
    weights[2] = 0.09442139;
    weights[3] = 0.01037598;
    weights[4] = 0.00025940;
    
    offsets[0] = 0.00000000;
    offsets[1] = 1.41176471;
    offsets[2] = 3.29411765;
    offsets[3] = 5.17647059;
    offsets[4] = 7.05882353;
    
    vec2 uv = fragCoord.xy / iResolution.xy;
    
    vec3 color = vec3(0.0);
    float weightSum = 0.0;
    
    if (uv.x < 0.52)
    {
        color += ColorFetch(uv) * weights[0];
        weightSum += weights[0];

        for(int i = 1; i < 5; i++)
        {
            vec2 offset = vec2(offsets[i]) / iResolution.xy;
            color += ColorFetch(uv + offset * vec2(0.0, 0.5)) * weights[i];
            color += ColorFetch(uv - offset * vec2(0.0, 0.5)) * weights[i];
            weightSum += weights[i] * 2.0;
        }

        color /= weightSum;
    }

    fragColor = vec4(color,1.0);
}
// iChannel0: 与 A 相同的盘贴图；1: C；2: B。左侧沿用纵向 Bloom，右侧生成下一次 A 所需的光线。
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    rayResolution = iResolution;
    if (RayPrepassEnabled() && int(fragCoord.x) >= RayAtlasStart()) {
        ivec2 outputPixel = ivec2(fragCoord);
        if (all(equal(outputPixel, RayAtlasPixel(0)))) {
            fragColor = vec4(iResolution.xy, iTime, float(iFrame));
            return;
        }
        if (all(equal(outputPixel, RayAtlasPixel(1)))) {
            fragColor = vec4(float(RAY_DOWNSAMPLE), 0.0, 0.0, 7391.0);
            return;
        }
        ivec2 size = RayLowSize();
        // 用矩形条带保持邻近 GPU 线程的光线方向接近，避免线性展平造成跨行分支发散。
        int tile = outputPixel.y / size.y;
        int localX = outputPixel.x - RayAtlasStart();
        ivec2 lowPixel = ivec2(localX + tile * RayAtlasTileWidth(), outputPixel.y % size.y);
        if (localX < RayAtlasTileWidth() && lowPixel.x < size.x) {
            vec2 pixel = vec2(lowPixel) * float(RAY_DOWNSAMPLE) + 0.5;
            pixel = mix(pixel, iResolution.xy - 0.5, equal(lowPixel, size - 1));
            if (!LoadRayCamera(iChannel2)) {
                fragColor = vec4(0.0);
                return;
            }
            iTraceTime = iTime;
            TraceResult ray = TraceRay(pixel / iResolution.xy, iResolution.xy, RAY_PREPASS_STEPS, RAY_DISK_TEXTURE);
            fragColor = RayPack(ray);
            return;
        }
        fragColor = vec4(0.0);
        return;
    }
    RenderBloom(fragColor, fragCoord);
}
