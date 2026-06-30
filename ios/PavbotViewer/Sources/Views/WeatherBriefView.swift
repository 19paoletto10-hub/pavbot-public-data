import Charts
import ImageIO
import SwiftUI
import UIKit

struct WeatherBriefView: View {
    @Environment(WeatherBriefStore.self) private var weatherStore
    @Environment(TodayHumorStore.self) private var humorStore
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var rangeTileMode: WeatherRangeTileMode = .value
    @State private var precipitationTileMode: WeatherPrecipitationTileMode = .value
    @State private var isLocationEditorPresented = false
    @State private var savedHumorStore = TodayHumorSavedStore()
    @State private var selectedCockpitHumorItem: TodayHumorItem?
    @State private var isCockpitHumorSavedPresented = false

    var body: some View {
        GeometryReader { proxy in
            let layout = PavbotAdaptiveLayout.resolve(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            ScrollView {
                VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                    switch weatherStore.state {
                    case .loading where weatherStore.report == nil:
                        loadingView
                    case .failed(let error) where weatherStore.report == nil:
                        missingConfigurationView(error: error)
                    default:
                        if let report = weatherStore.report {
                            reportView(report, layout: layout)
                        } else {
                            missingConfigurationView(
                                error: .custom(
                                    title: "Brak raportu pogodowego",
                                    message: "Brak raportu pogodowego.",
                                    actionTitle: "Otwórz ustawienia",
                                    systemImage: "cloud.sun.fill",
                                    tint: .blue
                                )
                            )
                        }
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
                .frame(maxWidth: layout.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .environment(\.pavbotAdaptiveLayout, layout)
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Dzisiaj")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PavbotRefreshToolbarButton(
                    isRefreshing: isRefreshingTodayContent,
                    accessibilityLabel: "Odśwież pogodę i radar memów",
                    accessibilityHint: "Odświeża raport pogodowy oraz Śmiechowy radar."
                ) {
                    Task { await refreshCurrentWeather() }
                }
            }
        }
        .task {
            await loadTodayContent(minimumInterval: 20)
        }
        .task {
            await runTopHourRefreshLoop()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, router.selectedTab == .today else { return }
            Task {
                await loadTodayContent()
            }
        }
        .refreshable {
            await refreshCurrentWeather()
        }
        .sheet(isPresented: $isLocationEditorPresented) {
            WeatherLocationEditorView(
                currentLocationLabel: ManualWeatherLocationSettings.location()?.city
                    ?? weatherStore.report?.city
                    ?? WeatherBriefLocation.fallback.city,
                refreshWeather: { location in
                    await weatherStore.refreshNow(location: location)
                }
            )
            .pavbotLargeObjectPresentation()
        }
        .sheet(item: $selectedCockpitHumorItem) { item in
            TodayHumorDetailSheet(
                item: item,
                digestID: humorStore.digest?.id ?? "",
                digestTitle: humorStore.digest?.title ?? "<RR> Reddit Radar",
                displayTime: humorStore.digest?.displayTime ?? "",
                savedStore: savedHumorStore
            )
            .pavbotLargeObjectPresentation()
        }
        .sheet(isPresented: $isCockpitHumorSavedPresented) {
            TodayHumorSavedView(savedStore: savedHumorStore)
                .pavbotLargeObjectPresentation()
        }
        .pavbotTabInfo(.today)
    }

    private func refreshCurrentWeather() async {
        guard !isRefreshingTodayContent else { return }
        await weatherStore.refreshSelectedLocation()
        await humorStore.load()
    }

    private var isRefreshingTodayContent: Bool {
        weatherStore.isRefreshing || humorStore.isRefreshing
    }

    private func loadTodayContent(
        minimumInterval: TimeInterval = 0,
        useCurrentLocationIfAuthorized: Bool = false
    ) async {
        if useCurrentLocationIfAuthorized {
            await weatherStore.loadWithCurrentLocation(minimumInterval: minimumInterval)
        } else {
            await weatherStore.load(minimumInterval: minimumInterval)
        }
        await humorStore.load(minimumInterval: minimumInterval)
    }

    private func runTopHourRefreshLoop() async {
        while !Task.isCancelled {
            let delay = Self.secondsUntilNextHour()
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, router.selectedTab == .today else { continue }
            await weatherStore.load(minimumInterval: 30)
        }
    }

    private static func secondsUntilNextHour(now: Date = Date(), calendar inputCalendar: Calendar = .current) -> TimeInterval {
        var calendar = inputCalendar
        calendar.timeZone = .current
        guard let interval = calendar.dateInterval(of: .hour, for: now) else {
            return 3600
        }
        return max(1, interval.end.timeIntervalSince(now))
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Pobieram poranny raport pogodowy...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private func missingConfigurationView(error: PavbotUserFacingError) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "cloud.sun")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 8) {
                Text(error.title)
                    .font(.title2.bold())
                Text(error.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button {
                router.selectedTab = .settings
            } label: {
                Label("Otwórz ustawienia", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func reportView(_ report: DailyWeatherReport, layout: PavbotAdaptiveLayout) -> some View {
        if layout.usesDashboardLayout {
            wideReportView(report, layout: layout)
        } else {
            phoneCockpitView(report, layout: layout)
        }
    }

    private func phoneCockpitView(_ report: DailyWeatherReport, layout: PavbotAdaptiveLayout) -> some View {
        PavbotPhoneDailyCockpit(
            report: report,
            cacheNotice: weatherStore.cacheNotice,
            locationNotice: weatherStore.locationNotice,
            humorDigest: humorStore.digest,
            humorState: humorStore.state,
            humorCacheNotice: humorStore.cacheNotice,
            isRefreshingHumor: humorStore.isRefreshing,
            isRefreshingTodayContent: isRefreshingTodayContent,
            dailyWisdomEntry: DailyWisdomProvider.entry(for: reportDate(report)),
            rangeTileMode: rangeTileMode,
            precipitationTileMode: precipitationTileMode,
            layout: layout,
            editLocation: {
                isLocationEditorPresented = true
            },
            toggleRangeTile: {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    rangeTileMode.toggle()
                }
            },
            togglePrecipitationTile: {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                    precipitationTileMode.toggle()
                }
            },
            openPulseDay: {
                router.selectedTab = .pulseDay
            },
            openJobs: {
                router.selectedTab = .jobs
            },
            openSettings: {
                router.selectedTab = .settings
            },
            reloadHumor: {
                Task { await humorStore.load() }
            },
            openHumorDetail: { item in
                selectedCockpitHumorItem = item
            },
            openSavedHumor: {
                isCockpitHumorSavedPresented = true
            }
        )
        .environment(\.pavbotAdaptiveLayout, layout)
    }

    private func compactReportView(_ report: DailyWeatherReport, layout: PavbotAdaptiveLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            DailyWisdomBanner(entry: DailyWisdomProvider.entry(for: reportDate(report)), report: report)

            WeatherHeroCard(report: report)

            if let cacheNotice = weatherStore.cacheNotice {
                PavbotCacheNoticeBanner(text: cacheNotice)
            }

            if let importantLocationNotice = WeatherLocationNoticeVisibility.importantNotice(from: weatherStore.locationNotice) {
                WeatherLocationNoticeBanner(text: importantLocationNotice) {
                    isLocationEditorPresented = true
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                WeatherMetricTile(
                    title: "Odczuwalna",
                    value: report.temperature.apparentLabel,
                    systemImage: "thermometer.medium",
                    tint: .orange
                )
                WeatherRangeTimelineTile(report: report, mode: rangeTileMode) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        rangeTileMode.toggle()
                    }
                }
                .environment(\.pavbotAdaptiveLayout, layout)
                WeatherPrecipitationTile(report: report, mode: precipitationTileMode) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        precipitationTileMode.toggle()
                    }
                }
                .environment(\.pavbotAdaptiveLayout, layout)
                WeatherMetricTile(
                    title: "Wiatr",
                    value: report.wind.speedLabel,
                    systemImage: "wind",
                    tint: .cyan
                )
            }

            WeatherNarrativePanel(report: report)

            TodayHumorPanel(
                digest: humorStore.digest,
                state: humorStore.state,
                cacheNotice: humorStore.cacheNotice,
                isRefreshing: humorStore.isRefreshing,
                layout: layout,
                savedStore: savedHumorStore
            ) {
                Task { await humorStore.load() }
            }

            if let generatedAtDate = report.generatedAtDate {
                Text("Zaktualizowano \(generatedAtDate.formatted(date: .omitted, time: .shortened)) · \(report.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func wideReportView(_ report: DailyWeatherReport, layout: PavbotAdaptiveLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.sectionSpacing) {
            DailyWisdomBanner(entry: DailyWisdomProvider.entry(for: reportDate(report)), report: report)

            HStack(alignment: .top, spacing: layout.cardSpacing) {
                WeatherHeroCard(report: report)
                    .frame(maxWidth: .infinity, minHeight: 280)

                TemperatureTimelineChartTile(report: report)
                    .frame(maxWidth: .infinity, minHeight: 280)
            }

            if let cacheNotice = weatherStore.cacheNotice {
                PavbotCacheNoticeBanner(text: cacheNotice)
            }

            if let importantLocationNotice = WeatherLocationNoticeVisibility.importantNotice(from: weatherStore.locationNotice) {
                WeatherLocationNoticeBanner(text: importantLocationNotice) {
                    isLocationEditorPresented = true
                }
            }

            HStack(alignment: .top, spacing: layout.cardSpacing) {
                WeatherNarrativePanel(report: report)
                    .frame(maxWidth: .infinity)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    WeatherMetricTile(
                        title: "Odczuwalna",
                        value: report.temperature.apparentLabel,
                        systemImage: "thermometer.medium",
                        tint: .orange
                    )
                    WeatherRangeTimelineTile(report: report, mode: rangeTileMode) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            rangeTileMode.toggle()
                        }
                    }
                    WeatherPrecipitationTile(report: report, mode: precipitationTileMode) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            precipitationTileMode.toggle()
                        }
                    }
                    WeatherMetricTile(
                        title: "Wiatr",
                        value: report.wind.speedLabel,
                        systemImage: "wind",
                        tint: .cyan
                    )
                }
                .frame(maxWidth: layout.weatherMetricsMaxWidth)
            }

            TodayHumorPanel(
                digest: humorStore.digest,
                state: humorStore.state,
                cacheNotice: humorStore.cacheNotice,
                isRefreshing: humorStore.isRefreshing,
                layout: layout,
                savedStore: savedHumorStore
            ) {
                Task { await humorStore.load() }
            }

            if let generatedAtDate = report.generatedAtDate {
                Text("Zaktualizowano \(generatedAtDate.formatted(date: .omitted, time: .shortened)) · \(report.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func reportDate(_ report: DailyWeatherReport) -> Date {
        DateFormatter.pavbotDay.date(from: report.date) ?? Date()
    }

}

