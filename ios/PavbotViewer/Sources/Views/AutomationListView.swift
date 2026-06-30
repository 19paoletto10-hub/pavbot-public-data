import SwiftUI

struct AutomationClientBrief: Equatable {
    let headline: String
    let summary: String
    let outputLabel: String
    let highlights: [String]

    init(kind: AutomationKind) {
        switch kind {
        case .research:
            headline = "Sygnał rynkowy oparty na źródłach"
            summary = "Tworzy zwięzły raport badawczy, który zamienia sprawdzone źródła w czytelny materiał do decyzji."
            outputLabel = "Raport badawczy"
            highlights = [
                "Monitoruje wskazany temat i wychwytuje istotne zmiany oraz nowe fakty.",
                "Oddziela informacje źródłowe od interpretacji, żeby raport był łatwy do weryfikacji.",
                "Publikuje datowane raporty do GitHuba, dzięki czemu aplikacja iOS może je odświeżyć.",
                "Pokazuje ostatni przebieg jako krótki, menedżerski podgląd sytuacji."
            ]
        case .podcast:
            headline = "Codzienny briefing do odsłuchu"
            summary = "Zamienia aktualizację tematu w krótki materiał audio, który można odsłuchać bez przeglądania wszystkich plików."
            outputLabel = "Audio podcastu"
            highlights = [
                "Przekształca najnowszą aktualizację w zwięzły briefing mówiony.",
                "Publikuje pliki MP3 gotowe do odtworzenia w aplikacji iOS.",
                "Utrzymuje przewidywalny rytm publikacji, dobry do codziennego słuchania.",
                "Wspiera powiadomienia, gdy w repozytorium pojawi się nowe audio."
            ]
        case .researchAudio:
            headline = "Mobilny pakiet informacji"
            summary = "Przygotowuje zestaw do szybkiego przeglądu na telefonie: brief, dopracowany PDF i materiały audio."
            outputLabel = "Brief, PDF i audio"
            highlights = [
                "Tworzy krótki brief mobilny, który można szybko przeskanować.",
                "Dodaje PDF wyglądający bardziej jak raport dla klienta niż surowe notatki.",
                "Publikuje audio, którego można słuchać w tle podczas pracy.",
                "Odświeża manifest w GitHubie, żeby iOS widział cały pakiet wyników."
            ]
        case .automation:
            headline = "Monitoring procesu operacyjnego"
            summary = "Pilnuje działania workflow i pokazuje, czy automatyzacja wykonuje zadania w przewidywalny sposób."
            outputLabel = "Status automatyzacji"
            highlights = [
                "Sprawdza stan i zachowanie skonfigurowanego procesu.",
                "Zapisuje status oraz zadania następcze, gdy pojawi się ryzyko lub błąd.",
                "Publikuje artefakty przebiegu, żeby były widoczne w aplikacji iOS.",
                "Pokazuje pracę automatyzacji bez konieczności otwierania repozytorium."
            ]
        }
    }
}

