import Foundation

/// Represents a specific tile within a chunk
public struct TileCoord: CustomStringConvertible {
    public let chunk: ChunkCoord
    public let localX: Int
    public let localY: Int

    public var description: String {
        return "Chunk(\(chunk.x), \(chunk.y)) Tile(\(localX), \(localY))"
    }

    public init(chunk: ChunkCoord, localX: Int, localY: Int) {
        self.chunk = chunk
        self.localX = localX
        self.localY = localY
    }
}
