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
        var tabLabel: String? = nil
        var keyNotes: [String] = []
        var isFinished = false

        var remainingPlaybackTime: Double? {
            guard duration.isFinite, duration > 0, elapsed.isFinite else { return nil }
            return max(duration - max(elapsed, 0), 0)
        }

        var remainingPlaybackLabel: String {
            guard let remainingPlaybackTime else { return "--:--" }
            return "-\(Self.formatPlaybackTime(remainingPlaybackTime))"
        }

        var remainingPlaybackCountdownInterval: ClosedRange<Date>? {
            guard
                isPlaying,
                let remainingPlaybackTime,
                remainingPlaybackTime > 0,
                updatedAt.timeIntervalSinceReferenceDate.isFinite
            else { return nil }

            return updatedAt...updatedAt.addingTimeInterval(remainingPlaybackTime)
        }

        private static func formatPlaybackTime(_ seconds: Double) -> String {
            let totalSeconds = max(Int(seconds.rounded()), 0)
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var artifactID: String
    var artifactPath: String
    var topic: String
    var source: PavbotAudioActivitySource
}
