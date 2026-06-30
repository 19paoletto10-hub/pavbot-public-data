import Foundation

struct JobsMarkdownParser {
    enum ParserError: LocalizedError {
        case missingDate
        case missingSummary
        case missingOpportunities

        var errorDescription: String? {
            switch self {
            case .missingDate:
                "Raport jobs nie zawiera daty rundy."
            case .missingSummary:
                "Raport jobs nie zawiera podsumowania."
            case .missingOpportunities:
                "Raport jobs nie zawiera ofert pracy."
            }
        }
    }

    func parse(_ markdown: String) throws -> JobsReport {
        let lines = markdown.components(separatedBy: .newlines)
        let dateLine = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Date:") }
        let statusLine = lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Status:") }
        let dateParts = parseDateLine(dateLine)
        guard let runDate = dateParts.date, let runTime = dateParts.time else {
            throw ParserError.missingDate
        }

        let summary = cleanBlock(
            section(
                namedAny: ["Podsumowanie zarządcze", "Podsumowanie wykonawcze", "Executive Summary", "Summary"],
                in: markdown
            )
        )
        guard !summary.isEmpty else {
            throw ParserError.missingSummary
        }

        let checkedSources = parseCheckedSources(section(namedAny: ["Zakres sprawdzony", "Scope Checked"], in: markdown))
        let opportunities = parseOpportunities(
            section(
                namedAny: [
                    "Najciekawsze nowe lub materialnie zmienione role",
                    "Najciekawsze nowe lub zmienione role",
                    "Top New Or Materially Changed Roles",
                    "Top New Roles",
                    "Top Roles"
                ],
                in: markdown
            ),
            fallbackURLs: checkedSources.map(\.url)
        )
        guard !opportunities.isEmpty else {
            throw ParserError.missingOpportunities
        }

        return JobsReport(
            schemaVersion: 1,
            status: cleanInline(statusLine?.replacingOccurrences(of: "Status:", with: "") ?? "Unknown").trimmed,
            runDate: runDate,
            runTime: runTime,
            executiveSummary: summary,
            opportunities: opportunities,
            changes: bulletItems(in: section(namedAny: ["Zmiany od poprzedniej rundy", "Changes Since Previous Run"], in: markdown)),
            risks: bulletItems(in: section(namedAny: ["Ryzyka i niepewności", "Ryzyka i niepewność", "Risks"], in: markdown)),
            recommendedActions: bulletItems(in: section(namedAny: ["Rekomendowane akcje", "Rekomendowane działania", "Recommended Actions"], in: markdown)),
            checkedSources: checkedSources
        )
    }

    private func parseDateLine(_ line: String?) -> (date: String?, time: String?) {
        guard let line else { return (nil, nil) }
        let value = line
            .replacingOccurrences(of: "Date:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: " ").map(String.init)
        return (parts.first, parts.dropFirst().first)
    }

    private func section(namedAny headings: [String], in markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        let normalizedHeadings = Set(headings.map(normalizeHeading))
        var sectionLines: [String] = []
        var isInsideSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                if isInsideSection {
                    break
                }
                isInsideSection = normalizedHeadings.contains(normalizeHeading(String(trimmed.dropFirst(3))))
                continue
            }
            if isInsideSection {
                sectionLines.append(line)
            }
        }

