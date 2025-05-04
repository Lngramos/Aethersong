import simd

// Helper to build a translation matrix
extension matrix_float4x4 {
    static func makeTranslation(x: Float, y: Float, z: Float) -> matrix_float4x4 {
        var result = matrix_identity_float4x4
        result.columns.3 = SIMD4<Float>(x, y, z, 1.0)
        return result
    }
}
