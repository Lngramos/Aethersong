import simd
import Metal

/// Base class for all world entities (players, NPCs, etc.)
open class Entity {
    public var position: SIMD3<Float>

    public init(position: SIMD3<Float>) {
        self.position = position
    }

    open func update(deltaTime: Float) {
        // Default no-op
    }

    open func draw(encoder: MTLRenderCommandEncoder) {
        // Default no-op
    }
}
