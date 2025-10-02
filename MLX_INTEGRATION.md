# MLX Integration Guide

## Overview

This guide describes how Jarvis uses MLX (Apple's machine learning framework) to run language models directly on Apple Silicon. This replaces the previous Ollama-based approach, providing faster inference and true on-device AI.

## Architecture

### MLXModelManager

The `MLXModelManager` class is the core component that handles:

- **Model Loading**: Downloads and loads Gemma3 models from Hugging Face
- **Tokenization**: Converts text to tokens using the model's tokenizer
- **Inference**: Generates responses using MLX's optimized operations
- **Streaming**: Provides token-by-token streaming for real-time responses

### Key Components

1. **MLX Framework**: Apple's framework for efficient ML on Apple Silicon
2. **MLXLLM**: Language model utilities for loading and running LLMs
3. **MLXLMCommon**: Common utilities for language models
4. **Tokenizers**: Hugging Face tokenizer implementation in Swift

## Model Support

### Supported Models

Jarvis uses Qwen2.5 models from the `mlx-community` organization:

- `mlx-community/Qwen2.5-3B-Instruct-4bit` (default, 4-bit quantized, ~1.9GB)
- `mlx-community/Qwen2.5-1.5B-Instruct-4bit` (4-bit quantized, ~950MB)

These models are optimized for Apple Silicon with minimal quality loss. The Qwen2.5 models provide excellent performance with balanced speed and quality.

### Model Format

Models use the following structure:
- **Config**: `config.json` - Model architecture configuration
- **Weights**: Quantized weights in MLX format
- **Tokenizer**: Tokenizer configuration and vocabulary

## Integration Details

### Loading Models

```swift
let manager = MLXModelManager()
await manager.loadModel(modelName: "mlx-community/Qwen2.5-3B-Instruct-4bit")
```

Models are automatically downloaded from Hugging Face on first use and cached locally in:
```
~/Library/Caches/huggingface/hub/
```

### Generating Text

**Simple Generation:**
```swift
try await manager.generate(
    prompt: "Translate: Hello",
    systemPrompt: "You are a translator",
    temperature: 0.3,
    topP: 0.6,
    maxTokens: 2048
) { token in
    print(token, terminator: "")
}
```

**Chat with History:**
```swift
let messages = [
    ChatMessage(role: .system, content: "You are Jarvis"),
    ChatMessage(role: .user, content: "Hello"),
    ChatMessage(role: .assistant, content: "Hi!"),
    ChatMessage(role: .user, content: "How are you?")
]

try await manager.generateChat(
    messages: messages,
    temperature: 0.6,
    topP: 0.9,
    maxTokens: 2048
) { token in
    print(token, terminator: "")
}
```

### Prompt Formatting

Gemma3 uses specific chat templates:

```
<start_of_turn>system
{system_message}<end_of_turn>
<start_of_turn>user
{user_message}<end_of_turn>
<start_of_turn>model
{assistant_response}<end_of_turn>
```

The `MLXModelManager` handles this formatting automatically.

## Performance Optimization

### Memory Usage

- **4B model**: ~3-4GB RAM during inference
- **1B model**: ~1-2GB RAM during inference

The manager automatically manages memory and can be unloaded when not in use:

```swift
manager.unloadModel()
```

### Inference Speed

On M1 Pro/Max/Ultra and newer:
- **First token**: 50-200ms
- **Subsequent tokens**: 20-50 tokens/second

Performance varies by:
- Chip generation (M1 vs M2 vs M3)
- Available memory
- System load
- Model size

### Quantization

4-bit quantization reduces:
- Model size: ~75% reduction
- Memory usage: ~75% reduction
- Inference speed: Minimal impact on Apple Silicon
- Quality: <5% degradation for most tasks

## Error Handling

The manager provides robust error handling:

```swift
enum MLXError: LocalizedError {
    case modelNotLoaded
    case tokenizationFailed
    case generationFailed(String)
    
    var errorDescription: String? {
        // Human-readable error messages
    }
}
```

## Migration from OllamaKit

### Key Changes

1. **No External Server**: Models run in-process, no Ollama server needed
2. **Model Format**: Uses MLX format instead of GGUF
3. **API Changes**: New Swift-native API instead of REST calls
4. **Streaming**: Direct callback-based streaming instead of AsyncSequence

### Benefits

- **Faster**: Direct GPU acceleration, no network overhead
- **Simpler**: No external dependencies or servers
- **Privacy**: All computation on-device
- **Offline**: Works without internet after initial download
- **Native**: Pure Swift, better integration with macOS

## Dependencies

All dependencies are managed via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", from: "0.14.0")
]
```

This includes:
- MLX (core framework)
- MLXLLM (language model utilities)
- MLXLMCommon (common utilities)
- Tokenizers (tokenization)

## Troubleshooting

### Model Download Issues

**Problem**: Model fails to download

**Solutions**:
- Check internet connection
- Verify Hugging Face is accessible
- Clear cache: `rm -rf ~/Library/Caches/huggingface`
- Check available disk space

### Out of Memory

**Problem**: App crashes or freezes during inference

**Solutions**:
- Use smaller model variant (1B instead of 4B)
- Close other memory-intensive apps
- Restart the app to clear memory
- Increase RAM if possible

### Slow Performance

**Problem**: Generation is slower than expected

**Solutions**:
- Ensure Mac is not in Low Power Mode
- Close background apps
- Check Activity Monitor for CPU/GPU usage
- Try smaller model variant
- Restart the app

### Build Issues

**Problem**: MLX packages fail to build

**Solutions**:
- Update Xcode to latest version
- Clean build folder (Command+Shift+K)
- Delete derived data
- Verify Swift version is 5.9+
- Ensure macOS 14.0+ deployment target

## Future Enhancements

Potential improvements for future versions:

1. **Vision Support**: Add Gemma3 vision models for image understanding
2. **Model Selection**: UI for choosing different models
3. **Custom Models**: Support for user-provided MLX models
4. **LoRA Adapters**: Fine-tuned model variants
5. **Multi-modal**: Audio and image inputs
6. **Quantization Options**: Choose between 4-bit, 8-bit, and fp16

## References

- [MLX Documentation](https://ml-explore.github.io/mlx/build/html/index.html)
- [MLX Swift Examples](https://github.com/ml-explore/mlx-swift-examples)
- [Gemma Models](https://ai.google.dev/gemma)
- [Hugging Face MLX Community](https://huggingface.co/mlx-community)

## Contributing

To contribute to the MLX integration:

1. Test with different model variants
2. Report performance metrics for your hardware
3. Submit issues for bugs or enhancement requests
4. Share custom model configurations

## License

The MLX integration code follows the project's MIT License. Note that:
- MLX is licensed under Apache 2.0
- Gemma models have their own terms of use
- Check individual model licenses on Hugging Face

