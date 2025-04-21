// ----------------------------------------
// File: Renderer.swift
// Metal renderer focused solely on terrain
import Metal
import MetalKit
import simd

@MainActor
class Renderer: NSObject, MTKViewDelegate {
    // MARK: - Properties
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState
    let depthState: MTLDepthStencilState

    let maxBuffersInFlight = 3
    var dynamicUniformBuffer: MTLBuffer
    var uniformBufferIndex = 0
    var uniformBufferOffset = 0
    var uniforms: UnsafeMutablePointer<Uniforms>

    var projectionMatrix = matrix_identity_float4x4
    var terrainChunk: Chunk!
    var terrainMesh: MTKMesh!
    let inFlightSemaphore = DispatchSemaphore(value: 3)

    // MARK: - Initialization
    init?(metalKitView: MTKView) {
        guard let dev = metalKitView.device else { return nil }
        device = dev
        commandQueue = device.makeCommandQueue()!

        // Uniform buffer setup
        let alignedSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
        dynamicUniformBuffer = device.makeBuffer(length: alignedSize * maxBuffersInFlight,
                                                 options: .storageModeShared)!
        dynamicUniformBuffer.label = "UniformBuffer"
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents())
            .bindMemory(to: Uniforms.self, capacity: 1)

        // MTKView configuration
        metalKitView.depthStencilPixelFormat = .depth32Float_stencil8
        metalKitView.colorPixelFormat = .bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        metalKitView.clearColor = MTLClearColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1)

        // Pipeline setup
        let vDesc = Renderer.buildMetalVertexDescriptor()
        do {
            pipelineState = try Renderer.buildRenderPipelineWithDevice(device: device,
                                                                        metalKitView: metalKitView,
                                                                        mtlVertexDescriptor: vDesc)
        } catch {
            print("Pipeline creation error: \(error)")
            return nil
        }

        // Depth-stencil state
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDesc)!

        // Terrain mesh setup
        terrainChunk = Chunk()
        terrainChunk.generateDemoData()
        do {
            terrainMesh = try ChunkMeshBuilder.buildMesh(from: terrainChunk, device: device)
        } catch {
            print("Terrain mesh build error: \(error)")
            return nil
        }

        super.init()
    }

    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Update projection matrix on size change
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65),
                                                         aspectRatio: aspect,
                                                         nearZ: 0.1,
                                                         farZ: 100)
    }

    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let rpd = view.currentRenderPassDescriptor,
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            inFlightSemaphore.signal()
            return
        }

        updateUniforms(view: view)

        // Bind buffers
        encoder.setVertexBuffer(dynamicUniformBuffer, offset: uniformBufferOffset, index: 2)
        let vb = terrainMesh.vertexBuffers[0]
        encoder.setVertexBuffer(vb.buffer, offset: vb.offset, index: 0)

        // Render passes
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        // Filled pass
        encoder.setTriangleFillMode(.fill)
        var greenColor = SIMD4<Float>(0, 1, 0, 1)
        encoder.setFragmentBytes(&greenColor,
                                 length: MemoryLayout<SIMD4<Float>>.stride,
                                 index: 3)
        drawTerrainPrimitives(encoder: encoder)

        // Wireframe pass
        encoder.setTriangleFillMode(.lines)
        var blackColor = SIMD4<Float>(0, 0, 0, 1)
        encoder.setFragmentBytes(&blackColor,
                                 length: MemoryLayout<SIMD4<Float>>.stride,
                                 index: 3)
        drawTerrainPrimitives(encoder: encoder)

        encoder.endEncoding()
        if let drawable = view.currentDrawable {
            cmdBuf.present(drawable)
        }
        cmdBuf.commit()
    }

    // MARK: - Helpers
    private func drawTerrainPrimitives(encoder: MTLRenderCommandEncoder) {
        for sub in terrainMesh.submeshes {
            encoder.drawIndexedPrimitives(type: sub.primitiveType,
                                          indexCount: sub.indexCount,
                                          indexType: sub.indexType,
                                          indexBuffer: sub.indexBuffer.buffer,
                                          indexBufferOffset: sub.indexBuffer.offset)
        }
    }

    private func updateUniforms(view: MTKView) {
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        let alignedSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
        uniformBufferOffset = alignedSize * uniformBufferIndex
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset)
            .bindMemory(to: Uniforms.self, capacity: 1)

        // Set camera
        let eye = SIMD3<Float>(Float(Chunk.size)/2, 8, Float(Chunk.size)*1.5)
        let target = SIMD3<Float>(Float(Chunk.size)/2, 0, Float(Chunk.size)/2)
        let up = SIMD3<Float>(0, 1, 0)
        let viewMatrix = matrix_lookAtRH(eye: eye, target: target, up: up)
        uniforms.pointee.modelViewMatrix = viewMatrix
        uniforms.pointee.projectionMatrix = projectionMatrix
    }

    // MARK: - Static Pipeline Builders
    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        let desc = MTLVertexDescriptor()
        desc.attributes[0].format = .float3
        desc.attributes[0].offset = 0
        desc.attributes[0].bufferIndex = 0
        desc.attributes[1].format = .float2
        desc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        desc.attributes[1].bufferIndex = 0
        desc.layouts[0].stride = MemoryLayout<Float>.stride * 5
        desc.layouts[0].stepFunction = .perVertex
        desc.layouts[0].stepRate = 1
        return desc
    }

    @MainActor
    class func buildRenderPipelineWithDevice(device: MTLDevice,
                                             metalKitView: MTKView,
                                             mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()!
        let vertFn = library.makeFunction(name: "vertexShader")
        let fragFn = library.makeFunction(name: "fragmentShader")
        let pd = MTLRenderPipelineDescriptor()
        pd.label = "TerrainPipeline"
        pd.sampleCount = metalKitView.sampleCount
        pd.vertexFunction = vertFn
        pd.fragmentFunction = fragFn
        pd.vertexDescriptor = mtlVertexDescriptor
        pd.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pd.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pd.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        return try device.makeRenderPipelineState(descriptor: pd)
    }

    // MARK: - Math Utilities
    private func radians_from_degrees(_ degrees: Float) -> Float {
        return (degrees / 180) * .pi
    }

    private func matrix_perspective_right_hand(fovyRadians fovy: Float,
                                               aspectRatio aspect: Float,
                                               nearZ: Float,
                                               farZ: Float) -> matrix_float4x4 {
        let ys = 1 / tanf(fovy * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        return matrix_float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * nearZ, 0)
        ))
    }

    private func matrix_lookAtRH(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        let P = SIMD4<Float>( x.x,  y.x,  z.x,  0)
        let Q = SIMD4<Float>( x.y,  y.y,  z.y,  0)
        let R = SIMD4<Float>( x.z,  y.z,  z.z,  0)
        let T = SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        return matrix_float4x4(columns: (P, Q, R, T))
    }

