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
            HStack(spacing: 16) {
                    Picker("Model", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .padding(.trailing, 5.0)
                    .frame(width: 200)
                
                    Picker("Role", selection: $viewModel.selectedRole) {
                        ForEach(AssistantRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .padding(.leading, 2.0)
                    .frame(width: 120)
            }
            .padding(0.0)
            .background(Color(.windowBackgroundColor))
            
            // Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding()
                }
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
                HStack(alignment: .bottom, spacing: 8) {
                    CustomTextEditor(text: $messageText, onCommandReturn: {
                        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !message.isEmpty else { return }
                        messageText = ""
                        viewModel.sendMessage(message)
                    })
                    .frame(height: 64)
                    .focused($isEditorFocused)
                    
                    VStack(spacing: 8) {
                        Button(action: {
                            let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !message.isEmpty else { return }
                            messageText = ""
                            viewModel.sendMessage(message)
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                        }
                        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                        
                        Button(action: { viewModel.clearMessages() }) {
                            Image(systemName: "trash.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red)
                        }
                        .help("Clear chat history")
                    }
                }
                .padding()
            }
        }
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
            setupWindowBehavior()
            isEditorFocused = true
        }
    }
    
    private func setupWindowBehavior() {
        if let window = NSApplication.shared.windows.first {
            appDelegate.setupWindow(window)
        }
    }
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
            
            VStack(alignment: message.isUser ? .trailing : .leading) {
                Text(try! AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    .textSelection(.enabled)
                    .padding()
                    .background(message.isUser ? Color.accentColor : Color(.controlBackgroundColor))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(12)
            }
            .frame(maxWidth: 600, alignment: message.isUser ? .trailing : .leading)
            
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
