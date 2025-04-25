import Cocoa
import MetalKit

final class GameViewController: NSViewController, GameViewInputDelegate {
    private var renderer: Renderer!
    private var debugOverlay: DebugOverlayView!
    private var lastHoveredScreenPoint: SIMD2<Float>?
    private var lastHoveredViewSize: SIMD2<Float>?
    private var frameCounter: Int = 0
    private var lastFPSTime: TimeInterval = CACurrentMediaTime()
    private var fps: Int = 0

    override func loadView() {
        self.view = GameView(
            frame: NSRect(x: 0, y: 0, width: 1280, height: 720)
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? GameView else {
            fatalError("View of GameViewController is not an GameView")
        }

        // Initialize the renderer with the correct argument label
        renderer = Renderer(view: mtkView)
        mtkView.delegate = renderer
        mtkView.inputDelegate = self
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60

        debugOverlay = DebugOverlayView(frame: CGRect(x: 0, y: 0, width: 300, height: 80))
        debugOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugOverlay)

        NSLayoutConstraint.activate([
            debugOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            debugOverlay.topAnchor.constraint(equalTo: view.topAnchor)
        ])

        let frameInterval = 1.0 / Double(mtkView.preferredFramesPerSecond)

        Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.frameCounter += 1
            self.updateDebugOverlayIfNeeded()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
    }

    func didMoveMouse(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) {
        lastHoveredScreenPoint = screenPoint
        lastHoveredViewSize = viewSize
    }

    func didClick(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) {
        // Future: Handle clicks (e.g., move player, select tile)
    }

    // Update debug overlay with latest mouse position and camera info
    private func updateDebugOverlayIfNeeded() {
        guard let screenPoint = lastHoveredScreenPoint, let viewSize = lastHoveredViewSize else { return }

        let (origin, direction) = renderer.terrainRenderer.rayFromScreen(screenPoint: screenPoint, viewSize: viewSize)
        let cameraPosition = renderer.camera.position

        let now = CACurrentMediaTime()
        if now - lastFPSTime >= 1.0 {
            fps = frameCounter
            frameCounter = 0
            lastFPSTime = now
        }

        let t = -origin.y / direction.y
        if !t.isFinite || t < 0 {
            debugOverlay.updateText(
                """
                FPS: \(fps)
                Camera Pos: (\(String(format: "%.1f", cameraPosition.x)), \(String(format: "%.1f", cameraPosition.y)), \(String(format: "%.1f", cameraPosition.z)))
                World Hover: --
                Tile Hover: --
                Cursor Pos: (\(Int(screenPoint.x)), \(Int(screenPoint.y)))
                """
            )
            return
        }

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

        debugOverlay.updateText(
            """
            FPS: \(fps)
            Camera Pos: (\(String(format: "%.1f", cameraPosition.x)), \(String(format: "%.1f", cameraPosition.y)), \(String(format: "%.1f", cameraPosition.z)))
            World Hover: (\(Int(worldX)), \(Int(worldZ)))
            Tile Hover: (\(chunkCoord.x), \(chunkCoord.y)) (\(correctedLocalX), \(correctedLocalY))
            Cursor Pos: (\(Int(screenPoint.x)), \(Int(screenPoint.y)))
            """
        )
    }
}
