import SwiftUI

struct AudioTimelineControls: View {
    @Environment(AudioPlaybackService.self) private var audioPlayback
    @Environment(PavbotHaptics.self) private var haptics

    let artifact: PavbotArtifact
    let url: URL
    var sourceLinkTitle = "Otwórz audio źródłowe"

    @State private var seekTime = 0.0
    @State private var isSeeking = false

    private var isCurrentAudio: Bool {
        audioPlayback.currentArtifact?.id == artifact.id && audioPlayback.currentURL == url
    }

    private var displayedCurrentTime: Double {
        isCurrentAudio ? audioPlayback.currentTime : 0
    }

    private var displayedDuration: Double {
        isCurrentAudio ? audioPlayback.duration : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { isSeeking ? seekTime : displayedCurrentTime },
                        set: { value in
                            isSeeking = true
                            seekTime = value
                        }
                    ),
                    in: 0...max(displayedDuration, 1),
                    onEditingChanged: handleSeekEditing
                )
                .disabled(displayedDuration <= 0)
                .accessibilityLabel("Oś czasu audio")

                HStack {
                    Text(pavbotPlaybackTime(isSeeking ? seekTime : displayedCurrentTime))
                    Spacer()
                    Text(displayedDuration > 0 ? pavbotPlaybackTime(displayedDuration) : "--:--")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    togglePlayback()
                } label: {
                    Label(isCurrentAudio && audioPlayback.isPlaying ? "Pauza" : "Odtwórz", systemImage: isCurrentAudio && audioPlayback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)

                Link(destination: url) {
                    Label(sourceLinkTitle, systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage = audioPlayback.errorMessage, isCurrentAudio {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func togglePlayback() {
        if isCurrentAudio && audioPlayback.isPlaying {
            audioPlayback.pause()
        } else {
            audioPlayback.play(artifact: artifact, url: url)
        }
        haptics.play(.lightImpact)
    }

    private func handleSeekEditing(_ editing: Bool) {
        if editing {
            isSeeking = true
            seekTime = displayedCurrentTime
        } else {
            audioPlayback.seek(to: seekTime)
            isSeeking = false
            haptics.play(.selection)
        }
    }
}

func pavbotPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let totalSeconds = Int(seconds.rounded())
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
