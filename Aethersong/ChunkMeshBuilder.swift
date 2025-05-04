import Foundation

/// Represents a coordinate in the chunk grid
public struct ChunkCoord: Hashable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Protocol defining how to provide chunks for the game world
public protocol ChunkProvider {
    func chunk(at coord: ChunkCoord) -> Chunk
    func updateChunks(around coord: ChunkCoord)
}

public final class FileChunkProvider: ChunkProvider {
    private var loadedChunks: [ChunkCoord: Chunk] = [:]
    private let fileManager = FileManager.default
    private let basePath: URL

    public init(basePath: URL) {
        self.basePath = basePath
    }

    public func chunk(at coord: ChunkCoord) -> Chunk {
        if let chunk = loadedChunks[coord] {
            return chunk
        }

        let fileURL = basePath.appendingPathComponent(
            "chunk_\(coord.x)_\(coord.y).bin"
        )
        if let data = try? Data(contentsOf: fileURL),
            let chunk = decodeChunk(from: data)
        {
            loadedChunks[coord] = chunk
            print("Loaded chunk at (\(coord.x), \(coord.y)) from disk")
            return chunk
        } else {
            let chunk = Chunk()
            chunk.generateDemoData()
            loadedChunks[coord] = chunk
            print("Generated demo chunk at (\(coord.x), \(coord.y))")
            return chunk
        }
    }

    public func updateChunks(around coord: ChunkCoord) {
        let radius = 1
        for dx in -radius...radius {
            for dy in -radius...radius {
                let neighborCoord = ChunkCoord(x: coord.x + dx, y: coord.y + dy)
                _ = chunk(at: neighborCoord)
            }
        }
    }

    private func decodeChunk(from data: Data) -> Chunk? {
        return nil
    }
}
