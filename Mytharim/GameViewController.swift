import Cocoa
import MetalKit

final class GameViewController: NSViewController, GameViewInputDelegate {
    private var chunkProvider: ChunkProvider!
    private var entityManager: EntityManager!
    private var renderer: Renderer!
    private var debugOverlay: DebugOverlayView!
    private var lastHoveredScreenPoint: SIMD2<Float>?
    private var lastHoveredViewSize: SIMD2<Float>?
    private var playerEntity: PlayerEntity!
    private var frameCounter: Int = 0
    private var lastFPSTime: TimeInterval = CACurrentMediaTime()
    private var fps: Int = 0

    override func loadView() {
        self.chunkProvider = FileChunkProvider(basePath: FileManager.default.temporaryDirectory)
        self.entityManager = EntityManager(chunkProvider: chunkProvider)
        self.view = GameView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let mtkView = self.view as? GameView else {
            fatalError("View of GameViewController is not a GameView")
        }

        renderer = Renderer(view: mtkView, entityManager: entityManager, chunkProvider: chunkProvider)

        mtkView.framebufferOnly = false
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.inputDelegate = self

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak mtkView] _ in
            mtkView?.draw()
        }

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateDebugOverlayIfNeeded()
        }

        debugOverlay = DebugOverlayView(frame: CGRect(x: 0, y: 0, width: 300, height: 100))
        debugOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugOverlay)

        NSLayoutConstraint.activate([
            debugOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            debugOverlay.topAnchor.constraint(equalTo: view.topAnchor, constant: 8)
        ])

        let initialTile = TileCoord(chunk: ChunkCoord(x: 0, y: 0), localX: 8, localY: 8)
        playerEntity = PlayerEntity(startingTile: initialTile, chunkProvider: chunkProvider)
        entityManager.add(playerEntity)
    }

    func didMoveMouse(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) {
        lastHoveredScreenPoint = screenPoint
        lastHoveredViewSize = viewSize
    }

    func didClick(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) {
        guard let tile = tileFromScreenPoint(screenPoint, viewSize: viewSize) else { return }
        playerEntity.teleport(to: tile)
    }

    private func updateDebugOverlayIfNeeded() {
        frameCounter += 1

        let now = CACurrentMediaTime()
        if now - lastFPSTime >= 1.0 {
            fps = frameCounter
            frameCounter = 0
            lastFPSTime = now
        }

        var parts: [String] = []
        parts.append("FPS: \(fps)")
        parts.append(cameraOverlayText())
        parts.append(mouseHoverOverlayText())
        parts.append(playerOverlayText())
        print("Camera at \(renderer.camera.position), Player at \(playerEntity.position)")

        debugOverlay.updateText(parts.joined(separator: "\n"))
    }

    private func cameraOverlayText() -> String {
        let cam = renderer.camera.position
        return "Camera Pos: (\(Int(cam.x)), \(Int(cam.y)), \(Int(cam.z)))"
    }

    private func playerOverlayText() -> String {
        let p = playerEntity.position
        return "Player Pos: (\(Int(p.x)), \(Int(p.y)), \(Int(p.z)))"
    }

    private func mouseHoverOverlayText() -> String {
        guard let screenPoint = lastHoveredScreenPoint, let viewSize = lastHoveredViewSize else {
            return "World Hover: --\nTile Hover: --"
        }

        guard let tile = tileFromScreenPoint(screenPoint, viewSize: viewSize) else {
            return "World Hover: --\nTile Hover: --"
        }

        let worldX = Float(tile.chunk.x * Chunk.size + tile.localX)
        let worldZ = Float(tile.chunk.y * Chunk.size + tile.localY)

        return "World Hover: (\(Int(worldX)), \(Int(worldZ)))\nTile Hover: (\(tile.chunk.x), \(tile.chunk.y)) (\(tile.localX), \(tile.localY))"
    }

    private func tileFromScreenPoint(_ screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) -> TileCoord? {
        let (origin, direction) = renderer.terrainRenderer.rayFromScreen(screenPoint: screenPoint, viewSize: viewSize)
        let t = -origin.y / direction.y
        guard t.isFinite && t >= 0 else { return nil }

        let hitPoint = origin + direction * t
        let worldX = hitPoint.x
        let worldZ = hitPoint.z

        let chunkX = Int(floor(worldX)) / Chunk.size
        let chunkY = Int(floor(worldZ)) / Chunk.size
        let chunkCoord = ChunkCoord(x: chunkX, y: chunkY)

        let localX = Int(floor(worldX)) % Chunk.size
        let localY = Int(floor(worldZ)) % Chunk.size

        let correctedLocalX = localX < 0 ? localX + Chunk.size : localX
        let correctedLocalY = localY < 0 ? localY + Chunk.size : localY

        return TileCoord(chunk: chunkCoord, localX: correctedLocalX, localY: correctedLocalY)
    }
}
