// ----------------------------------------
// File: GameView.swift
import MetalKit

protocol GameViewInputDelegate: AnyObject {
    func didClick(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>)
}

final class GameView: MTKView {
    weak public var inputDelegate: GameViewInputDelegate?
    
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Handled via NSEvent monitors; suppress system beep
    }

    override func keyUp(with event: NSEvent) {
        // Handled via NSEvent monitors; suppress system beep
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        let locationInWindow = event.locationInWindow
        let localPoint = convert(locationInWindow, from: nil)

        let screenPoint = SIMD2<Float>(Float(localPoint.x), Float(bounds.height - localPoint.y))
        let viewSize = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))

        inputDelegate?.didClick(at: screenPoint, viewSize: viewSize)
    }
}