struct AutomationListView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let navigationMode: AutomationArtifactNavigationMode
    @State private var selectedAutomationID: String?
    @State private var isEmbeddedArtifactTimelinePresented = false

    init(navigationMode: AutomationArtifactNavigationMode = .global) {
        self.navigationMode = navigationMode
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = PavbotAdaptiveLayout.resolve(width: proxy.size.width, horizontalSizeClass: horizontalSizeClass)

            PavbotPremiumScreenScaffold(layout: layout) {
                    if let manifest = store.manifest {
                        OverviewSection(manifest: manifest)
                        StatusPanel()

                        let groups = manifest.automationArtifactGroups
                        if groups.isEmpty {
                            ContentUnavailableView(
                                "Brak aktywnych automatyzacji",
                                systemImage: "bolt.slash",
                                description: Text("Załaduj manifest z włączonymi automatyzacjami Pavbot, aby zobaczyć kafelki i wyniki.")
                            )
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(manifest.topics) { topic in
                                let topicGroups = groups.filter { $0.automation.topic == topic.slug }
                                if !topicGroups.isEmpty {
                                    AutomationTopicSection(
                                        topic: topic,
                                        groups: topicGroups,
                                        selectedAutomationID: $selectedAutomationID,
                                        selectAction: toggleSelection,
                                        viewFilesAction: openArtifacts
                                    )
                                }
                            }
                        }
                    } else {
                        StatusPanel()
                        ContentUnavailableView(
                            "Brak manifestu",
                            systemImage: "doc.badge.questionmark",
                            description: Text("Zapisz Manifest URL w ustawieniach albo odśwież, gdy manifest GitHuba będzie dostępny.")
                        )
                        .frame(maxWidth: .infinity)
                    }
            }
            .environment(\.pavbotAdaptiveLayout, layout)
        }
        .navigationTitle("Automatyzacje")
        .navigationDestination(isPresented: $isEmbeddedArtifactTimelinePresented) {
            ArtifactTimelineView(navigationMode: .embeddedInSettings)
        }
        .refreshable {
            await store.reload()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PavbotRefreshToolbarButton(
                    isRefreshing: store.state == .loading,
                    accessibilityLabel: "Odśwież manifest",
                    accessibilityHint: "Odświeża manifest automatyzacji."
                ) {
                    Task { await store.reload() }
                }
            }
        }
        .onChange(of: store.manifest) { _, manifest in
            guard let selectedAutomationID else { return }
            if manifest?.automationArtifactGroup(for: selectedAutomationID) == nil {
                self.selectedAutomationID = nil
            }
        }
    }

    private func toggleSelection(_ group: AutomationArtifactGroup) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            selectedAutomationID = selectedAutomationID == group.id ? nil : group.id
        }
    }

    private func openArtifacts(_ group: AutomationArtifactGroup) {
        let latestDay = group.latestArtifact?.date ?? group.days.first?.pavbotDayString
        if navigationMode == .embeddedInSettings {
            openEmbeddedArtifacts(group, latestDay: latestDay)
            return
        }

        openGlobalArtifacts(group, latestDay: latestDay)
    }

    private func openEmbeddedArtifacts(_ group: AutomationArtifactGroup, latestDay: String?) {
        router.selectArtifactAutomation(
            id: group.id,
            day: latestDay,
            switchToArtifactsTab: navigationMode.switchesToArtifactsTab
        )
        router.selectedTab = .settings
        isEmbeddedArtifactTimelinePresented = true
    }

    private func openGlobalArtifacts(_ group: AutomationArtifactGroup, latestDay: String?) {
        if router.openReportsForTopic(group.automation.topic, latestDay: latestDay) {
            return
        }
        router.openArtifactsForAutomation(
            id: group.id,
            latestDay: latestDay
        )
    }
}

private struct OverviewSection: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let manifest: PavbotManifest

    var body: some View {
        PavbotCommandHero(
            eyebrow: "Operational Console",
            title: "Pavbot",
            subtitle: layout.usesDashboardLayout
                ? "Monitor automatyzacji Codex z siatką workflow, statusami i szybkim wejściem do opublikowanych plików."
                : "Aktywne workflow, ostatnie uruchomienia i pliki generowane przez Codex.",
            systemImage: "bolt.circle.fill",
            tint: .yellow,
            insights: [
                PavbotInsight(title: "Automatyzacje", value: "\(manifest.enabledAutomations.count)", systemImage: "bolt.fill", tint: .yellow),
                PavbotInsight(title: "Artefakty", value: "\(manifest.artifacts.count)", systemImage: "tray.full.fill", tint: .blue),
                PavbotInsight(title: "Tematy", value: "\(manifest.topics.count)", systemImage: "folder.fill", tint: .green),
                PavbotInsight(title: "Ostatni przebieg", value: manifest.latestArtifact?.date ?? "-", systemImage: "clock.fill", tint: .purple)
            ],
            footnote: manifest.latestAutomationRun?.dashboardSubtitle
        )
    }
}

