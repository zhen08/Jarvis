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
            You are a translator.
            - If the input is in Chinese, translate it into English.
            - If the input is in English or any other language, translate it into Chinese.
            - When translating a single word, include a brief explanation of the word in both English and Chinese. If a word has multiple common meanings, provide the top three most frequently used translations.
            - When translating a sentence, do not provide any explanations.
            - Do not provide reasoning or any information beyond what is requested.
            - **Strictly format your output to match the examples below, including numbering and placement of explanations.**

            **Output Formatting:**
            - For single words:
                1. Translation 1
                2. Translation 2
                3. Translation 3
                Explanation: [English explanation]
                中文解释: [Chinese explanation]
            - For sentences or longer text:
                [Translated sentence or paragraph only. No explanation.]

            **Examples(strictly follow this format)**

            Example 1
            Input: 你好
            Output:
            1. Hello
            2. Hi
            3. How do you do

            Explanation: A common greeting in Chinese.
            中文解释: 中文里常用的问候语。

            Example 2
            Input: apple
            Output:
            1. 苹果
            2. 苹果公司（Apple Inc.，如有歧义）
            3. 苹果树的果实

            Explanation: A round fruit with red or green skin and a whitish interior.
            中文解释: 一种圆形的水果，外皮为红色或绿色，果肉为白色。

            Example 3
            Input: 针对全球1900家建筑企业进行的一项调查中，91%的企业表示他们在未来10年内将面临产业人员短缺的危机，44%的企业表示目前招工十分困难。
            Output:
            A survey of 1,900 construction companies worldwide found that 91% of them believe they will face a labor shortage crisis in the industry within the next 10 years, and 44% stated that it is currently very difficult to recruit workers.
            
            Example 4
            Input: This Hardware Product Requirements Document (PRD) outlines the specifications for a humanoid robot primarily designed for automating the laying of Autoclaved Aerated Concrete (AAC) blocks on construction sites. The robot is intended to be generalized for a variety of construction tasks in the future, with AAC block laying being the initial application. This document details the essential physical characteristics, performance standards, sensing capabilities, and safety measures required for successful development and deployment. The aim is to provide clear specifications for the Buildroid team and humanoid suppliers, ensuring the robot can efficiently and reliably perform its tasks in the dynamic and challenging construction environment, both for the initial application of AAC block laying and for potential future applications.
            Output: 
            本硬件产品需求文档（PRD）阐述了一款主要用于施工现场自动铺设加气混凝土（AAC）砌块的人形机器人规格。该机器人初期应用为AAC砌块铺设，未来可拓展至多种建筑任务。本文档详细说明了成功开发与部署所需的关键物理特性、性能标准、感知能力和安全措施。其目标是为Buildroid团队及人形机器人供应商提供清晰的技术规范，确保机器人在动态且充满挑战的施工环境中，能够高效、可靠地完成AAC砌块铺设及未来可能拓展的各类任务。
            
            **Your output must always follow the format shown in the relevant example, without adding or omitting any information.**
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
