import SwiftUI

enum ReportPackageCopy {
    static let emptyResearchTitle = "Brak raportów Research"
    static let emptyResearchDescription = "Odśwież manifest po publikacji Tech News albo Polska i Świat."
    static let noManifestTitle = "Brak manifestu"
    static let noManifestDescription = "Wklej Manifest URL w ustawieniach i odśwież dane."
    static let refreshReportsAccessibilityLabel = "Odśwież raporty"
    static let openResearchTitle = "Otwórz raport"
    static let openPDFTitle = "Otwórz PDF"
    static let openPodcastBriefTitle = "Otwórz brief podcastu"
    static let playAudioTitle = "Odtwórz audio"
    static let missingPDFTitle = "Brakuje PDF"
    static let missingPDFDescription = "Raport Markdown jest dostępny, ale PDF nie został jeszcze opublikowany."
    static let reportsMetricTitle = "Raporty"
    static let latestMetricTitle = "Najnowszy"
    static let latestBadgeTitle = "Najnowsze"
    static let filesLabel = "plików"
}

struct ResearchArticleListSnapshot: Equatable {
    let articles: [ResearchNewsArticle]

    init(issue: ResearchNewsIssue, selectedSection: ResearchNewsSection?, searchText: String) {
        articles = issue.filteredArticles(section: selectedSection, query: searchText)
    }
}

struct ResearchView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var newsStore = ResearchNewsStore()
    @State private var mobileNewsStore = MobileNewsStore()
    @StateObject private var mobileSpeechController = MobileNewsSpeechController()
    @StateObject private var podcastSpeechController = PodcastScriptSpeechController()
    @State private var savedResearchStore = SavedResearchArticleStore()
    @State private var selectedSection: ResearchNewsSection?
    @State private var selectedArticle: ResearchNewsArticle?
    @State private var selectedMobileArticle: MobileNewsArticle?
    @State private var isSavedResearchPresented = false

    var body: some View {
        @Bindable var router = router

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ResearchTopicPicker(selection: $router.selectedResearchTopic)

                if let manifest = store.manifest {
                    let packages = manifest.reportPackages(for: router.selectedResearchTopic)
                    if router.selectedResearchTopic == .aktualne {
                        MobileNewsNativeContent(
                            packages: packages,
                            magazine: mobileNewsStore.magazine,
                            state: mobileNewsStore.state,
                            cacheNotice: mobileNewsStore.cacheNotice,
                            selectedArticle: $selectedMobileArticle,
                            speechController: mobileSpeechController,
                            podcastSpeechController: podcastSpeechController,
                            reload: {
                                Task { await loadMobileMagazine() }
                            }
                        )
                    } else {
                        ResearchNativeContent(
                            topic: router.selectedResearchTopic,
                            packages: packages,
                            issue: newsStore.issue,
                            state: newsStore.state,
                            cacheNotice: newsStore.cacheNotice,
                            selectedSection: $selectedSection,
                            selectedArticle: $selectedArticle,
                            savedStore: savedResearchStore,
                            reload: {
                                Task { await loadNewsIssue() }
                            }
                        )
                    }
                } else {
                    ContentUnavailableView(
                        ReportPackageCopy.noManifestTitle,
                        systemImage: "doc.badge.questionmark",
                        description: Text(ReportPackageCopy.noManifestDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Research")
        .navigationDestination(for: PavbotArtifact.self) { artifact in
            ArtifactDetailView(artifact: artifact)
        }
        .sheet(item: $selectedArticle) { article in
            if let issue = newsStore.issue {
                ResearchArticleReader(article: article, issue: issue, savedStore: savedResearchStore)
            }
        }
        .sheet(item: $selectedMobileArticle) { article in
            if let magazine = mobileNewsStore.magazine {
                MobileNewsArticleReader(
                    article: article,
                    magazine: magazine,
                    speechController: mobileSpeechController
                )
            }
        }
        .sheet(isPresented: $isSavedResearchPresented) {
            SavedResearchArticlesView(store: savedResearchStore)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isSavedResearchPresented = true
                } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel("Otwórz zapisane artykuły Research")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.reload()
                        await loadSelectedResearchContent()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.state == .loading || newsStore.state == .loading)
                .accessibilityLabel(ReportPackageCopy.refreshReportsAccessibilityLabel)
            }
        }
        .refreshable {
            await store.reload()
            await loadSelectedResearchContent()
        }
        .task(id: loadKey) {
            await loadSelectedResearchContent()
        }
        .onAppear {
            if router.selectedReportDay == nil {
                router.selectedReportDay = store.manifest?.reportPackages(for: router.selectedResearchTopic).first?.date
            }
        }
        .onChange(of: router.selectedResearchTopic) { _, topic in
            router.selectedReportArtifactIDs = []
            router.selectedReportDay = store.manifest?.reportPackages(for: topic).first?.date
            selectedSection = nil
            selectedArticle = nil
            selectedMobileArticle = nil
            mobileSpeechController.stop()
        }
        .onChange(of: store.manifest) { _, manifest in
            guard let manifest else { return }
            if router.selectedReportDay == nil {
                router.selectedReportDay = manifest.reportPackages(for: router.selectedResearchTopic).first?.date
            }
        }
    }

    private var loadKey: String {
        [
            store.manifest?.generatedAt ?? "no-manifest",
            store.manifestURLString,
            router.selectedResearchTopic.rawValue,
            router.selectedReportDay ?? "no-day",
            router.selectedReportArtifactIDs.joined(separator: ",")
        ].joined(separator: "|")
    }

    private func loadNewsIssue() async {
        guard let manifest = store.manifest else { return }
        guard router.selectedResearchTopic != .aktualne else { return }
        await newsStore.load(
            packages: manifest.reportPackages(for: router.selectedResearchTopic),
            manifestURLString: store.manifestURLString,
            topic: router.selectedResearchTopic,
            selectedDay: router.selectedReportDay,
            selectedArtifactIDs: router.selectedReportArtifactIDs
        )
    }

    private func loadMobileMagazine() async {
        guard let manifest = store.manifest else { return }
        await mobileNewsStore.load(
            packages: manifest.reportPackages(for: .aktualne),
            manifestURLString: store.manifestURLString,
            selectedDay: router.selectedReportDay,
            selectedArtifactIDs: router.selectedReportArtifactIDs
        )
    }

    private func loadSelectedResearchContent() async {
        if router.selectedResearchTopic == .aktualne {
            await loadMobileMagazine()
        } else {
            await loadNewsIssue()
        }
    }
}

