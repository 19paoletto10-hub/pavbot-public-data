import AVFoundation
import Combine
import Foundation

protocol SpeechAudioSessionConfiguring {
    func activateForSpeech() throws
    func deactivateAfterSpeech()
}

struct SystemSpeechAudioSession: SpeechAudioSessionConfiguring {
    func activateForSpeech() throws {
        // System AVAudioSession ownership lives in PavbotAudioSessionCoordinator.
    }

    func deactivateAfterSpeech() {
        // System AVAudioSession ownership lives in PavbotAudioSessionCoordinator.
    }
}

protocol SpeechSynthesizing: AnyObject {
    var delegate: AVSpeechSynthesizerDelegate? { get set }
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }

    func speak(_ utterance: AVSpeechUtterance)
    func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool
    func continueSpeaking() -> Bool
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechSynthesizing {}

enum SpeechVoiceMode: String, CaseIterable, Identifiable {
    case polishDefault
    case selectedVoice
    case personalVoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polishDefault:
            "Polski domyślny"
        case .selectedVoice:
            "Wybrany głos"
        case .personalVoice:
            "Personal Voice"
        }
    }
}

struct SpeechVoicePreference: Equatable {
    let mode: SpeechVoiceMode
    let voiceIdentifier: String?

    static let polishDefault = SpeechVoicePreference(mode: .polishDefault, voiceIdentifier: nil)
}

enum SpeechVoiceSettings {
    static let modeDefaultsKey = "pavbot.speechVoiceMode"
    static let voiceIdentifierDefaultsKey = "pavbot.speechVoiceIdentifier"

    static func load(from defaults: UserDefaults = .standard) -> SpeechVoicePreference {
        let mode = defaults
            .string(forKey: modeDefaultsKey)
            .flatMap(SpeechVoiceMode.init(rawValue:)) ?? .polishDefault
        let identifier = defaults.string(forKey: voiceIdentifierDefaultsKey)
        return SpeechVoicePreference(mode: mode, voiceIdentifier: identifier?.isEmpty == false ? identifier : nil)
    }

    static func save(_ preference: SpeechVoicePreference, in defaults: UserDefaults = .standard) {
        defaults.set(preference.mode.rawValue, forKey: modeDefaultsKey)
        if let voiceIdentifier = preference.voiceIdentifier, !voiceIdentifier.isEmpty {
            defaults.set(voiceIdentifier, forKey: voiceIdentifierDefaultsKey)
        } else {
            defaults.removeObject(forKey: voiceIdentifierDefaultsKey)
        }
    }

    static func resolvedVoice(in defaults: UserDefaults = .standard) -> AVSpeechSynthesisVoice? {
        resolvedVoice(for: load(from: defaults))
    }

    static func resolvedVoice(
        for preference: SpeechVoicePreference,
        voiceWithIdentifier: (String) -> AVSpeechSynthesisVoice? = { AVSpeechSynthesisVoice(identifier: $0) },
        polishVoice: () -> AVSpeechSynthesisVoice? = {
            SpeechVoiceSettings.bestPolishVoice()
                ?? AVSpeechSynthesisVoice(language: "pl-PL")
        }
    ) -> AVSpeechSynthesisVoice? {
        switch preference.mode {
        case .polishDefault:
            return polishVoice()
        case .selectedVoice:
            guard let identifier = preference.voiceIdentifier, let voice = voiceWithIdentifier(identifier) else {
                return polishVoice()
            }
            return voice
        case .personalVoice:
            if let identifier = preference.voiceIdentifier, let voice = voiceWithIdentifier(identifier) {
                return voice
            }
            let personalVoiceIdentifier = SpeechVoiceCatalog.current().personalVoices.first?.id
            if let personalVoiceIdentifier, let voice = voiceWithIdentifier(personalVoiceIdentifier) {
                return voice
            }
            return polishVoice()
        }
    }

    private static func bestPolishVoice() -> AVSpeechSynthesisVoice? {
        let polishCandidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "pl-PL" || $0.language.hasPrefix("pl")
        }
        guard !polishCandidates.isEmpty else { return nil }

