// File: GameViewController.swift
import Cocoa
import MetalKit

class GameViewController: NSViewController {
    var renderer: Renderer?

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let mtkView = self.view as? MTKView else {
            fatalError("View of GameViewController is not an MTKView")
        }
        // Initialize the renderer with the correct argument label
        renderer = Renderer(view: mtkView)
        mtkView.delegate = renderer
    }
}
