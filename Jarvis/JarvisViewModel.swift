import Foundation
import SwiftUI

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

class JarvisViewModel: NSObject, ObservableObject, URLSessionDataDelegate {
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
    
    private let ollamaBaseURL = "http://localhost:11434"
    private var currentTask: URLSessionDataTask?
    private var responseData = Data()
    private var isProcessingThinkTag = false
    private var isDisplayingThinkingBlock = false
    
    override init() {
        super.init()
        loadAvailableModels()
    }
    
    func clearMessages() {
        messages.removeAll()
    }
    
    func loadAvailableModels() {
        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to connect to Ollama: \(error.localizedDescription)"
                }
                return
            }
            
            guard let data = data else { return }
            
            do {
                let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
                DispatchQueue.main.async {
                    self?.availableModels = response.models.map { $0.name }
                    if ((self?.availableModels.contains(self?.selectedModel ?? "")) == nil) {
                        self?.selectedModel = self?.availableModels.first ?? "qwen3:8b"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse models: \(error.localizedDescription)"
                }
            }
        }.resume()
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
        
        let userMessage = Message(content: content, isUser: true)
        messages.append(userMessage)
        
        isLoading = true
        errorMessage = nil
        responseData = Data()
        isProcessingThinkTag = false
        isDisplayingThinkingBlock = false
        
        var request: URLRequest
        var endpoint: String

        if selectedRole == .chat {
            endpoint = "\(ollamaBaseURL)/api/chat" // Use chat endpoint
            guard let url = URL(string: endpoint) else { return }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Construct messages payload
            var chatMessages: [ChatMessage] = []
            if !selectedRole.systemPrompt.isEmpty {
                 chatMessages.append(ChatMessage(role: "system", content: selectedRole.systemPrompt))
            }
            // Add history, excluding the empty assistant message placeholder
            for message in messages where message.id != messages.last?.id {
                if message.isUser || !message.content.isEmpty {
                    chatMessages.append(ChatMessage(role: message.isUser ? "user" : "assistant", content: message.content))
                }
            }
            // Add current user message
            chatMessages.append(ChatMessage(role: "user", content: content))

            let body = OllamaChatRequest(model: selectedModel, messages: chatMessages, stream: true)
            request.httpBody = try? JSONEncoder().encode(body)

        } else {
            // Keep using /api/generate for non-chat roles
            endpoint = "\(ollamaBaseURL)/api/generate"
            guard let url = URL(string: endpoint) else { return }
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // For non-chat roles, prompt is just the content
            let prompt = content
            let system = selectedRole.systemPrompt
            // Ensure OllamaRequest uses the optional prompt
            let body = OllamaRequest(model: selectedModel, prompt: prompt, system: system, stream: true)
            request.httpBody = try? JSONEncoder().encode(body)
        }

        let assistantMessage = Message(content: "", isUser: false)
        messages.append(assistantMessage) // Append placeholder for assistant response

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        currentTask = session.dataTask(with: request)
        currentTask?.resume()
    }
    
    // URLSessionDataDelegate methods
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let responseString = String(data: data, encoding: .utf8) {
            let lines = responseString.components(separatedBy: .newlines)
            for line in lines {
                if line.isEmpty { continue }
                if let jsonData = line.data(using: .utf8) {
                    
                    var chunk = ""
                    // Try decoding as Chat response first
                    if let chatResponse = try? JSONDecoder().decode(OllamaChatResponse.self, from: jsonData) {
                        chunk = chatResponse.message.content
                    // Fallback to Generate response
                    } else if let generateResponse = try? JSONDecoder().decode(OllamaResponse.self, from: jsonData) {
                         chunk = generateResponse.response
                    } else {
                        // Handle potential decoding errors or unexpected format
                        print("Failed to decode Ollama response line: \(line)")
                        continue
                    }

                    var contentToAppend = ""

                    while !chunk.isEmpty {
                        if isProcessingThinkTag {
                            if let endTagRange = chunk.range(of: "</think>") {
                                let thinkingContent = chunk[..<endTagRange.lowerBound]
                                if isDisplayingThinkingBlock {
                                    contentToAppend += thinkingContent
                                    contentToAppend += "💭"
                                    isDisplayingThinkingBlock = false
                                }
                                isProcessingThinkTag = false
                                chunk = String(chunk[endTagRange.upperBound...])
                            } else {
                                if isDisplayingThinkingBlock {
                                    contentToAppend += chunk
                                }
                                chunk = ""
                            }
                        } else {
                            if let startTagRange = chunk.range(of: "<think>") {
                                contentToAppend += chunk[..<startTagRange.lowerBound]
                                isProcessingThinkTag = true
                                
                                if self.selectedRole == .chat {
                                    isDisplayingThinkingBlock = true
                                    contentToAppend += "💭"
                                }
                                
                                chunk = String(chunk[startTagRange.upperBound...])
                            } else {
                                contentToAppend += chunk
                                chunk = ""
                            }
                        }
                    }

                    if !contentToAppend.isEmpty {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, let lastIndex = self.messages.indices.last, !self.messages.isEmpty, !self.messages[lastIndex].isUser else { return }
                            self.messages[lastIndex].content += contentToAppend
                        }
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.isProcessingThinkTag = false
            self.isDisplayingThinkingBlock = false
            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    self.errorMessage = "Failed to send message: \(error.localizedDescription)"
                    if self.messages.last?.content.isEmpty == true && self.messages.last?.isUser == false {
                        self.messages.removeLast()
                    }
                }
            }
        }
    }
}

// API Response Models
struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable {
    let name: String
}

struct ChatMessage: Codable {
    let role: String // "system", "user", or "assistant"
    let content: String
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

struct OllamaRequest: Codable {
    let model: String
    let prompt: String? // Make prompt optional
    let system: String?
    let stream: Bool
}

struct OllamaResponse: Codable {
    let response: String
}

struct OllamaChatResponse: Codable {
    let model: String
    let created_at: String
    let message: ChatMessage
    let done: Bool
} 
