import MetalKit

protocol RendererDelegate: AnyObject {
    func rendererDidRenderFrame()
}

@MainActor
public class Renderer: NSObject, MTKViewDelegate {
    weak var delegate: RendererDelegate?

    public static var sharedCameraViewMatrix: matrix_float4x4 =
        matrix_identity_float4x4
    public static var sharedProjectionMatrix: matrix_float4x4 =
        matrix_identity_float4x4

    public let device: MTLDevice
    public let terrainRenderer: TerrainRenderer
    public let camera = Camera()

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

    public init(
        view: MTKView,
        entityManager: EntityManager,
        chunkProvider: ChunkProvider
    ) {
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
        self.device = device
        self.entityManager = entityManager

        // Load default library
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Default Metal library not found")
        }
        
        print("Available Metal functions:")
        let functions = library.functionNames
        if !functions.isEmpty {
            for function in functions {
                print("  - \(function)")
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

        // Vertex descriptor
        let vDesc = MTLVertexDescriptor()
        vDesc.attributes[0].format = .float3
        vDesc.attributes[0].offset = 0
        vDesc.attributes[0].bufferIndex = 0
        vDesc.attributes[1].format = .float2
        vDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vDesc.attributes[1].bufferIndex = 0
        vDesc.layouts[0].stride = MemoryLayout<Float>.stride * 5

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

        EntityRenderer.buildPipelineState(device: view.device!)

        super.init()
        view.delegate = self
        setupKeyboardMonitoring()

        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60

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

        let target = SIMD3<Float>(
            Float(Chunk.size) / 2,
            1,
            Float(Chunk.size) / 2
        )
        let chunkX = Int(target.x) / Chunk.size
        let chunkY = Int(target.z) / Chunk.size
        let centerChunk = ChunkCoord(x: chunkX, y: chunkY)

        terrainRenderer.draw(encoder: encoder, centerChunk: centerChunk)
        entityManager.drawAll(encoder: encoder)

        encoder.endEncoding()
        if let drawable = view.currentDrawable {
            cmdBuf.present(drawable)
        }
        cmdBuf.commit()
    }

    // MARK: - Private helpers
    private func radians_from_degrees(_ degrees: Float) -> Float {
        return (degrees / 180) * .pi
    }

    private func updateCameraView() {
        let x = target.x + radius * cosf(pitch) * sinf(yaw)
        let y = target.y + radius * sinf(pitch)
        let z = target.z + radius * cosf(pitch) * cosf(yaw)
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
            case "w": pitch = min(.pi / 2 - 0.1, pitch + 0.02)
            case "s": pitch = max(-.pi / 2 + 0.1, pitch - 0.02)
            case "+", "=": radius = max(4, radius - 0.2)
            case "-": radius = min(80, radius + 0.2)
            default: continue
            }
        }
        updateCameraView()
    }

}
