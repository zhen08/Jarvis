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
    private var mainWindow: NSWindow?
    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHotKeyID = EventHotKeyID()
    private var eventHandler: EventHandlerRef?
    @Published private(set) var isModelLoading = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Chat Assistant")
            button.target = self
            button.action = #selector(toggleWindow)
        }
        
        // Register global shortcut (Command + Shift + J)
        registerGlobalShortcut()
        
        // Capture the main window
        DispatchQueue.main.async {
            self.mainWindow = NSApplication.shared.windows.first(where: { $0.isVisible })
        }
    }
    
    @objc func toggleWindow() {
        // Try to find the main window if we don't have it yet
        if mainWindow == nil {
            mainWindow = NSApplication.shared.windows.first(where: { $0.title != "" })
            // If still nil, just take the first window
            if mainWindow == nil {
                mainWindow = NSApplication.shared.windows.first
            }
        }
        
        guard let window = mainWindow else { return }
        
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            window.center()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    // A method that can be called from SwiftUI to set the main window
    func setMainWindow(_ window: NSWindow) {
        self.mainWindow = window
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