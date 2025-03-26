import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var messageText = ""
    @State private var showingError = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Model Selection
            HStack {
                Text("Model:")
                    .foregroundColor(.secondary)
                Picker("Model", selection: $viewModel.selectedModel) {
                    ForEach(viewModel.availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .frame(width: 200)
            }
            .padding()
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
                HStack(spacing: 12) {
                    TextEditor(text: $messageText)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                            .foregroundColor(.accentColor)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
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
    }
    
    private func sendMessage() {
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        
        viewModel.sendMessage(message)
        messageText = ""
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
} 