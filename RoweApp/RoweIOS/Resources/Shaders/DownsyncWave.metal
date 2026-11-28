#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Vivid full-spectrum 7-stop rainbow palette:
/// red -> orange -> yellow -> emerald green -> electric cyan -> royal blue -> violet (loops smoothly).
static float3 prismRainbow(float x) {
    float t = fract(x) * 7.0f;
    float3 c0 = float3(1.00f, 0.24f, 0.32f); // vivid red
    float3 c1 = float3(1.00f, 0.56f, 0.16f); // warm orange
    float3 c2 = float3(1.00f, 0.88f, 0.20f); // sunlit yellow
    float3 c3 = float3(0.22f, 0.90f, 0.46f); // emerald green
    float3 c4 = float3(0.16f, 0.84f, 1.00f); // electric cyan
    float3 c5 = float3(0.30f, 0.46f, 1.00f); // royal blue
    float3 c6 = float3(0.76f, 0.32f, 1.00f); // vivid violet

    if (t < 1.0f) return mix(c0, c1, smoothstep(0.0f, 1.0f, t));
    if (t < 2.0f) return mix(c1, c2, smoothstep(0.0f, 1.0f, t - 1.0f));
    if (t < 3.0f) return mix(c2, c3, smoothstep(0.0f, 1.0f, t - 2.0f));
    if (t < 4.0f) return mix(c3, c4, smoothstep(0.0f, 1.0f, t - 3.0f));
    if (t < 5.0f) return mix(c4, c5, smoothstep(0.0f, 1.0f, t - 4.0f));
    if (t < 6.0f) return mix(c5, c6, smoothstep(0.0f, 1.0f, t - 5.0f));
    return mix(c6, c0, smoothstep(0.0f, 1.0f, t - 6.0f));
}

