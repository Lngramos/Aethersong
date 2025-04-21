// File: Renderer.swift
import MetalKit

@MainActor
public class Renderer: NSObject, MTKViewDelegate {
    private let terrainRenderer: TerrainRenderer
    private let camera = Camera()
    private let uniformBuffer: MTLBuffer
    private let maxBuffersInFlight = 3
    private var bufferIndex = 0

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

        // Initialize terrain renderer
        do {
            terrainRenderer = try TerrainRenderer(
                device: device,
                library: library,
                descriptor: vDesc,
                pixelFormat: view.colorPixelFormat
            )
        } catch {
            fatalError("TerrainRenderer init failed: \(error)")
        }

        super.init()
        view.delegate = self
        // Prime camera with current drawable size
        self.mtkView(view, drawableSizeWillChange: view.drawableSize)
    }

    // MARK: - MTKViewDelegate
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        camera.updatePerspective(
            fovy: radians_from_degrees(65),
            aspect: aspect,
            nearZ: 0.1,
            farZ: 100
        )
        let center = Float(Chunk.size)/2
        camera.lookAt(eye: SIMD3(center, 8, center * 1.5),
                      target: SIMD3(center, 0, center),
                      up: SIMD3(0,1,0))
    }

    public func draw(in view: MTKView) {
        // Cycle uniform buffer
        let idx = bufferIndex % maxBuffersInFlight
        let alignedSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
        let offset = alignedSize * idx
        bufferIndex += 1

        // Update uniform data
        let ptr = uniformBuffer.contents().advanced(by: offset)
            .bindMemory(to: Uniforms.self, capacity: 1)
        ptr.pointee.projectionMatrix = camera.projectionMatrix
        ptr.pointee.modelViewMatrix = camera.viewMatrix

        // Acquire encoder
        guard let cmdQ = view.device?.makeCommandQueue(),
              let cmdBuf = cmdQ.makeCommandBuffer(),
              let rpd = view.currentRenderPassDescriptor,
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            return
        }

        // Draw terrain
        terrainRenderer.draw(
            encoder: encoder,
            uniformsBuffer: uniformBuffer,
            uniformOffset: offset
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
}