private struct PavbotPhoneCockpitHeader: View {
    let report: DailyWeatherReport
    let isRefreshing: Bool
    let freshnessLabel: String
    let freshnessSystemImage: String
    let freshnessTint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                PavbotFreshnessBadge(
                    label: freshnessLabel,
                    systemImage: freshnessSystemImage,
                    tint: freshnessTint
                )

                Spacer(minLength: 8)

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Odświeżam dane")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(dynamicDayTitle)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(dynamicDaySubtitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(report.temperature.currentLabel)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(report.conditions.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dynamicDayTitle: String {
        "\(report.weekday.capitalized), \(shortDateLabel)"
    }

    private var dynamicDaySubtitle: String {
        "Lokalizacja: \(report.city) · \(report.conditions.label.lowercased())."
    }

    private var shortDateLabel: String {
        guard let dateValue = DateFormatter.pavbotDay.date(from: report.date) else {
            return report.displayDate
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter.string(from: dateValue)
    }
}

struct PavbotImagePreviewRequest: Identifiable, Equatable {
    let id = UUID()
    let imageURL: URL
    let title: String
    let subtitle: String?
}

@Observable
final class PavbotImagePreviewStore {
    var request: PavbotImagePreviewRequest?

    func present(imageURL: URL, title: String, subtitle: String? = nil) {
        request = PavbotImagePreviewRequest(imageURL: imageURL, title: title, subtitle: subtitle)
    }

    func dismiss() {
        request = nil
    }
}

enum PavbotImageDownsampler {
    static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        guard CGImageSourceGetType(source) != nil else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up)))
        ] as CFDictionary

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: image)
    }
}

struct PavbotImagePreviewHost: View {
    let imagePreviewStore: PavbotImagePreviewStore

