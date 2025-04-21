// ----------------------------------------
// File: Chunk.swift
// Represents a 16×16 block of tiles with demo heightmap generation
import Foundation

public class Chunk {
    public static let size = 16
    public private(set) var tiles: [[Tile]]

    public init() {
        self.tiles = Array(
            repeating: Array(repeating: Tile(), count: Chunk.size),
            count: Chunk.size
        )
    }

    /// Generates a radial hill demo heightmap
    public func generateDemoData() {
        let centre = Chunk.size / 2
        for x in 0..<Chunk.size {
            for y in 0..<Chunk.size {
                let dx = Float(x - centre)
                let dy = Float(y - centre)
                let dist = sqrt(dx*dx + dy*dy)
                let h = max(0, Float(4) - dist)
                tiles[x][y] = Tile(height: h, type: 0)
            }
        }
    }
}
