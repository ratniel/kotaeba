# KotaebaApp - Swift Implementation

This directory contains the complete Swift/SwiftUI implementation for the KotaebaApp macOS application.

## 📁 Project Structure

```
KotaebaApp/
├── KotaebaApp/
│   ├── App/
│   │   ├── KotaebaApp.swift              ✅ App entry point
│   │   └── AppDelegate.swift             ✅ Menubar & lifecycle
│   │
│   ├── Core/
│   │   ├── AppStateManager.swift         ✅ Central orchestrator
│   │   └── Constants.swift               ✅ App constants
│   │
│   ├── Server/
│   │   ├── ServerManager.swift           ✅ Python subprocess
│   │   └── SetupManager.swift            ✅ First-run setup
│   │
│   ├── Audio/
│   │   └── AudioCaptureManager.swift     ✅ Microphone capture
│   │
│   ├── Network/
│   │   ├── WebSocketClient.swift         ✅ WebSocket connection
│   │   └── Messages.swift                ✅ Message models
│   │
│   ├── Hotkey/
│   │   ├── HotkeyManager.swift           ✅ Global hotkey listener
│   │   └── Permissions.swift             ✅ Permission utilities
│   │
│   ├── TextInsertion/
│   │   └── TextInserter.swift            ✅ Text insertion
│   │
│   ├── Data/
│   │   ├── Models.swift                  ✅ SwiftData models
│   │   └── StatisticsManager.swift       ✅ Stats tracking
│   │
│   ├── Views/
│   │   ├── MainWindow/
│   │   │   ├── MainWindowView.swift      ✅ Main window
│   │   │   ├── ServerControlView.swift   ✅ Server controls
│   │   │   ├── RecordingModeView.swift   ✅ Mode selection
│   │   │   └── StatisticsView.swift      ✅ Stats display
│   │   │
│   │   ├── RecordingBar/
│   │   │   ├── RecordingBarWindow.swift  ✅ Overlay window
│   │   │   ├── RecordingBarView.swift    ✅ Bar content
│   │   │   └── AudioVisualizerView.swift ✅ Animated bars
│   │   │
│   │   ├── Onboarding/
│   │   │   └── OnboardingView.swift      ✅ First-run setup
│   │   │
│   │   └── SettingsView.swift            ✅ Settings window
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   ├── setup.sh                      ✅ Setup script
│   │   └── Info.plist
│   │
│   └── Utilities/
│       └── Extensions.swift              ✅ Helper extensions
```

## 🚀 Getting Started

### 1. Install Dependencies

```bash
cd kotaeba
uv sync  # Install Python dependencies
```

### 2. Download Default Model

For instant transcription, download the default Parakeet model:

```bash
source .venv/bin/activate
python download_default_model.py
```

This ensures the model is cached locally before first use (no waiting on first hotkey press!).

### 3. Open Project in Xcode

```bash
cd KotaebaApp
open KotaebaApp.xcodeproj
```

### 4. Add Files to Xcode Project

All source files have been created in their proper directories. You need to add them to your Xcode project:

1. In Xcode, right-click on the `KotaebaApp` group
2. Select "Add Files to KotaebaApp..."
3. Navigate to each directory (App, Core, Server, etc.)
4. Select all `.swift` files
5. Make sure "Copy items if needed" is UNCHECKED
6. Click "Add"

Or use Xcode's automatic file detection:
- File → Add Files to "KotaebaApp"
- Select the entire `KotaebaApp` folder
- Xcode will find all new files

### 5. Configure Info.plist

Add these keys to `Info.plist`:

```xml
<!-- Microphone permission -->
<key>NSMicrophoneUsageDescription</key>
<string>Kotaeba needs microphone access to transcribe your speech to text.</string>

<!-- For menubar-only app (optional, keep dock icon during development) -->
<!-- <key>LSUIElement</key>
<true/> -->
```

### 6. Build Settings

- **Minimum Deployment Target**: macOS 14.0 (for SwiftData)
- **Swift Language Version**: Swift 5.9+

### 7. Run the App

Press `⌘R` to build and run!

## 📋 Implementation Checklist

### Phase 1: Foundation ✅
- [x] Project structure created
- [x] Constants defined
- [x] App entry point
- [x] AppDelegate with menubar
- [x] Main window view

### Phase 2: Server Management ✅
- [x] ServerManager (subprocess)
- [x] SetupManager (dependency installation)
- [x] Server control UI
- [x] Health monitoring

### Phase 3: First-Run Setup ✅
- [x] OnboardingView
- [x] Permission requests
- [x] Setup flow

### Phase 4: Hotkey System ✅
- [x] HotkeyManager
- [x] Permissions utility
- [x] Global Ctrl+X listener

### Phase 5: Audio Capture ✅
- [x] AudioCaptureManager
- [x] Amplitude computation
- [x] Format conversion (16kHz mono)

