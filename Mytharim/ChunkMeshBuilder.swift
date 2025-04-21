
// ----------------------------------------
// File: ChunkMeshBuilder.swift
// Converts Chunk heightmap into an MTKMesh for rendering
import Metal
import MetalKit
import ModelIO
import simd

public struct ChunkMeshBuilder {
    /// Builds a mesh from a 16x16 Chunk, interleaving position and texcoord
    public static func buildMesh(from chunk: Chunk, device: MTLDevice) throws -> MTKMesh {
        let allocator = MTKMeshBufferAllocator(device: device)

        // Generate interleaved vertex data [x, y, z, u, v]
        var vertexData: [Float] = []
        vertexData.reserveCapacity(Chunk.size * Chunk.size * 5)
        for x in 0..<Chunk.size {
            for y in 0..<Chunk.size {
                let tile = chunk.tiles[x][y]
                vertexData += [Float(x), tile.height, Float(y), 0.0, 0.0]
            }
        }
        let vDataSize = vertexData.count * MemoryLayout<Float>.stride
        let vData = Data(bytes: vertexData, count: vDataSize)
        let vertexBuffer = allocator.newBuffer(with: vData, type: .vertex)

        // Build index buffer for triangles
        var indices: [UInt32] = []
        indices.reserveCapacity((Chunk.size - 1) * (Chunk.size - 1) * 6)
        for x in 0..<Chunk.size-1 {
            for y in 0..<Chunk.size-1 {
                let tl = UInt32(x * Chunk.size + y)
                let tr = UInt32((x + 1) * Chunk.size + y)
                let bl = UInt32(x * Chunk.size + (y + 1))
                let br = UInt32((x + 1) * Chunk.size + (y + 1))
                indices += [tl, bl, tr, tr, bl, br]
            }
        }
        let iDataSize = indices.count * MemoryLayout<UInt32>.stride
        let iData = Data(bytes: indices, count: iDataSize)
        let indexBuffer = allocator.newBuffer(with: iData, type: .index)

        // ModelIO descriptor matching interleaved layout
        let mdlDesc = MDLVertexDescriptor()
        mdlDesc.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                   format: .float3,
                                                   offset: 0,
                                                   bufferIndex: 0)
        mdlDesc.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                   format: .float2,
                                                   offset: MemoryLayout<SIMD3<Float>>.stride,
                                                   bufferIndex: 0)
        mdlDesc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.stride * 5)

        let mesh = MDLMesh(vertexBuffer: vertexBuffer,
                           vertexCount: Chunk.size * Chunk.size,
                           descriptor: mdlDesc,
                           submeshes: [MDLSubmesh(indexBuffer: indexBuffer,
                                                   indexCount: indices.count,
                                                   indexType: .uInt32,
                                                   geometryType: .triangles,
                                                   material: nil)])

        return try MTKMesh(mesh: mesh, device: device)
    }
}
