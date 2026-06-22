import SwiftUI

struct ArtifactTimelineView: View {
    @Environment(ManifestStore.self) private var store
    @State private var selectedDay: Date?
    @State private var searchText = ""
    @State private var didApplyInitialDay = false

    var body: some View {
        List {
            if let manifest = store.manifest {
                ArtifactSummarySection(manifest: manifest)
                DateFilterSection(days: manifest.availableDays, selectedDay: $selectedDay)

                let artifacts = manifest.filteredArtifacts(on: selectedDay, query: searchText)
                if artifacts.isEmpty {
                    ContentUnavailableView(
                        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No artifacts" : "No matching artifacts",
                        systemImage: "tray",
                        description: Text("Try another day or search term.")
                    )
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
        .navigationDestination(for: PavbotArtifact.self) { artifact in
            ArtifactDetailView(artifact: artifact)
        }
        .onAppear {
            applyInitialDayIfNeeded()
        }
        .onChange(of: store.manifest) { _, _ in
            applyInitialDayIfNeeded()
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

    private func applyInitialDayIfNeeded() {
        guard !didApplyInitialDay, let latestDay = store.manifest?.availableDays.first else { return }
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
