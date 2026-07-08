import SwiftUI

enum ReportPackageCopy {
    static let emptyResearchTitle = "Brak raportów Przegląd"
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

struct ResearchLoadRequest: Hashable {
    let manifestGeneratedAt: String
    let manifestURLString: String
    let topic: ReportTopicKind
    let selectedDay: String?
    let selectedArtifactIDs: [String]
}

struct ResearchLoadTrigger: Hashable {
    let request: ResearchLoadRequest
    let routeRevision: Int
    let isResearchActive: Bool
}

struct ResearchArticleCardSnapshot: Identifiable, Equatable {
    let article: ResearchNewsArticle
    let presentation: PavbotNewsStoryPresentation

    var id: String { article.id }
}

struct ResearchArticleListSnapshot: Equatable {
    let issuePresentation: ResearchIssuePresentation
    let articles: [ResearchArticleCardSnapshot]
    let topArticle: ResearchArticleCardSnapshot?
    let remainingArticles: [ResearchArticleCardSnapshot]

    init(issue: ResearchNewsIssue, selectedSection: ResearchNewsSection?, searchText: String) {
        issuePresentation = ResearchIssuePresentation(issue: issue)
        let cardSnapshots = issue
            .filteredArticles(section: selectedSection, query: searchText)
            .map { article in
                let articlePresentation = ResearchArticlePresentation(article: article, topic: issue.topic)
                return ResearchArticleCardSnapshot(
                    article: article,
                    presentation: PavbotNewsStoryPresentation(
                        id: article.id,
                        section: article.section.rawValue,
                        sectionSystemImage: article.section.systemImage,
                        title: articlePresentation.title,
                        lead: articlePresentation.standfirst,
                        priority: article.priority,
                        facts: articlePresentation.bullets,
                        sources: article.sources,
                        tags: articlePresentation.keywords.map(\.title),
                        canReadAloud: false
                    )
                )
            }
        let selectedTopArticle = cardSnapshots.first { PavbotNewsPriorityStyle($0.article.priority) == .high } ?? cardSnapshots.first

        articles = cardSnapshots
        topArticle = selectedTopArticle
        remainingArticles = selectedTopArticle.map { top in
            cardSnapshots.filter { $0.id != top.id }
        } ?? cardSnapshots
    }
}

struct ResearchArticleSnapshotKey: Hashable {
    let issueID: String
    let selectedSectionID: String?
    let searchText: String
    let articleIDs: [String]

    init(issue: ResearchNewsIssue, selectedSection: ResearchNewsSection?, searchText: String) {
        issueID = issue.id
        selectedSectionID = selectedSection?.id
        self.searchText = searchText
        articleIDs = issue.articles.map(\.id)
    }
}

struct ResearchView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(PavbotAudioSessionCoordinator.self) private var audioCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var newsStore = ResearchNewsStore()
    @State private var mobileNewsStore = MobileNewsStore()
    @State private var mobileSpeechController = MobileNewsSpeechController()
    @StateObject private var podcastSpeechController = PodcastScriptSpeechController()
    @State private var savedResearchStore = SavedResearchArticleStore()
    @State private var selectedSection: ResearchNewsSection?
    @State private var selectedArticle: ResearchNewsArticle?
    @State private var selectedMobileArticle: MobileNewsArticle?
    @State private var isSavedResearchPresented = false
    @State private var handledReportRouteRevision = 0

