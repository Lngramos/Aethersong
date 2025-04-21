// ----------------------------------------
// File: Camera.swift
import simd

public class Camera {
    public var projectionMatrix = matrix_identity_float4x4
    public var viewMatrix = matrix_identity_float4x4

    public func updatePerspective(fovy: Float, aspect: Float, nearZ: Float, farZ: Float) {
        let ys = 1 / tanf(fovy * 0.5)
        let xs = ys / aspect
        let zs = farZ / (nearZ - farZ)
        projectionMatrix = matrix_float4x4(columns: (
            SIMD4(xs, 0,  0,   0),
            SIMD4(0,  ys, 0,   0),
            SIMD4(0,  0,  zs, -1),
            SIMD4(0,  0, zs*nearZ, 0)
        ))
    }

    public func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)
        viewMatrix = matrix_float4x4(columns: (
            SIMD4(x.x, y.x, z.x, 0),
            SIMD4(x.y, y.y, z.y, 0),
            SIMD4(x.z, y.z, z.z, 0),
            SIMD4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }
}