// MARK: - Uniform Updates
    private func updateUniforms(view: MTKView) {
        // Cycle uniform buffer index
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        let alignedSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
        uniformBufferOffset = alignedSize * uniformBufferIndex
        uniforms = UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + uniformBufferOffset)
            .bindMemory(to: Uniforms.self, capacity: 1)

        // Compute projection & view with look-at camera
        let aspect = Float(view.drawableSize.width) / Float(view.drawableSize.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65),
                                                         aspectRatio: aspect,
                                                         nearZ: 0.1,
                                                         farZ: 100)
        let eye = SIMD3<Float>(Float(Chunk.size)/2, 8, Float(Chunk.size)*1.5)
        let target = SIMD3<Float>(Float(Chunk.size)/2, 0, Float(Chunk.size)/2)
        let up = SIMD3<Float>(0, 1, 0)
        let viewMatrix = matrix_lookAtRH(eye: eye, target: target, up: up)
        uniforms.pointee.modelViewMatrix = viewMatrix
        uniforms.pointee.projectionMatrix = projectionMatrix
    }

    // MARK: - Math Utilities
    private func radians_from_degrees(_ degrees: Float) -> Float {
        return (degrees / 180) * .pi
    }

    private func matrix_perspective_right_hand(fovyRadians fovy: Float,
                                               aspectRatio aspect: Float,
                                               nearZ: Float,
                                               farZ: Float) -> matrix_float4x4 {
        let ys = 1 / tanf(fovy * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        return matrix_float4x4(columns: (
            SIMD4<Float>(xs, 0, 0, 0),
            SIMD4<Float>(0, ys, 0, 0),
            SIMD4<Float>(0, 0, zs, -1),
            SIMD4<Float>(0, 0, zs * nearZ, 0)
        ))
    }

    private func matrix_lookAtRH(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        let P = SIMD4<Float>( x.x,  y.x,  z.x,  0)
        let Q = SIMD4<Float>( x.y,  y.y,  z.y,  0)
        let R = SIMD4<Float>( x.z,  y.z,  z.z,  0)
        let T = SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        return matrix_float4x4(columns: (P, Q, R, T))
    }

