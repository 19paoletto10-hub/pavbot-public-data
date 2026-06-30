import SwiftUI

struct PulseDayView: View {
    @Environment(ManifestStore.self) private var manifestStore
    @Environment(AppRouter.self) private var router
    @Environment(PavbotHaptics.self) private var haptics
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var liveTopicsStore = TodayLiveTopicsStore()
    @State private var savedStore = TodayLiveTopicSavedStore()
    @State private var selectedMode: PulseDayMode = .latest
    @State private var selectedTopic: TodayLiveTopicSelection?
    @State private var selectedHistoryRun: TodayLiveTopicsSnapshot?

    var body: some View {
        GeometryReader { proxy in
            let layout = PavbotAdaptiveLayout.resolve(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            PavbotPremiumScreenScaffold(layout: layout) {
                    PulseDayHeroHeader(
                        snapshot: liveTopicsStore.snapshot,
                        isRefreshing: liveTopicsStore.isRefreshing,
                        layout: layout
                    )

                    Picker("Widok Pulsu Dnia", selection: $selectedMode) {
                        ForEach(PulseDayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedMode {
                    case .latest:
                        TodayLiveTopicsPanel(
                            snapshot: liveTopicsStore.snapshot,
                            state: liveTopicsStore.state,
                            emptyMessage: liveTopicsStore.emptyMessage,
                            isRefreshing: liveTopicsStore.isRefreshing,
                            selectedTopic: $selectedTopic,
                            savedStore: savedStore,
                            layout: layout,
                            openAktualne: openAktualneMagazine
                        )
                    case .history:
                        PulseDayHistoryView(
                            snapshots: liveTopicsStore.historySnapshots,
                            selectedTopic: $selectedTopic,
                            savedStore: savedStore,
                            layout: layout,
                            openRun: { snapshot in
                                selectedHistoryRun = snapshot
                            }
                        )
                    }
            }
            .environment(\.pavbotAdaptiveLayout, layout)
        }
        .navigationTitle("Puls Dnia")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PavbotRefreshToolbarButton(
                    isRefreshing: isRefreshingPulseDay,
                    accessibilityLabel: "Odśwież Puls Dnia",
                    accessibilityHint: "Odświeża manifest oraz dane Pulsu Dnia."
                ) {
                    Task { await reload(refreshManifest: true, minimumInterval: 0) }
                }
            }
        }
        .task {
            await reload(refreshManifest: false, minimumInterval: 10)
        }
        .task(id: pulseRouteReloadKey) {
            guard router.selectedTab == .pulseDay, pulseRouteReloadKey != "no-pulse-route" else { return }
            await reload(refreshManifest: true, minimumInterval: 0)
        }
        .onChange(of: manifestStore.manifest) { _, _ in
            Task { await reload(refreshManifest: false, minimumInterval: 10) }
        }
        .onChange(of: savedStore.savedTopics) { _, _ in
            liveTopicsStore.pruneHistory()
        }
        .onChange(of: selectedMode) { _, _ in
            haptics.play(.selection)
        }
        .refreshable {
            await reload(refreshManifest: true, minimumInterval: 0)
        }
        .sheet(item: $selectedTopic) { selection in
            TodayLiveTopicDetailView(
                topic: selection.topic,
                source: selection.source,
                displayDate: selection.displayDate,
                savedStore: savedStore
            )
            .pavbotLargeObjectPresentation()
        }
        .sheet(item: $selectedHistoryRun) { snapshot in
            PulseDayHistoryRunDetailView(
                snapshot: snapshot,
                savedStore: savedStore
            )
            .pavbotLargeObjectPresentation()
        }
        .pavbotTabInfo(PavbotTabInfoContent.pulseDay(subtabTitle: selectedMode.title))
    }

    private var pulseRouteReloadKey: String {
        guard router.selectedTab == .pulseDay else { return "no-pulse-route" }
        let day = router.selectedReportDay ?? "no-day"
        let artifacts = router.selectedReportArtifactIDs.joined(separator: "|")
        guard router.selectedReportDay != nil || !router.selectedReportArtifactIDs.isEmpty else {
            return "no-pulse-route"
        }
        return [day, artifacts].joined(separator: "::")
    }

    private var isRefreshingPulseDay: Bool {
        manifestStore.state == .loading || liveTopicsStore.isRefreshing
    }

    private func reload(refreshManifest: Bool, minimumInterval: TimeInterval) async {
        if refreshManifest {
            await manifestStore.reload(minimumInterval: 0)
        }
        await liveTopicsStore.load(
            manifest: manifestStore.manifest,
            manifestURLString: manifestStore.manifestURLString,
            minimumInterval: minimumInterval
        )
    }

    private func openAktualneMagazine() {
        router.selectedTab = .research
        router.selectedResearchTopic = .aktualne
    }
}

private enum PulseDayMode: String, CaseIterable, Identifiable {
    case latest
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest:
            "Najnowsze"
        case .history:
            "Historia"
        }
    }
}

