// File: GameViewController.swift
import Cocoa
import MetalKit

final class GameViewController: NSViewController, GameViewInputDelegate {
    private var renderer: Renderer!
    
    override func loadView() {
        self.view = GameView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        print("View is a:", type(of: view))
        
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
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
    }
    
    func didClick(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) {
        let (origin, direction) = renderer.terrainRenderer.rayFromScreen(screenPoint: screenPoint, viewSize: viewSize)

        // Assume ground plane at y = 0
        let t = -origin.y / direction.y
        if t < 0 {
            print("Click did not hit the ground plane.")
            return
        }

        let hitPoint = origin + direction * t

        let worldX = hitPoint.x
        let worldZ = hitPoint.z

        // Determine chunk coordinates
        let chunkX = Int(floor(worldX)) / Chunk.size
        let chunkY = Int(floor(worldZ)) / Chunk.size
        let chunkCoord = ChunkCoord(x: chunkX, y: chunkY)

        // Determine local tile within the chunk
        let localX = Int(floor(worldX)) % Chunk.size
        let localY = Int(floor(worldZ)) % Chunk.size

        // Correct for negative modulo
        let correctedLocalX = localX < 0 ? localX + Chunk.size : localX
        let correctedLocalY = localY < 0 ? localY + Chunk.size : localY

        let tileCoord = TileCoord(chunk: chunkCoord, localX: correctedLocalX, localY: correctedLocalY)

        print("Clicked tile: \(tileCoord)")
    }
}
