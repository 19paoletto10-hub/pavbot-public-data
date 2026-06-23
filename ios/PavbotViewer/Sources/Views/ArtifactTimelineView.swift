import SwiftUI

struct ArtifactTimelineView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var selectedDay: Date?
    @State private var searchText = ""
    @State private var didApplyInitialDay = false

    var body: some View {
        List {
            if let manifest = store.manifest {
                ArtifactSummarySection(manifest: manifest)
                if let route = router.artifactRoute {
                    ArtifactRouteSection(
                        route: route,
                        matchingCount: manifest.filteredArtifacts(for: route).count,
                        clearAction: clearFilters
                    )
                } else {
                    DateFilterSection(days: manifest.availableDays, selectedDay: $selectedDay)
                }

                let artifacts = visibleArtifacts(in: manifest)
                if artifacts.isEmpty {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            hasActiveFilters ? "No matching artifacts" : "No artifacts",
                            systemImage: "tray",
                            description: Text(hasActiveFilters ? "Clear filters or refresh the manifest." : "Refresh the manifest after an automation publishes files.")
                        )
                        if hasActiveFilters {
                            Button("Clear filters", action: clearFilters)
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    ForEach(groupedArtifacts(artifacts), id: \.key) { group in
                        Section(group.key) {
                            ForEach(group.values) { artifact in
                                NavigationLink(value: artifact) {
                                    ArtifactRow(artifact: artifact)
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("No manifest", systemImage: "doc.badge.questionmark")
            }
        }
        .navigationTitle("Artifacts")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search files, topics, paths")
        .listStyle(.insetGrouped)
        .refreshable {
            await refreshArtifacts()
        }
        .navigationDestination(for: PavbotArtifact.self) { artifact in
            ArtifactDetailView(artifact: artifact)
        }
        .onAppear {
            applyInitialDayIfNeeded()
        }
        .onChange(of: store.manifest) { _, _ in
            applyInitialDayIfNeeded()
        }
        .onChange(of: store.lastNewArtifacts) { _, newArtifacts in
            applyNewestNewArtifactDay(newArtifacts)
        }
        .onChange(of: router.artifactRoute) { _, route in
            if route != nil {
                selectedDay = nil
                searchText = ""
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshArtifacts() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.state == .loading)
                .accessibilityLabel("Refresh artifacts")
            }
        }
    }

    private func groupedArtifacts(_ artifacts: [PavbotArtifact]) -> [(key: String, values: [PavbotArtifact])] {
        Dictionary(grouping: artifacts, by: \.displayDate)
            .map { ($0.key, $0.value.sorted { $0.path < $1.path }) }
            .sorted { lhs, rhs in
                if lhs.key == "No date" { return false }
                if rhs.key == "No date" { return true }
                return lhs.key > rhs.key
            }
    }

    private var hasActiveFilters: Bool {
        router.artifactRoute != nil || selectedDay != nil || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func visibleArtifacts(in manifest: PavbotManifest) -> [PavbotArtifact] {
        let routeScopedArtifacts = router.artifactRoute.map { manifest.filteredArtifacts(for: $0) }
        let dateScopedArtifacts = routeScopedArtifacts ?? manifest.artifacts(on: selectedDay)
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return dateScopedArtifacts }
        return dateScopedArtifacts.filter { $0.matchesSearch(trimmedSearch) }
    }

    private func refreshArtifacts() async {
        await store.reload()
        guard router.artifactRoute == nil else { return }
        if store.lastNewArtifacts.isEmpty {
            selectedDay = store.manifest?.availableDays.first
            didApplyInitialDay = selectedDay != nil
        } else {
            applyNewestNewArtifactDay(store.lastNewArtifacts)
        }
    }

    private func clearFilters() {
        router.clearArtifactRoute()
        selectedDay = nil
        searchText = ""
    }

    private func applyInitialDayIfNeeded() {
        guard router.artifactRoute == nil, !didApplyInitialDay, let latestDay = store.manifest?.availableDays.first else { return }
        selectedDay = latestDay
        didApplyInitialDay = true
    }

    private func applyNewestNewArtifactDay(_ artifacts: [PavbotArtifact]) {
        guard router.artifactRoute == nil, let latestDay = artifacts.compactMap(\.day).max() else { return }
        selectedDay = latestDay
        didApplyInitialDay = true
    }
}

private struct ArtifactSummarySection: View {
    let manifest: PavbotManifest

    var body: some View {
        Section {
            HStack(spacing: 12) {
                MetricTile(title: "Files", value: "\(manifest.artifacts.count)", systemImage: "doc.on.doc.fill", tint: .blue)
                MetricTile(title: "Days", value: "\(manifest.availableDays.count)", systemImage: "calendar", tint: .green)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
    }
}

private struct DateFilterSection: View {
    let days: [Date]
    @Binding var selectedDay: Date?

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    DayChip(title: "All", isSelected: selectedDay == nil) {
                        selectedDay = nil
                    }
                    ForEach(days, id: \.self) { day in
                        DayChip(title: day.pavbotDayString, isSelected: selectedDay?.pavbotDayString == day.pavbotDayString) {
                            selectedDay = day
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ArtifactRouteSection: View {
    let route: ArtifactNotificationRoute
    let matchingCount: Int
    let clearAction: () -> Void

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 30, height: 30)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(route.displayTitle)
                        .font(.subheadline.weight(.semibold))
                    Text("\(matchingCount) files from the selected automation publish")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear", action: clearAction)
                    .font(.caption.weight(.semibold))
            }
        } header: {
            Text("Notification")
        }
    }
}

private struct DayChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
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
        }
        .padding(.vertical, 4)
    }
}

extension ArtifactViewerKind {
    var systemImage: String {
        switch self {
        case .markdown:
            "doc.text"
        case .pdf:
            "doc.richtext"
        case .audio:
            "waveform"
        case .json:
            "curlybraces"
        case .file:
            "doc"
        }
    }
}
