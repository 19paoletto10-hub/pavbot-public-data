import SwiftUI

struct TodayLiveTopicsPanel: View {
    @Environment(AppLanguageStore.self) private var languageStore
    @Environment(AutomationTranslationStore.self) private var translationStore
    let snapshot: TodayLiveTopicsSnapshot?
    let state: TodayLiveTopicsStore.LoadState
    let emptyMessage: String?
    let isRefreshing: Bool
    @Binding var selectedTopic: TodayLiveTopicSelection?
    let savedStore: TodayLiveTopicSavedStore
    var layout: PavbotAdaptiveLayout = .phone
    let openAktualne: () -> Void
    @State private var isSavedPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(LocalizedStringKey("Puls Dnia"), systemImage: "globe.europe.africa.fill")
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
                    Label(LocalizedStringKey("Zapisane"), systemImage: "bookmark.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemBackground), in: Circle())
                .accessibilityLabel("Otwórz zapisane newsy Pulsu dnia")
            }

            if let emptyMessage, snapshot != nil {
                PavbotCacheNoticeBanner(text: emptyMessage)
            }

            switch state {
            case .idle where snapshot == nil, .loading where snapshot == nil:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(LocalizedStringKey("Ładuję najważniejsze tematy z automatyzacji Puls Dnia..."))
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
                    if layout.usesDashboardLayout {
                        TodayLiveTopicsGrid(
                            snapshot: snapshot,
                            selectedTopic: $selectedTopic,
                            savedStore: savedStore,
                            layout: layout
                        )
                    } else {
                        TodayLiveTopicsCarousel(
                            snapshot: snapshot,
                            selectedTopic: $selectedTopic,
                            savedStore: savedStore
                        )
                    }
                } else {
                    TodayLiveTopicsEmptyState(
                        title: "Brak tematów Pulsu Dnia",
                        message: emptyMessage ?? "Odśwież manifest albo otwórz Przegląd -> Aktualne jako fallback.",
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
                .pavbotLargeObjectPresentation()
        }
        .task(id: translationRegistrationKey) {
            if let snapshot {
                translationStore.register(snapshot.automationTranslationDocument, language: languageStore.preference)
            }
        }
    }

    private var translationRegistrationKey: String {
        [
            languageStore.preference.rawValue,
            snapshot?.automationTranslationDocument.id ?? "no-snapshot"
        ]
        .joined(separator: "::")
    }
}

private struct TodayLiveTopicsGrid: View {
    @Environment(PavbotHaptics.self) private var haptics
    let snapshot: TodayLiveTopicsSnapshot
    @Binding var selectedTopic: TodayLiveTopicSelection?
    let savedStore: TodayLiveTopicSavedStore
    let layout: PavbotAdaptiveLayout

    private var visibleSnapshot: TodayLiveTopicsSnapshot {
        snapshot.removingSavedTopics(in: savedStore)
    }

    private var topics: [TodayLiveTopic] {
        visibleSnapshot.pairs.flatMap(\.topics)
    }

    private var topStory: TodayLiveTopic? {
        topics.first { PavbotNewsPriorityStyle($0.priority) == .high } ?? topics.first
    }

