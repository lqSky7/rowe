#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Smooth physical rainbow prism palette matching the reference screenshots:
/// warm coral/peach -> rose/magenta -> violet -> cyan/aqua -> soft mint/emerald.
static float3 prismRainbow(float x) {
    float t = clamp(x, 0.0f, 1.0f);
    float3 c0 = float3(1.00f, 0.62f, 0.42f); // warm peach / amber
    float3 c1 = float3(0.98f, 0.44f, 0.78f); // rose / magenta
    float3 c2 = float3(0.58f, 0.56f, 1.00f); // violet / indigo
    float3 c3 = float3(0.32f, 0.86f, 1.00f); // electric cyan
    float3 c4 = float3(0.48f, 0.96f, 0.76f); // soft emerald / mint

    if (t < 0.25f) return mix(c0, c1, t / 0.25f);
    if (t < 0.50f) return mix(c1, c2, (t - 0.25f) / 0.25f);
    if (t < 0.75f) return mix(c2, c3, (t - 0.50f) / 0.25f);
    return mix(c3, c4, (t - 0.75f) / 0.25f);
}

/// 2-phase optical sync shader for iOS:
/// - `phaseMode < 0.5` (Phase 1 — Syncing / Reaching Backend):
///   Rainbow arc & upward background distortion smoothly converge toward the top-center edge.
/// - `phaseMode >= 0.5` (Phase 2 — New Data Downsynced):
///   Luminous soft-white wave wrapped in a distinct rainbow halo expands organically from top
///   toward midway, stretching the background and fading out gracefully midway down.
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

    float2 origin = float2(0.5f, -0.07f);
    float2 delta = uv - origin;
    float2 scaledDelta = float2(delta.x * aspect * 0.48f, delta.y);
    float radialDist = length(scaledDelta);
    float2 dir = radialDist > 1e-4f ? (delta / max(length(delta), 1e-4f)) : float2(0.0f, 1.0f);

    // Spatial vertical fade so neither phase hits the bottom half harshly
    float verticalFade = 1.0f - smoothstep(0.40f, 0.86f, uv.y);

    bool isExpanding = (phaseMode >= 0.5f);

    float crestRadius;
    float leadWidth;
    float trailWidth;
    if (!isExpanding) {
        // Phase 1: Converging inward from midway (0.66) toward the top edge (0.04)
        crestRadius = mix(0.66f, 0.04f, progress);
        leadWidth = mix(0.28f, 0.14f, progress);
        trailWidth = mix(0.34f, 0.18f, progress);
    } else {
        // Phase 2: Expanding organically from top (-0.02) to midway (0.76) while widening
        crestRadius = mix(-0.02f, 0.76f, progress);
        leadWidth = mix(0.15f, 0.34f, progress);
        trailWidth = mix(0.26f, 0.54f, progress);
    }

    float signedDist = radialDist - crestRadius;
    float width = signedDist > 0.0f ? leadWidth : trailWidth;
    float normD = signedDist / max(width, 0.02f);
    float waveBell = exp(-normD * normD);
    float waveEnergy = waveBell * env * verticalFade;

    // 1. Directional background distortion / stretch (richer optical stretch matching reference)
    // Phase 1 pulls pixels UPWARD toward top; Phase 2 stretches them OUTWARD through the crest
    float pullSign = isExpanding ? -1.0f : 1.0f;
    float stretchStrength = isExpanding ? 1.0f : 0.85f;
    float stretchWave = (0.64f * waveBell + 0.36f * (-normD * exp(-0.78f * normD * normD))) * env * verticalFade * stretchStrength;
    float2 maxStretchPx = float2(viewSize.x * 0.054f, viewSize.y * 0.128f);
    float2 baseDisp = (pullSign * dir) * stretchWave * maxStretchPx;

    // 2. Chromatic RGB prism dispersion + soft 3-tap directional glass blur
    float blurPx = waveEnergy * (isExpanding ? 13.0f : 10.0f);
    float2 blurStep = dir * blurPx;

    float2 pR = clamp(position + baseDisp * 1.28f, float2(0.5f), viewSize - 0.5f);
    float2 pG = clamp(position + baseDisp * 1.00f, float2(0.5f), viewSize - 0.5f);
    float2 pB = clamp(position + baseDisp * 0.72f, float2(0.5f), viewSize - 0.5f);

    half4 sR0 = layer.sample(pR);
    half4 sR1 = layer.sample(clamp(pR - blurStep, float2(0.5f), viewSize - 0.5f));
    half4 sR2 = layer.sample(clamp(pR + blurStep * 0.50f, float2(0.5f), viewSize - 0.5f));
    half r = sR0.r * 0.52h + sR1.r * 0.30h + sR2.r * 0.18h;

    half4 sG0 = layer.sample(pG);
    half4 sG1 = layer.sample(clamp(pG - blurStep, float2(0.5f), viewSize - 0.5f));
    half4 sG2 = layer.sample(clamp(pG + blurStep * 0.50f, float2(0.5f), viewSize - 0.5f));
    half g = sG0.g * 0.52h + sG1.g * 0.30h + sG2.g * 0.18h;

    half4 sB0 = layer.sample(pB);
    half4 sB1 = layer.sample(clamp(pB - blurStep, float2(0.5f), viewSize - 0.5f));
    half4 sB2 = layer.sample(clamp(pB + blurStep * 0.50f, float2(0.5f), viewSize - 0.5f));
    half b = sB0.b * 0.52h + sB1.b * 0.30h + sB2.b * 0.18h;

    float3 refracted = float3(float(r), float(g), float(b));

    // 3. Rainbow prism halo + soft luminous white core (calibrated so it never flashbangs)
    // Radial spectral progression across the rim (warm coral/pink inside -> violet -> cyan/mint outside)
    float radialHue = clamp((signedDist / max(width * 1.35f, 0.08f)) * 0.5f + 0.5f, 0.0f, 1.0f);
    // Subtle lateral iridescent shimmer along X so the rainbow feels alive like the screenshots
    float lateralShift = 0.14f * sin(uv.x * 4.2f + progress * 2.4f);
    float3 rainbowColor = prismRainbow(fract(radialHue + lateralShift));

    float3 glowRGB;
    float blendAmt;
    if (!isExpanding) {
        // Phase 1: Lush converging rainbow aura gathering softly at the top edge
        float topGather = exp(-max(uv.y, 0.0f) * 4.2f) * smoothstep(0.25f, 1.0f, progress) * env;
        float rainbowBand = waveBell * env * verticalFade;
        float gain = mix(0.26f, 0.38f, isDarkMode);
        glowRGB = rainbowColor * (rainbowBand * gain + topGather * 0.24f)
                + float3(1.0f, 0.98f, 0.96f) * (topGather * 0.18f);
        blendAmt = clamp(rainbowBand * 1.05f + topGather * 0.85f, 0.0f, 0.82f);
    } else {
        // Phase 2: Luminous pearl-white wave wrapped in a distinct rainbow halo (Screenshots 6 & 7)
        float coreWidth = mix(0.095f, 0.23f, progress);
        float haloWidth = mix(0.22f, 0.44f, progress);
        float coreArc = exp(-pow(signedDist / coreWidth, 2.0f)) * env * verticalFade;
        // Distinct rainbow halo peaking slightly outside & inside the white core edge
        float outerHalo = exp(-pow((signedDist - coreWidth * 0.85f) / (haloWidth * 0.65f), 2.0f)) * env * verticalFade;
        float innerHalo = exp(-pow((signedDist + coreWidth * 0.75f) / (haloWidth * 0.75f), 2.0f)) * env * verticalFade;
        float rainbowHalo = clamp(outerHalo * 0.95f + innerHalo * 0.75f, 0.0f, 1.0f);
        float topLaunch = exp(-progress * 3.8f) * exp(-max(uv.y, 0.0f) * 4.5f) * env;

        float coreGain = mix(0.24f, 0.34f, isDarkMode);
        float haloGain = mix(0.28f, 0.42f, isDarkMode);
        glowRGB = float3(1.0f, 0.99f, 0.98f) * (coreArc * coreGain + topLaunch * 0.22f)
                + rainbowColor * (rainbowHalo * haloGain + topLaunch * 0.26f);
        blendAmt = clamp(coreArc + rainbowHalo * 1.05f + topLaunch, 0.0f, 0.88f);
    }

    float3 screened = 1.0f - (1.0f - clamp(refracted, 0.0f, 1.0f)) * (1.0f - clamp(glowRGB, 0.0f, 0.68f));
    float3 outRGB = mix(refracted, screened, blendAmt);

    return half4(half3(clamp(outRGB, 0.0f, 1.0f)), sG0.a);
}