    var body: some View {
        ZStack {
            if let request = imagePreviewStore.request {
                PavbotImagePreviewOverlay(request: request) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        imagePreviewStore.dismiss()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(1000)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: imagePreviewStore.request?.id)
        .allowsHitTesting(imagePreviewStore.request != nil)
    }
}

private struct PavbotImagePreviewOverlay: View {
    let request: PavbotImagePreviewRequest
    let dismiss: () -> Void
    @State private var imageScale: CGFloat = 1
    @State private var lastImageScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.96)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 18) {
                Spacer(minLength: 22)

                PavbotDownsampledRemoteImage(
                    url: request.imageURL,
                    maxPixelSize: 3_200
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(imageScale)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    imageScale = min(max(1, lastImageScale * value), 4)
                                }
                                .onEnded { _ in
                                    lastImageScale = imageScale
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                imageScale = imageScale > 1 ? 1 : 2
                                lastImageScale = imageScale
                            }
                        }
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                } failure: {
                    Label("Nie udało się wczytać obrazu", systemImage: "photo.badge.exclamationmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                VStack(spacing: 5) {
                    Text(request.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if let subtitle = request.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .padding(18)
            .accessibilityLabel("Zamknij powiększony obraz Reddit")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Powiększony obraz Reddit")
    }
}

private struct PavbotDownsampledRemoteImage<Content: View, Placeholder: View, Failure: View>: View {
    let url: URL
    let maxPixelSize: CGFloat
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @ViewBuilder var failure: () -> Failure
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else if failed {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        failed = false

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                failed = true
                return
            }
            guard let decoded = PavbotImageDownsampler.downsample(data: data, maxPixelSize: maxPixelSize) else {
                failed = true
                return
            }
            image = decoded
        } catch {
            if !Task.isCancelled {
                failed = true
            }
        }
    }
}

private struct PavbotPhoneDailyCockpit: View {
    let report: DailyWeatherReport
    let cacheNotice: String?
    let locationNotice: String?
    let humorDigest: TodayHumorDigest?
    let humorState: TodayHumorStore.LoadState
    let humorCacheNotice: String?
    let isRefreshingHumor: Bool
    let isRefreshingTodayContent: Bool
    let dailyWisdomEntry: DailyWisdomEntry
    let rangeTileMode: WeatherRangeTileMode
    let precipitationTileMode: WeatherPrecipitationTileMode
    let layout: PavbotAdaptiveLayout
    let editLocation: () -> Void
    let toggleRangeTile: () -> Void
    let togglePrecipitationTile: () -> Void
    let openPulseDay: () -> Void
    let openJobs: () -> Void
    let openSettings: () -> Void
    let reloadHumor: () -> Void
    let openHumorDetail: (TodayHumorItem) -> Void
    let openSavedHumor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PavbotPhoneCockpitHeader(
                report: report,
                isRefreshing: isRefreshingTodayContent,
                freshnessLabel: freshnessLabel,
                freshnessSystemImage: freshnessSystemImage,
                freshnessTint: freshnessTint
            )

            if let cacheNotice {
                PavbotCacheNoticeBanner(text: cacheNotice)
            }

            if let importantLocationNotice = WeatherLocationNoticeVisibility.importantNotice(from: locationNotice) {
                WeatherLocationNoticeBanner(text: importantLocationNotice, changeAction: editLocation)
            }

            DailyWisdomBanner(entry: dailyWisdomEntry, report: report)

            weatherDecisionCard

            PavbotInsightStrip(insights: insightItems)

            weatherDetailsGrid

            TodayHumorFeaturedPreview(
                digest: humorDigest,
                state: humorState,
                cacheNotice: humorCacheNotice,
                isRefreshing: isRefreshingHumor,
                reload: reloadHumor,
                openSaved: openSavedHumor,
                openDetail: openHumorDetail
            )

            dailyActionSection

            if let generatedAtDate = report.generatedAtDate {
                Text("Aktualizacja \(generatedAtDate.formatted(date: .omitted, time: .shortened)) · \(report.source)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily cockpit Pavbot")
    }

