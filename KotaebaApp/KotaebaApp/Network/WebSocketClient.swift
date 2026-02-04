import Foundation

/// Delegate protocol for WebSocket events
protocol WebSocketClientDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceiveTranscription(_ transcription: ServerTranscription)
    func webSocketDidReceiveStatus(_ status: ServerStatus)
}

/// WebSocket client for communicating with mlx_audio.server
///
/// Handles:
/// - Connection management
/// - Sending audio data and configuration
/// - Receiving transcription results
class WebSocketClient: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: WebSocketClientDelegate?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private let serverURL: URL
    private var isConnected = false
    
    // MARK: - Initialization
    
    init(serverURL: URL) {
        self.serverURL = serverURL
        super.init()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    // MARK: - Connection
    
    /// Connect to the WebSocket server
    func connect() {
        guard webSocketTask == nil else {
            Log.websocket.debug("Already connected or connecting")
            return
        }
        
        Log.websocket.info("Connecting to \(serverURL)...")
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
    }
    
    /// Disconnect from the WebSocket server
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }
    
    // MARK: - Sending
    
    /// Send configuration to server
    func sendConfiguration(_ config: ClientConfig) {
        guard let data = try? JSONEncoder().encode(config),
              let jsonString = String(data: data, encoding: .utf8) else {
            Log.websocket.error("Failed to encode config")
            return
        }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(message) { error in
            if let error = error {
                Log.websocket.error("Config send error: \(error)")
            } else {
                Log.websocket.info("Config sent successfully")
            }
        }
    }
    
    /// Send audio data (raw PCM bytes)
    func sendAudioData(_ data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { error in
            if let error = error {
                Log.websocket.error("Audio send error: \(error)")
            }
        }
    }
    
    /// Send text message (for debugging)
    func sendText(_ text: String) {
        let message = URLSessionWebSocketTask.Message.string(text)
        webSocketTask?.send(message) { error in
            if let error = error {
                Log.websocket.error("Text send error: \(error)")
            }
        }
    }
    
    // MARK: - Receiving
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                // Continue receiving
                self?.receiveMessage()
                
            case .failure(let error):
                Log.websocket.error("Receive error: \(error)")
                self?.delegate?.webSocketDidDisconnect(error: error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            Log.websocket.debug("Received message: \(text.prefix(200))")
            let serverMessage = ServerMessage(from: text)
            
            switch serverMessage {
            case .transcription(let transcription):
                Log.websocket.debug("Parsed transcription: \"\(transcription.text)\" (partial: \(transcription.isPartial))")
                delegate?.webSocketDidReceiveTranscription(transcription)
                
            case .status(let status):
                Log.websocket.info("Status: \(status.status) - \(status.message)")
                delegate?.webSocketDidReceiveStatus(status)
                
            case .unknown(let raw):
                Log.websocket.warning("Unknown message format: \(raw.prefix(100))...")
            }
            
        case .data(let data):
            Log.websocket.debug("Received binary data: \(data.count) bytes")
            
        @unknown default:
            Log.websocket.warning("Unknown message type")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketClient: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Log.websocket.info("Connected")
        isConnected = true
        delegate?.webSocketDidConnect()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        Log.websocket.info("Disconnected with code: \(closeCode.rawValue), reason: \(reasonString)")
        isConnected = false
        delegate?.webSocketDidDisconnect(error: nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Log.websocket.error("Task completed with error: \(error)")
            delegate?.webSocketDidDisconnect(error: error)
        }
    }
}
