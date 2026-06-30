import SwiftUI

struct SavedResearchArticlesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotHaptics.self) private var haptics
    let store: SavedResearchArticleStore

    @State private var query = ""
    @State private var selectedArticle: SavedResearchArticle?

    private var articles: [SavedResearchArticle] {
        store.filteredArticles(query: query)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if articles.isEmpty {
                        ContentUnavailableView(
                            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Brak zapisanych artykułów" : "Brak wyników",
                            systemImage: "bookmark",
                            description: Text("Zapisane artykuły z Research będą dostępne lokalnie na tym urządzeniu.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ForEach(articles) { saved in
                            Button {
                                haptics.play(.lightImpact)
                                selectedArticle = saved
                            } label: {
                                SavedResearchArticleRow(saved: saved)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.remove(saved)
                                    haptics.play(.warning)
                                } label: {
                                    Label("Usuń z zapisanych", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Zapisane Research")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Szukaj w zapisanych")
            .sheet(item: $selectedArticle) { saved in
                SavedResearchArticleDetailView(saved: saved, store: store)
                    .pavbotLargeObjectPresentation()
            }
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

private struct SavedResearchArticleRow: View {
    let saved: SavedResearchArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: saved.article.section.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(saved.topic.tint)
                    .frame(width: 38, height: 38)
                    .background(saved.topic.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(saved.topic.title.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(saved.topic.tint)
                        Text(saved.article.section.rawValue.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(saved.article.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(saved.article.summary)
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

            HStack(spacing: 8) {
                Label(saved.displayDate.isEmpty ? "Bez daty" : saved.displayDate, systemImage: "calendar")
                Label("\(saved.article.sources.count) źr.", systemImage: "link")
                Spacer()
                Label("Zapisany", systemImage: "bookmark.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SavedResearchArticleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotHaptics.self) private var haptics
    let saved: SavedResearchArticle
    let store: SavedResearchArticleStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusBadge(
                            text: "\(saved.topic.title) - \(saved.article.section.rawValue)",
                            systemImage: saved.topic.systemImage,
                            tint: saved.topic.tint
                        )
                        Text(saved.article.title)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(saved.article.summary)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(saved.article.body)
                            .font(.body)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if !saved.article.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Źródła")
                                .font(.headline.weight(.semibold))
                            ForEach(saved.article.sources) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        PavbotActionRow(title: source.title, subtitle: source.url, systemImage: "link.circle.fill", tint: saved.topic.tint)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Zapisany artykuł")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        store.remove(saved)
                        haptics.play(.warning)
                        dismiss()
                    } label: {
                        Label("Usuń", systemImage: "trash")
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
