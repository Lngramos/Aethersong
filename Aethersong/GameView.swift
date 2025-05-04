import MetalKit

protocol GameViewInputDelegate: AnyObject {
    func didMoveMouse(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>)
    func didClick(at screenPoint: SIMD2<Float>, viewSize: SIMD2<Float>)
}

final class GameView: MTKView {
    weak public var inputDelegate: GameViewInputDelegate?

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true

        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        if let scale = window?.screen?.backingScaleFactor, scale > 1.0 {
            print("Scaling view to \(scale)")
            self.layer?.contentsScale = scale
        }
    }

    override func keyDown(with event: NSEvent) {
    }

    override func keyUp(with event: NSEvent) {
    }

    private func screenAndViewSize(for event: NSEvent) -> (
        SIMD2<Float>, SIMD2<Float>
    ) {
        let locationInWindow = event.locationInWindow
        let localPoint = convert(locationInWindow, from: nil)

        let screenPoint = SIMD2<Float>(
            Float(localPoint.x),
            Float(bounds.height - localPoint.y)
        )
        let viewSize = SIMD2<Float>(
            Float(drawableSize.width),
            Float(drawableSize.height)
        )

        return (screenPoint, viewSize)
    }

    override func mouseMoved(with event: NSEvent) {
        let (screenPoint, viewSize) = screenAndViewSize(for: event)
        inputDelegate?.didMoveMouse(at: screenPoint, viewSize: viewSize)
    }

    override func mouseDown(with event: NSEvent) {
        let (screenPoint, viewSize) = screenAndViewSize(for: event)
        inputDelegate?.didClick(at: screenPoint, viewSize: viewSize)
    }
}
