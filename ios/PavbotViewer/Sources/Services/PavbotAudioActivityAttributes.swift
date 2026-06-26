import ActivityKit
import Foundation

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
}
