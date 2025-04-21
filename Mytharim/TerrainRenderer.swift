// File: TerrainRenderer.swift
import Metal
import MetalKit

public final class TerrainRenderer {
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let mesh: MTKMesh

    public init(device: MTLDevice,
                library: MTLLibrary,
                descriptor: MTLVertexDescriptor,
                pixelFormat: MTLPixelFormat) throws {
        // Build render pipeline
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = library.makeFunction(name: "vertexShader")
        pd.fragmentFunction = library.makeFunction(name: "fragmentShader")
        pd.vertexDescriptor = descriptor
        pd.colorAttachments[0].pixelFormat = pixelFormat
        pd.depthAttachmentPixelFormat = .depth32Float_stencil8
        pd.stencilAttachmentPixelFormat = .depth32Float_stencil8
        pipelineState = try device.makeRenderPipelineState(descriptor: pd)

        // Depth-stencil state
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: dsDesc)!

        // Generate mesh
        let chunk = Chunk()
        chunk.generateDemoData()
        mesh = try ChunkMeshBuilder.buildMesh(from: chunk, device: device)
    }

    public func draw(encoder: MTLRenderCommandEncoder,
                     uniformsBuffer: MTLBuffer,
                     uniformOffset: Int) {
        // Bind pipeline & depth state
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        // Bind uniform buffer
        encoder.setVertexBuffer(uniformsBuffer, offset: uniformOffset, index: 2)
        encoder.setFragmentBuffer(uniformsBuffer, offset: uniformOffset, index: 2)
        // Bind mesh vertex buffer
        encoder.setVertexBuffer(mesh.vertexBuffers[0].buffer,
                                offset: mesh.vertexBuffers[0].offset,
                                index: 0)

        // Two-pass draw: filled then wireframe
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
