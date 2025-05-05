import Metal
import MetalKit
import ModelIO
import simd

public struct ChunkMeshBuilder {
    /// Builds a mesh from a chunk using interleaved position + texcoord
    public static func buildMesh(from chunk: Chunk, device: MTLDevice) throws
        -> MTKMesh
    {
        let allocator = MTKMeshBufferAllocator(device: device)
        let size = Chunk.size

        // Generate interleaved vertex data: [x, y, z, u, v]
        var vertexData: [Float] = []
        vertexData.reserveCapacity(size * size * 5)
        
        // Fix: Ensure vertices go from 0 to size (inclusive) to cover the full chunk area
        // This ensures that adjacent chunks will connect properly
        for x in 0...size {
            for y in 0...size {
                // For vertices at the edge (x=size or y=size), use the last tile's height
                let tileX = min(x, size-1)
                let tileY = min(y, size-1)
                let tile = chunk.tiles[tileX][tileY]
                
                // Position - use actual x,y values for positioning
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

        // Build index buffer - adjusted for the new vertex layout
        var indices: [UInt32] = []
        indices.reserveCapacity(size * size * 6)
        
        // Fix: Adjust the indexing to account for the extra vertices
        let verticesPerRow = size + 1
        for x in 0..<size {
            for y in 0..<size {
                let tl = UInt32(x * verticesPerRow + y)
                let tr = UInt32(x * verticesPerRow + (y + 1))
                let bl = UInt32((x + 1) * verticesPerRow + y)
                let br = UInt32((x + 1) * verticesPerRow + (y + 1))
                // Two triangles
                indices += [tl, bl, tr, tr, bl, br]
            }
        }
        
        let iDataSize = indices.count * MemoryLayout<UInt32>.stride
        let iData = Data(bytes: indices, count: iDataSize)
        let indexBuffer = allocator.newBuffer(with: iData, type: .index)

        // Create ModelIO vertex descriptor
        let mdlDesc = MDLVertexDescriptor()
        mdlDesc.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        mdlDesc.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: MemoryLayout<SIMD3<Float>>.stride,
            bufferIndex: 0
        )
        mdlDesc.layouts[0] = MDLVertexBufferLayout(
            stride: MemoryLayout<Float>.stride * 5
        )

        // Create MDLMesh and convert to MTKMesh
        let mdlMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: (size + 1) * (size + 1),  // Updated vertex count
            descriptor: mdlDesc,
            submeshes: [
                MDLSubmesh(
                    indexBuffer: indexBuffer,
                    indexCount: indices.count,
                    indexType: .uInt32,
                    geometryType: .triangles,
                    material: nil
                )
            ]
        )
        return try MTKMesh(mesh: mdlMesh, device: device)
    }

    /// Alias for buildMesh
    public static func makeMesh(from chunk: Chunk, device: MTLDevice) throws
        -> MTKMesh
    {
        return try buildMesh(from: chunk, device: device)
    }
}
