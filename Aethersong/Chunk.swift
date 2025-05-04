import Foundation

public class Chunk {
    public static let size = 16
    public private(set) var tiles: [[Tile]]

    public init() {
        tiles = Array(
            repeating: Array(repeating: Tile(), count: Chunk.size),
            count: Chunk.size
        )
    }

    public func generateDemoData() {
        let centre = Chunk.size / 2
        for x in 0..<Chunk.size {
            for y in 0..<Chunk.size {
                let dx = Float(x - centre)
                let dy = Float(y - centre)
                let dist = sqrt(dx * dx + dy * dy)
                tiles[x][y] = Tile(height: max(0, 4 - dist), type: 0)
            }
        }
    }
}
