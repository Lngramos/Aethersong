import MetalKit
import simd

protocol RendererDelegate: AnyObject {
    func rendererDidUpdate()
}

@MainActor
public class Renderer: NSObject, MTKViewDelegate {
    weak var delegate: RendererDelegate?

    public static var sharedCameraViewMatrix: matrix_float4x4 {
        get { return Aethersong.GlobalUniforms.cameraViewMatrix }
        set { Aethersong.GlobalUniforms.cameraViewMatrix = newValue }
    }
    
    public static var sharedProjectionMatrix: matrix_float4x4 {
        get { return Aethersong.GlobalUniforms.projectionMatrix }
        set { Aethersong.GlobalUniforms.projectionMatrix = newValue }
    }

    public let device: MTLDevice
    public let terrainRenderer: TerrainRenderer
    public let camera = OrbitCamera()
    public let view: MTKView
    private var axisIndicator: AxisIndicator!

    private let entityManager: EntityManager
    private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()

    private let uniformBuffer: MTLBuffer
    private let maxBuffersInFlight = 3
    private var bufferIndex = 0

    // Camera target position
    private var target = SIMD3<Float>(
        Float(Chunk.size) / 2,
        1,
        Float(Chunk.size) / 2
    )
    private var heldKeys: Set<String> = []
    
    // Make camera target accessible for debugging
    public var cameraTarget: SIMD3<Float> {
        return target
    }

    public init(
        view: MTKView,
        entityManager: EntityManager,
        chunkProvider: ChunkProvider
    ) {
        // Setup Metal device
        let device: MTLDevice
        if let dev = view.device {
            device = dev
        } else if let defaultDevice = MTLCreateSystemDefaultDevice() {
            device = defaultDevice
            view.device = device
        } else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.view = view
        self.entityManager = entityManager

        // Get Metal library
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Default Metal library not found")
        }
        
        print("Available Metal functions:")
        let functions = library.functionNames
        if !functions.isEmpty {
            for _ in functions {
                // Use _ to avoid unused variable warning
                // print("  - \(function)")
            }
        } else {
            print("  No functions found in Metal library")
        }

        // Configure MTKView
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float_stencil8
        view.clearColor = MTLClearColor(
            red: 0.53,
            green: 0.81,
            blue: 0.98,
            alpha: 1
        )

        // Uniform buffer
        let alignedSize = (MemoryLayout<Uniforms>.stride + 0xFF) & -0x100
        guard
            let uBuf = device.makeBuffer(
                length: alignedSize * maxBuffersInFlight,
                options: .storageModeShared
            )
        else {
            fatalError("Unable to allocate uniform buffer")
        }
        self.uniformBuffer = uBuf

        // Setup vertex descriptor for terrain
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 5

        // Setup terrain renderer
        do {
            terrainRenderer = try TerrainRenderer(
                device: device,
                library: library,
                descriptor: vertexDescriptor,
                pixelFormat: view.colorPixelFormat,
                chunkProvider: chunkProvider
            )
        } catch {
            fatalError("TerrainRenderer init failed: \\(error)")
        }

        EntityRenderer.buildPipelineState(device: view.device!)
        
        // Initialize axis indicator
        self.axisIndicator = AxisIndicator(device: device)

        super.init()

        view.delegate = self
        setupKeyboardMonitoring()

        // Camera setup
        let aspect = Float(view.bounds.width) / Float(view.bounds.height)
        camera.updatePerspective(
            fovy: radians_from_degrees(65),
            aspect: aspect,
            nearZ: 1.0,
            farZ: 100.0
        )
        