    private var weatherDecisionCard: some View {
        PavbotPremiumCard(tint: .blue, cornerRadius: 26, horizontalPadding: 18, verticalPadding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: heroSymbol)
                        .font(.system(size: 34, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.yellow)
                        .frame(width: 48, height: 48)
                        .background(Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(report.headline)
                            .font(.title3.weight(.bold))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(report.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(precipitationAdvice)
                    .font(.callout.weight(.semibold))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                PavbotPrimaryActionCapsule(
                    title: "Dostosuj lokalizację",
                    systemImage: "location.circle.fill",
                    tint: .blue,
                    action: editLocation
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Najważniejsza decyzja dnia. \(report.headline). \(precipitationAdvice)")
    }

    private var dailyActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Następne kroki")
                .font(.headline.weight(.semibold))

            Button(action: openPulseDay) {
                PavbotCompactStoryRow(
                    title: "Puls Dnia",
                    subtitle: "Najważniejsze tematy w jednym widoku.",
                    systemImage: "newspaper.fill",
                    tint: .orange,
                    trailingText: "Otwórz"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Otwórz Puls Dnia")

            Button(action: openJobs) {
                PavbotCompactStoryRow(
                    title: "Jobs AI",
                    subtitle: "Sprawdź role LLM, ML i platform AI.",
                    systemImage: "briefcase.fill",
                    tint: .indigo,
                    trailingText: "Role"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Otwórz Jobs AI")

            Button(action: openSettings) {
                PavbotCompactStoryRow(
                    title: "Centrum aplikacji",
                    subtitle: "Pliki, automatyzacje i diagnostyka w ustawieniach.",
                    systemImage: "slider.horizontal.3",
                    tint: .teal,
                    trailingText: "Ustaw"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Otwórz ustawienia Pavbot")
        }
    }

    private var weatherDetailsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            WeatherRangeTimelineTile(report: report, mode: rangeTileMode, onToggle: toggleRangeTile)
                .environment(\.pavbotAdaptiveLayout, layout)
            WeatherPrecipitationTile(report: report, mode: precipitationTileMode, onToggle: togglePrecipitationTile)
                .environment(\.pavbotAdaptiveLayout, layout)
            WeatherMetricTile(
                title: "Odczuwalna",
                value: report.temperature.apparentLabel,
                systemImage: "thermometer.medium",
                tint: .orange
            )
            WeatherMetricTile(
                title: "Wiatr",
                value: report.wind.speedLabel,
                systemImage: "wind",
                tint: .cyan
            )
        }
    }

    private var insightItems: [PavbotInsight] {
        [
            PavbotInsight(
                title: "Opady",
                value: report.precipitation.probabilityLabel,
                systemImage: "cloud.rain.fill",
                tint: .blue
            ),
            PavbotInsight(
                title: "Zakres",
                value: report.temperature.rangeLabel,
                systemImage: "arrow.up.and.down",
                tint: .red
            ),
            PavbotInsight(
                title: "Radar",
                value: humorDigest == nil ? "Ładowanie" : "\(min(humorDigest?.items.count ?? 0, 12)) postów",
                systemImage: "sparkles.tv.fill",
                tint: .purple
            )
        ]
    }

    private var precipitationAdvice: String {
        WeatherPrecipitationTilePresentation(report: report).advice
    }

    private var freshnessLabel: String {
        cacheNotice == nil ? "Świeże dane" : "Dane z cache"
    }

    private var freshnessSystemImage: String {
        cacheNotice == nil ? "checkmark.seal.fill" : "externaldrive.fill"
    }

    private var freshnessTint: Color {
        cacheNotice == nil ? .green : .orange
    }

    private var heroSymbol: String {
        switch report.conditions.code {
        case 0...2:
            "sun.max.fill"
        case 45, 48:
            "cloud.fog.fill"
        case 51...67, 80...82:
            "cloud.rain.fill"
        case 71...77, 85...86:
            "cloud.snow.fill"
        case 95...99:
            "cloud.bolt.rain.fill"
        default:
            "cloud.sun.fill"
        }
    }

}

private struct DailyWisdomBanner: View {
    let entry: DailyWisdomEntry
    let report: DailyWeatherReport

    var body: some View {
        PavbotPremiumCard(tint: .orange, cornerRadius: 24, horizontalPadding: 18, verticalPadding: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 5) {
                    Text(calendarMonthLabel)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.orange.gradient, in: UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: 4,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 16,
                            style: .continuous
                        ))

                    Text(calendarDayNumber)
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(report.weekday.capitalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .padding(8)
                .frame(width: 86)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Data kartki kalendarzowej: \(calendarDayNumber) \(calendarMonthLabel), \(report.weekday)")

                VStack(alignment: .leading, spacing: 10) {
                    Label("Kartka z kalendarza", systemImage: "sunrise.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .textCase(.uppercase)

                    Text("„\(entry.text)”")
                        .font(.title3.weight(.bold))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.attribution)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(entry.context)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 1)

                    Text(entry.category.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.10), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kartka z kalendarza, \(calendarDayNumber) \(calendarMonthLabel). \(entry.text) \(entry.attribution). \(entry.context)")
    }

    private var calendarDayNumber: String {
        guard let dateValue = DateFormatter.pavbotDay.date(from: report.date) else {
            return report.date
        }
        let day = Calendar(identifier: .gregorian).component(.day, from: dateValue)
        return "\(day)"
    }

    private var calendarMonthLabel: String {
        guard let dateValue = DateFormatter.pavbotDay.date(from: report.date) else {
            return report.displayDate
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        let dayAndMonth = formatter.string(from: dateValue)
        return dayAndMonth
            .replacingOccurrences(of: calendarDayNumber, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TodayHumorFeaturedPreview: View {
    let digest: TodayHumorDigest?
    let state: TodayHumorStore.LoadState
    let cacheNotice: String?
    let isRefreshing: Bool
    let reload: () -> Void
    let openSaved: () -> Void
    let openDetail: (TodayHumorItem) -> Void

    var body: some View {
        PavbotPremiumCard(tint: .purple, cornerRadius: 26, horizontalPadding: 18, verticalPadding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                header

                if let cacheNotice {
                    Text(cacheNotice)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if digest == nil, state == .idle || state == .loading {
                    loadingContent
                } else if case .failed(let error) = state, digest == nil {
                    errorContent(error)
                } else if let digest {
                    digestContent(digest)
                } else {
                    Text("Brak postów do pokazania.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Śmiechowy radar", systemImage: "sparkles.tv.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.purple)
                Text("Przesuwaj w bok, żeby przejrzeć wszystkie posty z obrazem i opisem.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: openSaved) {
                Image(systemName: "bookmark.fill")
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
                    .background(Color.purple.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.purple)
            .accessibilityLabel("Otwórz zapisane Reddit Radar")

            PavbotRefreshButton(
                isRefreshing: isRefreshing,
                accessibilityLabel: "Odśwież Reddit Radar",
                accessibilityHint: "Odświeża tylko Śmiechowy radar.",
                action: reload
            )
            .buttonStyle(.plain)
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Szukam świeżych memów i lekkich trendów...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
    }

    private func errorContent(_ error: PavbotUserFacingError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.title)
                .font(.headline.weight(.semibold))
            Text(error.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
    }

    private func digestContent(_ digest: TodayHumorDigest) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(digest.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                PavbotFreshnessBadge(
                    label: "co \(digest.refreshIntervalHours)h",
                    systemImage: "clock.arrow.circlepath",
                    tint: .purple
                )
            }

            TodayHumorSummaryText(summary: digest.summary)

            TodayHumorSideScrollList(items: digest.items, openDetail: openDetail)

            Text("Ostatnio: \(digest.displayTime) · następne: \(digest.nextRefreshLabel)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct TodayHumorSideScrollList: View {
    let items: [TodayHumorItem]
    let openDetail: (TodayHumorItem) -> Void

    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            openDetail(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                TodayHumorArtwork(imageLink: item.imageLink, height: item.imageLink == nil ? 104 : 148)

                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.title)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(item.caption)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                HStack(spacing: 8) {
                                    Label(item.sourceName, systemImage: "link")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Spacer(minLength: 8)

                                    if let scoreLabel = item.scoreLabel {
                                        Label(scoreLabel, systemImage: "arrow.up")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.purple)
                                    }
                                }
                            }
                            .padding(14)
                            .frame(width: 292, alignment: .topLeading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.purple.opacity(0.12), lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Otwórz post Reddit Radar: \(item.title)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct WeatherRangeTimelineTile: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let report: DailyWeatherReport
    let mode: WeatherRangeTileMode
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 12) {
                switch mode {
                case .value:
                    valueContent
                case .chart:
                    chartContent
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: layout.weatherTileMinHeight, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zakres dnia. Przełącz wykres temperatury godzinowej.")
        .accessibilityValue(mode == .chart ? "Pokazuję wykres słupkowy" : report.temperature.rangeLabel)
    }

    private var valueContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "arrow.up.and.down")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.red)
                .frame(width: 34, height: 34)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(report.temperature.rangeLabel)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("Zakres dnia")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Dotknij, aby zobaczyć wykres")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartContent: some View {
        let model = TemperatureTimelineChartModel(report: report, maxVisibleLabels: 4)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zakres dnia")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Temperatura godzinowa")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
            }

            if model.bars.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Brak danych godzinowych")
                        .font(.caption.weight(.semibold))
                    Text("Dotknij, aby wrócić do zakresu")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                Chart(model.bars) { bar in
                    BarMark(
                        x: .value("Godzina", bar.date, unit: .hour),
                        yStart: .value("Punkt bazowy", bar.yStart),
                        yEnd: .value("Temperatura", bar.yEnd),
                        width: .ratio(0.68)
                    )
                    .foregroundStyle(WeatherTimelineChartData.temperatureColor(for: bar.temperature))
                    .cornerRadius(5)
                    .annotation(position: .top, alignment: .center) {
                        if model.visibleLabelIDs.contains(bar.id) {
                            WeatherTemperatureChartBubbleLabel(
                                bar.temperatureLabel,
                                temperature: bar.temperature,
                                font: .system(size: 9, weight: .bold),
                                horizontalPadding: 3,
                                verticalPadding: 1
                            )
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                            .font(.caption2)
                    }
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: model.domain)
                .frame(height: 98)
                .accessibilityLabel("Mini wykres słupkowy temperatury godzinowej")

                Text("Dotknij, aby wrócić do zakresu")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TemperatureTimelineChartTile: View {
    let report: DailyWeatherReport

    var body: some View {
        let model = TemperatureTimelineChartModel(report: report, maxVisibleLabels: 7)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Temperatura godzinowa do końca dnia", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                Text(model.bars.isEmpty ? "Brak danych" : "\(model.bars.count) punktów")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if model.bars.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brak danych godzinowych")
                        .font(.title3.bold())
                    Text("Backend nie zwrócił jeszcze godzinowego przebiegu temperatury dla tego raportu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            } else {
                Chart(model.bars) { bar in
                    BarMark(
                        x: .value("Godzina", bar.date, unit: .hour),
                        yStart: .value("Punkt bazowy", bar.yStart),
                        yEnd: .value("Temperatura", bar.yEnd),
                        width: .ratio(0.66)
                    )
                    .foregroundStyle(temperatureColor(for: bar.temperature))
                    .cornerRadius(7)
                    .annotation(position: .top, alignment: .center) {
                        if model.visibleLabelIDs.contains(bar.id) {
                            WeatherTemperatureChartBubbleLabel(
                                bar.temperatureLabel,
                                temperature: bar.temperature,
                                font: .caption2.weight(.bold),
                                horizontalPadding: 5,
                                verticalPadding: 2
                            )
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let temperature = value.as(Double.self) {
                                Text("\(Int(temperature.rounded()))°")
                            }
                        }
                    }
                }
                .chartYScale(domain: model.domain)
                .frame(height: 205)
                .accessibilityLabel("Słupkowy wykres temperatury godzinowej do końca dnia")

                if let last = model.bars.last {
                    Text("Prognoza od aktualnej godziny do \(last.date.formatted(date: .omitted, time: .shortened)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func temperatureColor(for value: Double) -> Color {
        WeatherTimelineChartData.temperatureColor(for: value)
    }
}

private struct WeatherTemperatureChartBubbleLabel: View {
    let text: String
    let temperature: Double
    let font: Font
    var horizontalPadding: CGFloat = 0
    var verticalPadding: CGFloat = 0

    init(
        _ text: String,
        temperature: Double,
        font: Font,
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 0
    ) {
        self.text = text
        self.temperature = temperature
        self.font = font
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        let bubbleColor = WeatherTimelineChartData.temperatureColor(for: temperature)

        Text(text)
            .font(font)
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.32), radius: 1, x: 0, y: 1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(bubbleColor, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(.systemBackground).opacity(0.72), lineWidth: 1)
            }
            .shadow(color: bubbleColor.opacity(0.28), radius: 4, x: 0, y: 2)
            .accessibilityLabel(text)
    }
}

private enum WeatherLocationNoticeVisibility {
    static func importantNotice(from notice: String?) -> String? {
        guard let notice else { return nil }
        let lowercasedNotice = notice.lowercased()
        let importantTokens = [
            "niedostęp",
            "odmów",
            "odmow",
            "fallback",
            "używam pogody",
            "uzywam pogody",
            "nie udało",
            "nie udalo"
        ]
        return importantTokens.contains { lowercasedNotice.contains($0) } ? notice : nil
    }
}

private struct WeatherLocationNoticeBanner: View {
    let text: String
    let changeAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label(text, systemImage: "location.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.blue)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: changeAction) {
                Text("Zmień")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .background(Color.blue.opacity(0.12), in: Capsule())
            .accessibilityLabel("Zmień lokalizację prognozy")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityHint("Otwiera formularz ręcznego wyboru miasta dla pogody.")
    }
}

private struct WeatherLocationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotHaptics.self) private var haptics
    let currentLocationLabel: String
    let refreshWeather: (WeatherBriefLocation) async -> Void
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var isResolving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lokalizacja prognozy")
                            .font(.title2.weight(.bold))
                        Text("Wpisz miasto, dla którego Pavbot ma pobierać pogodę. Wybór zapisuje się lokalnie i działa także po ponownym uruchomieniu aplikacji.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aktualnie")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Label(currentLocationLabel, systemImage: "location.fill")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Np. Warszawa, Gdańsk, Kraków", text: $query)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit {
                                Task { await saveManualLocation() }
                            }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button {
                        Task { await saveManualLocation() }
                    } label: {
                        if isResolving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Zapisz lokalizację", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResolving || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        Label("Użyj mojej lokalizacji", systemImage: "location.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResolving)

                    Button(role: .none) {
                        Task { await restoreDefaultLocation() }
                    } label: {
                        Label("Wróć do domyślnego Wrocławia", systemImage: "arrow.uturn.backward.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResolving)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pogoda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveManualLocation() async {
        guard !isResolving else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            let location = try await WeatherLocationService().weatherLocation(for: trimmedQuery)
            ManualWeatherLocationSettings.save(location)
            await refreshWeather(location)
            haptics.play(.success)
            dismiss()
        } catch {
            errorMessage = "Nie udało się znaleźć tej lokalizacji. Sprawdź nazwę miasta albo spróbuj wpisać większą miejscowość w pobliżu."
            haptics.play(.error)
        }
    }

    private func restoreDefaultLocation() async {
        guard !isResolving else { return }
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        ManualWeatherLocationSettings.clear()
        await refreshWeather(.fallback)
        haptics.play(.success)
        dismiss()
    }

    private func useCurrentLocation() async {
        guard !isResolving else { return }
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        do {
            let location = try await WeatherLocationService().currentWeatherLocation(mode: .requestIfNeeded)
            ManualWeatherLocationSettings.save(location)
            await refreshWeather(location)
            haptics.play(.success)
            dismiss()
        } catch {
            errorMessage = "Nie udało się pobrać bieżącej lokalizacji. Sprawdź zgodę na lokalizację albo wpisz miasto ręcznie."
            haptics.play(.error)
        }
    }
}

private struct WeatherHeroCard: View {
    let report: DailyWeatherReport

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(report.city)
                        .font(.largeTitle.bold())
                    Text("\(report.weekday.capitalized), \(report.displayDate)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: heroSymbol)
                    .font(.system(size: 42, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow)
                    .frame(width: 56, height: 56)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(report.temperature.currentLabel)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(report.conditions.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(report.headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.blue.opacity(0.12), Color.yellow.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var heroSymbol: String {
        switch report.conditions.code {
        case 0...2:
            "sun.max.fill"
        case 45, 48:
            "cloud.fog.fill"
        case 51...67, 80...82:
            "cloud.rain.fill"
        case 71...77, 85...86:
            "cloud.snow.fill"
        case 95...99:
            "cloud.bolt.rain.fill"
        default:
            "cloud.sun.fill"
        }
    }
}

private struct WeatherPrecipitationTile: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let report: DailyWeatherReport
    let mode: WeatherPrecipitationTileMode
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 12) {
                switch mode {
                case .value:
                    valueContent
                case .chart:
                    chartContent
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: layout.weatherTileMinHeight, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Opady. Przełącz godzinowy wykres opadów.")
        .accessibilityValue(mode == .chart ? WeatherPrecipitationTilePresentation(report: report).advice : report.precipitation.probabilityLabel)
    }

    private var valueContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "cloud.rain")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(report.precipitation.probabilityLabel)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text("Opady")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(report.precipitation.totalLabel) · dotknij po godziny")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var chartContent: some View {
        let presentation = WeatherPrecipitationTilePresentation(report: report)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.rain.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 28, height: 28)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Opady")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Godzinowa prognoza")
                        .font(.subheadline.bold())
                }
            }

            Text(presentation.advice)
                .font(.caption.weight(.semibold))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if presentation.chartPoints.isEmpty {
                Text("Dotknij, aby wrócić do podsumowania opadów")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Chart(presentation.chartPoints) { point in
                    BarMark(
                        x: .value("Godzina", point.hourLabel),
                        y: .value("Szansa opadów", chartValue(for: point)),
                        width: .ratio(0.72)
                    )
                    .foregroundStyle(color(for: point.kind))
                    .cornerRadius(4)
                    .annotation(position: .top, alignment: .center) {
                        if point.isSignificant {
                            Text("\(point.probability)%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisTick()
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 76)
                .accessibilityLabel("Mini wykres godzinowej szansy opadów")

                Text("Dotknij, aby wrócić do podsumowania")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(for kind: WeatherPrecipitationKind) -> Color {
        switch kind {
        case .rain:
            .blue
        case .snow:
            .cyan
        case .mixed:
            .indigo
        case .possible:
            .gray
        }
    }

    private func chartValue(for point: DailyWeatherHourlyPrecipitation) -> Int {
        point.probability > 0 ? point.probability : 20
    }
}

private struct WeatherMetricTile: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let title: String
    let value: String
    var caption: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: max(132, layout.weatherTileMinHeight - 24), alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WeatherNarrativePanel: View {
    let report: DailyWeatherReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Aktualny briefing", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.blue)

            Text(report.summary)
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                WeatherInlineFact(title: "Imieniny", value: report.nameDaysLabel)
                WeatherInlineFact(title: "Wilgotność", value: "\(report.humidity)%")
                if let sunrise = report.sunrise, let sunset = report.sunset {
                    WeatherInlineFact(title: "Słońce", value: "\(timeLabel(sunrise)) - \(timeLabel(sunset))")
                }
            }

            Text(report.weatherNarrativeRecommendation)
                .font(.callout.weight(.semibold))
                .lineSpacing(3)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func timeLabel(_ value: String) -> String {
        if let time = value.split(separator: "T").last {
            return String(time.prefix(5))
        }
        return value
    }
}

private struct TodayHumorPanel: View {
    let digest: TodayHumorDigest?
    let state: TodayHumorStore.LoadState
    let cacheNotice: String?
    let isRefreshing: Bool
    let layout: PavbotAdaptiveLayout
    let savedStore: TodayHumorSavedStore
    let reload: () -> Void
    @State private var selectedHumorItem: TodayHumorItem?
    @State private var isSavedPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Śmiechowy radar", systemImage: "sparkles.tv.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Button {
                    isSavedPresented = true
                } label: {
                    Label("Zapisane", systemImage: "bookmark.fill")
                        .font(.caption.weight(.bold))
                        .labelStyle(.iconOnly)
                        .frame(width: 32, height: 32)
                        .background(Color.purple.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.purple)
                .accessibilityLabel("Zapisane Reddit Radar")
                .accessibilityHint("Otwiera historię lokalnie zapisanych postów Reddit Radar.")
                PavbotRefreshButton(
                    isRefreshing: isRefreshing,
                    accessibilityLabel: "Odśwież radar memów",
                    accessibilityHint: "Odświeża tylko Śmiechowy radar.",
                    action: reload
                )
                .buttonStyle(.plain)
            }

            if let cacheNotice {
                Text(cacheNotice)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if digest == nil, state == .idle || state == .loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Szukam świeżych memów i lekkich trendów...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            } else if case .failed(let error) = state, digest == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.title)
                        .font(.subheadline.weight(.semibold))
                    Text(error.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            } else {
                if let digest {
                    digestContent(digest)
                } else {
                    Text("Brak memów do pokazania.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.purple.opacity(0.14), lineWidth: 1)
        }
        .sheet(item: $selectedHumorItem) { item in
            TodayHumorDetailSheet(
                item: item,
                digestID: digest?.id ?? "",
                digestTitle: digest?.title ?? "<RR> Reddit Radar",
                displayTime: digest?.displayTime ?? "",
                savedStore: savedStore
            )
            .pavbotLargeObjectPresentation()
        }
        .sheet(isPresented: $isSavedPresented) {
            TodayHumorSavedView(savedStore: savedStore)
                .pavbotLargeObjectPresentation()
        }
    }

    private func digestContent(_ digest: TodayHumorDigest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(digest.title)
                        .font(.title3.weight(.bold))
                    Spacer()
                    Label("co \(digest.refreshIntervalHours)h", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                TodayHumorSummaryText(summary: digest.summary)
                Text("Ostatnio: \(digest.displayTime) · następne: \(digest.nextRefreshLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TodayHumorDigestDiagnostics(digest: digest)
                if digest.hasCommentHighlightsWithoutOriginalBodies {
                    Text("Odśwież radar, aby pobrać oryginalne komentarze.")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if layout.isPhone {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: layout.cardSpacing) {
                        ForEach(digest.items) { item in
                            TodayHumorCard(item: item, layout: layout) {
                                selectedHumorItem = item
                            }
                            .frame(width: layout.humorCardMinWidth)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else {
                LazyVGrid(columns: layout.adaptiveColumns(minimum: layout.humorCardMinWidth), spacing: layout.cardSpacing) {
                    ForEach(digest.items) { item in
                        TodayHumorCard(item: item, layout: layout) {
                            selectedHumorItem = item
                        }
                    }
                }
            }
        }
    }
}

private struct TodayHumorCard: View {
    let item: TodayHumorItem
    let layout: PavbotAdaptiveLayout
    let openDetail: () -> Void

    var body: some View {
        Button(action: openDetail) {
            VStack(alignment: .leading, spacing: 12) {
                TodayHumorArtwork(imageLink: item.imageLink, height: item.imageLink == nil ? 96 : 128)

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title)
                        .font(layout.isPhone ? .subheadline.weight(.semibold) : .headline.weight(.semibold))
                        .lineLimit(layout.isPhone ? 3 : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.caption)
                        .font(layout.isPhone ? .caption : .callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(layout.isPhone ? 3 : 4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.10), in: Capsule())
                    }
                }

                HStack(spacing: 10) {
                    Label(item.sourceName, systemImage: "link")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if let scoreLabel = item.scoreLabel {
                        Label(scoreLabel, systemImage: "arrow.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(layout.isPhone ? 14 : 16)
            .frame(maxWidth: .infinity, minHeight: layout.humorCardMinHeight, alignment: .topLeading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.caption). Źródło: \(item.sourceName)")
    }
}

private struct TodayHumorArtwork: View {
    let imageLink: URL?
    let height: CGFloat

    var body: some View {
        ZStack {
            humorArtworkBackground

            if let imageLink {
                PavbotDownsampledRemoteImage(url: imageLink, maxPixelSize: 900) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ZStack {
                        humorPlaceholderIcon
                        ProgressView()
                    }
                } failure: {
                    humorPlaceholderIcon
                }
            } else {
                humorPlaceholderIcon
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var humorArtworkBackground: some View {
        LinearGradient(
            colors: [Color.purple.opacity(0.16), Color.blue.opacity(0.10), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var humorPlaceholderIcon: some View {
        Image(systemName: "face.smiling.inverse")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.purple)
    }
}

private struct TodayHumorSummaryText: View {
    let summary: String

    var body: some View {
        parsedSummary
            .font(.callout)
            .lineSpacing(3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var parsedSummary: Text {
        var remaining = summary
        var result = Text("")
        while let start = remaining.range(of: "<u>"),
              let end = remaining.range(of: "</u>", range: start.upperBound..<remaining.endIndex) {
            let prefix = String(remaining[..<start.lowerBound])
            let highlighted = String(remaining[start.upperBound..<end.lowerBound])
            result = result + Text(prefix) + Text(highlighted).underline()
            remaining = String(remaining[end.upperBound...])
        }
        return result + Text(remaining.replacingOccurrences(of: "<u>", with: "").replacingOccurrences(of: "</u>", with: ""))
    }
}

private struct TodayHumorDigestDiagnostics: View {
    let digest: TodayHumorDigest

    var body: some View {
        Text("Serwer: \(serverLabel) · Digest: \(digest.id) · Komentarze: \(digest.originalCommentBodyCount)/\(digest.commentHighlightCount)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var serverLabel: String {
        NotificationServerSettings.serverURL?.host ?? NotificationServerSettings.serverURLString
    }
}

private struct TodayHumorDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotHaptics.self) private var haptics
    @Environment(PavbotImagePreviewStore.self) private var imagePreviewStore
    let item: TodayHumorItem
    let digestID: String
    let digestTitle: String
    let displayTime: String
    let savedStore: TodayHumorSavedStore

    private var isSaved: Bool {
        savedStore.isSaved(item)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        guard let imageLink = item.imageLink else { return }
                        imagePreviewStore.present(
                            imageURL: imageLink,
                            title: item.title,
                            subtitle: item.sourceName
                        )
                    } label: {
                        TodayHumorArtwork(imageLink: item.imageLink, height: 220)
                            .overlay(alignment: .bottomTrailing) {
                                if item.imageLink != nil {
                                    Label("Powiększ", systemImage: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(.black.opacity(0.56), in: Capsule())
                                        .padding(12)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(item.imageLink == nil)
                    .accessibilityLabel(item.imageLink == nil ? "Brak obrazu posta Reddit" : "Powiększ obraz posta Reddit")

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            StatusBadge(text: item.sourceName, systemImage: "link", tint: .purple)
                            if let categoryLabel = item.categoryLabel, !categoryLabel.isEmpty {
                                StatusBadge(text: categoryLabel, systemImage: "tag.fill", tint: .blue)
                            }
                        }

                        Text(item.title)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(item.caption)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 14) {
                            if let scoreLabel = item.scoreLabel {
                                Label(scoreLabel, systemImage: "arrow.up")
                            }
                            if let comments = item.comments {
                                Label("\(comments)", systemImage: "bubble.left.and.bubble.right.fill")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }

                    if let postText = item.postText, !postText.isEmpty {
                        TodayHumorDetailSection(title: "Post", systemImage: "text.alignleft", text: postText)
                    }

                    if let whyFunny = item.whyFunny, !whyFunny.isEmpty {
                        TodayHumorDetailSection(title: "Dlaczego działa", systemImage: "sparkles", text: whyFunny)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Analiza komentarzy", systemImage: "quote.bubble.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.purple)

                        if let highlights = item.commentHighlights, !highlights.isEmpty {
                            ForEach(highlights) { highlight in
                                TodayHumorCommentHighlightCard(highlight: highlight)
                            }
                        } else {
                            Text("Automatyzacja nie znalazła jeszcze trzech bezpiecznych komentarzy do pokazania dla tego posta.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(15)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    if let sourceLink = item.sourceLink {
                        Link(destination: sourceLink) {
                            Label("Otwórz na Reddicie", systemImage: "safari")
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("<RR> Reddit Radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        let wasSaved = isSaved
                        savedStore.toggle(
                            item,
                            digestID: digestID,
                            digestTitle: digestTitle,
                            displayTime: displayTime
                        )
                        haptics.play(wasSaved ? .lightImpact : .success)
                    } label: {
                        Label(
                            isSaved ? "Usuń z zapisanych" : "Zapisz Reddit",
                            systemImage: isSaved ? "bookmark.fill" : "bookmark"
                        )
                    }
                    .accessibilityLabel(isSaved ? "Usuń z zapisanych Redditów" : "Zapisz Reddit")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Gotowe") {
                        dismiss()
                    }
                }
            }
        }
        .overlay {
            PavbotImagePreviewHost(imagePreviewStore: imagePreviewStore)
        }
    }
}

private struct TodayHumorSavedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PavbotHaptics.self) private var haptics
    let savedStore: TodayHumorSavedStore
    @State private var query = ""

    private var savedItems: [SavedTodayHumorItem] {
        savedStore.filteredItems(query: query)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zapisane Reddit Radar")
                            .font(.title2.weight(.bold))
                        Text("Posty zapisują się lokalnie na tym urządzeniu, razem z opisem i analizą komentarzy z chwili publikacji radaru.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if savedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Brak zapisanych Redditów", systemImage: "bookmark")
                                .font(.headline.weight(.semibold))
                            Text(query.isEmpty ? "Otwórz post w Śmiechowym radarze i użyj ikony zakładki." : "Nie znaleziono zapisanego posta dla wpisanego tekstu.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(savedItems) { saved in
                                NavigationLink {
                                    TodayHumorDetailSheet(
                                        item: saved.item,
                                        digestID: saved.digestID,
                                        digestTitle: saved.digestTitle,
                                        displayTime: saved.displayTime,
                                        savedStore: savedStore
                                    )
                                } label: {
                                    TodayHumorSavedRow(saved: saved)
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    haptics.play(.lightImpact)
                                })
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        savedStore.remove(saved)
                                        haptics.play(.lightImpact)
                                    } label: {
                                        Label("Usuń z zapisanych", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Zapisane")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Szukaj w zapisanych Redditach")
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

private struct TodayHumorSavedRow: View {
    let saved: SavedTodayHumorItem

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                StatusBadge(text: saved.item.sourceName, systemImage: "bookmark.fill", tint: .purple)
                Spacer()
                Text(saved.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(saved.item.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(saved.item.caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if !saved.displayTime.isEmpty {
                    Label(saved.displayTime, systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let scoreLabel = saved.item.scoreLabel {
                    Label(scoreLabel, systemImage: "arrow.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !saved.item.tags.isEmpty {
                PavbotArticleKeywordRows(horizontalSpacing: 7, verticalSpacing: 6) {
                    ForEach(saved.item.tags.prefix(3), id: \.self) { tag in
                        PavbotArticleTagChip(
                            title: tag,
                            systemImage: "tag.fill",
                            tint: .purple,
                            accessibilityPrefix: "Tag zapisanego Reddita"
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TodayHumorDetailSection: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.purple)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TodayHumorCommentHighlightCard: View {
    let highlight: TodayHumorCommentHighlight
    @State private var isShowingOriginal = false

    var body: some View {
        Group {
            if canToggleOriginal {
                Button {
                    isShowingOriginal.toggle()
                } label: {
                    cardContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(isShowingOriginal ? "Stuknij, aby wrócić do analizy." : "Stuknij, aby zobaczyć oryginalny komentarz.")
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isShowingOriginal, let originalBody {
                originalContent(originalBody)
            } else {
                analysisContent
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isShowingOriginal {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.purple.opacity(0.28), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var analysisContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerLabel("Czego dotyczy", systemImage: "text.bubble.fill")

            Text(highlight.summary)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Label("Dlaczego ciekawe/śmieszne", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)

            Text(highlight.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if canToggleOriginal {
                Text("Stuknij, aby zobaczyć oryginalny komentarz")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func originalContent(_ originalBody: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            headerLabel("Oryginalny komentarz", systemImage: "quote.opening")

            Text("\"\(originalBody)\"")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("Stuknij, aby wrócić do analizy")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func headerLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
            Spacer()
            if let score = highlight.score, score > 0 {
                Label("\(score)", systemImage: "arrow.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var originalBody: String? {
        guard let originalBody = highlight.originalBody?.trimmingCharacters(in: .whitespacesAndNewlines),
              !originalBody.isEmpty else {
            return nil
        }
        return originalBody
    }

    private var canToggleOriginal: Bool {
        originalBody != nil
    }

    private var cardBackground: Color {
        isShowingOriginal ? Color.purple.opacity(0.10) : Color(.secondarySystemGroupedBackground)
    }

    private var accessibilityLabel: String {
        if isShowingOriginal, let originalBody {
            return "Oryginalny komentarz. \(originalBody)"
        }
        return "Analiza komentarza. \(highlight.summary). \(highlight.explanation)"
    }
}

private struct WeatherInlineFact: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
