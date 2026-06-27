import AVFoundation
import Combine
import Foundation

@MainActor
final class TodayLiveTopicSpeechController: ObservableObject {
    var currentTopicID: String? { playback.currentItemID }
    var currentTitle: String? { playback.currentTitleText }
    var hasActivePlayback: Bool { playback.currentItemID != nil || playback.isSpeaking || playback.isPaused }
    var isSpeaking: Bool { playback.isSpeaking }
    var isPaused: Bool { playback.isPaused }
    var playbackState: SpeechPlaybackState { playback.playbackState }
    var speechRate: MobileNewsSpeechRate { playback.speechRate }
    var timeline: SpeechTimeline? { playback.timeline }
    var currentSegmentIndex: Int { playback.currentSegmentIndex }
    var estimatedElapsed: Double { playback.estimatedElapsed }
    var estimatedDuration: Double { playback.estimatedDuration }
    var currentSegmentText: String? { playback.currentSegmentText }
    var errorMessage: String? { playback.errorMessage }

    private let playback: SpeechPlaybackService
    private var cancellable: AnyCancellable?

    init(
        enableSpeech: Bool = true,
        synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
        audioSession: SpeechAudioSessionConfiguring = SystemSpeechAudioSession(),
        rateDefaults: UserDefaults = .standard
    ) {
        playback = SpeechPlaybackService(
            enableSpeech: enableSpeech,
            synthesizer: synthesizer,
            audioSession: audioSession,
            rateDefaults: rateDefaults
        )
        cancellable = playback.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func speak(_ topic: TodayLiveTopic) {
        playback.play(
            itemID: topic.id,
            title: topic.title,
            text: Self.speechText(for: topic)
        )
    }

    func setSpeechRate(_ rate: MobileNewsSpeechRate) {
        playback.setSpeechRate(rate)
    }

    func utteranceRate(for rate: MobileNewsSpeechRate) -> Float {
        playback.utteranceRate(for: rate)
    }

    func seek(toSegmentIndex index: Int) {
        playback.seek(toSegmentIndex: index)
    }

    func seek(toProgress progress: Double) {
        playback.seek(toProgress: progress)
    }

    func pause() {
        playback.pause()
    }

    func resume() {
        playback.resume()
    }

    func stop() {
        playback.stop()
    }

    static func speechText(for topic: TodayLiveTopic) -> String {
        var sections: [String] = []
        append(topic.title, to: &sections)
        append(topic.lead, to: &sections)
        appendList(title: "Najważniejsze fakty", items: topic.keyFacts, to: &sections)
        appendList(title: "Reakcje na sytuację", items: topic.reactions, to: &sections)
        appendWithTitle("Dlaczego to ważne", text: topic.whyItMatters, to: &sections)
        appendWithTitle("Kontekst", text: topic.context, to: &sections)
        appendList(title: "Co obserwować dalej", items: topic.watchNext, to: &sections)
        return sections.joined(separator: "\n\n")
    }

    private static func append(_ value: String, to sections: inout [String]) {
        guard let clean = cleanSpeechLine(value) else { return }
        sections.append(clean)
    }

    private static func appendWithTitle(_ title: String, text: String, to sections: inout [String]) {
        guard let clean = cleanSpeechLine(text) else { return }
        sections.append("\(title). \(clean)")
    }

    private static func appendList(title: String, items: [String], to sections: inout [String]) {
        let cleanItems = items.compactMap(cleanSpeechLine)
        guard !cleanItems.isEmpty else { return }
        sections.append(([title + "."] + cleanItems).joined(separator: " "))
    }

    private static func cleanSpeechLine(_ value: String) -> String? {
        let withoutURLs = value.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: .regularExpression
        )
        let normalized = withoutURLs
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