        return sectionLines.joined(separator: "\n")
    }

    private func parseOpportunities(_ markdown: String, fallbackURLs: [String]) -> [JobOpportunity] {
        let lines = markdown.components(separatedBy: .newlines)
        var result: [JobOpportunity] = []
        var currentHeading: String?
        var currentBlock: [String] = []

        func flush() {
            guard let currentHeading else { return }
            let block = currentBlock.joined(separator: "\n")
            result.append(
                opportunity(
                    from: currentHeading,
                    block: block,
                    rankFallback: result.count + 1,
                    fallbackURLs: fallbackURLs
                )
            )
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("### ") {
                flush()
                currentHeading = String(trimmed.dropFirst(4))
                currentBlock = []
            } else if currentHeading != nil {
                currentBlock.append(line)
            }
        }
        flush()

        if !result.isEmpty {
            return result
        }

        for (index, block) in flatBulletBlocks(in: markdown).enumerated() {
            result.append(flatOpportunity(from: block, rankFallback: index + 1, fallbackURLs: fallbackURLs))
        }

        return result
    }

    private func opportunity(from heading: String, block: String, rankFallback: Int, fallbackURLs: [String]) -> JobOpportunity {
        let headingWithoutMarkdown = cleanInline(heading)
        let rank = parseRank(headingWithoutMarkdown) ?? rankFallback
        let titleWithoutRank = stripRank(from: headingWithoutMarkdown)
        let split = splitCompanyAndTitle(titleWithoutRank)
        let location = bulletValue(in: block, labels: ["Lokalizacja/remote", "Lokalizacja", "Location", "Location/remote"])
        let fitSummary = bulletValue(in: block, labels: ["Fit LLM/AI", "Fit"])
        let whyInteresting = bulletValue(in: block, labels: ["Dlaczego interesujące", "Why interesting", "Why it matters"])
        let uncertainty = bulletValue(in: block, labels: ["Niepewność", "Uncertainty"])
        let compensation = bulletValue(in: block, labels: ["Wynagrodzenie", "Compensation"])
        let sourceURLs = markdownLinks(in: block).map(\.url)

        return JobOpportunity(
            rank: rank,
            title: split.title,
            company: split.company,
            location: location,
            workMode: inferWorkMode(from: location),
            compensation: compensation,
            seniority: inferSeniority(from: split.title),
            fitSummary: fitSummary,
            whyInteresting: whyInteresting,
            uncertainty: uncertainty,
            sourceURLs: sourceURLs.isEmpty ? Array(fallbackURLs.prefix(1)) : sourceURLs,
            tags: inferTags(from: [split.title, fitSummary, whyInteresting, location].joined(separator: " "))
        )
    }

    private func flatOpportunity(from block: String, rankFallback: Int, fallbackURLs: [String]) -> JobOpportunity {
        var raw = block.trimmed
        if raw.hasPrefix("- ") {
            raw = String(raw.dropFirst(2)).trimmed
        }

        let links = markdownLinks(in: raw)
        let label = cleanInline(links.first?.title ?? "")
        let split = splitCompanyAndTitle(label.isEmpty ? "Nieznana firma - Nieznany tytuł" : label)
        var body = raw
        if let first = links.first {
            body = body.replacingOccurrences(of: "[\(first.title)](\(first.url))", with: "", options: [], range: nil)
            body = body.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        }

        let normalizedBody = cleanInline(body)
        let clauses = normalizedBody
            .split(separator: ";")
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
            .filter { !$0.isEmpty }
        let backticked = captures(in: block, pattern: #"`([^`]+)`"#)

        let location = inferFlatLocation(backticked: backticked, clauses: clauses)
        let compensation = inferFlatCompensation(backticked: backticked, clauses: clauses)
        let uncertainty = inferFlatUncertainty(clauses: clauses)
        let fitSummary = inferFlatFitSummary(clauses: clauses)
        let whyInteresting = inferFlatWhyInteresting(clauses: clauses, fitSummary: fitSummary)
        let sourceURLs = links.map(\.url)

        return JobOpportunity(
            rank: rankFallback,
            title: split.title,
            company: split.company,
            location: location,
            workMode: inferWorkMode(from: location),
            compensation: compensation,
            seniority: inferSeniority(from: split.title),
            fitSummary: fitSummary,
            whyInteresting: whyInteresting,
            uncertainty: uncertainty,
            sourceURLs: sourceURLs.isEmpty ? Array(fallbackURLs.prefix(1)) : sourceURLs,
            tags: inferTags(from: [split.title, fitSummary, whyInteresting, location, normalizedBody].joined(separator: " "))
        )
    }

    private func bulletValue(in block: String, labels: [String]) -> String {
        for line in block.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { continue }
            for label in labels {
                let prefix = "- \(label):"
                if trimmed.localizedCaseInsensitiveContains(prefix) {
                    return cleanInline(trimmed.replacingOccurrences(of: prefix, with: "")).trimmed
                }
            }
        }
        return "Brak danych w raporcie."
    }

    private func flatBulletBlocks(in markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [String] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: " "))
                }
                current = [trimmed]
                continue
            }

            if !current.isEmpty, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                current.append(trimmed)
                continue
            }

            if !current.isEmpty {
                blocks.append(current.joined(separator: " "))
                current = []
            }
        }

        if !current.isEmpty {
            blocks.append(current.joined(separator: " "))
        }

        return blocks.filter { !markdownLinks(in: $0).isEmpty }
    }

    private func inferFlatLocation(backticked: [String], clauses: [String]) -> String {
        let candidates = backticked.filter { value in
            let normalized = value.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return normalized.contains("wroc")
                || normalized.contains("remote")
                || normalized.contains("zdal")
                || normalized.contains("hybrid")
                || normalized.contains("hybryd")
                || normalized.contains("location")
        }
        if !candidates.isEmpty {
            return Array(NSOrderedSet(array: candidates)).compactMap { $0 as? String }.joined(separator: ", ")
        }
        if let first = clauses.first, first.count < 120 {
            return first
        }
        return "Brak danych w raporcie."
    }

    private func inferFlatCompensation(backticked: [String], clauses: [String]) -> String {
        let pattern = #"\b(?:PLN|USD|EUR|CHF|zł|zl|net|gross|brutto|netto)\b"#
        for candidate in backticked + clauses {
            if candidate.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return candidate
            }
        }
        return "Brak publicznych widełek."
    }

    private func inferFlatUncertainty(clauses: [String]) -> String {
        for clause in clauses {
            let normalized = clause.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            if normalized.contains("niepewnosc") || normalized.contains("uncertainty") {
                return clause
            }
        }
        return "Brak danych w raporcie."
    }

    private func inferFlatFitSummary(clauses: [String]) -> String {
        let descriptive = clauses.filter { clause in
            let normalized = clause.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return !normalized.contains("niepewnosc") && !normalized.contains("uncertainty")
        }
        if descriptive.count >= 2 {
            return descriptive[1]
        }
        if let first = descriptive.first {
            return first
        }
        return "Brak danych w raporcie."
    }

    private func inferFlatWhyInteresting(clauses: [String], fitSummary: String) -> String {
        let descriptive = clauses.filter { clause in
            let normalized = clause.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return !normalized.contains("niepewnosc") && !normalized.contains("uncertainty")
        }
        if descriptive.count >= 3 {
            return descriptive[2]
        }
        if descriptive.count >= 2 {
            return descriptive[1]
        }
        if let first = descriptive.first {
            return first
        }
        return fitSummary.isEmpty ? "Brak danych w raporcie." : fitSummary
    }

    private func parseCheckedSources(_ markdown: String) -> [JobsCheckedSource] {
        markdownLinks(in: markdown).map {
            JobsCheckedSource(title: $0.title, url: $0.url, status: "checked")
        }
    }

    private func bulletItems(in markdown: String) -> [String] {
        markdown
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("- ") else { return nil }
                return cleanInline(String(trimmed.dropFirst(2))).trimmed
            }
            .filter { !$0.isEmpty }
    }

    private func markdownLinks(in markdown: String) -> [(title: String, url: String)] {
        let pattern = #"\[([^\]]+)\]\((https?://[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return regex.matches(in: markdown, range: nsRange).compactMap { match in
            guard
                let titleRange = Range(match.range(at: 1), in: markdown),
                let urlRange = Range(match.range(at: 2), in: markdown)
            else {
                return nil
            }
            return (String(markdown[titleRange]), String(markdown[urlRange]))
        }
    }

    private func captures(in value: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let groupRange = Range(match.range(at: 1), in: value) else {
                return nil
            }
            return String(value[groupRange])
        }
    }

    private func parseRank(_ value: String) -> Int? {
        guard let firstToken = value.split(separator: " ").first else { return nil }
        return Int(firstToken.replacingOccurrences(of: ".", with: ""))
    }

    private func stripRank(from value: String) -> String {
        value.replacingOccurrences(
            of: #"^\d+\.\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmed
    }

    private func splitCompanyAndTitle(_ value: String) -> (company: String, title: String) {
        guard let range = value.range(of: " - ") else {
            return ("Nieznana firma", value.trimmed)
        }
        return (
            String(value[..<range.lowerBound]).trimmed,
            String(value[range.upperBound...]).trimmed
        )
    }

    private func inferWorkMode(from location: String) -> String {
        let normalized = location.lowercased()
        if normalized.contains("remote") || normalized.contains("zdal") {
            return "Remote"
        }
        if normalized.contains("hybrid") || normalized.contains("hybryd") {
            return "Hybrid"
        }
        if normalized.contains("wrocław") || normalized.contains("wroclaw") {
            return "Wrocław"
        }
        return location.isEmpty ? "Brak danych" : location
    }

    private func inferSeniority(from title: String) -> String {
        let normalized = title.lowercased()
        if normalized.contains("principal") {
            return "Principal"
        }
        if normalized.contains("staff") {
            return "Staff"
        }
        if normalized.contains("senior") {
            return "Senior"
        }
        if normalized.contains("lead") {
            return "Lead"
        }
        return "Nieokreślony"
    }

    private func inferTags(from text: String) -> [String] {
        let normalized = text.lowercased()
        let candidates: [(String, String)] = [
            ("Agentic AI", "agentic"),
            ("RAG", "rag"),
            ("LLM", "llm"),
            ("GenAI", "genai"),
            ("MLOps", "mlops"),
            ("LLMOps", "llmops"),
            ("Python", "python"),
            ("AWS", "aws"),
            ("Azure", "azure"),
            ("GCP", "gcp")
        ]
        return candidates.compactMap { label, needle in
            normalized.contains(needle) ? label : nil
        }
    }

    private func cleanBlock(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .map { cleanInline($0).trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func cleanInline(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"\[([^\]]+)\]\((https?://[^)]+)\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
    }

    private func normalizeHeading(_ value: String) -> String {
        cleanInline(value)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
