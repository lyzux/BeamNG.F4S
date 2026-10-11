// Feel4Speed: original center-protected radial speed blur and vignette.
// BeamNG shared PostFX helpers provide the vertex layout and viewport transform.
#include "shaders/common/bng.hlsl"
#include "shaders/common/lighting.h.hlsl"
#include "shaders/common/postFx/postFx.h.hlsl"

uniform_sampler2D(f4sBackBuffer, 0);

cbuffer perDraw
{
    // x=vignette [0..1], y=centerward blur ray fraction, zw=protected center.
    uniform float4 f4sParams;
    uniform float2 oneOverTargetSize;
    PURE_POSTFX_UNIFORMS
    BNG_LIGHTING_UNIFORMS
};

#include "shaders/common/lighting.hlsl"
#include "shaders/common/postFx/postFx.hlsl"

#ifdef SHADER_STAGE_VS
PFXVertToPix main(PFXVert IN)
{
    return processPostFxVert(IN);
}
#else
float4 main(PFXVertToPix IN) : SV_Target
{
    // rtParams0.xy is the texture viewport offset; zw is its scale.
    // Work in local viewport coordinates, then convert back for sampling.
    float2 scaleMagnitude = max(abs(rtParams0.zw), float2(0.00001, 0.00001));
    float2 viewportScale = lerp(-scaleMagnitude, scaleMagnitude, step(0.0, rtParams0.zw));
    float2 viewportOffset = rtParams0.xy;
    float2 localUV = (IN.uv0 - viewportOffset) / viewportScale;
    float2 center = clamp(f4sParams.zw, float2(0.05, 0.05), float2(0.95, 0.95));
    float2 radial = localUV - center;
    float radius = length(radial * 2.0);
    float edgeMask = smoothstep(0.38, 1.05, radius);
    float vignetteMask = smoothstep(0.45, 1.25, radius);
    float vignette = saturate(f4sParams.x);
    float blur = saturate(f4sParams.y);

    float2 halfTexel = max(oneOverTargetSize * 0.5, float2(0.000001, 0.000001));
    float2 uvMin = min(viewportOffset, viewportOffset + viewportScale) + min(halfTexel, scaleMagnitude * 0.25);
    float2 uvMax = max(viewportOffset, viewportOffset + viewportScale) - min(halfTexel, scaleMagnitude * 0.25);
    float2 sourceUV = clamp(IN.uv0, uvMin, uvMax);
    float4 original = tex2D(f4sBackBuffer, sourceUV);
    float3 color = original.rgb;

    // Uniform strength test also skips all eight extra samples for vignette-only.
    // Center masking prevents blur across the car and the central road view.
    [branch]
    if (blur > 0.0001 && edgeMask > 0.0001)
    {
        float2 ray = radial * viewportScale * (blur * edgeMask);
        float3 sum = original.rgb * 2.0;
        [unroll]
        for (int sampleIndex = 1; sampleIndex <= 8; ++sampleIndex)
        {
            float2 uv = clamp(sourceUV - ray * (sampleIndex / 8.0), uvMin, uvMax);
            sum += tex2D(f4sBackBuffer, uv).rgb;
        }
        color = lerp(original.rgb, sum * 0.1, edgeMask);
    }

    // Preserve alpha and HDR range; avoid saturating scene RGB.
    color *= 1.0 - (0.80 * vignette * vignetteMask);
    return float4(color, original.a);
}
#endif
