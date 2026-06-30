import SwiftUI

enum AutomationArtifactNavigationMode {
    case global
    case embeddedInSettings

    var switchesToArtifactsTab: Bool {
        self == .global
    }
}

struct ArtifactTimelineView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let navigationMode: AutomationArtifactNavigationMode
    @State private var searchText = ""
    @State private var expandedDays: Set<String> = []

    init(navigationMode: AutomationArtifactNavigationMode = .global) {
        self.navigationMode = navigationMode
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = PavbotAdaptiveLayout.resolve(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            Group {
                if let manifest = store.manifest {
                    if let group = selectedGroup(in: manifest) {
                        AutomationArtifactsDetailView(
                            group: group,
                            route: router.artifactRoute,
                            searchText: $searchText,
                            expandedDays: $expandedDays,
                            refreshAction: refreshArtifacts,
                            clearFiltersAction: clearFilters,
                            backAction: showAutomationTiles
                        )
                    } else {
                        AutomationArtifactGridView(
                            manifest: manifest,
                            searchText: $searchText,
                            refreshAction: refreshArtifacts,
                            selectAction: selectGroup
                        )
                    }
                } else {
                    ContentUnavailableView("Brak manifestu", systemImage: "doc.badge.questionmark")
                }
            }
            .environment(\.pavbotAdaptiveLayout, layout)
        }
        .navigationTitle("Wszystkie pliki")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Szukaj automatyzacji, plików i tematów")
        .navigationDestination(for: PavbotArtifact.self) { artifact in
            ArtifactDetailView(artifact: artifact)
        }
        .onAppear {
            syncSelectionFromRoute()
        }
        .onChange(of: store.manifest) { _, _ in
            syncSelectionFromRoute()
        }
        .onChange(of: router.artifactRoute) { _, route in
            if route != nil {
                searchText = ""
            }
            syncSelectionFromRoute()
        }
        .onChange(of: router.selectedArtifactAutomationID) { _, _ in
            expandSelectedDayIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PavbotRefreshToolbarButton(
                    isRefreshing: store.state == .loading,
                    accessibilityLabel: "Odśwież artefakty",
                    accessibilityHint: "Odświeża manifest z listą artefaktów."
                ) {
                    Task { await refreshArtifacts() }
                }
            }
        }
    }

    private func selectedGroup(in manifest: PavbotManifest) -> AutomationArtifactGroup? {
        manifest.automationArtifactGroup(for: router.selectedArtifactAutomationID)
            ?? manifest.automationArtifactGroup(for: router.artifactRoute)
    }

    private func selectGroup(_ group: AutomationArtifactGroup) {
        searchText = ""
        expandedDays = []
        let day = group.latestArtifact?.date ?? group.days.first?.pavbotDayString
        if let day {
            expandedDays.insert(day)
        }
        selectArtifactAutomation(id: group.id, day: day)
    }

    private func showAutomationTiles() {
        searchText = ""
        expandedDays = []
        router.clearArtifactRoute()
        preserveEmbeddedSettingsTabIfNeeded()
    }

    private func clearFilters() {
        let currentGroup = store.manifest.flatMap { selectedGroup(in: $0) }
        let selectedDay = router.selectedArtifactDay ?? currentGroup?.latestArtifact?.date ?? currentGroup?.days.first?.pavbotDayString

        searchText = ""
        expandedDays = []
        router.clearArtifactRoute()

        if let currentGroup {
            if let selectedDay {
                expandedDays.insert(selectedDay)
            }
            selectArtifactAutomation(id: currentGroup.id, day: selectedDay)
        }
    }

    private func selectArtifactAutomation(id: String?, day: String?) {
        router.selectArtifactAutomation(
            id: id,
            day: day,
            switchToArtifactsTab: navigationMode.switchesToArtifactsTab
        )
        preserveEmbeddedSettingsTabIfNeeded()
    }

    private func preserveEmbeddedSettingsTabIfNeeded() {
        if navigationMode == .embeddedInSettings {
            router.selectedTab = .settings
        }
    }

    private func refreshArtifacts() async {
        await store.reload()
        syncSelectionFromRoute()

        guard
            router.artifactRoute == nil,
            let manifest = store.manifest,
            let group = selectedGroup(in: manifest)
        else {
            return
        }

        let groupIDs = Set(group.artifacts.map(\.id))
        if let latestNewDay = store.lastNewArtifacts
            .filter({ groupIDs.contains($0.id) })
            .compactMap(\.date)
            .max()
        {
            router.selectedArtifactDay = latestNewDay
            expandedDays.insert(latestNewDay)
        }
    }

    private func syncSelectionFromRoute() {
        guard let manifest = store.manifest else { return }

        if router.artifactRoute != nil {
            router.resolveArtifactRouteSelection(in: manifest)
        }

        guard let group = selectedGroup(in: manifest) else {
            if router.selectedArtifactAutomationID != nil {
                router.selectedArtifactAutomationID = nil
                router.selectedArtifactDay = nil
            }
            return
        }

        if let routeDate = router.artifactRoute?.date {
            router.selectedArtifactDay = routeDate
            expandedDays.insert(routeDate)
            return
        }

        expandSelectedDayIfNeeded(for: group)
    }

    private func expandSelectedDayIfNeeded() {
        guard
            let manifest = store.manifest,
            let group = selectedGroup(in: manifest)
        else {
            return
        }
        expandSelectedDayIfNeeded(for: group)
    }

    private func expandSelectedDayIfNeeded(for group: AutomationArtifactGroup) {
        if let selectedDay = router.selectedArtifactDay {
            expandedDays.insert(selectedDay)
            return
        }

        if let latestDay = group.latestArtifact?.date ?? group.days.first?.pavbotDayString {
            router.selectedArtifactDay = latestDay
            expandedDays.insert(latestDay)
        }
    }
}