    private var secondaryTopics: [TodayLiveTopic] {
        guard let topStory else { return topics }
        return topics.filter { $0.id != topStory.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout.cardSpacing) {
            PulseIssueMasthead(snapshot: snapshot)

            if topics.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label(LocalizedStringKey("Wszystkie tematy z tego wydania są zapisane"), systemImage: "bookmark.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(LocalizedStringKey("Zajrzyj do zapisanych albo odśwież manifest, gdy automatyzacja opublikuje nowy Puls Dnia."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous))
            } else {
                if let topStory {
                    Button {
                        haptics.play(.lightImpact)
                        selectedTopic = TodayLiveTopicSelection(
                            topic: topStory,
                            source: snapshot.source,
                            displayDate: snapshot.displayDate,
                            translationDocument: snapshot.automationTranslationDocument,
                            translationPathPrefix: TodayLiveTopicsSnapshot.translationPathPrefix(for: topStory)
                        )
                    } label: {
                        TodayLiveTopicRow(
                            topic: topStory,
                            isSaved: savedStore.isSaved(topStory),
                            isFeatured: true,
                            translationDocument: snapshot.automationTranslationDocument,
                            translationPathPrefix: TodayLiveTopicsSnapshot.translationPathPrefix(for: topStory)
                        )
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: layout.adaptiveColumns(minimum: 320), spacing: layout.cardSpacing) {
                    ForEach(secondaryTopics) { topic in
                        Button {
                            haptics.play(.lightImpact)
                            selectedTopic = TodayLiveTopicSelection(
                                topic: topic,
                                source: snapshot.source,
                                displayDate: snapshot.displayDate,
                                translationDocument: snapshot.automationTranslationDocument,
                                translationPathPrefix: TodayLiveTopicsSnapshot.translationPathPrefix(for: topic)
                            )
                        } label: {
                            TodayLiveTopicRow(
                                topic: topic,
                                isSaved: savedStore.isSaved(topic),
                                translationDocument: snapshot.automationTranslationDocument,
                                translationPathPrefix: TodayLiveTopicsSnapshot.translationPathPrefix(for: topic)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Puls Dnia w układzie siatki")
    }
}

private struct PulseIssueMasthead: View {
    let snapshot: TodayLiveTopicsSnapshot
    @State private var isContextExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseIssueMastheadMetadataRow(snapshot: snapshot)
            PulseIssueMastheadTitle(
                headline: snapshot.headline,
                translationDocument: snapshot.automationTranslationDocument
            )

            DisclosureGroup(isExpanded: $isContextExpanded) {
                PavbotTranslatedAutomationText(
                    snapshot.summary,
                    document: snapshot.automationTranslationDocument,
                    path: "summary"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Label(LocalizedStringKey("Kontekst wydania"), systemImage: "text.quote")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .textCase(.uppercase)
            }
            .tint(.orange)
        }
    }
}

private struct PulseIssueMastheadMetadataRow: View {
    let snapshot: TodayLiveTopicsSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            StatusBadge(
                text: snapshot.sourceLabel,
                systemImage: snapshot.isFallback ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                tint: snapshot.isFallback ? .orange : .green
            )

            Spacer(minLength: 8)

            Text(snapshot.displayDate)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct PulseIssueMastheadTitle: View {
    let headline: String
    let translationDocument: AutomationTranslationDocument

    var body: some View {
        PavbotTranslatedAutomationText(
            headline,
            document: translationDocument,
            path: "headline"
        )
            .font(.title3.weight(.bold))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TodayLiveTopicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotAudioSessionCoordinator.self) private var audioCoordinator
    @Environment(PavbotHaptics.self) private var haptics
    let topic: TodayLiveTopic
    let source: TodayLiveTopicsSource
    let displayDate: String
    let savedStore: TodayLiveTopicSavedStore?
    var translationDocument: AutomationTranslationDocument?
    var translationPathPrefix: String?
    @StateObject private var speechController = TodayLiveTopicSpeechController()

    private var isSaved: Bool {
        savedStore?.isSaved(topic) ?? false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        StatusBadge(
                            text: topic.scope.title,
                            systemImage: topic.scope.systemImage,
                            tint: .orange,
                            translatesAutomationText: true,
                            translationDocument: translationDocument,
                            translationPath: translationPath("scopeTitle")
                        )
                        if isSaved {
                            StatusBadge(text: "Zapisany", systemImage: "bookmark.fill", tint: .blue)
                        }
                        PavbotTranslatedAutomationText(
                            topic.title,
                            document: translationDocument,
                            path: translationPath("title")
                        )
                            .font(.title.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        PavbotTranslatedAutomationText(
                            topic.lead,
                            document: translationDocument,
                            path: translationPath("lead")
                        )
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    TodayLiveTopicSpeechPanel(topic: topic, speechController: speechController)

                    TodayLiveTopicTextSection(
                        title: "Key facts",
                        items: topic.keyFacts,
                        tint: .orange,
                        document: translationDocument,
                        pathPrefix: translationPath("keyFacts")
                    )
                    TodayLiveTopicTextSection(
                        title: "Reakcje na sytuację",
                        items: topic.reactions,
                        tint: .blue,
                        document: translationDocument,
                        pathPrefix: translationPath("reactions")
                    )
                    TodayLiveTopicTextBlock(
                        title: "Dlaczego to ważne",
                        text: topic.whyItMatters,
                        document: translationDocument,
                        path: translationPath("whyItMatters")
                    )
                    TodayLiveTopicTextBlock(
                        title: "Kontekst",
                        text: topic.context,
                        document: translationDocument,
                        path: translationPath("context")
                    )
                    TodayLiveTopicTextSection(
                        title: "Co obserwować dalej",
                        items: topic.watchNext,
                        tint: .purple,
                        document: translationDocument,
                        pathPrefix: translationPath("watchNext")
                    )

                    if !topic.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(LocalizedStringKey("Źródła"))
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
            .navigationTitle(LocalizedStringKey("Temat dnia"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                speechController.configureAudioCoordinator(audioCoordinator)
            }
            .onDisappear {
                speechController.stop()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        savedStore?.toggle(topic, source: source, displayDate: displayDate)
                        haptics.play(.success)
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    }
                    .disabled(savedStore == nil)
                    .accessibilityLabel(Text(LocalizedStringKey(isSaved ? "Usuń z zapisanych" : "Zapisz news")))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func translationPath(_ field: String) -> String? {
        guard translationDocument != nil else { return nil }
        guard let translationPathPrefix else { return field }
        return "\(translationPathPrefix).\(field)"
    }
}

private struct TodayLiveTopicSpeechPanel: View {
    @Environment(AppLanguageStore.self) private var languageStore
    @Environment(AutomationTranslationStore.self) private var translationStore
    @Environment(PavbotHaptics.self) private var haptics
    let topic: TodayLiveTopic
    @ObservedObject var speechController: TodayLiveTopicSpeechController

    private var isCurrent: Bool {
        speechController.currentTopicID == topic.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isCurrent ? "speaker.wave.2.circle.fill" : "speaker.wave.2.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey("Odczyt artykułu"))
                                .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(LocalizedStringKey(isCurrent ? statusText : "Przeczytaj ten temat głosem iPhone’a."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button {
                    handlePrimaryAction()
                    haptics.play(.lightImpact)
                } label: {
                    Label(LocalizedStringKey(primaryTitle), systemImage: primaryIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(primaryAccessibilityLabel)))

                if isCurrent {
                    Button {
                        speechController.stop()
                        haptics.play(.warning)
                    } label: {
                        Label(LocalizedStringKey("Stop"), systemImage: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(LocalizedStringKey("Zatrzymaj odczyt artykułu")))
                }
            }

            if isCurrent {
                PavbotSpeechRatePicker(title: "Tempo czytania artykułu", speechRate: rateBinding)

                PavbotSpeechTimelineScrubber(
                    timeline: speechController.timeline,
                    currentSegmentIndex: speechController.currentSegmentIndex,
                    estimatedElapsed: speechController.estimatedElapsed,
                    estimatedDuration: speechController.estimatedDuration,
                    currentSegmentText: speechController.currentSegmentText,
                    seekToProgress: speechController.seek(toProgress:)
                )
            }

            if let errorMessage = speechController.errorMessage {
                Text(LocalizedStringKey(errorMessage))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var rateBinding: Binding<MobileNewsSpeechRate> {
        Binding(
            get: { speechController.speechRate },
            set: { speechController.setSpeechRate($0) }
        )
    }

    private var primaryTitle: String {
        if isCurrent, speechController.isPaused { return "Wznów" }
        if isCurrent, speechController.isSpeaking { return "Pauza" }
        return "Przeczytaj artykuł"
    }

    private var primaryIcon: String {
        if isCurrent, speechController.isPaused { return "play.fill" }
        if isCurrent, speechController.isSpeaking { return "pause.fill" }
        return "speaker.wave.2.fill"
    }

    private var primaryAccessibilityLabel: String {
        if isCurrent, speechController.isPaused { return "Wznów odczyt artykułu" }
        if isCurrent, speechController.isSpeaking { return "Wstrzymaj odczyt artykułu" }
        return "Przeczytaj artykuł"
    }

    private var statusText: String {
        if speechController.isPaused {
            return "Wstrzymane. Możesz zmienić tempo, przesunąć fragment albo zatrzymać."
        }
        if speechController.isSpeaking {
            return "Odczyt aktywny. Zmiana tempa kontynuuje od aktualnego miejsca."
        }
        return "Gotowe do odczytu."
    }

    private func handlePrimaryAction() {
        if isCurrent, speechController.isPaused {
            speechController.resume()
        } else if isCurrent, speechController.isSpeaking {
            speechController.pause()
        } else {
            Task {
                await speechController.speak(
                    topic,
                    language: languageStore.preference,
                    translationStore: translationStore
                )
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
            compactWidth: horizontalSizeClass != .regular
        )
    }

    private var topics: [TodayLiveTopic] {
        visibleSnapshot.pairs.flatMap(\.topics)
    }

    private var topStory: TodayLiveTopic? {
        topics.first { PavbotNewsPriorityStyle($0.priority) == .high } ?? topics.first
    }

    private var carouselPairs: [TodayLiveTopicPair] {
        let secondaryTopics: [TodayLiveTopic]
        if let topStory {
            secondaryTopics = topics.filter { $0.id != topStory.id }
        } else {
            secondaryTopics = topics
        }

        return stride(from: 0, to: secondaryTopics.count, by: 2).map { index in
            TodayLiveTopicPair(topics: Array(secondaryTopics[index..<min(index + 2, secondaryTopics.count)]))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PulseIssueMasthead(snapshot: snapshot)

            if let topStory {
                Button {
                    haptics.play(.lightImpact)
                    selectedTopic = TodayLiveTopicSelection(
                        topic: topStory,
                        source: snapshot.source,
                        displayDate: snapshot.displayDate,
                        translationDocument: snapshot.automationTranslationDocument,
                        translationPathPrefix: TodayLiveTopicsSnapshot.translationPathPrefix(for: topStory)
                    )
                } label: {
                    TodayLiveTopicRow(
                        topic: topStory,
                        isSaved: savedStore.isSaved(topStory),
                        isFeatured: true,
                        translationDocument: snapshot.automationTranslationDocument,
                        translationPathPrefix: TodayLiveTopicsSnapshot.translationPathPrefix(for: topStory)
                    )
                }
                .buttonStyle(.plain)
            }

            if let pair = currentPair {
                TodayLiveTopicsPairPage(
                    pair: pair,
                    source: snapshot.source,
                    displayDate: snapshot.displayDate,
                    translationDocument: snapshot.automationTranslationDocument,
                    layout: layout,
                    selectedTopic: $selectedTopic,
                    savedStore: savedStore,
                    onSwipeEnded: handleSwipe
                )
                .contentShape(Rectangle())
                .simultaneousGesture(swipeGesture, including: .all)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else if topStory == nil {
                VStack(alignment: .leading, spacing: 10) {
                    Label(LocalizedStringKey("Wszystkie tematy z tego wydania są zapisane"), systemImage: "bookmark.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(LocalizedStringKey("Zajrzyj do zapisanych albo odśwież manifest, gdy automatyzacja opublikuje nowy Puls Dnia."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }

            TodayLiveTopicsCarouselControls(
                pageCount: carouselPairs.count,
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
            guard carouselPairs.count > 1, !accessibilityReduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                guard !Task.isCancelled else { return }
                guard selectedTopic == nil else { continue }
                advance(by: 1)
            }
        }
    }

    private var currentPair: TodayLiveTopicPair? {
        guard !carouselPairs.isEmpty else { return nil }
        return carouselPairs[min(selectedPairIndex, carouselPairs.count - 1)]
    }

    private var accessibilityPageValue: String {
        let pageCount = carouselPairs.count
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
            pageCount: carouselPairs.count,
            detailIsOpen: selectedTopic != nil
        ) else { return }
        advance(by: action.pageOffset)
    }

    private func normalizeSelection() {
        guard !carouselPairs.isEmpty else {
            selectedPairIndex = 0
            return
        }
        if selectedPairIndex >= carouselPairs.count {
            selectedPairIndex = 0
        }
    }

    private func advance(by offset: Int) {
        guard let next = TodayLiveTopicsPageAdvance.nextIndex(
            currentIndex: selectedPairIndex,
            pageCount: carouselPairs.count,
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
    let translationDocument: AutomationTranslationDocument
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
                        displayDate: displayDate,
                        translationDocument: translationDocument,
                        translationPathPrefix: TodayLiveTopicsSnapshot.translationPathPrefix(for: topic)
                    )
                } label: {
                    TodayLiveTopicPreviewCard(
                        topic: topic,
                        isSaved: savedStore.isSaved(topic),
                        translationDocument: translationDocument,
                        translationPathPrefix: TodayLiveTopicsSnapshot.translationPathPrefix(for: topic)
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(cardSwipeGesture, including: .all)
                .frame(maxWidth: .infinity, alignment: .top)
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

private struct TodayLiveTopicPreviewCard: View {
    let topic: TodayLiveTopic
    let isSaved: Bool
    let translationDocument: AutomationTranslationDocument
    let translationPathPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: topic.scope.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.orange.opacity(0.16), radius: 7, x: 0, y: 4)
                    .accessibilityHidden(true)

                PavbotArticleKeywordRows(horizontalSpacing: 5, verticalSpacing: 5) {
                    PavbotNewsSectionBadge(
                        title: topic.section,
                        tint: .orange,
                        document: translationDocument,
                        path: "\(translationPathPrefix).section"
                    )
                    PavbotNewsPriorityBadge(style: PavbotNewsPriorityStyle(topic.priority))
                    PavbotSourceCountBadge(count: topic.sources.count, tint: .orange)
                    if isSaved {
                        PavbotNewsSavedBadge()
                    }
                }
                .padding(.top, 1)
                .layoutPriority(1)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
                    .background(Color(.tertiarySystemBackground), in: Circle())
                    .accessibilityHidden(true)
            }

            PavbotTranslatedAutomationText(
                topic.title,
                document: translationDocument,
                path: "\(translationPathPrefix).title"
            )
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            PavbotTranslatedAutomationText(
                topic.lead,
                document: translationDocument,
                path: "\(translationPathPrefix).lead"
            )
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(backgroundShape)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.14), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Otwiera pełne szczegóły tematu")
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.orange.opacity(0.045),
                        Color(.secondarySystemBackground).opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 5)
    }

    private var accessibilityLabel: String {
        var values = [
            topic.section,
            PavbotNewsPriorityStyle(topic.priority).title,
            topic.title,
            topic.lead
        ]
        if topic.sources.count > 0 {
            values.append(topic.sources.count == 1 ? "1 źródło" : "\(topic.sources.count) źródeł")
        }
        return values.joined(separator: ". ")
    }
}

private struct TodayLiveTopicRow: View {
    let topic: TodayLiveTopic
    let isSaved: Bool
    var isFeatured = false
    var translationDocument: AutomationTranslationDocument?
    var translationPathPrefix: String?

    var body: some View {
        PavbotNewsStoryCard(
            presentation: PavbotNewsStoryPresentation(
                id: topic.id,
                section: topic.section,
                sectionSystemImage: topic.scope.systemImage,
                title: topic.title,
                lead: topic.lead,
                priority: topic.priority,
                facts: topic.keyFacts,
                sources: topic.sources,
                tags: topic.tags,
                canReadAloud: true,
                translationDocument: translationDocument,
                translationPathPrefix: translationPathPrefix,
                translationFieldPaths: TodayLiveTopicsSnapshot.storyTranslationFieldPaths(for: topic)
            ),
            tint: .orange,
            isSaved: isSaved,
            isFeatured: isFeatured
        )
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
                    Label(LocalizedStringKey("Pauza"), systemImage: "pause.circle.fill")
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
            Label(LocalizedStringKey(title), systemImage: "newspaper")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(LocalizedStringKey(message))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: openAktualne) {
                Label(LocalizedStringKey("Otwórz Aktualne"), systemImage: "arrow.right.circle.fill")
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
    @State private var selectedSavedTopic: SavedTodayLiveTopic?

    private var savedTopics: [SavedTodayLiveTopic] {
        savedStore.filteredTopics(query: query)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey("Zapisane Pulsu Dnia"))
                            .font(.title2.weight(.bold))
                        Text(LocalizedStringKey("Zapisane newsy zostają lokalnie w aplikacji. Możesz wrócić do faktów, reakcji i źródeł nawet po kolejnych odświeżeniach feedu."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if savedTopics.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(LocalizedStringKey("Brak zapisanych newsów"), systemImage: "bookmark")
                                .font(.headline.weight(.semibold))
                            Text(LocalizedStringKey(query.isEmpty ? "Otwórz temat w Pulsie Dnia i użyj przycisku zapisania." : "Nie znaleziono zapisanego tematu dla wpisanego tekstu."))
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
                    savedStore: savedStore,
                    translationDocument: saved.topic.automationTranslationDocument,
                    translationPathPrefix: nil
                )
                .pavbotLargeObjectPresentation()
            }
        }
    }
}

private struct TodayLiveTopicsSavedRow: View {
    @Environment(AppLanguageStore.self) private var languageStore
    let saved: SavedTodayLiveTopic

    private var translationDocument: AutomationTranslationDocument {
        saved.topic.automationTranslationDocument
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                StatusBadge(text: sourceLabel, systemImage: "bookmark.fill", tint: .blue)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(saved.savedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    PavbotSourceCountBadge(count: saved.topic.sources.count, tint: .blue)
                }
            }

            PavbotTranslatedAutomationText(
                saved.topic.title,
                document: translationDocument,
                path: "title"
            )
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            PavbotTranslatedAutomationText(
                saved.topic.lead,
                document: translationDocument,
                path: "lead"
            )
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !saved.topic.tags.isEmpty {
                PavbotArticleKeywordRows(horizontalSpacing: 7, verticalSpacing: 6) {
                    ForEach(Array(saved.topic.tags.prefix(3).enumerated()), id: \.offset) { index, tag in
                        PavbotArticleTagChip(
                            title: tag,
                            systemImage: "tag.fill",
                            tint: .blue,
                            accessibilityPrefix: "Tag zapisanego tematu",
                            translatesAutomationText: true,
                            translationDocument: translationDocument,
                            translationPath: "tags.\(index)"
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var sourceLabel: String {
        switch (saved.source, languageStore.preference) {
        case (.pulseNews, .polish):
            "Puls dnia 3h"
        case (.pulseNews, .english):
            "Daily Pulse 3h"
        case (.pulseNews, .russian):
            "Пульс дня 3 ч"
        case (.mobileNews, .polish):
            "Dane fallbackowe z magazynu 10:15"
        case (.mobileNews, .english):
            "10:15 magazine fallback"
        case (.mobileNews, .russian):
            "Резервные данные журнала 10:15"
        }
    }
}

private struct TodayLiveTopicTextSection: View {
    let title: String
    let items: [String]
    let tint: Color
    var document: AutomationTranslationDocument?
    var pathPrefix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    PavbotTranslatedAutomationText(
                        item,
                        document: document,
                        path: pathPrefix.map { "\($0).\(index)" }
                    )
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
    var document: AutomationTranslationDocument?
    var path: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            PavbotTranslatedAutomationText(text, document: document, path: path)
                .font(.callout)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
