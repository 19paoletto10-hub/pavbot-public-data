import AVFoundation
import PDFKit
import SwiftUI

struct ArtifactDetailView: View {
    @Environment(ManifestStore.self) private var store

    let artifact: PavbotArtifact

    var body: some View {
        VStack(spacing: 0) {
            ArtifactMetadataView(artifact: artifact)
            Divider()
            ArtifactPreviewView(artifact: artifact)
        }
        .navigationTitle(artifact.type.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = artifact.resolvedURL(manifestURL: URL(string: store.manifestURLString)) {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open raw file")
                }
            }
        }
    }
}

private struct ArtifactMetadataView: View {
    let artifact: PavbotArtifact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ArtifactIconBadge(kind: artifact.viewerKind)

                VStack(alignment: .leading, spacing: 8) {
                    Text(artifact.title)
                        .font(.headline)
                    HStack {
                        StatusBadge(text: artifact.type.label, systemImage: artifact.viewerKind.systemImage, tint: artifact.viewerKind.tint)
                        StatusBadge(text: artifact.displayDate, systemImage: "calendar", tint: .secondary)
                    }
                    Text(artifact.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

private struct ArtifactPreviewView: View {
    @Environment(ManifestStore.self) private var store

    let artifact: PavbotArtifact

    var body: some View {
        if store.isUsingPlaceholderManifestURL && !artifact.url.hasPrefix("http") {
            ContentUnavailableView(
                "Configure GitHub raw URL",
                systemImage: "link",
                description: Text("This bundled manifest can list files immediately. Set the real public manifest URL in Settings to preview Markdown, PDFs, and audio.")
            )
            .padding()
        } else if let url = artifact.resolvedURL(manifestURL: URL(string: store.manifestURLString)) {
            switch artifact.viewerKind {
            case .markdown:
                RemoteTextPreview(url: url, monospaced: false)
            case .json:
                RemoteTextPreview(url: url, monospaced: true)
            case .pdf:
                RemotePDFPreview(url: url)
            case .audio:
                AudioPreview(url: url)
            case .file:
                Link(destination: url) {
                    Label("Open raw file", systemImage: "arrow.up.right.square")
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "No public URL",
                systemImage: "link.badge.plus",
                description: Text("Regenerate the manifest with PAVBOT_RAW_BASE_URL set to a public GitHub raw base URL.")
            )
        }
    }
}

private struct RemoteTextPreview: View {
    let url: URL
    let monospaced: Bool

    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let text):
                ScrollView {
                    Text(text)
                        .font(monospaced ? .system(.body, design: .monospaced) : .body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            case .failed(let message):
                ContentUnavailableView("Preview failed", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            let data = try await fetchRemoteData(from: url)
            state = .loaded(String(decoding: data, as: UTF8.self))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private enum LoadState: Equatable {
        case loading
        case loaded(String)
        case failed(String)
    }
}

private struct RemotePDFPreview: View {
    let url: URL

    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Loading PDF")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let data):
                PDFDocumentView(data: data)
            case .failed(let message):
                ContentUnavailableView("PDF failed", systemImage: "doc.richtext", description: Text(message))
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            let data = try await fetchRemoteData(from: url)
            state = .loaded(data)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private enum LoadState: Equatable {
        case loading
        case loaded(Data)
        case failed(String)
    }
}

private func fetchRemoteData(from url: URL) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(from: url)
    if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
        throw URLError(.badServerResponse)
    }
    return data
}

private struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(data: data)
    }
}

private struct AudioPreview: View {
    let url: URL

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var seekTime = 0.0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var durationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)

                Text("Podcast audio")
                    .font(.title3.weight(.semibold))
            }

            VStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { isSeeking ? seekTime : currentTime },
                        set: { value in
                            isSeeking = true
                            seekTime = value
                        }
                    ),
                    in: 0...max(duration, 1),
                    onEditingChanged: handleSeekEditing
                )
                .disabled(duration <= 0)
                .accessibilityLabel("Audio timeline")

                HStack {
                    Text(formatPlaybackTime(isSeeking ? seekTime : currentTime))
                    Spacer()
                    Text(duration > 0 ? formatPlaybackTime(duration) : "--:--")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Button {
                    togglePlayback()
                } label: {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)

                Link(destination: url) {
                    Label("Open raw audio", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            configurePlayerIfNeeded()
        }
        .onDisappear {
            stopAndCleanUp()
        }
    }

    private func togglePlayback() {
        configurePlayerIfNeeded()
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }

    private func configurePlayerIfNeeded() {
        guard player == nil else { return }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        addPeriodicTimeObserver(to: newPlayer)
        durationTask = Task {
            await loadDuration(from: item)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            isPlaying = false
            currentTime = 0
            seekTime = 0
            newPlayer.seek(to: .zero)
        }
    }

    private func loadDuration(from item: AVPlayerItem) async {
        do {
            let loadedDuration = try await item.asset.load(.duration)
            let seconds = loadedDuration.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            await MainActor.run {
                duration = seconds
            }
        } catch {
            await MainActor.run {
                duration = 0
            }
        }
    }

    private func addPeriodicTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            if seconds.isFinite, !isSeeking {
                currentTime = seconds
            }

            if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
        }
    }

    private func handleSeekEditing(_ editing: Bool) {
        if editing {
            isSeeking = true
            seekTime = currentTime
        } else {
            seek(to: seekTime)
            isSeeking = false
        }
    }

    private func seek(to seconds: Double) {
        let clampedSeconds = min(max(seconds, 0), max(duration, 0))
        let target = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            currentTime = clampedSeconds
            seekTime = clampedSeconds
        }
    }

    private func stopAndCleanUp() {
        player?.pause()
        isPlaying = false
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
    }
}

private func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let totalSeconds = Int(seconds.rounded())
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
