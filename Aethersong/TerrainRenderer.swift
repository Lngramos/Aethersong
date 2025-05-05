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
    private var highlightedTile: TileCoord? = nil

    // Line thickening resources
    private let lineThickeningPipeline: MTLComputePipelineState
    private var lineRenderTexture: MTLTexture?
    private var lineThickenedTexture: MTLTexture?
    private var compositePipelineState: MTLRenderPipelineState
    private var quadVertexBuffer: MTLBuffer
    private var lineThickness: Float = 5.0
    private var noDepthWriteState: MTLDepthStencilState
    
    public func setHighlightedTile(_ tile: TileCoord) {
        // Check if this is a different tile than the currently highlighted one
        if highlightedTile?.chunk.x != tile.chunk.x || 
           highlightedTile?.chunk.y != tile.chunk.y ||
           highlightedTile?.localX != tile.localX || 
           highlightedTile?.localY != tile.localY {
            
            print("Highlighting tile: Chunk(\(tile.chunk.x), \(tile.chunk.y)) Local(\(tile.localX), \(tile.localY))")
        }
        
        highlightedTile = tile
    }

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
        pd.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        pd.depthAttachmentPixelFormat = .depth32Float_stencil8
        pd.stencilAttachmentPixelFormat = .depth32Float_stencil8

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pd)
        } catch {
            print("ERROR: Failed to create pipeline state: \(error)")
            throw error
        }

        // Setup depth stencil state
        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .less
        dsd.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: dsd)!

        // Setup line thickening compute pipeline
        let computeFunction = library.makeFunction(name: "thickenLines")
        do {
            lineThickeningPipeline = try device.makeComputePipelineState(
                function: computeFunction!
            )
        } catch {
            print("ERROR: Failed to create compute pipeline: \(error)")
            throw error
        }
        
        // Setup composite pipeline for drawing thickened lines
        let compositeDesc = MTLRenderPipelineDescriptor()
        compositeDesc.vertexFunction = library.makeFunction(name: "quadVertexShader")
        compositeDesc.fragmentFunction = library.makeFunction(name: "compositeFragmentShader")
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
    @MainActor
    public func rayFromScreen(screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>)
        -> (origin: SIMD3<Float>, direction: SIMD3<Float>)
    {
        // Convert screen coordinates to normalized device coordinates (NDC)
        // For Metal, (0,0) is top-left of the screen
        // NDC space goes from -1 to 1 in both dimensions
        let ndc = SIMD2<Float>(
            x: (2.0 * screenPoint.x / viewSize.x) - 1.0,
            y: 1.0 - (2.0 * screenPoint.y / viewSize.y)  // Flip Y for Metal's coordinate system
        )
        
        // Create homogeneous clip space coordinates for near and far points
        // Using 0.0 for near plane and 1.0 for far plane in normalized depth
        let clipNear = SIMD4<Float>(ndc.x, ndc.y, 0.0, 1.0)
        let clipFar = SIMD4<Float>(ndc.x, ndc.y, 1.0, 1.0)
        
        // Get the inverse view-projection matrix using GlobalUniforms
        let invViewProj = (GlobalUniforms.projectionMatrix * GlobalUniforms.cameraViewMatrix).inverse
        
        // Transform from clip space to world space
        var worldNear = invViewProj * clipNear
        var worldFar = invViewProj * clipFar
        
        // Perform perspective division to get 3D positions
        worldNear = worldNear / worldNear.w
        worldFar = worldFar / worldFar.w
        
        // Extract the 3D positions
        let rayOrigin = worldNear.xyz
        let rayDirection = simd_normalize(worldFar.xyz - rayOrigin)
        
        return (origin: rayOrigin, direction: rayDirection)
    }
    
    /// Verifies that the matrices used for ray casting match those used for rendering
    @MainActor
    public func verifyMatrices() {
        print("=== MATRIX VERIFICATION ===")
        print("Projection matrix used for rendering:")
        printMatrix(projectionMatrix)
        print("View matrix used for rendering:")
        printMatrix(cameraViewMatrix)
        
        // Compare with the global uniforms matrices
        print("GlobalUniforms camera view matrix:")
        printMatrix(GlobalUniforms.cameraViewMatrix)
        print("GlobalUniforms projection matrix:")
        printMatrix(GlobalUniforms.projectionMatrix)
        print("===========================")
    }

    private func printMatrix(_ matrix: matrix_float4x4) {
        print("[\(matrix.columns.0.x), \(matrix.columns.1.x), \(matrix.columns.2.x), \(matrix.columns.3.x)]")
        print("[\(matrix.columns.0.y), \(matrix.columns.1.y), \(matrix.columns.2.y), \(matrix.columns.3.y)]")
        print("[\(matrix.columns.0.z), \(matrix.columns.1.z), \(matrix.columns.2.z), \(matrix.columns.3.z)]")
        print("[\(matrix.columns.0.w), \(matrix.columns.1.w), \(matrix.columns.2.w), \(matrix.columns.3.w)]")
    }

    /// Draws a grid of terrain chunks centered around the given chunk coordinate
    public func draw(
        encoder: MTLRenderCommandEncoder,
        centerChunk: ChunkCoord,
        playerPosition: SIMD3<Float>? = nil
    ) {
        // Get the current viewport dimensions
        // For high DPI displays, we need to use higher resolution
        // Since we can't directly access the drawable from the encoder,
        // use a reasonable high-resolution default
        let viewportWidth = 1280  // Higher default for 4K/Retina displays
        let viewportHeight = 720
        
        // Update render textures to match viewport size
        updateRenderTextures(width: viewportWidth, height: viewportHeight)

        // If player position is provided, use it to determine which chunks to render
        let renderCenterChunk: ChunkCoord
        if let playerPos = playerPosition {
            let playerChunkX = Int(floor(playerPos.x / Float(Chunk.size)))
            let playerChunkZ = Int(floor(playerPos.z / Float(Chunk.size)))
            renderCenterChunk = ChunkCoord(x: playerChunkX, y: playerChunkZ)
        } else {
            renderCenterChunk = centerChunk
        }

        // First pass: Draw terrain to main render target
        drawTerrainOnly(encoder: encoder, centerChunk: renderCenterChunk)

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

        drawLinesOnly(encoder: lineEncoder, centerChunk: renderCenterChunk)
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
    private func createRenderPassDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        return rpd
    }

    /// Draws only the terrain without lines
    private func drawTerrainOnly(
        encoder: MTLRenderCommandEncoder,
        centerChunk: ChunkCoord
    ) {
        drawTerrainWithMode(
            encoder: encoder,
            centerChunk: centerChunk,
            drawLines: false
        )
    }

    /// Draws only the lines for the terrain
    private func drawLinesOnly(
        encoder: MTLRenderCommandEncoder,
        centerChunk: ChunkCoord
    ) {
        // Create a pipeline state for line rendering
        let pd = MTLRenderPipelineDescriptor()
        pd.vertexFunction = device.makeDefaultLibrary()?.makeFunction(
            name: "terrainVertexShader"
        )
        pd.fragmentFunction = device.makeDefaultLibrary()?.makeFunction(
            name: "terrainLinesFragmentShader"
        )
        pd.vertexDescriptor = vertexDescriptor
        pd.colorAttachments[0].pixelFormat = .rgba8Unorm
        
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

        // Limit the rendering radius to reduce lag
        let radius = 2  // Reduced from 3 to 2 to improve performance
        chunkProvider.updateChunks(around: centerChunk)
        
        for dx in -radius...radius {
            for dy in -radius...radius {
                let coord = ChunkCoord(
                    x: centerChunk.x + dx,
                    y: centerChunk.y + dy
                )
                let chunk = chunkProvider.chunk(at: coord)
                
                // Skip chunks that are too far away (optional optimization)
                let distanceSquared = dx*dx + dy*dy
                if distanceSquared > radius*radius {
                    continue
                }
                
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
                // Fix: Ensure chunks are positioned correctly without gaps
                // Since our mesh now goes from 0 to size (inclusive), we need to position chunks
                // at exact multiples of chunk size
                let tx = Float(coord.x * Chunk.size)
                let ty = Float(coord.y * Chunk.size)
                let modelMatrix = matrix_float4x4.makeTranslation(
                    x: tx,
                    y: 0,
                    z: ty
                )

                // Set uniforms for vertex shader
                var uniforms = TerrainUniforms(
                    modelViewMatrix: cameraViewMatrix * modelMatrix,
                    projectionMatrix: projectionMatrix
                )
                encoder.setVertexBytes(
                    &uniforms,
                    length: MemoryLayout<TerrainUniforms>.stride,
                    index: 2
                )

                // Set fragment shader parameters
                var params = TerrainParams(
                    drawLines: drawLines ? 1 : 0,
                    lineWidth: 0.05,
                    lineColor: SIMD4<Float>(0, 0, 0, 1)
                )
                encoder.setFragmentBytes(
                    &params,
                    length: MemoryLayout<TerrainParams>.stride,
                    index: 0
                )

                // Draw the mesh
                for submesh in mesh.submeshes {
                    // Check if any tile in this chunk is highlighted
                    if let highlightedTile = highlightedTile,
                       highlightedTile.chunk.x == coord.x && 
                       highlightedTile.chunk.y == coord.y {
                        
                        // Set highlighted tile info for fragment shader
                        var highlightInfo = HighlightInfo(
                            isHighlighted: 1,
                            tileX: Int32(highlightedTile.localX),
                            tileY: Int32(highlightedTile.localY),
                            highlightColor: SIMD4<Float>(1, 1, 0, 1)  // Yellow highlight
                        )
                        encoder.setFragmentBytes(
                            &highlightInfo,
                            length: MemoryLayout<HighlightInfo>.stride,
                            index: 1
                        )
                    } else {
                        // No highlight
                        var highlightInfo = HighlightInfo(
                            isHighlighted: 0,
                            tileX: 0,
                            tileY: 0,
                            highlightColor: SIMD4<Float>(0, 0, 0, 0)
                        )
                        encoder.setFragmentBytes(
                            &highlightInfo,
                            length: MemoryLayout<HighlightInfo>.stride,
                            index: 1
                        )
                    }
                    
                    encoder.setVertexBuffer(
                        mesh.vertexBuffers[0].buffer,
                        offset: mesh.vertexBuffers[0].offset,
                        index: 0
                    )
                    encoder.drawIndexedPrimitives(
                        type: .triangle,
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

// MARK: - Shader Structs

struct TerrainUniforms {
    var modelViewMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4
}

struct TerrainParams {
    var drawLines: UInt32
    var lineWidth: Float
    var lineColor: SIMD4<Float>
}

struct HighlightInfo {
    var isHighlighted: UInt32
    var tileX: Int32
    var tileY: Int32
    var highlightColor: SIMD4<Float>
}

extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        return SIMD3<Scalar>(x, y, z)
    }
}
