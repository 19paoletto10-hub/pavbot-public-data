import SwiftUI

struct JobsView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var jobsStore = JobsStore()
    @State private var historyStore = JobsHistoryStore()
    @State private var viewMode: JobsViewMode = .brief
    @State private var selectedFilter: JobsFilter = .all
    @State private var selectedHistoryDate: String?
    @State private var searchText = ""
    @State private var selectedOpportunity: JobOpportunity?
    @State private var selectedHistoricalOpportunity: HistoricalJobOpportunity?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let manifest = store.manifest {
                    let packages = manifest.reportPackages(for: .jobs)
                    JobsHeader(
                        packageCount: packages.count,
                        report: jobsStore.report,
                        source: jobsStore.source
                    )

                    if packages.isEmpty {
                        ContentUnavailableView(
                            "Brak raportów Jobs",
                            systemImage: "briefcase",
                            description: Text("Odśwież manifest po publikacji automatyzacji LLM/AI Jobs Wrocław.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        JobsModePicker(selection: $viewMode)

                        switch viewMode {
                        case .brief:
                            JobsContent(
                                state: jobsStore.state,
                                report: jobsStore.report,
                                package: jobsStore.selectedPackage,
                                source: jobsStore.source,
                                cacheNotice: jobsStore.cacheNotice,
                                filter: $selectedFilter,
                                searchText: searchText,
                                selectedOpportunity: $selectedOpportunity
                            )
                        case .allOffers:
                            JobsHistoryContent(
                                state: historyStore.state,
                                snapshot: historyStore.snapshot,
                                filter: $selectedFilter,
                                selectedDate: $selectedHistoryDate,
                                searchText: searchText,
                                selectedOpportunity: $selectedHistoricalOpportunity
                            )
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Brak manifestu",
                        systemImage: "doc.badge.questionmark",
                        description: Text("Ustaw Manifest URL w Settings i odśwież dane.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Jobs")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Szukaj firm, ról i tagów")
        .navigationDestination(for: PavbotArtifact.self) { artifact in
            ArtifactDetailView(artifact: artifact)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reloadJobs(refreshManifest: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.state == .loading || jobsStore.state == .loading)
                .accessibilityLabel("Odśwież Jobs")
            }
        }
        .refreshable {
            await reloadJobs(refreshManifest: true)
        }
        .task(id: loadKey) {
            await reloadJobs(refreshManifest: false)
        }
        .onChange(of: viewMode) { _, newValue in
            guard newValue == .allOffers else { return }
            Task { await reloadHistory(refreshManifest: false) }
        }
        .sheet(item: $selectedOpportunity) { opportunity in
            JobOpportunityDetailView(opportunity: opportunity)
        }
        .sheet(item: $selectedHistoricalOpportunity) { opportunity in
            HistoricalJobOpportunityDetailView(item: opportunity)
        }
    }

    private var loadKey: String {
        [
            store.manifest?.generatedAt,
            router.selectedReportDay,
            router.selectedReportArtifactIDs.joined(separator: "|"),
            store.manifestURLString
        ]
        .compactMap { $0 }
        .joined(separator: "::")
    }

    private func reloadJobs(refreshManifest: Bool) async {
        if refreshManifest {
            await store.reload()
        }
        guard let manifest = store.manifest else { return }
        await jobsStore.load(
            packages: manifest.reportPackages(for: .jobs),
            manifestURLString: store.manifestURLString,
            selectedDay: router.selectedReportDay,
            selectedArtifactIDs: router.selectedReportArtifactIDs
        )
        if viewMode == .allOffers {
            await historyStore.load(
                packages: manifest.reportPackages(for: .jobs),
                manifestURLString: store.manifestURLString,
                selectedDay: router.selectedReportDay
            )
        }
    }

    private func reloadHistory(refreshManifest: Bool) async {
        if refreshManifest {
            await store.reload()
        }
        guard let manifest = store.manifest else { return }
        await historyStore.load(
            packages: manifest.reportPackages(for: .jobs),
            manifestURLString: store.manifestURLString,
            selectedDay: router.selectedReportDay
        )
    }
}

enum JobsViewMode: String, CaseIterable, Identifiable {
    case brief
    case allOffers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brief:
            "Brief dnia"
        case .allOffers:
            "Wszystkie oferty"
        }
    }
}

