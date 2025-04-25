import Foundation

/// Represents a specific tile within a chunk
struct TileCoord: CustomStringConvertible {
    let chunk: ChunkCoord
    let localX: Int
    let localY: Int

    var description: String {
        return "Chunk(\(chunk.x), \(chunk.y)) Tile(\(localX), \(localY))"
    }
}
