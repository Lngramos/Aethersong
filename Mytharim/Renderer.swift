import MetalKit

@MainActor
public class Renderer: NSObject, MTKViewDelegate {
    private let terrainRenderer: TerrainRenderer
    private let camera = Camera()
    private let uniformBuffer: MTLBuffer
    private let maxBuffersInFlight = 3
    private var bufferIndex = 0

    // Camera orbit controls
    private var yaw: Float = .pi / 4
    private var pitch: Float = .pi / 4
    private var radius: Float = 12
    private var target = SIMD3<Float>(Float(Chunk.size)/2, 1, Float(Chunk.size)/2)
    private var heldKeys: Set<String> = []

    public init(view: MTKView) {
        // Setup Metal device
        let device: MTLDevice
        if let dev = view.device {
            device = dev
        } else if let sysDev = MTLCreateSystemDefaultDevice() {
            device = sysDev
            view.device = device
        } else {
            fatalError("Metal device not available")
        }

        // Load default library
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Default Metal library not found")
        }

        // Configure MTKView formats
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float_stencil8
        view.clearColor = MTLClearColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1)

        // Create uniform buffer
        let alignedSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
        guard let uBuf = device.makeBuffer(length: alignedSize * maxBuffersInFlight,
                                           options: .storageModeShared) else {
            fatalError("Unable to allocate uniform buffer")
        }
        uniformBuffer = uBuf

        // Build a matching vertex descriptor
        let vDesc = MTLVertexDescriptor()
        vDesc.attributes[0].format = .float3
        vDesc.attributes[0].offset = 0
        vDesc.attributes[0].bufferIndex = 0
        vDesc.attributes[1].format = .float2
        vDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vDesc.attributes[1].bufferIndex = 0
        vDesc.layouts[0].stride = MemoryLayout<Float>.stride * 5

        // Setup chunk provider
        let chunkProvider = FileChunkProvider(basePath: FileManager.default.temporaryDirectory)

        // Initialize terrain renderer with chunk provider
        do {
            terrainRenderer = try TerrainRenderer(
                device: device,
                library: library,
                descriptor: vDesc,
                pixelFormat: view.colorPixelFormat,
                chunkProvider: chunkProvider
            )
        } catch {
            fatalError("TerrainRenderer init failed: \(error)")
        }

        super.init()
        view.delegate = self
        setupKeyboardMonitoring()

        // Ensure MTKView animates
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60

        // Force projection + view setup before first frame
        let aspect = Float(view.bounds.width) / Float(view.bounds.height)
        camera.updatePerspective(fovy: radians_from_degrees(65),
                                 aspect: aspect,
                                 nearZ: 1.0,
                                 farZ: 100.0)
        updateCameraView()
    }

    // MARK: - MTKViewDelegate
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        camera.updatePerspective(fovy: radians_from_degrees(65),
                                 aspect: aspect,
                                 nearZ: 1.0,
                                 farZ: 100.0)
        updateCameraView()
    }

    public func draw(in view: MTKView) {
        // Cycle uniform buffer
        let idx = bufferIndex % maxBuffersInFlight
        let alignedSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
        let offset = alignedSize * idx
        bufferIndex += 1

        // Pass matrices to TerrainRenderer
        terrainRenderer.updateCamera(
            viewMatrix: camera.viewMatrix,
            projectionMatrix: camera.projectionMatrix
        )

        // Acquire encoder
        guard let cmdQ = view.device?.makeCommandQueue(),
              let cmdBuf = cmdQ.makeCommandBuffer(),
              let rpd = view.currentRenderPassDescriptor,
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            return
        }

        // Calculate which chunk the target position is in
        let chunkX = Int(target.x) / Chunk.size
        let chunkY = Int(target.z) / Chunk.size
        let centerChunk = ChunkCoord(x: chunkX, y: chunkY)

        // Compute the player's current chunk
        let playerChunk = ChunkCoord(
            x: Int(target.x) / Chunk.size,
            y: Int(target.z) / Chunk.size
        )
        
        // Draw terrain centered around player
        terrainRenderer.draw(
            encoder: encoder,
            centerChunk: playerChunk
        )

        encoder.endEncoding()
        if let drawable = view.currentDrawable {
            cmdBuf.present(drawable)
        }
        cmdBuf.commit()
    }

    // MARK: - Utilities
    private func radians_from_degrees(_ degrees: Float) -> Float {
        return (degrees / 180) * .pi
    }

    private func updateCameraView() {
        let x = target.x + radius * cosf(pitch) * sinf(yaw)
        let y = target.y + radius * sinf(pitch)
        let z = target.z + radius * cosf(pitch) * cosf(yaw)
        let eye = SIMD3<Float>(x, y, z)
        camera.lookAt(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
    }

    private func setupKeyboardMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let key = event.charactersIgnoringModifiers else { return event }
            self?.heldKeys.insert(key)
            return event
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let key = event.charactersIgnoringModifiers else { return nil }
            self?.heldKeys.remove(key)
            return nil
        } // Prevent event swallowing

        // Set up key repeat manually
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleHeldKeys()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers else { return }
        heldKeys.insert(key)
    }

    private func handleHeldKeys() {
        for key in heldKeys {
            switch key {
            case "a": yaw -= 0.02
            case "d": yaw += 0.02
            case "w": pitch = min(.pi/2 - 0.1, pitch + 0.02)
            case "s": pitch = max(-.pi/2 + 0.1, pitch - 0.02)
            case "+", "=": radius = max(4, radius - 0.2)
            case "-": radius = min(80, radius + 0.2)
            default: continue
            }
        }
        updateCameraView()
    }
}
