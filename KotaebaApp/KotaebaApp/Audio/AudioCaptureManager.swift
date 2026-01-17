import AVFoundation
import Foundation

/// Delegate protocol for audio capture events
protocol AudioCaptureDelegate: AnyObject {
    /// Called when audio buffer is ready to send
    func audioCaptureDidReceiveBuffer(_ buffer: Data)
    
    /// Called with amplitude value for visualizer (0.0 - 1.0)
    func audioCaptureDidUpdateAmplitude(_ amplitude: Float)
    
    /// Called when an error occurs
    func audioCaptureDidFail(error: Error)
}

/// Captures microphone audio and converts to format suitable for Whisper
///
/// Audio format: 16kHz, mono, Int16 PCM
/// Computes amplitude for visualizer display
class AudioCaptureManager {
    
    // MARK: - Properties
    
    weak var delegate: AudioCaptureDelegate?
    
    private var audioEngine: AVAudioEngine?
    private var isRecording = false
    
    // Target format for Whisper
    private let targetSampleRate: Double = Constants.Audio.sampleRate
    private let targetChannels: AVAudioChannelCount = AVAudioChannelCount(Constants.Audio.channels)
    
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
    func startRecording() throws {
        guard !isRecording else { return }
        
        guard checkPermission() else {
            throw AudioError.permissionDenied
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioError.engineCreationFailed
        }
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        print("[AudioCapture] Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
        
        // Create output format (16kHz, mono, Int16)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            throw AudioError.formatCreationFailed
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioError.converterCreationFailed
        }
        
        // Install tap on input node
        let bufferSize: AVAudioFrameCount = AVAudioFrameCount(Constants.Audio.bufferSize)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }
        
        // Start engine
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        print("[AudioCapture] Recording started")
    }
    
    /// Stop capturing audio
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        isRecording = false
        print("[AudioCapture] Recording stopped")
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ inputBuffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        // Calculate amplitude for visualizer (from input buffer)
        let amplitude = calculateAmplitude(from: inputBuffer)
        delegate?.audioCaptureDidUpdateAmplitude(amplitude)
        
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
            print("[AudioCapture] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return
        }
        
        // Extract Int16 data
        guard let int16Data = outputBuffer.int16ChannelData else { return }
        
        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0 else { return }
        
        let data = Data(bytes: int16Data[0], count: frameLength * 2)  // 2 bytes per Int16
        
        delegate?.audioCaptureDidReceiveBuffer(data)
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
    
    /// Get list of available audio input devices
    func getAvailableInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }
}

// MARK: - Audio Errors

enum AudioError: LocalizedError {
    case engineCreationFailed
    case formatCreationFailed
    case converterCreationFailed
    case permissionDenied
    
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
        }
    }
}
