import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = JarvisViewModel()
    @EnvironmentObject private var appDelegate: AppDelegate
    @State private var messageText = ""
    @State private var showingError = false
    @FocusState private var isEditorFocused: Bool
    
    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                chatMessages
                inputArea
            }
            .background(
                LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.12), Color.gray.opacity(0.22)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
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

    private var trimmedMessage: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSendDisabled: Bool {
        trimmedMessage.isEmpty || viewModel.isLoading
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isLoadingModel ? Color.blue : (viewModel.isLoading ? Color.orange : Color.green))
                .frame(width: 8, height: 8)
            Text(viewModel.isLoadingModel ? "Loading Model" : (viewModel.isLoading ? "Thinking" : "Ready"))
                .font(.caption.weight(.semibold))
            if viewModel.isLoading || viewModel.isLoadingModel {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoadingModel)
        .accessibilityLabel(viewModel.isLoadingModel ? "Model is loading" : (viewModel.isLoading ? "Jarvis is thinking" : "Jarvis is ready"))
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Jarvis")
                        .font(.title3.weight(.semibold))
                    Text("Your MLX-powered copilot")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusBadge
            }

            HStack(alignment: .center, spacing: 16) {
                Picker("Model", selection: $viewModel.selectedModel) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .frame(width: 260)
                .font(.headline)

                Picker("Role", selection: $viewModel.selectedRole) {
                    ForEach(AssistantRole.allCases, id: \.self) { role in
                        Text(role.rawValue)
                            .tag(role)
                            .keyboardShortcut(role.shortcut, modifiers: .command)
                    }
                }
                .frame(width: 170)
                .font(.headline)

                Spacer()

                // Cache management section
                Menu {
                    Button(action: {
                        viewModel.chooseDownloadDirectory()
                    }) {
                        Label("Change Download Location...", systemImage: "folder")
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        viewModel.showingClearCacheConfirmation = true
                    }) {
                        Label("Clear Cache (\(viewModel.cacheSize))", systemImage: "trash")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "externaldrive.fill")
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Model Cache")
                                .font(.caption2.weight(.semibold))
                            Text(viewModel.cacheSize)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .help("Manage model downloads and cache")
                .confirmationDialog(
                    "Clear Model Cache",
                    isPresented: $viewModel.showingClearCacheConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear Cache (\(viewModel.cacheSize))", role: .destructive) {
                        viewModel.clearModelCache()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete all downloaded models from \(viewModel.modelDownloadPath). The app will re-download models when needed.")
                }

                Text(viewModel.selectedRole.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                    .accessibilityLabel("Role description")
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(BlurView(style: .contentBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color.clear)
            .overlay {
                if viewModel.messages.isEmpty {
                    EmptyStateView(role: viewModel.selectedRole)
                        .padding(.horizontal, 48)
                        .padding(.vertical, 60)
                }
            }
            .onChange(of: viewModel.messages) { messages, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
            imagePreview
            HStack(alignment: .bottom, spacing: 12) {
                textEditorAndAttachButton
                sendAndClearButtons
            }
            .padding(10.0)
            .background(BlurView(style: .contentBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func sendMessage() {
        let message = trimmedMessage
        guard !message.isEmpty, !viewModel.isLoading else { return }
        messageText = ""
        viewModel.sendMessage(message)
    }

    private var imagePreview: some View {
        Group {
            if viewModel.selectedRole == .chat && !viewModel.selectedImages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            "\(viewModel.selectedImages.count) \(viewModel.selectedImages.count == 1 ? "Attachment" : "Attachments")",
                            systemImage: "photo.on.rectangle"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                        Spacer()

                        Button("Clear All") {
                            viewModel.clearSelectedImages()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }

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
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Divider()
                    .padding(.top, 12)
            }
        }
    }

    private var textEditorAndAttachButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                CustomTextEditor(text: $messageText, onCommandReturn: {
                    sendMessage()
                })
                .padding(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
                .frame(minHeight: 100, maxHeight: 160, alignment: .topLeading)
                .focused($isEditorFocused)

                if trimmedMessage.isEmpty {
                    Text(viewModel.selectedRole.composerPlaceholder)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isEditorFocused ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
            .animation(.easeInOut(duration: 0.2), value: isEditorFocused)

            if viewModel.selectedRole == .chat {
                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.selectImages()
                    }) {
                        Label("Attach Images", systemImage: "paperclip")
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Attach images")
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    private var sendAndClearButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                sendMessage()
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 52, height: 52)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 4)

                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isSendDisabled)
            .accessibilityLabel(viewModel.isLoading ? "Sending disabled while Jarvis is thinking" : "Send message")

            Button(action: {
                viewModel.clearMessages()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 42, height: 42)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Clear chat history")
            .accessibilityLabel("Clear chat history")
        }
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
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 12)
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

struct EmptyStateView: View {
    let role: AssistantRole

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: role.iconName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(Color.accentColor)
            }

            Text("Start a conversation")
                .font(.title3.weight(.semibold))

            Text(role.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(role.quickTips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.accentColor)
                        Text(tip)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(maxWidth: 420)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 12)
        .padding()
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

    override func paste(_ sender: Any?) {
        if let pasteboardString = NSPasteboard.general.string(forType: .string) {
            self.insertText(pasteboardString, replacementRange: self.selectedRange())
        }
        // Do not call super.paste to prevent rich text or other formats from being pasted
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
                senderLabel

                if !message.attachedImages.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(3, message.attachedImages.count)), spacing: 8) {
                        ForEach(message.attachedImages) { attachedImage in
                            if let nsImage = NSImage(data: attachedImage.data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 200, maxHeight: 200)
                                    .cornerRadius(18)
                                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                                    .clipped()
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                if !message.content.isEmpty {
                    Text(try! AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                        .textSelection(.enabled)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    message.isUser ?
                                        LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                        LinearGradient(colors: [Color(NSColor.windowBackgroundColor).opacity(0.95), Color(NSColor.windowBackgroundColor).opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(message.isUser ? Color.white.opacity(0.2) : Color.primary.opacity(0.05), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(message.isUser ? 0.25 : 0.10), radius: 10, x: 0, y: 4)
                        .foregroundColor(message.isUser ? .white : .primary)
                }
            }
            .frame(maxWidth: 700, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer()
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var senderLabel: some View {
        HStack(spacing: 6) {
            if message.isUser {
                Spacer(minLength: 0)
                Text("You")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Image(systemName: "person.fill")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "sparkles")
                    .foregroundColor(Color.accentColor)
                Text("Jarvis")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppDelegate())
}

struct BlurView: NSViewRepresentable {
    var style: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = style
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
} 
