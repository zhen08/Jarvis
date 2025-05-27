import Foundation
import SwiftUI
import OllamaKit

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
    @Published var availableModels: [String] = []
    @Published var selectedModel: String = "gemma3:4b-it-qat"
    @Published var selectedRole: AssistantRole = .translate {
        didSet {
            if oldValue != selectedRole {
                clearMessages()
                // Set default model based on role
                switch selectedRole {
                case .translate:
                    selectedModel = "gemma3:4b-it-qat"
                default:
                    selectedModel = "qwen3:32b-fp16"
                }
            }
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedImages: [AttachedImage] = []
    
    private let ollamaKit: OllamaKit
    private var streamTask: Task<Void, Never>?
    private var isProcessingThinkTag = false
    private var isDisplayingThinkingBlock = false
    
    init() {
        // Initialize OllamaKit with default localhost URL
        self.ollamaKit = OllamaKit(baseURL: URL(string: "http://localhost:11434")!)
        // Set initial model based on initial role
        switch selectedRole {
        case .translate:
            self.selectedModel = "gemma3:4b-it-qat"
        default:
            self.selectedModel = "qwen3:32b-fp16"
        }
        loadAvailableModels()
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
    
    func loadAvailableModels() {
        Task {
            do {
                let modelsResponse = try await ollamaKit.models()
                await MainActor.run {
                    self.availableModels = modelsResponse.models.map { $0.name }
                    if !self.availableModels.contains(self.selectedModel) {
                        self.selectedModel = self.availableModels.first ?? "gemma3:4b-it-qat"
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load models: \(error.localizedDescription)"
                }
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
                if selectedRole == .chat {
                    // Use chat endpoint for chat role
                    var chatMessages: [OKChatRequestData.Message] = []
                    
                    // Add system message if available
                    if !selectedRole.systemPrompt.isEmpty {
                        chatMessages.append(OKChatRequestData.Message(role: .system, content: selectedRole.systemPrompt))
                    }
                    
                    // Add conversation history (excluding the empty assistant placeholder)
                    for message in messages where message.id != messages.last?.id {
                        if message.isUser || !message.content.isEmpty {
                            let role: OKChatRequestData.Message.Role = message.isUser ? .user : .assistant
                            
                            // For user messages with images, include them in the images field
                            if message.isUser && !message.attachedImages.isEmpty {
                                let imageData = message.attachedImages.map { $0.data.base64EncodedString() }
                                chatMessages.append(OKChatRequestData.Message(
                                    role: role,
                                    content: message.content,
                                    images: imageData
                                ))
                            } else {
                                chatMessages.append(OKChatRequestData.Message(role: role, content: message.content))
                            }
                        }
                    }
                    
                    // Add current user message with images if any
                    if !userMessage.attachedImages.isEmpty {
                        let imageData = userMessage.attachedImages.map { $0.data.base64EncodedString() }
                        chatMessages.append(OKChatRequestData.Message(
                            role: .user,
                            content: content,
                            images: imageData
                        ))
                    } else {
                        chatMessages.append(OKChatRequestData.Message(role: .user, content: content))
                    }
                    
                    var data = OKChatRequestData(
                        model: selectedModel,
                        messages: chatMessages
                    )
                    
                    data.options = OKCompletionOptions(numCtx:32768,temperature:0.6,topP:0.9)

                    for try await response in ollamaKit.chat(data: data) {
                        guard !Task.isCancelled else { break }
                        
                        if let chunk = response.message?.content {
                            await processChunk(chunk)
                        }
                    }
                } else {
                    // Use generate endpoint for non-chat roles
                    var data = OKGenerateRequestData(
                        model: selectedModel,
                        prompt: content
                    )
                    
                    // Set system prompt if available
                    if !selectedRole.systemPrompt.isEmpty {
                        data.system = selectedRole.systemPrompt
                    }

                    data.options = OKCompletionOptions(temperature:0.3,topP:0.6)

                    for try await response in ollamaKit.generate(data: data) {
                        guard !Task.isCancelled else { break }
                        
                        await processChunk(response.response)
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
