import Foundation

final class GeminiLiveTranscriptionService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var accumulatedTranscript = ""
    private var onTranscriptUpdate: ((String) -> Void)?
    private var onError: ((Error) -> Void)?
    private var isActive = false
    private var apiKey: String?
    private var modelName: String = "gemini-2.5-flash"
    private var reconnectAttempts = 0
    private var setupCompleted = false

    private var pendingAudioChunks: [Data] = []
    private let pendingQueue = DispatchQueue(label: "com.hdtext.audio-buffer")

    private let maxReconnectAttempts = 3
    private let reconnectDelay: TimeInterval = 1.0

    var currentTranscript: String { accumulatedTranscript }

    func startSession(
        apiKey: String,
        modelName: String = "gemini-2.5-flash",
        onTranscript: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard !isActive else { return }

        self.apiKey = apiKey
        self.modelName = modelName
        self.onTranscriptUpdate = onTranscript
        self.onError = onError
        self.accumulatedTranscript = ""
        self.reconnectAttempts = 0
        self.isActive = true
        pendingQueue.sync { pendingAudioChunks.removeAll() }

        NSLog("[HD Text] Starting live session with model: %@", modelName)
        connect(apiKey: apiKey)
    }

    func sendAudio(_ pcmData: Data) {
        guard isActive else { return }

        if !setupCompleted {
            pendingQueue.sync { pendingAudioChunks.append(pcmData) }
            return
        }

        sendAudioMessage(pcmData)
    }

    func endSession() {
        let wasActive = isActive
        isActive = false
        onError = nil
        onTranscriptUpdate = nil

        NSLog("[HD Text] Ending session (wasActive: %d). Transcript length: %d chars",
              wasActive ? 1 : 0, accumulatedTranscript.count)

        if let task = webSocketTask {
            task.cancel(with: .normalClosure, reason: nil)
        }
        cleanup()
    }

    private func sendAudioMessage(_ pcmData: Data) {
        guard let task = webSocketTask, isActive else { return }

        let base64Audio = pcmData.base64EncodedString()
        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [[
                    "mimeType": "audio/pcm;rate=16000",
                    "data": base64Audio
                ]]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        task.send(.string(jsonString)) { error in
            if let error = error {
                NSLog("[HD Text] Send audio error: %@", error.localizedDescription)
            }
        }
    }

    private func flushPendingAudio() {
        var chunks: [Data] = []
        pendingQueue.sync {
            chunks = pendingAudioChunks
            pendingAudioChunks.removeAll()
        }
        NSLog("[HD Text] Flushing %d buffered audio chunks", chunks.count)
        for chunk in chunks {
            sendAudioMessage(chunk)
        }
    }

    private func connect(apiKey: String) {
        setupCompleted = false
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            onError?(GeminiError.invalidURL)
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600

        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)

        self.urlSession = session
        self.webSocketTask = task

        task.resume()
        sendSetupMessage()
        startReceiving()
    }

    private func sendSetupMessage() {
        let setup: [String: Any] = [
            "setup": [
                "model": "models/\(modelName)",
                "generationConfig": [
                    "responseModalities": ["TEXT"]
                ],
                "realtimeInputConfig": [
                    "automaticActivityDetection": [
                        "disabled": false,
                        "startOfSpeechSensitivity": "START_SENSITIVITY_HIGH",
                        "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
                        "prefixPaddingMs": 100,
                        "silenceDurationMs": 1000
                    ]
                ],
                "inputAudioTranscription": [String: Any](),
                "systemInstruction": [
                    "parts": [[
                        "text": "You are a transcription assistant. Listen to the audio and transcribe exactly what the user says. Do not add commentary or respond conversationally."
                    ]]
                ]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: setup),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        NSLog("[HD Text] Sending setup message for model: models/%@", modelName)
        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                NSLog("[HD Text] Setup send error: %@", error.localizedDescription)
            }
        }
    }

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isActive else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.startReceiving()

            case .failure(let error):
                NSLog("[HD Text] Receive error: %@", error.localizedDescription)
                self.handleConnectionError(error)
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseResponse(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseResponse(text)
            }
        @unknown default:
            break
        }
    }

    private func parseResponse(_ json: String) {
        guard let data = json.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[HD Text] Failed to parse response JSON")
            return
        }

        if response["setupComplete"] != nil {
            setupCompleted = true
            reconnectAttempts = 0
            NSLog("[HD Text] Setup complete - ready to receive audio")
            flushPendingAudio()
            return
        }

        if let serverContent = response["serverContent"] as? [String: Any] {
            if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
               let text = inputTranscription["text"] as? String,
               !text.isEmpty {
                NSLog("[HD Text] inputTranscription: %@", text)
                accumulatedTranscript += text
                onTranscriptUpdate?(accumulatedTranscript)
                return
            }

            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let text = part["text"] as? String, !text.isEmpty {
                        NSLog("[HD Text] modelTurn text: %@", text)
                        accumulatedTranscript += text
                        onTranscriptUpdate?(accumulatedTranscript)
                    }
                }
                return
            }

            let keys = serverContent.keys.joined(separator: ", ")
            NSLog("[HD Text] serverContent keys: %@", keys)
            return
        }

        let topKeys = response.keys.joined(separator: ", ")
        NSLog("[HD Text] Response keys: %@", topKeys)
    }

    private func handleConnectionError(_ error: Error) {
        guard isActive else { return }

        NSLog("[HD Text] Connection error: %@ (attempt %d/%d)",
              error.localizedDescription, reconnectAttempts, maxReconnectAttempts)

        if reconnectAttempts < maxReconnectAttempts, let apiKey = self.apiKey {
            reconnectAttempts += 1
            let delay = reconnectDelay * Double(reconnectAttempts)

            webSocketTask?.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            urlSession = nil

            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self, self.isActive else { return }
                NSLog("[HD Text] Reconnecting (attempt %d)", self.reconnectAttempts)
                self.connect(apiKey: apiKey)
            }
        } else {
            let savedError = onError
            isActive = false
            savedError?(error)
        }
    }

    private func cleanup() {
        webSocketTask = nil
        urlSession = nil
        apiKey = nil
        setupCompleted = false
        pendingQueue.sync { pendingAudioChunks.removeAll() }
    }
}

enum GeminiError: LocalizedError {
    case invalidURL
    case connectionFailed
    case sessionTimeout
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Gemini API URL"
        case .connectionFailed: return "Failed to connect to Gemini"
        case .sessionTimeout: return "Gemini session timed out"
        case .networkUnavailable: return "Network is unavailable"
        }
    }
}
