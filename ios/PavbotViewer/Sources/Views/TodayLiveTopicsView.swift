import SwiftUI

struct TodayLiveTopicsPanel: View {
    let snapshot: TodayLiveTopicsSnapshot?
    let state: TodayLiveTopicsStore.LoadState
    let emptyMessage: String?
    let isRefreshing: Bool
    @Binding var selectedTopic: TodayLiveTopicSelection?
    let savedStore: TodayLiveTopicSavedStore
    let openAktualne: () -> Void
    @State private var isSavedPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Puls Dnia", systemImage: "globe.europe.africa.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                if isRefreshing {
                    ProgressView()
                } else if let snapshot {
                    Text(snapshot.displayDate)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Button {
                    isSavedPresented = true
                } label: {
                    Label("Zapisane", systemImage: "bookmark.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemBackground), in: Circle())
                .accessibilityLabel("Otwórz zapisane newsy Pulsu dnia")
            }

            switch state {
            case .idle where snapshot == nil, .loading where snapshot == nil:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Ładuję najważniejsze tematy z automatyzacji Puls Dnia...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            case .failed(let error) where snapshot == nil:
                TodayLiveTopicsEmptyState(
                    title: error.title,
                    message: error.message,
                    openAktualne: openAktualne
                )
            default:
                if let snapshot {
                    TodayLiveTopicsCarousel(
                        snapshot: snapshot,
                        selectedTopic: $selectedTopic,
                        savedStore: savedStore
                    )
                } else {
                    TodayLiveTopicsEmptyState(
                        title: "Brak tematów Pulsu Dnia",
                        message: emptyMessage ?? "Odśwież manifest albo otwórz Research -> Aktualne jako fallback.",
                        openAktualne: openAktualne
                    )
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        }
        .sheet(isPresented: $isSavedPresented) {
            TodayLiveTopicsSavedView(savedStore: savedStore)
        }
    }
}

struct TodayLiveTopicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotHaptics.self) private var haptics
    let topic: TodayLiveTopic
    let source: TodayLiveTopicsSource
    let displayDate: String
    let savedStore: TodayLiveTopicSavedStore?

