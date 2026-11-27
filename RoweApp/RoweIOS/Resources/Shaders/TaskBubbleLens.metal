#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Rounded-rectangle signed distance field (negative inside, positive outside).
static float sdRoundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + float2(radius);
    return min(max(q.x, q.y), 0.0f) + length(max(q, float2(0.0f))) - radius;
}

/// Optical Liquid Glass Bubble shader for Rowe's iOS Task Composer -> Calendar flight:
/// - Smoothly morphs from a 24pt rounded-rect card into an organic jelly-wobbling
///   liquid glass bubble (combining lnreader-ios's wavelength-separated optical lens
///   with Apple Genmoji's organic bubble silhouette and specular rim).
/// - Always outputs transparent (half4(0.0h)) outside the bubble mask so it composites
///   cleanly over the live UIKit/SwiftUI calendar without ever touching UIKit layers.
/// - `letteringOnly = 0`: refracts the captured Calendar backdrop snapshot inside the bubble.
/// - `letteringOnly = 1`: refracts only the task title inside the bubble with preserved
///   premultiplied alpha so the text visibly bends inside the glass lens during flight.
[[ stitchable ]] half4 taskBubbleLens(
    float2 position,
    SwiftUI::Layer layer,
    float2 center,
    float2 halfSize,
    float cornerRadius,
    float power,
    float dispersion,
    float wobblePhase,
    float wobbleAmp,
    float opacity,
    float letteringOnly
) {
    if (opacity <= 0.001f) {
        return half4(0.0h);
    }

    float2 safeHalf = max(halfSize, float2(1.0f));
    float2 delta = position - center;
    float2 n = delta / safeHalf;
    float rRaw = length(n);
    float angle = atan2(n.y, n.x);

    // Organic harmonic jelly wobble (peaks when condensed into the flying bubble)
    float wobble = wobbleAmp * (
        0.048f * sin(2.0f * angle + wobblePhase) +
        0.030f * cos(3.0f * angle - wobblePhase * 1.35f) +
        0.016f * sin(4.0f * angle + wobblePhase * 0.75f)
    );
    float2 wobbledHalf = safeHalf * (1.0f + wobble);
    float effRadius = min(cornerRadius, min(wobbledHalf.x, wobbledHalf.y));

    // Signed distance to the morphing rounded-rect / organic bubble
    float sdf = sdRoundedBox(delta, wobbledHalf, effRadius);
    float minDim = max(min(wobbledHalf.x, wobbledHalf.y), 1.0f);
    float feather = 1.25f;
    float mask = 1.0f - smoothstep(-feather, feather, sdf);
    if (mask <= 0.001f) {
        return half4(0.0h);
    }

    // Normalized radial interior coordinate (0 at center, 1 at rim)
    float edgeProx = clamp(1.0f + sdf / minDim, 0.0f, 1.0f);
    float r = clamp(mix(rRaw, edgeProx, 0.55f), 0.0f, 1.0f);

    float2 direction = rRaw > 0.0001f ? n / rRaw : float2(0.0f);
    float2 tangent = float2(-direction.y, direction.x);

    // Spherical barrel refraction (adapted from lnreader-ios's LiquidGlassShader)
    float zoom = mix(1.0f, 0.48f + pow(r, 3.0f) * 0.80f, power);
    float split = pow(r, 2.4f) * min(minDim * 0.34f, 24.0f) * dispersion;

    float2 base = delta * (zoom - 1.0f);
    float2 redOffset   = clamp(base - direction * split * 1.18f + tangent * split * 0.24f, -140.0f, 140.0f);
    float2 greenOffset = clamp(base, -140.0f, 140.0f);
    float2 blueOffset  = clamp(base + direction * split * 1.26f - tangent * split * 0.24f, -140.0f, 140.0f);

    half4 red   = layer.sample(position + redOffset);
    half4 green = layer.sample(position + greenOffset);
    half4 blue  = layer.sample(position + blueOffset);

    half3 color = half3(red.r, green.g, blue.b);

    if (letteringOnly > 0.5f) {
        // Preserve premultiplied alpha for the refracted task lettering
        half alpha = max(red.a, max(green.a, blue.a));
        return half4(color, alpha) * half(mask * opacity);
    }

    // Optical glass body frost, top-left specular crescent, bottom bounce & Fresnel rim
    float z = sqrt(max(1.0f - min(r * r, 1.0f), 0.0f));
    float frost = mix(0.14f, 0.03f, power) * (0.42f + 0.58f * (1.0f - z));
    color = mix(color, half3(0.14h), half(frost * power));

    float topLight = pow(max(dot(n, normalize(float2(-0.32f, -0.88f))), 0.0f), 3.4f);
    float bottomBounce = pow(max(dot(n, normalize(float2(0.25f, 0.92f))), 0.0f), 3.8f);
    float specular = topLight * smoothstep(0.58f, 0.98f, r) * 0.44f * power;
    float bounce = bottomBounce * smoothstep(0.72f, 0.985f, r) * 0.16f * power;

    float rim = smoothstep(-2.4f, -0.35f, sdf) * (1.0f - smoothstep(-0.15f, 1.1f, sdf));
    float innerShade = smoothstep(0.76f, 0.96f, r) * (1.0f - rim) * 0.045f * power;

    // Subtle prismatic rim glint from directional dispersion
    half3 rimTint = half3(
        1.0h + half(0.22f * dispersion * sin(angle * 2.0f + wobblePhase)),
        1.0h,
        1.0h + half(0.22f * dispersion * cos(angle * 2.0f - wobblePhase))
    );

    color += half3(specular + bounce - innerShade) + rimTint * half(rim * 0.38f * (0.32f + 0.68f * power));
    half outAlpha = half(mask * opacity);
    return half4(clamp(color, half3(0.0h), half3(1.0h)) * outAlpha, outAlpha);
}