        let sorted = polishCandidates.sorted { first, second in
            let leftScore = polishVoicePriority(for: first)
            let rightScore = polishVoicePriority(for: second)
            if leftScore == rightScore {
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
            return leftScore > rightScore
        }
        return sorted.first
    }

    private static func polishVoicePriority(for voice: AVSpeechSynthesisVoice) -> Int {
        let signature = "\(voice.name) \(voice.identifier)".lowercased()
        var score = 0

        if signature.contains("zosia") || signature.contains("zośia") {
            score += 700
        }

        if signature.contains("extended") || signature.contains("rozszerz") {
            score += 120
        }

        switch voice.quality {
        case .premium:
            score += 90
        case .enhanced:
            score += 70
        case .default:
            score += 40
        @unknown default:
            score += 20
        }

        if voice.language == "pl-PL" {
            score += 30
        }

        return score
    }
}

struct SpeechVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality
    let qualityLabel: String
    let isPersonalVoice: Bool

    var displayTitle: String {
        isPersonalVoice ? "\(name) · Personal Voice" : name
    }

    var displaySubtitle: String {
        "\(language) · \(qualityLabel)"
    }

    init(
        id: String,
        name: String,
        language: String,
        qualityLabel: String,
        isPersonalVoice: Bool
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.qualityLabel = qualityLabel
        self.isPersonalVoice = isPersonalVoice
    }

    init(voice: AVSpeechSynthesisVoice) {
        id = voice.identifier
        name = voice.name
        language = voice.language
        quality = voice.quality
        qualityLabel = Self.qualityLabel(for: voice.quality)
        if #available(iOS 17.0, *) {
            isPersonalVoice = voice.voiceTraits.contains(.isPersonalVoice)
        } else {
            isPersonalVoice = false
        }
    }

    private static func qualityLabel(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default:
            "Domyślny"
        case .enhanced:
            "Enhanced"
        case .premium:
            "Premium"
        @unknown default:
            "Systemowy"
        }
    }
}

enum SpeechPersonalVoiceAuthorization: String, Equatable {
    case notDetermined
    case denied
    case unsupported
    case authorized

    init(_ status: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .unsupported:
            self = .unsupported
        case .authorized:
            self = .authorized
        @unknown default:
            self = .unsupported
        }
    }

    var label: String {
        switch self {
        case .notDetermined:
            "Nie pytano"
        case .denied:
            "Brak zgody"
        case .unsupported:
            "Niedostępny"
        case .authorized:
            "Zgoda"
        }
    }
}

struct SpeechVoiceCatalog: Equatable {
    let voices: [SpeechVoiceOption]
    let personalVoiceAuthorization: SpeechPersonalVoiceAuthorization

    var systemVoices: [SpeechVoiceOption] {
        sortedVoices(voices.filter { !$0.isPersonalVoice })
    }

    var personalVoices: [SpeechVoiceOption] {
        guard personalVoiceAuthorization == .authorized else { return [] }
        return sortedVoices(voices.filter(\.isPersonalVoice))
    }

    var personalVoiceStatusLabel: String {
        if personalVoiceAuthorization == .authorized, personalVoices.isEmpty {
            return "Zgoda, ale brak głosu"
        }
        return personalVoiceAuthorization.label
    }

    static func current() -> SpeechVoiceCatalog {
        SpeechVoiceCatalog(
            voices: AVSpeechSynthesisVoice.speechVoices().map(SpeechVoiceOption.init(voice:)),
            personalVoiceAuthorization: SpeechPersonalVoiceAuthorization(AVSpeechSynthesizer.personalVoiceAuthorizationStatus)
        )
    }