    var body: some View {
        @Bindable var router = router

        GeometryReader { proxy in
            let layout = PavbotAdaptiveLayout.resolve(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            PavbotPremiumScreenScaffold(layout: layout) {
                ResearchLibraryHeader(
                    topic: router.selectedResearchTopic,
                    packageCount: nativeContentPackages(
                        from: store.manifest?.reportPackages(for: router.selectedResearchTopic) ?? [],
                        topic: router.selectedResearchTopic
                    ).count,
                    savedCount: savedResearchStore.savedArticles.count,
                    isRefreshing: isRefreshingSelectedResearchContent,
                    layout: layout
                )

                ResearchTopicPicker(selection: $router.selectedResearchTopic)

                if let manifest = store.manifest {
                    let packages = nativeContentPackages(
                        from: manifest.reportPackages(for: router.selectedResearchTopic),
                        topic: router.selectedResearchTopic
                    )
                    ResearchRunPicker(
                        topic: router.selectedResearchTopic,
                        packages: packages,
                        selectedReportDay: $router.selectedReportDay
                    )

                    if router.selectedResearchTopic == .aktualne {
                        MobileNewsNativeContent(
                            packages: packages,
                            magazine: mobileNewsStore.magazine,
                            state: mobileNewsStore.state,
                            cacheNotice: mobileNewsStore.cacheNotice,
                            selectedArticle: $selectedMobileArticle,
                            speechController: mobileSpeechController,
                            podcastSpeechController: podcastSpeechController,
                            savedStore: savedResearchStore,
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
                            speechController: mobileSpeechController,
                            savedStore: savedResearchStore,
                            reload: {
                                Task { await loadNewsIssue() }
                            }
                        )
                    }
                } else {
                    PavbotStateCard(
                        title: ReportPackageCopy.noManifestTitle,
                        message: ReportPackageCopy.noManifestDescription,
                        systemImage: "doc.badge.questionmark",
                        tint: .orange,
                        actionTitle: "Otwórz ustawienia",
                        actionSystemImage: "gearshape"
                    ) {
                        router.selectedTab = .settings
                    }
                }
            }
            .environment(\.pavbotAdaptiveLayout, layout)
        }
        .navigationTitle("Przegląd")
        .navigationDestination(for: PavbotArtifact.self) { artifact in
            ArtifactDetailView(artifact: artifact)
        }
        .sheet(item: $selectedArticle) { article in
            if let issue = newsStore.issue {
                ResearchArticleReader(
                    article: article,
                    issue: issue,
                    speechController: mobileSpeechController,
                    savedStore: savedResearchStore
                )
                    .pavbotLargeObjectPresentation()
            }
        }
        .sheet(item: $selectedMobileArticle) { article in
            if let magazine = mobileNewsStore.magazine {
                MobileNewsArticleReader(
                    article: article,
                    magazine: magazine,
                    speechController: mobileSpeechController,
                    savedStore: savedResearchStore
                )
                .pavbotLargeObjectPresentation()
            }
        }
        .sheet(isPresented: $isSavedResearchPresented) {
            SavedResearchArticlesView(store: savedResearchStore)
                .pavbotLargeObjectPresentation()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isSavedResearchPresented = true
                } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel("Otwórz zapisane artykuły Przegląd")

                PavbotRefreshToolbarButton(
                    isRefreshing: isRefreshingSelectedResearchContent,
                    accessibilityLabel: ReportPackageCopy.refreshReportsAccessibilityLabel,
                    accessibilityHint: "Odświeża manifest i wybraną kartę Przegląd."
                ) {
                    Task {
                        await store.reload()
                        syncSelectedReportDayToLatestIfNeeded(force: true)
                        await loadSelectedResearchContent()
                    }
                }
            }
        }
        .refreshable {
            await store.reload()
            syncSelectedReportDayToLatestIfNeeded(force: true)
            await loadSelectedResearchContent()
        }
        .task(id: researchLoadTrigger) {
            let trigger = researchLoadTrigger
            await handleResearchLoadTrigger(trigger)
        }
        .onAppear {
            mobileSpeechController.configureAudioCoordinator(audioCoordinator)
            podcastSpeechController.configureAudioCoordinator(audioCoordinator)
            syncSelectedReportDayToLatestIfNeeded()
        }
        .onChange(of: router.selectedResearchTopic) { _, topic in
            router.selectedReportArtifactIDs = []
            syncSelectedReportDayToLatestIfNeeded(topic: topic, force: true)
            selectedSection = nil
            selectedArticle = nil
            selectedMobileArticle = nil
            if router.selectedTab == .research {
                Task {
                    await loadSelectedResearchContent()
                    await resolvePendingAudioArticleRouteIfNeeded()
                }
            }
        }
        .onChange(of: router.selectedTab) { _, tab in
            guard tab == .research else { return }
            Task {
                await handleResearchActivation()
            }
        }
        .onChange(of: router.pendingAudioArticleRoute) { _, route in
            guard route != nil else { return }
            Task {
                await resolvePendingAudioArticleRouteIfNeeded()
            }
        }
        .onChange(of: store.manifest) { _, manifest in
            guard let manifest else { return }
            syncSelectedReportDayToLatestIfNeeded(manifest: manifest, force: true)
        }
        .pavbotTabInfo(PavbotTabInfoContent.research(topicTitle: router.selectedResearchTopic.title, topicSystemImage: router.selectedResearchTopic.systemImage, topicTint: router.selectedResearchTopic.tint))
    }

    private var researchLoadRequest: ResearchLoadRequest {
        ResearchLoadRequest(
            manifestGeneratedAt: store.manifest?.generatedAt ?? "no-manifest",
            manifestURLString: store.manifestURLString,
            topic: router.selectedResearchTopic,
            selectedDay: router.selectedReportDay,
            selectedArtifactIDs: router.selectedReportArtifactIDs
        )
    }

    private var researchLoadTrigger: ResearchLoadTrigger {
        ResearchLoadTrigger(
            request: researchLoadRequest,
            routeRevision: router.reportRouteRevision,
            isResearchActive: router.selectedTab == .research
        )
    }

    private func handleResearchLoadTrigger(_ trigger: ResearchLoadTrigger) async {
        guard trigger.isResearchActive else { return }
        if trigger.routeRevision != handledReportRouteRevision {
            handledReportRouteRevision = trigger.routeRevision
            await store.reload(minimumInterval: 0)
            guard !Task.isCancelled else { return }
        }
        await loadSelectedResearchContent()
        await resolvePendingAudioArticleRouteIfNeeded()
    }

    private func handleResearchActivation() async {
        syncSelectedReportDayToLatestIfNeeded()
        await loadSelectedResearchContent()
        await resolvePendingAudioArticleRouteIfNeeded()
    }

    private func loadNewsIssue() async {
        guard let manifest = store.manifest else { return }
        guard router.selectedResearchTopic != .aktualne else { return }
        await newsStore.load(
            packages: nativeContentPackages(
                from: manifest.reportPackages(for: router.selectedResearchTopic),
                topic: router.selectedResearchTopic
            ),
            manifestURLString: store.manifestURLString,
            topic: router.selectedResearchTopic,
            selectedDay: router.selectedReportDay,
            selectedArtifactIDs: router.selectedReportArtifactIDs
        )
    }

    private func loadMobileMagazine() async {
        guard let manifest = store.manifest else { return }
        await mobileNewsStore.load(
            packages: nativeContentPackages(
                from: manifest.reportPackages(for: .aktualne),
                topic: .aktualne
            ),
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

    private func syncSelectedReportDayToLatestIfNeeded(
        topic: ReportTopicKind? = nil,
        manifest: PavbotManifest? = nil,
        force: Bool = false
    ) {
        let activeManifest = manifest ?? store.manifest
        let activeTopic = topic ?? router.selectedResearchTopic
        if !router.selectedReportArtifactIDs.isEmpty {
            guard force && activeTopic == .aktualne else { return }
            router.selectedReportArtifactIDs = []
        }
        let packages = nativeContentPackages(
            from: activeManifest?.reportPackages(for: activeTopic) ?? [],
            topic: activeTopic
        )
        guard force || !hasSelectedReportDay(in: packages) else { return }
        guard let latestReportKey = latestReportKey(in: packages) else { return }
        if router.selectedReportDay != latestReportKey {
            router.selectedReportDay = latestReportKey
        }
    }

    private func latestReportKey(in packages: [TopicReportPackage]) -> String? {
        packages.first?.key
    }

    private func hasSelectedReportDay(in packages: [TopicReportPackage]) -> Bool {
        guard let selectedReportDay = router.selectedReportDay else { return false }
        return packages.contains { package in
            package.key == selectedReportDay
                || package.date == selectedReportDay
                || package.key.hasPrefix(selectedReportDay)
        }
    }

    private func resolvePendingAudioArticleRouteIfNeeded() async {
        guard let route = router.pendingAudioArticleRoute else { return }

        switch route {
        case .mobileNewsArticle(let topic, let articleID):
            guard topic == .aktualne else { return }
            if router.selectedResearchTopic != .aktualne {
                router.selectedResearchTopic = .aktualne
                return
            }
            if mobileNewsStore.magazine == nil {
                await loadMobileMagazine()
            }
            guard let article = mobileNewsStore.magazine?.sections
                .flatMap(\.articles)
                .first(where: { $0.id == articleID })
            else { return }
            selectedMobileArticle = article
            router.clearPendingAudioArticleRoute(route)

        case .researchArticle(let topic, let articleID):
            if router.selectedResearchTopic != topic {
                router.selectedResearchTopic = topic
                return
            }
            if newsStore.issue?.topic != topic {
                await loadNewsIssue()
            }
            guard let article = newsStore.issue?.articles.first(where: { $0.id == articleID }) else { return }
            selectedArticle = article
            router.clearPendingAudioArticleRoute(route)
        }
    }

    private var isRefreshingSelectedResearchContent: Bool {
        store.state == .loading
            || newsStore.state == .loading
            || mobileNewsStore.state == .loading
    }

    private func nativeContentPackages(
        from packages: [TopicReportPackage],
        topic: ReportTopicKind
    ) -> [TopicReportPackage] {
        TopicReportPackage.nativeContentPackages(for: topic, in: packages)
    }
}

private struct ResearchRunPicker: View {
    let topic: ReportTopicKind
    let packages: [TopicReportPackage]
    @Binding var selectedReportDay: String?

    private var recentReportDays: [String] {
        TopicReportPackage.recentReportDays(in: packages, limit: 4)
    }

    private var selectedReportDate: String? {
        let candidate = TopicReportPackage.selectedReportDate(in: packages, selectedReportDay: selectedReportDay)
        if let candidate, recentReportDays.contains(candidate) {
            return candidate
        }
        return recentReportDays.first
    }

    private var selectedDayPackages: [TopicReportPackage] {
        packages(on: selectedReportDate)
    }

    private var daySummary: String {
        recentReportDays.count == 1 ? "Ostatni dzień" : "Ostatnie \(recentReportDays.count) dni"
    }

    var body: some View {
        if shouldShowPicker {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Przebieg", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(topic.tint)
                        .textCase(.uppercase)

                    Spacer(minLength: 8)

                    Text(daySummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if recentReportDays.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentReportDays, id: \.self) { day in
                                Button {
                                    selectedReportDay = packages(on: day).first?.key ?? day
                                } label: {
                                    ResearchDayFilterChip(
                                        date: day,
                                        isSelected: day == selectedReportDate,
                                        tint: topic.tint
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Pokaż przebiegi z dnia \(day)")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if selectedDayPackages.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedDayPackages) { package in
                                Button {
                                    selectedReportDay = package.key
                                } label: {
                                    ResearchRunChip(
                                        package: package,
                                        isSelected: package.id == selectedPackageID,
                                        tint: topic.tint
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Wybierz przebieg \(package.displayDate)")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(12)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(topic.tint.opacity(0.16), lineWidth: 1)
            }
        }
    }

    private var shouldShowPicker: Bool {
        recentReportDays.count > 1 || selectedDayPackages.count > 1
    }

    private var selectedPackageID: String? {
        TopicReportPackage.selectedPackage(in: selectedDayPackages, selectedReportDay: selectedReportDay)?.id
            ?? selectedDayPackages.first?.id
    }

    private func packages(on selectedReportDate: String?) -> [TopicReportPackage] {
        TopicReportPackage.reportPackages(in: packages, on: selectedReportDate)
    }
}

private struct ResearchDayFilterChip: View {
    let date: String
    let isSelected: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "calendar")
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? .white : tint)
                .frame(width: 16, height: 16)

            Text(date)
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? .white : tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .background(isSelected ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.5) : tint.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct ResearchRunChip: View {
    let package: TopicReportPackage
    let isSelected: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "calendar")
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? tint : .secondary)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? tint : .primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 42)
        .background(isSelected ? tint.opacity(0.12) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.5) : Color(.separator).opacity(0.2), lineWidth: 1)
        }
    }

    private var title: String {
        runPeriodTitle
    }

    private var subtitle: String {
        let fileCount = "\(package.artifacts.count) \(ReportPackageCopy.filesLabel)"
        if let time = clean(package.time) {
            return "\(time) · \(fileCount)"
        }
        return "\(package.date ?? package.key) · \(fileCount)"
    }

    private var runPeriodTitle: String {
        guard let time = clean(package.time),
              let hour = Int(time.prefix(2))
        else {
            return "Poranna"
        }

        switch hour {
        case 0..<12:
            return "Poranna"
        case 12..<17:
            return "Dzienna"
        default:
            return "Wieczorna"
        }
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ResearchLibraryHeader: View {
    let topic: ReportTopicKind
    let packageCount: Int
    let savedCount: Int
    let isRefreshing: Bool
    let layout: PavbotAdaptiveLayout

    var body: some View {
        PavbotPremiumCard(tint: topic.tint, cornerRadius: 22, horizontalPadding: 16, verticalPadding: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(topic.tint.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: topic.tint.opacity(0.22), radius: 10, x: 0, y: 6)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Przegląd")
                        .font(.title2.weight(.bold))
                    Text(layout.usesDashboardLayout
                        ? "Raporty, magazyny i zapisane artykuły w newsroomowym układzie."
                        : "Najpierw konkretne newsy, potem pełny kontekst wydania.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        StatusBadge(text: topic.title, systemImage: topic.systemImage, tint: topic.tint)
                        StatusBadge(text: "\(packageCount) pak.", systemImage: "shippingbox.fill", tint: .blue)
                        StatusBadge(text: "\(savedCount) zapis.", systemImage: "bookmark.fill", tint: .purple)
                        if isRefreshing {
                            StatusBadge(text: "Odświeżam", systemImage: "arrow.clockwise", tint: .blue)
                        }
                    }
                }
            }
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
    let speechController: MobileNewsSpeechController
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
                    researchLoadingCard
                }
            case .loading:
                if let issue {
                    PavbotCacheNoticeBanner(text: PavbotCacheNoticeCopy.refreshing(context: "wydanie Przegląd"))
                    issueContent(issue)
                } else {
                    researchLoadingCard
                }
            case .failed(let error):
                if let issue {
                    PavbotCacheNoticeBanner(text: error.message)
                    issueContent(issue)
                } else {
                    PavbotStateCard(error: error, action: reload)
                }
            case .loaded:
                if let issue {
                    issueContent(issue)
                } else {
                    PavbotStateCard(
                        title: ReportPackageCopy.emptyResearchTitle,
                        message: ReportPackageCopy.emptyResearchDescription,
                        systemImage: topic.systemImage,
                        tint: topic.tint,
                        actionTitle: "Odśwież Przegląd",
                        actionSystemImage: "arrow.clockwise",
                        action: reload
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func issueContent(_ issue: ResearchNewsIssue) -> some View {
        if let cacheNotice {
            PavbotCacheNoticeBanner(text: cacheNotice)
        }

        ResearchArticleSnapshotHost(
            issue: issue,
            topic: topic,
            packageCount: packages.count,
            selectedSection: $selectedSection,
            selectedArticle: $selectedArticle,
            speechController: speechController,
            savedStore: savedStore
        )
    }

    private var researchLoadingCard: some View {
        PavbotLoadingStateCard(
            title: "Ładuję Przegląd",
            message: "Pobieram najnowsze wydanie i przygotowuję karty artykułów.",
            systemImage: topic.systemImage,
            tint: topic.tint
        )
    }
}

private struct ResearchArticleSnapshotHost: View {
    let issue: ResearchNewsIssue
    let topic: ReportTopicKind
    let packageCount: Int
    @Binding var selectedSection: ResearchNewsSection?
    @Binding var selectedArticle: ResearchNewsArticle?
    let speechController: MobileNewsSpeechController
    let savedStore: SavedResearchArticleStore

    var body: some View {
        let snapshot = ResearchArticleListSnapshot(issue: issue, selectedSection: selectedSection, searchText: "")
        snapshotContent(snapshot)
    }

    @ViewBuilder
    private func snapshotContent(_ articleSnapshot: ResearchArticleListSnapshot) -> some View {
        ResearchIssueHero(
            issue: issue,
            presentation: articleSnapshot.issuePresentation,
            packageCount: packageCount
        )

        MobileNewsSpeechMiniPlayerHost(speechController: speechController)

        ResearchSectionFilterBar(topic: topic, selection: $selectedSection)

        if articleSnapshot.articles.isEmpty {
            PavbotStateCard(
                title: "Brak newsów dla filtra",
                message: "Zmień sekcję, żeby zobaczyć inne artykuły z wydania.",
                systemImage: "line.3.horizontal.decrease.circle",
                tint: topic.tint
            )
        } else {
            VStack(spacing: 12) {
                if let topArticle = articleSnapshot.topArticle {
                    Button {
                        selectedArticle = topArticle.article
                    } label: {
                        ResearchArticleCard(
                            article: topArticle.article,
                            presentation: topArticle.presentation,
                            topic: topic,
                            isSaved: savedStore.isSaved(article: topArticle.article, issue: issue),
                            isFeatured: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(articleSnapshot.remainingArticles) { articleSnapshot in
                    Button {
                        selectedArticle = articleSnapshot.article
                    } label: {
                        ResearchArticleCard(
                            article: articleSnapshot.article,
                            presentation: articleSnapshot.presentation,
                            topic: topic,
                            isSaved: savedStore.isSaved(article: articleSnapshot.article, issue: issue)
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
    let speechController: MobileNewsSpeechController
    let podcastSpeechController: PodcastScriptSpeechController
    let savedStore: SavedResearchArticleStore
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
                    mobileNewsLoadingCard
                }
            case .loading:
                if let magazine {
                    PavbotCacheNoticeBanner(text: PavbotCacheNoticeCopy.refreshing(context: "magazyn Aktualne"))
                    magazineContent(magazine)
                } else {
                    mobileNewsLoadingCard
                }
            case .failed(let error):
                if let magazine {
                    PavbotCacheNoticeBanner(text: error.message)
                    magazineContent(magazine)
                } else {
                    PavbotStateCard(error: error, action: reload)
                }
            case .loaded:
                if let magazine {
                    magazineContent(magazine)
                } else {
                    PavbotStateCard(
                        title: "Brak magazynu Aktualne",
                        message: "Odśwież manifest po publikacji automatyzacji 10:15.",
                        systemImage: ReportTopicKind.aktualne.systemImage,
                        tint: ReportTopicKind.aktualne.tint,
                        actionTitle: "Odśwież Aktualne",
                        actionSystemImage: "arrow.clockwise",
                        action: reload
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func magazineContent(_ magazine: MobileNewsMagazine) -> some View {
        if let cacheNotice {
            PavbotCacheNoticeBanner(text: cacheNotice)
        }

        MobileNewsHero(magazine: magazine, packageCount: packages.count)

        MobileNewsSpeechMiniPlayerHost(speechController: speechController)

        PodcastScriptSpeechMiniPlayerHost(speechController: podcastSpeechController)

        let sections = magazine.sections
        if sections.isEmpty {
            PavbotStateCard(
                title: "Brak artykułów",
                message: "Magazyn Aktualne nie zawiera jeszcze artykułów do pokazania.",
                systemImage: "newspaper",
                tint: .orange
            )
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections) { section in
                    MobileNewsSectionBlock(
                        section: section,
                        magazine: magazine,
                        selectedArticle: $selectedArticle,
                        speechController: speechController,
                        savedStore: savedStore
                    )
                }
            }
        }

        MobileNewsAddOns(magazine: magazine, podcastSpeechController: podcastSpeechController)
    }

    private var mobileNewsLoadingCard: some View {
        PavbotLoadingStateCard(
            title: "Ładuję Aktualne",
            message: "Pobieram magazyn dnia i przygotowuję teksty do czytania na głos.",
            systemImage: ReportTopicKind.aktualne.systemImage,
            tint: ReportTopicKind.aktualne.tint
        )
    }
}

private struct MobileNewsSpeechMiniPlayerHost: View {
    @ObservedObject var speechController: MobileNewsSpeechController

    var body: some View {
        if speechController.hasActivePlayback {
            MobileNewsSpeechMiniPlayer(speechController: speechController)
        }
    }
}

private struct PodcastScriptSpeechMiniPlayerHost: View {
    @ObservedObject var speechController: PodcastScriptSpeechController

    var body: some View {
        if speechController.hasActivePlayback {
            PodcastScriptSpeechMiniPlayer(speechController: speechController)
        }
    }
}

private struct MobileNewsSpeechMiniPlayer: View {
    let speechController: MobileNewsSpeechController
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
                PavbotInlineErrorNotice(message: errorMessage, tint: .orange)
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
                PavbotInlineErrorNotice(message: errorMessage, tint: .purple)
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
    @State private var isContextExpanded = false

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

            DisclosureGroup(isExpanded: $isContextExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(magazine.leadParagraphs.enumerated()), id: \.offset) { index, paragraph in
                        Text(paragraph)
                            .font(index == 0 ? .body.weight(.semibold) : .callout)
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Kontekst wydania", systemImage: "text.quote")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
            }
            .tint(.orange)
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
    let magazine: MobileNewsMagazine
    @Binding var selectedArticle: MobileNewsArticle?
    let speechController: MobileNewsSpeechController
    let savedStore: SavedResearchArticleStore

    private var topArticle: MobileNewsArticle? {
        section.articles.first { PavbotNewsPriorityStyle($0.priority) == .high } ?? section.articles.first
    }

    private var remainingArticles: [MobileNewsArticle] {
        guard let topArticle else { return section.articles }
        return section.articles.filter { $0.id != topArticle.id }
    }

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
                if let topArticle {
                    MobileNewsArticleRow(
                        article: topArticle,
                        magazine: magazine,
                        selectedArticle: $selectedArticle,
                        speechController: speechController,
                        savedStore: savedStore,
                        isFeatured: true
                    )
                }

                ForEach(remainingArticles) { article in
                    MobileNewsArticleRow(
                        article: article,
                        magazine: magazine,
                        selectedArticle: $selectedArticle,
                        speechController: speechController,
                        savedStore: savedStore
                    )
                }
            }
        }
    }
}

private struct MobileNewsArticleRow: View {
    let article: MobileNewsArticle
    let magazine: MobileNewsMagazine
    @Binding var selectedArticle: MobileNewsArticle?
    let speechController: MobileNewsSpeechController
    let savedStore: SavedResearchArticleStore
    var isFeatured = false

    private var isSaved: Bool {
        savedStore.isSaved(article: article, magazine: magazine)
    }

    private var canReadAloud: Bool {
        !article.ttsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        MobileNewsArticleSpeechActionHost(
            article: article,
            magazine: magazine,
            selectedArticle: $selectedArticle,
            speechController: speechController,
            isFeatured: isFeatured,
            isSaved: isSaved,
            canReadAloud: canReadAloud
        )
    }
}

private struct MobileNewsArticleSpeechActionHost: View {
    @Environment(PavbotHaptics.self) private var haptics
    let article: MobileNewsArticle
    let magazine: MobileNewsMagazine
    @Binding var selectedArticle: MobileNewsArticle?
    @ObservedObject var speechController: MobileNewsSpeechController
    let isFeatured: Bool
    let isSaved: Bool
    let canReadAloud: Bool

    private var isCurrent: Bool {
        speechController.currentArticleID == article.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                haptics.play(.lightImpact)
                selectedArticle = article
            } label: {
                MobileNewsArticleCard(
                    article: article,
                    isSaved: isSaved,
                    isActiveRead: isCurrent,
                    isFeatured: isFeatured
                )
            }
            .buttonStyle(.plain)

            if canReadAloud {
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
            }

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
                PavbotInlineErrorNotice(message: errorMessage, tint: .orange)
                    .padding(.horizontal, 4)
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
            speechController.speak(
                article,
                destination: .mobileNewsArticle(topic: .aktualne, articleID: article.id)
            )
        }
        haptics.play(.lightImpact)
    }
}

private struct MobileNewsArticleCard: View {
    let article: MobileNewsArticle
    var isSaved = false
    var isActiveRead = false
    var isFeatured = false

    var body: some View {
        PavbotNewsStoryCard(
            presentation: PavbotNewsStoryPresentation(
                id: article.id,
                section: article.section,
                sectionSystemImage: mobileNewsSectionSystemImage(for: article.section),
                title: article.title,
                lead: article.lead,
                priority: article.priority,
                facts: article.facts,
                sources: article.sources,
                tags: article.tags,
                canReadAloud: !article.ttsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ),
            tint: .orange,
            isSaved: isSaved,
            isActiveRead: isActiveRead,
            isFeatured: isFeatured
        )
    }

    private func mobileNewsSectionSystemImage(for section: String) -> String {
        switch section.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() {
        case let value where value.contains("polska"):
            "flag.fill"
        case let value where value.contains("polityka"):
            "building.columns.fill"
        case let value where value.contains("swiat") || value.contains("zagraniczne"):
            "globe.europe.africa.fill"
        case let value where value.contains("technologia"):
            "cpu.fill"
        case let value where value.contains("pogoda"):
            "cloud.sun.fill"
        default:
            "newspaper.fill"
        }
    }
}

private struct MobileNewsAddOns: View {
    @Environment(ManifestStore.self) private var store

    let magazine: MobileNewsMagazine
    let podcastSpeechController: PodcastScriptSpeechController

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
                        PavbotActionRow(title: "MP3 niedostępne", subtitle: "Odśwież manifest z publicznym adresem GitHub.", systemImage: "play.slash.fill", tint: .secondary)
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
                PavbotInlineErrorNotice(message: errorMessage, tint: .purple)
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
            speechController.errorMessage = "Brak publicznego adresu tekstu podcastu. Odśwież manifest z publicznym adresem GitHub."
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
            speechController.errorMessage = "Brak publicznego adresu transkrypcji. Odśwież manifest z publicznym adresem GitHub."
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
    @Environment(PavbotHaptics.self) private var haptics

    let article: MobileNewsArticle
    let magazine: MobileNewsMagazine
    @ObservedObject var speechController: MobileNewsSpeechController
    let savedStore: SavedResearchArticleStore

    private var isSaved: Bool {
        savedStore.isSaved(article: article, magazine: magazine)
    }

    private var canReadAloud: Bool {
        !article.ttsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

                        if canReadAloud {
                            MobileNewsSpeechControls(article: article, speechController: speechController)
                        }

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        savedStore.toggle(article: article, magazine: magazine)
                        haptics.play(.success)
                    } label: {
                        Label(isSaved ? "Usuń z zapisanych" : "Zapisz artykuł", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(isSaved ? "Usuń artykuł z zapisanych" : "Zapisz artykuł")
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

private struct MobileNewsSpeechControls: View {
    @Environment(PavbotHaptics.self) private var haptics
    let article: MobileNewsArticle
    let speechController: MobileNewsSpeechController
    var destination: PavbotAudioDestination?

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
                        speechController.speak(article, destination: destination)
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
                PavbotInlineErrorNotice(message: errorMessage, tint: .orange)
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

private struct ResearchArticleSpeechControlsHost: View {
    let article: MobileNewsArticle
    @ObservedObject var speechController: MobileNewsSpeechController
    let destination: PavbotAudioDestination

    var body: some View {
        MobileNewsSpeechControls(article: article, speechController: speechController, destination: destination)
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

private struct ResearchIssueHero: View {
    let issue: ResearchNewsIssue
    let presentation: ResearchIssuePresentation
    let packageCount: Int
    @State private var isContextExpanded = false

    var body: some View {
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

            DisclosureGroup(isExpanded: $isContextExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    ResearchLeadParagraphs(
                        paragraphs: presentation.leadParagraphs,
                        keywords: presentation.keywords,
                        tint: issue.topic.tint
                    )

                    ResearchQuickPoints(points: presentation.quickPoints, tint: issue.topic.tint)
                }
                .padding(.top, 8)
            } label: {
                Label("Kontekst wydania", systemImage: "text.quote")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(issue.topic.tint)
                    .textCase(.uppercase)
            }
            .tint(issue.topic.tint)
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
                            PavbotArticleTagChip(
                                title: keyword.title,
                                systemImage: keyword.systemImage,
                                tint: tint,
                                accessibilityPrefix: "Słowo kluczowe"
                            )
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
    let presentation: PavbotNewsStoryPresentation
    let topic: ReportTopicKind
    var isSaved = false
    var isFeatured = false

    var body: some View {
        if isFeatured {
            PavbotTopStoryCard(
                presentation: presentation,
                tint: topic.tint,
                isSaved: isSaved
            )
        } else {
            PavbotNewsStoryCard(
                presentation: presentation,
                tint: topic.tint,
                isSaved: isSaved,
                isFeatured: false
            )
        }
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
    let speechController: MobileNewsSpeechController
    let savedStore: SavedResearchArticleStore

    private let presentation: ResearchArticlePresentation
    private let speechArticle: MobileNewsArticle

    init(
        article: ResearchNewsArticle,
        issue: ResearchNewsIssue,
        speechController: MobileNewsSpeechController,
        savedStore: SavedResearchArticleStore
    ) {
        self.article = article
        self.issue = issue
        self.speechController = speechController
        self.savedStore = savedStore
        self.presentation = ResearchArticlePresentation(article: article, topic: issue.topic)
        self.speechArticle = MobileNewsArticle(researchArticle: article, topic: issue.topic)
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
                        ResearchArticleSpeechControlsHost(
                            article: speechArticle,
                            speechController: speechController,
                            destination: .researchArticle(topic: issue.topic, articleID: article.id)
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
                        PavbotStateCard(
                            title: emptyTitle,
                            message: emptyDescription,
                            systemImage: topic.systemImage,
                            tint: topic.tint
                        )
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
                    PavbotStateCard(
                        title: ReportPackageCopy.noManifestTitle,
                        message: ReportPackageCopy.noManifestDescription,
                        systemImage: "doc.badge.questionmark",
                        tint: .orange,
                        actionTitle: "Otwórz ustawienia",
                        actionSystemImage: "gearshape"
                    ) {
                        router.selectedTab = .settings
                    }
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
                PavbotRefreshToolbarButton(
                    isRefreshing: store.state == .loading,
                    accessibilityLabel: ReportPackageCopy.refreshReportsAccessibilityLabel,
                    accessibilityHint: "Odświeża manifest i listę raportów."
                ) {
                    Task {
                        await store.reload()
                        syncSelectedReportDayToLatestIfNeeded()
                    }
                }
            }
        }
        .refreshable {
            await store.reload()
            syncSelectedReportDayToLatestIfNeeded()
        }
        .onAppear {
            syncSelectedReportDayToLatestIfNeeded()
        }
        .onChange(of: topic) { _, _ in
            router.selectedReportArtifactIDs = []
            router.selectedReportDay = store.manifest?.reportPackages(for: topic).first?.date
        }
        .onChange(of: store.manifest) { _, manifest in
            guard let manifest else { return }
            syncSelectedReportDayToLatestIfNeeded(manifest: manifest)
        }
    }

    private func syncSelectedReportDayToLatestIfNeeded(manifest: PavbotManifest? = nil) {
        guard router.selectedReportArtifactIDs.isEmpty else { return }
        let activeManifest = manifest ?? store.manifest
        guard let latestDay = activeManifest?.reportPackages(for: topic).first?.date else { return }
        if router.selectedReportDay != latestDay {
            router.selectedReportDay = latestDay
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
        ResearchTopicCompactSwitcher(selection: $selection)
    }
}

private struct ResearchTopicCompactSwitcher: View {
    @Binding var selection: ReportTopicKind

    private let columns = Array(repeating: GridItem(.flexible(minimum: 96), spacing: 8), count: 3)

    private var items: [ResearchTopicCompactItem] {
        [
            ResearchTopicCompactItem(
                id: .aktualne,
                title: "Aktualne",
                badge: "TTS",
                systemImage: ReportTopicKind.aktualne.systemImage,
                tint: ReportTopicKind.aktualne.tint
            ),
            ResearchTopicCompactItem(
                id: .techNews,
                title: "Tech",
                badge: "AI",
                systemImage: ReportTopicKind.techNews.systemImage,
                tint: ReportTopicKind.techNews.tint
            ),
            ResearchTopicCompactItem(
                id: .polskaSwiat,
                title: "Polska i Świat",
                badge: "News",
                systemImage: ReportTopicKind.polskaSwiat.systemImage,
                tint: ReportTopicKind.polskaSwiat.tint
            )
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items) { item in
                Button {
                    selection = item.id
                } label: {
                    ResearchTopicCompactCell(
                        item: item,
                        isSelected: selection == item.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                .accessibilityLabel("\(item.title), \(selection == item.id ? "wybrane" : "otwórz")")
            }
        }
    }
}

private struct ResearchTopicCompactItem: Identifiable {
    let id: ReportTopicKind
    let title: String
    let badge: String
    let systemImage: String
    let tint: Color
}

private struct ResearchTopicCompactCell: View {
    let item: ResearchTopicCompactItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: item.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? .white : item.tint)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? item.tint.gradient : item.tint.opacity(0.12).gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                Text(item.badge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? item.tint : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isSelected ? Color(.systemBackground).opacity(0.94) : item.tint.opacity(0.10), in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(item.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 30, alignment: .topLeading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(Color(.systemBackground).opacity(isSelected ? 1.0 : 0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? item.tint.opacity(0.72) : item.tint.opacity(0.16), lineWidth: isSelected ? 1.7 : 1)
        }
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.025), radius: isSelected ? 11 : 5, x: 0, y: isSelected ? 6 : 3)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
