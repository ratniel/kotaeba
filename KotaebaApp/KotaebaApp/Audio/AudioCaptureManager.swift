import AVFoundation
import AudioToolbox
import Foundation

typealias AudioCaptureSessionID = UUID

/// Delegate protocol for audio capture events
protocol AudioCaptureDelegate: AnyObject {
    /// Called when audio buffer is ready to send
    func audioCaptureDidReceiveBuffer(_ buffer: Data, sessionID: AudioCaptureSessionID)
    
    /// Called with amplitude value for visualizer (0.0 - 1.0)
    func audioCaptureDidUpdateAmplitude(_ amplitude: Float, sessionID: AudioCaptureSessionID)
    
    /// Called when an error occurs
    func audioCaptureDidFail(error: Error, sessionID: AudioCaptureSessionID)
}

protocol AudioCapturing: AnyObject {
    var delegate: AudioCaptureDelegate? { get set }
    var inputDevicesDidChange: (() -> Void)? { get set }

    func requestPermission() async -> Bool
    func checkPermission() -> Bool
    @discardableResult
    func startRecording() throws -> AudioCaptureSessionID
    func stopRecording()
    func refreshAvailableInputDevices() -> [AudioInputDevice]
    func selectedInputDeviceID() -> String
    func setSelectedInputDeviceID(_ deviceID: String)
}

/// Captures microphone audio and converts to format suitable for Whisper
///
/// Audio format: 16kHz, mono, Int16 PCM
/// Computes amplitude for visualizer display
class AudioCaptureManager: AudioCapturing {
    
    // MARK: - Properties
    
    weak var delegate: AudioCaptureDelegate?
    var inputDevicesDidChange: (() -> Void)?
    
