import ActivityKit
import AVFoundation
import Foundation
import MediaPlayer
import Observation

enum PavbotAudioDestination: Equatable, Hashable {
    case mobileNewsArticle(topic: ReportTopicKind, articleID: String)
    case researchArticle(topic: ReportTopicKind, articleID: String)
}

struct PavbotAudioPlaybackSession: Equatable {
    let id: String
    let source: PavbotAudioActivitySource
    let title: String
    let topic: String
    let routeID: String
    var destination: PavbotAudioDestination? = nil
    var routePath = ""
    var tabLabel: String? = nil
    var keyNotes: [String] = []
}

enum PavbotAudioRemoteCommand: Equatable {
    case play
    case pause
    case togglePlayPause
    case seek(to: Double)
    case skip(by: Double)
}

@MainActor
protocol PavbotSystemAudioIntegrating: AnyObject {
    func activatePlaybackSession() throws
    func deactivatePlaybackSession()
    func publishNowPlaying(_ info: [String: Any]?)
    func configureRemoteCommands(handler: @escaping @MainActor (PavbotAudioRemoteCommand) -> MPRemoteCommandHandlerStatus)
    func resetRemoteCommands()
}

@MainActor
final class SystemPavbotAudioIntegration: PavbotSystemAudioIntegrating {
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []

    func activatePlaybackSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio, options: [])
        try session.setActive(true)
    }

    func deactivatePlaybackSession() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func publishNowPlaying(_ info: [String: Any]?) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func configureRemoteCommands(handler: @escaping @MainActor (PavbotAudioRemoteCommand) -> MPRemoteCommandHandlerStatus) {
        resetRemoteCommands()

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.preferredIntervals = [15]

        addTarget(commandCenter.playCommand) { _ in
            handler(.play)
        }
        addTarget(commandCenter.pauseCommand) { _ in
            handler(.pause)
        }
        addTarget(commandCenter.togglePlayPauseCommand) { _ in
            handler(.togglePlayPause)
        }
        addTarget(commandCenter.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return handler(.seek(to: event.positionTime))
        }
        addTarget(commandCenter.skipForwardCommand) { _ in
            handler(.skip(by: 15))
        }
        addTarget(commandCenter.skipBackwardCommand) { _ in
            handler(.skip(by: -15))
        }
    }

    func resetRemoteCommands() {
        for commandTarget in commandTargets {
            commandTarget.command.removeTarget(commandTarget.target)
        }
        commandTargets.removeAll()
    }

    private func addTarget(
        _ command: MPRemoteCommand,
        handler: @escaping @MainActor (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget { event in
            Task { @MainActor in
                _ = handler(event)
            }
            return .success
        }
        commandTargets.append((command, target))
    }
}

struct PavbotAudioPlaybackControls {
    let pause: @MainActor () -> Void
    let resume: @MainActor () -> Void
    let stop: @MainActor () -> Void
    let seek: @MainActor (Double) -> Void
    let skip: @MainActor (Double) -> Void

    init(
        pause: @escaping @MainActor () -> Void,
        resume: @escaping @MainActor () -> Void,
        stop: @escaping @MainActor () -> Void,
        seek: @escaping @MainActor (Double) -> Void = { _ in },
        skip: @escaping @MainActor (Double) -> Void = { _ in }
    ) {
        self.pause = pause
        self.resume = resume
        self.stop = stop
        self.seek = seek
        self.skip = skip
    }
}

struct PavbotAudioSessionSnapshot: Equatable {
    let source: PavbotAudioActivitySource
    let title: String
    let topic: String
    let progress: Double
    let isPlaying: Bool
    let playPauseSystemImage: String
    let sourceSystemImage: String
    let timeLabel: String
    let elapsed: Double
    let duration: Double
    let destination: PavbotAudioDestination?
    let tabLabel: String?
    let keyNotes: [String]

