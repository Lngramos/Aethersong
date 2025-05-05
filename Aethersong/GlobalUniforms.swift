import simd

/// Global storage for camera matrices that are used across the application
/// This serves as the single source of truth for camera transformation matrices
@MainActor
public enum GlobalUniforms {
    /// The current camera view matrix
    public static var cameraViewMatrix: matrix_float4x4 =
        matrix_identity_float4x4
    
    /// The current projection matrix
    public static var projectionMatrix: matrix_float4x4 =
        matrix_identity_float4x4
}
