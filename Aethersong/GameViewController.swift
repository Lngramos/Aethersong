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
    private var hoveredTile: TileCoord?

    override func loadView() {
        self.chunkProvider = FileChunkProvider(
            basePath: FileManager.default.temporaryDirectory
        )
        self.entityManager = EntityManager(chunkProvider: chunkProvider)
        self.view = GameView(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let mtkView = self.view as? GameView else {
            fatalError("View of GameViewController is not a GameView")
        }

        renderer = Renderer(
            view: mtkView,
            entityManager: entityManager,
            chunkProvider: chunkProvider
        )

        mtkView.framebufferOnly = false
        
        // Create debug overlay
        debugOverlay = DebugOverlayView(frame: view.bounds)
        debugOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(debugOverlay)
        
        // Make sure debug overlay stays on top and resizes with the view
        NSLayoutConstraint.activate([
            debugOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            debugOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            debugOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            debugOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.inputDelegate = self

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak mtkView] _ in
            mtkView?.draw()
        }

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in
            self?.updateDebugOverlayIfNeeded()
        }

        let initialTile = TileCoord(
            chunk: ChunkCoord(x: 0, y: 0),
            localX: 8,
            localY: 8
        )
        playerEntity = PlayerEntity(
            startingTile: initialTile,
            chunkProvider: chunkProvider
        )
        entityManager.add(playerEntity)
        
        // Setup test teleport key commands
        setupTestTeleportCommands()
    }

    func didMoveMouse(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) {
        // For now, use raw coordinates without scaling
        let adjustedScreenPoint = screenPoint
        
        lastHoveredScreenPoint = adjustedScreenPoint
        lastHoveredViewSize = viewSize
        
        // Update the hovered tile
        hoveredTile = tileFromScreenPoint(adjustedScreenPoint, viewSize: viewSize)
        
        // Update debug overlay with window mouse coordinates
        debugOverlay.updateWindowMouseCoordinates(x: Int(screenPoint.x), y: Int(screenPoint.y))
        
        // Update debug overlay with game mouse coordinates
        debugOverlay.updateGameMouseCoordinates(x: Int(screenPoint.x), y: Int(screenPoint.y))
        
        // Pass the hovered tile to the renderer
        if let tile = hoveredTile {
            renderer.terrainRenderer.setHighlightedTile(tile)
            
            // Update debug overlay with hovered tile information
            debugOverlay.updateHoveredTileCoordinates(
                chunkX: tile.chunk.x, 
                chunkY: tile.chunk.y,
                localX: tile.localX, 
                localY: tile.localY
            )
            
            // Add hit point info to debug overlay
            if let hitPoint = lastHitPoint {
                debugOverlay.updateRayHitInfo(hitPoint: hitPoint)
            }
        } else {
            debugOverlay.updateHoveredTileCoordinates(
                chunkX: nil, 
                chunkY: nil,
                localX: nil, 
                localY: nil
            )
            debugOverlay.updateRayHitInfo(hitPoint: nil)
        }
    }

    func didClick(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) {
        // Verify matrices to debug ray casting issues
        renderer.terrainRenderer.verifyMatrices()
        
        // For now, use raw coordinates without scaling
        let adjustedScreenPoint = screenPoint
        
        guard let tile = tileFromScreenPoint(adjustedScreenPoint, viewSize: viewSize)
        else { 
            print("No valid tile found at click position")
            return 
        }
        
        print("Clicked on tile: \(tile)")
        playerEntity.teleport(to: tile)
        
        // Focus camera on player's new position
        renderer.focusCameraOnPosition(playerEntity.position)
    }

    private func updateDebugOverlayIfNeeded() {
        frameCounter += 1

        let now = CACurrentMediaTime()
        if now - lastFPSTime >= 1.0 {
            fps = frameCounter
            frameCounter = 0
            lastFPSTime = now
        }

        // Update FPS
        debugOverlay.updateFPS(Double(fps))
        
        // Update window mouse coordinates if available
        if let screenPoint = lastHoveredScreenPoint {
            debugOverlay.updateWindowMouseCoordinates(
                x: Int(screenPoint.x),
                y: Int(screenPoint.y)
            )
        }
        
        // Update game mouse coordinates if available
        if let screenPoint = lastHoveredScreenPoint {
            debugOverlay.updateGameMouseCoordinates(
                x: Int(screenPoint.x),
                y: Int(screenPoint.y)
            )
        }
        
        // Update hovered tile coordinates
        if let hoveredTile = hoveredTile {
            debugOverlay.updateHoveredTileCoordinates(
                chunkX: hoveredTile.chunk.x,
                chunkY: hoveredTile.chunk.y,
                localX: hoveredTile.localX,
                localY: hoveredTile.localY
            )
        } else {
            debugOverlay.updateHoveredTileCoordinates(
                chunkX: nil,
                chunkY: nil,
                localX: nil,
                localY: nil
            )
        }
        
        // Update player tile coordinates
        let playerTile = playerEntity.tileCoord
        debugOverlay.updatePlayerTileCoordinates(
            chunkX: playerTile.chunk.x,
            chunkY: playerTile.chunk.y,
            localX: playerTile.localX,
            localY: playerTile.localY
        )
        
        // Keep the general info text for backward compatibility
        var parts: [String] = []
        parts.append(cameraOverlayText())

        debugOverlay.updateText(parts.joined(separator: "\n"))
    }

    private func cameraOverlayText() -> String {
        let cam = renderer.camera.position
        let target = renderer.cameraTarget
        
        return String(format: "Camera: Pos(%.1f,%.1f,%.1f) → Target(%.1f,%.1f,%.1f)",
                     cam.x, cam.y, cam.z,
                     target.x, target.y, target.z)
    }

    private func playerOverlayText() -> String {
        let p = playerEntity.position
        let tile = playerEntity.tileCoord
        
        return String(format: "Player: Chunk(%d,%d) Tile(%d,%d) → World(%.1f,%.1f,%.1f)",
                     tile.chunk.x, tile.chunk.y,
                     tile.localX, tile.localY,
                     p.x, p.y, p.z)
    }

    private func mouseHoverOverlayText() -> String {
        guard let screenPoint = lastHoveredScreenPoint,
            let viewSize = lastHoveredViewSize
        else {
            return "Hover: No tile"
        }

        guard let tile = tileFromScreenPoint(screenPoint, viewSize: viewSize)
        else {
            return "Hover: No tile"
        }

        // Calculate world position from tile coordinates
        let worldX = Float(tile.chunk.x * Chunk.size + tile.localX)
        let worldZ = Float(tile.chunk.y * Chunk.size + tile.localY)
        
        // Get the height of the tile
        let chunk = chunkProvider.chunk(at: tile.chunk)
        let height = chunk.tiles[tile.localX][tile.localY].height

        return String(format: "Hover: Chunk(%d,%d) Tile(%d,%d) → World(%.1f,%.1f,%.1f)",
                     tile.chunk.x, tile.chunk.y,
                     tile.localX, tile.localY,
                     worldX, height, worldZ)
    }

    private func tileFromScreenPoint(_ screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>) -> TileCoord? {
        // Cast ray and find intersection point
        let (origin, direction) = renderer.terrainRenderer.rayFromScreen(
            screenPoint: screenPoint, 
            viewSize: viewSize
        )
        
        // Only proceed if the ray is pointing downward
        if direction.y >= 0 {
            return nil
        }
        
        // We'll use a more precise ray-terrain intersection algorithm
        // This is a binary search approach to find the exact intersection point
        
        // First, find a rough intersection with y=0 plane to get bounds for our search
        let t0 = -origin.y / direction.y
        guard t0.isFinite && t0 > 0 else { 
            return nil 
        }
        
        let chunkSize = Float(Chunk.size)
        
        // Define our search range
        // Start from a point above the terrain
        var minDistance: Float = 0
        // End at a point well below any possible terrain
        var maxDistance: Float = t0 * 2
        
        // Binary search parameters
        let maxIterations = 20
        let epsilon: Float = 0.01  // Precision threshold
        
        var bestHitPoint: SIMD3<Float>? = nil
        var bestTileCoord: TileCoord? = nil
        var minHeightDifference: Float = Float.greatestFiniteMagnitude
        
        // Binary search for the intersection point
        for _ in 0..<maxIterations {
            // Calculate the midpoint of our search range
            let midDistance = (minDistance + maxDistance) / 2
            let testPoint = origin + direction * midDistance
            
            // Calculate chunk and tile coordinates for this test point
            let testChunkX = Int(floor(testPoint.x / chunkSize))
            let testChunkY = Int(floor(testPoint.z / chunkSize))
            
            // Calculate local coordinates within chunk
            let testLocalXFloat = testPoint.x - (Float(testChunkX) * chunkSize)
            let testLocalYFloat = testPoint.z - (Float(testChunkY) * chunkSize)
            
            // Convert to integer tile coordinates
            let testLocalX = Int(floor(testLocalXFloat))
            let testLocalY = Int(floor(testLocalYFloat))
            
            // Ensure coordinates are within valid range
            if testLocalX < 0 || testLocalX >= Chunk.size || testLocalY < 0 || testLocalY >= Chunk.size {
                // Outside valid chunk bounds, adjust search range
                minDistance = midDistance
                continue
            }
            
            // Get the chunk and tile at test position
            let testChunk = chunkProvider.chunk(at: ChunkCoord(x: testChunkX, y: testChunkY))
            let tileHeight = testChunk.tiles[testLocalX][testLocalY].height
            
            // Calculate height difference
            let heightDifference = testPoint.y - tileHeight
            
            // If we're very close to the surface, we've found our intersection
            if abs(heightDifference) < epsilon {
                bestHitPoint = testPoint
                bestTileCoord = TileCoord(
                    chunk: ChunkCoord(x: testChunkX, y: testChunkY),
                    localX: testLocalX,
                    localY: testLocalY
                )
                break
            }
            
            // Track the closest point to the surface we've found
            if abs(heightDifference) < minHeightDifference {
                minHeightDifference = abs(heightDifference)
                bestHitPoint = testPoint
                bestTileCoord = TileCoord(
                    chunk: ChunkCoord(x: testChunkX, y: testChunkY),
                    localX: testLocalX,
                    localY: testLocalY
                )
            }
            
            // Adjust our search range
            if heightDifference > 0 {
                // We're above the terrain, search further along the ray
                minDistance = midDistance
            } else {
                // We're below the terrain, search closer to the origin
                maxDistance = midDistance
            }
            
            // If our search range is very small, we've converged
            if maxDistance - minDistance < epsilon {
                break
            }
        }
        
        // If we found a good intersection point, use it
        if let hitPoint = bestHitPoint, let tileCoord = bestTileCoord {
            lastHitPoint = hitPoint
            return tileCoord
        }
        
        // Fallback to a simpler approach if binary search failed
        // Use linear search with smaller steps
        var currentDistance: Float = 0
        let stepSize: Float = 0.2
        let maxDistance2: Float = 100  // Limit search distance
        
        while currentDistance < maxDistance2 {
            let testPoint = origin + direction * currentDistance
            
            // Calculate chunk and tile coordinates
            let testChunkX = Int(floor(testPoint.x / chunkSize))
            let testChunkY = Int(floor(testPoint.z / chunkSize))
            
            // Calculate local coordinates within chunk
            let testLocalXFloat = testPoint.x - (Float(testChunkX) * chunkSize)
            let testLocalYFloat = testPoint.z - (Float(testChunkY) * chunkSize)
            
            // Convert to integer tile coordinates
            let testLocalX = Int(floor(testLocalXFloat))
            let testLocalY = Int(floor(testLocalYFloat))
            
            // Ensure coordinates are within valid range
            if testLocalX >= 0 && testLocalX < Chunk.size && testLocalY >= 0 && testLocalY < Chunk.size {
                // Get the chunk and tile at test position
                let testChunk = chunkProvider.chunk(at: ChunkCoord(x: testChunkX, y: testChunkY))
                let tileHeight = testChunk.tiles[testLocalX][testLocalY].height
                
                // If we're at or below the terrain surface, we've found our intersection
                if testPoint.y <= tileHeight {
                    lastHitPoint = testPoint
                    return TileCoord(
                        chunk: ChunkCoord(x: testChunkX, y: testChunkY),
                        localX: testLocalX,
                        localY: testLocalY
                    )
                }
            }
            
            currentDistance += stepSize
        }
        
        // If all else fails, use the initial plane intersection
        let fallbackPoint = origin + direction * t0
        lastHitPoint = fallbackPoint
        
        let fbChunkX = Int(floor(fallbackPoint.x / chunkSize))
        let fbChunkY = Int(floor(fallbackPoint.z / chunkSize))
        let fbLocalX = Int(floor(fallbackPoint.x - Float(fbChunkX) * chunkSize))
        let fbLocalY = Int(floor(fallbackPoint.z - Float(fbChunkY) * chunkSize))
        
        return TileCoord(
            chunk: ChunkCoord(x: fbChunkX, y: fbChunkY),
            localX: max(0, min(fbLocalX, Chunk.size - 1)),
            localY: max(0, min(fbLocalY, Chunk.size - 1))
        )
    }
    
    // Test teleport positions for debugging
    private func setupTestTeleportCommands() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let key = event.charactersIgnoringModifiers else {
                return event
            }
            
            // Use number keys 1-6 to teleport to test positions
            switch key {
            case "1":
                self.testTeleport(chunk: 0, 0, tile: 8, 8)
                return nil
            case "2":
                self.testTeleport(chunk: 1, 0, tile: 8, 8)
                return nil
            case "3":
                self.testTeleport(chunk: 0, 1, tile: 8, 8)
                return nil
            case "4":
                self.testTeleport(chunk: 1, 1, tile: 8, 8)
                return nil
            case "5":
                self.testTeleport(chunk: -1, 0, tile: 8, 8)
                return nil
            case "6":
                self.testTeleport(chunk: 0, -1, tile: 8, 8)
                return nil
            default:
                break
            }
            
            return event
        }
    }
    
    private func testTeleport(chunk chunkX: Int, _ chunkY: Int, tile tileX: Int, _ tileY: Int) {
        print("\n--- TEST TELEPORT ---")
        print("Teleporting to Chunk(\(chunkX), \(chunkY)) Tile(\(tileX), \(tileY))")
        
        let chunkCoord = ChunkCoord(x: chunkX, y: chunkY)
        
        // Ensure chunks are loaded in the area
        chunkProvider.ensureChunksLoaded(around: chunkCoord, radius: 2)
        
        // Extend camera range to see distant chunks
        renderer.extendCameraRange()
        
        let tile = TileCoord(
            chunk: chunkCoord,
            localX: tileX,
            localY: tileY
        )
        
        playerEntity.teleport(to: tile)
        
        // Force camera to look at the player's new position
        renderer.focusCameraOnPosition(playerEntity.position)
        
        print("------------------\n")
    }
}
    // Store the last hit point for visual debugging
    private var lastHitPoint: SIMD3<Float>?
