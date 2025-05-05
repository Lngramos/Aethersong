import simd

/// Uniform buffer containing model-view and projection matrices for entities
public struct EntityUniforms {
    public var modelViewMatrix: matrix_float4x4
    public var projectionMatrix: matrix_float4x4
}