private struct AutomationArtifactGridView: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let manifest: PavbotManifest
    @Binding var searchText: String
    let refreshAction: () async -> Void
    let selectAction: (AutomationArtifactGroup) -> Void

    var body: some View {
        PavbotPremiumScreenScaffold(layout: layout, spacing: 18) {
                ArtifactSummaryHeader(manifest: manifest)

                if visibleGroups.isEmpty {
                        ContentUnavailableView(
                            hasSearch ? "Brak pasujących automatyzacji" : "Brak automatyzacji",
                            systemImage: "square.grid.2x2",
                            description: Text(hasSearch ? "Wyczyść wyszukiwanie, aby zobaczyć wszystkie kafelki." : "Włącz automatyzacje w manifeście, aby pokazać opublikowane pliki.")
                        )
                        if hasSearch {
                            Button("Wyczyść wyszukiwanie") {
                                searchText = ""
                            }
                        .buttonStyle(.bordered)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(visibleGroups) { group in
                            AutomationArtifactTile(group: group) {
                                selectAction(group)
                            }
                        }
                    }
                }
        }
        .refreshable {
            await refreshAction()
        }
    }

    private var columns: [GridItem] {
        layout.adaptiveColumns(minimum: layout.artifactTileMinWidth, maximum: layout.artifactTileMaxWidth)
    }

    private var visibleGroups: [AutomationArtifactGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = manifest.automationArtifactGroups
        guard !query.isEmpty else { return groups }
        return groups.filter { groupMatchesSearch($0, query: query) }
    }

    private var hasSearch: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func groupMatchesSearch(_ group: AutomationArtifactGroup, query: String) -> Bool {
        let automationValues = [
            group.automation.id,
            group.automation.name,
            group.automation.kind.label,
            group.automation.topic,
            group.automation.topicPath,
            group.automation.cadence
        ]

        if automationValues.contains(where: { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
            return true
        }

        return group.artifacts.contains { $0.matchesSearch(query) }
    }
}

