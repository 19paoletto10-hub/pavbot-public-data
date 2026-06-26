import AVFoundation
import Combine
import Foundation

protocol SpeechAudioSessionConfiguring {
    func activateForSpeech() throws
    func deactivateAfterSpeech()
}

struct SystemSpeechAudioSession: SpeechAudioSessionConfiguring {
    func activateForSpeech() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
    }

    func deactivateAfterSpeech() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct SpeechSegment: Equatable, Identifiable {
    let index: Int
    let text: String
    let wordCount: Int
    let estimatedStart: Double
    let estimatedDuration: Double

    var id: Int { index }
}

struct SpeechTimeline: Equatable {
    let segments: [SpeechSegment]
    let estimatedDuration: Double

    init(text: String, wordsPerMinute: Double = 155) {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawSegments = cleaned
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceSegments = rawSegments.isEmpty && !cleaned.isEmpty ? [cleaned] : rawSegments
        var cursor = 0.0
        var builtSegments: [SpeechSegment] = []

        for (index, segmentText) in sourceSegments.enumerated() {
            let wordCount = max(Self.wordCount(in: segmentText), 1)
            let duration = max((Double(wordCount) / max(wordsPerMinute, 1)) * 60, 2.5)
            builtSegments.append(
                SpeechSegment(
                    index: index,
                    text: segmentText,
                    wordCount: wordCount,
                    estimatedStart: cursor,
                    estimatedDuration: duration
                )
            )
            cursor += duration
        }

        segments = builtSegments
        estimatedDuration = cursor
    }

    func segmentIndex(forProgress progress: Double) -> Int {
        guard !segments.isEmpty, estimatedDuration > 0 else { return 0 }
        let clampedProgress = min(max(progress, 0), 1)
        let target = clampedProgress * estimatedDuration
        if clampedProgress >= 1 {
            return segments.indices.last ?? 0
        }
        return segments.last(where: { $0.estimatedStart <= target })?.index ?? 0
    }

    func progress(forSegmentIndex index: Int) -> Double {
        guard !segments.isEmpty, estimatedDuration > 0 else { return 0 }
        let safeIndex = min(max(index, 0), segments.count - 1)
        return min(max(segments[safeIndex].estimatedStart / estimatedDuration, 0), 1)
    }

    func segment(at index: Int) -> SpeechSegment? {
        guard !segments.isEmpty else { return nil }
        return segments[min(max(index, 0), segments.count - 1)]
    }

    private static func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}

enum SpeechPlaybackState: Equatable {
    case idle
    case playing
    case paused
    case stopping
    case failed(String)

    var isActive: Bool {
        switch self {
        case .playing, .paused, .stopping:
            return true
        case .idle, .failed:
            return false
        }
    }

    var isSpeaking: Bool {
        switch self {
        case .playing, .paused:
            return true
        case .idle, .stopping, .failed:
            return false
        }
    }

    var isPaused: Bool {
        self == .paused
    }
}

