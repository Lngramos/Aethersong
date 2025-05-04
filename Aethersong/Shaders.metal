#include <metal_stdlib>
using namespace metal;

//
// Shared Uniforms
//
struct Uniforms {
    float4x4 modelViewMatrix;
    float4x4 projectionMatrix;
};

//
// Terrain pipeline
//
struct TerrainVertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
};

struct TerrainVertexOut {
    float4 position [[position]];
    float2 texcoord;
};

vertex TerrainVertexOut terrainVertexShader(TerrainVertexIn in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(2)]]) {
    TerrainVertexOut out;
    float4 worldPosition = float4(in.position, 1.0);
    float4 viewPos = uniforms.modelViewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPos;
    out.texcoord = in.texcoord;
    return out;
}

fragment float4 terrainFragmentShader(TerrainVertexOut in [[stage_in]],
                               constant float4& colorOverride [[buffer(3)]]) {
    return colorOverride;
}

//
// Entity pipeline
//
struct EntityVertexIn {
    float3 position [[attribute(0)]];
    float2 texcoord [[attribute(1)]];
};

struct EntityVertexOut {
    float4 position [[position]];
    float2 texcoord;
};

vertex EntityVertexOut entityVertexShader(EntityVertexIn in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(2)]])
{
    EntityVertexOut out;
    float4 worldPosition = float4(in.position, 1.0);
    float4 viewPos = uniforms.modelViewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPos;
    out.texcoord = float2(0.0, 0.0);
    return out;
}

fragment float4 entityFragmentShader(EntityVertexOut in [[stage_in]],
                                     constant float4& color [[buffer(3)]]) {
    return color;
}
