import Cocoa
import MetalKit

public final class PlayerEntity: Entity {
    public private(set) var tileCoord: TileCoord
    private let chunkProvider: ChunkProvider

    private static var vertexBuffer: MTLBuffer?
    private static var indexBuffer: MTLBuffer?
    private static var indexCount: Int = 0

    public init(startingTile: TileCoord, chunkProvider: ChunkProvider) {
        self.tileCoord = startingTile
        self.chunkProvider = chunkProvider
        let pos = PlayerEntity.worldPosition(
            for: startingTile,
            using: chunkProvider
        )
        super.init(position: pos)
        buildCubeBuffersIfNeeded()
    }

    public func teleport(to tile: TileCoord) {
        self.tileCoord = tile
        self.position = PlayerEntity.worldPosition(
            for: tile,
            using: chunkProvider
        )
    }

    override public func draw(encoder: MTLRenderCommandEncoder) {
        guard let vb = Self.vertexBuffer, let ib = Self.indexBuffer else {
            return
        }

        EntityRenderer.apply(to: encoder)

        var modelMatrix = matrix_identity_float4x4
        modelMatrix.columns.3 = SIMD4<Float>(
            position.x,
            position.y,
            position.z,
            1
        )

        var uniforms = Uniforms(
            modelViewMatrix: GlobalUniforms.cameraViewMatrix * modelMatrix,
            projectionMatrix: GlobalUniforms.projectionMatrix
        )

        // Set uniforms for vertex shader only
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: 2
        )

        // Set vertex buffer
        encoder.setVertexBuffer(vb, offset: 0, index: 0)

        // Set color for fragment shader
        var color = SIMD4<Float>(1, 0, 0, 1)  // Red
        encoder.setFragmentBytes(
            &color,
            length: MemoryLayout<SIMD4<Float>>.stride,
            index: 3
        )

        encoder.setTriangleFillMode(.fill)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: Self.indexCount,
            indexType: .uint16,
            indexBuffer: ib,
            indexBufferOffset: 0
        )
    }

    private static func worldPosition(
        for tile: TileCoord,
        using provider: ChunkProvider
    ) -> SIMD3<Float> {
        let worldX = Float(tile.chunk.x * Chunk.size + tile.localX) + 0.5
        let worldZ = Float(tile.chunk.y * Chunk.size + tile.localY) + 0.5

        let chunk = provider.chunk(at: tile.chunk)
        let tileHeight = chunk.tiles[tile.localX][tile.localY].height

        let worldY = tileHeight + 0.4

        return SIMD3<Float>(worldX, worldY, worldZ)
    }

    private func buildCubeBuffersIfNeeded() {
        guard Self.vertexBuffer == nil else { return }

        let s: Float = 0.4
        let cubeVertices: [Float] = [
            // x, y, z, u, v
            -s, -s, -s, 0.0, 0.0,
            s, -s, -s, 0.0, 0.0,
            s, s, -s, 0.0, 0.0,
            -s, s, -s, 0.0, 0.0,
            -s, -s, s, 0.0, 0.0,
            s, -s, s, 0.0, 0.0,
            s, s, s, 0.0, 0.0,
            -s, s, s, 0.0, 0.0,
        ]

        let cubeIndices: [UInt16] = [
            0, 2, 1, 0, 3, 2,
            4, 5, 6, 4, 6, 7,
            0, 1, 5, 0, 5, 4,
            3, 7, 6, 3, 6, 2,
            1, 2, 6, 1, 6, 5,
            0, 4, 7, 0, 7, 3,
        ]

        let device = MTLCreateSystemDefaultDevice()!
        Self.vertexBuffer = device.makeBuffer(
            bytes: cubeVertices,
            length: cubeVertices.count * MemoryLayout<Float>.stride,
            options: []
        )
        Self.indexBuffer = device.makeBuffer(
            bytes: cubeIndices,
            length: cubeIndices.count * MemoryLayout<UInt16>.stride,
            options: []
        )
        Self.indexCount = cubeIndices.count
    }
}