@MainActor
final class SpeechPlaybackService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var currentItemID: String?
    @Published private(set) var playbackState: SpeechPlaybackState = .idle
    @Published private(set) var speechRate: MobileNewsSpeechRate
    @Published private(set) var timeline: SpeechTimeline?
    @Published private(set) var currentSegmentIndex = 0
    @Published private(set) var estimatedElapsed = 0.0
    @Published private(set) var errorMessage: String?

    var isSpeaking: Bool {
        playbackState.isSpeaking
    }

    var isPaused: Bool {
        playbackState.isPaused
    }

    var estimatedDuration: Double {
        timeline?.estimatedDuration ?? 0
    }

    var currentTitleText: String? {
        currentTitle
    }

    var currentSegmentText: String? {
        timeline?.segment(at: currentSegmentIndex)?.text
    }

    private let synthesizer: AVSpeechSynthesizer
    private let audioSession: SpeechAudioSessionConfiguring
    private let enableSpeech: Bool
    private let rateDefaults: UserDefaults
    private var currentTitle: String?
    private var currentText: String?
    private var segmentStartDate: Date?
    private var segmentStartElapsed = 0.0
    private var timer: Timer?
    private var playbackSessionID = UUID()
    private var currentUtterance: AVSpeechUtterance?
    private var currentUtteranceSessionID: UUID?
    private var currentSegmentWordOffset = 0

    init(
        enableSpeech: Bool = true,
        synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
        audioSession: SpeechAudioSessionConfiguring = SystemSpeechAudioSession(),
        rateDefaults: UserDefaults = .standard
    ) {
        self.enableSpeech = enableSpeech
        self.synthesizer = synthesizer
        self.audioSession = audioSession
        self.rateDefaults = rateDefaults
        self.speechRate = MobileNewsSpeechRate.saved(in: rateDefaults)
        super.init()
        synthesizer.delegate = self
    }

    func play(itemID: String, title: String, text: String) {
        if currentItemID == itemID, playbackState == .paused {
            resume()
            return
        }

        if currentItemID == itemID, playbackState == .playing {
            pause()
            return
        }

        start(itemID: itemID, title: title, text: text, segmentIndex: 0)
    }

    func start(
        itemID: String,
        title: String,
        text: String,
        segmentIndex: Int = 0,
        preservedElapsed: Double? = nil,
        wordOffset: Int = 0,
        startPaused: Bool = false
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            stop()
            errorMessage = "Tekst do odczytania jest pusty."
            return
        }

        do {
            try audioSession.activateForSpeech()
        } catch {
            errorMessage = PavbotUserFacingError.audio(error.localizedDescription).message
            playbackState = .failed(errorMessage ?? "Nie udało się przygotować odczytu.")
            return
        }

        stopSynthesizerForRestart()

        let newTimeline = SpeechTimeline(text: cleanText)
        guard !newTimeline.segments.isEmpty else {
            stop()
            errorMessage = "Tekst do odczytania nie zawiera czytelnych fragmentów."
            return
        }

        playbackSessionID = UUID()
        currentItemID = itemID
        currentTitle = title
        currentText = cleanText
        timeline = newTimeline
        currentSegmentIndex = min(max(segmentIndex, 0), newTimeline.segments.count - 1)
        currentSegmentWordOffset = safeWordOffset(wordOffset, in: newTimeline.segment(at: currentSegmentIndex))
        let segmentStart = newTimeline.segment(at: currentSegmentIndex)?.estimatedStart ?? 0
        estimatedElapsed = min(max(preservedElapsed ?? segmentStart, 0), newTimeline.estimatedDuration)
        playbackState = startPaused ? .paused : .playing
        errorMessage = nil
        if startPaused {
            timer?.invalidate()
            timer = nil
            segmentStartDate = nil
            segmentStartElapsed = estimatedElapsed
            return
        }
        speakCurrentSegment()
    }

    func setSpeechRate(_ rate: MobileNewsSpeechRate) {
        guard speechRate != rate else { return }
        let resumeContext = currentResumeContext()
        let wasPaused = playbackState == .paused
        speechRate = rate
        MobileNewsSpeechRate.save(rate, in: rateDefaults)

        guard isSpeaking, let currentItemID, let currentTitle, let currentText else { return }
        start(
            itemID: currentItemID,
            title: currentTitle,
            text: currentText,
            segmentIndex: resumeContext?.segmentIndex ?? currentSegmentIndex,
            preservedElapsed: resumeContext?.estimatedElapsed ?? estimatedElapsed,
            wordOffset: resumeContext?.wordOffset ?? currentSegmentWordOffset,
            startPaused: wasPaused
        )
    }

    func utteranceRate(for rate: MobileNewsSpeechRate) -> Float {
        AVSpeechUtteranceDefaultSpeechRate * rate.multiplier
    }

    func seek(toSegmentIndex index: Int) {
        guard let currentItemID, let currentTitle, let currentText, let timeline else { return }
        let safeIndex = min(max(index, 0), max(timeline.segments.count - 1, 0))
        start(itemID: currentItemID, title: currentTitle, text: currentText, segmentIndex: safeIndex)
    }

    func seek(toProgress progress: Double) {
        guard let timeline else { return }
        seek(toSegmentIndex: timeline.segmentIndex(forProgress: progress))
    }

    func pause() {
        guard playbackState == .playing else { return }
        updateEstimatedElapsed()
        if enableSpeech, !synthesizer.pauseSpeaking(at: .word) {
            errorMessage = "Nie udało się wstrzymać czytania. Spróbuj ponownie albo użyj Stop."
            playbackState = .playing
            return
        }

        playbackState = .paused
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard playbackState == .paused else { return }
        if currentUtterance == nil {
            playbackState = .playing
            speakCurrentSegment()
            return
        }

        if enableSpeech, !synthesizer.continueSpeaking() {
            errorMessage = "Nie udało się wznowić czytania. Uruchom odczyt ponownie."
            playbackState = .paused
            return
        }

        playbackState = .playing
        startProgressTimer()
    }

    func stop() {
        playbackSessionID = UUID()
        playbackState = .stopping
        currentUtterance = nil
        if enableSpeech, synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resetPlaybackState(finalElapsed: 0, keepError: false)
        audioSession.deactivateAfterSpeech()
    }

    private func resetPlaybackState(finalElapsed: Double, keepError: Bool) {
        timer?.invalidate()
        timer = nil
        currentItemID = nil
        currentTitle = nil
        currentText = nil
        timeline = nil
        currentUtterance = nil
        currentUtteranceSessionID = nil
        currentSegmentIndex = 0
        currentSegmentWordOffset = 0
        estimatedElapsed = finalElapsed
        playbackState = .idle
        if !keepError {
            errorMessage = nil
        }
    }

    private func speakCurrentSegment() {
        guard let segment = timeline?.segment(at: currentSegmentIndex) else {
            finishPlayback()
            return
        }

        segmentStartDate = Date()
        let segmentEnd = segment.estimatedStart + segment.estimatedDuration
        let startElapsed = min(max(estimatedElapsed, segment.estimatedStart), segmentEnd)
        segmentStartElapsed = startElapsed
        estimatedElapsed = startElapsed
        startProgressTimer()

        guard enableSpeech else { return }

        let utterance = AVSpeechUtterance(string: speechText(from: segment, droppingWords: currentSegmentWordOffset))
        utterance.voice = AVSpeechSynthesisVoice(language: "pl-PL")
        if utterance.voice == nil {
            errorMessage = "Brak polskiego głosu TTS na urządzeniu. Sprawdź ustawienia języka i dostępności iOS."
        }
        utterance.rate = utteranceRate(for: speechRate)
        currentUtterance = utterance
        currentUtteranceSessionID = playbackSessionID
        synthesizer.speak(utterance)
    }

    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateEstimatedElapsed()
            }
        }
    }

    private func updateEstimatedElapsed() {
        guard isSpeaking, !isPaused, let timeline, let segment = timeline.segment(at: currentSegmentIndex), let segmentStartDate else {
            return
        }
        let rawElapsed = segmentStartElapsed + Date().timeIntervalSince(segmentStartDate)
        estimatedElapsed = min(rawElapsed, segment.estimatedStart + segment.estimatedDuration)
    }

    private func stopSynthesizerForRestart() {
        guard enableSpeech, synthesizer.isSpeaking || synthesizer.isPaused else { return }
        currentUtterance = nil
        currentUtteranceSessionID = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finishPlayback() {
        let finalDuration = timeline?.estimatedDuration ?? estimatedElapsed
        resetPlaybackState(finalElapsed: finalDuration, keepError: true)
        audioSession.deactivateAfterSpeech()
    }

    private func isCurrentUtterance(_ utterance: AVSpeechUtterance) -> Bool {
        guard enableSpeech else { return false }
        guard let currentUtterance else { return false }
        guard currentUtteranceSessionID == playbackSessionID else { return false }
        return currentUtterance === utterance
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isCurrentUtterance(utterance) else { return }
            guard self.isSpeaking, let timeline = self.timeline else { return }
            let nextIndex = self.currentSegmentIndex + 1
            if nextIndex < timeline.segments.count {
                self.currentSegmentIndex = nextIndex
                self.currentSegmentWordOffset = 0
                self.speakCurrentSegment()
            } else {
                self.finishPlayback()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isCurrentUtterance(utterance) else { return }
            self.finishPlayback()
        }
    }
}