        // Initialize camera position with default values
        camera.target = target
        camera.pitch = 60.0  // 60 degrees (looking down at player)
        camera.yaw = 180.0   // Directly in front of player
        camera.radius = 15.0 // Default distance
    }

    // MARK: - MTKViewDelegate
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        camera.updatePerspective(
            fovy: radians_from_degrees(65),
            aspect: aspect,
            nearZ: 1.0,
            farZ: 100.0
        )
    }

    public func draw(in view: MTKView) {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastFrameTimestamp
        lastFrameTimestamp = currentTime

        entityManager.updateAll(deltaTime: Float(deltaTime))
        
        // Find player position and update camera target
        var playerPosition: SIMD3<Float>? = nil
        for entity in entityManager.entities {
            if let player = entity as? PlayerEntity {
                playerPosition = player.position
                // Always keep camera focused on player
                // Add a small Y offset to focus slightly above the player
                let targetPosition = SIMD3<Float>(player.position.x, player.position.y + 1.0, player.position.z)
                focusCameraOnPosition(targetPosition)
                break
            }
        }
        
        handleHeldKeys()

        bufferIndex = (bufferIndex + 1) % maxBuffersInFlight

        let viewMatrix = camera.viewMatrix
        let projectionMatrix = camera.projectionMatrix
        
        // Update global uniforms with current camera matrices
        Aethersong.GlobalUniforms.cameraViewMatrix = viewMatrix
        Aethersong.GlobalUniforms.projectionMatrix = projectionMatrix

        terrainRenderer.updateCamera(
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix
        )

        guard let cmdQ = view.device?.makeCommandQueue(),
            let cmdBuf = cmdQ.makeCommandBuffer(),
            let rpd = view.currentRenderPassDescriptor,
            let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        // Use player position to determine center chunk for rendering
        let centerChunk: ChunkCoord
        if let playerPos = playerPosition {
            let chunkX = Int(floor(playerPos.x / Float(Chunk.size)))
            let chunkY = Int(floor(playerPos.z / Float(Chunk.size)))
            centerChunk = ChunkCoord(x: chunkX, y: chunkY)
        } else {
            // Fallback to default center if no player found
            let defaultTarget = SIMD3<Float>(
                Float(Chunk.size) / 2,
                1,
                Float(Chunk.size) / 2
            )
            let chunkX = Int(defaultTarget.x) / Chunk.size
            let chunkY = Int(defaultTarget.z) / Chunk.size
            centerChunk = ChunkCoord(x: chunkX, y: chunkY)
        }

        // Pass player position to terrain renderer
        terrainRenderer.draw(encoder: encoder, centerChunk: centerChunk, playerPosition: playerPosition)
        entityManager.drawAll(encoder: encoder)
        
        // Draw axis indicator in the top-right corner
        axisIndicator.draw(encoder: encoder, 
                          viewMatrix: camera.viewMatrix, 
                          projectionMatrix: camera.projectionMatrix)

        encoder.endEncoding()

        if let drawable = view.currentDrawable {
            cmdBuf.present(drawable)
            cmdBuf.commit()
        }
        
        delegate?.rendererDidUpdate()
    }

    private func setupKeyboardMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let key = event.charactersIgnoringModifiers else {
                return event
            }
            self?.heldKeys.insert(key)
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
            [weak self] event in
            guard let key = event.charactersIgnoringModifiers else {
                return nil
            }
            self?.heldKeys.remove(key)
            return nil
        }

        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.handleHeldKeys()
            }
        }
    }

    private func handleHeldKeys() {
        for key in heldKeys {
            switch key {
            case "a": camera.adjustYaw(-0.8)  // Rotate camera left (counter-clockwise around player)
            case "d": camera.adjustYaw(0.8)   // Rotate camera right (clockwise around player)
            case "w": 
                // W key increases pitch (more top-down view)
                camera.adjustPitch(0.8)
            case "s": 
                // S key decreases pitch (more horizontal view)
                camera.adjustPitch(-0.8)
            case "+", "=": camera.adjustZoom(-0.5)  // Zoom in
            case "-": camera.adjustZoom(0.5)        // Zoom out
            default: continue
            }
        }
    }
    
    // Focus camera on a specific position
    public func focusCameraOnPosition(_ position: SIMD3<Float>) {
        // Update the camera target to look at this position
        target = position
        camera.target = position
        
        // Make sure the view matrix is updated to look at the new target
        camera.updateViewMatrix()
    }
    
    // Increase the camera's far plane to ensure all chunks are visible
    public func extendCameraRange() {
        let aspect = Float(view.bounds.width) / Float(view.bounds.height)
        camera.updatePerspective(
            fovy: radians_from_degrees(65),
            aspect: aspect,
            nearZ: 1.0,
            farZ: 200.0  // Increased far plane distance
        )
        print("Extended camera range to farZ=200.0")
    }
}

