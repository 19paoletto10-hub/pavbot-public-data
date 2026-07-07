import Foundation
import SwiftUI

enum ResearchIssueKeywordKind: String, Hashable {
    case technology
    case source
    case region
    case section
    case format
}

struct ResearchIssueKeyword: Hashable, Identifiable {
    let title: String
    let kind: ResearchIssueKeywordKind

    var id: String { "\(kind.rawValue)-\(title)" }

    var systemImage: String {
        switch kind {
        case .technology:
            "sparkles"
        case .source:
            "link.circle.fill"
        case .region:
            "globe.europe.africa.fill"
        case .section:
            "tag.fill"
        case .format:
            "doc.richtext.fill"
        }
    }
}

struct ResearchIssueSignal: Hashable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let section: ResearchNewsSection
    let bullets: [String]

    var systemImage: String { section.systemImage }
}

struct ResearchArticlePresentation: Hashable, Identifiable {
    let id: String
    let title: String
    let standfirst: String
    let summary: String
    let section: ResearchNewsSection
    let keywords: [ResearchIssueKeyword]
    let bullets: [String]
    let paragraphs: [String]
    let deeperAnalysis: [String]
    let contextPoints: [String]
    let sourceCount: Int
    let primarySourceTitle: String?

    init(article: ResearchNewsArticle, topic: ReportTopicKind) {
        id = article.id
        section = article.section
        sourceCount = article.sources.count
        primarySourceTitle = article.sources.first?.title
        keywords = ResearchKeywordCatalog.keywords(
            topic: topic,
            lead: article.body,
            articles: [article],
            checkedSources: article.sources,
            hasPDF: false,
            hasAudio: false
        )
        title = Self.moderatedTitle(for: article, topic: topic)
        let bodyParagraphs = Self.editorialParagraphs(from: article.body)
        let structuredContextPoints = Self.cleanList(article.contextPoints)
        contextPoints = structuredContextPoints
        standfirst = Self.standfirst(from: bodyParagraphs, fallback: article.summary)
        let duplicateReferences: [String?] = [
            standfirst,
            article.whatHappened,
            structuredContextPoints.first
        ]
        let structuredDeeperAnalysis = Self.filteredAnalysis(Self.cleanList(article.deeperAnalysis), references: duplicateReferences)
        let filteredBodyParagraphs = Self.filteredAnalysis(bodyParagraphs, references: duplicateReferences)
        deeperAnalysis = structuredDeeperAnalysis
        paragraphs = structuredDeeperAnalysis.isEmpty ? filteredBodyParagraphs : structuredDeeperAnalysis
        summary = Self.moderatedSummary(for: article, topic: topic, standfirst: standfirst)
        bullets = structuredContextPoints.isEmpty
            ? Self.keyPoints(for: article, topic: topic, standfirst: standfirst)
            : structuredContextPoints
    }

    private static func moderatedTitle(for article: ResearchNewsArticle, topic: ReportTopicKind) -> String {
        let entities = keyEntities(in: article, topic: topic)
        let entityLabel = entities.isEmpty ? conciseTitleSeed(from: article) : entities.prefix(2).joined(separator: " i ")
        return "\(article.section.editorialPrefix(topic: topic)): \(entityLabel)"
    }

    private static func moderatedSummary(for article: ResearchNewsArticle, topic: ReportTopicKind, standfirst: String) -> String {
        let what = cleanOptional(article.whatHappened) ?? standfirst
        let why = cleanOptional(article.whyItMatters) ?? article.section.editorialImportance(topic: topic)
        if what.isEmpty {
            return "Dlaczego to ważne: \(why)."
        }
        return "\(what)\n\nDlaczego to ważne: \(why)"
    }

