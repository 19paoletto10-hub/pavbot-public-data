import SwiftUI

struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct ArtifactIconBadge: View {
    let kind: ArtifactViewerKind

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.headline)
            .foregroundStyle(kind.tint)
            .frame(width: 38, height: 38)
            .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension ArtifactViewerKind {
    var tint: Color {
        switch self {
        case .markdown:
            .blue
        case .pdf:
            .red
        case .audio:
            .purple
        case .json:
            .orange
        case .file:
            .secondary
        }
    }
}

extension Int {
    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
