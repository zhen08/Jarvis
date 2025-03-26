import Foundation
import SwiftUI

enum AssistantRole: String, CaseIterable {
    case chat = "Chat"
    case translate = "Translate"
    case explain = "Explain"
    
    var prompt: String {
        switch self {
        case .chat:
            return "You are a helpful AI assistant. Please respond to the following conversation:\n\n"
        case .translate:
            return "Translate the following text to Chinese. Only provide the translation without any additional explanation:\n\n"
        case .explain:
            return "Explain the meaning of the following word or phrase in simple terms:\n\n"
        }
    }
}

struct Message: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isUser: Bool
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isUser == rhs.isUser
    }
}

class JarvisViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var availableModels: [String] = []
    @Published var selectedModel: String = "gemma3:12b"
    @Published var selectedRole: AssistantRole = .chat
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let ollamaBaseURL = "http://localhost:11434"
    
    init() {
        loadAvailableModels()
    }
    
    func clearMessages() {
        messages.removeAll()
    }
    
    private func buildPrompt(for content: String) -> String {
        switch selectedRole {
        case .chat:
            // Build chat history
            var chatHistory = selectedRole.prompt
            for message in messages {
                chatHistory += "\(message.isUser ? "User" : "Assistant"): \(message.content)\n\n"
            }
            chatHistory += "User: \(content)\n\nAssistant:"
            return chatHistory
        default:
            return selectedRole.prompt + content
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
                        self?.selectedModel = self?.availableModels.first ?? "gemma3:12b"
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
        
        guard let url = URL(string: "\(ollamaBaseURL)/api/generate") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = buildPrompt(for: content)
        let body = OllamaRequest(model: selectedModel, prompt: prompt, stream: false)
        request.httpBody = try? JSONEncoder().encode(body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Failed to send message: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "No data received"
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
                    let formattedResponse = self?.formatMarkdown(response.response) ?? response.response
                    let assistantMessage = Message(content: formattedResponse, isUser: false)
                    self?.messages.append(assistantMessage)
                } catch {
                    self?.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                }
            }
        }.resume()
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
    let stream: Bool
}

struct OllamaResponse: Codable {
    let response: String
} 
