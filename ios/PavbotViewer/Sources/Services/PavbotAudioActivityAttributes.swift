import ActivityKit
import Foundation

enum PavbotAudioActivitySource: String, Codable, Hashable {
    case mp3Podcast
    case pulseDayTTS
    case researchTTS

    var compactSystemImage: String {
        switch self {
        case .mp3Podcast:
            "waveform"
        case .pulseDayTTS:
            "globe.europe.africa.fill"
        case .researchTTS:
            "globe"
        }
    }
}

struct PavbotAudioActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var elapsed: Double
        var duration: Double
        var isPlaying: Bool
        var updatedAt: Date
    }

    var artifactID: String
    var artifactPath: String
    var topic: String
    var source: PavbotAudioActivitySource
}
