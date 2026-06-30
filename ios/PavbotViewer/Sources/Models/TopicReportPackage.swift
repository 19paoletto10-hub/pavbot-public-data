import Foundation
import SwiftUI

enum ReportTopicKind: String, CaseIterable, Codable, Identifiable, Equatable, Hashable {
    case jobs
    case techNews
    case polskaSwiat
    case aktualne

    var id: String { rawValue }

    init?(topic: String) {
        guard let value = Self.allCases.first(where: { $0.topic == topic }) else {
            return nil
        }
        self = value
    }

    var topic: String {
        switch self {
        case .jobs:
            "llm-ai-jobs-wroclaw"
        case .techNews:
            "tech-news"
        case .polskaSwiat:
            "polska-swiat"
        case .aktualne:
            "aktualne-wydarzenia-mobile"
        }
    }

    var title: String {
        switch self {
        case .jobs:
            "LLM / AI Jobs Wrocław"
        case .techNews:
            "Tech News"
        case .polskaSwiat:
            "Polska i Świat"
        case .aktualne:
            "Aktualne"
        }
    }

    var subtitle: String {
        switch self {
        case .jobs:
            "Oferty, sygnały rynku i raporty PDF"
        case .techNews:
            "Technologia, AI i najważniejsze zmiany"
        case .polskaSwiat:
            "Wydarzenia krajowe i zagraniczne"
        case .aktualne:
            "Mobilny magazyn dnia z TTS"
        }
    }

    var systemImage: String {
        switch self {
        case .jobs:
            "briefcase.fill"
        case .techNews:
            "cpu.fill"
        case .polskaSwiat:
            "globe.europe.africa.fill"
        case .aktualne:
            "newspaper.fill"
        }
    }

    var tint: Color {
        switch self {
        case .jobs:
            .indigo
        case .techNews:
            .blue
        case .polskaSwiat:
            .green
        case .aktualne:
            .orange
        }
    }
}

struct TopicReportPackage: Identifiable, Equatable, Hashable {
    let topic: ReportTopicKind
    let key: String
    let artifacts: [PavbotArtifact]

    var id: String { "\(topic.topic)-\(key)" }

    var date: String? {
        artifacts.first?.date
    }

    var time: String? {
        artifacts.first?.time
    }

    var displayDate: String {
        [date, time]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var researchReport: PavbotArtifact? {
        artifacts.first { $0.type == .run }
    }

    var pdfReport: PavbotArtifact? {
        artifacts.first { $0.type == .pdf }
    }

    var dataArtifact: PavbotArtifact? {
        artifacts.first { $0.type == .jobsData }
    }

    var researchDataArtifact: PavbotArtifact? {
        let candidates = artifacts
            .filter { $0.type == .researchData }
            .filter { !Self.isFinderStyleDuplicate($0.path) }
        return candidates.first { Self.isCanonicalResearchDataPath($0.path) } ?? candidates.first
    }

    var mobileNewsDataArtifact: PavbotArtifact? {
        artifacts.first { $0.type == .mobileNewsData }
    }

    var podcastBriefPDF: PavbotArtifact? {
        artifacts.first { $0.type == .podcastBriefPdf }
    }

    var primaryAudio: PavbotArtifact? {
        artifacts.first { $0.type == .podcastAudio } ?? artifacts.first { $0.type == .podcastAudioVariant }
    }

    var podcastScript: PavbotArtifact? {
        artifacts.first { $0.type == .podcastScript }
    }

    var additionalArtifacts: [PavbotArtifact] {
        let primaryIDs = [
            researchReport?.id,
            pdfReport?.id,
            dataArtifact?.id,
            researchDataArtifact?.id,
            mobileNewsDataArtifact?.id,
            podcastBriefPDF?.id,
            primaryAudio?.id,
            podcastScript?.id
        ].compactMap { $0 }
        let primaryIDSet = Set(primaryIDs)
        return artifacts.filter { !primaryIDSet.contains($0.id) }
    }

    var hasPDF: Bool {
        pdfReport != nil || podcastBriefPDF != nil
    }

    var preferredPreviewArtifact: PavbotArtifact? {
        dataArtifact ?? researchDataArtifact ?? mobileNewsDataArtifact ?? pdfReport ?? researchReport ?? podcastBriefPDF ?? primaryAudio ?? artifacts.first
    }

    func filteringArtifacts(to artifactIDs: Set<String>) -> TopicReportPackage? {
        guard !artifactIDs.isEmpty else {
            return self
        }
        let filteredArtifacts = artifacts.filter { artifactIDs.contains($0.id) }
        guard !filteredArtifacts.isEmpty else {
            return nil
        }
        return TopicReportPackage(topic: topic, key: key, artifacts: filteredArtifacts)
    }

    static func packages(
        for topic: ReportTopicKind,
        in manifest: PavbotManifest
    ) -> [TopicReportPackage] {
        let artifacts = manifest.artifacts
            .filter { $0.topic == topic.topic }
            .filter { $0.date != nil }

        let grouped = Dictionary(grouping: artifacts) { artifact in
            packageKey(for: artifact)
        }

        return grouped.map { key, artifacts in
            TopicReportPackage(
                topic: topic,
                key: key,
                artifacts: artifacts.sorted(by: PavbotArtifact.automationDisplaySort)
            )
        }
        .sorted { lhs, rhs in
            lhs.key > rhs.key
        }
    }

    private static func packageKey(for artifact: PavbotArtifact) -> String {
        let date = artifact.date ?? "no-date"
        if let time = artifact.time, !time.isEmpty {
            return "\(date)-\(time)"
        }

        let filename = URL(fileURLWithPath: artifact.path).deletingPathExtension().lastPathComponent
        if filename.count >= 15 {
            let prefix = String(filename.prefix(15))
            if prefix.range(of: #"^\d{4}-\d{2}-\d{2}-\d{4}$"#, options: .regularExpression) != nil {
                return prefix
            }
        }

        return date
    }

    private static func isCanonicalResearchDataPath(_ path: String) -> Bool {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return filename.range(
            of: #"^\d{4}-\d{2}-\d{2}(?:-\d{4})?-research\.json$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isFinderStyleDuplicate(_ path: String) -> Bool {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return stem.range(of: #" \d+$"#, options: .regularExpression) != nil
    }
}

extension PavbotManifest {
    func reportPackages(for topic: ReportTopicKind) -> [TopicReportPackage] {
        TopicReportPackage.packages(for: topic, in: self)
    }
}
