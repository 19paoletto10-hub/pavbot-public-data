import Foundation
import Observation

struct ResearchNewsClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Serwer Research zwrócił nieprawidłową odpowiedź."
            case .httpStatus(let status):
                "Serwer Research zwrócił HTTP \(status)."
            }
        }
    }

    var fetchData: @Sendable (URL) async throws -> Data
    var fetchText: @Sendable (URL) async throws -> String

    init(
        fetchData: @escaping @Sendable (URL) async throws -> Data = { url in
            let (data, response) = try await URLSession.shared.data(for: ManifestClient.request(for: url))
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ClientError.httpStatus(httpResponse.statusCode)
            }
            return data
        },
        fetchText: @escaping @Sendable (URL) async throws -> String = { url in
            let (data, response) = try await URLSession.shared.data(for: ManifestClient.request(for: url))
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ClientError.httpStatus(httpResponse.statusCode)
            }
            return String(decoding: data, as: UTF8.self)
        }
    ) {
        self.fetchData = fetchData
        self.fetchText = fetchText
    }
}

@MainActor
@Observable
final class ResearchNewsStore {
    typealias LoadState = PavbotLoadState

    var state: LoadState = .idle
    var issue: ResearchNewsIssue?
    var selectedPackage: TopicReportPackage?
    var cacheNotice: String?

    private let client: ResearchNewsClient
    private let cache: ResearchNewsCache
    private let parser: ResearchNewsParser

    init(
        client: ResearchNewsClient = ResearchNewsClient(),
        cache: ResearchNewsCache = ResearchNewsCache(),
        parser: ResearchNewsParser = ResearchNewsParser()
    ) {
        self.client = client
        self.cache = cache
        self.parser = parser
    }

    func load(
        packages: [TopicReportPackage],
        manifestURLString: String,
        topic: ReportTopicKind,
        selectedDay: String?,
        selectedArtifactIDs: [String]
    ) async {
        let candidatePackages = selectPackages(from: packages, selectedDay: selectedDay, selectedArtifactIDs: selectedArtifactIDs)
        guard !candidatePackages.isEmpty else {
            loadCachedIssue(for: topic)
            if issue == nil {
                state = .failed(
                    .custom(
                        title: "Brak raportów Research",
                        message: "Brak opublikowanych raportów Research w manifeście.",
                        actionTitle: "Odśwież manifest",
                        systemImage: topic.systemImage,
                        tint: topic.tint
                    )
                )
            }
            return
        }

        cacheNotice = nil
        state = .loading
        var lastError: Error?

        for package in candidatePackages {
            selectedPackage = package

            do {
                let parsedIssue = try await loadIssue(from: package, manifestURLString: manifestURLString)
                issue = parsedIssue
                selectedPackage = package
                cache.save(parsedIssue)
                cacheNotice = nil
                state = .loaded
                return
            } catch {
                lastError = error
                continue
            }
        }

        loadCachedIssue(for: topic)
        if issue != nil {
            cacheNotice = "Pokazuję ostatnie zapisane wydanie Research. Odświeżenie nie powiodło się."
            state = .loaded
        } else {
            cacheNotice = nil
            state = .failed(
                lastError.map { .network($0, context: .preview) }
                    ?? .custom(
                        title: "Nie udało się wczytać Research",
                        message: "Nie udało się wczytać wydania Research.",
                        actionTitle: "Odśwież wydanie",
                        systemImage: topic.systemImage,
                        tint: topic.tint
                    )
            )
        }
    }

    private func loadIssue(from package: TopicReportPackage, manifestURLString: String) async throws -> ResearchNewsIssue {
        let manifestURL = URL(string: manifestURLString)
        if let dataArtifact = package.researchDataArtifact,
           let url = dataArtifact.resolvedURL(manifestURL: manifestURL) {
            do {
                let data = try await client.fetchData(url)
                let report = try JSONDecoder.pavbot.decode(ResearchDataReport.self, from: data)
                return try report.nativeIssue(package: package)
            } catch {
                if package.researchReport == nil {
                    throw error
                }
            }
        }

        guard
            let artifact = package.researchReport,
            let url = artifact.resolvedURL(manifestURL: manifestURL)
        else {
            throw ParserError.missingReport
        }

        let markdown = try await client.fetchText(url)
        return try parser.parse(markdown, package: package)
    }

