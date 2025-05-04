import Foundation

public struct Tile {
    public var height: Float
    public var type: UInt8

    public init(height: Float = 0, type: UInt8 = 0) {
        self.height = height
        self.type = type
    }
}