    private var audioEngine: AVAudioEngine?
    private var isRecording = false
    private var activeSessionID: AudioCaptureSessionID?
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var defaultInputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    
    // Target format for Whisper
    private let targetSampleRate: Double = Constants.Audio.sampleRate
    private let targetChannels: AVAudioChannelCount = AVAudioChannelCount(Constants.Audio.channels)

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        observeDeviceChanges()
    }

    deinit {
        notificationCenter.removeObserver(self)
        removeDefaultInputDeviceObserver()
        stopRecording()
    }
    
    // MARK: - Permission
    
    /// Request microphone permission
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    /// Check if microphone permission is granted
    func checkPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    // MARK: - Recording Control
    
    /// Start capturing audio from microphone
    @discardableResult
    func startRecording() throws -> AudioCaptureSessionID {
        if isRecording, let activeSessionID {
            return activeSessionID
        }
        
        guard checkPermission() else {
            throw AudioError.permissionDenied
        }

        let sessionID = AudioCaptureSessionID()
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioError.engineCreationFailed
        }

        do {
            try configureSelectedInputDevice(on: audioEngine)
        } catch {
            audioEngine.stop()
            self.audioEngine = nil
            throw error
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        Log.audio.info("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        // Create output format (16kHz, mono, Int16)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            audioEngine.stop()
            self.audioEngine = nil
            throw AudioError.formatCreationFailed
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            audioEngine.stop()
            self.audioEngine = nil
            throw AudioError.converterCreationFailed
        }
        
        // Install tap on input node
        let bufferSize: AVAudioFrameCount = AVAudioFrameCount(Constants.Audio.bufferSize)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(
                buffer,
                converter: converter,
                outputFormat: outputFormat,
                sessionID: sessionID
            )
        }
        
        // Start engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            self.audioEngine = nil
            activeSessionID = nil
            isRecording = false
            throw error
        }
        
        activeSessionID = sessionID
        isRecording = true
        Log.audio.info("Recording started")
        return sessionID
    }
    
    /// Stop capturing audio
    func stopRecording() {
        guard isRecording || audioEngine != nil || activeSessionID != nil else { return }
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        isRecording = false
        activeSessionID = nil
        Log.audio.info("Recording stopped")
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        sessionID: AudioCaptureSessionID
    ) {
        guard isRecording, activeSessionID == sessionID else { return }

        // Calculate amplitude for visualizer (from input buffer)
        let amplitude = calculateAmplitude(from: inputBuffer)
        delegate?.audioCaptureDidUpdateAmplitude(amplitude, sessionID: sessionID)
        
        // Convert to output format
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            return
        }
        
        var error: NSError?
        var hasData = true
        
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if hasData {
                outStatus.pointee = .haveData
                hasData = false
                return inputBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }
        
        guard status != .error, error == nil else {
            Log.audio.error("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return
        }
        
        // Extract Int16 data
        guard let int16Data = outputBuffer.int16ChannelData else { return }
        
        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0 else { return }
        
        let data = Data(bytes: int16Data[0], count: frameLength * 2)  // 2 bytes per Int16
        
        guard isRecording, activeSessionID == sessionID else { return }
        delegate?.audioCaptureDidReceiveBuffer(data, sessionID: sessionID)
    }
    
    /// Calculate RMS amplitude from audio buffer (0.0 - 1.0)
    private func calculateAmplitude(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        
        // Calculate RMS (root mean square)
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameLength))
        
        // Normalize to 0-1 range (adjust multiplier for sensitivity)
        let normalized = min(1.0, rms * 5.0)
        
        return normalized
    }
    
    // MARK: - Audio Device Selection
    
    func selectedInputDeviceID() -> String {
        AudioInputDeviceSelection.normalizedSelectionID(
            defaults.string(forKey: Constants.UserDefaultsKeys.selectedAudioDevice)
        )
    }

    func setSelectedInputDeviceID(_ deviceID: String) {
        let normalizedID = AudioInputDeviceSelection.normalizedSelectionID(deviceID)
        guard normalizedID != selectedInputDeviceID() else { return }

        defaults.set(normalizedID, forKey: Constants.UserDefaultsKeys.selectedAudioDevice)
        stopRecording()
    }

    /// Get list of available audio input devices plus the explicit System Default option.
    func refreshAvailableInputDevices() -> [AudioInputDevice] {
        AudioInputDeviceSelection.devicesForSettings(
            availablePhysicalDevices: getAvailableInputDevices().map {
                AudioInputDevice(
                    id: $0.uniqueID,
                    name: $0.localizedName,
                    isAvailable: true,
                    isSystemDefault: false
                )
            },
            selectedID: selectedInputDeviceID()
        )
    }

    private func getAvailableInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func observeDeviceChanges() {
        notificationCenter.addObserver(
            self,
            selector: #selector(audioDevicesDidChange),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(audioDevicesDidChange),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
        observeDefaultInputDeviceChanges()
    }

    @objc private func audioDevicesDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.handleAudioDevicesDidChange(defaultInputChanged: false)
        }
    }

    private func handleAudioDevicesDidChange(defaultInputChanged: Bool) {
        let selectedID = selectedInputDeviceID()
        let availableDevices = refreshAvailableInputDevices()
        let selectedDeviceIsUnavailable = selectedID != AudioInputDevice.systemDefaultID &&
            AudioInputDeviceSelection.resolvedCaptureDeviceID(
                selectedID: selectedID,
                availableDevices: availableDevices
            ) == nil
        let systemDefaultChanged = defaultInputChanged && selectedID == AudioInputDevice.systemDefaultID

        if isRecording, selectedDeviceIsUnavailable || systemDefaultChanged {
            let sessionID = activeSessionID
            stopRecording()
            delegate?.audioCaptureDidFail(
                error: systemDefaultChanged ? AudioError.inputDeviceChanged : AudioError.selectedInputUnavailable,
                sessionID: sessionID ?? AudioCaptureSessionID()
            )
        }

        inputDevicesDidChange?()
    }

    private func observeDefaultInputDeviceChanges() {
        let listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleAudioDevicesDidChange(defaultInputChanged: true)
        }

        var address = Self.defaultInputDeviceAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listenerBlock
        )

        if status != noErr {
            Log.audio.warning("Could not observe default input device changes: \(status)")
            return
        }

        defaultInputDeviceListenerBlock = listenerBlock
    }

    private func removeDefaultInputDeviceObserver() {
        guard let defaultInputDeviceListenerBlock else { return }

        var address = Self.defaultInputDeviceAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            defaultInputDeviceListenerBlock
        )
        self.defaultInputDeviceListenerBlock = nil
    }

    private static var defaultInputDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func configureSelectedInputDevice(on audioEngine: AVAudioEngine) throws {
        let devices = refreshAvailableInputDevices()
        guard let selectedDeviceID = AudioInputDeviceSelection.resolvedCaptureDeviceID(
            selectedID: selectedInputDeviceID(),
            availableDevices: devices
        ) else {
            Log.audio.info("Using system default microphone")
            return
        }

        guard let coreAudioDeviceID = coreAudioDeviceID(forUID: selectedDeviceID) else {
            Log.audio.warning("Selected microphone is unavailable; using system default")
            return
        }

        guard let audioUnit = audioEngine.inputNode.audioUnit else {
            throw AudioError.deviceSelectionFailed
        }

        var deviceID = coreAudioDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioError.deviceSelectionFailed
        }

        Log.audio.info("Using selected microphone: \(selectedDeviceID)")
    }

    private func coreAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return nil }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return nil
        }

        return deviceIDs.first { deviceID in
            coreAudioDeviceUID(for: deviceID) == uid
        }
    }

    private func coreAudioDeviceUID(for deviceID: AudioDeviceID) -> String? {
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &uidAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        guard status == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}

// MARK: - Audio Errors

enum AudioError: LocalizedError {
    case engineCreationFailed
    case formatCreationFailed
    case converterCreationFailed
    case permissionDenied
    case deviceSelectionFailed
    case selectedInputUnavailable
    case inputDeviceChanged
    
    var errorDescription: String? {
        switch self {
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .permissionDenied:
            return "Microphone permission denied. Please grant access in System Settings."
        case .deviceSelectionFailed:
            return "Failed to use the selected microphone."
        case .selectedInputUnavailable:
            return "The selected microphone is no longer available."
        case .inputDeviceChanged:
            return "The active microphone changed."
        }
    }
}