    static func requestPersonalVoiceAuthorization() async -> SpeechPersonalVoiceAuthorization {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: SpeechPersonalVoiceAuthorization(status))
            }
        }
    }

    func selectedOption(for preference: SpeechVoicePreference) -> SpeechVoiceOption? {
        switch preference.mode {
        case .polishDefault:
            return defaultSystemVoice
        case .selectedVoice:
            if let identifier = preference.voiceIdentifier,
               let selected = systemVoices.first(where: { $0.id == identifier }) {
                return selected
            }
            return defaultSystemVoice
        case .personalVoice:
            if let identifier = preference.voiceIdentifier,
               let selected = personalVoices.first(where: { $0.id == identifier }) {
                return selected
            }
            return personalVoices.first ?? defaultSystemVoice
        }
    }

    func fallbackMessage(for preference: SpeechVoicePreference) -> String? {
        guard preference.mode != .polishDefault else { return nil }
        guard let identifier = preference.voiceIdentifier else {
            if preference.mode == .personalVoice, personalVoiceAuthorization == .authorized, personalVoices.isEmpty {
                return "Nie znaleziono Personal Voice. Utwórz głos w Ustawieniach iOS, a potem odśwież tę kartę."
            }
            return "Nie wybrano głosu. Pavbot użyje polskiego głosu domyślnego."
        }
        guard selectedOption(for: preference)?.id == identifier else {
            return "Wybrany głos nie jest dostępny na tym urządzeniu. Pavbot użyje polskiego głosu domyślnego."
        }
        return nil
    }

    var defaultSystemVoice: SpeechVoiceOption? {
        let polishVoices = systemVoices.filter { $0.language == "pl-PL" || $0.language.hasPrefix("pl") }
        guard !polishVoices.isEmpty else {
            return systemVoices.first
        }

        let preferred = polishVoices.sorted { lhs, rhs in
            let lhsScore = polishVoicePriority(for: lhs)
            let rhsScore = polishVoicePriority(for: rhs)
            if lhsScore == rhsScore {
                if lhs.quality == rhs.quality { return false }
                return voiceQualityPriority(lhs.quality) > voiceQualityPriority(rhs.quality)
            }
            return lhsScore > rhsScore
        }
        return preferred.first ?? polishVoices.first
    }

    private func sortedVoices(_ options: [SpeechVoiceOption]) -> [SpeechVoiceOption] {
        options.sorted { lhs, rhs in
            let lhsPriority = languagePriority(lhs.language)
            let rhsPriority = languagePriority(rhs.language)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func languagePriority(_ language: String) -> Int {
        if language == "pl-PL" { return 0 }
        if language.hasPrefix("pl") { return 1 }
        if language.hasPrefix("en") { return 2 }
        return 3
    }

    private func polishVoicePriority(for option: SpeechVoiceOption) -> Int {
        let signature = "\(option.name) \(option.id)".lowercased()
        var score = 0

        if signature.contains("zosia") || signature.contains("zośia") {
            score += 700
        }

        if signature.contains("extended") || signature.contains("rozszerz") {
            score += 120
        }

        score += voiceQualityPriority(option.quality)
        if option.language == "pl-PL" {
            score += 30
        }

        return score
    }

    private func voiceQualityPriority(_ quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium:
            90
        case .enhanced:
            70
        case .default:
            40
        @unknown default:
            20
        }
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

    private let synthesizer: SpeechSynthesizing
    private let audioSession: SpeechAudioSessionConfiguring
    private let enableSpeech: Bool
    private let rateDefaults: UserDefaults
    private let voiceProvider: () -> AVSpeechSynthesisVoice?
    private weak var audioCoordinator: PavbotAudioSessionCoordinator?
    private var audioSource: PavbotAudioActivitySource?
    private var audioTopic: String
    private var currentTitle: String?
    private var currentText: String?
    private var currentDestination: PavbotAudioDestination?
    private var currentKeyNotes: [String] = []
    private var currentTabLabel: String?
    private var segmentStartDate: Date?
    private var segmentStartElapsed = 0.0
    private var timer: Timer?
    private var playbackSessionID = UUID()
    private var currentUtterance: AVSpeechUtterance?
    private var currentUtteranceSessionID: UUID?
    private var currentSegmentWordOffset = 0

    init(
        enableSpeech: Bool = true,
        synthesizer: SpeechSynthesizing = AVSpeechSynthesizer(),
        audioSession: SpeechAudioSessionConfiguring = SystemSpeechAudioSession(),
        rateDefaults: UserDefaults = .standard,
        audioCoordinator: PavbotAudioSessionCoordinator? = nil,
        audioSource: PavbotAudioActivitySource? = nil,
        audioTopic: String = "Pavbot",
        voiceProvider: @escaping () -> AVSpeechSynthesisVoice? = { SpeechVoiceSettings.resolvedVoice() }
    ) {
        self.enableSpeech = enableSpeech
        self.synthesizer = synthesizer
        self.audioSession = audioSession
        self.rateDefaults = rateDefaults
        self.audioCoordinator = audioCoordinator
        self.audioSource = audioSource
        self.audioTopic = audioTopic
        self.voiceProvider = voiceProvider
        self.speechRate = MobileNewsSpeechRate.saved(in: rateDefaults)
        super.init()
        synthesizer.delegate = self
    }

    func configureAudioCoordinator(
        _ coordinator: PavbotAudioSessionCoordinator,
        source: PavbotAudioActivitySource,
        topic: String
    ) {
        audioCoordinator = coordinator
        audioSource = source
        audioTopic = topic
    }

    func play(
        itemID: String,
        title: String,
        text: String,
        destination: PavbotAudioDestination? = nil,
        keyNotes: [String] = [],
        tabLabel: String? = nil
    ) {
        if currentItemID == itemID, playbackState == .paused {
            resume()
            return
        }

        if currentItemID == itemID, playbackState == .playing {
            pause()
            return
        }

        start(
            itemID: itemID,
            title: title,
            text: text,
            segmentIndex: 0,
            destination: destination,
            keyNotes: keyNotes,
            tabLabel: tabLabel
        )
    }

    func start(
        itemID: String,
        title: String,
        text: String,
        segmentIndex: Int = 0,
        preservedElapsed: Double? = nil,
        wordOffset: Int = 0,
        startPaused: Bool = false,
        destination: PavbotAudioDestination? = nil,
        keyNotes: [String] = [],
        tabLabel: String? = nil
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

        let previousAudioSessionID = currentAudioSessionID
        let nextAudioSessionID = audioSessionID(itemID: itemID)
        stopSynthesizerForRestart()
        if let previousAudioSessionID, previousAudioSessionID != nextAudioSessionID {
            audioCoordinator?.deactivate(sessionID: previousAudioSessionID)
        }

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
        currentDestination = destination
        currentKeyNotes = keyNotes
        currentTabLabel = tabLabel
        timeline = newTimeline
        currentSegmentIndex = min(max(segmentIndex, 0), newTimeline.segments.count - 1)
        currentSegmentWordOffset = safeWordOffset(wordOffset, in: newTimeline.segment(at: currentSegmentIndex))
        let segmentStart = newTimeline.segment(at: currentSegmentIndex)?.estimatedStart ?? 0
        estimatedElapsed = min(max(preservedElapsed ?? segmentStart, 0), newTimeline.estimatedDuration)
        playbackState = startPaused ? .paused : .playing
        errorMessage = nil
        activateAudioCoordinator(isPlaying: !startPaused)
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
            startPaused: wasPaused,
            destination: currentDestination,
            keyNotes: currentKeyNotes,
            tabLabel: currentTabLabel
        )
    }

    func utteranceRate(for rate: MobileNewsSpeechRate) -> Float {
        AVSpeechUtteranceDefaultSpeechRate * rate.multiplier
    }

    func seek(toSegmentIndex index: Int) {
        guard let currentItemID, let currentTitle, let currentText, let timeline else { return }
        let safeIndex = min(max(index, 0), max(timeline.segments.count - 1, 0))
        start(
            itemID: currentItemID,
            title: currentTitle,
            text: currentText,
            segmentIndex: safeIndex,
            destination: currentDestination,
            keyNotes: currentKeyNotes,
            tabLabel: currentTabLabel
        )
    }

    func seek(to seconds: Double) {
        guard let currentItemID, let currentTitle, let currentText, let timeline else { return }
        let safeSeconds = min(max(seconds, 0), max(timeline.estimatedDuration, 0))
        let safeProgress = timeline.estimatedDuration > 0 ? safeSeconds / timeline.estimatedDuration : 0
        let segmentIndex = timeline.segmentIndex(forProgress: safeProgress)
        guard let segment = timeline.segment(at: segmentIndex) else { return }
        start(
            itemID: currentItemID,
            title: currentTitle,
            text: currentText,
            segmentIndex: segmentIndex,
            preservedElapsed: safeSeconds,
            wordOffset: wordOffset(in: segment, at: safeSeconds),
            startPaused: playbackState == .paused,
            destination: currentDestination,
            keyNotes: currentKeyNotes,
            tabLabel: currentTabLabel
        )
    }

    func skip(by seconds: Double) {
        updateEstimatedElapsed()
        seek(to: estimatedElapsed + seconds)
    }

    func seek(toProgress progress: Double) {
        guard let timeline else { return }
        seek(to: timeline.estimatedDuration * min(max(progress, 0), 1))
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
        updateAudioCoordinator()
    }

    func resume() {
        guard playbackState == .paused else { return }
        if currentUtterance == nil {
            playbackState = .playing
            activateAudioCoordinator(isPlaying: true)
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
        activateAudioCoordinator(isPlaying: true)
    }

    func stop() {
        stop(notifyCoordinator: true)
    }

    private func stop(notifyCoordinator: Bool) {
        let sessionID = currentAudioSessionID
        playbackSessionID = UUID()
        playbackState = .stopping
        currentUtterance = nil
        if enableSpeech, synthesizer.isSpeaking || synthesizer.isPaused {
            _ = synthesizer.stopSpeaking(at: .immediate)
        }
        resetPlaybackState(finalElapsed: 0, keepError: false)
        if notifyCoordinator, let sessionID {
            audioCoordinator?.deactivate(sessionID: sessionID)
        }
        audioSession.deactivateAfterSpeech()
    }

    private func stopFromCoordinator() {
        stop(notifyCoordinator: false)
    }

    private func resetPlaybackState(finalElapsed: Double, keepError: Bool) {
        timer?.invalidate()
        timer = nil
        currentItemID = nil
        currentTitle = nil
        currentText = nil
        currentDestination = nil
        currentKeyNotes = []
        currentTabLabel = nil
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
        utterance.voice = voiceProvider() ?? AVSpeechSynthesisVoice(language: "pl-PL")
        if utterance.voice == nil {
            errorMessage = "Brak wybranego głosu TTS na urządzeniu. Sprawdź ustawienia języka, dostępności i Personal Voice w iOS."
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
        updateAudioCoordinator()
    }

    private func stopSynthesizerForRestart() {
        guard enableSpeech, synthesizer.isSpeaking || synthesizer.isPaused else { return }
        currentUtterance = nil
        currentUtteranceSessionID = nil
        _ = synthesizer.stopSpeaking(at: .immediate)
    }

    private func finishPlayback() {
        let sessionID = currentAudioSessionID
        let finalDuration = timeline?.estimatedDuration ?? estimatedElapsed
        resetPlaybackState(finalElapsed: finalDuration, keepError: true)
        if let sessionID {
            audioCoordinator?.deactivate(sessionID: sessionID, isFinished: true)
        }
        audioSession.deactivateAfterSpeech()
    }

    private var currentAudioSessionID: String? {
        guard let currentItemID else { return nil }
        return audioSessionID(itemID: currentItemID)
    }

    private func audioSessionID(itemID: String) -> String {
        "\(audioSource?.rawValue ?? "speech"):\(itemID)"
    }

    private func activateAudioCoordinator(isPlaying: Bool) {
        guard let audioCoordinator, let audioSource, let currentItemID, let currentTitle else { return }
        let session = PavbotAudioPlaybackSession(
            id: audioSessionID(itemID: currentItemID),
            source: audioSource,
            title: currentTitle,
            topic: audioTopic,
            routeID: currentItemID,
            destination: currentDestination,
            tabLabel: currentTabLabel,
            keyNotes: currentKeyNotes
        )
        audioCoordinator.activate(
            session,
            controls: PavbotAudioPlaybackControls(
                pause: { [weak self] in self?.pause() },
                resume: { [weak self] in self?.resume() },
                stop: { [weak self] in self?.stopFromCoordinator() },
                seek: { [weak self] seconds in self?.seek(to: seconds) },
                skip: { [weak self] seconds in self?.skip(by: seconds) }
            ),
            elapsed: estimatedElapsed,
            duration: estimatedDuration,
            isPlaying: isPlaying
        )
    }

    private func updateAudioCoordinator() {
        guard let currentAudioSessionID else { return }
        audioCoordinator?.update(
            sessionID: currentAudioSessionID,
            elapsed: estimatedElapsed,
            duration: estimatedDuration,
            isPlaying: playbackState == .playing
        )
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
