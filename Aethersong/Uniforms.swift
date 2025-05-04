
// ----------------------------------------
// File: Uniforms.swift
import simd

/// Uniform buffer containing model-view and projection matrices
public struct Uniforms {
    public var modelViewMatrix: matrix_float4x4
    public var projectionMatrix: matrix_float4x4
}
