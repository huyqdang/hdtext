import Foundation
import Combine

enum AppMode: String, Equatable {
    case idle
    case listening
    case processing
    case error
}

@MainActor
final class AppState: ObservableObject {
    @Published var mode: AppMode = .idle
    @Published var isLockMode: Bool = false
    @Published var roughTranscript: String = ""
    @Published var cleanedText: String = ""
    @Published var errorMessage: String?

    @Published var isOnboardingComplete: Bool {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: "isOnboardingComplete") }
    }
    @Published var isCalibrated: Bool {
        didSet { UserDefaults.standard.set(isCalibrated, forKey: "isCalibrated") }
    }

    @Published var selectedMicrophoneID: String? {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: "selectedMicrophoneID") }
    }

    @Published var rewriteAggressiveness: RewriteAggressiveness {
        didSet { UserDefaults.standard.set(rewriteAggressiveness.rawValue, forKey: "rewriteAggressiveness") }
    }

    @Published var selectedTranscriptionModelID: String {
        didSet { UserDefaults.standard.set(selectedTranscriptionModelID, forKey: "selectedTranscriptionModelID") }
    }

    @Published var selectedRewriteModelID: String {
        didSet { UserDefaults.standard.set(selectedRewriteModelID, forKey: "selectedRewriteModelID") }
    }

    @Published var smartCorrectionEnabled: Bool {
        didSet { UserDefaults.standard.set(smartCorrectionEnabled, forKey: "smartCorrectionEnabled") }
    }

    @Published var overlayX: Double {
        didSet { UserDefaults.standard.set(overlayX, forKey: "overlayX") }
    }
    @Published var overlayY: Double {
        didSet { UserDefaults.standard.set(overlayY, forKey: "overlayY") }
    }
    var hasCustomOverlayPosition: Bool {
        UserDefaults.standard.object(forKey: "overlayX") != nil
    }

    let errorLog: ErrorLog
    let hotkeyManager: HotkeyManager
    let audioCaptureEngine: AudioCaptureEngine
    let geminiTranscriptionService: GeminiTranscriptionService
    let geminiRewriteService: GeminiRewriteService
    let textInsertionService: TextInsertionService
    let historyStore: HistoryStore
    let keychainStore: KeychainStore
    let refineService: RefineService

    var transcriptionModelAPIName: String {
        GeminiModelCatalog.apiName(forID: selectedTranscriptionModelID, fallback: "gemini-2.5-flash")
    }

    var rewriteModelAPIName: String {
        GeminiModelCatalog.apiName(forID: selectedRewriteModelID, fallback: "gemini-2.5-flash")
    }

    init() {
        self.isOnboardingComplete = UserDefaults.standard.bool(forKey: "isOnboardingComplete")
        self.isCalibrated = UserDefaults.standard.bool(forKey: "isCalibrated")
        self.selectedMicrophoneID = UserDefaults.standard.string(forKey: "selectedMicrophoneID")

        let savedAggressiveness = UserDefaults.standard.string(forKey: "rewriteAggressiveness") ?? ""
        self.rewriteAggressiveness = RewriteAggressiveness(rawValue: savedAggressiveness) ?? .balanced

        self.selectedTranscriptionModelID = UserDefaults.standard.string(forKey: "selectedTranscriptionModelID")
            ?? GeminiModelCatalog.defaultTranscriptionID
        self.selectedRewriteModelID = UserDefaults.standard.string(forKey: "selectedRewriteModelID")
            ?? GeminiModelCatalog.defaultTextID
        self.smartCorrectionEnabled = UserDefaults.standard.object(forKey: "smartCorrectionEnabled") as? Bool ?? true
        self.overlayX = UserDefaults.standard.object(forKey: "overlayX") as? Double ?? -1
        self.overlayY = UserDefaults.standard.object(forKey: "overlayY") as? Double ?? -1

        self.errorLog = ErrorLog()
        self.keychainStore = KeychainStore()
        self.hotkeyManager = HotkeyManager()
        self.audioCaptureEngine = AudioCaptureEngine()
        self.geminiTranscriptionService = GeminiTranscriptionService()
        self.geminiRewriteService = GeminiRewriteService()
        self.textInsertionService = TextInsertionService()
        self.historyStore = HistoryStore()
        self.refineService = RefineService()
    }

    var hasAPIKey: Bool {
        keychainStore.retrieveAPIKey() != nil
    }
}

enum RewriteAggressiveness: String, CaseIterable, Identifiable {
    case minimal = "minimal"
    case balanced = "balanced"
    case polished = "polished"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal Cleanup"
        case .balanced: return "Balanced"
        case .polished: return "More Polished"
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Remove fillers only, keep your phrasing"
        case .balanced: return "Fix grammar and punctuation, preserve meaning"
        case .polished: return "Smooth and restructure for clarity"
        }
    }
}
