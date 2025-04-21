// ----------------------------------------
// File: GameView.swift
import MetalKit

final class GameView: MTKView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Handled via NSEvent monitors; suppress system beep
    }

    override func keyUp(with event: NSEvent) {
        // Handled via NSEvent monitors; suppress system beep
    }
}
