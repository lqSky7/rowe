#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Smooth physical rainbow prism palette matching the reference screenshots:
/// warm coral/peach -> rose/magenta -> violet -> cyan/aqua -> soft mint/emerald.
static float3 prismRainbow(float x) {
    float t = clamp(x, 0.0f, 1.0f);
    float3 c0 = float3(1.00f, 0.62f, 0.42f);
    float3 c1 = float3(0.98f, 0.44f, 0.78f);
    float3 c2 = float3(0.58f, 0.56f, 1.00f);
    float3 c3 = float3(0.32f, 0.86f, 1.00f);
    float3 c4 = float3(0.48f, 0.96f, 0.76f);

    if (t < 0.25f) return mix(c0, c1, t / 0.25f);
    if (t < 0.50f) return mix(c1, c2, (t - 0.25f) / 0.25f);
    if (t < 0.75f) return mix(c2, c3, (t - 0.50f) / 0.25f);
    return mix(c3, c4, (t - 0.75f) / 0.25f);
}

/// 2-phase optical sync shader for iOS:
/// - Smooth liquid-lens magnification stretch (zero pixelation)
/// - 16-tap Vogel spiral progressive frosted blur covering a wide zone around the halo
/// - Phase 1 (phaseMode < 0.5): rainbow + upward lens stretch converging toward top-center
/// - Phase 2 (phaseMode >= 0.5): soft-white dome wave with rainbow prism halo expanding to midway
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
        return layer.sample(position);
    }

    float2 uv = position / viewSize;
    float aspect = viewSize.x / max(viewSize.y, 1.0f);

    float2 origin = float2(0.5f, -0.06f);
    float2 delta = uv - origin;
    float2 scaledDelta = float2(delta.x * aspect * 0.48f, delta.y);
    float radialDist = length(scaledDelta);

    float verticalFade = 1.0f - smoothstep(0.42f, 0.88f, uv.y);
    bool isExpanding = (phaseMode >= 0.5f);

    float crestRadius;
    float leadWidth;
    float trailWidth;
    if (!isExpanding) {
        crestRadius = mix(0.64f, 0.04f, progress);
        leadWidth = mix(0.28f, 0.14f, progress);
        trailWidth = mix(0.34f, 0.18f, progress);
    } else {
        crestRadius = mix(-0.02f, 0.74f, progress);
        leadWidth = mix(0.16f, 0.34f, progress);
        trailWidth = mix(0.28f, 0.54f, progress);
    }

    float signedDist = radialDist - crestRadius;
    float width = signedDist > 0.0f ? leadWidth : trailWidth;
    float normD = signedDist / max(width, 0.02f);
    float waveBell = exp(-normD * normD);

    // 1. True smooth liquid-lens magnification stretch (stretches background smoothly like glass, never blocky)
    float stretchEnv = waveBell * env * verticalFade;
    float lensScale = isExpanding
        ? (1.0f - 0.16f * stretchEnv)   // smooth outward radial stretch/magnification
        : (1.0f + 0.13f * stretchEnv);  // smooth inward pull toward top-center

    // Subtle chromatic RGB lens dispersion
    float2 uvR = origin + delta * mix(1.0f, lensScale, 1.14f);
    float2 uvG = origin + delta * lensScale;
    float2 uvB = origin + delta * mix(1.0f, lensScale, 0.86f);

    float2 pR = clamp(uvR * viewSize, float2(0.5f), viewSize - 0.5f);
    float2 pG = clamp(uvG * viewSize, float2(0.5f), viewSize - 0.5f);
    float2 pB = clamp(uvB * viewSize, float2(0.5f), viewSize - 0.5f);

    // 2. Smooth 16-tap golden-angle Vogel spiral progressive blur (silky frosted glass, zero ghosting)
    float blurWidth = max(width * 1.80f, 0.22f);
    float blurBell = exp(-pow(signedDist / blurWidth, 2.0f));
    float topBlur = exp(-max(uv.y, 0.0f) * 2.8f) * (isExpanding ? exp(-progress * 2.4f) : smoothstep(0.1f, 0.9f, progress));
    float progBlurAmt = clamp(max(blurBell, topBlur * 0.85f) * env * verticalFade, 0.0f, 1.0f);
    float blurRadiusPx = progBlurAmt * (isExpanding ? 12.5f : 10.5f);

    half4 sG0 = layer.sample(pG);
    float3 refracted;
    if (blurRadiusPx < 0.6f) {
        refracted = float3(float(layer.sample(pR).r), float(sG0.g), float(layer.sample(pB).b));
    } else {
        float rAcc = 0.0f;
        float gAcc = 0.0f;
        float bAcc = 0.0f;
        float wSum = 0.0f;
        const float goldenAngle = 2.39996323f;
        for (int i = 0; i < 16; i++) {
            float fi = float(i) + 0.5f;
            float rNorm = sqrt(fi / 16.0f);
            float theta = fi * goldenAngle;
            float2 off = float2(cos(theta), sin(theta)) * (rNorm * blurRadiusPx);
            float w = exp(-1.8f * rNorm * rNorm);
            rAcc += float(layer.sample(clamp(pR + off, float2(0.5f), viewSize - 0.5f)).r) * w;
            gAcc += float(layer.sample(clamp(pG + off, float2(0.5f), viewSize - 0.5f)).g) * w;
            bAcc += float(layer.sample(clamp(pB + off, float2(0.5f), viewSize - 0.5f)).b) * w;
            wSum += w;
        }
        refracted = float3(rAcc, gAcc, bAcc) / max(wSum, 1e-4f);
    }

    // 3. Rainbow prism halo + soft luminous white core (non-blinding)
    float radialHue = clamp((signedDist / max(width * 1.35f, 0.08f)) * 0.5f + 0.5f, 0.0f, 1.0f);
    float lateralShift = 0.14f * sin(uv.x * 4.2f + progress * 2.4f);
    float3 rainbowColor = prismRainbow(fract(radialHue + lateralShift));

    float3 glowRGB;
    float blendAmt;
    if (!isExpanding) {
        float topGather = exp(-max(uv.y, 0.0f) * 4.0f) * smoothstep(0.20f, 1.0f, progress) * env;
        float rainbowBand = waveBell * env * verticalFade;
        float gain = mix(0.24f, 0.36f, isDarkMode);
        glowRGB = rainbowColor * (rainbowBand * gain + topGather * 0.22f)
                + float3(1.0f, 0.98f, 0.96f) * (topGather * 0.16f);
        blendAmt = clamp(rainbowBand * 1.05f + topGather * 0.85f, 0.0f, 0.80f);
    } else {
        float coreWidth = mix(0.095f, 0.23f, progress);
        float haloWidth = mix(0.22f, 0.44f, progress);
        float coreArc = exp(-pow(signedDist / coreWidth, 2.0f)) * env * verticalFade;
        float outerHalo = exp(-pow((signedDist - coreWidth * 0.85f) / (haloWidth * 0.65f), 2.0f)) * env * verticalFade;
        float innerHalo = exp(-pow((signedDist + coreWidth * 0.75f) / (haloWidth * 0.75f), 2.0f)) * env * verticalFade;
        float rainbowHalo = clamp(outerHalo * 0.95f + innerHalo * 0.75f, 0.0f, 1.0f);
        float topLaunch = exp(-progress * 3.8f) * exp(-max(uv.y, 0.0f) * 4.5f) * env;

        float coreGain = mix(0.22f, 0.32f, isDarkMode);
        float haloGain = mix(0.26f, 0.40f, isDarkMode);
        glowRGB = float3(1.0f, 0.99f, 0.98f) * (coreArc * coreGain + topLaunch * 0.20f)
                + rainbowColor * (rainbowHalo * haloGain + topLaunch * 0.24f);
        blendAmt = clamp(coreArc + rainbowHalo * 1.05f + topLaunch, 0.0f, 0.86f);
    }

    float3 screened = 1.0f - (1.0f - clamp(refracted, 0.0f, 1.0f)) * (1.0f - clamp(glowRGB, 0.0f, 0.65f));
    float3 outRGB = mix(refracted, screened, blendAmt);

    return half4(half3(clamp(outRGB, 0.0f, 1.0f)), sG0.a);
}
