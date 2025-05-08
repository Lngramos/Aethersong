import simd

public class OrbitCamera {
    // MARK: - Public Properties

    public var target = SIMD3<Float>(0, 0, 0) // What we're orbiting around (player position)
    
    // Pitch in degrees (0 is horizontal, 80 is looking almost straight down)
    private var _pitch: Float = 60.0  // Default 60 degrees (looking down at player)
    public var pitch: Float {
        get { return _pitch }
        set { 
            // Clamp pitch between 20° and 80° as specified
            _pitch = min(80.0, max(20.0, newValue))
            updateViewMatrix()
        }
    }
    
    // Yaw in degrees (0 is behind player, 90 is to the right, etc.)
    private var _yaw: Float = 180.0  // Default to directly in front of player
    public var yaw: Float {
        get { return _yaw }
        set {
            // Keep yaw in the range [0, 360)
            _yaw = fmod(newValue, 360.0)
            if _yaw < 0 { _yaw += 360.0 }
            updateViewMatrix()
        }
    }
    
    // Distance from target (radius)
    private var _radius: Float = 15.0  // Default distance
    public var radius: Float {
        get { return _radius }
        set {
            // Clamp radius between 5 and 50 world units as specified
            _radius = min(50.0, max(5.0, newValue))
            updateViewMatrix()
        }
    }
    
    // MARK: - Private Properties
    
    private var _viewMatrix = matrix_identity_float4x4
    private var _projectionMatrix = matrix_identity_float4x4

    // MARK: - Computed Properties

    public var position: SIMD3<Float> {
        // Convert spherical coordinates to Cartesian
        let pitchRad = degreesToRadians(_pitch)
        let yawRad = degreesToRadians(_yaw)
        
        // Calculate position using spherical coordinates
        // For a top-down view with correct orientation:
        // In this coordinate system:
        // - pitch = 0° means camera is at same height as target (horizontal view)
        // - pitch = 80° means camera is almost directly above target (looking down)
        
        // Calculate camera position:
        // x = target.x + radius * cos(pitch) * sin(yaw)
        // y = target.y + radius * sin(pitch)  // This puts camera above when pitch > 0
        // z = target.z + radius * cos(pitch) * cos(yaw)
        
        let x = target.x + _radius * cos(pitchRad) * sin(yawRad)
        let y = target.y + _radius * sin(pitchRad)  // Higher pitch = higher y position
        let z = target.z + _radius * cos(pitchRad) * cos(yawRad)
        
        return SIMD3<Float>(x, y, z)
    }

    public var viewMatrix: matrix_float4x4 {
        return _viewMatrix
    }
    
    public var projectionMatrix: matrix_float4x4 {
        return _projectionMatrix
    }
    
    // MARK: - Initialization
    
    public init() {
        updateViewMatrix()
    }

    // MARK: - Input Handling

    public func adjustPitch(_ delta: Float) {
        // Adjust pitch in degrees
        pitch = _pitch + delta
    }

    public func adjustYaw(_ delta: Float) {
        // Adjust yaw in degrees - this rotates the camera around the target
        yaw = _yaw + delta
    }

    public func adjustZoom(_ delta: Float) {
        // Adjust radius (zoom)
        radius = _radius + delta
    }
    
    // MARK: - Matrix Updates
    
    public func updateViewMatrix() {
        // Calculate the camera position based on spherical coordinates
        let eye = position
        
        // CRITICAL: Always look at the target (player)
        // This ensures the camera direction updates when orbiting
        _viewMatrix = lookAt(eye: eye, target: target)
    }
    
    public func updatePerspective(fovy: Float, aspect: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovy * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange
        
        _projectionMatrix = matrix_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        )
    }

    // MARK: - Helpers
    
    private func degreesToRadians(_ degrees: Float) -> Float {
        return degrees * Float.pi / 180.0
    }

    // Simplified lookAt function that always uses world up vector
    private func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> matrix_float4x4 {
        let worldUp = SIMD3<Float>(0, 1, 0)
        
        // Calculate the z axis of the camera coordinate system (forward)
        // This is the direction from the eye to the target, normalized
        let forward = normalize(target - eye)
        
        // Calculate the x axis of the camera coordinate system (right)
        // This is the cross product of the forward and up vectors, normalized
        let right = normalize(cross(forward, worldUp))
        
        // Calculate the y axis of the camera coordinate system (up)
        // This is the cross product of the right and forward vectors
        let up = normalize(cross(right, forward))
        
        // Create the view matrix directly
        // This matrix transforms from world space to camera space
        let viewMatrix = matrix_float4x4(
            SIMD4<Float>(right.x, up.x, -forward.x, 0),
            SIMD4<Float>(right.y, up.y, -forward.y, 0),
            SIMD4<Float>(right.z, up.z, -forward.z, 0),
            SIMD4<Float>(-dot(right, eye), -dot(up, eye), dot(forward, eye), 1)
        )
        
        return viewMatrix
    }
}
