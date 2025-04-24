// MARK: - TerrainRenderer Integration with ChunkProvider

import Metal
import MetalKit

/// Responsible for rendering terrain chunks using Metal
public final class TerrainRenderer {
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let device: MTLDevice
    private let vertexDescriptor: MTLVertexDescriptor
    private var meshCache: [ChunkCoord: MTKMesh] = [:]
    private let chunkProvider: ChunkProvider
    private var cameraViewMatrix: matrix_float4x4 = matrix_identity_float4x4
    private var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4

    public init(device: MTLDevice,
                library: MTLLibrary,
                descriptor: MTLVertexDescriptor,
                pixelFormat: MTLPixelFormat,
                chunkProvider: ChunkProvider) throws {
        self.device = device
        self.vertexDescriptor = descriptor
        self.chunkProvider = chunkProvider

        // Setup render pipeline
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = library.makeFunction(name: "vertexShader")
        pd.fragmentFunction = library.makeFunction(name: "fragmentShader")
        pd.vertexDescriptor = descriptor
        pd.colorAttachments[0].pixelFormat = pixelFormat
        pd.depthAttachmentPixelFormat = .depth32Float_stencil8
        pd.stencilAttachmentPixelFormat = .depth32Float_stencil8
        pipelineState = try device.makeRenderPipelineState(descriptor: pd)

        // Configure depth and stencil testing
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: dsDesc)!
    }

    /// Updates the camera matrices that will be used in the next draw call
    public func updateCamera(viewMatrix: matrix_float4x4, projectionMatrix: matrix_float4x4) {
        self.cameraViewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
    }

    /// Draws a grid of terrain chunks centered around the given chunk coordinate
    public func draw(encoder: MTLRenderCommandEncoder,
                     centerChunk: ChunkCoord) {
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)

        let radius = 1
        chunkProvider.updateChunks(around: centerChunk)

        for dx in -radius...radius {
            for dy in -radius...radius {
                let coord = ChunkCoord(x: centerChunk.x + dx, y: centerChunk.y + dy)
                let chunk = chunkProvider.chunk(at: coord)

                // Use cached mesh if available, otherwise build and cache
                let mesh: MTKMesh
                if let cached = meshCache[coord] {
                    mesh = cached
                } else {
                    guard let newMesh = try? ChunkMeshBuilder.buildMesh(from: chunk, device: device) else {
                        print("Failed to build mesh for chunk at (\(coord.x), \(coord.y))")
                        continue
                    }
                    meshCache[coord] = newMesh
                    mesh = newMesh
                }

                // Translate chunk into world space based on its coordinates
                let tx = Float(coord.x * (Chunk.size - 1))
                let ty = Float(coord.y * (Chunk.size - 1))
                let modelMatrix = matrix_float4x4.makeTranslation(x: tx, y: 0, z: ty)

                // Prepare uniforms with transformed view
                var uniforms = Uniforms(
                    modelViewMatrix: matrix_multiply(cameraViewMatrix, modelMatrix),
                    projectionMatrix: projectionMatrix
                )

                // Bind uniforms and vertex data
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
                encoder.setVertexBuffer(mesh.vertexBuffers[0].buffer,
                                        offset: mesh.vertexBuffers[0].offset,
                                        index: 0)

                // Draw each submesh with solid and wireframe modes
                let baseColors: [SIMD4<Float>] = [SIMD4(0,1,0,1), SIMD4(0,0,0,1)]
                let modes: [MTLTriangleFillMode] = [.fill, .lines]
                for i in 0..<modes.count {
                    var color = baseColors[i]
                    encoder.setTriangleFillMode(modes[i])
                    encoder.setFragmentBytes(&color,
                                             length: MemoryLayout<SIMD4<Float>>.stride,
                                             index: 3)
                    for submesh in mesh.submeshes {
                        encoder.drawIndexedPrimitives(
                            type: submesh.primitiveType,
                            indexCount: submesh.indexCount,
                            indexType: submesh.indexType,
                            indexBuffer: submesh.indexBuffer.buffer,
                            indexBufferOffset: submesh.indexBuffer.offset
                        )
                    }
                }
            }
        }
    }
}
