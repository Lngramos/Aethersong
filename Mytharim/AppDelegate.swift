import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create your GameViewController
        let viewController = GameViewController()

        // Define the initial window size
        let initialWindowSize = NSRect(x: 0, y: 0, width: 1280, height: 720)

        // Create the window with the specified content rect
        window = NSWindow(
            contentRect: initialWindowSize,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        // Assign the view controller
        window.contentViewController = viewController
        window.title = "Mytharim"

        // Center and show the window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