struct JobsOpportunityPresentationSnapshot: Equatable {
    let opportunities: [JobOpportunity]

    init(report: JobsReport?, filter: JobsFilter, searchText: String) {
        guard let report else {
            opportunities = []
            return
        }
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        opportunities = report.opportunities
            .filter { filter.matches($0) }
            .filter { opportunity in
                guard !trimmedSearch.isEmpty else { return true }
                return opportunity.normalizedSearchText.range(
                    of: trimmedSearch,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
    }
}

struct JobsHistoryPresentationSnapshot: Equatable {
    let opportunities: [HistoricalJobOpportunity]

    init(snapshot: JobsHistorySnapshot?, filter: JobsFilter, selectedDate: String?, searchText: String) {
        opportunities = snapshot?.filteredOpportunities(
            filter: filter,
            date: selectedDate,
            searchText: searchText
        ) ?? []
    }
}

private struct JobsModePicker: View {
    @Environment(PavbotHaptics.self) private var haptics
    @Binding var selection: JobsViewMode

    var body: some View {
        Picker("Widok Jobs", selection: $selection) {
            ForEach(JobsViewMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Wybierz widok Jobs")
        .onChange(of: selection) { _, _ in
            haptics.play(.selection)
        }
    }
}

private struct JobsContent: View {
    let state: JobsStore.LoadState
    let report: JobsReport?
    let package: TopicReportPackage?
    let source: JobsReportSource?
    let cacheNotice: String?
    @Binding var filter: JobsFilter
    let searchText: String
    @Binding var selectedOpportunity: JobOpportunity?

    private var presentationSnapshot: JobsOpportunityPresentationSnapshot {
        JobsOpportunityPresentationSnapshot(report: report, filter: filter, searchText: searchText)
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            if let report {
                loadedContent(report: report)
                    .overlay(alignment: .topTrailing) {
                        ProgressView()
                            .padding(14)
                    }
            } else {
                JobsLoadingSkeleton()
            }
        case .loaded:
            if let report {
                loadedContent(report: report)
            } else {
                ContentUnavailableView("Brak danych Jobs", systemImage: "briefcase")
                    .frame(maxWidth: .infinity, minHeight: 260)
            }
        case .failed(let error):
            if let report {
                VStack(alignment: .leading, spacing: 14) {
                    StatusBadge(text: "Dane z cache", systemImage: "externaldrive.fill.badge.checkmark", tint: .orange)
                    Text(error.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    loadedContent(report: report)
                }
            } else {
                PavbotStateView(error: error)
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    @ViewBuilder
    private func loadedContent(report: JobsReport) -> some View {
        JobsBriefCard(report: report, package: package, source: source)

        if let cacheNotice {
            PavbotCacheNoticeBanner(text: cacheNotice)
        }

        JobsFilterBar(selection: $filter)

        if presentationSnapshot.opportunities.isEmpty {
            ContentUnavailableView(
                "Brak ofert dla filtra",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Zmień filtr albo wyczyść wyszukiwanie, aby zobaczyć wszystkie znalezione role.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Najciekawsze oferty")
                    .font(.headline.weight(.semibold))
                ForEach(presentationSnapshot.opportunities) { opportunity in
                    JobOpportunityCard(opportunity: opportunity) {
                        selectedOpportunity = opportunity
                    }
                }
            }
        }
    }
}

private struct JobsHistoryContent: View {
    let state: JobsHistoryStore.LoadState
    let snapshot: JobsHistorySnapshot?
    @Binding var filter: JobsFilter
    @Binding var selectedDate: String?
    let searchText: String
    @Binding var selectedOpportunity: HistoricalJobOpportunity?

    private var presentationSnapshot: JobsHistoryPresentationSnapshot {
        JobsHistoryPresentationSnapshot(
            snapshot: snapshot,
            filter: filter,
            selectedDate: selectedDate,
            searchText: searchText
        )
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            if let snapshot {
                loadedContent(snapshot: snapshot)
                    .overlay(alignment: .topTrailing) {
                        ProgressView()
                            .padding(14)
                    }
            } else {
                JobsLoadingSkeleton()
            }
        case .loaded:
            if let snapshot {
                loadedContent(snapshot: snapshot)
            } else {
                ContentUnavailableView("Brak historii ofert", systemImage: "clock.badge.questionmark")
                    .frame(maxWidth: .infinity, minHeight: 260)
            }
        case .failed(let error):
            if let snapshot {
                VStack(alignment: .leading, spacing: 14) {
                    StatusBadge(text: "Ostatni widok historii", systemImage: "clock.arrow.circlepath", tint: .orange)
                    Text(error.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    loadedContent(snapshot: snapshot)
                }
            } else {
                PavbotStateView(error: error)
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    @ViewBuilder
    private func loadedContent(snapshot: JobsHistorySnapshot) -> some View {
        JobsHistorySummaryCard(snapshot: snapshot)
        JobsFilterBar(selection: $filter)
        JobsHistoryDateBar(snapshot: snapshot, selectedDate: $selectedDate)

        if presentationSnapshot.opportunities.isEmpty {
            ContentUnavailableView(
                "Brak ofert dla wybranego widoku",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Zmień filtr, datę albo wyszukiwanie, żeby zobaczyć oferty z ostatnich raportów.")
            )
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Znalezione oferty")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text("\(presentationSnapshot.opportunities.count)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.indigo.opacity(0.12), in: Capsule())
                }

                ForEach(presentationSnapshot.opportunities) { item in
                    HistoricalJobOpportunityCard(item: item) {
                        selectedOpportunity = item
                    }
                }
            }
        }
    }
}

private struct JobsHistorySummaryCard: View {
    let snapshot: JobsHistorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Historia ofert")
                        .font(.headline.weight(.semibold))
                    Text("Scalone role z najnowszego raportu i dwóch poprzednich dni.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 10) {
                JobsInlineMetric(title: "Oferty", value: "\(snapshot.opportunities.count)", subtitle: "unikalne", systemImage: "person.crop.rectangle.stack.fill", tint: .indigo)
                Divider().frame(height: 46)
                JobsInlineMetric(title: "Raporty", value: "\(snapshot.reportCount)", subtitle: snapshot.dateRangeLabel, systemImage: "doc.text.magnifyingglass", tint: .blue)
                Divider().frame(height: 46)
                JobsInlineMetric(title: "Fallback", value: "\(snapshot.sourceBreakdown[.markdownFallback] ?? 0)", subtitle: "\(snapshot.failedPackageCount) błędów", systemImage: "curlybraces", tint: .orange)
            }
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.indigo.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct JobsInlineMetric: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct JobsHistoryDateBar: View {
    let snapshot: JobsHistorySnapshot
    @Binding var selectedDate: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(snapshot.dateBuckets) { bucket in
                    let isSelected = selectedDate == bucket.date
                    Button {
                        selectedDate = bucket.date
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bucket.title)
                                .font(.caption.weight(.bold))
                            if let date = bucket.date {
                                Text(date)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                            }
                        }
                        .frame(minHeight: 44, alignment: .center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? .white : .indigo)
                        .background(isSelected ? Color.indigo : Color.indigo.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Filtr dat ofert Jobs")
    }
}

private struct HistoricalJobOpportunityCard: View {
    let item: HistoricalJobOpportunity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "briefcase.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 42, height: 42)
                        .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.opportunity.company)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Text(item.opportunity.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(item.latestSeen)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.indigo)
                        Text("ostatnio")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }

                Text(item.opportunity.fitSummary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        StatusBadge(text: item.opportunity.workMode, systemImage: "location.fill", tint: .blue)
                        StatusBadge(text: item.opportunity.seniority, systemImage: "star.fill", tint: .purple)
                    }
                    StatusBadge(text: "Widziana w \(item.occurrenceCount) \(item.occurrenceCount == 1 ? "raporcie" : "raportach")", systemImage: "clock.fill", tint: .orange)
                }

                if !item.opportunity.compensation.isEmpty {
                    Label(item.opportunity.compensation, systemImage: "banknote.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }

                JobsTagRow(tags: item.opportunity.tags)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 198, alignment: .topLeading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct JobsHeader: View {
    let packageCount: Int
    let report: JobsReport?
    let source: JobsReportSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "briefcase.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 48, height: 48)
                    .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text("LLM / AI Jobs Wrocław")
                        .font(.title2.weight(.bold))
                    Text("Natywny przegląd ról, firm, źródeł i sygnałów rynku.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                MetricTile(title: "Oferty", value: "\(report?.opportunities.count ?? 0)", systemImage: "person.crop.rectangle.stack.fill", tint: .indigo)
                MetricTile(title: "Zmiany", value: "\(report?.changes.count ?? 0)", systemImage: "sparkles", tint: .purple)
                MetricTile(title: "Źródła", value: "\(report?.checkedSources.count ?? 0)", subtitle: source?.label ?? "\(packageCount) publikacji", systemImage: "link.circle.fill", tint: .blue)
            }
        }
    }
}

private struct JobsBriefCard: View {
    let report: JobsReport
    let package: TopicReportPackage?
    let source: JobsReportSource?

    private var presentation: JobsBriefPresentation {
        JobsBriefPresentation(report: report)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            JobsBriefHero(
                presentation: presentation,
                runDateTime: report.displayRunDateTime,
                status: report.status,
                source: source
            )

            HighlightedKeywordText(
                text: report.executiveSummary,
                keywords: presentation.keywords
            )

            JobsBriefSignalSection(signals: presentation.signals)

            if !presentation.keywords.isEmpty {
                JobsBriefKeywordSection(keywords: presentation.keywords)
            }

            JobsBriefActionSection(presentation: presentation)

            if !presentation.topOpportunities.isEmpty {
                JobsBriefTopOpportunities(opportunities: presentation.topOpportunities)
            }

            if let package {
                Divider()
                JobsArchiveActions(package: package)
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [.indigo, .blue], startPoint: .leading, endPoint: .trailing))
                .frame(width: 82, height: 4)
                .padding(.leading, 18)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.indigo.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 8)
    }
}

private struct JobsBriefHero: View {
    let presentation: JobsBriefPresentation
    let runDateTime: String
    let status: String
    let source: JobsReportSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        StatusBadge(text: status, systemImage: "checkmark.seal.fill", tint: .green)
                        if let source {
                            StatusBadge(text: source.label, systemImage: "curlybraces", tint: .orange)
                        }
                    }

                    Text(presentation.title)
                        .font(.title2.weight(.bold))

                    Text(runDateTime)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text(presentation.lead)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HighlightedKeywordText: View {
    let text: String
    let keywords: [JobsBriefKeyword]

    var body: some View {
        Text(
            JobsKeywordHighlighter.attributedText(
                text,
                keywords: keywords,
                baseFont: .callout,
                baseColor: .secondary
            )
        )
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct JobsBriefSignalSection: View {
    let signals: [JobsBriefSignal]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Najważniejsze sygnały")
                .font(.headline.weight(.semibold))

            VStack(spacing: 9) {
                ForEach(signals) { signal in
                    JobsBriefSignalRow(signal: signal)
                }
            }
        }
    }
}

private struct JobsBriefSignalRow: View {
    let signal: JobsBriefSignal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: signal.kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(signal.kind.tint)
                .frame(width: 34, height: 34)
                .background(signal.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(signal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(signal.body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct JobsBriefKeywordSection: View {
    let keywords: [JobsBriefKeyword]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Słowa kluczowe")
                .font(.headline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keywords.prefix(12)) { keyword in
                        JobsBriefKeywordChip(keyword: keyword)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}

private struct JobsBriefKeywordChip: View {
    let keyword: JobsBriefKeyword

    var body: some View {
        Text(keyword.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(keyword.kind.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(keyword.kind.tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

private struct JobsBriefActionSection: View {
    let presentation: JobsBriefPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Co zrobić teraz", systemImage: "arrow.up.forward.circle.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.indigo)

            Text(presentation.primaryRecommendation)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(presentation.secondaryRecommendations, id: \.self) { action in
                Label(action, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct JobsBriefTopOpportunities: View {
    let opportunities: [JobOpportunity]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Szybki podgląd top ofert")
                .font(.headline.weight(.semibold))

            ForEach(opportunities.prefix(2)) { opportunity in
                HStack(alignment: .top, spacing: 10) {
                    Text("#\(opportunity.rank)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.indigo)
                        .frame(width: 34, height: 28)
                        .background(Color.indigo.opacity(0.12), in: Capsule())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(opportunity.company)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(opportunity.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !opportunity.compensation.isEmpty {
                            Text(opportunity.compensation)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct JobsArchiveActions: View {
    let package: TopicReportPackage

    var body: some View {
        HStack(spacing: 10) {
            if let report = package.researchReport {
                NavigationLink(value: report) {
                    JobsArchiveButton(title: "Otwórz raport", systemImage: "doc.text.fill", tint: .blue)
                }
                .buttonStyle(.plain)
            }
            if let pdf = package.pdfReport {
                NavigationLink(value: pdf) {
                    JobsArchiveButton(title: "Otwórz PDF", systemImage: "doc.richtext.fill", tint: .red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct JobsArchiveButton: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct JobsFilterBar: View {
    @Binding var selection: JobsFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JobsFilter.allCases) { filter in
                    Button {
                        selection = filter
                    } label: {
                        Label(filter.title, systemImage: filter.systemImage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .foregroundStyle(selection == filter ? .white : filter.tint)
                            .background(selection == filter ? filter.tint : filter.tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct JobOpportunityCard: View {
    let opportunity: JobOpportunity
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 42, height: 42)
                        .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(opportunity.company)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                        Text(opportunity.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Text("#\(opportunity.rank)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.indigo.opacity(0.12), in: Capsule())
                }

                Text(opportunity.fitSummary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    StatusBadge(text: opportunity.workMode, systemImage: "location.fill", tint: .blue)
                    StatusBadge(text: opportunity.seniority, systemImage: "star.fill", tint: .purple)
                }

                if !opportunity.compensation.isEmpty {
                    Label(opportunity.compensation, systemImage: "banknote.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }

                JobsTagRow(tags: opportunity.tags)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct JobsTagRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(tags.prefix(6), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .foregroundStyle(.secondary)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
            }
        }
    }
}

private struct JobOpportunityDetailView: View {
    let opportunity: JobOpportunity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(opportunity.company)
                            .font(.title2.weight(.bold))
                        Text(opportunity.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            StatusBadge(text: opportunity.workMode, systemImage: "location.fill", tint: .blue)
                            StatusBadge(text: opportunity.seniority, systemImage: "star.fill", tint: .purple)
                        }
                    }

                    JobDetailSection(title: "Dlaczego interesujące", systemImage: "sparkles", text: opportunity.whyInteresting)
                    JobDetailSection(title: "Fit LLM/AI", systemImage: "brain.head.profile", text: opportunity.fitSummary)
                    JobDetailSection(title: "Niepewność", systemImage: "exclamationmark.triangle.fill", text: opportunity.uncertainty)

                    if !opportunity.compensation.isEmpty {
                        JobDetailSection(title: "Wynagrodzenie", systemImage: "banknote.fill", text: opportunity.compensation)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Źródła")
                            .font(.headline.weight(.semibold))
                        ForEach(opportunity.sourceURLs, id: \.self) { source in
                            if let url = URL(string: source) {
                                Link(destination: url) {
                                    Label(source, systemImage: "link")
                                        .font(.footnote.weight(.medium))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(15)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Oferta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HistoricalJobOpportunityDetailView: View {
    let item: HistoricalJobOpportunity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.opportunity.company)
                            .font(.title2.weight(.bold))
                        Text(item.opportunity.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            StatusBadge(text: item.opportunity.workMode, systemImage: "location.fill", tint: .blue)
                            StatusBadge(text: item.opportunity.seniority, systemImage: "star.fill", tint: .purple)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Historia wystąpień", systemImage: "clock.arrow.circlepath")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.indigo)

                        HStack(alignment: .top, spacing: 12) {
                            JobsInlineMetric(title: "Pierwszy raz", value: item.firstSeen, subtitle: "w historii", systemImage: "calendar.badge.clock", tint: .blue)
                            Divider().frame(height: 46)
                            JobsInlineMetric(title: "Ostatnio", value: item.latestSeen, subtitle: "najnowszy raport", systemImage: "calendar.badge.checkmark", tint: .indigo)
                        }

                        Text("Widziana w \(item.occurrenceCount) \(item.occurrenceCount == 1 ? "raporcie" : "raportach"): \(item.reportDates.joined(separator: ", ")).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(15)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                    JobDetailSection(title: "Dlaczego interesujące", systemImage: "sparkles", text: item.opportunity.whyInteresting)
                    JobDetailSection(title: "Fit LLM/AI", systemImage: "brain.head.profile", text: item.opportunity.fitSummary)
                    JobDetailSection(title: "Niepewność", systemImage: "exclamationmark.triangle.fill", text: item.opportunity.uncertainty)

                    if !item.opportunity.compensation.isEmpty {
                        JobDetailSection(title: "Wynagrodzenie", systemImage: "banknote.fill", text: item.opportunity.compensation)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Źródła")
                            .font(.headline.weight(.semibold))
                        ForEach(item.sourceURLs, id: \.self) { source in
                            if let url = URL(string: source) {
                                Link(destination: url) {
                                    Label(source, systemImage: "link")
                                        .font(.footnote.weight(.medium))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(15)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Oferta historyczna")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct JobDetailSection: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct JobsLoadingSkeleton: View {
    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .frame(height: 210)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .frame(height: 170)
            }
        }
        .redacted(reason: .placeholder)
    }
}

enum JobsFilter: String, CaseIterable, Identifiable {
    case all
    case remote
    case hybrid
    case wroclaw
    case senior
    case agenticRag

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "Wszystkie"
        case .remote:
            "Remote"
        case .hybrid:
            "Hybrid"
        case .wroclaw:
            "Wrocław"
        case .senior:
            "Senior"
        case .agenticRag:
            "Agentic/RAG"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "square.grid.2x2"
        case .remote:
            "house.lodge"
        case .hybrid:
            "building.2"
        case .wroclaw:
            "mappin.and.ellipse"
        case .senior:
            "star"
        case .agenticRag:
            "brain.head.profile"
        }
    }

    var tint: Color {
        switch self {
        case .all:
            .indigo
        case .remote:
            .blue
        case .hybrid:
            .cyan
        case .wroclaw:
            .green
        case .senior:
            .purple
        case .agenticRag:
            .orange
        }
    }

    func matches(_ opportunity: JobOpportunity) -> Bool {
        let searchable = opportunity.normalizedSearchText.lowercased()
        switch self {
        case .all:
            return true
        case .remote:
            return searchable.contains("remote") || searchable.contains("zdal")
        case .hybrid:
            return searchable.contains("hybrid") || searchable.contains("hybryd")
        case .wroclaw:
            return searchable.contains("wrocław") || searchable.contains("wroclaw")
        case .senior:
            return searchable.contains("senior") || searchable.contains("principal") || searchable.contains("lead")
        case .agenticRag:
            return searchable.contains("agentic") || searchable.contains("rag") || searchable.contains("llm")
        }
    }
}
