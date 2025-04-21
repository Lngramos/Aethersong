// File: GameViewController.swift
import Cocoa
import MetalKit

class GameViewController: NSViewController {
    var renderer: Renderer?

    override func viewDidLoad() {
        super.viewDidLoad()
        print("View is a:", type(of: view))
        
        guard let mtkView = self.view as? MTKView else {
            fatalError("View of GameViewController is not an MTKView")
        }
        // Initialize the renderer with the correct argument label
        renderer = Renderer(view: mtkView)
        mtkView.delegate = renderer

        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = 60

    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(view)
    }
}
