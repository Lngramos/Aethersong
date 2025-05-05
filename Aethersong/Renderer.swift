import MetalKit
import simd

protocol RendererDelegate: AnyObject {
    func rendererDidUpdate()
}

@MainActor
public class Renderer: NSObject, MTKViewDelegate {
    weak var delegate: RendererDelegate?

    public static var sharedCameraViewMatrix: matrix_float4x4 {
        get { return GlobalUniforms.cameraViewMatrix }
        set { GlobalUniforms.cameraViewMatrix = newValue }
    }
    
    public static var sharedProjectionMatrix: matrix_float4x4 {
        get { return GlobalUniforms.projectionMatrix }
        set { GlobalUniforms.projectionMatrix = newValue }
    }

    public let device: MTLDevice
    public let terrainRenderer: TerrainRenderer
    public let camera = Camera()
    public let view: MTKView
    private var axisIndicator: AxisIndicator!

    private let entityManager: EntityManager
    private var lastFrameTimestamp: CFTimeInterval = CACurrentMediaTime()

    private let uniformBuffer: MTLBuffer
    private let maxBuffersInFlight = 3
    private var bufferIndex = 0

    private var yaw: Float = .pi / 4
    private var pitch: Float = .pi / 6  // Changed from .pi/4 to .pi/6 for a better initial view
    private var radius: Float = 12
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
        updateCameraView()
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
        updateCameraView()
    }

    public func draw(in view: MTKView) {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastFrameTimestamp
        lastFrameTimestamp = currentTime

        entityManager.updateAll(deltaTime: Float(deltaTime))

        bufferIndex += 1

        let viewMatrix = camera.viewMatrix
        let projectionMatrix = camera.projectionMatrix
        
        // Update global uniforms with current camera matrices
        GlobalUniforms.cameraViewMatrix = viewMatrix
        GlobalUniforms.projectionMatrix = projectionMatrix

        terrainRenderer.updateCamera(
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix
        )

        guard let cmdQ = view.device?.makeCommandQueue(),
            let cmdBuf = cmdQ.makeCommandBuffer(),
            let rpd = view.currentRenderPassDescriptor,
            let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        // Get player position for chunk rendering
        var playerPosition: SIMD3<Float>? = nil
        for entity in entityManager.entities {
            if let player = entity as? PlayerEntity {
                playerPosition = player.position
                break
            }
        }
        
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
        }

        cmdBuf.commit()

        delegate?.rendererDidUpdate()
    }

    private func updateCameraView() {
        let x = target.x + radius * sinf(pitch) * sinf(yaw)
        let y = target.y + radius * cosf(pitch)
        let z = target.z + radius * sinf(pitch) * cosf(yaw)
        let eye = SIMD3<Float>(x, y, z)
        
        // Ensure y is positive to avoid looking from below
        if y < target.y {
            let adjustedPitch = max(0.1, pitch)
            let adjustedY = target.y + radius * sinf(adjustedPitch)
            camera.lookAt(
                eye: SIMD3<Float>(x, adjustedY, z),
                target: target,
                up: SIMD3<Float>(0, 1, 0)
            )
        } else {
            camera.lookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
        }
        
        // Update global uniforms with current camera matrices
        GlobalUniforms.cameraViewMatrix = camera.viewMatrix
        GlobalUniforms.projectionMatrix = camera.projectionMatrix
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
            case "a": yaw -= 0.02
            case "d": yaw += 0.02
            case "s": pitch = min(.pi / 2 - 0.1, pitch + 0.02)  // Inverted: S moves camera up
            case "w": pitch = max(-.pi / 2 + 0.1, pitch - 0.02) // Inverted: W moves camera down
            case "+", "=": radius = max(4, radius - 0.2)
            case "-": radius = min(80, radius + 0.2)
            default: continue
            }
            updateCameraView()
        }
    }
    
    // Focus camera on a specific position
    public func focusCameraOnPosition(_ position: SIMD3<Float>) {
        // Update the camera target to look at this position
        target = position
        
        // Maintain the same camera angle but focus on the new target
        updateCameraView()
        
        print("Camera now focused on position: \(position)")
        print("Camera position: \(camera.position)")
        print("Camera target: \(target)")
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
