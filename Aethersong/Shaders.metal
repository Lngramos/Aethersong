#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float3 worldPosition;
    float3 localPosition;
};

struct TerrainUniforms {
    float4x4 modelViewMatrix;
    float4x4 projectionMatrix;
};

struct TerrainParams {
    uint drawLines;
    float lineWidth;
    float4 lineColor;
};

struct HighlightInfo {
    uint isHighlighted;
    int tileX;
    int tileY;
    float4 highlightColor;
};

vertex VertexOut terrainVertexShader(
    VertexIn in [[stage_in]],
    constant TerrainUniforms &uniforms [[buffer(2)]]
) {
    VertexOut out;
    
    // Transform position
    float4 worldPos = float4(in.position, 1.0);
    float4 viewPos = uniforms.modelViewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    
    // Pass through texture coordinates
    out.texCoord = in.texCoord;
    
    // Store world position for fragment shader
    out.worldPosition = worldPos.xyz;
    
    // Store local position (within the chunk) for highlighting
    out.localPosition = in.position;
    
    return out;
}

fragment float4 terrainFragmentShader(
    VertexOut in [[stage_in]],
    constant TerrainParams &params [[buffer(0)]],
    constant HighlightInfo &highlight [[buffer(1)]]
) {
    // Base terrain color - green
    float4 baseColor = float4(0.2, 0.7, 0.3, 1.0);
    
    // Check if this fragment is part of the highlighted tile
    if (highlight.isHighlighted == 1) {
        // Get the integer tile coordinates
        int tileX = int(floor(in.localPosition.x));
        int tileY = int(floor(in.localPosition.z));
        
        if (tileX == highlight.tileX && tileY == highlight.tileY) {
            // This is the highlighted tile - blend with highlight color
            return mix(baseColor, highlight.highlightColor, 0.7);
        }
    }
    
    // Draw grid lines if enabled
    if (params.drawLines == 1) {
        float gridX = fract(in.localPosition.x);
        float gridZ = fract(in.localPosition.z);
        
        if (gridX < params.lineWidth || gridX > (1.0 - params.lineWidth) ||
            gridZ < params.lineWidth || gridZ > (1.0 - params.lineWidth)) {
            return params.lineColor;
        }
    }
    
    // Height-based coloring
    float height = in.localPosition.y;
    if (height > 3.0) {
        // Mountain peaks - white
        return mix(baseColor, float4(1.0, 1.0, 1.0, 1.0), (height - 3.0) / 2.0);
    } else if (height > 1.0) {
        // Hills - darker green
        return mix(float4(0.1, 0.5, 0.2, 1.0), baseColor, (height - 1.0) / 2.0);
    } else if (height < 0.2) {
        // Water - blue
        return float4(0.0, 0.3, 0.8, 1.0);
    }
    
    return baseColor;
}

fragment float4 terrainLinesFragmentShader(
    VertexOut in [[stage_in]],
    constant TerrainParams &params [[buffer(0)]]
) {
    // Only draw grid lines
    float gridX = fract(in.localPosition.x);
    float gridZ = fract(in.localPosition.z);
    
    if (gridX < params.lineWidth || gridX > (1.0 - params.lineWidth) ||
        gridZ < params.lineWidth || gridZ > (1.0 - params.lineWidth)) {
        return params.lineColor;
    }
    
    // Transparent for non-line areas
    return float4(0, 0, 0, 0);
}

kernel void thickenLines(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &thickness [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Get dimensions of the texture
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();
    
    // Check if this pixel is within bounds
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Read the center pixel
    float4 centerColor = inTexture.read(gid);
    
    // If the center pixel already has a line, just copy it
    if (centerColor.a > 0.01) {
        outTexture.write(centerColor, gid);
        return;
    }
    
    // Check neighboring pixels within the thickness radius
    int radius = int(thickness);
    float4 finalColor = float4(0, 0, 0, 0);
    
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            // Skip if out of bounds
            int nx = int(gid.x) + dx;
            int ny = int(gid.y) + dy;
            if (nx < 0 || nx >= int(width) || ny < 0 || ny >= int(height)) {
                continue;
            }
            
            // Read neighbor color
            float4 neighborColor = inTexture.read(uint2(nx, ny));
            
            // If neighbor has a line, blend based on distance
            if (neighborColor.a > 0.01) {
                float dist = length(float2(dx, dy));
                if (dist <= thickness) {
                    float factor = 1.0 - (dist / thickness);
                    finalColor = max(finalColor, neighborColor * factor);
                }
            }
        }
    }
    
    outTexture.write(finalColor, gid);
}

vertex float4 quadVertexShader(
    uint vertexID [[vertex_id]],
    constant float4 *vertices [[buffer(0)]]
) {
    // Each vertex has position (xy) and texcoord (zw)
    float4 vertexData = vertices[vertexID];
    float2 position = vertexData.xy;
    // We don't need texCoord here
    
    // Pass through position and store texcoord in z,w
    return float4(position, 0, 1);
}

fragment float4 compositeFragmentShader(
    float4 in [[position]],
    texture2d<float> lineTexture [[texture(0)]]
) {
    // Convert from clip space to texture space
    float2 texCoord = float2(
        (in.x / in.w + 1.0) * 0.5,
        (1.0 - (in.y / in.w + 1.0) * 0.5)
    );
    
    // Sample the line texture
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear);
    float4 lineColor = lineTexture.sample(texSampler, texCoord);
    
    // Return the line color (with alpha for blending)
    return lineColor;
}

// Axis indicator shader functions
struct AxisVertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct AxisVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex AxisVertexOut axisVertexShader(uint vertexID [[vertex_id]],
                                     constant float *vertices [[buffer(0)]],
                                     constant AxisUniforms &uniforms [[buffer(1)]]) {
    AxisVertexOut out;
    
    // Extract position and color from interleaved vertex data
    float3 position = float3(vertices[vertexID * 7], 
                            vertices[vertexID * 7 + 1], 
                            vertices[vertexID * 7 + 2]);
    float4 color = float4(vertices[vertexID * 7 + 3],
                         vertices[vertexID * 7 + 4],
                         vertices[vertexID * 7 + 5],
                         vertices[vertexID * 7 + 6]);
    
    // Transform position
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * float4(position, 1.0);
    out.color = color;
    
    return out;
}

fragment float4 axisFragmentShader(AxisVertexOut in [[stage_in]]) {
    // Make the lines thicker by increasing the color intensity
    return float4(in.color.rgb * 1.5, in.color.a);
}
