import Foundation
import SwiftUI

enum AssistantRole: String, CaseIterable {
    case chat = "General Chat"
    case translate = "Translate"
    case fixGrammar = "Fix Grammar"

    var shortcut: KeyEquivalent {
        switch self {
        case .chat: return "g"
        case .translate: return "t"
        case .fixGrammar: return "f"
        }
    }

    var iconName: String {
        switch self {
        case .chat: return "sparkles"
        case .translate: return "globe"
        case .fixGrammar: return "textformat.abc"
        }
    }

    var systemPrompt: String {
        switch self {
        case .chat:
            return Prompts.chat
        case .translate:
            return Prompts.translate
        case .fixGrammar:
            return Prompts.fixGrammar
        }
    }

    var description: String {
        switch self {
        case .chat:
            return "Have natural conversations, brainstorm ideas, or get quick answers."
        case .translate:
            return "Translate snippets or entire documents to another language instantly."
        case .fixGrammar:
            return "Polish your writing with grammar fixes and tone improvements."
        }
    }

    var quickTips: [String] {
        switch self {
        case .chat:
            return [
                "Attach reference images for visual context",
                "Ask follow-up questions to refine answers",
                "Use Command+Enter to send without leaving the keyboard"
            ]
        case .translate:
            return [
                "Specify the target language for accurate translations",
                "Paste large blocks of text—Jarvis keeps the formatting",
                "Send another message to translate into a different language"
            ]
        case .fixGrammar:
            return [
                "Paste drafts to get grammar and clarity suggestions",
                "Mention the tone you want to achieve (e.g., formal, friendly)",
                "Jarvis keeps your original meaning while polishing the text"
            ]
        }
    }

    var composerPlaceholder: String {
        switch self {
        case .chat:
            return "Ask Jarvis anything or drop images for more context..."
        case .translate:
            return "Paste text you would like translated..."
        case .fixGrammar:
            return "Paste text that needs proofreading or tone adjustments..."
        }
    }
}

struct AttachedImage: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let fileName: String
    
    static func == (lhs: AttachedImage, rhs: AttachedImage) -> Bool {
        lhs.id == rhs.id
    }
}

struct Message: Identifiable, Equatable {
    let id = UUID()
    var content: String
    let isUser: Bool
    var attachedImages: [AttachedImage] = []
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isUser == rhs.isUser && lhs.attachedImages == rhs.attachedImages
    }
}

class JarvisViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var availableModels: [String] = [
        "mlx-community/Qwen2.5-3B-Instruct-4bit",
        "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
    ]
    @Published var selectedModel: String = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    @Published var selectedRole: AssistantRole = .translate {
        didSet {
            if oldValue != selectedRole {
                clearMessages()
            }
        }
    }
    @Published var isLoading = false
    @Published var isLoadingModel = false
    @Published var modelLoadProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var selectedImages: [AttachedImage] = []
    
    private let mlxManager: MLXModelManager
    private var streamTask: Task<Void, Never>?
    private var isProcessingThinkTag = false
    private var isDisplayingThinkingBlock = false
    
    init() {
        self.mlxManager = MLXModelManager()
        // Load the model on initialization
        Task {
            await loadModel()
        }
    }
    
    func clearMessages() {
        messages.removeAll()
        selectedImages.removeAll()
    }
    
    func selectImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.title = "Select Images"
        
        if panel.runModal() == .OK {
            let newImages = panel.urls.compactMap { url -> AttachedImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return AttachedImage(data: data, fileName: url.lastPathComponent)
            }
            selectedImages.append(contentsOf: newImages)
        }
    }
    
    func removeSelectedImage(_ image: AttachedImage) {
        selectedImages.removeAll { $0.id == image.id }
    }

    func clearSelectedImages() {
        selectedImages.removeAll()
    }
    
    func loadModel() async {
        await MainActor.run {
            self.isLoadingModel = true
            self.errorMessage = nil
        }
        
        await mlxManager.loadModel(modelName: selectedModel)
        
        await MainActor.run {
            self.isLoadingModel = false
            if let error = self.mlxManager.errorMessage {
                self.errorMessage = error
            }
        }
    }
    
    private func formatMarkdown(_ text: String) -> String {
        // Ensure code blocks are properly formatted
        var formattedText = text
        
        // Fix code blocks that might be missing language specification
        let codeBlockPattern = "```([^\\n]*\\n[\\s\\S]*?```)"
        let regex = try? NSRegularExpression(pattern: codeBlockPattern)
        let nsRange = NSRange(formattedText.startIndex..<formattedText.endIndex, in: formattedText)
        
        if let matches = regex?.matches(in: formattedText, range: nsRange) {
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: formattedText) {
                    let block = String(formattedText[range])
                    if !block.hasPrefix("```\n") && !block.contains("```swift") {
                        let newBlock = block.replacingOccurrences(of: "```", with: "```swift", options: [], range: block.startIndex..<block.index(block.startIndex, offsetBy: 3))
                        formattedText.replaceSubrange(range, with: newBlock)
                    }
                }
            }
        }
        
        return formattedText
    }
    
    func sendMessage(_ content: String) {
        guard !content.isEmpty else { return }
        
        // Always clear history in translate mode
        if selectedRole == .translate {
            clearMessages()
        }
        
        // Cancel any existing stream task
        streamTask?.cancel()
        
        let userMessage = Message(content: content, isUser: true, attachedImages: selectedImages)
        messages.append(userMessage)
        
        // Note: Image support will need to be added separately for MLX vision models
        if !selectedImages.isEmpty {
            errorMessage = "Note: Image support is not yet implemented with MLX. Images will be ignored."
        }
        
        // Clear selected images after sending
        selectedImages.removeAll()
        
        isLoading = true
        errorMessage = nil
        isProcessingThinkTag = false
        isDisplayingThinkingBlock = false
        
        // Add assistant placeholder message
        let assistantMessage = Message(content: "", isUser: false)
        messages.append(assistantMessage)
        
        streamTask = Task {
            do {
                // Check if model is loaded
                guard mlxManager.isModelLoaded else {
                    await MainActor.run {
                        self.errorMessage = "Model is not loaded. Please wait for the model to load."
                        self.isLoading = false
                        if self.messages.last?.content.isEmpty == true && self.messages.last?.isUser == false {
                            self.messages.removeLast()
                        }
                    }
                    return
                }
                
                if selectedRole == .chat {
                    // Use chat mode with conversation history
                    var chatMessages: [ChatMessage] = []
                    
                    // Add system message if available
                    if !selectedRole.systemPrompt.isEmpty {
                        chatMessages.append(ChatMessage(role: .system, content: selectedRole.systemPrompt))
                    }
                    
                    // Add conversation history (excluding the empty assistant placeholder)
                    for message in messages where message.id != messages.last?.id {
                        if message.isUser {
                            chatMessages.append(ChatMessage(role: .user, content: message.content))
                        } else if !message.content.isEmpty {
                            chatMessages.append(ChatMessage(role: .assistant, content: message.content))
                        }
                    }
                    
                    // Add current user message
                    chatMessages.append(ChatMessage(role: .user, content: content))
                    
                    // Generate with chat history
                    try await mlxManager.generateChat(
                        messages: chatMessages,
                        temperature: 0.6,
                        topP: 0.9,
                        maxTokens: 2048
                    ) { [weak self] token in
                        guard let self = self else { return }
                        Task {
                            await self.processChunk(token)
                        }
                    }
                } else {
                    // Use simple generation for non-chat roles (translate, fix grammar)
                    try await mlxManager.generate(
                        prompt: content,
                        systemPrompt: selectedRole.systemPrompt,
                        temperature: 0.3,
                        topP: 0.6,
                        maxTokens: 2048
                    ) { [weak self] token in
                        guard let self = self else { return }
                        Task {
                            await self.processChunk(token)
                        }
                    }
                }
                
                await MainActor.run {
                    self.isLoading = false
                    self.isProcessingThinkTag = false
                    self.isDisplayingThinkingBlock = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.isProcessingThinkTag = false
                    self.isDisplayingThinkingBlock = false
                    
                    if !(error is CancellationError) {
                        self.errorMessage = "Failed to send message: \(error.localizedDescription)"
                        if self.messages.last?.content.isEmpty == true && self.messages.last?.isUser == false {
                            self.messages.removeLast()
                        }
                    }
                }
            }
        }
    }
    
    private func processChunk(_ chunk: String) async {
        var remainingChunk = chunk
        var contentToAppend = ""
        
        while !remainingChunk.isEmpty {
            if isProcessingThinkTag {
                if let endTagRange = remainingChunk.range(of: "</think>") {
                    let thinkingContent = remainingChunk[..<endTagRange.lowerBound]
                    if isDisplayingThinkingBlock {
                        contentToAppend += thinkingContent
                        contentToAppend += "💭"
                        isDisplayingThinkingBlock = false
                    }
                    isProcessingThinkTag = false
                    remainingChunk = String(remainingChunk[endTagRange.upperBound...])
                } else {
                    if isDisplayingThinkingBlock {
                        contentToAppend += remainingChunk
                    }
                    remainingChunk = ""
                }
            } else {
                if let startTagRange = remainingChunk.range(of: "<think>") {
                    contentToAppend += remainingChunk[..<startTagRange.lowerBound]
                    isProcessingThinkTag = true
                    
                    if self.selectedRole == .chat {
                        isDisplayingThinkingBlock = true
                        contentToAppend += "💭"
                    }
                    
                    remainingChunk = String(remainingChunk[startTagRange.upperBound...])
                } else {
                    contentToAppend += remainingChunk
                    remainingChunk = ""
                }
            }
        }
        
        if !contentToAppend.isEmpty {
            let finalContent = contentToAppend
            await MainActor.run {
                guard let lastIndex = self.messages.indices.last,
                      !self.messages.isEmpty,
                      !self.messages[lastIndex].isUser else { return }
                self.messages[lastIndex].content += finalContent
            }
        }
    }
} 