/// 2-phase optical sync shader for iOS:
/// - Full-spectrum rainbow prism sweep (zero green/pink chromatic fringing)
/// - Zero-ghosting exit: lens displacement & blur decay smoothly to 0 BEFORE alpha fades out
/// - Local wave-only premultiplied alpha so untouched pixels remain 100% live & transparent
[[ stitchable ]] half4 downsyncWaveShader(
    float2 position,
    SwiftUI::Layer layer,
    float2 viewSize,
    float progress,
    float intensity,
    float isDarkMode,
    float phaseMode
) {
    float env = clamp(intensity, 0.0f, 1.0f);
    if (env <= 0.001f || viewSize.x < 1.0f || viewSize.y < 1.0f) {
        return half4(0.0h);
    }

    float2 uv = position / viewSize;
    float aspect = viewSize.x / max(viewSize.y, 1.0f);

    float2 origin = float2(0.5f, -0.06f);
    float2 delta = uv - origin;
    float2 scaledDelta = float2(delta.x * aspect * 0.48f, delta.y);
    float radialDist = length(scaledDelta);

    float verticalFade = 1.0f - smoothstep(0.42f, 0.86f, uv.y);
    bool isExpanding = (phaseMode >= 0.5f);

    float crestRadius;
    float leadWidth;
    float trailWidth;
    if (!isExpanding) {
        crestRadius = mix(0.64f, 0.04f, progress);
        leadWidth = mix(0.26f, 0.14f, progress);
        trailWidth = mix(0.32f, 0.18f, progress);
    } else {
        crestRadius = mix(-0.02f, 0.72f, progress);
        leadWidth = mix(0.15f, 0.32f, progress);
        trailWidth = mix(0.26f, 0.48f, progress);
    }

    float signedDist = radialDist - crestRadius;
    float width = signedDist > 0.0f ? leadWidth : trailWidth;
    float normD = signedDist / max(width, 0.02f);
    float waveBell = exp(-normD * normD);

    // Zero-ghosting envelope: displacement settles back to 1.0 well before the wave fades out
    float warpEnv = smoothstep(0.28f, 0.92f, env);
    float stretchEnv = waveBell * warpEnv * verticalFade;
    float lensScale = isExpanding
        ? (1.0f - 0.075f * stretchEnv)
        : (1.0f + 0.065f * stretchEnv);

    float2 p = clamp((origin + delta * lensScale) * viewSize, float2(0.5f), viewSize - 0.5f);

    // Smooth 16-tap Vogel spiral progressive blur (decays cleanly before alpha disappears)
    float blurWidth = max(width * 1.55f, 0.18f);
    float blurBell = exp(-pow(signedDist / blurWidth, 2.0f));
    float topBlur = exp(-max(uv.y, 0.0f) * 3.0f) * (isExpanding ? exp(-progress * 2.8f) : smoothstep(0.12f, 0.88f, progress));
    float progBlurAmt = clamp(max(blurBell, topBlur * 0.78f) * warpEnv * verticalFade, 0.0f, 1.0f);
    float blurRadiusPx = progBlurAmt * (isExpanding ? 9.5f : 8.0f);

    half4 s0 = layer.sample(p);
    float3 refracted;
    if (blurRadiusPx < 0.5f) {
        refracted = float3(float(s0.r), float(s0.g), float(s0.b));
    } else {
        float3 acc = float3(0.0f);
        float wSum = 0.0f;
        const float goldenAngle = 2.39996323f;
        for (int i = 0; i < 16; i++) {
            float fi = float(i) + 0.5f;
            float rNorm = sqrt(fi / 16.0f);
            float theta = fi * goldenAngle;
            float2 off = float2(cos(theta), sin(theta)) * (rNorm * blurRadiusPx);
            float w = exp(-1.8f * rNorm * rNorm);
            half4 tap = layer.sample(clamp(p + off, float2(0.5f), viewSize - 0.5f));
            acc += float3(float(tap.r), float(tap.g), float(tap.b)) * w;
            wSum += w;
        }
        refracted = acc / max(wSum, 1e-4f);
    }

    // Full-spectrum rainbow sweep across the horizontal arc + radial crest
    float horizontalSpectrum = uv.x * 1.20f;
    float radialSpectrum = (signedDist / max(width * 1.7f, 0.12f)) * 0.28f;
    float timeDrift = isExpanding ? (progress * 0.38f) : (-progress * 0.48f);
    float3 rainbowColor = prismRainbow(horizontalSpectrum + radialSpectrum + timeDrift);

    float3 glowRGB;
    float blendAmt;
    float localAlpha;
    if (!isExpanding) {
        float topGather = exp(-max(uv.y, 0.0f) * 4.2f) * smoothstep(0.22f, 1.0f, progress) * env;
        float rainbowBand = waveBell * env * verticalFade;
        float gain = mix(0.32f, 0.46f, isDarkMode);
        glowRGB = rainbowColor * (rainbowBand * gain + topGather * 0.28f)
                + float3(1.0f, 0.99f, 0.98f) * (topGather * 0.12f);
        blendAmt = clamp(rainbowBand * 1.05f + topGather * 0.85f, 0.0f, 0.84f);
        localAlpha = clamp(max(max(blurBell * warpEnv, waveBell * env), topGather) * verticalFade, 0.0f, 1.0f);
    } else {
        float coreWidth = mix(0.09f, 0.22f, progress);
        float haloWidth = mix(0.20f, 0.40f, progress);
        float coreArc = exp(-pow(signedDist / coreWidth, 2.0f)) * env * verticalFade;
        float outerHalo = exp(-pow((signedDist - coreWidth * 0.82f) / (haloWidth * 0.65f), 2.0f)) * env * verticalFade;
        float innerHalo = exp(-pow((signedDist + coreWidth * 0.72f) / (haloWidth * 0.75f), 2.0f)) * env * verticalFade;
        float rainbowHalo = clamp(outerHalo * 0.98f + innerHalo * 0.82f, 0.0f, 1.0f);
        float topLaunch = exp(-progress * 4.0f) * exp(-max(uv.y, 0.0f) * 4.5f) * env;

        float coreGain = mix(0.18f, 0.28f, isDarkMode);
        float haloGain = mix(0.34f, 0.50f, isDarkMode);
        glowRGB = float3(1.0f, 0.99f, 0.98f) * (coreArc * coreGain + topLaunch * 0.16f)
                + rainbowColor * (rainbowHalo * haloGain + topLaunch * 0.32f);
        blendAmt = clamp(coreArc + rainbowHalo * 1.05f + topLaunch, 0.0f, 0.86f);
        localAlpha = clamp(max(max(blurBell * warpEnv, max(coreArc, rainbowHalo)), topLaunch) * verticalFade, 0.0f, 1.0f);
    }

    float3 screened = 1.0f - (1.0f - clamp(refracted, 0.0f, 1.0f)) * (1.0f - clamp(glowRGB, 0.0f, 0.72f));
    float3 outRGB = mix(refracted, screened, blendAmt);

    return half4(half3(clamp(outRGB, 0.0f, 1.0f) * localAlpha), half(localAlpha));
}
