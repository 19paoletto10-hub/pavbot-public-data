import AVFoundation
import Combine
import Foundation

struct PodcastScriptSpeechClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Serwer tekstu podcastu zwrócił nieprawidłową odpowiedź."
            case .httpStatus(let status):
                "Serwer tekstu podcastu zwrócił HTTP \(status)."
            }
        }
    }

    var fetchText: @Sendable (URL) async throws -> String

    init(
        fetchText: @escaping @Sendable (URL) async throws -> String = { url in
            let (data, response) = try await URLSession.shared.data(for: ManifestClient.request(for: url))
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ClientError.httpStatus(httpResponse.statusCode)
            }
            return String(decoding: data, as: UTF8.self)
        }
    ) {
        self.fetchText = fetchText
    }
}

enum PodcastScriptSpeechText {
    static func clean(_ markdown: String) -> String {
        let withoutCodeBlocks = markdown.replacingOccurrences(
            of: #"(?s)```.*?```"#,
            with: " ",
            options: .regularExpression
        )
        let withoutImages = withoutCodeBlocks.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^)]+\)"#,
            with: " ",
            options: .regularExpression
        )
        let withoutMarkdownLinks = withoutImages.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        let withoutRawURLs = withoutMarkdownLinks.replacingOccurrences(
            of: #"https?://\S+"#,
            with: " ",
            options: .regularExpression
        )

        let lines = withoutRawURLs
            .split(whereSeparator: \.isNewline)
            .map { cleanLine(String($0)) }
            .filter { !$0.isEmpty && !isTechnicalTitle($0) }

        return lines.joined(separator: "\n\n")
    }

    private static func isTechnicalTitle(_ line: String) -> Bool {
        let normalized = line
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "script"
            || normalized == "podcast script"
            || normalized == "pavbot aktualne wydarzenia mobile"
    }

    private static func cleanLine(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: #"^\[[^\]]+\]\s*"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"^[-*+]\s+"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class PodcastScriptSpeechController: ObservableObject {
    @Published var isLoading = false
    @Published private var localErrorMessage: String?

    var currentArtifactID: String? { playback.currentItemID }
    var currentTitle: String? { playback.currentTitleText }
    var hasActivePlayback: Bool { playback.currentItemID != nil || playback.isSpeaking || playback.isPaused }
    var isSpeaking: Bool { playback.isSpeaking }
    var isPaused: Bool { playback.isPaused }
    var playbackState: SpeechPlaybackState { playback.playbackState }
    var errorMessage: String? {
        get { localErrorMessage ?? playback.errorMessage }
        set { localErrorMessage = newValue }
    }
    var speechRate: MobileNewsSpeechRate { playback.speechRate }
    var timeline: SpeechTimeline? { playback.timeline }
    var currentSegmentIndex: Int { playback.currentSegmentIndex }
    var estimatedElapsed: Double { playback.estimatedElapsed }
    var estimatedDuration: Double { playback.estimatedDuration }
    var currentSegmentText: String? { playback.currentSegmentText }
    var transcriptArtifactID: String? { currentArtifact?.id }
    var currentTranscriptText: String? { currentText }

    private let client: PodcastScriptSpeechClient
    private let playback: SpeechPlaybackService
    private var currentArtifact: PavbotArtifact?
    private var currentText: String?
    private var cancellable: AnyCancellable?

    init(
        client: PodcastScriptSpeechClient = PodcastScriptSpeechClient(),
        enableSpeech: Bool = true,
        synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
        audioSession: SpeechAudioSessionConfiguring = SystemSpeechAudioSession(),
        rateDefaults: UserDefaults = .standard
    ) {
        self.client = client
        self.playback = SpeechPlaybackService(
            enableSpeech: enableSpeech,
            synthesizer: synthesizer,
            audioSession: audioSession,
            rateDefaults: rateDefaults
        )
        cancellable = playback.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func playOrToggle(artifact: PavbotArtifact, url: URL) async {
        if currentArtifactID == artifact.id, isSpeaking, isPaused {
            resume()
            return
        }
        if currentArtifactID == artifact.id, isSpeaking {
            pause()
            return
        }

        await loadAndSpeak(artifact: artifact, url: url)
    }

    func loadTranscript(artifact: PavbotArtifact, url: URL) async {
        if transcriptArtifactID == artifact.id, currentTranscriptText?.isEmpty == false {
            return
        }

        isLoading = true
        localErrorMessage = nil
        do {
            let markdown = try await client.fetchText(url)
            let text = PodcastScriptSpeechText.clean(markdown)
            guard !text.isEmpty else {
                throw PodcastScriptSpeechError.emptyScript
            }
            currentArtifact = artifact
            currentText = text
            isLoading = false
        } catch {
            isLoading = false
            localErrorMessage = PavbotUserFacingError.network(error, context: .preview).message
        }
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
        currentArtifact = nil
        currentText = nil
        isLoading = false
    }

    private func loadAndSpeak(artifact: PavbotArtifact, url: URL) async {
        isLoading = true
        localErrorMessage = nil
        do {
            let markdown = try await client.fetchText(url)
            let text = PodcastScriptSpeechText.clean(markdown)
            guard !text.isEmpty else {
                throw PodcastScriptSpeechError.emptyScript
            }
            isLoading = false
            startSpeaking(text: text, artifact: artifact)
        } catch {
            isLoading = false
            localErrorMessage = PavbotUserFacingError.network(error, context: .preview).message
        }
    }

    private func startSpeaking(text: String, artifact: PavbotArtifact) {
        currentArtifact = artifact
        currentText = text
        playback.start(itemID: artifact.id, title: artifact.title, text: text)
    }
}

private enum PodcastScriptSpeechError: LocalizedError {
    case emptyScript

    var errorDescription: String? {
        "Tekst podcastu jest pusty albo nie nadaje się do lokalnego TTS."
    }
}
