import Cocoa

final class DebugOverlayView: NSView {
    // MARK: - UI Elements
    private var fpsLabel: NSTextField!
    private var windowMouseCoordinatesLabel: NSTextField!
    private var gameMouseCoordinatesLabel: NSTextField!
    private var hoveredTileCoordinatesLabel: NSTextField!
    private var playerTileCoordinatesLabel: NSTextField!
    private var generalInfoLabel: NSTextField!
    private var rayHitInfoLabel: NSTextField!
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        setupLabels()
    }
    
    private func setupLabels() {
        // Create FPS label
        fpsLabel = createLabel(y: 130)
        fpsLabel.stringValue = "FPS: 0"
        
        // Create window mouse coordinates label
        windowMouseCoordinatesLabel = createLabel(y: 110)
        windowMouseCoordinatesLabel.stringValue = "Window Mouse: (0, 0)"
        
        // Create game mouse coordinates label
        gameMouseCoordinatesLabel = createLabel(y: 90)
        gameMouseCoordinatesLabel.stringValue = "Game Mouse: (0, 0)"
        
        // Create hovered tile coordinates label
        hoveredTileCoordinatesLabel = createLabel(y: 70)
        hoveredTileCoordinatesLabel.stringValue = "Hovered Tile: None"
        
        // Create player tile coordinates label
        playerTileCoordinatesLabel = createLabel(y: 50)
        playerTileCoordinatesLabel.stringValue = "Player Tile: None"
        
        // Create ray hit info label
        rayHitInfoLabel = createLabel(y: 30)
        rayHitInfoLabel.stringValue = "Ray Hit: None"
        
        // Create general info label
        generalInfoLabel = createLabel(y: 10)
        generalInfoLabel.stringValue = ""
    }
    
    private func createLabel(y: CGFloat) -> NSTextField {
        let label = NSTextField(frame: NSRect(x: 10, y: y, width: 400, height: 20))
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = true
        label.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        label.textColor = NSColor.white
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        addSubview(label)
        return label
    }
    
    // MARK: - Public Methods
    
    /// Updates the FPS display
    func updateFPS(_ fps: Double) {
        fpsLabel.stringValue = String(format: "FPS: %.1f", fps)
    }
    
    /// Updates the window mouse coordinates display
    func updateWindowMouseCoordinates(x: Int, y: Int) {
        windowMouseCoordinatesLabel.stringValue = "Window Mouse: (\(x), \(y))"
    }
    
    /// Updates the game mouse coordinates display (in game world coordinates)
    func updateGameMouseCoordinates(x: Int, y: Int) {
        gameMouseCoordinatesLabel.stringValue = "Game Mouse: (\(x), \(y))"
    }
    
    /// Updates the hovered tile coordinates display
    func updateHoveredTileCoordinates(chunkX: Int?, chunkY: Int?, localX: Int?, localY: Int?) {
        if let chunkX = chunkX, let chunkY = chunkY, let localX = localX, let localY = localY {
            hoveredTileCoordinatesLabel.stringValue = "Hovered Tile: Chunk(\(chunkX), \(chunkY)) Local(\(localX), \(localY))"
        } else {
            hoveredTileCoordinatesLabel.stringValue = "Hovered Tile: None"
        }
    }
    
    /// Updates the player tile coordinates display
    func updatePlayerTileCoordinates(chunkX: Int?, chunkY: Int?, localX: Int?, localY: Int?) {
        if let chunkX = chunkX, let chunkY = chunkY, let localX = localX, let localY = localY {
            playerTileCoordinatesLabel.stringValue = "Player Tile: Chunk(\(chunkX), \(chunkY)) Local(\(localX), \(localY))"
        } else {
            playerTileCoordinatesLabel.stringValue = "Player Tile: None"
        }
    }
    
    /// Updates the ray hit information
    func updateRayHitInfo(hitPoint: SIMD3<Float>?) {
        if let hitPoint = hitPoint {
            rayHitInfoLabel.stringValue = String(format: "Ray Hit: (%.2f, %.2f, %.2f)", hitPoint.x, hitPoint.y, hitPoint.z)
        } else {
            rayHitInfoLabel.stringValue = "Ray Hit: None"
        }
    }
    
    /// Updates the general information text
    func updateText(_ text: String) {
        generalInfoLabel.stringValue = text
    }
    
    // MARK: - Legacy Methods (for backward compatibility)
    
    /// Legacy method for updating mouse coordinates (maps to game mouse coordinates)
    func updateMouseCoordinates(x: Int, y: Int) {
        updateGameMouseCoordinates(x: x, y: y)
    }
    
    /// Legacy method for updating tile coordinates (maps to hovered tile coordinates)
    func updateTileCoordinates(chunkX: Int?, chunkY: Int?, localX: Int?, localY: Int?) {
        updateHoveredTileCoordinates(chunkX: chunkX, chunkY: chunkY, localX: localX, localY: localY)
    }
}
