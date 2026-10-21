import Foundation

final class GeminiTranscriptionService {

    private let client: GeminiClient

    init(client: GeminiClient = GeminiClient()) {
        self.client = client
    }

    func buildSystemPrompt(
        aggressiveness: RewriteAggressiveness,
        smartCorrection: Bool
    ) -> String {
        let cleanupLevel: String
        switch aggressiveness {
        case .minimal:
            cleanupLevel = "Fix punctuation. Remove false starts and repeated words. Keep original phrasing."
        case .balanced:
            cleanupLevel = "Fix grammar, punctuation, and sentence breaks. Remove ALL filler words and hesitation sounds, even mid-sentence. Remove false starts, repetitions, self-corrections, and duplicated phrases. Keep the speaker's tone and vocabulary."
        case .polished:
            cleanupLevel = "Fix grammar. Improve sentence structure for clarity and flow. Keep the speaker's voice and intent."
        }

        let smartCorrectionRule: String
        if smartCorrection {
            smartCorrectionRule = """

            SMART CORRECTION:
            - If a word makes no sense in context and sounds phonetically similar to a word that fits, replace it with the fitting word.
            - Only replace when the sentence is clearly nonsensical with the original word. If unsure, keep the original.
            - Prefer words that are phonetically close AND contextually appropriate over distant guesses.
            - NEVER replace names, numbers, technical terms, or domain-specific vocabulary.
            """
        } else {
            smartCorrectionRule = ""
        }

        return """
        You are a speech-to-text transcription assistant. Your ONLY job is to accurately transcribe spoken audio and clean it up.
        CRITICAL RULES:
        1. Transcribe EXACTLY what the speaker says. Never invent, add, or hallucinate content.
        2. Remove ALL filler words and hesitation sounds. This includes all forms and variations of: um, umm, uh, uh huh, uhh, hmm, ah, ahh, er, eh, like (when used as filler), you know, basically, literally, I mean, kind of, sort of, right (filler), so (filler), well (filler), actually (filler), and any other non-content vocalization. Remove them whether they appear at the start, middle, or end of a sentence.
        3. Remove ALL duplicate phrases, stutters, restarts, and self-corrections. When a speaker repeats or restarts a phrase, keep only ONE clean version that captures the full intent. This includes adjacent duplicates AND nearby duplicates (separated by a few words). Examples:
           - "I need to grab I need to grab water." → "I need to grab water."
           - "Hello, hello." → "Hello."
           - "Let me think let me think about it." → "Let me think about it."
           - "Can you can you check this?" → "Can you check this?"
           - "So the the issue is" → "So the issue is"
           - "I need to grab. Need to grab a water." → "I need to grab a water."
           - "I need to grab. Need to grab a water. Be right back." → "I need to grab a water. Be right back."
           - "This is testing. One two three. This is testing." → "This is testing. One two three."
           - "Let me see. Let me see if this works." → "Let me see if this works."
           - "Tomorrow I will. Tomorrow I will go to the store." → "Tomorrow I will go to the store."
           - "Send the email send the email to John." → "Send the email to John."
           Detect restarts even when not word-for-word identical — if the speaker clearly began a phrase, paused, then restarted with more detail, keep only the more complete version. Apply this aggressively.
        4. \(cleanupLevel)\(smartCorrectionRule)
        5. Preserve ALL names, numbers, technical terms, negations, and meaning exactly as spoken.
        6. Do NOT add information the speaker did not say. Do NOT rephrase into different meanings.
        7. Output ONLY the cleaned transcription. No labels, timestamps, or commentary.
        8. If no speech is detected: output [NO_SPEECH]
        """
    }

    func transcribeAndClean(
        audioData: Data,
        aggressiveness: RewriteAggressiveness = .balanced,
        smartCorrection: Bool = true,
        modelName: String,
        apiKey: String
    ) async throws -> String {
        guard !audioData.isEmpty else {
            throw TranscriptionError.noAudio
        }

        hdLog("Transcribe+clean \(audioData.count) bytes with \(modelName)")

        let wavData = wrapInWAV(pcmData: audioData, sampleRate: 16000, channels: 1, bitsPerSample: 16)

        let systemPrompt = buildSystemPrompt(aggressiveness: aggressiveness, smartCorrection: smartCorrection)

        let text: String
        do {
            text = try await client.generate(
                model: modelName,
                apiKey: apiKey,
                systemPrompt: systemPrompt,
                parts: [.inlineData(mimeType: "audio/wav", data: wavData), .text("Transcribe.")],
                options: GeminiGenerationOptions(
                    temperature: 0.2,
                    thinkingLevel: GeminiModelCatalog.thinkingLevel(forAPIName: modelName)))
        } catch GeminiAPIError.emptyResponse {
            throw TranscriptionError.noSpeechDetected
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
        modelName: String,
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