    private var isSaved: Bool {
        savedStore?.isSaved(topic) ?? false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusBadge(text: topic.scope.title, systemImage: topic.scope.systemImage, tint: .orange)
                        if isSaved {
                            StatusBadge(text: "Zapisany", systemImage: "bookmark.fill", tint: .blue)
                        }
                        Text(topic.title)
                            .font(.title.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(topic.lead)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    TodayLiveTopicTextSection(title: "Key facts", items: topic.keyFacts, tint: .orange)
                    TodayLiveTopicTextSection(title: "Reakcje na sytuację", items: topic.reactions, tint: .blue)
                    TodayLiveTopicTextBlock(title: "Dlaczego to ważne", text: topic.whyItMatters)
                    TodayLiveTopicTextBlock(title: "Kontekst", text: topic.context)
                    TodayLiveTopicTextSection(title: "Co obserwować dalej", items: topic.watchNext, tint: .purple)

                    if !topic.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Źródła")
                                .font(.headline.weight(.semibold))
                            ForEach(topic.sources) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        PavbotActionRow(title: source.title, subtitle: source.url, systemImage: "link.circle.fill", tint: .orange)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Temat dnia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        savedStore?.toggle(topic, source: source, displayDate: displayDate)
                        haptics.play(.success)
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    }
                    .disabled(savedStore == nil)
                    .accessibilityLabel(isSaved ? "Usuń z zapisanych" : "Zapisz news")
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

private struct TodayLiveTopicsCarousel: View {
    let snapshot: TodayLiveTopicsSnapshot
    @Binding var selectedTopic: TodayLiveTopicSelection?
    let savedStore: TodayLiveTopicSavedStore
    @Environment(PavbotHaptics.self) private var haptics
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var selectedPairIndex = 0

    private var visibleSnapshot: TodayLiveTopicsSnapshot {
        snapshot.removingSavedTopics(in: savedStore)
    }

    private var layout: TodayLiveTopicsCarouselLayout {
        TodayLiveTopicsCarouselLayout(
            cardCount: currentPair?.topics.count ?? 2,
            compactWidth: horizontalSizeClass != .regular
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                StatusBadge(
                    text: snapshot.sourceLabel,
                    systemImage: snapshot.isFallback ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                    tint: snapshot.isFallback ? .orange : .green
                )
                Text(snapshot.headline)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(snapshot.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pair = currentPair {
                TodayLiveTopicsPairPage(
                    pair: pair,
                    source: snapshot.source,
                    displayDate: snapshot.displayDate,
                    layout: layout,
                    selectedTopic: $selectedTopic,
                    savedStore: savedStore,
                    onSwipeEnded: handleSwipe
                )
                .frame(height: layout.pageHeight, alignment: .top)
                .contentShape(Rectangle())
                .simultaneousGesture(swipeGesture, including: .all)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Wszystkie tematy z tego wydania są zapisane", systemImage: "bookmark.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text("Zajrzyj do zapisanych albo odśwież manifest, gdy automatyzacja opublikuje nowy Puls Dnia.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }

            TodayLiveTopicsCarouselControls(
                pageCount: visibleSnapshot.pairs.count,
                selectedIndex: $selectedPairIndex,
                isPaused: selectedTopic != nil || accessibilityReduceMotion
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Puls Dnia. Kafelki można przewijać gestem w lewo albo w prawo.")
        .accessibilityValue(accessibilityPageValue)
        .accessibilityAction(named: Text("Następna para tematów")) {
            advance(by: 1)
        }
        .accessibilityAction(named: Text("Poprzednia para tematów")) {
            advance(by: -1)
        }
        .onAppear {
            normalizeSelection()
        }
        .onChange(of: visibleSnapshot.id) { _, _ in
            normalizeSelection()
        }
        .task(id: "\(visibleSnapshot.id)-\(selectedTopic?.id ?? "none")-\(accessibilityReduceMotion)") {
            guard visibleSnapshot.pairs.count > 1, !accessibilityReduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                guard !Task.isCancelled else { return }
                guard selectedTopic == nil else { continue }
                advance(by: 1)
            }
        }
    }

    private var currentPair: TodayLiveTopicPair? {
        guard !visibleSnapshot.pairs.isEmpty else { return nil }
        return visibleSnapshot.pairs[min(selectedPairIndex, visibleSnapshot.pairs.count - 1)]
    }

    private var accessibilityPageValue: String {
        let pageCount = visibleSnapshot.pairs.count
        guard pageCount > 1 else { return "Jedna para tematów" }
        return "Para \(min(selectedPairIndex + 1, pageCount)) z \(pageCount)"
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded(handleSwipe)
    }

    private func handleSwipe(_ value: DragGesture.Value) {
        guard let action = TodayLiveTopicsSwipeDecision.action(
            translation: value.translation,
            predictedEndTranslation: value.predictedEndTranslation,
            pageCount: visibleSnapshot.pairs.count,
            detailIsOpen: selectedTopic != nil
        ) else { return }
        advance(by: action.pageOffset)
    }

    private func normalizeSelection() {
        guard !visibleSnapshot.pairs.isEmpty else {
            selectedPairIndex = 0
            return
        }
        if selectedPairIndex >= visibleSnapshot.pairs.count {
            selectedPairIndex = 0
        }
    }

    private func advance(by offset: Int) {
        guard let next = TodayLiveTopicsPageAdvance.nextIndex(
            currentIndex: selectedPairIndex,
            pageCount: visibleSnapshot.pairs.count,
            offset: offset,
            detailIsOpen: selectedTopic != nil
        ) else { return }
        guard !accessibilityReduceMotion else {
            selectedPairIndex = next
            haptics.play(.selection)
            return
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            selectedPairIndex = next
        }
        haptics.play(.selection)
    }
}

private struct TodayLiveTopicsPairPage: View {
    @Environment(PavbotHaptics.self) private var haptics
    let pair: TodayLiveTopicPair
    let source: TodayLiveTopicsSource
    let displayDate: String
    let layout: TodayLiveTopicsCarouselLayout
    @Binding var selectedTopic: TodayLiveTopicSelection?
    let savedStore: TodayLiveTopicSavedStore
    let onSwipeEnded: (DragGesture.Value) -> Void

    var body: some View {
        VStack(spacing: layout.cardSpacing) {
            ForEach(pair.topics) { topic in
                Button {
                    haptics.play(.lightImpact)
                    selectedTopic = TodayLiveTopicSelection(
                        topic: topic,
                        source: source,
                        displayDate: displayDate
                    )
                } label: {
                    TodayLiveTopicRow(topic: topic, isSaved: savedStore.isSaved(topic))
                }
                .buttonStyle(PavbotInteractiveSurfaceButtonStyle(tint: .orange, cornerRadius: 17))
                .simultaneousGesture(cardSwipeGesture, including: .all)
                .frame(height: layout.cardHeight)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(cardSwipeGesture, including: .all)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var cardSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded(onSwipeEnded)
    }
}

private struct TodayLiveTopicRow: View {
    let topic: TodayLiveTopic
    let isSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(topic.section.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                        if isSaved {
                            Image(systemName: "bookmark.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.blue)
                                .accessibilityLabel("Zapisany")
                        }
                    }
                    Text(topic.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(topic.lead)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 7) {
                ForEach(topic.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.10), in: Capsule())
                }
                Spacer()
                Text(topic.sourceCountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct TodayLiveTopicsCarouselControls: View {
    @Environment(PavbotHaptics.self) private var haptics
    let pageCount: Int
    @Binding var selectedIndex: Int
    let isPaused: Bool

    var body: some View {
        if pageCount > 1 {
            HStack(spacing: 10) {
                Button {
                    move(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemBackground), in: Circle())
                .accessibilityLabel("Poprzednia para tematów")

                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedIndex ? Color.orange : Color.orange.opacity(0.22))
                            .frame(width: index == selectedIndex ? 18 : 7, height: 7)
                            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedIndex)
                    }
                }
                .frame(maxWidth: .infinity)

                if isPaused {
                    Label("Pauza", systemImage: "pause.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Button {
                    move(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemBackground), in: Circle())
                .accessibilityLabel("Następna para tematów")
            }
        }
    }

    private func move(by offset: Int) {
        guard pageCount > 1 else { return }
        let next = (selectedIndex + offset + pageCount) % pageCount
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            selectedIndex = next
        }
        haptics.play(.selection)
    }
}

private struct TodayLiveTopicsEmptyState: View {
    let title: String
    let message: String
    let openAktualne: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "newspaper")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openAktualne) {
                Label("Otwórz Aktualne", systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
    }
}

private struct TodayLiveTopicsSavedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotHaptics.self) private var haptics
    let savedStore: TodayLiveTopicSavedStore
    @State private var query = ""
    @State private var selectedFilter: TodayLiveTopicsSavedFilter = .all
    @State private var selectedSavedTopic: SavedTodayLiveTopic?

    private var savedTopics: [SavedTodayLiveTopic] {
        savedStore.filteredTopics(query: query, scope: selectedFilter.scope)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zapisane Pulsu Dnia")
                            .font(.title2.weight(.bold))
                        Text("Zapisane newsy zostają lokalnie w aplikacji. Możesz wrócić do faktów, reakcji i źródeł nawet po kolejnych odświeżeniach feedu.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Picker("Filtr zapisanych", selection: $selectedFilter) {
                        ForEach(TodayLiveTopicsSavedFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedFilter) { _, _ in
                        haptics.play(.selection)
                    }

                    if savedTopics.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Brak zapisanych newsów", systemImage: "bookmark")
                                .font(.headline.weight(.semibold))
                            Text(query.isEmpty ? "Otwórz temat w Pulsie Dnia i użyj przycisku zapisania." : "Nie znaleziono zapisanego tematu dla wpisanego tekstu.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(savedTopics) { saved in
                                Button {
                                    haptics.play(.lightImpact)
                                    selectedSavedTopic = saved
                                } label: {
                                    TodayLiveTopicsSavedRow(saved: saved)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Zapisane")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Szukaj w zapisanych")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedSavedTopic) { saved in
                TodayLiveTopicDetailView(
                    topic: saved.topic,
                    source: saved.source,
                    displayDate: saved.displayDate,
                    savedStore: savedStore
                )
            }
        }
    }
}

private enum TodayLiveTopicsSavedFilter: String, CaseIterable, Identifiable {
    case all
    case pulse
    case poland
    case world

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "Wszystkie"
        case .pulse:
            "Puls"
        case .poland:
            "Polska"
        case .world:
            "Świat"
        }
    }

    var scope: TodayLiveTopicScope? {
        switch self {
        case .all:
            nil
        case .pulse:
            .pulse
        case .poland:
            .poland
        case .world:
            .world
        }
    }
}

private struct TodayLiveTopicsSavedRow: View {
    let saved: SavedTodayLiveTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                StatusBadge(text: saved.sourceLabel, systemImage: "bookmark.fill", tint: .blue)
                Spacer()
                Text(saved.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(saved.topic.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(saved.topic.lead)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                ForEach(saved.topic.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.10), in: Capsule())
                }
                Spacer()
                Text(saved.topic.sourceCountLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TodayLiveTopicTextSection: View {
    let title: String
    let items: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(item)
                        .font(.callout)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TodayLiveTopicTextBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(text)
                .font(.callout)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
