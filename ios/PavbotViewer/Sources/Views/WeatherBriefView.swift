import Charts
import SwiftUI

struct WeatherBriefView: View {
    @Environment(WeatherBriefStore.self) private var weatherStore
    @Environment(TodayHumorStore.self) private var humorStore
    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var rangeTileMode: WeatherRangeTileMode = .value
    @State private var isRefreshingWeather = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch weatherStore.state {
                case .loading where weatherStore.report == nil:
                    loadingView
                case .failed(let error) where weatherStore.report == nil:
                    missingConfigurationView(error: error)
                default:
                    if let report = weatherStore.report {
                        reportView(report)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dzisiaj")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshCurrentWeather() }
                } label: {
                    if isRefreshingWeather || weatherStore.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingWeather || weatherStore.isRefreshing)
                .accessibilityLabel("Odśwież pogodę")
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
    }

    private func refreshCurrentWeather() async {
        guard !isRefreshingWeather else { return }
        isRefreshingWeather = true
        defer { isRefreshingWeather = false }

        await loadTodayContent()
    }

    private func loadTodayContent(minimumInterval: TimeInterval = 0) async {
        async let weatherLoad: Void = weatherStore.load(minimumInterval: minimumInterval)
        async let humorLoad: Void = humorStore.load(minimumInterval: minimumInterval)
        _ = await (weatherLoad, humorLoad)
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
    private func reportView(_ report: DailyWeatherReport) -> some View {
        if usesWideLayout {
            wideReportView(report)
        } else {
            compactReportView(report)
        }
    }

    private func compactReportView(_ report: DailyWeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            WeatherHeroCard(report: report)

            if let cacheNotice = weatherStore.cacheNotice {
                PavbotCacheNoticeBanner(text: cacheNotice)
            }

            if let locationNotice = weatherStore.locationNotice {
                PavbotCacheNoticeBanner(text: locationNotice)
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
                WeatherMetricTile(
                    title: "Opady",
                    value: report.precipitation.probabilityLabel,
                    caption: report.precipitation.totalLabel,
                    systemImage: "cloud.rain",
                    tint: .blue
                )
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
                isRefreshing: humorStore.isRefreshing
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

    private func wideReportView(_ report: DailyWeatherReport) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                WeatherHeroCard(report: report)
                    .frame(maxWidth: .infinity, minHeight: 280)

                TemperatureTimelineChartTile(report: report)
                    .frame(maxWidth: .infinity, minHeight: 280)
            }

            if let cacheNotice = weatherStore.cacheNotice {
                PavbotCacheNoticeBanner(text: cacheNotice)
            }

            if let locationNotice = weatherStore.locationNotice {
                PavbotCacheNoticeBanner(text: locationNotice)
            }

            HStack(alignment: .top, spacing: 18) {
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
                    WeatherMetricTile(
                        title: "Opady",
                        value: report.precipitation.probabilityLabel,
                        caption: report.precipitation.totalLabel,
                        systemImage: "cloud.rain",
                        tint: .blue
                    )
                    WeatherMetricTile(
                        title: "Wiatr",
                        value: report.wind.speedLabel,
                        systemImage: "wind",
                        tint: .cyan
                    )
                }
                .frame(maxWidth: 430)
            }

            TodayHumorPanel(
                digest: humorStore.digest,
                state: humorStore.state,
                cacheNotice: humorStore.cacheNotice,
                isRefreshing: humorStore.isRefreshing
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

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular || ProcessInfo.processInfo.isiOSAppOnMac
    }

}

private struct WeatherRangeTimelineTile: View {
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
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
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
                            Text(bar.temperatureLabel)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(.thinMaterial, in: Capsule())
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
                            Text(bar.temperatureLabel)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
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

private struct WeatherMetricTile: View {
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
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
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

            Text(report.recommendation)
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
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Śmiechowy radar", systemImage: "sparkles.tv.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Button(action: reload) {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .accessibilityLabel("Odśwież radar memów")
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
                Text(digest.summary)
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ostatnio: \(digest.displayTime) · następne: \(digest.nextRefreshLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(digest.items.prefix(6)) { item in
                        TodayHumorCard(item: item)
                            .frame(width: 250)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct TodayHumorCard: View {
    let item: TodayHumorItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageLink = item.imageLink {
                AsyncImage(url: imageLink) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        humorPlaceholder
                    case .empty:
                        ZStack {
                            humorPlaceholder
                            ProgressView()
                        }
                    @unknown default:
                        humorPlaceholder
                    }
                }
                .frame(height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                humorPlaceholder
                    .frame(height: 96)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
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

            if let sourceLink = item.sourceLink {
                Link(destination: sourceLink) {
                    Label("Źródło", systemImage: "safari")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 286, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.caption). Źródło: \(item.sourceName)")
    }

    private var humorPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.20), Color.blue.opacity(0.12), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "face.smiling.inverse")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.purple)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
