import Metal
import Foundation

/// Manages all active entities in the world
@MainActor
public final class EntityManager {
    private(set) var entities: [Entity] = []
    private let chunkProvider: ChunkProvider

    public init(chunkProvider: ChunkProvider) {
        self.chunkProvider = chunkProvider
    }

    public func add(_ entity: Entity) {
        entities.append(entity)
    }

    public func updateAll(deltaTime: Float) {
        for entity in entities {
            entity.update(deltaTime: deltaTime)
        }
    }

    public func drawAll(encoder: MTLRenderCommandEncoder) {
        for entity in entities {
            entity.draw(encoder: encoder)
        }
    }
}