private struct PulseDayHeroHeader: View {
    let snapshot: TodayLiveTopicsSnapshot?
    let isRefreshing: Bool
    let layout: PavbotAdaptiveLayout

    var body: some View {
        PavbotCommandHero(
            eyebrow: "Pavbot info",
            title: "Puls Dnia",
            subtitle: layout.usesDashboardLayout
                ? "Newsroom grid z top tematami, historią i lokalnym zapisem najważniejszych artykułów."
                : "Szybki briefing co 3 godziny z tematami gotowymi do zapisania lokalnie.",
            systemImage: "globe.europe.africa.fill",
            tint: .orange,
            insights: [
                PavbotInsight(title: "Tematy", value: "\(snapshot?.allTopics.count ?? 0)", systemImage: "doc.text.fill", tint: .orange),
                PavbotInsight(title: "Źródło", value: snapshot?.sourceLabel ?? "Ładowanie", systemImage: snapshot?.isFallback == true ? "exclamationmark.triangle.fill" : "checkmark.seal.fill", tint: snapshot?.isFallback == true ? .orange : .green),
                PavbotInsight(title: "Aktualizacja", value: snapshot?.displayDate ?? "-", systemImage: "clock.fill", tint: .blue),
                PavbotInsight(title: "Status", value: isRefreshing ? "Odświeżam" : "Gotowe", systemImage: isRefreshing ? "arrow.clockwise" : "sparkles", tint: isRefreshing ? .blue : .green)
            ],
            startsCollapsed: true
        )
    }
}