### Phase 6: WebSocket Client ✅
- [x] WebSocketClient
- [x] Message models
- [x] Connection management

### Phase 7: Recording Bar ✅
- [x] RecordingBarWindow (NSPanel)
- [x] RecordingBarView
- [x] AudioVisualizerView
- [x] Bottom-of-screen positioning

### Phase 8: Text Insertion ✅
- [x] TextInserter
- [x] CGEvent unicode method
- [x] Clipboard fallback

### Phase 9: Statistics ✅
- [x] SwiftData models
- [x] StatisticsManager
- [x] StatisticsView

### Phase 10: Settings ✅
- [x] SettingsView
- [x] Preferences persistence
- [x] Mode selection UI

## 🎨 UI Design

### Color Scheme (Dark Mode)
- **Background**: `#1C1C1E`
- **Surface**: `#2C2C2E`
- **Accent**: `#FF6B35` (fire orange)
- **Text Primary**: `#FFFFFF`
- **Text Secondary**: `#8E8E93`
- **Success**: `#30D158`
- **Recording**: `#FF453A`

### Recording Bar
- Height: 48pt
- Width: 60% of screen
- Position: 20pt from bottom center
- Corner radius: 12pt
- Opacity: 95%

## 🔧 Configuration

### Instant Transcription (NEW!)

Kotaeba now provides **instant hotkey response** by:
1. Auto-starting the server when the app launches
2. Pre-loading the server in the background
3. Showing model download status in the UI

See `../INSTANT_TRANSCRIPTION.md` for architecture details.

### Default Settings
- **Hotkey**: Ctrl+X
- **Recording Mode**: Toggle
- **Model**: Parakeet-TDT-0.6B (default, pre-downloaded)
- **Auto-Start Server**: Configurable in Settings
- **Server**: localhost:9999
- **Audio**: 16kHz, mono, Int16 PCM

### Configurable Settings
- Recording mode (Hold/Toggle)
- Language (auto-detect or specific)
- Auto-start server
- Launch at login
- Text insertion method

## 🧪 Testing

### Manual Testing Steps

1. **First Launch**
   - Verify onboarding appears
   - Complete setup process
   - Check permissions granted

2. **Server Control**
   - Start server from main window
   - Verify status indicator
   - Stop server

3. **Recording**
   - Press Ctrl+X
   - Speak into microphone
   - Verify recording bar appears
   - Check visualizer animation
   - Verify transcription text displays

4. **Text Insertion**
   - Open TextEdit
   - Record and speak
   - Verify text appears at cursor

5. **Statistics**
   - Check word count updates
   - Verify duration tracking
   - Check time saved calculation

### Test Apps
- TextEdit (native)
- Notes (native)
- Safari (browser)
- Chrome (browser)
- Cursor IDE (Electron)
- VS Code (Electron)
- Slack (Electron)

## 📝 Notes

### SwiftData Requirements
- Minimum macOS 14.0 (Sonoma)
- Automatic persistence
- No Core Data boilerplate

### Audio Format
- Sample rate: 16000 Hz (required by Whisper)
- Channels: 1 (mono)
- Format: Int16 PCM
- Buffer size: 1600 samples (100ms)

### WebSocket Protocol
- Endpoint: `ws://localhost:9999/v1/audio/transcriptions/realtime`
- First message: JSON config
- Subsequent messages: Binary audio data
- Receives: JSON transcriptions

### Permissions Required
1. **Microphone**: Audio capture
2. **Accessibility**: Global hotkeys + text insertion

## 🐛 Troubleshooting

### Common Issues

1. **"Event tap failed to create"**
   - **Cause**: Accessibility permission not granted
   - **Fix**: System Settings → Privacy & Security → Accessibility

2. **"Microphone permission denied"**
   - **Fix**: System Settings → Privacy & Security → Microphone

3. **"Server failed to start"**
   - **Cause**: Python environment not set up
   - **Fix**: Run onboarding again or manually run setup.sh

4. **"Text not inserting"**
   - **Cause**: Accessibility permission or app incompatibility
   - **Fix**: Enable clipboard fallback in settings

## 🚧 Future Enhancements

- [ ] Customizable hotkey configuration
- [ ] Multiple language profiles
- [ ] Session history viewer
- [ ] Export transcriptions
- [ ] Custom vocabulary/corrections
- [ ] Sound effects for start/stop
- [ ] Server auto-launch on app start
- [ ] Bundled Python distribution (PyInstaller)

## 📚 Resources

- [Apple MLX Documentation](https://github.com/ml-explore/mlx)
- [mlx-audio Documentation](https://github.com/ml-explore/mlx-audio)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)

---

**Happy coding! 🔥**

For implementation details, see `SWIFT_APP_IMPLEMENTATION_PLAN.md` in the parent directory.
