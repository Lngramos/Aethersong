// MARK: - TerrainRenderer Integration with ChunkProvider

import Metal
import MetalKit

/// Responsible for rendering terrain chunks using Metal
public final class TerrainRenderer {
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let device: MTLDevice
    private let vertexDescriptor: MTLVertexDescriptor
    private var meshCache: [ChunkCoord: MTKMesh] = [:]
    private let chunkProvider: ChunkProvider
    private var cameraViewMatrix: matrix_float4x4 = matrix_identity_float4x4
    private var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4

    // Line thickening resources
    private let lineThickeningPipeline: MTLComputePipelineState
    private var lineRenderTexture: MTLTexture?
    private var lineThickenedTexture: MTLTexture?
    private var compositePipelineState: MTLRenderPipelineState
    private var quadVertexBuffer: MTLBuffer
    private var lineThickness: Float = 5.0
    private var noDepthWriteState: MTLDepthStencilState

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        descriptor: MTLVertexDescriptor,
        pixelFormat: MTLPixelFormat,
        chunkProvider: ChunkProvider
    ) throws {
        self.device = device
        self.vertexDescriptor = descriptor
        self.chunkProvider = chunkProvider

        print("Main render target pixel format: \(pixelFormat.rawValue)")
        
        // Setup render pipeline
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = library.makeFunction(name: "terrainVertexShader")
        pd.fragmentFunction = library.makeFunction(
            name: "terrainFragmentShader"
        )
        pd.vertexDescriptor = descriptor
        pd.colorAttachments[0].pixelFormat = pixelFormat

        // Enable alpha blending for transparent contour lines
        pd.colorAttachments[0].isBlendingEnabled = true
        pd.colorAttachments[0].rgbBlendOperation = .add
        pd.colorAttachments[0].alphaBlendOperation = .add
        pd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pd.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pd.colorAttachments[0].destinationAlphaBlendFactor =
            .oneMinusSourceAlpha

        pd.depthAttachmentPixelFormat = .depth32Float_stencil8
        pd.stencilAttachmentPixelFormat = .depth32Float_stencil8
        pipelineState = try device.makeRenderPipelineState(descriptor: pd)

        // Configure depth and stencil testing
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.depthCompareFunction = .less
        dsDesc.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: dsDesc)!

        // Setup line thickening compute pipeline
        guard let lineThickeningFunction = library.makeFunction(name: "lineThickeningKernel") else {
            print("ERROR: Failed to find lineThickeningKernel function in Metal library")
            throw NSError(domain: "TerrainRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create line thickening kernel function"])
        }
        
        do {
            lineThickeningPipeline = try device.makeComputePipelineState(function: lineThickeningFunction)
        } catch {
            print("ERROR: Failed to create compute pipeline state: \(error)")
            throw error
        }
        
        // Setup composite pipeline for rendering the thickened lines back to the screen
        let compositeDesc = MTLRenderPipelineDescriptor()
        
        guard let vertexFunction = library.makeFunction(name: "compositeVertexShader") else {
            print("ERROR: Failed to find compositeVertexShader function in Metal library")
            throw NSError(domain: "TerrainRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to find compositeVertexShader"])
        }
        
        guard let fragmentFunction = library.makeFunction(name: "compositeFragmentShader") else {
            print("ERROR: Failed to find compositeFragmentShader function in Metal library")
            throw NSError(domain: "TerrainRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to find compositeFragmentShader"])
        }
        
        compositeDesc.vertexFunction = vertexFunction
        compositeDesc.fragmentFunction = fragmentFunction
        compositeDesc.colorAttachments[0].pixelFormat = pixelFormat  // Use the same format as the main render target
        
        // Set depth and stencil formats to match the main render target
        compositeDesc.depthAttachmentPixelFormat = .depth32Float_stencil8
        compositeDesc.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        compositeDesc.colorAttachments[0].isBlendingEnabled = true
        compositeDesc.colorAttachments[0].rgbBlendOperation = .add
        compositeDesc.colorAttachments[0].alphaBlendOperation = .add
        compositeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        compositeDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        compositeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        compositeDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        compositeDesc.colorAttachments[0].pixelFormat = pixelFormat
        compositeDesc.colorAttachments[0].isBlendingEnabled = true
        compositeDesc.colorAttachments[0].rgbBlendOperation = .add
        compositeDesc.colorAttachments[0].alphaBlendOperation = .add
        compositeDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        compositeDesc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        compositeDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        compositeDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            compositePipelineState = try device.makeRenderPipelineState(descriptor: compositeDesc)
        } catch {
            print("ERROR: Failed to create composite pipeline state: \(error)")
            throw error
        }

        // Create a simple quad for rendering the thickened lines texture
        let quadVertices: [Float] = [
            -1.0, -1.0, 0.0, 0.0,  // bottom-left
            1.0, -1.0, 1.0, 0.0,  // bottom-right
            -1.0, 1.0, 0.0, 1.0,  // top-left
            1.0, 1.0, 1.0, 1.0,  // top-right
        ]

        quadVertexBuffer = device.makeBuffer(
            bytes: quadVertices,
            length: quadVertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )!
        
        // Create a depth stencil state that doesn't write to the depth buffer
        // This is used for the composite pass to ensure entities render on top
        let noDepthDesc = MTLDepthStencilDescriptor()
        noDepthDesc.depthCompareFunction = .always
        noDepthDesc.isDepthWriteEnabled = false
        noDepthWriteState = device.makeDepthStencilState(descriptor: noDepthDesc)!

        // Initialize textures with default size
        updateRenderTextures(width: 1024, height: 768)
    }

    /// Updates the camera matrices that will be used in the next draw call
    public func updateCamera(
        viewMatrix: matrix_float4x4,
        projectionMatrix: matrix_float4x4
    ) {
        self.cameraViewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
    }

    /// Ensures the render textures are properly sized for the current view
    private func updateRenderTextures(width: Int, height: Int) {
        // Check if we need to create or resize textures
        if lineRenderTexture == nil || lineRenderTexture?.width != width
            || lineRenderTexture?.height != height
        {
            // Use full resolution for high DPI displays
            let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,  // Use RGBA8Unorm consistently
                width: width,  // Use full resolution
                height: height,
                mipmapped: false
            )

            // Texture for initial line rendering
            textureDesc.usage = [.renderTarget, .shaderRead]
            lineRenderTexture = device.makeTexture(descriptor: textureDesc)

            // Texture for thickened lines
            textureDesc.usage = [.shaderWrite, .shaderRead]
            lineThickenedTexture = device.makeTexture(descriptor: textureDesc)
            
            print("Created render textures with format: \(textureDesc.pixelFormat.rawValue), size: \(width)x\(height)")
        }
    }

    /// Converts a screen-space point into a ray in world space
    public func rayFromScreen(screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>)
        -> (origin: SIMD3<Float>, direction: SIMD3<Float>)
    {
        let ndc = SIMD2<Float>(
            x: (2.0 * screenPoint.x / viewSize.x) - 1.0,
            y: 1.0 - (2.0 * screenPoint.y / viewSize.y)
        )

        let invProj = projectionMatrix.inverse
        let invView = cameraViewMatrix.inverse

        let nearPoint = SIMD4<Float>(ndc.x, ndc.y, 0, 1)
        let farPoint = SIMD4<Float>(ndc.x, ndc.y, 1, 1)

        let nearWorld = invView * invProj * nearPoint
        let farWorld = invView * invProj * farPoint

        let rayOrigin = (nearWorld / nearWorld.w).xyz
        let rayTarget = (farWorld / farWorld.w).xyz
        let rayDirection = simd_normalize(rayTarget - rayOrigin)

        return (origin: rayOrigin, direction: rayDirection)
    }

    /// Draws a grid of terrain chunks centered around the given chunk coordinate
    public func draw(
        encoder: MTLRenderCommandEncoder,
        centerChunk: ChunkCoord
    ) {
        // Get the current viewport dimensions
        // For high DPI displays, we need to use higher resolution
        // Since we can't directly access the drawable from the encoder,
        // use a reasonable high-resolution default
        let viewportWidth = 1280  // Higher default for 4K/Retina displays
        let viewportHeight = 720
        
        // Update render textures to match viewport size
        updateRenderTextures(width: viewportWidth, height: viewportHeight)

        // First pass: Draw terrain to main render target
        drawTerrainOnly(encoder: encoder, centerChunk: centerChunk)

        // Skip post-processing if textures aren't ready
        guard let lineRenderTexture = lineRenderTexture,
              let lineThickenedTexture = lineThickenedTexture else {
            print("ERROR: Render textures not initialized")
            return
        }
        
        // We need to get the command buffer from a new command queue
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("ERROR: Failed to create command buffer")
            return
        }

        let lineRenderPassDesc = createRenderPassDescriptor(
            texture: lineRenderTexture
        )

        // Second pass: Draw only lines to our line render texture
        guard let lineEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: lineRenderPassDesc
            ) else {
            print("ERROR: Failed to create line encoder")
            return
        }

        drawLinesOnly(encoder: lineEncoder, centerChunk: centerChunk)
        lineEncoder.endEncoding()

        // Third pass: Apply compute shader to thicken lines
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            print("ERROR: Failed to create compute encoder")
            return
        }

        computeEncoder.setComputePipelineState(lineThickeningPipeline)
        computeEncoder.setTexture(lineRenderTexture, index: 0)
        computeEncoder.setTexture(lineThickenedTexture, index: 1)
        computeEncoder.setBytes(
            &lineThickness,
            length: MemoryLayout<Float>.size,
            index: 0
        )

        // Calculate threadgroup size
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(
            width: (viewportWidth + threadgroupSize.width - 1)
                / threadgroupSize.width,
            height: (viewportHeight + threadgroupSize.height - 1)
                / threadgroupSize.height,
            depth: 1
        )
        
        // Dispatch compute shader
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        
        // Wait for the compute pass to complete
        commandBuffer.commit()
        
        // Wait for completion before compositing
        commandBuffer.waitUntilCompleted()
        
        // Fourth pass: Composite thickened lines back to main render target
        encoder.setRenderPipelineState(compositePipelineState)
        
        // Use the no-depth-write state to ensure entities render on top
        encoder.setDepthStencilState(noDepthWriteState)
        
        encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(lineThickenedTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Creates a render pass descriptor for rendering to a texture
    private func createRenderPassDescriptor(texture: MTLTexture)
        -> MTLRenderPassDescriptor
    {
        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = texture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        
        // Explicitly set no depth or stencil attachment
        renderPassDesc.depthAttachment.texture = nil
        renderPassDesc.stencilAttachment.texture = nil
        
        return renderPassDesc
    }

    /// Draws only the terrain (fill mode) for the given chunks
    private func drawTerrainOnly(
        encoder: MTLRenderCommandEncoder,
        centerChunk: ChunkCoord
    ) {
        drawTerrainWithMode(
            encoder: encoder,
            centerChunk: centerChunk,
            drawLines: false,
            customPipelineState: nil
        )
    }

    /// Draws only the lines (wireframe mode) for the given chunks
    private func drawLinesOnly(
        encoder: MTLRenderCommandEncoder,
        centerChunk: ChunkCoord
    ) {
        // Create a new pipeline state specifically for the line render texture
        // that matches its pixel format (RGBA8Unorm)
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = device.makeDefaultLibrary()?.makeFunction(name: "terrainVertexShader")
        pd.fragmentFunction = device.makeDefaultLibrary()?.makeFunction(name: "terrainFragmentShader")
        pd.vertexDescriptor = vertexDescriptor
        pd.colorAttachments[0].pixelFormat = .rgba8Unorm  // Match the texture format
        
        // Enable alpha blending for transparent contour lines
        pd.colorAttachments[0].isBlendingEnabled = true
        pd.colorAttachments[0].rgbBlendOperation = .add
        pd.colorAttachments[0].alphaBlendOperation = .add
        pd.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pd.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pd.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // For offscreen rendering to our texture, we know there's no depth/stencil
        // No need to check the encoder's renderPassDescriptor as it's not accessible
        
        do {
            let linesPipelineState = try device.makeRenderPipelineState(descriptor: pd)
            
            // Create a depth stencil state with depth testing disabled for offscreen rendering
            let dsDesc = MTLDepthStencilDescriptor()
            dsDesc.depthCompareFunction = .always
            dsDesc.isDepthWriteEnabled = false
            let offscreenDepthState = device.makeDepthStencilState(descriptor: dsDesc)!
            
            drawTerrainWithMode(
                encoder: encoder,
                centerChunk: centerChunk,
                drawLines: true,
                customPipelineState: linesPipelineState,
                customDepthState: offscreenDepthState
            )
        } catch {
            print("ERROR: Failed to create lines pipeline state: \(error)")
        }
    }

    /// Draws terrain with or without lines based on the drawLines parameter
    private func drawTerrainWithMode(
        encoder: MTLRenderCommandEncoder,
        centerChunk: ChunkCoord,
        drawLines: Bool,
        customPipelineState: MTLRenderPipelineState? = nil,
        customDepthState: MTLDepthStencilState? = nil
    ) {
        // Use custom pipeline state if provided, otherwise use default
        if let customState = customPipelineState {
            encoder.setRenderPipelineState(customState)
        } else {
            encoder.setRenderPipelineState(pipelineState)
        }
        
        // Use custom depth state if provided, otherwise use default
        if let customDepth = customDepthState {
            encoder.setDepthStencilState(customDepth)
        } else {
            encoder.setDepthStencilState(depthState)
        }

        let radius = 1
        chunkProvider.updateChunks(around: centerChunk)

        for dx in -radius...radius {
            for dy in -radius...radius {
                let coord = ChunkCoord(
                    x: centerChunk.x + dx,
                    y: centerChunk.y + dy
                )
                let chunk = chunkProvider.chunk(at: coord)

                // Use cached mesh if available, otherwise build and cache
                let mesh: MTKMesh
                if let cached = meshCache[coord] {
                    mesh = cached
                } else {
                    guard
                        let newMesh = try? ChunkMeshBuilder.buildMesh(
                            from: chunk,
                            device: device
                        )
                    else {
                        print(
                            "Failed to build mesh for chunk at (\(coord.x), \(coord.y))"
                        )
                        continue
                    }
                    meshCache[coord] = newMesh
                    mesh = newMesh
                }

                // Translate chunk into world space based on its coordinates
                let tx = Float(coord.x * (Chunk.size - 1))
                let ty = Float(coord.y * (Chunk.size - 1))
                let modelMatrix = matrix_float4x4.makeTranslation(
                    x: tx,
                    y: 0,
                    z: ty
                )

                // Prepare uniforms with transformed view
                var uniforms = Uniforms(
                    modelViewMatrix: matrix_multiply(
                        cameraViewMatrix,
                        modelMatrix
                    ),
                    projectionMatrix: projectionMatrix
                )

                // Bind uniforms and vertex data
                encoder.setVertexBytes(
                    &uniforms,
                    length: MemoryLayout<Uniforms>.stride,
                    index: 2
                )
                encoder.setFragmentBytes(
                    &uniforms,
                    length: MemoryLayout<Uniforms>.stride,
                    index: 2
                )
                encoder.setVertexBuffer(
                    mesh.vertexBuffers[0].buffer,
                    offset: mesh.vertexBuffers[0].offset,
                    index: 0
                )

                // Draw each submesh with solid and wireframe modes
                let baseColors: [SIMD4<Float>] = [
                    SIMD4(0, 1, 0, 1), SIMD4(0, 0, 0, 0.5),
                ]

                // If drawing lines, only draw the wireframe mode
                // If drawing terrain, only draw the fill mode
                let modes: [MTLTriangleFillMode]
                let colorIndices: [Int]

                if drawLines {
                    modes = [.lines]
                    colorIndices = [1]  // Black transparent lines
                } else {
                    modes = [.fill]
                    colorIndices = [0]  // Green terrain
                }

                for i in 0..<modes.count {
                    var color = baseColors[colorIndices[i]]
                    encoder.setTriangleFillMode(modes[i])
                    encoder.setFragmentBytes(
                        &color,
                        length: MemoryLayout<SIMD4<Float>>.stride,
                        index: 3
                    )

                    for submesh in mesh.submeshes {
                        encoder.drawIndexedPrimitives(
                            type: submesh.primitiveType,
                            indexCount: submesh.indexCount,
                            indexType: submesh.indexType,
                            indexBuffer: submesh.indexBuffer.buffer,
                            indexBufferOffset: submesh.indexBuffer.offset
                        )
                    }
                }
            }
        }
    }
}