private struct AutomationArtifactsDetailView: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let group: AutomationArtifactGroup
    let route: ArtifactNotificationRoute?
    @Binding var searchText: String
    @Binding var expandedDays: Set<String>
    let refreshAction: () async -> Void
    let clearFiltersAction: () -> Void
    let backAction: () -> Void

    var body: some View {
        PavbotPremiumScreenScaffold(layout: layout, spacing: 16) {
                Button(action: backAction) {
                    Label("Automatyzacje", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                AutomationArtifactsHeader(group: group)

                if let route {
                    ArtifactRouteBanner(
                        route: route,
                        matchingCount: matchingCount,
                        clearAction: clearFiltersAction
                    )
                }

                if visibleDays.isEmpty && visibleOtherArtifacts.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            hasActiveFilters ? "Brak pasujących plików" : "Brak plików",
                            systemImage: "tray",
                            description: Text(hasActiveFilters ? "Wyczyść filtry albo odśwież manifest." : "Odśwież manifest po publikacji plików przez tę automatyzację.")
                        )
                        if hasActiveFilters {
                            Button("Wyczyść filtry", action: clearFiltersAction)
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 10) {
                        ForEach(visibleDays, id: \.self) { day in
                            let artifacts = visibleArtifacts(on: day)
                            ArtifactDayDisclosure(
                                day: day,
                                artifacts: artifacts,
                                podcastPackage: group.automation.kind == .podcast ? group.podcastPackage(on: day, matching: route) : nil,
                                isExpanded: expansionBinding(for: day.pavbotDayString)
                            )
                        }

                        if !visibleOtherArtifacts.isEmpty {
                            OtherArtifactsPanel(artifacts: visibleOtherArtifacts)
                        }
                    }
                }
        }
        .refreshable {
            await refreshAction()
        }
    }

    private var visibleDays: [Date] {
        group.days.filter { !visibleArtifacts(on: $0).isEmpty }
    }

    private var visibleOtherArtifacts: [PavbotArtifact] {
        guard route?.date == nil else { return [] }

        var artifacts = group.otherArtifacts
        if let route, !route.artifactIDs.isEmpty {
            let ids = Set(route.artifactIDs)
            artifacts = artifacts.filter { ids.contains($0.id) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return artifacts.sorted(by: PavbotArtifact.automationDisplaySort)
        }
        return artifacts
            .filter { $0.matchesSearch(query) }
            .sorted(by: PavbotArtifact.automationDisplaySort)
    }

    private var matchingCount: Int {
        visibleDays.reduce(0) { $0 + visibleArtifacts(on: $1).count } + visibleOtherArtifacts.count
    }

    private var hasActiveFilters: Bool {
        route != nil || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func visibleArtifacts(on day: Date) -> [PavbotArtifact] {
        if let routeDate = route?.date, routeDate != day.pavbotDayString {
            return []
        }

        var artifacts = group.artifacts(on: day, matching: route)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            artifacts = artifacts.filter { $0.matchesSearch(query) }
        }
        return artifacts
    }

    private func expansionBinding(for day: String) -> Binding<Bool> {
        Binding(
            get: { expandedDays.contains(day) },
            set: { isExpanded in
                if isExpanded {
                    expandedDays.insert(day)
                } else {
                    expandedDays.remove(day)
                }
            }
        )
    }
}

private struct ArtifactSummaryHeader: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let manifest: PavbotManifest

    var body: some View {
        PavbotCommandHero(
            eyebrow: "Wszystkie pliki",
            title: "Biblioteka automatyzacji",
            subtitle: layout.usesDashboardLayout
                ? "Master-detail dla automatyzacji, dni i plików z większymi kafelkami w szerokim oknie."
                : "Wybierz automatyzację i przeglądaj wygenerowane pliki bez opuszczania bieżącego miejsca.",
            systemImage: "folder.fill.badge.gearshape",
            tint: .blue,
            insights: [
                PavbotInsight(title: "Automatyzacje", value: "\(manifest.enabledAutomations.count)", systemImage: "bolt.fill", tint: .yellow),
                PavbotInsight(title: "Pliki", value: "\(manifest.artifacts.count)", systemImage: "doc.on.doc.fill", tint: .blue),
                PavbotInsight(title: "Dni", value: "\(manifest.availableDays.count)", systemImage: "calendar", tint: .green),
                PavbotInsight(title: "Najnowsze", value: manifest.latestArtifact?.date ?? "-", systemImage: "clock.fill", tint: .purple)
            ]
        )
    }
}