    init(session: PavbotAudioPlaybackSession, elapsed: Double, duration: Double, isPlaying: Bool) {
        source = session.source
        title = session.title
        topic = session.topic
        destination = session.destination
        tabLabel = session.tabLabel
        keyNotes = session.keyNotes
        self.elapsed = elapsed
        self.duration = duration
        self.isPlaying = isPlaying
        progress = Self.progress(currentTime: elapsed, duration: duration)
        playPauseSystemImage = isPlaying ? "pause.fill" : "play.fill"
        sourceSystemImage = session.source.compactSystemImage
        timeLabel = Self.timeLabel(currentTime: elapsed, duration: duration)
    }

    static func progress(currentTime: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    static func timeLabel(currentTime: Double, duration: Double) -> String {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return "00:00" }
        return "\(format(currentTime)) / \(format(duration))"
    }

    private static func format(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

@MainActor
@Observable
final class PavbotAudioSessionCoordinator {
    private static let liveActivityRelevanceScore = 100.0
    private static let finishedActivityDismissalDelay: TimeInterval = 120

    private(set) var currentSnapshot: PavbotAudioSessionSnapshot?

    @ObservationIgnored private let enableLiveActivities: Bool
    @ObservationIgnored private let enableSystemIntegrations: Bool
    @ObservationIgnored private let systemAudio: PavbotSystemAudioIntegrating
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var activeSession: PavbotAudioPlaybackSession?
    @ObservationIgnored private var controls: PavbotAudioPlaybackControls?
    @ObservationIgnored private var activity: Activity<PavbotAudioActivityAttributes>?
    @ObservationIgnored private var lastActivityUpdate = Date.distantPast
    @ObservationIgnored private var systemAudioSessionActive = false
    @ObservationIgnored private var shouldResumeAfterInterruption = false
    @ObservationIgnored private var notificationObservers: [NSObjectProtocol] = []

    init(
        enableLiveActivities: Bool = true,
        enableSystemIntegrations: Bool = true,
        systemAudio: PavbotSystemAudioIntegrating? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.enableLiveActivities = enableLiveActivities
        self.enableSystemIntegrations = enableSystemIntegrations
        self.systemAudio = systemAudio ?? SystemPavbotAudioIntegration()
        self.notificationCenter = notificationCenter
        if enableSystemIntegrations {
            configureRemoteCommands()
            observeAudioSessionNotifications()
        }
    }

    deinit {
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }
        Task { @MainActor [systemAudio] in
            systemAudio.resetRemoteCommands()
        }
    }

    func activate(
        _ session: PavbotAudioPlaybackSession,
        controls: PavbotAudioPlaybackControls,
        elapsed: Double = 0,
        duration: Double = 0,
        isPlaying: Bool = true
    ) {
        if let activeSession, activeSession.id != session.id {
            let previousControls = self.controls
            let previousSnapshot = currentSnapshot
            self.activeSession = nil
            self.controls = nil
            currentSnapshot = nil
            endLiveActivity(snapshot: previousSnapshot, isFinished: false)
            clearSystemAudioState()
            previousControls?.stop()
        }

        activeSession = session
        self.controls = controls
        currentSnapshot = PavbotAudioSessionSnapshot(
            session: session,
            elapsed: elapsed,
            duration: duration,
            isPlaying: isPlaying
        )
        if isPlaying {
            activateSystemAudioSessionIfNeeded()
        }
        publishNowPlayingInfo()
        updateLiveActivity(force: true)
    }

    func update(sessionID: String, elapsed: Double, duration: Double, isPlaying: Bool) {
        guard let activeSession, activeSession.id == sessionID else { return }
        currentSnapshot = PavbotAudioSessionSnapshot(
            session: activeSession,
            elapsed: elapsed,
            duration: duration,
            isPlaying: isPlaying
        )
        if isPlaying {
            activateSystemAudioSessionIfNeeded()
        }
        publishNowPlayingInfo()
        updateLiveActivity(force: false)
    }

    func deactivate(sessionID: String, isFinished: Bool = false) {
        guard activeSession?.id == sessionID else { return }
        let snapshot = currentSnapshot
        activeSession = nil
        controls = nil
        currentSnapshot = nil
        endLiveActivity(snapshot: snapshot, isFinished: isFinished)
        clearSystemAudioState()
    }

    func pauseActive() {
        controls?.pause()
    }

    func resumeActive() {
        controls?.resume()
    }

    func stopActive() {
        guard activeSession != nil || controls != nil else { return }
        let stopControls = controls
        let snapshot = currentSnapshot
        activeSession = nil
        controls = nil
        currentSnapshot = nil
        endLiveActivity(snapshot: snapshot, isFinished: false)
        clearSystemAudioState()
        Task { @MainActor in
            await Task.yield()
            stopControls?.stop()
        }
    }

    func seekActive(to seconds: Double) {
        controls?.seek(seconds)
    }

    func skipActive(by seconds: Double) {
        controls?.skip(seconds)
    }

    func performRemoteCommand(_ command: PavbotAudioRemoteCommand) -> MPRemoteCommandHandlerStatus {
        guard controls != nil else { return .noSuchContent }
        switch command {
        case .play:
            resumeActive()
        case .pause:
            pauseActive()
        case .togglePlayPause:
            if currentSnapshot?.isPlaying == true {
                pauseActive()
            } else {
                resumeActive()
            }
        case .seek(let seconds):
            seekActive(to: seconds)
        case .skip(let seconds):
            skipActive(by: seconds)
        }
        return .success
    }

    func handleAudioSessionInterruptionBegan() {
        shouldResumeAfterInterruption = currentSnapshot?.isPlaying == true
        guard shouldResumeAfterInterruption else { return }
        pauseActive()
        setActivePlayback(isPlaying: false)
    }

    func handleAudioSessionInterruptionEnded(shouldResume: Bool) {
        defer { shouldResumeAfterInterruption = false }
        guard shouldResumeAfterInterruption, shouldResume else { return }
        activateSystemAudioSessionIfNeeded()
        resumeActive()
    }

    func handleOldAudioRouteUnavailable() {
        guard currentSnapshot?.isPlaying == true else { return }
        pauseActive()
        setActivePlayback(isPlaying: false)
    }

    func handleMediaServicesWereReset() {
        guard enableSystemIntegrations else { return }
        systemAudioSessionActive = false
        systemAudio.publishNowPlaying(nil)
        configureRemoteCommands()
        if currentSnapshot?.isPlaying == true {
            activateSystemAudioSessionIfNeeded()
        }
        publishNowPlayingInfo()
    }

    private func configureRemoteCommands() {
        systemAudio.configureRemoteCommands { [weak self] command in
            self?.performRemoteCommand(command) ?? .noSuchContent
        }
    }

    private func observeAudioSessionNotifications() {
        let interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioSessionInterruption(notification)
            }
        }
        let routeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioRouteChange(notification)
            }
        }
        let resetObserver = notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesWereReset()
            }
        }
        notificationObservers = [interruptionObserver, routeObserver, resetObserver]
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            handleAudioSessionInterruptionBegan()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            handleAudioSessionInterruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
            reason == .oldDeviceUnavailable
        else { return }
        handleOldAudioRouteUnavailable()
    }

    private func activateSystemAudioSessionIfNeeded() {
        guard enableSystemIntegrations, !systemAudioSessionActive else { return }
        do {
            try systemAudio.activatePlaybackSession()
            systemAudioSessionActive = true
        } catch {
            systemAudioSessionActive = false
        }
    }

    private func clearSystemAudioState() {
        guard enableSystemIntegrations else { return }
        systemAudio.publishNowPlaying(nil)
        if systemAudioSessionActive {
            systemAudio.deactivatePlaybackSession()
            systemAudioSessionActive = false
        }
    }

    private func publishNowPlayingInfo() {
        guard enableSystemIntegrations, let currentSnapshot else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentSnapshot.title,
            MPMediaItemPropertyArtist: "Pavbot",
            MPMediaItemPropertyAlbumTitle: currentSnapshot.topic,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentSnapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: currentSnapshot.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if currentSnapshot.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = currentSnapshot.duration
        }
        systemAudio.publishNowPlaying(info)
    }

    private func setActivePlayback(isPlaying: Bool) {
        guard let activeSession, let currentSnapshot else { return }
        self.currentSnapshot = PavbotAudioSessionSnapshot(
            session: activeSession,
            elapsed: currentSnapshot.elapsed,
            duration: currentSnapshot.duration,
            isPlaying: isPlaying
        )
        publishNowPlayingInfo()
        updateLiveActivity(force: true)
    }

    private func updateLiveActivity(force: Bool) {
        guard enableLiveActivities, let activeSession, let currentSnapshot else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastActivityUpdate) >= 5 else { return }
        lastActivityUpdate = now

        let state = PavbotAudioActivityAttributes.ContentState(
            title: currentSnapshot.title,
            elapsed: currentSnapshot.elapsed,
            duration: currentSnapshot.duration,
            isPlaying: currentSnapshot.isPlaying,
            updatedAt: now,
            tabLabel: currentSnapshot.tabLabel,
            keyNotes: currentSnapshot.keyNotes
        )
        let staleDate = now.addingTimeInterval(60)
        let content = ActivityContent(
            state: state,
            staleDate: staleDate,
            relevanceScore: Self.liveActivityRelevanceScore
        )

        if let activity {
            Task {
                await activity.update(content)
            }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = PavbotAudioActivityAttributes(
            artifactID: activeSession.routeID,
            artifactPath: activeSession.routePath,
            topic: activeSession.topic,
            source: activeSession.source
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            // Live Activities are supportive UI; audio playback should continue if ActivityKit refuses a request.
        }
    }

    private func endLiveActivity(snapshot: PavbotAudioSessionSnapshot?, isFinished: Bool) {
        guard let activity else { return }
        self.activity = nil
        let state = PavbotAudioActivityAttributes.ContentState(
            title: snapshot?.title ?? "Pavbot audio",
            elapsed: snapshot?.elapsed ?? 0,
            duration: snapshot?.duration ?? 0,
            isPlaying: false,
            updatedAt: Date(),
            tabLabel: snapshot?.tabLabel,
            keyNotes: snapshot?.keyNotes ?? [],
            isFinished: isFinished
        )
        let content = ActivityContent(
            state: state,
            staleDate: nil,
            relevanceScore: Self.liveActivityRelevanceScore
        )
        Task {
            if isFinished {
                await activity.end(content, dismissalPolicy: .after(Date().addingTimeInterval(Self.finishedActivityDismissalDelay)))
            } else {
                await activity.end(content, dismissalPolicy: .after(Date()))
            }
        }
    }
}

