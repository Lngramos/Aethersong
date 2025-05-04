#include <metal_stdlib>
using namespace metal;

// Vertex shader for rendering a full-screen quad
struct CompositeVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex CompositeVertexOut compositeVertexShader(uint vertexID [[vertex_id]],
                                               constant float4 *vertices [[buffer(0)]]) {
    CompositeVertexOut out;
    float4 position = vertices[vertexID];
    out.position = float4(position.xy, 0.0, 1.0);
    // Flip Y coordinate to correct the upside-down rendering
    out.texCoord = float2(position.z, 1.0 - position.w);
    return out;
}

// Fragment shader for compositing the thickened lines
fragment float4 compositeFragmentShader(CompositeVertexOut in [[stage_in]],
                                       texture2d<float> lineTexture [[texture(0)]]) {
    // Use nearest filtering for sharper lines
    constexpr sampler textureSampler(mag_filter::nearest, min_filter::nearest);
    float4 lineColor = lineTexture.sample(textureSampler, in.texCoord);
    
    // Only output pixels that have some opacity
    if (lineColor.a < 0.01) {
        discard_fragment();
    }
    
    return lineColor;
}
