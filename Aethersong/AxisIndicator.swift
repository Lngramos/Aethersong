import MetalKit
import simd

@MainActor
class AxisIndicator {
    private var vertexBuffer: MTLBuffer
    private var pipelineState: MTLRenderPipelineState
    private let device: MTLDevice
    private var depthStencilState: MTLDepthStencilState
    
    init(device: MTLDevice) {
        self.device = device
        
        // Create vertices for the three axes with thicker lines
        // X axis (red)
        // Y axis (green)
        // Z axis (blue)
        let vertices: [Float] = [
            // Position (xyz)     // Color (rgba)
            // X axis (red)
            0.0, 0.0, 0.0,        1.0, 0.0, 0.0, 1.0,  // X axis start
            1.0, 0.0, 0.0,        1.0, 0.0, 0.0, 1.0,  // X axis end
            
            // Y axis (green)
            0.0, 0.0, 0.0,        0.0, 1.0, 0.0, 1.0,  // Y axis start
            0.0, 1.0, 0.0,        0.0, 1.0, 0.0, 1.0,  // Y axis end
            
            // Z axis (blue)
            0.0, 0.0, 0.0,        0.0, 0.0, 1.0, 1.0,  // Z axis start
            0.0, 0.0, 1.0,        0.0, 0.0, 1.0, 1.0   // Z axis end
        ]
        
        // Create vertex buffer
        guard let buffer = device.makeBuffer(bytes: vertices, 
                                            length: vertices.count * MemoryLayout<Float>.stride, 
                                            options: []) else {
            fatalError("Failed to create vertex buffer for axis indicator")
        }
        self.vertexBuffer = buffer
        
        // Create pipeline state
        let library = device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "axisVertexShader")
        let fragmentFunction = library.makeFunction(name: "axisFragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        // Disable culling to ensure axes are visible from all angles
        let rasterizerDescriptor = MTLRasterizationRateMapDescriptor()
        pipelineDescriptor.rasterSampleCount = 1
        pipelineDescriptor.isRasterizationEnabled = true
        
        // Create a depth stencil state that always passes depth test for UI elements
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .always
        depthStencilDescriptor.isDepthWriteEnabled = false
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state for axis indicator: \(error)")
        }
    }
    
    func draw(encoder: MTLRenderCommandEncoder, viewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4) {
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        // Create a fixed orthographic projection for UI rendering
        let orthoProjection = matrix_float4x4.makeOrthographic(
            left: -1, right: 1, 
            bottom: -1, top: 1, 
            near: -1, far: 1
        )
        
        // Create model matrix to position the axes in the top-right corner as UI element
        var modelMatrix = matrix_identity_float4x4
        
        // Scale down the axes to appropriate size for UI (smaller than before)
        let scale = SIMD3<Float>(0.15, 0.15, 0.15)
        modelMatrix.columns.0.x = scale.x
        modelMatrix.columns.1.y = scale.y
        modelMatrix.columns.2.z = scale.z
        
        // Position in top-right corner of the screen
        modelMatrix.columns.3 = SIMD4<Float>(0.85, 0.85, 0.0, 1.0)
        
        // Create a rotation matrix that matches the camera orientation
        // Extract just the rotation component from the view matrix
        var rotationMatrix = matrix_identity_float4x4
        rotationMatrix.columns.0 = SIMD4<Float>(viewMatrix.columns.0.x, viewMatrix.columns.0.y, viewMatrix.columns.0.z, 0.0)
        rotationMatrix.columns.1 = SIMD4<Float>(viewMatrix.columns.1.x, viewMatrix.columns.1.y, viewMatrix.columns.1.z, 0.0)
        rotationMatrix.columns.2 = SIMD4<Float>(viewMatrix.columns.2.x, viewMatrix.columns.2.y, viewMatrix.columns.2.z, 0.0)
        
        // Combine the matrices: first rotate, then scale, then position
        let finalModelMatrix = matrix_multiply(modelMatrix, rotationMatrix)
        
        // Use orthographic projection for UI-style rendering
        var uniforms = AxisUniforms(
            modelViewMatrix: finalModelMatrix,
            projectionMatrix: orthoProjection
        )
        
        // Use a depth stencil state that always passes depth test for UI elements
        encoder.setDepthStencilState(depthStencilState)
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<AxisUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 6)
        
        // Re-enable depth testing for subsequent rendering
        // This would need to be set back to the original depth state if needed
    }
}

struct AxisUniforms {
    var modelViewMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4
}

// Helper extension for creating orthographic projection matrices
extension matrix_float4x4 {
    static func makeOrthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> matrix_float4x4 {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        let fan = far + near
        let fsn = far - near
        
        var m = matrix_identity_float4x4
        m.columns.0.x = 2.0 / rsl
        m.columns.1.y = 2.0 / tsb
        m.columns.2.z = -2.0 / fsn
        m.columns.3.x = -ral / rsl
        m.columns.3.y = -tab / tsb
        m.columns.3.z = -fan / fsn
        
        return m
    }
}