    private func loadCachedIssue(for topic: ReportTopicKind) {
        if let cached = cache.load(topic: topic) {
            issue = cached
            state = .loaded
        }
    }

    private func selectPackages(
        from packages: [TopicReportPackage],
        selectedDay: String?,
        selectedArtifactIDs: [String]
    ) -> [TopicReportPackage] {
        let artifactIDs = Set(selectedArtifactIDs)
        if !artifactIDs.isEmpty,
           let package = packages.first(where: { package in
               package.artifacts.contains { artifactIDs.contains($0.id) }
           }) {
            return [package]
        }

        if let selectedDay,
           let package = packages.first(where: { $0.date == selectedDay || $0.key.hasPrefix(selectedDay) }) {
            return [package]
        }

        return packages
    }

    private enum ParserError: LocalizedError {
        case missingReport

        var errorDescription: String? {
            "Paczka Research nie zawiera raportu Markdown."
        }
    }
}

struct ResearchNewsCache {
    private let defaults: UserDefaults
    private let keyPrefix = "pavbot.cachedResearchNewsIssue."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(topic: ReportTopicKind) -> ResearchNewsIssue? {
        guard let data = defaults.data(forKey: key(for: topic)) else { return nil }
        return try? JSONDecoder.pavbot.decode(ResearchNewsIssue.self, from: data)
    }

    func save(_ issue: ResearchNewsIssue) {
        guard let data = try? JSONEncoder().encode(issue) else { return }
        defaults.set(data, forKey: key(for: issue.topic))
    }

    private func key(for topic: ReportTopicKind) -> String {
        keyPrefix + topic.rawValue
    }
}

struct ResearchNewsParser {
    enum ParserError: LocalizedError {
        case missingContent

        var errorDescription: String? {
            "Raport Research nie zawiera treści do pokazania."
        }
    }

    func parse(_ markdown: String, package: TopicReportPackage) throws -> ResearchNewsIssue {
        let sections = markdownSections(from: markdown)
        let lead = cleanedLead(from: section(namedAnyOf: ["Podsumowanie", "Summary"], in: sections))
        let facts = section(namedAnyOf: ["Nowe fakty", "New facts", "Key facts"], in: sections)
        let sourcesSection = section(namedAnyOf: ["Źródła", "Sources", "Source"], in: sections)
        let articleBlocks = bulletBlocks(from: facts)
        let articles = articlesFromBlocks(articleBlocks, topic: package.topic, packageKey: package.key)

        let fallbackArticles = articles.isEmpty
            ? fallbackArticles(from: lead, topic: package.topic, packageKey: package.key)
            : articles

        guard !lead.isEmpty || !fallbackArticles.isEmpty else {
            throw ParserError.missingContent
        }

        return ResearchNewsIssue(
            topic: package.topic,
            packageKey: package.key,
            date: metadataValue(named: "Date", in: markdown) ?? package.date,
            time: package.time,
            status: metadataValue(named: "Status", in: markdown) ?? "Research update",
            lead: lead.isEmpty ? "Wydanie zawiera nowe materiały Research gotowe do czytania w aplikacji." : lead,
            articles: fallbackArticles,
            checkedSources: extractSources(from: sourcesSection),
            podcastTopics: parsePodcastTopics(from: section(namedAnyOf: ["Tematy do podcastu", "Podcast topics"], in: sections)),
            reportArtifact: package.researchReport,
            pdfArtifact: package.pdfReport,
            podcastBriefArtifact: package.podcastBriefPDF,
            audioArtifact: package.primaryAudio
        )
    }

