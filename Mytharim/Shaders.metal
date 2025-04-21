// ----------------------------------------
// File: Shaders.metal
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
};

struct Uniforms {
    float4x4 modelViewMatrix;
    float4x4 projectionMatrix;
};

struct VertexOut {
    float4 position [[position]];
    float2 texcoord;
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(2)]]) {
    VertexOut out;
    float4 worldPosition = float4(in.position, 1.0);
    float4 viewPos = uniforms.modelViewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPos;
    out.texcoord = in.texcoord;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               constant float4& colorOverride [[buffer(3)]]) {
    return colorOverride;
}
