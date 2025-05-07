import simd

public class Camera {
    public private(set) var position = SIMD3<Float>(0, 0, 0)
    public private(set) var viewMatrix = matrix_identity_float4x4
    public private(set) var projectionMatrix = matrix_identity_float4x4
    
    public func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        position = eye
        
        // Calculate the forward vector (z-axis)
        let z = normalize(eye - target)
        
        // Calculate the right vector (x-axis)
        // If we're looking almost straight up or down, the cross product can become unstable
        // causing flickering. We need to handle this special case.
        let upDotZ = dot(up, z)
        
        // If the up vector and forward vector are nearly parallel (looking straight up/down)
        if abs(upDotZ) > 0.99 {
            // Use a fixed right vector to avoid instability
            // This prevents the camera from flipping at extreme angles
            let fixedRight = normalize(SIMD3<Float>(1, 0, 0))
            let x = fixedRight
            let y = normalize(cross(z, x))
            
            viewMatrix = matrix_float4x4(
                SIMD4<Float>(x.x, y.x, z.x, 0),
                SIMD4<Float>(x.y, y.y, z.y, 0),
                SIMD4<Float>(x.z, y.z, z.z, 0),
                SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
            )
        } else {
            // Normal case - calculate the right vector from the cross product
            let x = normalize(cross(up, z))
            let y = cross(z, x)
            
            viewMatrix = matrix_float4x4(
                SIMD4<Float>(x.x, y.x, z.x, 0),
                SIMD4<Float>(x.y, y.y, z.y, 0),
                SIMD4<Float>(x.z, y.z, z.z, 0),
                SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
            )
        }
    }
    
    public func updatePerspective(fovy: Float, aspect: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovy * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange
        
        projectionMatrix = matrix_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        )
    }
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
