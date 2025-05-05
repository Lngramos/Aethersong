#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct EntityUniforms {
    float4x4 modelViewMatrix;
    float4x4 projectionMatrix;
};

vertex VertexOut entityVertexShader(
    VertexIn in [[stage_in]],
    constant EntityUniforms &uniforms [[buffer(2)]]
) {
    VertexOut out;
    
    // Transform position
    float4 worldPos = float4(in.position, 1.0);
    float4 viewPos = uniforms.modelViewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    
    // Pass through texture coordinates
    out.texCoord = in.texCoord;
    
    return out;
}

fragment float4 entityFragmentShader(
    VertexOut in [[stage_in]],
    constant float4 &color [[buffer(3)]]
) {
    // Just use the provided color
    return color;
}
