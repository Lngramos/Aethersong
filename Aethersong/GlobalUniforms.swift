import simd

public enum GlobalUniforms {
    public static var cameraViewMatrix: matrix_float4x4 =
        matrix_identity_float4x4
    public static var projectionMatrix: matrix_float4x4 =
        matrix_identity_float4x4
}