    private static func keyEntities(in article: ResearchNewsArticle, topic: ReportTopicKind) -> [String] {
        let corpus = [
            article.title,
            article.body,
            article.summary,
            article.tags.joined(separator: " "),
            article.sources.map(\.title).joined(separator: " ")
        ].joined(separator: " ")
        let candidates: [String] = switch topic {
        case .techNews:
            ["OpenAI", "Cloudflare", "NVIDIA", "Broadcom", "Anthropic", "Apple", "Microsoft", "Google", "Meta"]
        case .polskaSwiat:
            ["NATO", "MON", "KPRM", "UE", "Ukraina", "USA", "Polska", "Rząd", "Sejm", "IMGW", "RCB"]
        case .jobs, .aktualne:
            []
        }
        return candidates.filter { corpus.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private static func conciseTitleSeed(from article: ResearchNewsArticle) -> String {
        compactWords(cleanSourceNoise(article.title), maxWords: 8)
    }

    private static func standfirst(from paragraphs: [String], fallback: String) -> String {
        let fallbackCandidate = cleanSourceNoise(fallback)
        let candidate = fallbackCandidate.isEmpty ? (paragraphs.first ?? "") : fallbackCandidate
        let sentences = sentences(from: candidate)
        if sentences.count >= 2 {
            return sentences.prefix(2).joined(separator: " ")
        }
        return candidate
    }

    private static func cleanSourceNoise(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(
            of: #"\b(Źródła?|Source|Sources):\s*.*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func editorialParagraphs(from value: String) -> [String] {
        let blocks = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map(cleanSourceNoise)
            .filter { !$0.isEmpty }
        if !blocks.isEmpty {
            return blocks
        }
        let cleaned = cleanSourceNoise(value)
        return cleaned.isEmpty ? [] : [cleaned]
    }

    private static func keyPoints(for article: ResearchNewsArticle, topic: ReportTopicKind, standfirst: String) -> [String] {
        var points: [String] = []
        if let whatHappened = cleanOptional(article.whatHappened) ?? (standfirst.isEmpty ? nil : standfirst) {
            points.append("Co się stało: \(whatHappened)")
        }
        points.append("Dlaczego to ważne: \(cleanOptional(article.whyItMatters) ?? article.section.editorialImportance(topic: topic)).")
        if !article.sources.isEmpty {
            let sourceLabel = article.sources.prefix(2).map(\.title).joined(separator: ", ")
            points.append("Źródła: \(sourceLabel)")
        }
        return points
    }

    private static func cleanOptional(_ value: String?) -> String? {
        let trimmed = value?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func cleanList(_ values: [String]?) -> [String] {
        guard let values else { return [] }
        return values.compactMap(cleanOptional)
    }

    private static func filteredAnalysis(_ values: [String], references: [String?]) -> [String] {
        let duplicateKeys = Set(references.compactMap(duplicateKey))
        let filtered = values.filter { value in
            guard let key = duplicateKey(value) else { return false }
            return !duplicateKeys.contains(key)
        }
        return filtered.isEmpty && values.count == 1 ? values : filtered
    }

    private static func duplicateKey(_ value: String?) -> String? {
        guard let value = cleanOptional(stripContextLabel(value)) else { return nil }
        let normalized = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func stripContextLabel(_ value: String?) -> String? {
        value?.replacingOccurrences(
            of: #"^\s*Co\s+si[eę]\s+sta[lł]o\s*:\s*"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func sentences(from value: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for index in value.indices {
            let character = value[index]
            current.append(character)
            let nextIndex = value.index(after: index)
            let isBoundary = nextIndex == value.endIndex || value[nextIndex].isWhitespace
            if ".!?".contains(character), isBoundary {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            sentences.append(tail)
        }
        return sentences
    }

    private static func compactWords(_ value: String, maxWords: Int) -> String {
        let words = value
            .split(separator: " ")
            .prefix(maxWords)
            .map(String.init)
        let compacted = words.joined(separator: " ")
        return compacted.isEmpty ? "Najważniejszy wątek" : compacted
    }
}

struct ResearchIssuePresentation: Hashable {
    let eyebrow: String
    let title: String
    let lead: String
    let leadParagraphs: [String]
    let quickPoints: [String]
    let signalsTitle: String
    let keywordsTitle: String
    let signals: [ResearchIssueSignal]
    let keywords: [ResearchIssueKeyword]

    init(issue: ResearchNewsIssue) {
        eyebrow = issue.topic.researchEyebrow
        title = issue.topic.researchHeroTitle
        signalsTitle = issue.topic.researchSignalsTitle
        keywordsTitle = "Słowa kluczowe"
        let moderatedSignals = Self.signals(from: issue)
        lead = Self.curatedLead(from: issue, signals: moderatedSignals)
        leadParagraphs = Self.leadParagraphs(from: lead)
        quickPoints = Self.quickPoints(from: issue, signals: moderatedSignals)
        signals = moderatedSignals
        keywords = ResearchKeywordCatalog.keywords(
            topic: issue.topic,
            lead: issue.lead,
            articles: issue.articles,
            checkedSources: issue.checkedSources,
            hasPDF: issue.hasPDF,
            hasAudio: issue.audioArtifact != nil
        )
    }

    private static func curatedLead(from issue: ResearchNewsIssue, signals: [ResearchIssueSignal]) -> String {
        guard !issue.articles.isEmpty else {
            return normalizedLead(issue.lead)
        }
        guard !signals.isEmpty else {
            return normalizedLead(issue.lead)
        }

        let topSignals = signals
            .prefix(3)
            .map(\.title)
            .joined(separator: "; ")
        let rawLead = normalizedLead(issue.lead)

        let lead: String = switch issue.topic {
        case .techNews:
            "Dzisiejszy przegląd technologiczny porządkuje najważniejsze ruchy w AI, produktach i infrastrukturze.\n\nNajmocniejszy wniosek: \(topSignals).\n\n\(rawLead)"
        case .polskaSwiat:
            "Dzisiejszy przegląd Polski i świata zbiera najważniejsze sygnały dla decyzji, bezpieczeństwa i gospodarki.\n\nNajmocniejszy wniosek: \(topSignals).\n\n\(rawLead)"
        case .jobs, .aktualne:
            rawLead
        }

        return normalizedLead(lead)
    }

    private static func normalizedLead(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Wydanie jest gotowe do przeglądu w aplikacji Pavbot."
        }
        return trimmed
    }

    private static func leadParagraphs(from lead: String) -> [String] {
        let paragraphs = lead
            .components(separatedBy: "\n\n")
            .map { normalizedLead($0) }
            .filter { !$0.isEmpty }
        return paragraphs.isEmpty ? [normalizedLead(lead)] : Array(paragraphs.prefix(4))
    }

    private static func quickPoints(from issue: ResearchNewsIssue, signals: [ResearchIssueSignal]) -> [String] {
        let sourcePoint = issue.sourceCount > 0 ? "Sprawdzono \(issue.sourceCount) źródeł i wybrano sygnały, które mają największe znaczenie dla tematu." : ""
        let signalPoints = signals.prefix(2).map { "\($0.section.rawValue): \($0.title)" }
        let outputPoint = issue.hasPDF ? "Pełny raport i PDF są dostępne jako dodatki do wydania." : "Raport źródłowy jest dostępny, PDF nie został jeszcze opublikowany."
        return ([sourcePoint] + signalPoints + [outputPoint]).filter { !$0.isEmpty }.prefix(3).map { $0 }
    }

    private static func signals(from issue: ResearchNewsIssue) -> [ResearchIssueSignal] {
        let articleSignals = issue.articles.prefix(3).map { article in
            let presentation = ResearchArticlePresentation(article: article, topic: issue.topic)
            return ResearchIssueSignal(
                id: article.id,
                title: presentation.title,
                summary: presentation.summary,
                section: article.section,
                bullets: Array(presentation.bullets.prefix(2))
            )
        }
        if !articleSignals.isEmpty {
            return articleSignals
        }

        return [
            ResearchIssueSignal(
                id: "\(issue.id)-fallback",
                title: issue.topic.researchFallbackSignalTitle,
                summary: normalizedLead(issue.lead),
                section: issue.topic == .polskaSwiat ? .polska : .ai,
                bullets: []
            )
        ]
    }
}

enum ResearchKeywordCatalog {
    private struct Entry {
        let title: String
        let kind: ResearchIssueKeywordKind
        let variants: [String]
    }

    static func keywords(
        topic: ReportTopicKind,
        lead: String,
        articles: [ResearchNewsArticle],
        checkedSources: [ResearchNewsSource],
        hasPDF: Bool,
        hasAudio: Bool
    ) -> [ResearchIssueKeyword] {
        let corpus = corpus(lead: lead, articles: articles, checkedSources: checkedSources)
        var result: [ResearchIssueKeyword] = entries(for: topic).compactMap { entry in
            containsAny(entry.variants, in: corpus) ? ResearchIssueKeyword(title: entry.title, kind: entry.kind) : nil
        }

        for section in articles.map(\.section) where section != .inne {
            result.append(ResearchIssueKeyword(title: section.rawValue, kind: .section))
        }

        if hasPDF {
            result.append(ResearchIssueKeyword(title: "PDF", kind: .format))
        }
        if hasAudio {
            result.append(ResearchIssueKeyword(title: "Audio", kind: .format))
        }

        if result.isEmpty {
            result = topic.defaultResearchKeywords
        }

        return deduplicated(result).prefix(10).map { $0 }
    }

    static func variants(for keyword: String) -> [String] {
        let canonical = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { return [] }
        let normalized = canonical.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        if let entry = allEntries.first(where: {
            $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased() == normalized
        }) {
            return entry.variants
        }
        return [canonical]
    }

    private static func entries(for topic: ReportTopicKind) -> [Entry] {
        switch topic {
        case .techNews:
            [
                Entry(title: "OpenAI", kind: .technology, variants: ["OpenAI"]),
                Entry(title: "Cloudflare", kind: .technology, variants: ["Cloudflare"]),
                Entry(title: "NVIDIA", kind: .technology, variants: ["NVIDIA"]),
                Entry(title: "AI", kind: .technology, variants: ["AI"]),
                Entry(title: "LLM", kind: .technology, variants: ["LLM", "dużych modeli"]),
                Entry(title: "RAG", kind: .technology, variants: ["RAG"]),
                Entry(title: "Cyber", kind: .section, variants: ["cyber", "security", "bezpieczeństwo cyfrowe"]),
                Entry(title: "Regulacje", kind: .section, variants: ["regulacje", "regulacji", "ustawa", "compliance"]),
                Entry(title: "Infrastruktura", kind: .section, variants: ["infrastruktura", "infrastruktury", "compute", "inference", "GPU", "chip"])
            ]
        case .polskaSwiat:
            [
                Entry(title: "Polska", kind: .region, variants: ["Polska", "polski", "polskie", "rząd"]),
                Entry(title: "UE", kind: .region, variants: ["UE", "Unia Europejska", "Bruksela"]),
                Entry(title: "NATO", kind: .region, variants: ["NATO"]),
                Entry(title: "Ukraina", kind: .region, variants: ["Ukraina", "ukraiń"]),
                Entry(title: "Bezpieczeństwo", kind: .section, variants: ["bezpieczeństwo", "bezpieczeństwa", "obrona", "MON", "wojsk"]),
                Entry(title: "Gospodarka", kind: .section, variants: ["gospodarka", "gospodarki", "gospodarkę", "energia", "firm"]),
                Entry(title: "Polityka", kind: .section, variants: ["polityka", "polityki", "Sejm", "prezydent", "premier"]),
                Entry(title: "Pogoda", kind: .section, variants: ["pogoda", "pogody", "IMGW", "burze", "upał"])
            ]
        case .jobs, .aktualne:
            []
        }
    }

    private static var allEntries: [Entry] {
        entries(for: .techNews) + entries(for: .polskaSwiat)
    }

    private static func corpus(
        lead: String,
        articles: [ResearchNewsArticle],
        checkedSources: [ResearchNewsSource]
    ) -> String {
        var values: [String] = [lead]
        for article in articles {
            values.append(article.title)
            values.append(article.body)
            values.append(article.summary)
            values.append(article.whatHappened ?? "")
            values.append(article.whyItMatters ?? "")
            values.append((article.deeperAnalysis ?? []).joined(separator: " "))
            values.append((article.contextPoints ?? []).joined(separator: " "))
            values.append(article.tags.joined(separator: " "))
            values.append(article.sources.map(\.title).joined(separator: " "))
        }
        values.append(contentsOf: checkedSources.map(\.title))
        return values.joined(separator: " ")
    }

    private static func containsAny(_ terms: [String], in corpus: String) -> Bool {
        terms.contains { term in
            corpus.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private static func deduplicated(_ keywords: [ResearchIssueKeyword]) -> [ResearchIssueKeyword] {
        var seen: Set<String> = []
        return keywords.compactMap { keyword in
            let title = keyword.title
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
            guard seen.insert(key).inserted else { return nil }
            return ResearchIssueKeyword(title: title, kind: keyword.kind)
        }
    }
}

private extension ResearchNewsSection {
    func editorialPrefix(topic: ReportTopicKind) -> String {
        switch topic {
        case .techNews:
            switch self {
            case .ai:
                return "AI i modele"
            case .infrastruktura:
                return "Infrastruktura AI"
            case .produkty:
                return "Produktowy sygnał AI"
            case .regulacje:
                return "Regulacje technologiczne"
            case .cyber:
                return "Cyberbezpieczeństwo"
            default:
                return "Sygnał technologiczny"
            }
        case .polskaSwiat:
            switch self {
            case .polska:
                return "Polska"
            case .polityka:
                return "Polityka"
            case .swiat:
                return "Świat"
            case .bezpieczenstwo:
                return "Bezpieczeństwo"
            case .gospodarka:
                return "Gospodarka"
            case .pogoda:
                return "Pogoda"
            default:
                return "Wydarzenia"
            }
        case .jobs, .aktualne:
            return rawValue
        }
    }

    func editorialImportance(topic: ReportTopicKind) -> String {
        switch topic {
        case .techNews:
            switch self {
            case .ai:
                return "może zmienić tempo adopcji modeli i narzędzi agentowych"
            case .infrastruktura:
                return "wpływa na koszt, dostępność i skalowanie rozwiązań AI"
            case .produkty:
                return "pokazuje, które funkcje szybko przechodzą z eksperymentu do codziennego użycia"
            case .regulacje:
                return "określa ryzyko prawne i tempo wdrożeń w firmach"
            case .cyber:
                return "bezpośrednio dotyka bezpieczeństwa systemów i danych"
            default:
                return "warto obserwować wpływ tej zmiany na produkty i decyzje technologiczne"
            }
        case .polskaSwiat:
            switch self {
            case .polska:
                return "może przełożyć się na decyzje administracji, firm i samorządów"
            case .polityka:
                return "wpływa na kierunek decyzji publicznych i najbliższą agendę polityczną"
            case .swiat:
                return "zmienia kontekst międzynarodowy dla Polski i Europy"
            case .bezpieczenstwo:
                return "dotyczy ryzyka strategicznego oraz odporności państwa"
            case .gospodarka:
                return "może wpływać na koszty, inwestycje i decyzje firm"
            case .pogoda:
                return "ma praktyczne znaczenie dla planowania dnia i bezpieczeństwa"
            default:
                return "warto obserwować dalszy rozwój tego wątku"
            }
        case .jobs, .aktualne:
            return "pomaga szybciej ocenić znaczenie tej informacji"
        }
    }
}

enum ResearchKeywordHighlighter {
    static func attributedText(_ text: String, keywords: [ResearchIssueKeyword], tint: Color) -> AttributedString {
        var attributed = AttributedString(text)
        for range in highlightedRanges(in: text, keywords: keywords) {
            guard let attributedRange = Range(range, in: attributed) else { continue }
            attributed[attributedRange].foregroundColor = tint
            attributed[attributedRange].font = .body.weight(.semibold)
            attributed[attributedRange].underlineStyle = Text.LineStyle(pattern: .solid, color: tint.opacity(0.72))
        }
        return attributed
    }

    static func highlightedRanges(in text: String, keywords: [ResearchIssueKeyword]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let uniqueKeywords = Array(Set(keywords.map(\.title))).sorted { $0.count > $1.count }

        for keyword in uniqueKeywords where keyword.count >= 2 {
            for term in searchTerms(for: keyword) {
                var searchRange = text.startIndex..<text.endIndex
                while let range = text.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchRange
                ) {
                    if isStandalone(range, in: text), !ranges.contains(where: { $0.overlaps(range) }) {
                        ranges.append(range)
                    }
                    searchRange = range.upperBound..<text.endIndex
                }
            }
        }

        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    private static func searchTerms(for keyword: String) -> [String] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        return Array(Set(ResearchKeywordCatalog.variants(for: trimmed)))
    }

    private static func isStandalone(_ range: Range<String.Index>, in text: String) -> Bool {
        let beforeIsBoundary: Bool
        if range.lowerBound == text.startIndex {
            beforeIsBoundary = true
        } else {
            let previousIndex = text.index(before: range.lowerBound)
            beforeIsBoundary = isBoundaryCharacter(text[previousIndex])
        }

        let afterIsBoundary: Bool
        if range.upperBound == text.endIndex {
            afterIsBoundary = true
        } else {
            afterIsBoundary = isBoundaryCharacter(text[range.upperBound])
        }

        return beforeIsBoundary && afterIsBoundary
    }

    private static func isBoundaryCharacter(_ character: Character) -> Bool {
        let wordCharacters = CharacterSet.letters.union(.decimalDigits)
        return character.unicodeScalars.allSatisfy { !wordCharacters.contains($0) }
    }
}

private extension ReportTopicKind {
    var researchEyebrow: String {
        switch self {
        case .techNews:
            "Sygnał technologiczny dnia"
        case .polskaSwiat:
            "Przegląd wydarzeń dnia"
        case .jobs, .aktualne:
            "Wydanie dnia"
        }
    }

    var researchHeroTitle: String {
        switch self {
        case .techNews:
            "Najważniejsze zmiany technologiczne"
        case .polskaSwiat:
            "Polska i świat w skrócie"
        case .jobs, .aktualne:
            "Wydanie dnia"
        }
    }

    var researchSignalsTitle: String {
        switch self {
        case .techNews:
            "Najważniejsze sygnały technologiczne"
        case .polskaSwiat:
            "Najważniejsze sygnały z Polski i świata"
        case .jobs, .aktualne:
            "Najważniejsze sygnały"
        }
    }

    var researchFallbackSignalTitle: String {
        switch self {
        case .techNews:
            "Wydanie technologiczne jest gotowe"
        case .polskaSwiat:
            "Przegląd wydarzeń jest gotowy"
        case .jobs, .aktualne:
            "Wydanie jest gotowe"
        }
    }

    var defaultResearchKeywords: [ResearchIssueKeyword] {
        switch self {
        case .techNews:
            [
                ResearchIssueKeyword(title: "AI", kind: .technology),
                ResearchIssueKeyword(title: "LLM", kind: .technology),
                ResearchIssueKeyword(title: "Infrastruktura", kind: .section)
            ]
        case .polskaSwiat:
            [
                ResearchIssueKeyword(title: "Polska", kind: .region),
                ResearchIssueKeyword(title: "Świat", kind: .region),
                ResearchIssueKeyword(title: "Bezpieczeństwo", kind: .section)
            ]
        case .jobs, .aktualne:
            []
        }
    }
}
