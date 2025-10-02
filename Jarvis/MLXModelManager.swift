import Foundation
import MLXLMCommon

/// Manages MLX model loading and inference for language models
class MLXModelManager: ObservableObject {
    @Published var isModelLoaded = false
    @Published var loadingProgress: Double = 0.0
    @Published var errorMessage: String?
    
    private var model: ModelContext?
    private var chatSession: ChatSession?
    
    // Default model path - can be customized
    // Using Qwen2.5 as it's well-tested and reliable
    private let defaultModelName = "mlx-community/Qwen2.5-3B-Instruct-4bit"
    
    init() {}
    
    /// Load a language model from Hugging Face
    func loadModel(modelName: String? = nil) async {
        await MainActor.run {
            self.isModelLoaded = false
            self.loadingProgress = 0.0
            self.errorMessage = nil
        }
        
        do {
            let name = modelName ?? defaultModelName
            
            await MainActor.run {
                self.loadingProgress = 0.3
            }
            
            // Load the model using MLXLMCommon's loadModel
            let loadedModel = try await MLXLMCommon.loadModel(id: name)
            
            await MainActor.run {
                self.model = loadedModel
                self.chatSession = ChatSession(loadedModel)
                self.loadingProgress = 1.0
                self.isModelLoaded = true
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load model: \(error.localizedDescription)"
                self.isModelLoaded = false
            }
        }
    }
    
    /// Generate text using the loaded model with streaming (for simple prompts)
    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        temperature: Float = 0.6,
        topP: Float = 0.9,
        maxTokens: Int = 2048,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let model = model else {
            throw MLXError.modelNotLoaded
        }
        
        // Create a new session for simple generation
        let session = ChatSession(model)
        
        // If there's a system prompt, add it first
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            // Create a custom conversation starting with system message
            // For now, we'll prepend it to the prompt
            let fullPrompt = "\(systemPrompt)\n\nUser: \(prompt)\nAssistant:"
            
            for try await token in session.streamResponse(to: fullPrompt) {
                onToken(token)
            }
        } else {
            // Stream the response
            for try await token in session.streamResponse(to: prompt) {
                onToken(token)
            }
        }
    }
    
    /// Generate text for multi-turn chat with history
    func generateChat(
        messages: [ChatMessage],
        temperature: Float = 0.6,
        topP: Float = 0.9,
        maxTokens: Int = 2048,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard let chatSession = chatSession else {
            throw MLXError.modelNotLoaded
        }
        
        // Get the latest user message
        guard let lastMessage = messages.last, lastMessage.role == .user else {
            throw MLXError.generationFailed("No user message found")
        }
        
        // Stream the response using the existing chat session (maintains context)
        for try await token in chatSession.streamResponse(to: lastMessage.content) {
            onToken(token)
        }
    }
    
    /// Unload the model to free memory
    func unloadModel() {
        model = nil
        chatSession = nil
        isModelLoaded = false
        loadingProgress = 0.0
    }
}

// MARK: - Supporting Types

enum MLXError: LocalizedError {
    case modelNotLoaded
    case tokenizationFailed
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model is not loaded. Please load the model first."
        case .tokenizationFailed:
            return "Failed to tokenize the input text."
        case .generationFailed(let message):
            return "Text generation failed: \(message)"
        }
    }
}

struct ChatMessage {
    enum Role {
        case system
        case user
        case assistant
    }
    
    let role: Role
    let content: String
}

