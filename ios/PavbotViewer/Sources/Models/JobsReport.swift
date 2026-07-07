import Foundation

struct JobsReport: Codable, Equatable, Identifiable {
    var id: String { "jobs-\(runDate)-\(runTime)" }

    let schemaVersion: Int
    let status: String
    let runDate: String
    let runTime: String
    let executiveSummary: String
    let opportunities: [JobOpportunity]
    let changes: [String]
    let risks: [String]
    let recommendedActions: [String]
    let checkedSources: [JobsCheckedSource]

    var displayRunDate: String {
        guard let dateValue = DateFormatter.pavbotDay.date(from: runDate) else {
            return runDate
        }
        return DateFormatter.polishLongDate.string(from: dateValue)
    }

    var displayRunDateTime: String {
        "\(displayRunDate), \(runTime)"
    }
}

struct JobOpportunity: Codable, Equatable, Hashable, Identifiable {
    var id: String {
        "\(rank)-\(company)-\(title)-\(sourceURLs.first ?? "")"
    }

    let rank: Int
    let title: String
    let company: String
    let location: String
    let workMode: String
    let compensation: String
    let seniority: String
    let fitSummary: String
    let whyInteresting: String
    let uncertainty: String
    let sourceURLs: [String]
    let tags: [String]

    var normalizedSearchText: String {
        [
            title,
            company,
            location,
            workMode,
            compensation,
            seniority,
            fitSummary,
            whyInteresting,
            uncertainty
        ]
        .joined(separator: " ")
    }
}

struct JobsCheckedSource: Codable, Equatable, Hashable, Identifiable {
    var id: String { url }

    let title: String
    let url: String
    let status: String?
}

enum JobsReportSource: String, Codable, Equatable, Hashable {
    case jobsData
    case markdownFallback

    var label: String {
        switch self {
        case .jobsData:
            "Dane strukturalne"
        case .markdownFallback:
            "Fallback z Markdown"
        }
    }
}