private struct ResearchNativeContent: View {
    let topic: ReportTopicKind
    let packages: [TopicReportPackage]
    let issue: ResearchNewsIssue?
    let state: ResearchNewsStore.LoadState
    let cacheNotice: String?
    @Binding var selectedSection: ResearchNewsSection?
    @Binding var selectedArticle: ResearchNewsArticle?
    let savedStore: SavedResearchArticleStore
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PavbotScreenHeader(
                title: topic.title,
                subtitle: topic.subtitle,
                systemImage: topic.systemImage,
                tint: topic.tint
            )

            switch state {
            case .idle:
                if let issue {
                    issueContent(issue)
                } else {
                    ProgressView("Ładuję wydanie Research...")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            case .loading:
                if let issue {
                    ResearchCacheBanner(message: "Odświeżam wydanie Research...")
                    issueContent(issue)
                } else {
                    ProgressView("Ładuję wydanie Research...")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            case .failed(let error):
                if let issue {
                    ResearchCacheBanner(message: error.message)
                    issueContent(issue)
                } else {
                    PavbotStateView(error: error, action: reload)
                }
            case .loaded:
                if let issue {
                    issueContent(issue)
                } else {
                    ContentUnavailableView(
                        ReportPackageCopy.emptyResearchTitle,
                        systemImage: topic.systemImage,
                        description: Text(ReportPackageCopy.emptyResearchDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
        }
    }

    @ViewBuilder
    private func issueContent(_ issue: ResearchNewsIssue) -> some View {
        if let cacheNotice {
            ResearchCacheBanner(message: cacheNotice)
        }

        ResearchIssueHero(issue: issue, packageCount: packages.count)
        ResearchSectionFilterBar(topic: topic, selection: $selectedSection)

        let articleSnapshot = ResearchArticleListSnapshot(issue: issue, selectedSection: selectedSection, searchText: "")
        if articleSnapshot.articles.isEmpty {
            ContentUnavailableView(
                "Brak newsów dla filtra",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Zmień sekcję, żeby zobaczyć inne artykuły z wydania.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(spacing: 12) {
                ForEach(articleSnapshot.articles) { article in
                    Button {
                        selectedArticle = article
                    } label: {
                        ResearchArticleCard(
                            article: article,
                            topic: topic,
                            isSaved: savedStore.isSaved(article: article, issue: issue)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        ResearchIssueAddOns(issue: issue)
    }
}

private struct MobileNewsNativeContent: View {
    let packages: [TopicReportPackage]
    let magazine: MobileNewsMagazine?
    let state: MobileNewsStore.LoadState
    let cacheNotice: String?
    @Binding var selectedArticle: MobileNewsArticle?
    @ObservedObject var speechController: MobileNewsSpeechController
    @ObservedObject var podcastSpeechController: PodcastScriptSpeechController
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PavbotScreenHeader(
                title: ReportTopicKind.aktualne.title,
                subtitle: ReportTopicKind.aktualne.subtitle,
                systemImage: ReportTopicKind.aktualne.systemImage,
                tint: ReportTopicKind.aktualne.tint
            )

            switch state {
            case .idle:
                if let magazine {
                    magazineContent(magazine)
                } else {
                    ProgressView("Ładuję magazyn Aktualne...")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            case .loading:
                if let magazine {
                    ResearchCacheBanner(message: "Odświeżam magazyn Aktualne...")
                    magazineContent(magazine)
                } else {
                    ProgressView("Ładuję magazyn Aktualne...")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            case .failed(let error):
                if let magazine {
                    ResearchCacheBanner(message: error.message)
                    magazineContent(magazine)
                } else {
                    PavbotStateView(error: error, action: reload)
                }
            case .loaded:
                if let magazine {
                    magazineContent(magazine)
                } else {
                    ContentUnavailableView(
                        "Brak magazynu Aktualne",
                        systemImage: ReportTopicKind.aktualne.systemImage,
                        description: Text("Odśwież manifest po publikacji automatyzacji 10:15.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
        }
    }

    @ViewBuilder
    private func magazineContent(_ magazine: MobileNewsMagazine) -> some View {
        if let cacheNotice {
            ResearchCacheBanner(message: cacheNotice)
        }

        MobileNewsHero(magazine: magazine, packageCount: packages.count)

        if speechController.hasActivePlayback {
            MobileNewsSpeechMiniPlayer(speechController: speechController)
        }

        if podcastSpeechController.hasActivePlayback {
            PodcastScriptSpeechMiniPlayer(speechController: podcastSpeechController)
        }

        let sections = magazine.sections
        if sections.isEmpty {
            ContentUnavailableView(
                "Brak artykułów",
                systemImage: "newspaper",
                description: Text("Magazyn Aktualne nie zawiera jeszcze artykułów do pokazania.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    MobileNewsSectionBlock(
                        section: section,
                        selectedArticle: $selectedArticle,
                        speechController: speechController
                    )
                }
            }
        }

        MobileNewsAddOns(magazine: magazine, podcastSpeechController: podcastSpeechController)
    }
}

private struct MobileNewsSpeechMiniPlayer: View {
    @ObservedObject var speechController: MobileNewsSpeechController
    @Environment(PavbotHaptics.self) private var haptics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: speechController.isPaused ? "pause.circle.fill" : "speaker.wave.2.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Lokalny TTS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(speechController.currentTitle ?? "Czytanie artykułu")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button {
                    if speechController.isPaused {
                        speechController.resume()
                    } else {
                        speechController.pause()
                    }
                    haptics.play(.lightImpact)
                } label: {
                    Label(speechController.isPaused ? "Wznów" : "Pauza", systemImage: speechController.isPaused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!speechController.isSpeaking)

                Button {
                    speechController.stop()
                    haptics.play(.warning)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            MobileNewsSpeechRatePicker(speechController: speechController)

            PavbotSpeechTimelineScrubber(
                timeline: speechController.timeline,
                currentSegmentIndex: speechController.currentSegmentIndex,
                estimatedElapsed: speechController.estimatedElapsed,
                estimatedDuration: speechController.estimatedDuration,
                currentSegmentText: speechController.currentSegmentText,
                seekToProgress: speechController.seek(toProgress:)
            )

            if let errorMessage = speechController.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var statusText: String {
        if speechController.isPaused {
            return "Wstrzymane. Możesz wznowić, zmienić tempo albo zatrzymać."
        }
        if speechController.isSpeaking {
            return "Odczyt aktywny. Player zostaje widoczny po zamknięciu artykułu."
        }
        return "Gotowe do odczytu."
    }
}

private struct PodcastScriptSpeechMiniPlayer: View {
    @ObservedObject var speechController: PodcastScriptSpeechController
    @Environment(PavbotHaptics.self) private var haptics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 38, height: 38)
                    .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Podcast TTS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(speechController.currentTitle ?? "Czytanie tekstu podcastu")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(speechController.isPaused ? "Wstrzymane" : "Odczyt aktywny")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button {
                    if speechController.isPaused {
                        speechController.resume()
                    } else {
                        speechController.pause()
                    }
                    haptics.play(.lightImpact)
                } label: {
                    Label(speechController.isPaused ? "Wznów" : "Pauza", systemImage: speechController.isPaused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.purple, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!speechController.isSpeaking)

                Button {
                    speechController.stop()
                    haptics.play(.warning)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            MobileNewsPodcastSpeechRatePicker(speechController: speechController)

            PavbotSpeechTimelineScrubber(
                timeline: speechController.timeline,
                currentSegmentIndex: speechController.currentSegmentIndex,
                estimatedElapsed: speechController.estimatedElapsed,
                estimatedDuration: speechController.estimatedDuration,
                currentSegmentText: speechController.currentSegmentText,
                seekToProgress: speechController.seek(toProgress:)
            )

            if let errorMessage = speechController.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.purple.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MobileNewsHero: View {
    let magazine: MobileNewsMagazine
    let packageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(text: "Magazyn 10:15", systemImage: "newspaper.fill", tint: .orange)
                    Text(magazine.displayDate)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(magazine.headline)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "iphone.gen3")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(magazine.leadParagraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(index == 0 ? .body.weight(.semibold) : .callout)
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                MetricTile(title: "Artykuły", value: "\(magazine.articleCount)", systemImage: "doc.text.fill", tint: .orange)
                MetricTile(title: "Źródła", value: "\(magazine.sourceCount)", systemImage: "link.circle.fill", tint: .blue)
                MetricTile(title: "Audio", value: magazine.audioArtifact == nil ? "Brak" : "Tak", systemImage: "waveform", tint: .purple)
            }

            HStack(spacing: 8) {
                StatusBadge(text: magazine.status, systemImage: "checkmark.seal.fill", tint: .green)
                if magazine.pdfArtifact != nil {
                    StatusBadge(text: "PDF", systemImage: "doc.richtext.fill", tint: .red)
                }
                if packageCount > 1 {
                    StatusBadge(text: "\(packageCount) wydań", systemImage: "calendar", tint: .gray)
                }
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct MobileNewsSectionBlock: View {
    let section: MobileNewsSection
    @Binding var selectedArticle: MobileNewsArticle?
    @ObservedObject var speechController: MobileNewsSpeechController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.headline.weight(.bold))
                    if let summary = section.displaySummary {
                        Text("Stan sekcji")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .textCase(.uppercase)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: 10) {
                ForEach(section.articles) { article in
                    MobileNewsArticleRow(
                        article: article,
                        selectedArticle: $selectedArticle,
                        speechController: speechController
                    )
                }
            }
        }
    }
}

private struct MobileNewsArticleRow: View {
    @Environment(PavbotHaptics.self) private var haptics
    let article: MobileNewsArticle
    @Binding var selectedArticle: MobileNewsArticle?
    @ObservedObject var speechController: MobileNewsSpeechController

    private var isCurrent: Bool {
        speechController.currentArticleID == article.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                haptics.play(.lightImpact)
                selectedArticle = article
            } label: {
                MobileNewsArticleCard(article: article)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    handleSpeechAction()
                } label: {
                    Label(speechTitle, systemImage: speechIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(speechTitle): \(article.title)")

                if isCurrent {
                    Button {
                        speechController.stop()
                        haptics.play(.warning)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(article.sources.count) źr.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if isCurrent {
                MobileNewsSpeechRatePicker(speechController: speechController)
                    .padding(.horizontal, 4)
                PavbotSpeechTimelineScrubber(
                    timeline: speechController.timeline,
                    currentSegmentIndex: speechController.currentSegmentIndex,
                    estimatedElapsed: speechController.estimatedElapsed,
                    estimatedDuration: speechController.estimatedDuration,
                    currentSegmentText: speechController.currentSegmentText,
                    seekToProgress: speechController.seek(toProgress:)
                )
                .padding(.horizontal, 4)
            }

            if let errorMessage = speechController.errorMessage, isCurrent {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var speechTitle: String {
        if isCurrent, speechController.isPaused {
            return "Wznów"
        }
        if isCurrent, speechController.isSpeaking {
            return "Pauza"
        }
        return "Czytaj na głos"
    }

    private var speechIcon: String {
        if isCurrent, speechController.isPaused {
            return "play.fill"
        }
        if isCurrent, speechController.isSpeaking {
            return "pause.fill"
        }
        return "speaker.wave.2.fill"
    }

    private func handleSpeechAction() {
        if isCurrent, speechController.isPaused {
            speechController.resume()
        } else if isCurrent, speechController.isSpeaking {
            speechController.pause()
        } else {
            speechController.speak(article)
        }
        haptics.play(.lightImpact)
    }
}

private struct MobileNewsArticleCard: View {
    let article: MobileNewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(article.section.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                    Text(article.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(article.lead)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            if !article.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(article.tags.prefix(4), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MobileNewsAddOns: View {
    @Environment(ManifestStore.self) private var store

    let magazine: MobileNewsMagazine
    @ObservedObject var podcastSpeechController: PodcastScriptSpeechController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dodatki do wydania")
                .font(.headline.weight(.semibold))

            VStack(alignment: .leading, spacing: 0) {
                if let pdf = magazine.pdfArtifact {
                    NavigationLink(value: pdf) {
                        PavbotActionRow(title: "Otwórz PDF", subtitle: pdf.title, systemImage: "doc.richtext.fill", tint: .red)
                    }
                    .buttonStyle(.plain)
                }

                if let script = magazine.podcastScriptArtifact {
                    if magazine.pdfArtifact != nil {
                        Divider().padding(.leading, 50)
                    }
                    PodcastScriptSpeechPanel(
                        artifact: script,
                        manifestURLString: store.manifestURLString,
                        speechController: podcastSpeechController
                    )
                }

                if let audio = magazine.audioArtifact {
                    if magazine.pdfArtifact != nil || magazine.podcastScriptArtifact != nil {
                        Divider().padding(.leading, 50)
                    }
                    if let url = audio.resolvedURL(manifestURL: URL(string: store.manifestURLString)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.purple)
                                    .frame(width: 34, height: 34)
                                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Odtwórz MP3")
                                        .font(.subheadline.weight(.semibold))
                                    Text(audio.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                            }

                            AudioTimelineControls(artifact: audio, url: url, sourceLinkTitle: "Plik MP3")
                        }
                        .padding(.vertical, 12)
                    } else {
                        PavbotActionRow(title: "MP3 niedostępne", subtitle: "Odśwież manifest z publicznym GitHub raw URL.", systemImage: "play.slash.fill", tint: .secondary)
                    }
                }

                if magazine.podcastScriptArtifact == nil && magazine.audioArtifact == nil {
                    PavbotActionRow(
                        title: "Brak podcastu",
                        subtitle: "Manifest nie zawiera jeszcze tekstu podcastu ani MP3 dla tego wydania.",
                        systemImage: "waveform.slash",
                        tint: .secondary
                    )
                }
            }
            .padding(.horizontal, 14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct PodcastScriptSpeechPanel: View {
    let artifact: PavbotArtifact
    let manifestURLString: String
    @ObservedObject var speechController: PodcastScriptSpeechController
    @State private var showTranscript = false

    private var isCurrent: Bool {
        speechController.currentArtifactID == artifact.id
    }

    private var transcriptText: String? {
        guard speechController.transcriptArtifactID == artifact.id else { return nil }
        return speechController.currentTranscriptText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Czytaj lokalnie")
                        .font(.subheadline.weight(.semibold))
                    Text("iPhone odczyta tekst podcastu bez czekania na render MP3.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await playOrToggle() }
                } label: {
                    Label(buttonTitle, systemImage: buttonIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(speechController.isLoading)

                if isCurrent {
                    Button {
                        speechController.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            MobileNewsPodcastSpeechRatePicker(speechController: speechController)

            Button {
                Task { await toggleTranscript() }
            } label: {
                Label(showTranscript ? "Ukryj transkrypcję" : "Pokaż transkrypcję", systemImage: "captions.bubble")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(showTranscript ? "Ukryj transkrypcję podcastu" : "Pokaż transkrypcję podcastu")
            .accessibilityHint("Pokazuje tekst źródłowy używany przez lokalny odczyt TTS.")

            if showTranscript {
                if let transcriptText, !transcriptText.isEmpty {
                    PodcastTranscriptPreview(text: transcriptText)
                } else if speechController.isLoading {
                    Label("Wczytuję transkrypcję...", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Brak transkrypcji dla tego nagrania", systemImage: "captions.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isCurrent {
                PavbotSpeechTimelineScrubber(
                    timeline: speechController.timeline,
                    currentSegmentIndex: speechController.currentSegmentIndex,
                    estimatedElapsed: speechController.estimatedElapsed,
                    estimatedDuration: speechController.estimatedDuration,
                    currentSegmentText: speechController.currentSegmentText,
                    seekToProgress: speechController.seek(toProgress:)
                )
            }

            if let errorMessage = speechController.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
    }

    private var buttonTitle: String {
        if speechController.isLoading { return "Wczytuję" }
        if isCurrent, speechController.isPaused { return "Wznów" }
        if isCurrent, speechController.isSpeaking { return "Pauza" }
        return "Czytaj podcast"
    }

    private var buttonIcon: String {
        if speechController.isLoading { return "hourglass" }
        if isCurrent, speechController.isPaused { return "play.fill" }
        if isCurrent, speechController.isSpeaking { return "pause.fill" }
        return "speaker.wave.2.fill"
    }

    private func playOrToggle() async {
        guard let url = artifact.resolvedURL(manifestURL: URL(string: manifestURLString)) else {
            speechController.errorMessage = "Brak publicznego URL tekstu podcastu. Odśwież manifest z GitHub raw URL."
            return
        }
        await speechController.playOrToggle(artifact: artifact, url: url)
    }

    private func toggleTranscript() async {
        if showTranscript {
            showTranscript = false
            return
        }
        showTranscript = true
        guard let url = artifact.resolvedURL(manifestURL: URL(string: manifestURLString)) else {
            speechController.errorMessage = "Brak publicznego URL transkrypcji. Odśwież manifest z GitHub raw URL."
            return
        }
        await speechController.loadTranscript(artifact: artifact, url: url)
    }
}

private struct PodcastTranscriptPreview: View {
    let text: String

    private var paragraphs: [String] {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Transkrypcja audio", systemImage: "text.quote")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transkrypcja audio. \(paragraphs.joined(separator: " "))")
    }
}

private struct MobileNewsArticleReader: View {
    @Environment(ManifestStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let article: MobileNewsArticle
    let magazine: MobileNewsMagazine
    @ObservedObject var speechController: MobileNewsSpeechController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 13) {
                        StatusBadge(text: article.section, systemImage: "newspaper.fill", tint: .orange)
                        Text(article.title)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(article.lead)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        MobileNewsSpeechControls(article: article, speechController: speechController)

                        Divider()
                        MobileNewsTextSection(title: "Fakty", items: article.facts)
                        MobileNewsTextBlock(title: "Analiza", text: article.analysis)
                        MobileNewsTextBlock(title: "Dlaczego to ważne", text: article.whyItMatters)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if !article.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Źródła")
                                .font(.headline.weight(.semibold))
                            ForEach(article.sources) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        PavbotActionRow(title: source.title, subtitle: source.url, systemImage: "link.circle.fill", tint: .orange)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    MobileNewsReaderAddOns(magazine: magazine, manifestURLString: store.manifestURLString)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Aktualne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct MobileNewsSpeechControls: View {
    @Environment(PavbotHaptics.self) private var haptics
    let article: MobileNewsArticle
    @ObservedObject var speechController: MobileNewsSpeechController

    private var isCurrent: Bool {
        speechController.currentArticleID == article.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if isCurrent, speechController.isPaused {
                        speechController.resume()
                    } else if isCurrent, speechController.isSpeaking {
                        speechController.pause()
                    } else {
                        speechController.speak(article)
                    }
                    haptics.play(.lightImpact)
                } label: {
                    Label(title, systemImage: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.orange, in: Capsule())
                }
                .buttonStyle(.plain)

                if isCurrent {
                    Button {
                        speechController.stop()
                        haptics.play(.warning)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            MobileNewsSpeechRatePicker(speechController: speechController)
            if isCurrent {
                PavbotSpeechTimelineScrubber(
                    timeline: speechController.timeline,
                    currentSegmentIndex: speechController.currentSegmentIndex,
                    estimatedElapsed: speechController.estimatedElapsed,
                    estimatedDuration: speechController.estimatedDuration,
                    currentSegmentText: speechController.currentSegmentText,
                    seekToProgress: speechController.seek(toProgress:)
                )
            }
            if let errorMessage = speechController.errorMessage, isCurrent {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: String {
        if isCurrent, speechController.isPaused { return "Wznów" }
        if isCurrent, speechController.isSpeaking { return "Pauza" }
        return "Czytaj na głos"
    }

    private var icon: String {
        if isCurrent, speechController.isPaused { return "play.fill" }
        if isCurrent, speechController.isSpeaking { return "pause.fill" }
        return "speaker.wave.2.fill"
    }
}

private struct MobileNewsSpeechRatePicker: View {
    @ObservedObject var speechController: MobileNewsSpeechController

    var body: some View {
        PavbotSpeechRatePicker(title: "Tempo czytania na głos", speechRate: rateBinding)
    }

    private var rateBinding: Binding<MobileNewsSpeechRate> {
        Binding(
            get: { speechController.speechRate },
            set: { speechController.setSpeechRate($0) }
        )
    }
}

private struct MobileNewsPodcastSpeechRatePicker: View {
    @ObservedObject var speechController: PodcastScriptSpeechController

    var body: some View {
        PavbotSpeechRatePicker(title: "Tempo czytania podcastu", speechRate: rateBinding)
    }

    private var rateBinding: Binding<MobileNewsSpeechRate> {
        Binding(
            get: { speechController.speechRate },
            set: { speechController.setSpeechRate($0) }
        )
    }
}

private struct MobileNewsTextSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MobileNewsTextBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.callout)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MobileNewsReaderAddOns: View {
    let magazine: MobileNewsMagazine
    let manifestURLString: String

    var body: some View {
        VStack(spacing: 0) {
            if let pdf = magazine.pdfArtifact, let url = pdf.resolvedURL(manifestURL: URL(string: manifestURLString)) {
                Link(destination: url) {
                    PavbotActionRow(title: "Otwórz PDF wydania", subtitle: pdf.title, systemImage: "doc.richtext.fill", tint: .red)
                }
            }

            if let audio = magazine.audioArtifact, let url = audio.resolvedURL(manifestURL: URL(string: manifestURLString)) {
                if magazine.pdfArtifact != nil {
                    Divider().padding(.leading, 50)
                }
                Link(destination: url) {
                    PavbotActionRow(title: "Otwórz podcast", subtitle: audio.title, systemImage: "play.circle.fill", tint: .purple)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ResearchCacheBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "icloud.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ResearchIssueHero: View {
    let issue: ResearchNewsIssue
    let packageCount: Int

    var body: some View {
        let presentation = ResearchIssuePresentation(issue: issue)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    StatusBadge(text: presentation.eyebrow, systemImage: "newspaper.fill", tint: issue.topic.tint)
                    Text(issue.displayDate.isEmpty ? issue.topic.title : issue.displayDate)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(presentation.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: issue.topic.systemImage)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(issue.topic.tint)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("Wydanie dnia", systemImage: "text.quote")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(issue.topic.tint)
                    .textCase(.uppercase)

                ResearchLeadParagraphs(
                    paragraphs: presentation.leadParagraphs,
                    keywords: presentation.keywords,
                    tint: issue.topic.tint
                )

                ResearchQuickPoints(points: presentation.quickPoints, tint: issue.topic.tint)
            }

            ResearchSignalSummary(presentation: presentation, tint: issue.topic.tint)

            ResearchKeywordRail(keywords: presentation.keywords, tint: issue.topic.tint)

            HStack(spacing: 10) {
                MetricTile(title: "Newsy", value: "\(issue.articles.count)", systemImage: "doc.text.fill", tint: issue.topic.tint)
                MetricTile(title: "Źródła", value: "\(issue.sourceCount)", systemImage: "link.circle.fill", tint: .blue)
                MetricTile(title: "PDF", value: issue.hasPDF ? "Tak" : "Brak", systemImage: "doc.richtext.fill", tint: issue.hasPDF ? .red : .orange)
            }

            HStack(spacing: 8) {
                StatusBadge(text: issue.status, systemImage: "checkmark.seal.fill", tint: .green)
                if issue.audioArtifact != nil {
                    StatusBadge(text: "Audio", systemImage: "play.circle.fill", tint: .purple)
                }
                if !issue.podcastTopics.isEmpty {
                    StatusBadge(text: "\(issue.podcastTopics.count) tematów podcastu", systemImage: "mic.fill", tint: .orange)
                }
                if packageCount > 1 {
                    StatusBadge(text: "\(packageCount) wydań", systemImage: "calendar", tint: .gray)
                }
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(issue.topic.tint)
                        .frame(width: 4)
                        .padding(.vertical, 18)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(issue.topic.tint.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ResearchLeadParagraphs: View {
    let paragraphs: [String]
    let keywords: [ResearchIssueKeyword]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                HighlightedResearchText(
                    text: paragraph,
                    keywords: keywords,
                    tint: tint,
                    font: index == 0 ? .body.weight(.semibold) : .callout
                )
                .foregroundStyle(index == 0 ? .primary : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ResearchQuickPoints: View {
    let points: [String]
    let tint: Color

    var body: some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("W skrócie")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .textCase(.uppercase)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(points, id: \.self) { point in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(tint)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                                .accessibilityHidden(true)
                            Text(point)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

struct HighlightedResearchText: View {
    let text: String
    let keywords: [ResearchIssueKeyword]
    let tint: Color
    var font: Font = .body
    var lineLimit: Int?

    var body: some View {
        Text(ResearchKeywordHighlighter.attributedText(text, keywords: keywords, tint: tint))
            .font(font)
            .foregroundStyle(.primary)
            .lineSpacing(4)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }
}

private struct ResearchSignalSummary: View {
    let presentation: ResearchIssuePresentation
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(presentation.signalsTitle, systemImage: "bolt.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)

            VStack(spacing: 10) {
                ForEach(presentation.signals) { signal in
                    ResearchSignalRow(signal: signal, tint: tint)

                    if signal.id != presentation.signals.last?.id {
                        Divider()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ResearchSignalRow: View {
    let signal: ResearchIssueSignal
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: signal.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(signal.section.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Text(signal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(signal.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                ResearchArticleBulletList(points: signal.bullets, tint: tint, font: .footnote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ResearchArticleBulletList: View {
    let points: [String]
    let tint: Color
    var font: Font = .callout

    var body: some View {
        if !points.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        Text(point)
                            .font(font)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

private struct ResearchKeywordRail: View {
    let keywords: [ResearchIssueKeyword]
    let tint: Color

    var body: some View {
        if !keywords.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("Słowa kluczowe")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(keywords) { keyword in
                            Label(keyword.title, systemImage: keyword.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(tint.opacity(0.1), in: Capsule())
                                .accessibilityLabel("Słowo kluczowe: \(keyword.title)")
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

private struct ResearchSectionFilterBar: View {
    let topic: ReportTopicKind
    @Binding var selection: ResearchNewsSection?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ResearchSectionChip(title: "Wszystkie", systemImage: "square.grid.2x2.fill", tint: topic.tint, isSelected: selection == nil) {
                    selection = nil
                }

                ForEach(topic.newsSections) { section in
                    ResearchSectionChip(
                        title: section.rawValue,
                        systemImage: section.systemImage,
                        tint: topic.tint,
                        isSelected: selection == section
                    ) {
                        selection = section
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct ResearchSectionChip: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isSelected ? tint : Color(.systemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ResearchArticleCard: View {
    let article: ResearchNewsArticle
    let topic: ReportTopicKind
    var isSaved = false

    private var presentation: ResearchArticlePresentation {
        ResearchArticlePresentation(article: article, topic: topic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: article.section.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(topic.tint)
                    .frame(width: 42, height: 42)
                    .background(topic.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(article.section.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(topic.tint)
                    Text(presentation.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HighlightedResearchText(
                        text: presentation.standfirst,
                        keywords: presentation.keywords,
                        tint: topic.tint,
                        font: .callout
                    )
                    ResearchArticleBulletList(points: Array(presentation.bullets.prefix(2)), tint: topic.tint, font: .footnote)
                }

                Spacer(minLength: 0)

                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Artykuł zapisany")
                }
            }

            HStack(spacing: 8) {
                ForEach(presentation.keywords.prefix(3)) { keyword in
                    Label(keyword.title, systemImage: keyword.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }

                Spacer()

                if let source = presentation.primarySourceTitle {
                    Text(source)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Label("\(presentation.sourceCount)", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ResearchIssueAddOns: View {
    let issue: ResearchNewsIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dodatki do wydania")
                .font(.headline.weight(.semibold))

            VStack(spacing: 0) {
                if let pdf = issue.pdfArtifact {
                    NavigationLink(value: pdf) {
                        PavbotActionRow(title: "Otwórz PDF", subtitle: pdf.title, systemImage: "doc.richtext.fill", tint: .red)
                    }
                    .buttonStyle(.plain)
                } else {
                    MissingReportRow(title: ReportPackageCopy.missingPDFTitle, subtitle: ReportPackageCopy.missingPDFDescription)
                }

                if let report = issue.reportArtifact {
                    Divider().padding(.leading, 50)
                    NavigationLink(value: report) {
                        PavbotActionRow(title: "Otwórz raport źródłowy", subtitle: report.title, systemImage: "doc.text.fill", tint: .blue)
                    }
                    .buttonStyle(.plain)
                }

                if let brief = issue.podcastBriefArtifact {
                    Divider().padding(.leading, 50)
                    NavigationLink(value: brief) {
                        PavbotActionRow(title: "Otwórz brief podcastu", subtitle: brief.title, systemImage: "newspaper.fill", tint: .orange)
                    }
                    .buttonStyle(.plain)
                }

                if let audio = issue.audioArtifact {
                    Divider().padding(.leading, 50)
                    NavigationLink(value: audio) {
                        PavbotActionRow(title: "Odtwórz audio", subtitle: audio.title, systemImage: "play.circle.fill", tint: .purple)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct ResearchArticleReader: View {
    @Environment(ManifestStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotHaptics.self) private var haptics

    let article: ResearchNewsArticle
    let issue: ResearchNewsIssue
    let savedStore: SavedResearchArticleStore

    private var presentation: ResearchArticlePresentation {
        ResearchArticlePresentation(article: article, topic: issue.topic)
    }

    private var canSave: Bool {
        SavedResearchArticleStore.canSave(article: article, issue: issue)
    }

    private var isSaved: Bool {
        savedStore.isSaved(article: article, issue: issue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        StatusBadge(text: article.section.rawValue, systemImage: article.section.systemImage, tint: issue.topic.tint)
                        Text(presentation.title)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        HighlightedResearchText(
                            text: presentation.standfirst,
                            keywords: presentation.keywords,
                            tint: issue.topic.tint,
                            font: .headline
                        )
                        ResearchArticleBulletList(points: presentation.bullets, tint: issue.topic.tint)
                        Divider()
                        ResearchArticleBody(
                            title: "Pełny opis",
                            paragraphs: presentation.paragraphs,
                            keywords: presentation.keywords,
                            tint: issue.topic.tint
                        )
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if !article.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Źródła")
                                .font(.headline.weight(.semibold))
                            ForEach(article.sources) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        PavbotActionRow(title: source.title, subtitle: source.url, systemImage: "link.circle.fill", tint: issue.topic.tint)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    ResearchArticleSecondaryLinks(issue: issue, manifestURLString: store.manifestURLString)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Artykuł")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if canSave {
                        Button {
                            savedStore.toggle(article: article, issue: issue)
                            haptics.play(.success)
                        } label: {
                            Label(isSaved ? "Usuń z zapisanych" : "Zapisz artykuł", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                        }
                        .accessibilityLabel(isSaved ? "Usuń artykuł z zapisanych" : "Zapisz artykuł")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ResearchArticleBody: View {
    let title: String
    let paragraphs: [String]
    let keywords: [ResearchIssueKeyword]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                HighlightedResearchText(text: paragraph, keywords: keywords, tint: tint, font: .callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ResearchArticleSecondaryLinks: View {
    let issue: ResearchNewsIssue
    let manifestURLString: String

    var body: some View {
        VStack(spacing: 0) {
            if let pdf = issue.pdfArtifact, let url = pdf.resolvedURL(manifestURL: URL(string: manifestURLString)) {
                Link(destination: url) {
                    PavbotActionRow(title: "Otwórz PDF", subtitle: pdf.title, systemImage: "doc.richtext.fill", tint: .red)
                }
            }

            if let report = issue.reportArtifact, let url = report.resolvedURL(manifestURL: URL(string: manifestURLString)) {
                Divider().padding(.leading, 50)
                Link(destination: url) {
                    PavbotActionRow(title: "Otwórz raport źródłowy", subtitle: report.title, systemImage: "doc.text.fill", tint: .blue)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ReportTopicPackagesView<Header: View>: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router

    let topic: ReportTopicKind
    let title: String
    let emptyTitle: String
    let emptyDescription: String
    @ViewBuilder var header: () -> Header

    init(
        topic: ReportTopicKind,
        title: String,
        emptyTitle: String,
        emptyDescription: String,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() }
    ) {
        self.topic = topic
        self.title = title
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.header = header
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header()

                if let manifest = store.manifest {
                    let packages = visiblePackages(manifest.reportPackages(for: topic))
                    ReportTopicHeader(topic: topic, packages: packages)

                    if packages.isEmpty {
                        ContentUnavailableView(emptyTitle, systemImage: topic.systemImage, description: Text(emptyDescription))
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        VStack(spacing: 14) {
                            if let latest = packages.first {
                                FeaturedReportPackageCard(package: latest)
                            }

                            ForEach(packages.dropFirst()) { package in
                                ReportPackageCard(package: package)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        ReportPackageCopy.noManifestTitle,
                        systemImage: "doc.badge.questionmark",
                        description: Text(ReportPackageCopy.noManifestDescription)
                    )
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationDestination(for: PavbotArtifact.self) { artifact in
            ArtifactDetailView(artifact: artifact)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.state == .loading)
                .accessibilityLabel(ReportPackageCopy.refreshReportsAccessibilityLabel)
            }
        }
        .refreshable {
            await store.reload()
        }
        .onAppear {
            if router.selectedReportDay == nil {
                router.selectedReportDay = store.manifest?.reportPackages(for: topic).first?.date
            }
        }
        .onChange(of: topic) { _, _ in
            router.selectedReportArtifactIDs = []
            router.selectedReportDay = store.manifest?.reportPackages(for: topic).first?.date
        }
        .onChange(of: store.manifest) { _, manifest in
            guard let manifest else { return }
            if router.selectedReportDay == nil {
                router.selectedReportDay = manifest.reportPackages(for: topic).first?.date
            }
        }
    }

    private func orderedPackages(_ packages: [TopicReportPackage]) -> [TopicReportPackage] {
        guard let selectedReportDay = router.selectedReportDay else {
            return packages
        }
        return packages.sorted { lhs, rhs in
            if lhs.date == selectedReportDay, rhs.date != selectedReportDay {
                return true
            }
            if rhs.date == selectedReportDay, lhs.date != selectedReportDay {
                return false
            }
            return lhs.key > rhs.key
        }
    }

    private func visiblePackages(_ packages: [TopicReportPackage]) -> [TopicReportPackage] {
        let artifactIDs = Set(router.selectedReportArtifactIDs)
        let filteredPackages = packages.compactMap { $0.filteringArtifacts(to: artifactIDs) }
        return orderedPackages(filteredPackages)
    }
}

private struct ResearchTopicPicker: View {
    @Binding var selection: ReportTopicKind

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ResearchTopicButton(topic: .techNews, selection: $selection)
            ResearchTopicButton(topic: .polskaSwiat, selection: $selection)
            ResearchTopicButton(topic: .aktualne, selection: $selection)
        }
    }
}

private struct ResearchTopicButton: View {
    @Environment(PavbotHaptics.self) private var haptics
    let topic: ReportTopicKind
    @Binding var selection: ReportTopicKind

    private var isSelected: Bool {
        selection == topic
    }

    var body: some View {
        Button {
            guard selection != topic else { return }
            selection = topic
            haptics.play(.selection)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: topic.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(topic.tint)
                    .frame(width: 34, height: 34)
                    .background(topic.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(topic.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        }
        .buttonStyle(PavbotInteractiveSurfaceButtonStyle(tint: topic.tint, isSelected: isSelected, cornerRadius: 12))
    }
}

private struct ReportTopicHeader: View {
    let topic: ReportTopicKind
    let packages: [TopicReportPackage]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: topic.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(topic.tint)
                    .frame(width: 48, height: 48)
                    .background(topic.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text(topic.title)
                        .font(.title2.weight(.bold))
                    Text(topic.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                MetricTile(title: ReportPackageCopy.reportsMetricTitle, value: "\(packages.count)", systemImage: "doc.text.fill", tint: topic.tint)
                MetricTile(title: "PDFs", value: "\(packages.filter(\.hasPDF).count)", systemImage: "doc.richtext.fill", tint: .red)
                MetricTile(title: ReportPackageCopy.latestMetricTitle, value: packages.first?.date ?? "-", subtitle: packages.first?.time, systemImage: "clock.fill", tint: .purple)
            }
        }
    }
}

private struct FeaturedReportPackageCard: View {
    let package: TopicReportPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(text: ReportPackageCopy.latestBadgeTitle, systemImage: "sparkles", tint: package.topic.tint)
                    Text(package.displayDate.isEmpty ? package.topic.title : package.displayDate)
                        .font(.title2.weight(.bold))
                    Text(featuredSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: package.topic.systemImage)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(package.topic.tint)
            }

            ReportPackageActions(package: package, prominent: true)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), package.topic.tint.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private var featuredSubtitle: String {
        if package.pdfReport != nil, package.researchReport != nil {
            return "Pakiet zawiera natywny research oraz czytelny PDF do przeglądania na telefonie."
        }
        if package.researchReport != nil {
            return "Raport research jest gotowy. PDF nie jest jeszcze dostępny dla tej publikacji."
        }
        return "Najnowsza paczka plików dla tego tematu."
    }
}

private struct ReportPackageCard: View {
    let package: TopicReportPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ArtifactIconBadge(kind: package.preferredPreviewArtifact?.viewerKind ?? .file)

                VStack(alignment: .leading, spacing: 4) {
                    Text(package.displayDate.isEmpty ? "Paczka raportu" : package.displayDate)
                        .font(.headline.weight(.semibold))
                    Text("\(package.artifacts.count) \(ReportPackageCopy.filesLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !package.hasPDF {
                    StatusBadge(text: ReportPackageCopy.missingPDFTitle, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
            }

            ReportPackageActions(package: package, prominent: false)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ReportPackageActions: View {
    let package: TopicReportPackage
    let prominent: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let report = package.researchReport {
                NavigationLink(value: report) {
                    ReportActionRow(
                        title: ReportPackageCopy.openResearchTitle,
                        subtitle: report.title,
                        systemImage: "doc.text.fill",
                        tint: .blue,
                        prominent: prominent
                    )
                }
                .buttonStyle(.plain)
            }

            if let pdf = package.pdfReport {
                rowDivider
                NavigationLink(value: pdf) {
                    ReportActionRow(
                        title: ReportPackageCopy.openPDFTitle,
                        subtitle: pdf.title,
                        systemImage: "doc.richtext.fill",
                        tint: .red,
                        prominent: prominent
                    )
                }
                .buttonStyle(.plain)
            } else if package.researchReport != nil {
                rowDivider
                MissingReportRow(title: ReportPackageCopy.missingPDFTitle, subtitle: ReportPackageCopy.missingPDFDescription)
            }

            if let briefPDF = package.podcastBriefPDF {
                rowDivider
                NavigationLink(value: briefPDF) {
                    ReportActionRow(
                        title: ReportPackageCopy.openPodcastBriefTitle,
                        subtitle: briefPDF.title,
                        systemImage: "newspaper.fill",
                        tint: .orange,
                        prominent: prominent
                    )
                }
                .buttonStyle(.plain)
            }

            if let audio = package.primaryAudio {
                rowDivider
                NavigationLink(value: audio) {
                    ReportActionRow(
                        title: ReportPackageCopy.playAudioTitle,
                        subtitle: audio.title,
                        systemImage: "play.circle.fill",
                        tint: .purple,
                        prominent: prominent
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(package.additionalArtifacts.prefix(3)) { artifact in
                rowDivider
                NavigationLink(value: artifact) {
                    ReportActionRow(
                        title: artifact.type.label,
                        subtitle: artifact.title,
                        systemImage: artifact.viewerKind.systemImage,
                        tint: artifact.viewerKind.tint,
                        prominent: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 42)
    }
}

private struct ReportActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let prominent: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(prominent ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(prominent ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, prominent ? 12 : 9)
    }
}

private struct MissingReportRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.badge.clock")
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 9)
    }
}
