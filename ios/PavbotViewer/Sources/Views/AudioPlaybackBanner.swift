import SwiftUI

enum AudioPlaybackBannerLayout {
    static let bottomClearance: CGFloat = 20
}

struct AudioPlaybackBannerSnapshot: Equatable {
    let title: String
    let topic: String
    let progress: Double
    let isPlaying: Bool
    let playPauseSystemImage: String
    let timeLabel: String

    @MainActor
    init?(service: AudioPlaybackService) {
        guard let artifact = service.currentArtifact else { return nil }
        title = artifact.title
        topic = artifact.topic
        isPlaying = service.isPlaying
        playPauseSystemImage = service.isPlaying ? "pause.fill" : "play.fill"
        progress = Self.progress(currentTime: service.currentTime, duration: service.duration)
        timeLabel = Self.timeLabel(currentTime: service.currentTime, duration: service.duration)
    }

    private static func progress(currentTime: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    private static func timeLabel(currentTime: Double, duration: Double) -> String {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return "00:00" }
        return "\(format(currentTime)) / \(format(duration))"
    }

    private static func format(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct AudioPlaybackBanner: View {
    @Environment(AudioPlaybackService.self) private var audioPlayback

    var body: some View {
        if let snapshot = AudioPlaybackBannerSnapshot(service: audioPlayback) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 38, height: 38)
                    .background(Color.purple.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(snapshot.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(snapshot.timeLabel)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text(snapshot.topic)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressView(value: snapshot.progress)
                            .progressViewStyle(.linear)
                            .tint(.purple)
                    }
                }

                Button {
                    snapshot.isPlaying ? audioPlayback.pause() : audioPlayback.resume()
                } label: {
                    Image(systemName: snapshot.playPauseSystemImage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.purple, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(snapshot.isPlaying ? "Pauza audio" : "Odtwórz audio")

                Button {
                    audioPlayback.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zamknij odtwarzanie audio")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.purple.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, AudioPlaybackBannerLayout.bottomClearance)
            .accessibilityElement(children: .combine)
        }
    }
}
