import SwiftUI

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Jarvis") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "A native macOS AI assistant powered by Ollama",
                                attributes: [
                                    .foregroundColor: NSColor.textColor
                                ]
                            ),
                            NSApplication.AboutPanelOptionKey.version: ""
                        ]
                    )
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    private var windowDelegate: WindowDelegate?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Chat Assistant")
            button.target = self
            button.action = #selector(toggleWindow)
        }
        
        // Get the window
        if let window = NSApplication.shared.windows.first {
            setupWindow(window)
        }
    }
    
    func setupWindow(_ window: NSWindow) {
        self.window = window
        self.windowDelegate = WindowDelegate()
        window.delegate = windowDelegate
        window.center()
        window.makeKeyAndOrderFront(nil)
        
        // Set minimum window size
        window.minSize = NSSize(width: 800, height: 600)
        
        // Set window appearance
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor.windowBackgroundColor
    }
    
    @objc func toggleWindow() {
        guard let window = window else { return }
        
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            window.orderOut(nil)
        }
    }
} 