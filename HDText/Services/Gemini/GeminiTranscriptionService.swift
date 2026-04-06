import Foundation
import GoogleGenerativeAI

final class GeminiTranscriptionService {

    private var cachedModel: GenerativeModel?
    private var cachedModelKey: String = ""

    func transcribeAndClean(
        audioData: Data,
        aggressiveness: RewriteAggressiveness = .balanced,
        smartCorrection: Bool = true,
        modelName: String = "gemini-2.5-flash",
        apiKey: String
    ) async throws -> String {
        guard !audioData.isEmpty else {
            throw TranscriptionError.noAudio
        }

        hdLog("Transcribe+clean \(audioData.count) bytes with \(modelName)")

        let wavData = wrapInWAV(pcmData: audioData, sampleRate: 16000, channels: 1, bitsPerSample: 16)

        let cleanupLevel: String
        switch aggressiveness {
        case .minimal:
            cleanupLevel = "Fix punctuation. Remove false starts and repeated words. Keep original phrasing."
        case .balanced:
            cleanupLevel = "Fix grammar, punctuation, and sentence breaks. Remove false starts, repetitions, and self-corrections. Keep the speaker's tone."
        case .polished:
            cleanupLevel = "Fix grammar. Improve sentence structure for clarity and flow. Keep the speaker's voice and intent."
        }

        let smartCorrectionRule = smartCorrection
            ? "\n- If a word clearly doesn't fit the sentence context, replace it with the most likely intended word."
            : ""

        let systemPrompt = """
        You are a speech-to-text transcription assistant. Your ONLY job is to accurately transcribe spoken audio and lightly clean it up.
        CRITICAL RULES:
        1. Transcribe EXACTLY what the speaker says. Never invent, add, or hallucinate content.
        2. Remove filler words: um, uh, uh huh, hmm, ah, er, like (filler), you know, basically, literally, I mean, kind of, sort of, right, so (filler), well (filler), actually (filler).
        3. \(cleanupLevel)\(smartCorrectionRule)
        4. Preserve ALL names, numbers, technical terms, negations, and meaning exactly as spoken.
        5. Do NOT add information the speaker did not say. Do NOT rephrase into different meanings.
        6. Output ONLY the cleaned transcription. No labels, timestamps, or commentary.
        7. If no speech is detected: output [NO_SPEECH]
        """

        let cacheKey = "\(modelName)|\(apiKey)|\(aggressiveness.rawValue)|\(smartCorrection)"
        let model: GenerativeModel
        if cacheKey == cachedModelKey, let cached = cachedModel {
            model = cached
        } else {
            let systemInstruction = ModelContent(role: "system", parts: systemPrompt)
            model = GenerativeModel(name: modelName, apiKey: apiKey, systemInstruction: systemInstruction)
            cachedModel = model
            cachedModelKey = cacheKey
        }

        let response = try await model.generateContent(
            ModelContent.Part.data(mimetype: "audio/wav", wavData),
            ModelContent.Part.text("Transcribe.")
        )

        guard let text = response.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) else {
            throw TranscriptionError.emptyResponse
        }

        if text == "[NO_SPEECH]" || text.isEmpty {
            throw TranscriptionError.noSpeechDetected
        }

        let lower = text.lowercased()
        let phantomPhrases = [
            "transcribe", "i will transcribe", "transcribe for you",
            "no speech", "silence", "no audio", "[silence]",
            "thank you", "thanks for watching",
        ]
        if text.count < 30, phantomPhrases.contains(where: { lower.contains($0) }) {
            hdLog("Rejected phantom transcription: \(text)")
            throw TranscriptionError.noSpeechDetected
        }

        hdLog("Result: \(text)")
        return text
    }

    func transcribe(
        audioData: Data,
        modelName: String = "gemini-2.5-flash",
        apiKey: String
    ) async throws -> String {
        try await transcribeAndClean(
            audioData: audioData,
            aggressiveness: .minimal,
            smartCorrection: false,
            modelName: modelName,
            apiKey: apiKey
        )
    }

    private func wrapInWAV(pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        var header = Data()

        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        return header + pcmData
    }
}

enum TranscriptionError: LocalizedError, Equatable {
    case noAudio
    case emptyResponse
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .noAudio: return "No audio data was captured"
        case .emptyResponse: return "Gemini returned an empty response"
        case .noSpeechDetected: return "No speech detected in the audio"
        }
    }
}
