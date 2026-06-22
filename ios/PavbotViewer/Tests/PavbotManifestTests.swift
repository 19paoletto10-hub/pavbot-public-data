import XCTest
@testable import PavbotViewer

final class PavbotManifestTests: XCTestCase {
    func testDecodesManifestAndGroupsEnabledAutomations() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.automations.count, 2)
        XCTAssertEqual(manifest.enabledAutomations.map(\.id), ["research", "podcast"])
        XCTAssertEqual(manifest.topics.map(\.slug), ["tech-news"])
    }

    func testFiltersArtifactsByExactDay() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)

        let filtered = manifest.artifacts(on: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 22).date!)

        XCTAssertEqual(filtered.map(\.id), ["run-2026-06-22", "audio-2026-06-22"])
    }

    func testSearchesArtifactsByTitleTopicTypeAndPath() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let day = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 22).date!

        XCTAssertEqual(manifest.filteredArtifacts(on: day, query: "audio").map(\.id), ["audio-2026-06-22"])
        XCTAssertEqual(manifest.filteredArtifacts(on: day, query: "tech-news").map(\.id), ["run-2026-06-22", "audio-2026-06-22"])
        XCTAssertEqual(manifest.filteredArtifacts(on: nil, query: "2026-06-21").map(\.id), ["run-2026-06-21"])
    }

    func testSortsAvailableArtifactDaysDescending() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)

        XCTAssertEqual(manifest.availableDays.map(\.pavbotDayString), ["2026-06-22", "2026-06-21"])
    }

    func testArtifactKindMapsToViewerCapability() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let audio = try XCTUnwrap(manifest.artifacts.first { $0.type == .podcastAudio })
        let markdown = try XCTUnwrap(manifest.artifacts.first { $0.type == .run })

        XCTAssertEqual(audio.viewerKind, .audio)
        XCTAssertEqual(markdown.viewerKind, .markdown)
    }

    func testResolvesRelativeArtifactURLAgainstRawManifestRoot() throws {
        let artifact = PavbotArtifact(
            id: "relative",
            type: .run,
            topic: "tech-news",
            title: "Daily Research Report",
            path: "research/tech-news/runs/2026-06-22.md",
            url: "research/tech-news/runs/2026-06-22.md",
            sizeBytes: 100,
            date: "2026-06-22",
            time: nil
        )
        let manifestURL = try XCTUnwrap(URL(string: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"))

        XCTAssertEqual(
            artifact.resolvedURL(manifestURL: manifestURL)?.absoluteString,
            "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/runs/2026-06-22.md"
        )
    }

    func testManifestURLValidationRequiresHTTPSManifestJSON() {
        XCTAssertEqual(ManifestURLValidator.validate("https://example.com/public/pavbot-manifest.json"), .valid)
        XCTAssertEqual(ManifestURLValidator.validate("http://example.com/public/pavbot-manifest.json"), .invalid("Use an HTTPS manifest URL."))
        XCTAssertEqual(ManifestURLValidator.validate("https://example.com/public/manifest.txt"), .invalid("Manifest URL must point to a JSON file."))
        XCTAssertEqual(ManifestURLValidator.validate(""), .invalid("Enter a manifest URL."))
    }

    func testDecoderRejectsUnsupportedManifestSchemaVersion() throws {
        let data = """
        {
          "schemaVersion": 99,
          "title": "Pavbot Automation Manifest",
          "generatedAt": "2026-06-22T12:00:00+00:00",
          "rawBaseUrl": "",
          "automations": [],
          "topics": [],
          "artifacts": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder.pavbot.decode(PavbotManifest.self, from: data)) { error in
            XCTAssertEqual(error.localizedDescription, "Unsupported manifest schema version 99.")
        }
    }

    func testDetectsNewArtifactsComparedToPreviousManifest() throws {
        let previous = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        var nextArtifacts = previous.artifacts
        nextArtifacts.insert(Self.newArtifact, at: 0)
        let next = PavbotManifest(
            schemaVersion: previous.schemaVersion,
            title: previous.title,
            generatedAt: previous.generatedAt,
            rawBaseUrl: previous.rawBaseUrl,
            automations: previous.automations,
            topics: previous.topics,
            artifacts: nextArtifacts
        )

        XCTAssertEqual(next.newArtifacts(comparedTo: previous).map(\.id), ["new-run-2026-06-23"])
    }

    func testDiagnosticsReportsFreshManifestAndCounts() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-23T11:59:00Z")
        )

        XCTAssertEqual(diagnostics.enabledAutomationCount, 2)
        XCTAssertEqual(diagnostics.topicCount, 1)
        XCTAssertEqual(diagnostics.artifactCount, 3)
        XCTAssertEqual(diagnostics.freshness.severity, .ok)
        XCTAssertEqual(diagnostics.urlStatus.severity, .ok)
        XCTAssertTrue(diagnostics.issues.isEmpty)
    }

    func testDiagnosticsWarnsWhenManifestIsStale() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-23T12:01:00Z")
        )

        XCTAssertEqual(diagnostics.freshness.severity, .warning)
        XCTAssertTrue(diagnostics.issues.contains { $0.title == "Manifest is stale" })
    }

    func testDiagnosticsWarnsForPlaceholderURLAndMissingRawBaseURL() throws {
        let loadedManifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let manifest = PavbotManifest(
            schemaVersion: loadedManifest.schemaVersion,
            title: loadedManifest.title,
            generatedAt: loadedManifest.generatedAt,
            rawBaseUrl: "",
            automations: loadedManifest.automations,
            topics: loadedManifest.topics,
            artifacts: loadedManifest.artifacts
        )
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/OWNER/REPO/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-22T13:00:00Z")
        )

        XCTAssertEqual(diagnostics.urlStatus.severity, .warning)
        XCTAssertEqual(diagnostics.rawBaseURLStatus.severity, .warning)
        XCTAssertTrue(diagnostics.issues.contains { $0.title == "Public raw base URL missing" })
    }

    func testDiagnosticsFlagsActiveAutomationWithoutArtifacts() throws {
        let loadedManifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let manifest = PavbotManifest(
            schemaVersion: loadedManifest.schemaVersion,
            title: loadedManifest.title,
            generatedAt: loadedManifest.generatedAt,
            rawBaseUrl: loadedManifest.rawBaseUrl,
            automations: loadedManifest.automations,
            topics: loadedManifest.topics,
            artifacts: []
        )
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-22T13:00:00Z")
        )

        XCTAssertEqual(diagnostics.automationStatuses.map(\.severity), [.warning, .warning])
        XCTAssertTrue(diagnostics.issues.contains { $0.title == "Automation has no artifacts" })
    }

    func testDiagnosticsFindsLatestArtifactForAutomationTopic() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-22T13:00:00Z")
        )

        XCTAssertEqual(diagnostics.automationStatuses.map { $0.latestArtifact?.id }, ["run-2026-06-22", "audio-2026-06-22"])
    }

    func testLatestAutomationRunSummaryUsesArtifactTimeAndMatchingAutomationName() throws {
        let loadedManifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let latestAudio = PavbotArtifact(
            id: "audio-2026-06-23",
            type: .podcastAudio,
            topic: "tech-news",
            title: "Podcast audio",
            path: "research/tech-news/podcasts/2026-06-23/podcast.mp3",
            url: "research/tech-news/podcasts/2026-06-23/podcast.mp3",
            sizeBytes: 300,
            date: "2026-06-23",
            time: "09:30"
        )
        let manifest = PavbotManifest(
            schemaVersion: loadedManifest.schemaVersion,
            title: loadedManifest.title,
            generatedAt: loadedManifest.generatedAt,
            rawBaseUrl: loadedManifest.rawBaseUrl,
            automations: loadedManifest.automations,
            topics: loadedManifest.topics,
            artifacts: [latestAudio] + loadedManifest.artifacts
        )

        XCTAssertEqual(manifest.latestAutomationRun?.time, "09:30")
        XCTAssertEqual(manifest.latestAutomationRun?.automationName, "Pavbot Tech Podcast 09:00")
        XCTAssertEqual(manifest.latestAutomationRun?.dashboardSubtitle, "09:30 · Pavbot Tech Podcast 09:00")
    }

    @MainActor
    func testStoreSchedulesNotificationsForNewArtifactsAfterRefresh() async throws {
        let previous = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let next = PavbotManifest(
            schemaVersion: previous.schemaVersion,
            title: previous.title,
            generatedAt: previous.generatedAt,
            rawBaseUrl: previous.rawBaseUrl,
            automations: previous.automations,
            topics: previous.topics,
            artifacts: [Self.newArtifact] + previous.artifacts
        )
        let notifier = SpyArtifactNotifier()
        let store = ManifestStore(
            client: StubManifestClient(manifest: next),
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: notifier,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )
        store.manifest = previous

        await store.load()

        XCTAssertEqual(notifier.notifiedArtifactIDs, ["new-run-2026-06-23"])
        XCTAssertEqual(store.manifest?.artifacts.first?.id, "new-run-2026-06-23")
    }

    @MainActor
    func testStoreStartsLoadedWhenCacheContainsManifest() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = ManifestCache(defaults: defaults)
        cache.save(manifest)

        let store = ManifestStore(
            client: StubManifestClient(manifest: manifest),
            cache: cache,
            notifier: SpyArtifactNotifier(),
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.manifest?.artifacts.count, 3)
    }

    @MainActor
    func testStoreDoesNotFetchPlaceholderURLWhenManifestAlreadyAvailable() async throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let client = CountingFailingManifestClient()
        let store = ManifestStore(
            client: client,
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: SpyArtifactNotifier(),
            manifestURLString: ManifestStore.defaultManifestURL
        )
        store.manifest = manifest
        store.state = .loaded

        await store.load()

        XCTAssertEqual(client.fetchCount, 0)
        XCTAssertEqual(store.state, .loaded)
    }

    @MainActor
    func testRouterOpensArtifactFromNotificationUserInfo() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let router = AppRouter()

        router.handleNotification(userInfo: ["artifactID": "audio-2026-06-22"])
        router.resolvePendingArtifact(in: manifest)

        XCTAssertEqual(router.selectedTab, .artifacts)
        XCTAssertEqual(router.artifactPath.map(\.id), ["audio-2026-06-22"])
        XCTAssertNil(router.pendingArtifactID)
    }

    private static let fixtureData = """
    {
      "schemaVersion": 1,
      "title": "Pavbot Automation Manifest",
      "generatedAt": "2026-06-22T12:00:00+00:00",
      "rawBaseUrl": "https://raw.githubusercontent.com/example/pavbot/main/",
      "automations": [
        {
          "id": "research",
          "name": "Pavbot Tech Research 08:00",
          "enabled": true,
          "kind": "research",
          "topic": "tech-news",
          "topicPath": "research/tech-news",
          "cadence": "daily at 08:00 local time",
          "sourcePath": "docs/how-to-use.md",
          "sourceUrl": "https://raw.githubusercontent.com/example/pavbot/main/docs/how-to-use.md"
        },
        {
          "id": "podcast",
          "name": "Pavbot Tech Podcast 09:00",
          "enabled": true,
          "kind": "podcast",
          "topic": "tech-news",
          "topicPath": "research/tech-news",
          "cadence": "daily at 09:00 local time",
          "sourcePath": "docs/how-to-use.md",
          "sourceUrl": "https://raw.githubusercontent.com/example/pavbot/main/docs/how-to-use.md",
          "output": "research/tech-news/podcasts/YYYY-MM-DD/podcast.mp3",
          "outputUrl": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/podcasts/YYYY-MM-DD/podcast.mp3"
        }
      ],
      "topics": [
        {
          "slug": "tech-news",
          "title": "Topic Contract: tech-news",
          "path": "research/tech-news",
          "topicFilePath": "research/tech-news/topic.md",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/topic.md"
        }
      ],
      "artifacts": [
        {
          "id": "run-2026-06-22",
          "type": "run",
          "topic": "tech-news",
          "title": "Daily Research Report: tech-news",
          "path": "research/tech-news/runs/2026-06-22.md",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/runs/2026-06-22.md",
          "date": "2026-06-22",
          "sizeBytes": 100
        },
        {
          "id": "audio-2026-06-22",
          "type": "podcastAudio",
          "topic": "tech-news",
          "title": "Podcast audio",
          "path": "research/tech-news/podcasts/2026-06-22/podcast.mp3",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/podcasts/2026-06-22/podcast.mp3",
          "date": "2026-06-22",
          "sizeBytes": 100
        },
        {
          "id": "run-2026-06-21",
          "type": "run",
          "topic": "tech-news",
          "title": "Daily Research Report: tech-news",
          "path": "research/tech-news/runs/2026-06-21.md",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/runs/2026-06-21.md",
          "date": "2026-06-21",
          "sizeBytes": 100
        }
      ]
    }
    """.data(using: .utf8)!

    private static let newArtifact = PavbotArtifact(
        id: "new-run-2026-06-23",
        type: .run,
        topic: "tech-news",
        title: "Daily Research Report: tech-news",
        path: "research/tech-news/runs/2026-06-23.md",
        url: "research/tech-news/runs/2026-06-23.md",
        sizeBytes: 200,
        date: "2026-06-23",
        time: nil
    )

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private struct StubManifestClient: ManifestFetching {
    let manifest: PavbotManifest

    func fetchManifest(from url: URL) async throws -> PavbotManifest {
        manifest
    }
}

private final class CountingFailingManifestClient: ManifestFetching {
    private(set) var fetchCount = 0

    func fetchManifest(from url: URL) async throws -> PavbotManifest {
        fetchCount += 1
        throw URLError(.badServerResponse)
    }
}

@MainActor
private final class SpyArtifactNotifier: ArtifactNotifying {
    private(set) var notifiedArtifactIDs: [String] = []

    func notify(artifacts: [PavbotArtifact], manifestURL: URL) async {
        notifiedArtifactIDs = artifacts.map(\.id)
    }
}
