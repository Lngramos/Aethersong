import Metal

public enum EntityRenderer {
    private static var pipelineState: MTLRenderPipelineState?
    private static var depthStencilState: MTLDepthStencilState?
    private static var vertexDescriptor: MTLVertexDescriptor?

    public static func apply(to encoder: MTLRenderCommandEncoder) {
        guard let pipeline = pipelineState else { return }
        encoder.setRenderPipelineState(pipeline)
        if let depthStencilState = depthStencilState {
            encoder.setDepthStencilState(depthStencilState)
        }
    }

    public static func buildPipelineState(device: MTLDevice) {
        let library = device.makeDefaultLibrary()!

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(
            name: "entityVertexShader"
        )
        descriptor.fragmentFunction = library.makeFunction(
            name: "entityFragmentShader"
        )
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8

        // Setup correct vertex layout
        let vDesc = MTLVertexDescriptor()
        vDesc.attributes[0].format = .float3
        vDesc.attributes[0].offset = 0
        vDesc.attributes[0].bufferIndex = 0
        vDesc.attributes[1].format = .float2
        vDesc.attributes[1].offset = MemoryLayout<Float>.stride * 3
        vDesc.attributes[1].bufferIndex = 0
        vDesc.layouts[0].stride = MemoryLayout<Float>.stride * 5

        descriptor.vertexDescriptor = vDesc
        vertexDescriptor = vDesc

        pipelineState = try! device.makeRenderPipelineState(
            descriptor: descriptor
        )

        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(
            descriptor: depthStencilDescriptor
        )
    }

}
