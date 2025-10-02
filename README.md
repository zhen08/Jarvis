# Jarvis

A native macOS AI assistant powered by MLX. Jarvis runs language models directly on your Apple Silicon Mac using Apple's MLX framework for fast, on-device AI inference.

## Features

- **Native macOS app** with SwiftUI interface
- **On-device AI** powered by MLX - no external server needed
- **Qwen2.5 models** - Choose between 3B and 1.5B variants
- **Real-time streaming** responses with low latency
- **Markdown rendering** support
- **Menu bar quick access** (Command+Shift+J)
- **Multiple assistant roles** for different tasks:
  - General Chat
  - Translation
  - Grammar Fixing
- **Command+Enter** shortcut for sending messages
- **Privacy-first** - all processing happens on your device

## Requirements

- **macOS 14.0** or later
- **Apple Silicon** (M1/M2/M3 or newer)
- **8GB RAM minimum** (16GB recommended for 4B model)
- **~5GB free disk space** for model files

## Installation

1. Download the latest release
2. Move Jarvis.app to your Applications folder
3. Launch Jarvis
4. The app will automatically download and load the model on first launch (~1.9GB)

## Models

Jarvis uses Qwen2.5 models optimized for Apple Silicon:

- `mlx-community/Qwen2.5-3B-Instruct-4bit` (default, ~1.9GB, recommended)
- `mlx-community/Qwen2.5-1.5B-Instruct-4bit` (faster, ~950MB)

Models are automatically downloaded from Hugging Face on first use. You can switch between models using the dropdown in the app.

## Development

### Prerequisites

- Xcode 15.0 or later
- Swift 5.9 or later
- MLX Swift package (automatically managed by SPM)

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/Jarvis.git
   cd Jarvis
   ```

2. Open Jarvis.xcodeproj in Xcode

3. Build and run the project (Command+R)

### Architecture

- **MLXModelManager**: Handles model loading and inference using MLX
- **JarvisViewModel**: Manages app state and message flow
- **ContentView**: SwiftUI interface

## Performance

On Apple Silicon:
- **Initial load time**: 10-30 seconds (one-time download + load)
- **Response latency**: ~50-200ms for first token
- **Throughput**: 20-50 tokens/second (varies by chip)

## Privacy & Security

- All AI processing happens **locally on your device**
- No data is sent to external servers
- No internet connection required after model download
- Models are cached locally for offline use

## Troubleshooting

### Model loading issues
- Ensure you have sufficient disk space (~5GB)
- Check internet connection for initial model download
- Try restarting the app

### Performance issues
- Close other memory-intensive apps
- Use the 1B model variant for better performance on older M1 chips
- Ensure your Mac is not in Low Power Mode

## License

This project is open source and available under the MIT License.

## Credits

- Built with [MLX](https://github.com/ml-explore/mlx) by Apple
- Default model: [Qwen2.5](https://qwenlm.github.io/) by Alibaba Cloud
- MLX Swift bindings from [ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)
- Models from [mlx-community](https://huggingface.co/mlx-community) on Hugging Face 