import Foundation

enum SpeechBackendID: String, CaseIterable, Identifiable {
    case system
    case kokoro
    case qwen3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .kokoro:
            return "Kokoro"
        case .qwen3:
            return "Qwen3"
        }
    }

    var detailLabel: String {
        switch self {
        case .system:
            return "Built-in macOS voices"
        case .kokoro:
            return "Fast local Hugging Face model"
        case .qwen3:
            return "Higher-quality local Hugging Face model"
        }
    }
}

struct VoiceOption: Identifiable, Hashable {
    let id: String
    let backendID: SpeechBackendID
    let name: String
    let localeIdentifier: String

    var displayLabel: String {
        let locale = Locale(identifier: localeIdentifier)
        let region = locale.region?.identifier ?? locale.language.languageCode?.identifier.uppercased() ?? localeIdentifier
        return "\(name) · \(region)"
    }
}

struct SpeechBackendOption: Identifiable, Hashable {
    let id: SpeechBackendID
    let title: String
    let subtitle: String
}

struct SpeechEngineStatus: Equatable {
    var isPreparing = false
    var isReady = false
    var progress = 0.0
    var message = ""
}

struct AlignedWordTiming: Codable, Hashable {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let startOffset: Int
    let endOffset: Int

    var range: NSRange {
        NSRange(location: startOffset, length: max(0, endOffset - startOffset))
    }
}

struct LocalModelProfile: Hashable {
    let backendID: SpeechBackendID
    let modelIdentifier: String
    let languageCode: String
    let voices: [VoiceOption]
}

enum LocalModelCatalog {
    static let kokoro = LocalModelProfile(
        backendID: .kokoro,
        modelIdentifier: "mlx-community/Kokoro-82M-bf16",
        languageCode: "a",
        voices: [
            VoiceOption(id: "kokoro:af_heart", backendID: .kokoro, name: "Heart", localeIdentifier: "en-US"),
            VoiceOption(id: "kokoro:af_alloy", backendID: .kokoro, name: "Alloy", localeIdentifier: "en-US"),
            VoiceOption(id: "kokoro:af_bella", backendID: .kokoro, name: "Bella", localeIdentifier: "en-US"),
            VoiceOption(id: "kokoro:af_nicole", backendID: .kokoro, name: "Nicole", localeIdentifier: "en-US"),
            VoiceOption(id: "kokoro:af_sarah", backendID: .kokoro, name: "Sarah", localeIdentifier: "en-US"),
            VoiceOption(id: "kokoro:am_adam", backendID: .kokoro, name: "Adam", localeIdentifier: "en-US"),
            VoiceOption(id: "kokoro:am_michael", backendID: .kokoro, name: "Michael", localeIdentifier: "en-US"),
        ]
    )

    static let qwen3 = LocalModelProfile(
        backendID: .qwen3,
        modelIdentifier: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
        languageCode: "English",
        voices: [
            VoiceOption(id: "qwen3:Chelsie", backendID: .qwen3, name: "Chelsie", localeIdentifier: "en-US"),
            VoiceOption(id: "qwen3:Ryan", backendID: .qwen3, name: "Ryan", localeIdentifier: "en-US"),
            VoiceOption(id: "qwen3:Aiden", backendID: .qwen3, name: "Aiden", localeIdentifier: "en-US"),
            VoiceOption(id: "qwen3:Dylan", backendID: .qwen3, name: "Dylan", localeIdentifier: "en-US"),
            VoiceOption(id: "qwen3:Serena", backendID: .qwen3, name: "Serena", localeIdentifier: "en-US"),
            VoiceOption(id: "qwen3:Vivian", backendID: .qwen3, name: "Vivian", localeIdentifier: "en-US"),
        ]
    )

    static func profile(for backendID: SpeechBackendID) -> LocalModelProfile? {
        switch backendID {
        case .kokoro:
            return kokoro
        case .qwen3:
            return qwen3
        case .system:
            return nil
        }
    }
}
