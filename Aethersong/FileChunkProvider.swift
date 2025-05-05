import Foundation

public final class FileChunkProvider: ChunkProvider {
    private let basePath: URL
    private var loadedChunks: [ChunkCoord: Chunk] = [:]
    
    public init(basePath: URL) {
        self.basePath = basePath
    }
    
    public func chunk(at coord: ChunkCoord) -> Chunk {
        if let existing = loadedChunks[coord] {
            return existing
        }
        
        // For now, just generate a demo chunk
        let chunk = Chunk()
        chunk.generateDemoData()
        loadedChunks[coord] = chunk
        print("Generated demo chunk at (\(coord.x), \(coord.y))")
        return chunk
    }
    
    public func updateChunks(around coord: ChunkCoord) {
        // For now, just ensure the immediate neighbors are loaded
        for dx in -1...1 {
            for dy in -1...1 {
                let neighborCoord = ChunkCoord(x: coord.x + dx, y: coord.y + dy)
                if loadedChunks[neighborCoord] == nil {
                    _ = chunk(at: neighborCoord)
                }
            }
        }
    }
    
    public func ensureChunksLoaded(around centerChunk: ChunkCoord, radius: Int = 2) {
        print("Ensuring chunks are loaded around \(centerChunk) with radius \(radius)")
        
        for dx in -radius...radius {
            for dy in -radius...radius {
                let neighborCoord = ChunkCoord(x: centerChunk.x + dx, y: centerChunk.y + dy)
                let _ = chunk(at: neighborCoord)
                print("Loaded chunk at \(neighborCoord)")
            }
        }
    }
}