@MainActor
@Observable
final class AudioPlaybackService {
    private(set) var currentArtifact: PavbotArtifact?
    private(set) var currentURL: URL?
    private(set) var isPlaying = false
    private(set) var currentTime = 0.0
    private(set) var duration = 0.0
    private(set) var errorMessage: String?

    @ObservationIgnored private let enableSystemIntegrations: Bool
    @ObservationIgnored private let ownedAudioCoordinator: PavbotAudioSessionCoordinator?
    @ObservationIgnored private weak var audioCoordinator: PavbotAudioSessionCoordinator?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var durationTask: Task<Void, Never>?

    init(enableSystemIntegrations: Bool = true, audioCoordinator: PavbotAudioSessionCoordinator? = nil) {
        self.enableSystemIntegrations = enableSystemIntegrations
        if let audioCoordinator {
            self.ownedAudioCoordinator = nil
            self.audioCoordinator = audioCoordinator
        } else if enableSystemIntegrations {
            let coordinator = PavbotAudioSessionCoordinator()
            self.ownedAudioCoordinator = coordinator
            self.audioCoordinator = coordinator
        } else {
            self.ownedAudioCoordinator = nil
            self.audioCoordinator = nil
        }
    }

    func load(artifact: PavbotArtifact, url: URL) {
        guard currentArtifact?.id != artifact.id || currentURL != url || player == nil else { return }

        resetPlayer(clearCurrentItem: false, endActivity: true)
        currentArtifact = artifact
        currentURL = url
        currentTime = 0
        duration = 0
        errorMessage = nil

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        addPeriodicTimeObserver(to: newPlayer)
        loadDuration(from: item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finishPlayback()
            }
        }
        activateCoordinator(isPlaying: isPlaying)
    }

    func play(artifact: PavbotArtifact, url: URL) {
        load(artifact: artifact, url: url)
        resume()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateCoordinator()
    }

    func resume() {
        guard let player else { return }
        activateCoordinator(isPlaying: true)
        player.play()
        isPlaying = true
        updateCoordinator()
    }

    func seek(to seconds: Double) {
        let clampedSeconds = min(max(seconds, 0), max(duration, 0))
        let target = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = clampedSeconds
                self?.updateCoordinator()
            }
        }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func stop() {
        stop(notifyCoordinator: true)
    }

    private func stop(notifyCoordinator: Bool) {
        let sessionID = currentAudioSessionID
        player?.pause()
        isPlaying = false
        resetPlayer(clearCurrentItem: true, endActivity: true)
        if notifyCoordinator, let sessionID {
            audioCoordinator?.deactivate(sessionID: sessionID)
        }
    }

    private func stopFromCoordinator() {
        stop(notifyCoordinator: false)
    }

    private func addPeriodicTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                }
                if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateCoordinator()
            }
        }
    }

    private func loadDuration(from item: AVPlayerItem) {
        durationTask = Task { [weak self] in
            do {
                let loadedDuration = try await item.asset.load(.duration)
                let seconds = loadedDuration.seconds
                guard seconds.isFinite, seconds > 0 else { return }
                await MainActor.run {
                    self?.duration = seconds
                    self?.updateCoordinator()
                }
            } catch {
                await MainActor.run {
                    self?.duration = 0
                }
            }
        }
    }

    private func finishPlayback() {
        isPlaying = false
        currentTime = 0
        player?.seek(to: .zero)
        if let currentAudioSessionID {
            audioCoordinator?.deactivate(sessionID: currentAudioSessionID, isFinished: true)
        }
    }

    private func resetPlayer(clearCurrentItem: Bool, endActivity: Bool) {
        let sessionID = currentAudioSessionID
        durationTask?.cancel()
        durationTask = nil
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player = nil
        if endActivity, let sessionID {
            audioCoordinator?.deactivate(sessionID: sessionID)
        }
        if clearCurrentItem {
            currentArtifact = nil
            currentURL = nil
            currentTime = 0
            duration = 0
            errorMessage = nil
        }
    }

    private var currentAudioSessionID: String? {
        guard let currentArtifact, let currentURL else { return nil }
        return audioSessionID(artifact: currentArtifact, url: currentURL)
    }

    private func audioSessionID(artifact: PavbotArtifact, url: URL) -> String {
        "mp3:\(artifact.id):\(url.absoluteString)"
    }

    private func activateCoordinator(isPlaying: Bool) {
        guard let currentArtifact, let currentURL else { return }
        let session = PavbotAudioPlaybackSession(
            id: audioSessionID(artifact: currentArtifact, url: currentURL),
            source: .mp3Podcast,
            title: currentArtifact.title,
            topic: currentArtifact.topic,
            routeID: currentArtifact.id,
            routePath: currentArtifact.path
        )
        audioCoordinator?.activate(
            session,
            controls: PavbotAudioPlaybackControls(
                pause: { [weak self] in self?.pause() },
                resume: { [weak self] in self?.resume() },
                stop: { [weak self] in self?.stopFromCoordinator() },
                seek: { [weak self] seconds in self?.seek(to: seconds) },
                skip: { [weak self] seconds in self?.skip(by: seconds) }
            ),
            elapsed: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func updateCoordinator() {
        guard let currentAudioSessionID else { return }
        audioCoordinator?.update(
            sessionID: currentAudioSessionID,
            elapsed: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }
}