private struct AutomationArtifactTile: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let group: AutomationArtifactGroup
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: group.automation.kind.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(group.automation.kind.tint)
                        .frame(width: 42, height: 42)
                        .background(group.automation.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    StatusBadge(text: group.automation.kind.label, systemImage: "checkmark.circle.fill", tint: group.automation.kind.tint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(group.automation.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(group.automation.topic)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .leading, spacing: 6) {
                    TileMetric(label: "Pliki", value: "\(group.artifacts.count)")
                    TileMetric(label: "Dni", value: "\(group.days.count)")
                    TileMetric(label: "Ostatnio", value: group.latestArtifact?.displayDate ?? "Brak plików")
                }
            }
            .frame(maxWidth: .infinity, minHeight: layout.usesDashboardLayout ? 220 : 188, alignment: .topLeading)
            .padding(layout.usesDashboardLayout ? 18 : 14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: layout.usesDashboardLayout ? 18 : 8))
            .overlay(
                RoundedRectangle(cornerRadius: layout.usesDashboardLayout ? 18 : 8)
                    .stroke(group.automation.kind.tint.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TileMetric: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct AutomationArtifactsHeader: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let group: AutomationArtifactGroup

    var body: some View {
        PavbotCommandHero(
            eyebrow: group.automation.kind.label,
            title: group.automation.name,
            subtitle: layout.usesDashboardLayout
                ? group.automation.topicPath
                : "Dni publikacji i wygenerowane pliki tej automatyzacji.",
            systemImage: group.automation.kind.systemImage,
            tint: group.automation.kind.tint,
            insights: [
                PavbotInsight(title: "Pliki", value: "\(group.artifacts.count)", systemImage: "doc.on.doc.fill", tint: .blue),
                PavbotInsight(title: "Dni", value: "\(group.days.count)", systemImage: "calendar", tint: .green),
                PavbotInsight(title: "Ostatnio", value: group.latestArtifact?.date ?? "-", systemImage: "clock.fill", tint: .purple),
                PavbotInsight(title: "Temat", value: group.automation.topic, systemImage: "folder.fill", tint: group.automation.kind.tint)
            ]
        )
    }
}

private struct ArtifactRouteBanner: View {
    let route: ArtifactNotificationRoute
    let matchingCount: Int
    let clearAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(route.displayTitle)
                    .font(.subheadline.weight(.semibold))
                Text("\(matchingCount) plików z tej publikacji automatyzacji")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Wyczyść", action: clearAction)
                .font(.caption.weight(.semibold))
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ArtifactDayDisclosure: View {
    let day: Date
    let artifacts: [PavbotArtifact]
    let podcastPackage: PodcastArtifactPackage?
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 0) {
                if let podcastPackage {
                    PodcastPackagePanel(package: podcastPackage)

                    if !remainingArtifacts.isEmpty {
                        Divider()
                            .padding(.leading, 50)
                    }
                }

                ForEach(remainingArtifacts) { artifact in
                    NavigationLink {
                        ArtifactDetailView(artifact: artifact)
                    } label: {
                        ArtifactRow(artifact: artifact)
                    }
                    .buttonStyle(ArtifactNavigationRowStyle())

                    if artifact.id != remainingArtifacts.last?.id {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(day.pavbotDayString)
                        .font(.headline.weight(.semibold))
                    Text("\(artifacts.count) plików")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var remainingArtifacts: [PavbotArtifact] {
        guard let podcastPackage else { return artifacts }
        var packagedIDs = Set<String>()
        if let primaryAudio = podcastPackage.primaryAudio {
            packagedIDs.insert(primaryAudio.id)
        }
        if let briefPDF = podcastPackage.briefPDF {
            packagedIDs.insert(briefPDF.id)
        }
        packagedIDs.formUnion(podcastPackage.audioVariants.map(\.id))
        return artifacts.filter { !packagedIDs.contains($0.id) }
    }
}

private struct PodcastPackagePanel: View {
    let package: PodcastArtifactPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Paczka podcastu")
                        .font(.subheadline.weight(.semibold))
                    Text("Audio i brief przygotowane do przeglądu na telefonie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                if let audio = package.primaryAudio ?? package.audioVariants.first {
                    NavigationLink {
                        ArtifactDetailView(artifact: audio)
                    } label: {
                        PodcastPackageActionRow(
                            title: "Odtwórz audio",
                            subtitle: audio.title,
                            systemImage: "play.circle.fill",
                            tint: .blue
                        )
                    }
                    .buttonStyle(ArtifactNavigationRowStyle())
                }

                if let briefPDF = package.briefPDF {
                    if package.hasAudio {
                        Divider()
                            .padding(.leading, 42)
                    }

                    NavigationLink {
                        ArtifactDetailView(artifact: briefPDF)
                    } label: {
                        PodcastPackageActionRow(
                            title: "Otwórz brief PDF",
                            subtitle: "Czytelne podsumowanie ze źródłami",
                            systemImage: "doc.richtext.fill",
                            tint: .orange
                        )
                    }
                    .buttonStyle(ArtifactNavigationRowStyle())
                } else if package.isMissingBriefPDF {
                    if package.hasAudio {
                        Divider()
                            .padding(.leading, 42)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "doc.badge.clock")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Brakuje briefu PDF")
                                .font(.subheadline.weight(.semibold))
                            Text("Ta publikacja ma audio, ale nie ma jeszcze mobilnego briefu PDF.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 9)
                }
            }

            if package.audioVariants.count > 1 {
                Text("\(package.audioVariants.count) warianty audio w tej paczce")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct PodcastPackageActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
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
        .padding(.vertical, 9)
    }
}

private struct OtherArtifactsPanel: View {
    let artifacts: [PavbotArtifact]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pozostałe pliki")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(artifacts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(artifacts) { artifact in
                    NavigationLink {
                        ArtifactDetailView(artifact: artifact)
                    } label: {
                        ArtifactRow(artifact: artifact)
                    }
                    .buttonStyle(ArtifactNavigationRowStyle())

                    if artifact.id != artifacts.last?.id {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ArtifactRow: View {
    let artifact: PavbotArtifact

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtifactIconBadge(kind: artifact.viewerKind)

            VStack(alignment: .leading, spacing: 5) {
                Text(artifact.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(artifact.topic)
                    Text("·")
                    Text(artifact.type.label)
                    Text("·")
                    Text(artifact.sizeBytes.fileSizeLabel)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(artifact.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct ArtifactNavigationRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.secondary.opacity(0.10) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
