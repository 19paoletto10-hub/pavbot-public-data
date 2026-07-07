import SwiftUI

struct TemperatureTimelinePoint: Identifiable {
    let id: String
    let date: Date
    let temperature: Double

    var temperatureLabel: String {
        if temperature.rounded() == temperature {
            return "\(Int(temperature))°"
        }
        return String(format: "%.1f°", temperature)
    }
}

struct TemperatureTimelineChartBar: Identifiable, Equatable {
    let id: String
    let date: Date
    let temperature: Double
    let yStart: Double
    let yEnd: Double

    var temperatureLabel: String {
        if temperature.rounded() == temperature {
            return "\(Int(temperature))°"
        }
        return String(format: "%.1f°", temperature)
    }
}

struct TemperatureTimelineChartModel: Equatable {
    let bars: [TemperatureTimelineChartBar]
    let baseline: Double
    let domain: ClosedRange<Double>
    let visibleLabelIDs: Set<String>

    init(report: DailyWeatherReport, maxVisibleLabels: Int = 5) {
        self.init(points: WeatherTimelineChartData.points(for: report), maxVisibleLabels: maxVisibleLabels)
    }

    init(points: [TemperatureTimelinePoint], maxVisibleLabels: Int = 5) {
        guard let min = points.map(\.temperature).min(), let max = points.map(\.temperature).max() else {
            bars = []
            baseline = 0
            domain = 0...1
            visibleLabelIDs = []
            return
        }

        let spread = Swift.max(max - min, 0.8)
        let lowerPadding = Swift.max(0.8, spread * 0.22)
        let upperPadding = Swift.max(0.8, spread * 0.28)
        let baselineValue = min - lowerPadding
        let visibleIDs = Self.visibleLabelIDs(for: points, maxCount: maxVisibleLabels)
        let nextBars = points.map { point in
            TemperatureTimelineChartBar(
                id: point.id,
                date: point.date,
                temperature: point.temperature,
                yStart: baselineValue,
                yEnd: point.temperature
            )
        }
        baseline = baselineValue
        domain = baselineValue...(max + upperPadding)
        visibleLabelIDs = visibleIDs
        bars = nextBars
    }

    private static func visibleLabelIDs(for points: [TemperatureTimelinePoint], maxCount: Int) -> Set<String> {
        guard maxCount > 0, points.count > maxCount else {
            return Set(points.map(\.id))
        }

        let stride = Double(points.count - 1) / Double(maxCount - 1)
        let indexes = (0..<maxCount).map { Int((Double($0) * stride).rounded()) }
        return Set(indexes.compactMap { index in
            points.indices.contains(index) ? points[index].id : nil
        })
    }
}

enum WeatherTimelineChartData {
    static func points(for report: DailyWeatherReport) -> [TemperatureTimelinePoint] {
        report.timelineTemperaturePoints().compactMap { item -> TemperatureTimelinePoint? in
            guard let date = item.dateValue else { return nil }
            return TemperatureTimelinePoint(id: item.id, date: date, temperature: item.temperature)
        }
    }

    static func temperatureColor(for value: Double) -> Color {
        switch value {
        case ..<8:
            return .blue
        case 8..<18:
            return .cyan
        case 18..<26:
            return .orange
        default:
            return .red
        }
    }
}
