import SwiftUI
import Carbon
import Cocoa

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
    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHotKeyID = EventHotKeyID()
    private var eventHandler: EventHandlerRef?
    
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
        
        // Register global shortcut (Command + Shift + J)
        registerGlobalShortcut()
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
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    private func registerGlobalShortcut() {
        // Set up the hot key ID
        eventHotKeyID.signature = OSType("JRVS".utf8.reduce(0, { ($0 << 8) + UInt32($1) }))
        eventHotKeyID.id = 1
        
        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerCallback: EventHandlerUPP = { (_, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            
            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            
            if status == noErr && hotkeyID.id == 1 {
                DispatchQueue.main.async {
                    appDelegate.toggleWindow()
                }
            }
            
            return noErr
        }
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        
        if status != noErr {
            print("Failed to install event handler")
            return
        }
        
        // Register the hot key (Command + Shift + J)
        let commandKey = UInt32(cmdKey)
        let shiftKey = UInt32(shiftKey)
        let jKey = UInt32(kVK_ANSI_J)
        
        let hotkeyStatus = RegisterEventHotKey(jKey, commandKey | shiftKey, eventHotKeyID, GetApplicationEventTarget(), 0, &eventHotKeyRef)
        
        if hotkeyStatus != noErr {
            print("Failed to register global shortcut")
        }
    }
    
    deinit {
        if let eventHotKeyRef = eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
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