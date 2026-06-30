import PDFKit
import SwiftUI

struct ArtifactDetailView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let artifact: PavbotArtifact

    var body: some View {
        VStack(spacing: 0) {
            ArtifactMetadataView(artifact: artifact)
            Divider()
            ArtifactPreviewView(artifact: artifact)
        }
        .frame(
            minWidth: usesLargeCanvas ? 720 : nil,
            idealWidth: usesLargeCanvas ? 980 : nil,
            maxWidth: .infinity,
            minHeight: usesLargeCanvas ? 620 : nil,
            maxHeight: .infinity
        )
        .background(Color(.systemGroupedBackground))
        .navigationTitle(artifact.type.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = artifact.resolvedURL(manifestURL: URL(string: store.manifestURLString)) {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Otwórz plik źródłowy")
                }
            }
        }
    }

    private var usesLargeCanvas: Bool {
        horizontalSizeClass == .regular || ProcessInfo.processInfo.isiOSAppOnMac
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
                "Skonfiguruj GitHub raw URL",
                systemImage: "link",
                description: Text("Manifest w aplikacji pokazuje pliki, ale do podglądu Markdown, PDF i audio potrzebny jest prawdziwy publiczny Manifest URL w ustawieniach.")
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
                AudioPreview(artifact: artifact, url: url)
            case .file:
                Link(destination: url) {
                    Label("Otwórz plik źródłowy", systemImage: "arrow.up.right.square")
                }
                .padding()
            }
        } else {
            ContentUnavailableView(
                "Brak publicznego URL",
                systemImage: "link.badge.plus",
                description: Text("Odśwież manifest z publicznym GitHub raw URL, aby aplikacja mogła otworzyć ten plik.")
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
                ProgressView("Wczytuję podgląd")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let text):
                ScrollView {
                    if monospaced {
                        Text(text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    } else {
                        MarkdownReportText(text: text)
                            .padding()
                    }
                }
            case .failed(let error):
                VStack(spacing: 14) {
                    PavbotStateView(error: error) {
                        Task { await load() }
                    }
                    Link(destination: url) {
                        Label("Otwórz plik źródłowy", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
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
            state = .failed(.network(error, context: .preview))
        }
    }

    private enum LoadState: Equatable {
        case loading
        case loaded(String)
        case failed(PavbotUserFacingError)
    }
}

private struct MarkdownReportText: View {
    let text: String

    var body: some View {
        if let markdown = try? AttributedString(markdown: text) {
            Text(markdown)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RemotePDFPreview: View {
    let url: URL

    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Wczytuję PDF")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let data):
                PDFDocumentView(data: data)
            case .failed(let error):
                VStack(spacing: 14) {
                    PavbotStateView(error: error) {
                        Task { await load() }
                    }
                    Link(destination: url) {
                        Label("Otwórz PDF źródłowy", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
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
            state = .failed(.network(error, context: .preview))
        }
    }

    private enum LoadState: Equatable {
        case loading
        case loaded(Data)
        case failed(PavbotUserFacingError)
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
    let artifact: PavbotArtifact
    let url: URL

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)

                Text("Audio podcastu")
                    .font(.title3.weight(.semibold))
            }

            AudioTimelineControls(artifact: artifact, url: url)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