private struct PulseDayHistoryView: View {
    let snapshots: [TodayLiveTopicsSnapshot]
    @Binding var selectedTopic: TodayLiveTopicSelection?
    let savedStore: TodayLiveTopicSavedStore
    let layout: PavbotAdaptiveLayout
    let openRun: (TodayLiveTopicsSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Historia z 48h", systemImage: "clock.arrow.circlepath")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Text("\(snapshots.count) runów")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Aplikacja pokazuje lokalnie zapamiętane runy Pulsu Dnia z ostatnich 48 godzin. Starsze niezapisane newsy są czyszczone automatycznie, żeby feed był szybki i świeży.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if snapshots.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Brak lokalnej historii", systemImage: "tray")
                        .font(.headline.weight(.semibold))
                    Text("Starsze niezapisane newsy są czyszczone po 48h. Odśwież Puls Dnia, gdy automatyzacja opublikuje kolejny run.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                LazyVGrid(columns: layout.adaptiveColumns(minimum: layout.usesDashboardLayout ? 340 : 280), spacing: layout.cardSpacing) {
                    ForEach(snapshots) { snapshot in
                        PulseDayHistoryRunCard(
                            snapshot: snapshot,
                            selectedTopic: $selectedTopic,
                            savedStore: savedStore,
                            openRun: {
                                openRun(snapshot)
                            }
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct PulseDayHistoryRunCard: View {
    let snapshot: TodayLiveTopicsSnapshot
    @Binding var selectedTopic: TodayLiveTopicSelection?
    let savedStore: TodayLiveTopicSavedStore
    let openRun: () -> Void

    private var presentation: PulseDayHistoryRunPresentation {
        PulseDayHistoryRunPresentation(snapshot: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StatusBadge(text: snapshot.sourceLabel, systemImage: "newspaper.fill", tint: .orange)
                Spacer()
                Text(snapshot.displayDate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(snapshot.headline)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("\(presentation.allTopics.count) tematów znalezionych w tym runie")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if presentation.allTopics.isEmpty {
                Label("Ten run nie zawiera tematów do pokazania", systemImage: "tray")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(presentation.previewTopics) { topic in
                        Button {
                            selectedTopic = TodayLiveTopicSelection(
                                topic: topic,
                                source: snapshot.source,
                                displayDate: snapshot.displayDate
                            )
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(topic.section.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .frame(width: 78, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(topic.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(topic.lead)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if savedStore.isSaved(topic) {
                                        Label("Zapisany", systemImage: "bookmark.fill")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Text(presentation.previewStatusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(action: openRun) {
                        Label(presentation.openAllButtonTitle, systemImage: "list.bullet.rectangle.portrait.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .accessibilityLabel("Zobacz wszystkie artykuły z runu \(snapshot.displayDate)")
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PulseDayHistoryRunDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: TodayLiveTopicsSnapshot
    let savedStore: TodayLiveTopicSavedStore
    @State private var selectedSection = PulseDayHistoryRunDetailView.allSectionsID
    @State private var selectedTopic: TodayLiveTopicSelection?

    private static let allSectionsID = "all"

    private var presentation: PulseDayHistoryRunPresentation {
        PulseDayHistoryRunPresentation(snapshot: snapshot)
    }

    private var filteredTopics: [TodayLiveTopic] {
        presentation.topics(in: selectedSection == Self.allSectionsID ? nil : selectedSection)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if !presentation.sectionTitles.isEmpty {
                        PulseDaySectionFilterBar(
                            sections: presentation.sectionTitles,
                            selectedSection: $selectedSection,
                            allSectionsID: Self.allSectionsID
                        )
                    }

                    if filteredTopics.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Brak artykułów w tej sekcji", systemImage: "tray")
                                .font(.headline.weight(.semibold))
                            Text("Wybierz inną sekcję albo wróć do widoku wszystkich artykułów.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredTopics) { topic in
                                Button {
                                    selectedTopic = TodayLiveTopicSelection(
                                        topic: topic,
                                        source: snapshot.source,
                                        displayDate: snapshot.displayDate
                                    )
                                } label: {
                                    PulseDayHistoryTopicRow(
                                        topic: topic,
                                        isSaved: savedStore.isSaved(topic)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Run Pulsu Dnia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedTopic) { selection in
                TodayLiveTopicDetailView(
                    topic: selection.topic,
                    source: selection.source,
                    displayDate: selection.displayDate,
                    savedStore: savedStore
                )
                .pavbotLargeObjectPresentation()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                StatusBadge(text: snapshot.sourceLabel, systemImage: "newspaper.fill", tint: .orange)
                StatusBadge(text: snapshot.displayDate, systemImage: "clock.fill", tint: .blue)
            }

            Text(snapshot.headline)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(snapshot.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                MetricTile(
                    title: "Artykuły",
                    value: "\(presentation.allTopics.count)",
                    systemImage: "doc.text.fill",
                    tint: .orange
                )
                MetricTile(
                    title: "Sekcje",
                    value: "\(max(presentation.sectionTitles.count, 1))",
                    systemImage: "square.grid.2x2.fill",
                    tint: .blue
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct PulseDaySectionFilterBar: View {
    let sections: [String]
    @Binding var selectedSection: String
    let allSectionsID: String

    private var filters: [(id: String, title: String)] {
        [(allSectionsID, "Wszystkie")] + sections.map { ($0, $0) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.id) { filter in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedSection = filter.id
                        }
                    } label: {
                        Text(filter.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedSection == filter.id ? .white : .orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selectedSection == filter.id ? Color.orange : Color.orange.opacity(0.10),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pokaż sekcję \(filter.title)")
                    .accessibilityAddTraits(selectedSection == filter.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct PulseDayHistoryTopicRow: View {
    let topic: TodayLiveTopic
    let isSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(topic.section.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
                if isSaved {
                    Label("Zapisany", systemImage: "bookmark.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    PavbotSourceCountBadge(count: topic.sources.count, tint: .orange)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(topic.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(topic.lead)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !topic.tags.isEmpty {
                PavbotArticleKeywordRows(horizontalSpacing: 7, verticalSpacing: 6) {
                    ForEach(topic.tags.prefix(4), id: \.self) { tag in
                        PavbotArticleTagChip(
                            title: tag,
                            systemImage: "tag.fill",
                            tint: .orange,
                            accessibilityPrefix: "Tag tematu"
                        )
                    }
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.10), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
