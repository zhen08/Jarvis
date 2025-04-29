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
            return "You are a helpful AI assistant." 
        case .translate:
            return "Do not reason. You are a translator. If the following word or sentence is in English, translate it into Chinese. If the word or sentence is in Chinese, translate it into English. If the word or sentence has multiple meanings, translate top three most used meanings."
        case .explain:
            return "Explain the meaning of the following word or phrase in simple terms in English."
        case .fixGrammar:
            return "Fix the grammar and improve the writing of the following text. Only provide the corrected version without any additional explanation."
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
    
    override init() {
        super.init()
        loadAvailableModels()
    }
    
    func clearMessages() {
        messages.removeAll()
    }
    
    private func buildPrompt(for content: String) -> String {
        switch selectedRole {
        case .chat:
            // Build chat history for the main prompt field
            var chatHistory = ""
            for message in messages where message.id != messages.last?.id { // Exclude the latest assistant message placeholder
                // Only include user messages and non-empty assistant messages in history
                if message.isUser || !message.content.isEmpty {
                   chatHistory += "\(message.isUser ? "User" : "Assistant"): \(message.content)\n\n"
                }
            }
            // Add the current user message
            chatHistory += "User: \(content)\n\nAssistant:"
            return chatHistory
        default:
            // For non-chat roles, the main prompt is just the user content
            return content
        }
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
        
        guard let url = URL(string: "\(ollamaBaseURL)/api/generate") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = buildPrompt(for: content)
        let system = selectedRole.systemPrompt
        let body = OllamaRequest(model: selectedModel, prompt: prompt, system: system, stream: true)
        request.httpBody = try? JSONEncoder().encode(body)
        
        let assistantMessage = Message(content: "", isUser: false)
        messages.append(assistantMessage)
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        currentTask = session.dataTask(with: request)
        currentTask?.resume()
    }
    
    // URLSessionDataDelegate methods
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Process data received chunk by chunk
        if let responseString = String(data: data, encoding: .utf8) {
            let lines = responseString.components(separatedBy: .newlines)
            for line in lines {
                if line.isEmpty { continue }
                if let jsonData = line.data(using: .utf8),
                   let response = try? JSONDecoder().decode(OllamaResponse.self, from: jsonData) {
                    
                    var chunk = response.response
                    var contentToAppend = ""

                    while !chunk.isEmpty {
                        if isProcessingThinkTag {
                            if let endTagRange = chunk.range(of: "</think>") {
                                isProcessingThinkTag = false
                                chunk = String(chunk[endTagRange.upperBound...])
                            } else {
                                // Entire remaining chunk is within think tags, discard
                                chunk = ""
                            }
                        } else {
                            if let startTagRange = chunk.range(of: "<think>") {
                                contentToAppend += chunk[..<startTagRange.lowerBound]
                                isProcessingThinkTag = true
                                chunk = String(chunk[startTagRange.upperBound...])
                            } else {
                                // No start tag found, append the whole remaining chunk
                                contentToAppend += chunk
                                chunk = ""
                            }
                        }
                    }

                    if !contentToAppend.isEmpty {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, !self.messages.isEmpty else { return }
                            // Assuming formatMarkdown is still desired for the final content
                            let formattedContent = self.formatMarkdown(contentToAppend)
                            self.messages[self.messages.count - 1].content += formattedContent
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

struct OllamaRequest: Codable {
    let model: String
    let prompt: String
    let system: String?
    let stream: Bool
}

struct OllamaResponse: Codable {
    let response: String
} 
