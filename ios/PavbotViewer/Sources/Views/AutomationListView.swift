import SwiftUI

struct AutomationListView: View {
    @Environment(ManifestStore.self) private var store

    var body: some View {
        List {
            if let manifest = store.manifest {
                OverviewSection(manifest: manifest)
                StatusSection()

                ForEach(manifest.topics) { topic in
                    let automations = manifest.enabledAutomations.filter { $0.topic == topic.slug }
                    if !automations.isEmpty {
                        Section {
                            ForEach(automations) { automation in
                                AutomationRow(
                                    automation: automation,
                                    latestArtifact: manifest.latestArtifact(for: automation)
                                )
                            }
                        } header: {
                            Text(topic.slug)
                        }
                    }
                }
            } else {
                StatusSection()
            }
        }
        .navigationTitle("Automations")
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh manifest")
            }
        }
    }
}

private struct OverviewSection: View {
    let manifest: PavbotManifest

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pavbot")
                        .font(.largeTitle.bold())
                    Text("Codex automation monitor")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(title: "Automations", value: "\(manifest.enabledAutomations.count)", systemImage: "bolt.fill", tint: .yellow)
                    MetricTile(title: "Artifacts", value: "\(manifest.artifacts.count)", systemImage: "tray.full.fill", tint: .blue)
                    MetricTile(title: "Topics", value: "\(manifest.topics.count)", systemImage: "folder.fill", tint: .green)
                    MetricTile(title: "Latest", value: manifest.latestArtifact?.date ?? "—", systemImage: "clock.fill", tint: .purple)
                }
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }
}

private struct StatusSection: View {
    @Environment(ManifestStore.self) private var store

    var body: some View {
        Section {
            switch store.state {
            case .idle:
                Label("Ready", systemImage: "checkmark.circle")
            case .loading:
                HStack {
                    ProgressView()
                    Text("Loading manifest")
                }
            case .loaded:
                Label("Manifest loaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if !store.lastNewArtifacts.isEmpty {
                Label("\(store.lastNewArtifacts.count) new artifact notifications queued", systemImage: "bell.badge")
                    .foregroundStyle(.blue)
            }
        }
    }
}

private struct AutomationRow: View {
    let automation: PavbotAutomation
    let latestArtifact: PavbotArtifact?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: automation.kind.systemImage)
                    .font(.headline)
                    .foregroundStyle(automation.kind.tint)
                    .frame(width: 34, height: 34)
                    .background(automation.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Text(automation.name)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                StatusBadge(text: automation.kind.rawValue.capitalized, systemImage: "checkmark.circle.fill", tint: automation.kind.tint)
            }

            Text(automation.cadence)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(automation.topicPath)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let latestArtifact {
                Label("\(latestArtifact.type.label) · \(latestArtifact.displayDate)", systemImage: latestArtifact.viewerKind.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Label("No generated files yet", systemImage: "tray")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

extension AutomationKind {
    var systemImage: String {
        switch self {
        case .research:
            "doc.text.magnifyingglass"
        case .podcast:
            "waveform.circle"
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
        case .automation:
            .orange
        }
    }
}