private struct StatusPanel: View {
    @Environment(ManifestStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch store.state {
            case .idle:
                Label("Gotowe", systemImage: "checkmark.circle")
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Wczytuję manifest")
                }
            case .loaded:
                Label("Manifest załadowany", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let error):
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if !store.lastNewArtifacts.isEmpty {
                Label("\(store.lastNewArtifacts.count) nowych artefaktów po odświeżeniu", systemImage: "bell.badge")
                    .foregroundStyle(.blue)
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AutomationTopicSection: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let topic: PavbotTopic
    let groups: [AutomationArtifactGroup]
    @Binding var selectedAutomationID: String?
    let selectAction: (AutomationArtifactGroup) -> Void
    let viewFilesAction: (AutomationArtifactGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.slug)
                    .font(.headline.weight(.semibold))
                Text(topic.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(groups) { group in
                    AutomationTile(
                        group: group,
                        isSelected: selectedAutomationID == group.id,
                        action: { selectAction(group) }
                    )
                }
            }

            if let selectedGroup = groups.first(where: { $0.id == selectedAutomationID }) {
                AutomationInfoBubble(
                    group: selectedGroup,
                    action: { viewFilesAction(selectedGroup) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var columns: [GridItem] {
        layout.adaptiveColumns(
            minimum: layout.usesDashboardLayout ? 220 : 166,
            maximum: layout.usesDashboardLayout ? 320 : 240
        )
    }
}

private struct AutomationTile: View {
    let group: AutomationArtifactGroup
    let isSelected: Bool
    let action: () -> Void

    private var automation: PavbotAutomation {
        group.automation
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: automation.kind.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(automation.kind.tint)
                        .frame(width: 42, height: 42)
                        .background(automation.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    Image(systemName: isSelected ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? automation.kind.tint : .secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(automation.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(automation.topic)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                StatusBadge(text: automation.kind.label, systemImage: "checkmark.circle.fill", tint: automation.kind.tint)

                VStack(alignment: .leading, spacing: 6) {
                    AutomationTileMetric(label: "Harmonogram", value: automation.cadence)
                    AutomationTileMetric(label: "Pliki", value: "\(group.artifacts.count)")
                    AutomationTileMetric(label: "Najnowsze", value: group.latestArtifact?.displayDate ?? "Brak plików")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? automation.kind.tint.opacity(0.6) : automation.kind.tint.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(automation.name), \(automation.kind.label), \(group.artifacts.count) plików")
    }
}

private struct AutomationTileMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
    }
}

private struct AutomationInfoBubble: View {
    let group: AutomationArtifactGroup
    let action: () -> Void

    private var automation: PavbotAutomation {
        group.automation
    }

    private var brief: AutomationClientBrief {
        AutomationClientBrief(kind: automation.kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: automation.kind.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(automation.kind.tint)
                    .frame(width: 46, height: 46)
                    .background(automation.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Co robi ta automatyzacja")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(automation.kind.tint)
                        .textCase(.uppercase)
                    Text(brief.headline)
                        .font(.title3.weight(.bold))
                    Text(brief.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(brief.highlights, id: \.self) { highlight in
                    AutomationHighlightRow(text: highlight, tint: automation.kind.tint)
                }
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                AutomationBubbleMetric(label: "Wynik", value: brief.outputLabel)
                AutomationBubbleMetric(label: "Temat", value: automation.topic)
                AutomationBubbleMetric(label: "Harmonogram", value: automation.cadence)
                AutomationBubbleMetric(label: "Artefakty", value: "\(group.artifacts.count)")
            }

            if let output = automation.output {
                Label(output, systemImage: "shippingbox.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Button(action: action) {
                Label("Zobacz wygenerowane pliki", systemImage: "tray.full.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(automation.kind.tint)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(automation.kind.tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct AutomationHighlightRow: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AutomationBubbleMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AutomationKind {
    var label: String {
        switch self {
        case .research:
            "Research"
        case .podcast:
            "Podcast"
        case .researchAudio:
            "Research + Audio"
        case .automation:
            "Automation"
        }
    }

    var systemImage: String {
        switch self {
        case .research:
            "doc.text.magnifyingglass"
        case .podcast:
            "waveform.circle"
        case .researchAudio:
            "waveform.badge.magnifyingglass"
        case .automation:
            "gearshape.2"
        }
    }

    var tint: Color {
        switch self {
        case .research:
            .blue
        case .podcast:
            .purple
        case .researchAudio:
            .indigo
        case .automation:
            .orange
        }
    }
}
