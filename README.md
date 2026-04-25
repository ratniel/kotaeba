## KotaebaApp - Native macOS Client

For **global hotkey activation** and **text insertion anywhere on screen**, we're building a native Swift menubar app.

### Features (Planned)
- **Global Hotkey** (⌥Space) — trigger transcription from any app
- **Push-to-Talk** or **Toggle** recording modes  
- **Text Insertion** — transcribed text appears at your cursor
- **Menubar Resident** — runs silently in the background

### Documentation

See the `KotaebaApp/` folder:
- [`QUICKSTART.md`](KotaebaApp/QUICKSTART.md) — Get running in 15 minutes
- [`ARCHITECTURE.md`](KotaebaApp/ARCHITECTURE.md) — System design & components
- [`IMPLEMENTATION_GUIDE.md`](KotaebaApp/IMPLEMENTATION_GUIDE.md) — Step-by-step code guide

### Architecture Overview

```
┌───────────────────────────────────────────────────────────┐
│              KotaebaApp (Swift Menubar App)               │
│  ⌥Space → Audio Capture → WebSocket → Text Insertion     │
└───────────────────────────────────────────────────────────┘
                            │
                            │ WebSocket (ws://localhost:8000)
                            ▼
┌───────────────────────────────────────────────────────────┐
│              Python Backend (This Repo)                   │
│  MLX Whisper Server + VAD → Real-time Transcription      │
└───────────────────────────────────────────────────────────┘
```

---

## 📄 License

MIT
