# Custos Librarius

<img width="1100" height="741" alt="image" src="https://github.com/user-attachments/assets/53dfdb71-0dcd-4198-91c2-bfe24f0b5c8f" />

<img width="1004" height="594" alt="image" src="https://github.com/user-attachments/assets/0743a919-16a6-430c-9bcf-82c63c966b7e" />


*Your personal AI guardian of knowledge*

A native macOS app that turns your documents into an AI-powered research assistant. Built with SwiftUI and Apple's MLX framework for on-device inference.

## Features

- **Chat** - Ask questions about your documents
- **Search** - BM25 keyword search across your library
- **Quiz** - Generate multiple choice quizzes with difficulty levels
- **Flashcards** - Create study cards from your content
- **Training** - Fine-tune the AI on your documents with LoRA

## Requirements

- macOS 14.0+
- Apple Silicon (M1/M2/M3)
- Xcode 15+

## Setup

1. Clone the repo
2. Open `Package.swift` in Xcode
3. Build and run (Cmd+R)

The app will download the required models from Hugging Face on first launch:
- Chat: `mlx-community/Qwen2.5-1.5B-Instruct-4bit`
- Can be configured in project settings

## Usage

1. Create a new project or open an existing one
2. Add documents (PDF, TXT, MD, EPUB) to your library
3. Click "Index All" to process documents
4. Start chatting, searching, or taking quizzes

## Tech Stack

- **SwiftUI** - Native macOS UI
- **MLX** - Apple's ML framework for Apple Silicon
- **MLXLLM** - LLM inference
- **LoRA** - Efficient fine-tuning

## License

MIT
