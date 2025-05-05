import Foundation

/// Protocol defining how to provide chunks for the game world
public protocol ChunkProvider {
    func chunk(at coord: ChunkCoord) -> Chunk
    func updateChunks(around coord: ChunkCoord)
    func ensureChunksLoaded(around centerChunk: ChunkCoord, radius: Int)
}
