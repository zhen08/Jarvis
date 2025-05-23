import Foundation
import SwiftUI
import OllamaKit

enum AssistantRole: String, CaseIterable {
    case chat = "General Chat"
    case translate = "Translate"
    case explain = "Explain"
    case fixGrammar = "Fix Grammar"
    
    var shortcut: KeyEquivalent {
        switch self {
        case .chat: return "g"
        case .translate: return "t"
        case .explain: return "e"
        case .fixGrammar: return "f"
        }
    }
    
    var systemPrompt: String {
        switch self {
        case .chat:
            // Using an empty system prompt for chat for now, 
            // history is managed in the main prompt.
            // Alternatively, provide a base persona here.
            return """
            You are Jarvis, a helpful AI assistant. You are a highly capable, thoughtful, and precise assistant. 
            Your goal is to deeply understand the user's intent, ask clarifying questions when needed, think 
            step-by-step through complex problems, provide clear and accurate answers, and proactively 
            anticipate helpful follow-up information. Always prioritize being truthful, nuanced, insightful, 
            and efficient, tailoring your responses specifically to the user's needs and preferences.
            """
        case .translate:
            return """
            You are a translator. If the following word or sentence is in English, translate it into Chinese. 
            If the word or sentence is in Chinese, translate it into English. If the word or sentence has multiple meanings, 
            translate top three most used meanings.
            Do not reason. Do not provide any additional information.
            """
        case .explain:
            return """
            Explain the meaning of the following word or phrase in simple terms and use simple words in English. 
            Do not reason. Do not provide any additional information.
            """
        case .fixGrammar:
            return """
            You are a proofreader. Fix the grammar and improve the writing of the following text. 
            Only provide the corrected version without any additional explanation.
            Do not reason. Do not provide any additional information.
            """
        }
    }
}

struct Message: Identifiable, Equatable {
    let id = UUID()
    var content: String
    let isUser: Bool
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isUser == rhs.isUser
    }
}

class JarvisViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var availableModels: [String] = []
    @Published var selectedModel: String = "qwen3:8b"
    @Published var selectedRole: AssistantRole = .translate {
        didSet {
            if oldValue != selectedRole {
                clearMessages()
            }
        }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let ollamaKit: OllamaKit
    private var streamTask: Task<Void, Never>?
    private var isProcessingThinkTag = false
    private var isDisplayingThinkingBlock = false
    
    init() {
        // Initialize OllamaKit with default localhost URL
        self.ollamaKit = OllamaKit(baseURL: URL(string: "http://localhost:11434")!)
        loadAvailableModels()
    }
    
    func clearMessages() {
        messages.removeAll()
    }
    
    func loadAvailableModels() {
        Task {
            do {
                let modelsResponse = try await ollamaKit.models()
                await MainActor.run {
                    self.availableModels = modelsResponse.models.map { $0.name }
                    if !self.availableModels.contains(self.selectedModel) {
                        self.selectedModel = self.availableModels.first ?? "qwen3:8b"
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
        
        // Cancel any existing stream task
        streamTask?.cancel()
        
        let userMessage = Message(content: content, isUser: true)
        messages.append(userMessage)
        
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
                            chatMessages.append(OKChatRequestData.Message(role: role, content: message.content))
                        }
                    }
                    
                    // Add current user message
                    chatMessages.append(OKChatRequestData.Message(role: .user, content: content))
                    
                    let data = OKChatRequestData(
                        model: selectedModel,
                        messages: chatMessages
                    )
                    
                    for try await response in ollamaKit.chat(data: data) {
                        guard !Task.isCancelled else { break }
                        
                        if let chunk = response.message?.content {
                            await processChunk(chunk)
                        }
                    }
                } else {
                    // Use generate endpoint for non-chat roles
                    // Combine system prompt with user content for non-chat roles
                    let fullPrompt = selectedRole.systemPrompt.isEmpty ? content : "\(selectedRole.systemPrompt)\n\n\(content)"
                    
                    let data = OKGenerateRequestData(
                        model: selectedModel,
                        prompt: fullPrompt
                    )
                    
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
