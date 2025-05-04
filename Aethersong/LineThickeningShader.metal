#include <metal_stdlib>
using namespace metal;

// Kernel for thickening lines using a dilation approach
kernel void lineThickeningKernel(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float &lineThickness [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    // Get dimensions of the texture
    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();
    
    // Check if we're within bounds
    if (gid.x >= width || gid.y >= height) {
        return;
    }
    
    // Calculate the radius for our sampling kernel based on desired thickness
    int radius = int(lineThickness);
    
    // Start with the current pixel
    float4 originalColor = inputTexture.read(gid);
    float4 resultColor = originalColor;
    
    // Only process if this isn't already a line pixel (assuming lines are black)
    if (originalColor.a < 0.1) {
        // Check surrounding pixels in a square pattern
        for (int dy = -radius; dy <= radius; dy++) {
            for (int dx = -radius; dx <= radius; dx++) {
                // Skip if outside the radius
                if (dx*dx + dy*dy > radius*radius) continue;
                
                // Calculate sample position with bounds checking
                int2 samplePos = int2(gid) + int2(dx, dy);
                if (samplePos.x < 0 || samplePos.x >= int(width) || 
                    samplePos.y < 0 || samplePos.y >= int(height)) {
                    continue;
                }
                
                // Read the sample
                float4 sampleColor = inputTexture.read(uint2(samplePos));
                
                // If we found a line pixel nearby (black with alpha)
                if (sampleColor.a > 0.1 && 
                    sampleColor.r < 0.1 && 
                    sampleColor.g < 0.1 && 
                    sampleColor.b < 0.1) {
                    
                    // Calculate distance-based alpha with sharper falloff
                    float dist = length(float2(dx, dy)) / float(radius);
                    float alpha = 0.5 * pow(1.0 - dist, 3.0); // Sharper falloff for crisper lines
                    
                    // Only update if this gives us a more opaque result
                    if (alpha > resultColor.a) {
                        resultColor = float4(0.0, 0.0, 0.0, alpha);
                    }
                }
            }
        }
    }
    
    // Write the result
    outputTexture.write(resultColor, gid);
}
