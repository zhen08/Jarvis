# OllamaKit Integration Guide

## Overview
This guide describes how your Jarvis project has been updated to use OllamaKit instead of direct URLSession calls for Ollama API integration.

## Adding OllamaKit to Your Xcode Project

Since your project uses Xcode (not Swift Package Manager), you need to add OllamaKit through Xcode:

1. Open your `Jarvis.xcodeproj` in Xcode
2. Select the project in the navigator
3. Select the "Jarvis" target
4. Go to the "General" tab
5. Scroll down to "Frameworks, Libraries, and Embedded Content"
6. Click the "+" button
7. Select "Add Package Dependency..."
8. Enter the OllamaKit repository URL: `https://github.com/kevinhermawan/OllamaKit`
9. Click "Add Package"
10. Select "OllamaKit" from the package products
11. Click "Add Package"

## Alternative: Using Swift Package Manager in Xcode

If the above doesn't work, you can also try:

1. In Xcode, go to File → Add Package Dependencies...
2. Enter: `https://github.com/kevinhermawan/OllamaKit`
3. Click "Add Package"
4. Select your target and click "Add Package"

## Key Changes Made to JarvisViewModel.swift

### 1. Replaced URLSession with OllamaKit
- Removed `URLSessionDataDelegate` inheritance
- Replaced `URLSessionDataTask` with Swift Concurrency `Task`
- Removed manual JSON encoding/decoding

### 2. Updated Model Loading
```swift
// Old approach
URLSession.shared.dataTask(with: url) { ... }

// New approach
let modelsResponse = try await ollamaKit.models()
```

### 3. Simplified Message Sending
- Uses OllamaKit's streaming API with async/await
- Separate handling for chat and generate endpoints
- Cleaner error handling with Swift Concurrency

### 4. Improved Stream Processing
- Extracted chunk processing to a separate `processChunk` method
- Better handling of think tags
- More maintainable code structure

## Benefits of Using OllamaKit

1. **Type Safety**: OllamaKit provides strongly-typed request/response models
2. **Async/Await**: Modern Swift concurrency instead of delegates
3. **Streaming Support**: Built-in support for streaming responses
4. **Error Handling**: Better error handling with Swift's error system
5. **Maintainability**: Less boilerplate code to maintain

## Troubleshooting

### Common Errors and Solutions

1. **"Cannot find 'OllamaKit' in scope"**
   - Make sure you've added OllamaKit as a package dependency
   - Try cleaning the build folder (Cmd+Shift+K) and rebuilding
   - Close and reopen Xcode

2. **Type errors with OllamaKit types**
   - The refactored code uses OllamaKit's actual API:
     - `OKChatRequestData` for chat requests
     - `OKGenerateRequestData` for generate requests
     - Messages are passed as `[[String: String]]` dictionaries

3. **"Failed to connect to Ollama"**
   - Ensure Ollama is running locally: `ollama serve`
   - Check that Ollama is accessible at `http://localhost:11434`

## Testing

After adding OllamaKit to your Xcode project:

1. Build and run the application
2. Ensure Ollama is running locally (`ollama serve`)
3. Test all assistant roles (Chat, Translate, Explain, Fix Grammar)
4. Verify streaming responses work correctly
5. Check that think tag processing still works for chat mode

## References

- [OllamaKit Documentation](https://kevinhermawan.github.io/OllamaKit/documentation/ollamakit/)
- [OllamaKit GitHub](https://github.com/kevinhermawan/OllamaKit)
- [Ollamac Source Code](https://github.com/kevinhermawan/Ollamac) (reference implementation) 