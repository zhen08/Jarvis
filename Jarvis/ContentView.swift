import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = JarvisViewModel()
    @EnvironmentObject private var appDelegate: AppDelegate
    @State private var messageText = ""
    @State private var showingError = false
    @FocusState private var isEditorFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Model and Role Selection
            HStack(spacing: 20.0) {
                Picker("Model", selection: $viewModel.selectedModel) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .frame(width: 250)
                
                Picker("Role", selection: $viewModel.selectedRole) {
                    ForEach(AssistantRole.allCases, id: \.self) { role in
                        Text(role.rawValue)
                            .tag(role)
                            .keyboardShortcut(role.shortcut, modifiers: .command)
                    }
                }
                .frame(width: 150)
            }
            .padding(2.0)
            .background(Color(.windowBackgroundColor))
            
            // Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .background(Color(.textBackgroundColor))
                .onChange(of: viewModel.messages) { messages, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area
            VStack(spacing: 0) {
                Divider()
                
                // Selected Images Preview (only show in chat mode when images are selected)
                if viewModel.selectedRole == .chat && !viewModel.selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.selectedImages) { image in
                                SelectedImageView(image: image) {
                                    viewModel.removeSelectedImage(image)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.controlBackgroundColor))
                    Divider()
                }
                
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(spacing: 0) {
                        CustomTextEditor(text: $messageText, onCommandReturn: {
                            let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !message.isEmpty else { return }
                            messageText = ""
                            viewModel.sendMessage(message)
                        })
                        .padding(0.0)
                        .frame(height: 80)
                        .focused($isEditorFocused)
                        
                        // Image attachment button (only show in chat mode)
                        if viewModel.selectedRole == .chat {
                            HStack {
                                Button(action: {
                                    viewModel.selectImages()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo")
                                        Text("Attach Images")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                                
                                Spacer()
                            }
                        }
                    }
                    
                    VStack(spacing: 12) {
                        Button(action: {
                            let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !message.isEmpty else { return }
                            messageText = ""
                            viewModel.sendMessage(message)
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                        
                        Button(action: { viewModel.clearMessages() }) {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.red)
                        }
                        .help("Clear chat history")
                    }
                }
                .padding(10.0)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onChange(of: viewModel.errorMessage) { _, error in
            showingError = error != nil
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            isEditorFocused = true
        }
        .background(WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor.windowBackgroundColor
            window.center()
            appDelegate.setMainWindow(window)
        })
    }
}

struct SelectedImageView: View {
    let image: AttachedImage
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let nsImage = NSImage(data: image.data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -5)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onCommandReturn: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = CustomNSTextView(frame: .zero)
        textView.customDelegate = context.coordinator
        
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.allowsUndo = true
        
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.frame.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: text.count, length: 0))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        
        init(_ parent: CustomTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
            }
        }
    }
}

class CustomNSTextView: NSTextView {
    weak var customDelegate: CustomTextEditor.Coordinator?
    
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.keyCode == 36 { // 36 is Return key
            customDelegate?.parent.onCommandReturn()
            return
        }
        super.keyDown(with: event)
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 12) {
                // Display attached images if any
                if !message.attachedImages.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(3, message.attachedImages.count)), spacing: 8) {
                        ForEach(message.attachedImages) { attachedImage in
                            if let nsImage = NSImage(data: attachedImage.data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 200, maxHeight: 200)
                                    .cornerRadius(12)
                                    .clipped()
                            }
                        }
                    }
                }
                
                // Display text content if not empty
                if !message.content.isEmpty {
                    Text(try! AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                        .textSelection(.enabled)
                        .padding(16)
                        .background(message.isUser ? Color.accentColor : Color(.controlBackgroundColor))
                        .foregroundColor(message.isUser ? .white : .primary)
                        .cornerRadius(16)
                }
            }
            .frame(maxWidth: 700, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppDelegate())
} 