private struct SpeechResumeContext {
    let segmentIndex: Int
    let estimatedElapsed: Double
    let wordOffset: Int
}

private extension SpeechPlaybackService {
    func currentResumeContext() -> SpeechResumeContext? {
        updateEstimatedElapsed()
        guard let timeline, timeline.estimatedDuration > 0 else { return nil }
        let safeElapsed = min(max(estimatedElapsed, 0), timeline.estimatedDuration)
        let progress = safeElapsed / timeline.estimatedDuration
        let segmentIndex = timeline.segmentIndex(forProgress: progress)
        guard let segment = timeline.segment(at: segmentIndex) else { return nil }
        return SpeechResumeContext(
            segmentIndex: segmentIndex,
            estimatedElapsed: safeElapsed,
            wordOffset: wordOffset(in: segment, at: safeElapsed)
        )
    }

    func wordOffset(in segment: SpeechSegment, at elapsed: Double) -> Int {
        guard segment.wordCount > 1, segment.estimatedDuration > 0 else { return 0 }
        let elapsedInsideSegment = min(max(elapsed - segment.estimatedStart, 0), segment.estimatedDuration)
        let segmentProgress = min(max(elapsedInsideSegment / segment.estimatedDuration, 0), 0.95)
        return safeWordOffset(Int((Double(segment.wordCount) * segmentProgress).rounded(.down)), in: segment)
    }

    func safeWordOffset(_ wordOffset: Int, in segment: SpeechSegment?) -> Int {
        guard let segment, segment.wordCount > 1 else { return 0 }
        return min(max(wordOffset, 0), segment.wordCount - 1)
    }

    func speechText(from segment: SpeechSegment, droppingWords wordOffset: Int) -> String {
        let safeOffset = safeWordOffset(wordOffset, in: segment)
        guard safeOffset > 0 else { return segment.text }
        let words = segment.text.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return segment.text }
        return words.dropFirst(min(safeOffset, max(words.count - 1, 0))).joined(separator: " ")
    }
}
