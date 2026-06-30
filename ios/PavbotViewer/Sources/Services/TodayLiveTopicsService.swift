import Foundation
import Observation

@MainActor
@Observable
final class TodayLiveTopicsStore {
    typealias LoadState = PavbotLoadState

    var snapshot: TodayLiveTopicsSnapshot?
    var state: LoadState = .idle
    var emptyMessage: String?
    var isRefreshing = false

    private let client: MobileNewsClient
    private let pulseClient: PulseNewsClient
    private let historyStore: PulseNewsHistoryStore
    @ObservationIgnored private let reloadGate = ReloadGate()

    var historySnapshots: [TodayLiveTopicsSnapshot] {
        historyStore.snapshots
    }

    init(
        client: MobileNewsClient = MobileNewsClient(),
        pulseClient: PulseNewsClient = PulseNewsClient(),
        historyStore: PulseNewsHistoryStore = PulseNewsHistoryStore()
    ) {
        self.client = client
        self.pulseClient = pulseClient
        self.historyStore = historyStore
    }

    func load(
        manifest: PavbotManifest?,
        manifestURLString: String,
        minimumInterval: TimeInterval = 0
    ) async {
        guard reloadGate.begin(key: "today.liveTopics", minimumInterval: minimumInterval) else { return }
        isRefreshing = true
        defer {
            reloadGate.finish(key: "today.liveTopics")
            isRefreshing = false
        }

        historyStore.prune()
        showCachedPulseIfNeeded(message: PavbotCacheNoticeCopy.refreshing(context: "Puls Dnia z ostatnich 48h"))

        guard let manifest else {
            if snapshot == nil {
                emptyMessage = "Brak opublikowanego Pulsu dnia. Odśwież manifest albo otwórz Research -> Aktualne."
            }
            state = .loaded
            return
        }

        if snapshot == nil {
            state = .loading
        }

        if await loadPulseNews(from: manifest, manifestURLString: manifestURLString) {
            return
        }

        guard
            let package = manifest.reportPackages(for: .aktualne).first(where: { $0.mobileNewsDataArtifact != nil }),
            let artifact = package.mobileNewsDataArtifact,
            let url = artifact.resolvedURL(manifestURL: URL(string: manifestURLString))
        else {
            snapshot = nil
            emptyMessage = "Automatyzacja Puls dnia 3h nie opublikowała jeszcze danych, a fallback z magazynu 10:15 nie jest dostępny. Odśwież manifest albo otwórz Research -> Aktualne."
            state = .loaded
            return
        }

        do {
            let data = try await client.fetchData(url)
            let magazine = try JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: data).withPackage(package)
            let nextSnapshot = TodayLiveTopicsSnapshot(magazine: magazine)
            snapshot = nextSnapshot.groups.isEmpty ? nil : nextSnapshot
            emptyMessage = nextSnapshot.groups.isEmpty
                ? "Magazyn 10:15 nie zawiera jeszcze tematów dla kafelka Polska/Świat."
                : nil
            state = .loaded
        } catch {
            if snapshot != nil {
                state = .loaded
                emptyMessage = PavbotCacheNoticeCopy.refreshFailed(context: "ostatnio wczytane tematy")
            } else {
                emptyMessage = nil
                state = .failed(.network(error, context: .preview))
            }
        }
    }

    private func loadPulseNews(from manifest: PavbotManifest, manifestURLString: String) async -> Bool {
        guard
            let artifact = manifest.artifacts
                .filter({ $0.topic == "puls-dnia-news" && $0.type == .pulseNewsData })
                .sorted(by: PavbotArtifact.automationDisplaySort)
                .first,
            let url = artifact.resolvedURL(manifestURL: URL(string: manifestURLString))
        else {
            return false
        }

        do {
            let data = try await pulseClient.fetchData(url)
            let digest = try JSONDecoder.pavbot.decode(PulseNewsDigest.self, from: data)
            historyStore.save(digest)
            let nextSnapshot = TodayLiveTopicsSnapshot(digest: digest)
            snapshot = nextSnapshot.pairs.isEmpty ? nil : nextSnapshot
            emptyMessage = nextSnapshot.pairs.isEmpty
                ? "Puls dnia nie zawiera jeszcze par kafelków do pokazania."
                : nil
            state = .loaded
            return true
        } catch {
            if snapshot != nil {
                state = .loaded
                emptyMessage = PavbotCacheNoticeCopy.refreshFailed(context: "Puls Dnia z ostatnich 48h")
                return true
            }
            if showCachedPulseIfNeeded(message: PavbotCacheNoticeCopy.refreshFailed(context: "Puls Dnia z ostatnich 48h")) {
                state = .loaded
                return true
            }
            return false
        }
    }

    func pruneHistory() {
        historyStore.prune()
        guard
            let currentSnapshot = snapshot,
            currentSnapshot.source == .pulseNews,
            !historyStore.snapshots.contains(where: { $0.id == currentSnapshot.id })
        else {
            return
        }
        snapshot = historyStore.latest?.snapshot
    }

    @discardableResult
    private func showCachedPulseIfNeeded(message: String) -> Bool {
        guard snapshot == nil, let cached = historyStore.latest else {
            return false
        }
        snapshot = cached.snapshot
        emptyMessage = message
        state = .loaded
        return true
    }
}
