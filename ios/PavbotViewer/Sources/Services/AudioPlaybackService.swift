import ActivityKit
import AVFoundation
import Foundation
import MediaPlayer
import Observation

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
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var durationTask: Task<Void, Never>?
    @ObservationIgnored private var activity: Activity<PavbotAudioActivityAttributes>?
    @ObservationIgnored private var lastActivityUpdate = Date.distantPast

    init(enableSystemIntegrations: Bool = true) {
        self.enableSystemIntegrations = enableSystemIntegrations
        if enableSystemIntegrations {
            configureRemoteCommands()
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
        updateNowPlayingInfo()
    }

    func play(artifact: PavbotArtifact, url: URL) {
        load(artifact: artifact, url: url)
        resume()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        updateLiveActivity(force: true)
    }

    func resume() {
        guard let player else { return }
        configureAudioSession()
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
        updateLiveActivity(force: true)
    }

    func seek(to seconds: Double) {
        let clampedSeconds = min(max(seconds, 0), max(duration, 0))
        let target = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = clampedSeconds
                self?.updateNowPlayingInfo()
                self?.updateLiveActivity(force: true)
            }
        }
    }

    func stop() {
        player?.pause()
        isPlaying = false
        resetPlayer(clearCurrentItem: true, endActivity: true)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if enableSystemIntegrations {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func configureAudioSession() {
        guard enableSystemIntegrations else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            errorMessage = nil
        } catch {
            errorMessage = PavbotUserFacingError.audio(error.localizedDescription).message
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.resume() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying ? self.pause() : self.resume()
            }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: event.positionTime) }
            return .success
        }
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
                self.updateNowPlayingInfo()
                self.updateLiveActivity(force: false)
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
                    self?.updateNowPlayingInfo()
                    self?.updateLiveActivity(force: true)
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
        updateNowPlayingInfo()
        endLiveActivity()
    }

    private func resetPlayer(clearCurrentItem: Bool, endActivity: Bool) {
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
        if endActivity {
            endLiveActivity()
        }
        if clearCurrentItem {
            currentArtifact = nil
            currentURL = nil
            currentTime = 0
            duration = 0
            errorMessage = nil
        }
    }

    private func updateNowPlayingInfo() {
        guard enableSystemIntegrations, let currentArtifact else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentArtifact.title,
            MPMediaItemPropertyArtist: "Pavbot",
            MPMediaItemPropertyAlbumTitle: currentArtifact.topic,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateLiveActivity(force: Bool) {
        guard enableSystemIntegrations, let currentArtifact else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastActivityUpdate) >= 5 else { return }
        lastActivityUpdate = now

        let state = PavbotAudioActivityAttributes.ContentState(
            title: currentArtifact.title,
            elapsed: currentTime,
            duration: duration,
            isPlaying: isPlaying,
            updatedAt: now
        )

        if let activity {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)))
            }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = PavbotAudioActivityAttributes(
            artifactID: currentArtifact.id,
            artifactPath: currentArtifact.path,
            topic: currentArtifact.topic
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(60)),
                pushType: nil
            )
        } catch {
            errorMessage = PavbotUserFacingError.audio(error.localizedDescription).message
        }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        self.activity = nil
        let state = PavbotAudioActivityAttributes.ContentState(
            title: currentArtifact?.title ?? "Pavbot audio",
            elapsed: currentTime,
            duration: duration,
            isPlaying: false,
            updatedAt: Date()
        )
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
    }
}
