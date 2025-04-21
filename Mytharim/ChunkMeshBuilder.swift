// ----------------------------------------
// File: ChunkMeshBuilder.swift
import Metal
import MetalKit
import ModelIO
import simd

public struct ChunkMeshBuilder {
    /// Builds a mesh from a chunk using interleaved position + texcoord
    public static func buildMesh(from chunk: Chunk, device: MTLDevice) throws -> MTKMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let size = Chunk.size
        
        // Generate interleaved vertex data: [x, y, z, u, v]
        var vertexData: [Float] = []
        vertexData.reserveCapacity(size * size * 5)
        for x in 0..<size {
            for y in 0..<size {
                let tile = chunk.tiles[x][y]
                // Position
                vertexData.append(Float(x))
                vertexData.append(tile.height)
                vertexData.append(Float(y))
                // Dummy texcoord
                vertexData.append(0.0)
                vertexData.append(0.0)
            }
        }
        let vDataSize = vertexData.count * MemoryLayout<Float>.stride
        let vData = Data(bytes: vertexData, count: vDataSize)
        let vertexBuffer = allocator.newBuffer(with: vData, type: .vertex)
        
        // Build index buffer
        var indices: [UInt32] = []
        indices.reserveCapacity((size - 1) * (size - 1) * 6)
        for x in 0..<size-1 {
            for y in 0..<size-1 {
                let tl = UInt32(x * size + y)
                let tr = UInt32((x + 1) * size + y)
                let bl = UInt32(x * size + (y + 1))
                let br = UInt32((x + 1) * size + (y + 1))
                // Two triangles
                indices += [tl, bl, tr, tr, bl, br]
            }
        }
        let iDataSize = indices.count * MemoryLayout<UInt32>.stride
        let iData = Data(bytes: indices, count: iDataSize)
        let indexBuffer = allocator.newBuffer(with: iData, type: .index)
        
        // Create ModelIO vertex descriptor
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

        // Create MDLMesh and convert to MTKMesh
        let mdlMesh = MDLMesh(vertexBuffer: vertexBuffer,
                              vertexCount: size * size,
                              descriptor: mdlDesc,
                              submeshes: [MDLSubmesh(indexBuffer: indexBuffer,
                                                      indexCount: indices.count,
                                                      indexType: .uInt32,
                                                      geometryType: .triangles,
                                                      material: nil)])
        return try MTKMesh(mesh: mdlMesh, device: device)
    }

    /// Alias for buildMesh
    public static func makeMesh(from chunk: Chunk, device: MTLDevice) throws -> MTKMesh {
        return try buildMesh(from: chunk, device: device)
    }
}
