# Kotaeba - Streaming STT

Kotaeba is a high-performance, real-time Speech-to-Text (STT) application built with [MLX Audio](https://github.com/blaizzy/mlx-audio). It is specifically optimized for Apple Silicon (M series) and uses WebSockets for low-latency streaming.

## 🚀 Features

- **Real-time Transcription**: Stream audio directly from your microphone and get instant text feedback.
- **Apple Silicon Optimized**: Leverages the MLX framework for lightning-fast inference on Mac.
- **Session Management**: Automatically saves your audio (`.wav`) and transcripts (`.txt`) to the `recordings/` directory.
- **VAD Integration**: Intelligent Voice Activity Detection server-side for accurate speech capturing.
- **Modern Stack**: Built with Python 3.12, `uv` for package management, and `Pydantic` for configuration.

## 🛠️ Prerequisites

- **OS**: macOS (Required for MLX)
- **Hardware**: Apple Silicon (M series)
- **Dependencies**: 
  - [uv](https://github.com/astral-sh/uv) (recommended)
  - `portaudio` (required for PyAudio: `brew install portaudio`)

## 📦 Installation

1. **Clone the repository**:
   ```bash
   git clone <repo-url>
   cd kotaeba
   ```

2. **Sync dependencies**:
   ```bash
   uv sync
   ```

## 🚦 Usage

Start the streaming client and server with a single command:

```bash
uv run main.py
```

- The application automatically starts the MLX Whisper server in the background.
- It captures audio from your default microphone.
- Transcriptions appear in the console in real-time.
- Press `Ctrl+C` to stop. The session data is saved in the `recordings/` folder.

## ⚙️ Configuration

Copy `.env.example` to `.env` and customize as needed:

```bash
cp .env.example .env
```

The server supports:

- `STT_MODEL`: Whisper model (default: `mlx-community/Qwen3-ASR-0.6B-8bit`)
- `STT_HOST` / `STT_PORT`: Server bind address/port
- `LANGUAGE`: Transcription language (default: `en`)
- `AUDIO__*`: Audio capture and streaming settings
- `VAD__*`: Voice activity detection settings
- `LOG_*`: Logging destination and rotation
- `RECORDINGS_DIR`: Output directory for sessions (default: `recordings`)
- `HF_TOKEN` / `HUGGINGFACE_HUB_TOKEN` (optional): Hugging Face auth token for private or gated models

For the macOS app, keep sensitive values (such as `HF_TOKEN`) in Keychain via Settings, not in plain-text files.

## 📂 Project Structure

- `main.py`: Main entry point; manages the client-server lifecycle and audio streaming.
- `stt/`: Server wrapper logic for the MLX backend.
- `config.py`: Centralized configuration and validation.
- `models/`: Pydantic models for WebSocket protocols.
- `validation.py`: Pre-flight checks for audio devices and dependencies.
- `recordings/`: Directory containing session history.

## 📄 License

MIT