    private func metadataValue(named name: String, in markdown: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?m)^\\s*#?\\s*" + escapedName + "\\s*:\\s*(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        guard
            let match = regex.firstMatch(in: markdown, range: range),
            let valueRange = Range(match.range(at: 1), in: markdown)
        else {
            return nil
        }
        return String(markdown[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdownSections(from markdown: String) -> [(title: String, body: String)] {
        var sections: [(title: String, body: String)] = []
        var currentTitle = ""
        var currentLines: [String] = []

        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                if !currentTitle.isEmpty {
                    sections.append((currentTitle, currentLines.joined(separator: "\n")))
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentLines = []
            } else if !currentTitle.isEmpty {
                currentLines.append(line)
            }
        }

        if !currentTitle.isEmpty {
            sections.append((currentTitle, currentLines.joined(separator: "\n")))
        }

        return sections
    }

    private func section(namedAnyOf titles: [String], in sections: [(title: String, body: String)]) -> String {
        sections.first { section in
            titles.contains { title in
                section.title.range(of: title, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }?.body ?? ""
    }

    private func cleanedLead(from text: String) -> String {
        cleanMarkdownParagraphs(text).joined(separator: "\n\n")
    }

    private func bulletBlocks(from section: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []

        for rawLine in section.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: " "))
                }
                current = [String(line.dropFirst(2))]
            } else if !current.isEmpty, !line.hasPrefix("|"), !line.hasPrefix("---") {
                current.append(line)
            }
        }

        if !current.isEmpty {
            blocks.append(current.joined(separator: " "))
        }

        return blocks
    }

    private func articlesFromBlocks(_ blocks: [String], topic: ReportTopicKind, packageKey: String) -> [ResearchNewsArticle] {
        blocks.enumerated().map { index, block in
            let cleanBody = cleanMarkdown(block)
            let title = titleFromBody(cleanBody)
            let section = classify(block, topic: topic)
            return ResearchNewsArticle(
                id: stableID(topic: topic, packageKey: packageKey, index: index, title: title),
                title: title,
                section: section,
                body: cleanBody,
                summary: summaryFromBody(cleanBody),
                sources: extractSources(from: block),
                priority: priorityFromBody(block),
                tags: tags(from: block, section: section)
            )
        }
    }

    private func fallbackArticles(from lead: String, topic: ReportTopicKind, packageKey: String) -> [ResearchNewsArticle] {
        guard !lead.isEmpty else { return [] }
        let section = topic == .polskaSwiat ? ResearchNewsSection.polska : .ai
        return [
            ResearchNewsArticle(
                id: stableID(topic: topic, packageKey: packageKey, index: 0, title: "Najważniejsze z wydania"),
                title: "Najważniejsze z wydania",
                section: section,
                body: lead,
                summary: summaryFromBody(lead),
                sources: [],
                priority: nil,
                tags: [section.rawValue]
            )
        ]
    }

    private func titleFromBody(_ body: String) -> String {
        let firstSentence = body
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? body
        return compactWords(firstSentence, maxWords: 12)
    }

    private func summaryFromBody(_ body: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractSources(from text: String) -> [ResearchNewsSource] {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var sources: [ResearchNewsSource] = []
        var seen: Set<String> = []

        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard
                let match,
                let titleRange = Range(match.range(at: 1), in: text),
                let urlRange = Range(match.range(at: 2), in: text)
            else {
                return
            }
            let source = ResearchNewsSource(
                title: String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                url: String(text[urlRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if seen.insert(source.id).inserted {
                sources.append(source)
            }
        }

        return sources
    }

    private func parsePodcastTopics(from section: String) -> [ResearchPodcastTopic] {
        section
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("|") && !$0.contains("---") }
            .dropFirst()
            .compactMap { row in
                let values = row
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { cleanMarkdown(String($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard values.count >= 3 else { return nil }
                return ResearchPodcastTopic(
                    priority: values[safe: 0] ?? "",
                    title: values[safe: 1] ?? "",
                    rationale: values[safe: 2] ?? "",
                    sourcesLabel: values[safe: 3] ?? ""
                )
            }
    }

    private func priorityFromBody(_ body: String) -> String? {
        let lowered = body.lowercased()
        if lowered.contains("high") || lowered.contains("wysok") { return "High" }
        if lowered.contains("medium") || lowered.contains("śred") { return "Medium" }
        if lowered.contains("low") || lowered.contains("niski") { return "Low" }
        return nil
    }

    private func classify(_ text: String, topic: ReportTopicKind) -> ResearchNewsSection {
        let value = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()

        switch topic {
        case .techNews:
            if containsAny(value, ["cve", "cyber", "security", "malware", "phishing", "vulnerability"]) {
                return .cyber
            }
            if containsAny(value, ["chip", "compute", "gpu", "tpu", "inference", "data center", "broadcom", "qualcomm", "micron", "infrastr"]) {
                return .infrastruktura
            }
            if containsAny(value, ["regul", "senate", "cma", "act", "law", "ustaw", "compliance"]) {
                return .regulacje
            }
            if containsAny(value, ["product", "produkt", "app", "cloudflare", "oauth", "figma", "wallet", "deezer", "krea", "apple"]) {
                return .produkty
            }
            if containsAny(value, ["ai", "llm", "openai", "anthropic", "model", "agent", "rag"]) {
                return .ai
            }
            return .inne
        case .polskaSwiat:
            if containsAny(value, ["pogod", "upal", "burz", "imgw", "rcb"]) {
                return .pogoda
            }
            if containsAny(value, ["bezpieczen", "nato", "mon", "wojsk", "obron", "granica", "iran", "ukraina"]) {
                return .bezpieczenstwo
            }
            if containsAny(value, ["gospod", "energia", "firm", "biznes", "inflac", "bank", "podat"]) {
                return .gospodarka
            }
            if containsAny(value, ["sejm", "rzad", "prezydent", "premier", "wybor", "polity"]) {
                return .polityka
            }
            if containsAny(value, ["usa", "europa", "guardian", "ap", "turcja", "chiny", "swiat"]) {
                return .swiat
            }
            if containsAny(value, ["polsk", "kprm", "warszaw", "gdansk", "wroclaw"]) {
                return .polska
            }
            return .inne
        case .jobs, .aktualne:
            return .inne
        }
    }

    private func tags(from text: String, section: ResearchNewsSection) -> [String] {
        let keywords = ["AI", "LLM", "RAG", "OpenAI", "Cloudflare", "NATO", "MON", "KPRM", "Remote", "Cyber", "OAuth"]
        let found = keywords.filter {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return Array(([section.rawValue] + found).prefix(5))
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private func cleanMarkdown(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanMarkdownParagraphs(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var currentLines: [String] = []

        func flushCurrentParagraph() {
            let paragraph = currentLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            currentLines = []
            guard !paragraph.isEmpty else { return }
            paragraphs.append(cleanMarkdown(paragraph))
        }

        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushCurrentParagraph()
                continue
            }
            guard !line.hasPrefix("|"), !line.hasPrefix("---") else { continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushCurrentParagraph()
                currentLines = ["• \(String(line.dropFirst(2)))"]
                flushCurrentParagraph()
            } else {
                currentLines.append(line)
            }
        }

        flushCurrentParagraph()
        return paragraphs.filter { !$0.isEmpty }
    }

    private func compactWords(_ text: String, maxWords: Int) -> String {
        let words = text
            .split(separator: " ")
            .prefix(maxWords)
            .map(String.init)
        let title = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Najważniejszy wątek" : title
    }

    private func stableID(topic: ReportTopicKind, packageKey: String, index: Int, title: String) -> String {
        let slug = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(topic.topic)-\(packageKey)-\(index)-\(slug)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
