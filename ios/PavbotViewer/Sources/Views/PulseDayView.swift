import SwiftUI

struct PulseDayView: View {
    @Environment(ManifestStore.self) private var manifestStore
    @Environment(AppRouter.self) private var router
    @State private var liveTopicsStore = TodayLiveTopicsStore()
    @State private var savedStore = TodayLiveTopicSavedStore()
    @State private var selectedMode: PulseDayMode = .latest
    @State private var selectedTopic: TodayLiveTopicSelection?
    @State private var selectedHistoryRun: TodayLiveTopicsSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PulseDayHeroHeader(
                    snapshot: liveTopicsStore.snapshot,
                    isRefreshing: liveTopicsStore.isRefreshing
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
                        openAktualne: openAktualneMagazine
                    )
                case .history:
                    PulseDayHistoryView(
                        snapshots: liveTopicsStore.historySnapshots,
                        selectedTopic: $selectedTopic,
                        savedStore: savedStore,
                        openRun: { snapshot in
                            selectedHistoryRun = snapshot
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Puls Dnia")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload(minimumInterval: 0) }
                } label: {
                    if liveTopicsStore.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(liveTopicsStore.isRefreshing)
                .accessibilityLabel("Odśwież Puls Dnia")
            }
        }
        .task {
            await reload(minimumInterval: 10)
        }
        .onChange(of: manifestStore.manifest) { _, _ in
            Task { await reload(minimumInterval: 10) }
        }
        .onChange(of: savedStore.savedTopics) { _, _ in
            liveTopicsStore.pruneHistory()
        }
        .refreshable {
            await reload(minimumInterval: 0)
        }
        .sheet(item: $selectedTopic) { selection in
            TodayLiveTopicDetailView(
                topic: selection.topic,
                source: selection.source,
                displayDate: selection.displayDate,
                savedStore: savedStore
            )
        }
        .sheet(item: $selectedHistoryRun) { snapshot in
            PulseDayHistoryRunDetailView(
                snapshot: snapshot,
                savedStore: savedStore
            )
        }
    }

    private func reload(minimumInterval: TimeInterval) async {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 58, height: 58)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(text: "Pavbot info", systemImage: "sparkles", tint: .orange)
                    Text("Puls Dnia")
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Najważniejsze tematy z automatyzacji co 3 godziny, gotowe do szybkiego przeglądu i zapisania lokalnie.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if let snapshot {
                    StatusBadge(text: snapshot.sourceLabel, systemImage: snapshot.isFallback ? "exclamationmark.triangle.fill" : "checkmark.seal.fill", tint: snapshot.isFallback ? .orange : .green)
                    StatusBadge(text: snapshot.displayDate, systemImage: "clock.fill", tint: .blue)
                }

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.orange.opacity(0.10),
                    Color.blue.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

private struct PulseDayHistoryView: View {
    let snapshots: [TodayLiveTopicsSnapshot]
    @Binding var selectedTopic: TodayLiveTopicSelection?
    let savedStore: TodayLiveTopicSavedStore
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
                LazyVStack(spacing: 12) {
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
                Text(topic.sourceCountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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

            HStack(spacing: 7) {
                ForEach(topic.tags.prefix(4), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.10), in: Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
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
