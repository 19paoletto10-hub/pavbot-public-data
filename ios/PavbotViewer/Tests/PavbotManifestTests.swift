import XCTest
import UserNotifications
import SwiftUI
import AVFoundation
@testable import PavbotViewer

final class PavbotManifestTests: XCTestCase {
    func testDecodesManifestAndGroupsEnabledAutomations() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.automations.count, 2)
        XCTAssertEqual(manifest.enabledAutomations.map(\.id), ["research", "podcast"])
        XCTAssertEqual(manifest.topics.map(\.slug), ["tech-news"])
    }

    func testFiltersArtifactsByExactDay() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)

        let filtered = manifest.artifacts(on: DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 22).date!)

        XCTAssertEqual(filtered.map(\.id), ["run-2026-06-22", "audio-2026-06-22", "brief-pdf-2026-06-22", "pdf-2026-06-22"])
    }

    func testSearchesArtifactsByTitleTopicTypeAndPath() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let day = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 6, day: 22).date!

        XCTAssertEqual(manifest.filteredArtifacts(on: day, query: "audio").map(\.id), ["audio-2026-06-22"])
        XCTAssertEqual(manifest.filteredArtifacts(on: day, query: "tech-news").map(\.id), ["run-2026-06-22", "audio-2026-06-22", "brief-pdf-2026-06-22", "pdf-2026-06-22"])
        XCTAssertEqual(manifest.filteredArtifacts(on: nil, query: "2026-06-21").map(\.id), ["run-2026-06-21"])
    }

    func testFiltersArtifactsByNotificationRoute() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let route = ArtifactNotificationRoute(
            topic: "tech-news",
            date: "2026-06-22",
            artifactIDs: ["audio-2026-06-22", "missing-id"]
        )

        XCTAssertEqual(manifest.filteredArtifacts(for: route).map(\.id), ["audio-2026-06-22"])
    }

    func testFiltersArtifactsByNotificationTopicAndDateWhenIDsAreMissing() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let route = ArtifactNotificationRoute(topic: "tech-news", date: "2026-06-22", artifactIDs: [])

        XCTAssertEqual(manifest.filteredArtifacts(for: route).map(\.id), ["run-2026-06-22", "audio-2026-06-22", "brief-pdf-2026-06-22", "pdf-2026-06-22"])
    }

    func testSortsAvailableArtifactDaysDescending() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)

        XCTAssertEqual(manifest.availableDays.map(\.pavbotDayString), ["2026-06-22", "2026-06-21"])
    }

    func testArtifactKindMapsToViewerCapability() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let audio = try XCTUnwrap(manifest.artifacts.first { $0.type == .podcastAudio })
        let markdown = try XCTUnwrap(manifest.artifacts.first { $0.type == .run })

        XCTAssertEqual(audio.viewerKind, .audio)
        XCTAssertEqual(markdown.viewerKind, .markdown)
    }

    func testAutomationArtifactGroupsFilterArtifactsByAutomationKind() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)

        let groups = manifest.automationArtifactGroups

        XCTAssertEqual(groups.map(\.id), ["research", "podcast"])
        XCTAssertEqual(groups[0].artifacts.map(\.id), ["run-2026-06-22", "pdf-2026-06-22", "run-2026-06-21"])
        XCTAssertEqual(groups[1].artifacts.map(\.id), ["audio-2026-06-22", "brief-pdf-2026-06-22"])
    }

    func testAutomationArtifactGroupDaysAreSortedDescending() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let researchGroup = try XCTUnwrap(manifest.automationArtifactGroups.first { $0.id == "research" })

        XCTAssertEqual(researchGroup.days.map(\.pavbotDayString), ["2026-06-22", "2026-06-21"])
        XCTAssertEqual(researchGroup.latestArtifact?.id, "run-2026-06-22")
    }

    func testAutomationArtifactGroupFiltersNotificationRouteIDsWithinDay() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let podcastGroup = try XCTUnwrap(manifest.automationArtifactGroups.first { $0.id == "podcast" })
        let day = try XCTUnwrap(DateFormatter.pavbotDay.date(from: "2026-06-22"))
        let route = ArtifactNotificationRoute(
            topic: "tech-news",
            date: "2026-06-22",
            artifactIDs: ["run-2026-06-22", "audio-2026-06-22"]
        )

        XCTAssertEqual(podcastGroup.artifacts(on: day, matching: route).map(\.id), ["audio-2026-06-22"])
    }

    func testPodcastPackagePairsAudioWithBriefPDFForTheSameDay() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let podcastGroup = try XCTUnwrap(manifest.automationArtifactGroups.first { $0.id == "podcast" })
        let day = try XCTUnwrap(DateFormatter.pavbotDay.date(from: "2026-06-22"))

        let package = try XCTUnwrap(podcastGroup.podcastPackage(on: day))

        XCTAssertEqual(package.primaryAudio?.id, "audio-2026-06-22")
        XCTAssertEqual(package.briefPDF?.id, "brief-pdf-2026-06-22")
        XCTAssertFalse(package.isMissingBriefPDF)
    }

    func testPodcastPackageFlagsMissingBriefPDFWhenAudioExists() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let podcastAutomation = try XCTUnwrap(manifest.enabledAutomations.first { $0.id == "podcast" })
        let audioOnly = manifest.artifacts.filter { $0.id == "audio-2026-06-22" }
        let podcastGroup = AutomationArtifactGroup(automation: podcastAutomation, artifacts: audioOnly)
        let day = try XCTUnwrap(DateFormatter.pavbotDay.date(from: "2026-06-22"))

        let package = try XCTUnwrap(podcastGroup.podcastPackage(on: day))

        XCTAssertEqual(package.primaryAudio?.id, "audio-2026-06-22")
        XCTAssertNil(package.briefPDF)
        XCTAssertTrue(package.isMissingBriefPDF)
    }

    func testJobsReportPackagesPairMarkdownAndPDFForGeneration() throws {
        let manifest = try manifestWithAdditionalArtifacts([
            PavbotArtifact(
                id: "jobs-run-2026-06-25-0141",
                type: .run,
                topic: "llm-ai-jobs-wroclaw",
                title: "LLM AI Jobs Wrocław",
                path: "research/llm-ai-jobs-wroclaw/runs/2026-06-25-0141.md",
                url: "research/llm-ai-jobs-wroclaw/runs/2026-06-25-0141.md",
                sizeBytes: 300,
                date: "2026-06-25",
                time: nil
            ),
            PavbotArtifact(
                id: "jobs-pdf-2026-06-25-0141",
                type: .pdf,
                topic: "llm-ai-jobs-wroclaw",
                title: "LLM AI Jobs Wrocław PDF",
                path: "research/llm-ai-jobs-wroclaw/pdfs/2026-06-25-0141-llm-ai-jobs-wroclaw.pdf",
                url: "research/llm-ai-jobs-wroclaw/pdfs/2026-06-25-0141-llm-ai-jobs-wroclaw.pdf",
                sizeBytes: 400,
                date: "2026-06-25",
                time: nil
            )
        ])

        let packages = manifest.reportPackages(for: .jobs)

        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].researchReport?.id, "jobs-run-2026-06-25-0141")
        XCTAssertEqual(packages[0].pdfReport?.id, "jobs-pdf-2026-06-25-0141")
        XCTAssertTrue(packages[0].hasPDF)
    }

    func testJobsReportPackagesPairRunAndJobsDataForSameTimestamp() throws {
        let manifest = try manifestWithAdditionalArtifacts([
            PavbotArtifact(
                id: "jobs-run-2026-06-25-0141",
                type: .run,
                topic: "llm-ai-jobs-wroclaw",
                title: "LLM AI Jobs Wrocław",
                path: "research/llm-ai-jobs-wroclaw/runs/2026-06-25-0141.md",
                url: "research/llm-ai-jobs-wroclaw/runs/2026-06-25-0141.md",
                sizeBytes: 300,
                date: "2026-06-25",
                time: "01:41"
            ),
            PavbotArtifact(
                id: "jobs-data-2026-06-25-0141",
                type: .jobsData,
                topic: "llm-ai-jobs-wroclaw",
                title: "Jobs data",
                path: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
                url: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
                sizeBytes: 400,
                date: "2026-06-25",
                time: "01:41"
            )
        ])

        let packages = manifest.reportPackages(for: .jobs)

        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].key, "2026-06-25-01:41")
        XCTAssertEqual(packages[0].researchReport?.id, "jobs-run-2026-06-25-0141")
        XCTAssertEqual(packages[0].dataArtifact?.id, "jobs-data-2026-06-25-0141")
    }

    func testResearchReportPackagesExposeTechAndPolskaTopics() throws {
        let manifest = try manifestWithAdditionalArtifacts([
            PavbotArtifact(
                id: "polska-run-2026-06-24",
                type: .run,
                topic: "polska-swiat",
                title: "Polska Świat Research",
                path: "research/polska-swiat/runs/2026-06-24.md",
                url: "research/polska-swiat/runs/2026-06-24.md",
                sizeBytes: 300,
                date: "2026-06-24",
                time: nil
            ),
            PavbotArtifact(
                id: "polska-pdf-2026-06-24",
                type: .pdf,
                topic: "polska-swiat",
                title: "Polska Świat PDF",
                path: "research/polska-swiat/pdfs/2026-06-24-polska-swiat.pdf",
                url: "research/polska-swiat/pdfs/2026-06-24-polska-swiat.pdf",
                sizeBytes: 300,
                date: "2026-06-24",
                time: nil
            )
        ])

        let techPackages = manifest.reportPackages(for: .techNews)
        let polskaPackages = manifest.reportPackages(for: .polskaSwiat)

        XCTAssertEqual(techPackages.map(\.date), ["2026-06-22", "2026-06-21"])
        XCTAssertEqual(polskaPackages.map(\.date), ["2026-06-24"])
        XCTAssertEqual(polskaPackages[0].researchReport?.id, "polska-run-2026-06-24")
        XCTAssertEqual(polskaPackages[0].pdfReport?.id, "polska-pdf-2026-06-24")
    }

    func testReportPackageKeepsMarkdownVisibleWhenPDFIsMissing() throws {
        let manifest = try manifestWithAdditionalArtifacts([
            PavbotArtifact(
                id: "jobs-run-2026-06-24-0141",
                type: .run,
                topic: "llm-ai-jobs-wroclaw",
                title: "LLM AI Jobs Wrocław",
                path: "research/llm-ai-jobs-wroclaw/runs/2026-06-24-0141.md",
                url: "research/llm-ai-jobs-wroclaw/runs/2026-06-24-0141.md",
                sizeBytes: 300,
                date: "2026-06-24",
                time: nil
            )
        ])

        let package = try XCTUnwrap(manifest.reportPackages(for: .jobs).first)

        XCTAssertEqual(package.researchReport?.id, "jobs-run-2026-06-24-0141")
        XCTAssertNil(package.pdfReport)
        XCTAssertFalse(package.hasPDF)
    }

    func testReportPackageCanLimitArtifactsToNotificationIDs() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let package = try XCTUnwrap(manifest.reportPackages(for: .techNews).first { $0.date == "2026-06-22" })

        let filtered = try XCTUnwrap(package.filteringArtifacts(to: ["run-2026-06-22", "audio-2026-06-22"]))

        XCTAssertEqual(filtered.artifacts.map(\.id), ["run-2026-06-22", "audio-2026-06-22"])
        XCTAssertEqual(filtered.researchReport?.id, "run-2026-06-22")
        XCTAssertEqual(filtered.primaryAudio?.id, "audio-2026-06-22")
        XCTAssertNil(filtered.pdfReport)
    }

    func testResearchNewsParserBuildsNativeIssueFromTechReportMarkdown() throws {
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [
            Self.artifact(id: "tech-run", type: .run, topic: "tech-news", path: "research/tech-news/runs/2026-06-25.md", date: "2026-06-25"),
            Self.artifact(id: "tech-pdf", type: .pdf, topic: "tech-news", path: "research/tech-news/pdfs/2026-06-25-tech-news.pdf", date: "2026-06-25"),
            Self.artifact(id: "tech-audio", type: .podcastAudio, topic: "tech-news", path: "research/tech-news/podcasts/2026-06-25/podcast.mp3", date: "2026-06-25")
        ])

        let issue = try ResearchNewsParser().parse(Self.techResearchMarkdownFixture, package: package)

        XCTAssertEqual(issue.topic, .techNews)
        XCTAssertEqual(issue.date, "2026-06-25")
        XCTAssertEqual(issue.status, "Material update")
        XCTAssertTrue(issue.lead.contains("AI i infrastruktura"))
        XCTAssertEqual(issue.articles.count, 2)
        XCTAssertEqual(issue.articles[0].section, .infrastruktura)
        XCTAssertGreaterThanOrEqual(issue.articles[0].sources.count, 2)
        XCTAssertEqual(issue.podcastTopics.count, 1)
        XCTAssertEqual(issue.pdfArtifact?.id, "tech-pdf")
        XCTAssertEqual(issue.audioArtifact?.id, "tech-audio")
    }

    func testResearchNewsParserBuildsNativeIssueFromPolskaSwiatEnglishHeadings() throws {
        let package = TopicReportPackage(topic: .polskaSwiat, key: "2026-06-25", artifacts: [
            Self.artifact(id: "polska-run", type: .run, topic: "polska-swiat", path: "research/polska-swiat/runs/2026-06-25.md", date: "2026-06-25")
        ])

        let issue = try ResearchNewsParser().parse(Self.polskaSwiatResearchMarkdownFixture, package: package)

        XCTAssertEqual(issue.topic, .polskaSwiat)
        XCTAssertEqual(issue.status, "Material update")
        XCTAssertTrue(issue.lead.contains("Polska i świat"))
        XCTAssertEqual(issue.articles.count, 2)
        XCTAssertEqual(issue.articles[0].section, .bezpieczenstwo)
        XCTAssertTrue(issue.articles[1].matchesSearch("energia"))
        XCTAssertGreaterThanOrEqual(issue.sourceCount, 2)
    }

    func testResearchNewsArticlesHaveStableIDsAndSearchableContent() throws {
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [
            Self.artifact(id: "tech-run", type: .run, topic: "tech-news", path: "research/tech-news/runs/2026-06-25.md", date: "2026-06-25")
        ])
        let parser = ResearchNewsParser()

        let firstIssue = try parser.parse(Self.techResearchMarkdownFixture, package: package)
        let secondIssue = try parser.parse(Self.techResearchMarkdownFixture, package: package)

        XCTAssertEqual(firstIssue.articles.first?.id, secondIssue.articles.first?.id)
        XCTAssertTrue(firstIssue.articles[0].matchesSearch("Broadcom"))
        XCTAssertTrue(firstIssue.articles[0].matchesSearch("OpenAI"))
        XCTAssertFalse(firstIssue.articles[0].body.isEmpty)
    }

    func testResearchNewsIssueFiltersBySectionAndSearchText() throws {
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [
            Self.artifact(id: "tech-run", type: .run, topic: "tech-news", path: "research/tech-news/runs/2026-06-25.md", date: "2026-06-25")
        ])
        let issue = try ResearchNewsParser().parse(Self.techResearchMarkdownFixture, package: package)

        XCTAssertEqual(issue.filteredArticles(section: .infrastruktura, query: "").map(\.title), [issue.articles[0].title])
        XCTAssertEqual(issue.filteredArticles(section: nil, query: "oauth").map(\.section), [.produkty])
    }

    func testResearchNewsIssueKeepsNewsVisibleWhenPDFIsMissing() throws {
        let package = TopicReportPackage(topic: .polskaSwiat, key: "2026-06-25", artifacts: [
            Self.artifact(id: "polska-run", type: .run, topic: "polska-swiat", path: "research/polska-swiat/runs/2026-06-25.md", date: "2026-06-25")
        ])

        let issue = try ResearchNewsParser().parse(Self.polskaSwiatResearchMarkdownFixture, package: package)

        XCTAssertNil(issue.pdfArtifact)
        XCTAssertFalse(issue.articles.isEmpty)
        XCTAssertFalse(issue.hasPDF)
    }

    func testResearchIssuePresentationBuildsPremiumTechNewsBrief() throws {
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [
            Self.artifact(id: "tech-run", type: .run, topic: "tech-news", path: "research/tech-news/runs/2026-06-25.md", date: "2026-06-25")
        ])
        let issue = try ResearchNewsParser().parse(Self.techResearchMarkdownFixture, package: package)

        let presentation = ResearchIssuePresentation(issue: issue)

        XCTAssertEqual(presentation.eyebrow, "Sygnał technologiczny dnia")
        XCTAssertTrue(presentation.lead.contains("AI i infrastruktura"))
        XCTAssertGreaterThanOrEqual(presentation.signals.count, 2)
        XCTAssertLessThanOrEqual(presentation.signals.count, 3)

        let keywords = presentation.keywords.map(\.title)
        XCTAssertTrue(keywords.contains("AI"))
        XCTAssertTrue(keywords.contains("OpenAI"))
        XCTAssertTrue(keywords.contains("Cloudflare"))
    }

    func testResearchIssuePresentationModeratesTechLeadAndSignals() throws {
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [
            Self.artifact(id: "tech-run", type: .run, topic: "tech-news", path: "research/tech-news/runs/2026-06-25.md", date: "2026-06-25")
        ])
        let issue = try ResearchNewsParser().parse(Self.techResearchMarkdownFixture, package: package)

        let presentation = ResearchIssuePresentation(issue: issue)

        XCTAssertTrue(presentation.lead.contains("Najmocniejszy wniosek"))
        XCTAssertTrue(presentation.lead.contains("OpenAI"))
        XCTAssertTrue(presentation.lead.contains("Cloudflare"))
        XCTAssertGreaterThanOrEqual(presentation.leadParagraphs.count, 3)
        XCTAssertEqual(presentation.quickPoints.count, 3)
        XCTAssertEqual(presentation.signals.count, 2)
        XCTAssertNotEqual(presentation.signals[0].title, issue.articles[0].title)
        XCTAssertTrue(presentation.signals[0].title.contains("OpenAI"))
        XCTAssertTrue(presentation.signals[0].summary.contains("Dlaczego to ważne"))
        XCTAssertFalse(presentation.signals[0].summary.contains("["))
        XCTAssertFalse(presentation.signals[0].summary.contains("]("))
        XCTAssertFalse(presentation.signals[0].summary.contains("..."))
    }

    func testResearchArticlePresentationBuildsModeratedNewsCopy() throws {
        let package = TopicReportPackage(topic: .polskaSwiat, key: "2026-06-25", artifacts: [
            Self.artifact(id: "polska-run", type: .run, topic: "polska-swiat", path: "research/polska-swiat/runs/2026-06-25.md", date: "2026-06-25")
        ])
        let issue = try ResearchNewsParser().parse(Self.polskaSwiatResearchMarkdownFixture, package: package)
        let article = try XCTUnwrap(issue.articles.first)

        let presentation = ResearchArticlePresentation(article: article, topic: .polskaSwiat)

        XCTAssertTrue(presentation.title.contains("Bezpieczeństwo"))
        XCTAssertTrue(presentation.title.contains("NATO"))
        XCTAssertTrue(presentation.summary.contains("Dlaczego to ważne"))
        XCTAssertFalse(presentation.summary.contains("Source:"))
        XCTAssertFalse(presentation.summary.contains("..."))
        XCTAssertFalse(presentation.standfirst.isEmpty)
        XCTAssertGreaterThanOrEqual(presentation.bullets.count, 2)
        XCTAssertFalse(presentation.paragraphs.isEmpty)
        XCTAssertTrue(presentation.keywords.map(\.title).contains("NATO"))
    }

    func testResearchNewsParserPreservesFullSummaryParagraphs() throws {
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-26", artifacts: [
            Self.artifact(id: "tech-run", type: .run, topic: "tech-news", path: "research/tech-news/runs/2026-06-26.md", date: "2026-06-26")
        ])
        let markdown = """
        # Daily Research Report: tech-news
        Date: 2026-06-26
        Status: Material update

        ## Podsumowanie
        Pierwszy akapit opisuje najważniejsze sygnały AI i LLM z porannego przeglądu.

        Drugi akapit dopowiada, co zmieniło się w infrastrukturze i kosztach inference.

        Trzeci akapit pokazuje wpływ na produkty oraz regulacje.

        Czwarty akapit nie może zostać zgubiony, bo zawiera wniosek redakcyjny dla użytkownika.

        ## Nowe fakty
        - OpenAI i Cloudflare aktualizują narzędzia AI dla agentów. Źródła: [OpenAI](https://openai.com/news), [Cloudflare](https://blog.cloudflare.com/news).

        ## Źródła
        - [OpenAI](https://openai.com/news)
        """

        let issue = try ResearchNewsParser().parse(markdown, package: package)
        let presentation = ResearchIssuePresentation(issue: issue)

        XCTAssertTrue(issue.lead.contains("Pierwszy akapit"))
        XCTAssertTrue(issue.lead.contains("Czwarty akapit nie może zostać zgubiony"))
        XCTAssertTrue(issue.lead.contains("\n\nDrugi akapit"))
        XCTAssertTrue(presentation.lead.contains("Czwarty akapit nie może zostać zgubiony"))
        XCTAssertGreaterThanOrEqual(presentation.leadParagraphs.count, 3)
        XCTAssertLessThanOrEqual(presentation.leadParagraphs.count, 4)
        XCTAssertFalse(presentation.lead.hasSuffix("..."))
    }

    func testResearchArticlePresentationBuildsMagazineBlocksWithoutHardEllipsis() throws {
        let article = ResearchNewsArticle(
            id: "magazine-card",
            title: "OpenAI i Cloudflare aktualizują narzędzia agentowe",
            section: .produkty,
            body: "OpenAI i Cloudflare pokazują nowe narzędzia dla agentów w produktach webowych. Zmiana dotyczy zarówno doświadczenia użytkownika, jak i bezpieczeństwa integracji.\n\nDrugi akapit opisuje praktyczny wpływ na zespoły produktowe oraz deweloperów aplikacji.",
            summary: "OpenAI i Cloudflare pokazują nowe narzędzia dla agentów.",
            sources: [
                ResearchNewsSource(title: "OpenAI", url: "https://openai.com/news"),
                ResearchNewsSource(title: "Cloudflare", url: "https://blog.cloudflare.com/news")
            ],
            priority: "High",
            tags: ["AI", "Cloudflare"]
        )

        let presentation = ResearchArticlePresentation(article: article, topic: .techNews)

        XCTAssertTrue(presentation.title.contains("OpenAI"))
        XCTAssertTrue(presentation.standfirst.contains("nowe narzędzia"))
        XCTAssertGreaterThanOrEqual(presentation.bullets.count, 3)
        XCTAssertEqual(presentation.paragraphs.count, 2)
        XCTAssertFalse(presentation.summary.contains("..."))
        XCTAssertFalse(presentation.bullets.joined(separator: " ").contains("..."))
    }

    func testSavedResearchArticleStorePersistsRemovesAndSortsArticles() throws {
        let suiteName = "SavedResearchArticleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let olderArticle = ResearchNewsArticle(
            id: "polska-1",
            title: "Polska aktualizuje decyzje bezpieczeństwa",
            section: .polska,
            body: "Pełny opis krajowego tematu.",
            summary: "Krótki opis krajowego tematu.",
            sources: [ResearchNewsSource(title: "Gov.pl", url: "https://www.gov.pl/")],
            priority: "High",
            tags: ["Polska", "Bezpieczeństwo"]
        )
        let newerArticle = ResearchNewsArticle(
            id: "swiat-1",
            title: "Świat reaguje na decyzje NATO",
            section: .swiat,
            body: "Pełny opis światowego tematu.",
            summary: "Krótki opis światowego tematu.",
            sources: [ResearchNewsSource(title: "NATO", url: "https://www.nato.int/")],
            priority: "High",
            tags: ["Świat", "NATO"]
        )
        let issue = ResearchNewsIssue(
            topic: .polskaSwiat,
            packageKey: "2026-06-26",
            date: "2026-06-26",
            time: "12:00",
            status: "Material update",
            lead: "Polska i świat",
            articles: [olderArticle, newerArticle],
            checkedSources: [],
            podcastTopics: [],
            reportArtifact: nil,
            pdfArtifact: nil,
            podcastBriefArtifact: nil,
            audioArtifact: nil
        )
        let store = SavedResearchArticleStore(defaults: defaults)

        store.save(article: olderArticle, issue: issue, savedAt: Self.date("2026-06-26T10:00:00Z"))
        store.save(article: newerArticle, issue: issue, savedAt: Self.date("2026-06-26T11:00:00Z"))

        XCTAssertTrue(store.isSaved(article: olderArticle, issue: issue))
        XCTAssertEqual(store.savedArticles.map(\.article.title), ["Świat reaguje na decyzje NATO", "Polska aktualizuje decyzje bezpieczeństwa"])
        XCTAssertEqual(store.filteredArticles(section: .polska).map(\.article.id), ["polska-1"])

        store.remove(article: olderArticle, issue: issue)

        XCTAssertFalse(store.isSaved(article: olderArticle, issue: issue))
        XCTAssertEqual(store.savedArticles.map(\.article.id), ["swiat-1"])
    }

    func testDecodesResearchDataReportAndBuildsNativeIssue() throws {
        let report = try JSONDecoder.pavbot.decode(ResearchDataReport.self, from: Self.researchDataFixtureData)
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [
            Self.artifact(id: "tech-data", type: .researchData, topic: "tech-news", path: "research/tech-news/data/2026-06-25-research.json", date: "2026-06-25"),
            Self.artifact(id: "tech-run", type: .run, topic: "tech-news", path: "research/tech-news/runs/2026-06-25.md", date: "2026-06-25"),
            Self.artifact(id: "tech-pdf", type: .pdf, topic: "tech-news", path: "research/tech-news/pdfs/2026-06-25-tech-news.pdf", date: "2026-06-25")
        ])

        let issue = try report.nativeIssue(package: package)

        XCTAssertEqual(issue.topic, .techNews)
        XCTAssertEqual(issue.date, "2026-06-25")
        XCTAssertEqual(issue.articles.count, 1)
        XCTAssertEqual(issue.articles[0].section, .ai)
        XCTAssertEqual(issue.articles[0].whatHappened, "OpenAI i Cloudflare pokazują nowe narzędzia agentowe.")
        XCTAssertEqual(issue.articles[0].whyItMatters, "To ważne, bo przyspiesza praktyczne wdrożenia AI.")
        XCTAssertEqual(issue.pdfArtifact?.id, "tech-pdf")
    }

    func testResearchArticlePresentationUsesStructuredAnalysisWhenAvailable() throws {
        let report = try JSONDecoder.pavbot.decode(ResearchDataReport.self, from: Self.researchDataFixtureData)
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [])
        let issue = try report.nativeIssue(package: package)
        let article = try XCTUnwrap(issue.articles.first)

        let presentation = ResearchArticlePresentation(article: article, topic: .techNews)

        XCTAssertTrue(presentation.summary.contains("OpenAI i Cloudflare pokazują nowe narzędzia agentowe."))
        XCTAssertTrue(presentation.summary.contains("przyspiesza praktyczne wdrożenia AI"))
        XCTAssertEqual(presentation.bullets.first, "Co się stało: OpenAI i Cloudflare aktualizują warstwę agentową.")
        XCTAssertTrue(presentation.paragraphs.contains("Głębszy opis pokazuje wpływ na produkty, integracje i bezpieczeństwo agentów."))
        XCTAssertEqual(presentation.deeperAnalysis.count, 2)
    }

    func testResearchIssuePresentationBuildsPremiumPolskaSwiatBrief() throws {
        let package = TopicReportPackage(topic: .polskaSwiat, key: "2026-06-25", artifacts: [
            Self.artifact(id: "polska-run", type: .run, topic: "polska-swiat", path: "research/polska-swiat/runs/2026-06-25.md", date: "2026-06-25")
        ])
        let issue = try ResearchNewsParser().parse(Self.polskaSwiatResearchMarkdownFixture, package: package)

        let presentation = ResearchIssuePresentation(issue: issue)

        XCTAssertEqual(presentation.eyebrow, "Przegląd wydarzeń dnia")
        XCTAssertTrue(presentation.lead.contains("Polska i świat"))
        XCTAssertGreaterThanOrEqual(presentation.signals.count, 2)

        let keywords = presentation.keywords.map(\.title)
        XCTAssertTrue(keywords.contains("Polska"))
        XCTAssertTrue(keywords.contains("NATO"))
        XCTAssertTrue(keywords.contains("Bezpieczeństwo"))
    }

    func testResearchKeywordHighlighterPreservesTextAndHighlightsPolishKeywords() throws {
        let text = "Polska, NATO i AI wzmacniają bezpieczeństwo oraz gospodarkę."
        let keywords = [
            ResearchIssueKeyword(title: "Polska", kind: .region),
            ResearchIssueKeyword(title: "NATO", kind: .source),
            ResearchIssueKeyword(title: "AI", kind: .technology),
            ResearchIssueKeyword(title: "bezpieczeństwo", kind: .section),
            ResearchIssueKeyword(title: "gospodarka", kind: .section)
        ]

        let attributed = ResearchKeywordHighlighter.attributedText(text, keywords: keywords, tint: .blue)

        XCTAssertEqual(String(attributed.characters), text)
        XCTAssertGreaterThanOrEqual(ResearchKeywordHighlighter.highlightedRanges(in: text, keywords: keywords).count, 5)
    }

    func testResearchKeywordHighlighterAvoidsAccidentalSubstringMatches() throws {
        let text = "Mainstream cloudflarex nie jest Cloudflare, a OpenAI nie powinno podkreślać samego AI w środku nazwy."
        let keywords = [
            ResearchIssueKeyword(title: "Cloudflare", kind: .technology),
            ResearchIssueKeyword(title: "AI", kind: .technology),
            ResearchIssueKeyword(title: "OpenAI", kind: .technology)
        ]

        let ranges = ResearchKeywordHighlighter.highlightedRanges(in: text, keywords: keywords)
        let matches = ranges.map { String(text[$0]) }

        XCTAssertEqual(matches, ["Cloudflare", "OpenAI", "AI"])
        XCTAssertFalse(matches.contains("cloudflarex"))
    }

    func testResearchIssuePresentationUsesLeadFallbackWhenLeadIsEmpty() throws {
        let issue = ResearchNewsIssue(
            topic: .techNews,
            packageKey: "empty",
            date: "2026-06-25",
            time: nil,
            status: "No material change",
            lead: "",
            articles: [],
            checkedSources: [],
            podcastTopics: [],
            reportArtifact: nil,
            pdfArtifact: nil,
            podcastBriefArtifact: nil,
            audioArtifact: nil
        )

        let presentation = ResearchIssuePresentation(issue: issue)

        XCTAssertEqual(presentation.lead, "Wydanie jest gotowe do przeglądu w aplikacji Pavbot.")
        XCTAssertFalse(presentation.signals.isEmpty)
        XCTAssertFalse(presentation.keywords.isEmpty)
    }

    func testResearchIssuePresentationDoesNotHardClipLongLead() throws {
        let longLead = Array(repeating: "Pełne podsumowanie opisuje konkretne wnioski z przeszukiwania sieci dla AI, infrastruktury i produktów.", count: 9)
            .joined(separator: " ")
        let article = ResearchNewsArticle(
            id: "long-lead-ai",
            title: "OpenAI i Cloudflare pokazują nowe sygnały",
            section: .ai,
            body: "OpenAI i Cloudflare pojawiają się jako główne wątki.",
            summary: "OpenAI i Cloudflare pojawiają się jako główne wątki.",
            sources: [],
            priority: "1",
            tags: ["AI", "Cloudflare"]
        )
        let issue = ResearchNewsIssue(
            topic: .techNews,
            packageKey: "long-lead",
            date: "2026-06-25",
            time: nil,
            status: "Research update",
            lead: longLead,
            articles: [article],
            checkedSources: [],
            podcastTopics: [],
            reportArtifact: nil,
            pdfArtifact: nil,
            podcastBriefArtifact: nil,
            audioArtifact: nil
        )

        let presentation = ResearchIssuePresentation(issue: issue)

        XCTAssertTrue(presentation.lead.contains(longLead))
        XCTAssertFalse(presentation.lead.hasSuffix("..."))
        XCTAssertGreaterThan(presentation.lead.count, 700)
    }

    @MainActor
    func testResearchNewsStoreChoosesNewestPackageAndCachesAfterRefreshFailure() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = ResearchNewsCache(defaults: defaults)
        let run = Self.artifact(id: "tech-run", type: .run, topic: "tech-news", path: "research/tech-news/runs/2026-06-25.md", date: "2026-06-25")
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [run])
        let store = ResearchNewsStore(
            client: ResearchNewsClient(fetchText: { _ in Self.techResearchMarkdownFixture }),
            cache: cache
        )

        await store.load(
            packages: [package],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            topic: .techNews,
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.issue?.date, "2026-06-25")
        XCTAssertEqual(store.selectedPackage?.key, "2026-06-25")

        let failingStore = ResearchNewsStore(
            client: ResearchNewsClient(fetchText: { _ in throw URLError(.notConnectedToInternet) }),
            cache: cache
        )

        await failingStore.load(
            packages: [package],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            topic: .techNews,
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(failingStore.state, .loaded)
        XCTAssertEqual(failingStore.issue?.date, "2026-06-25")
        XCTAssertEqual(failingStore.cacheNotice, "Pokazuję ostatnie zapisane wydanie Research. Odświeżenie nie powiodło się.")
    }

    @MainActor
    func testResearchNewsStorePrefersResearchDataArtifactOverMarkdownFallback() async throws {
        let dataArtifact = Self.artifact(
            id: "tech-data",
            type: .researchData,
            topic: "tech-news",
            path: "research/tech-news/data/2026-06-25-research.json",
            date: "2026-06-25"
        )
        let markdownArtifact = Self.artifact(
            id: "tech-run",
            type: .run,
            topic: "tech-news",
            path: "research/tech-news/runs/2026-06-25.md",
            date: "2026-06-25"
        )
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [dataArtifact, markdownArtifact])
        let store = ResearchNewsStore(
            client: ResearchNewsClient(
                fetchData: { _ in Self.researchDataFixtureData },
                fetchText: { _ in XCTFail("Markdown fallback should not be fetched when researchData exists"); return Self.techResearchMarkdownFixture }
            ),
            cache: ResearchNewsCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )

        await store.load(
            packages: [package],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            topic: .techNews,
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.issue?.articles.first?.whatHappened, "OpenAI i Cloudflare pokazują nowe narzędzia agentowe.")
        XCTAssertEqual(store.selectedPackage?.researchDataArtifact?.id, "tech-data")
    }

    @MainActor
    func testResearchNewsStoreFallsBackToMarkdownWhenResearchDataFails() async throws {
        let dataArtifact = Self.artifact(
            id: "broken-tech-data",
            type: .researchData,
            topic: "tech-news",
            path: "research/tech-news/data/2026-06-25-research.json",
            date: "2026-06-25"
        )
        let markdownArtifact = Self.artifact(
            id: "tech-run",
            type: .run,
            topic: "tech-news",
            path: "research/tech-news/runs/2026-06-25.md",
            date: "2026-06-25"
        )
        let package = TopicReportPackage(topic: .techNews, key: "2026-06-25", artifacts: [dataArtifact, markdownArtifact])
        let store = ResearchNewsStore(
            client: ResearchNewsClient(
                fetchData: { _ in throw URLError(.badServerResponse) },
                fetchText: { _ in Self.techResearchMarkdownFixture }
            ),
            cache: ResearchNewsCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )

        await store.load(
            packages: [package],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            topic: .techNews,
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertNil(store.issue?.articles.first?.whatHappened)
        XCTAssertEqual(store.issue?.articles.first?.section, .infrastruktura)
    }

    func testDecodesMobileNewsMagazineForNativeAktualneUI() throws {
        let magazine = try JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: Self.mobileNewsDataFixtureData)

        XCTAssertEqual(magazine.schemaVersion, 1)
        XCTAssertEqual(magazine.topic, "aktualne-wydarzenia-mobile")
        XCTAssertEqual(magazine.runDate, "2026-06-25")
        XCTAssertEqual(magazine.runTime, "10:15")
        XCTAssertEqual(magazine.sections.count, 4)
        XCTAssertEqual(magazine.sections[0].title, "Polska")
        XCTAssertEqual(magazine.sections[0].articles[0].title, "Gdańsk jako centrum rozmów")
        XCTAssertTrue(magazine.sections[0].articles[0].ttsText.contains("Polska jest gospodarzem ważnych rozmów"))
        XCTAssertFalse(magazine.sections[0].articles[0].ttsText.contains("https://"))
        XCTAssertEqual(magazine.articleCount, 5)
    }

    func testMobileNewsDataArtifactIsGroupedInAktualneReportPackages() throws {
        let manifest = try manifestWithAdditionalArtifacts([
            Self.artifact(
                id: "mobile-data",
                type: .mobileNewsData,
                topic: "aktualne-wydarzenia-mobile",
                path: "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json",
                date: "2026-06-25",
                time: "10:15"
            ),
            Self.artifact(
                id: "mobile-pdf",
                type: .pdf,
                topic: "aktualne-wydarzenia-mobile",
                path: "research/aktualne-wydarzenia-mobile/pdfs/2026-06-25-1015-mobile-brief.pdf",
                date: "2026-06-25",
                time: "10:15"
            ),
            Self.artifact(
                id: "mobile-audio",
                type: .podcastAudioVariant,
                topic: "aktualne-wydarzenia-mobile",
                path: "research/aktualne-wydarzenia-mobile/podcasts/2026-06-25-1015/audio/female-piper/podcast.mp3",
                date: "2026-06-25",
                time: "10:15"
            ),
            Self.artifact(
                id: "mobile-script",
                type: .podcastScript,
                topic: "aktualne-wydarzenia-mobile",
                path: "research/aktualne-wydarzenia-mobile/podcasts/2026-06-25-1015/script.md",
                date: "2026-06-25",
                time: "10:15"
            )
        ])

        let packages = manifest.reportPackages(for: .aktualne)

        XCTAssertEqual(ReportTopicKind(topic: "aktualne-wydarzenia-mobile"), .aktualne)
        XCTAssertEqual(packages.count, 1)
        XCTAssertEqual(packages[0].mobileNewsDataArtifact?.id, "mobile-data")
        XCTAssertEqual(packages[0].pdfReport?.id, "mobile-pdf")
        XCTAssertEqual(packages[0].primaryAudio?.id, "mobile-audio")
        XCTAssertEqual(packages[0].podcastScript?.id, "mobile-script")
        XCTAssertEqual(packages[0].preferredPreviewArtifact?.id, "mobile-data")
    }

    @MainActor
    func testMobileNewsStorePrefersMobileNewsDataArtifact() async throws {
        let dataArtifact = Self.artifact(
            id: "mobile-data",
            type: .mobileNewsData,
            topic: "aktualne-wydarzenia-mobile",
            path: "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json",
            date: "2026-06-25",
            time: "10:15"
        )
        let pdfArtifact = Self.artifact(
            id: "mobile-pdf",
            type: .pdf,
            topic: "aktualne-wydarzenia-mobile",
            path: "research/aktualne-wydarzenia-mobile/pdfs/2026-06-25-1015-mobile-brief.pdf",
            date: "2026-06-25",
            time: "10:15"
        )
        let package = TopicReportPackage(topic: .aktualne, key: "2026-06-25-1015", artifacts: [dataArtifact, pdfArtifact])
        let store = MobileNewsStore(
            client: MobileNewsClient(fetchData: { _ in Self.mobileNewsDataFixtureData }),
            cache: MobileNewsCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )

        await store.load(
            packages: [package],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.magazine?.headline, "Wydanie dnia")
        XCTAssertEqual(store.selectedPackage?.mobileNewsDataArtifact?.id, "mobile-data")
        XCTAssertEqual(store.magazine?.pdfArtifact?.id, "mobile-pdf")
    }

    @MainActor
    func testMobileNewsSpeechControllerTracksPerArticlePlaybackState() throws {
        let magazine = try JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: Self.mobileNewsDataFixtureData)
        let article = try XCTUnwrap(magazine.sections.first?.articles.first)
        let controller = MobileNewsSpeechController(enableSpeech: false, rateDefaults: UserDefaults(suiteName: UUID().uuidString)!)

        controller.speak(article)

        XCTAssertEqual(controller.currentArticleID, article.id)
        XCTAssertTrue(controller.isSpeaking)
        XCTAssertFalse(controller.isPaused)

        controller.pause()

        XCTAssertEqual(controller.currentArticleID, article.id)
        XCTAssertTrue(controller.isPaused)

        controller.stop()

        XCTAssertNil(controller.currentArticleID)
        XCTAssertFalse(controller.isSpeaking)
        XCTAssertFalse(controller.isPaused)
    }

    @MainActor
    func testSpeechPlaybackIgnoresDelayedCancelFromPreviousSession() async throws {
        let service = SpeechPlaybackService(enableSpeech: false, rateDefaults: UserDefaults(suiteName: UUID().uuidString)!)

        service.start(itemID: "article-a", title: "Pierwszy artykuł", text: "Pierwszy tekst do odczytania.")
        service.start(itemID: "article-b", title: "Drugi artykuł", text: "Drugi tekst do odczytania.")

        service.speechSynthesizer(AVSpeechSynthesizer(), didCancel: AVSpeechUtterance(string: "Stary tekst"))
        await Task.yield()

        XCTAssertEqual(service.currentItemID, "article-b")
        XCTAssertTrue(service.isSpeaking)
        XCTAssertFalse(service.isPaused)
        XCTAssertNil(service.errorMessage)
    }

    @MainActor
    func testSpeechPlaybackStopIgnoresLaterCancelCallbacks() async throws {
        let service = SpeechPlaybackService(enableSpeech: false, rateDefaults: UserDefaults(suiteName: UUID().uuidString)!)

        service.start(itemID: "article-a", title: "Artykuł", text: "Tekst do odczytania.")
        service.stop()
        service.speechSynthesizer(AVSpeechSynthesizer(), didCancel: AVSpeechUtterance(string: "Tekst do odczytania."))
        await Task.yield()

        XCTAssertNil(service.currentItemID)
        XCTAssertFalse(service.isSpeaking)
        XCTAssertFalse(service.isPaused)
        XCTAssertNil(service.timeline)
    }

    @MainActor
    func testMobileNewsSpeechRatePersistsAndRestartsCurrentArticle() throws {
        let magazine = try JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: Self.mobileNewsDataFixtureData)
        let article = try XCTUnwrap(magazine.sections.first?.articles.first)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = MobileNewsSpeechController(enableSpeech: false, rateDefaults: defaults)

        XCTAssertEqual(controller.speechRate, .normal)
        XCTAssertEqual(controller.utteranceRate(for: .normal), AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.0001)

        controller.speak(article)
        controller.setSpeechRate(.fast)

        XCTAssertEqual(controller.speechRate, .fast)
        XCTAssertEqual(MobileNewsSpeechRate.saved(in: defaults), .fast)
        XCTAssertEqual(controller.currentArticleID, article.id)
        XCTAssertTrue(controller.isSpeaking)
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(controller.utteranceRate(for: .fast), AVSpeechUtteranceDefaultSpeechRate * 1.11, accuracy: 0.0001)
    }

    @MainActor
    func testSpeechRateChangePreservesActivePlaybackProgress() throws {
        let service = SpeechPlaybackService(enableSpeech: false, rateDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let text = """
        Pierwszy akapit ma wystarczająco dużo słów, żeby symulować czytanie w środku fragmentu bez cofania do początku po zmianie tempa.

        Drugi akapit sprawdza, czy wybór segmentu nadal wynika z aktualnego postępu całego tekstu.
        """

        service.start(itemID: "article-a", title: "Artykuł", text: text)
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        let elapsedBeforeRateChange = service.estimatedElapsed
        XCTAssertGreaterThan(elapsedBeforeRateChange, 0)

        service.setSpeechRate(.fast)

        XCTAssertEqual(service.currentItemID, "article-a")
        XCTAssertEqual(service.speechRate, .fast)
        XCTAssertTrue(service.isSpeaking)
        XCTAssertFalse(service.isPaused)
        XCTAssertGreaterThanOrEqual(service.estimatedElapsed, elapsedBeforeRateChange * 0.9)
    }

    @MainActor
    func testSpeechRateChangeWhilePausedKeepsPausedStateAndPlace() throws {
        let service = SpeechPlaybackService(enableSpeech: false, rateDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let text = """
        Pierwszy fragment do lokalnego TTS.

        Drugi fragment ma pozostać wybrany po zmianie tempa w pauzie.
        """

        service.start(itemID: "article-a", title: "Artykuł", text: text)
        service.seek(toProgress: 0.65)
        let segmentBeforeRateChange = service.currentSegmentIndex
        let elapsedBeforeRateChange = service.estimatedElapsed
        service.pause()

        service.setSpeechRate(.slow)

        XCTAssertEqual(service.currentItemID, "article-a")
        XCTAssertEqual(service.speechRate, .slow)
        XCTAssertTrue(service.isPaused)
        XCTAssertEqual(service.currentSegmentIndex, segmentBeforeRateChange)
        XCTAssertEqual(service.estimatedElapsed, elapsedBeforeRateChange, accuracy: 0.0001)
    }

    func testSpeechTimelineBuildsSeekableTextSegments() throws {
        let text = """
        Pierwszy akapit opisuje najważniejszy temat dnia i ma być jednym fragmentem.

        Drugi akapit rozwija kontekst oraz pokazuje odbiorcy kolejne fakty.

        Trzeci akapit zamyka materiał rekomendacją.
        """

        let timeline = SpeechTimeline(text: text, wordsPerMinute: 150)

        XCTAssertEqual(timeline.segments.count, 3)
        XCTAssertEqual(timeline.segments[0].index, 0)
        XCTAssertTrue(timeline.estimatedDuration > 0)
        XCTAssertEqual(timeline.segmentIndex(forProgress: 0), 0)
        XCTAssertEqual(timeline.segmentIndex(forProgress: 0.55), 1)
        XCTAssertEqual(timeline.segmentIndex(forProgress: 1), 2)
        XCTAssertTrue(timeline.progress(forSegmentIndex: 1) > 0)
    }

    @MainActor
    func testMobileNewsSpeechConfiguresAudioSessionAndCanSeekToSegment() throws {
        let magazine = try JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: Self.mobileNewsDataFixtureData)
        let article = try XCTUnwrap(magazine.sections.first?.articles.first)
        let spySession = SpySpeechAudioSession()
        let controller = MobileNewsSpeechController(
            enableSpeech: false,
            audioSession: spySession,
            rateDefaults: UserDefaults(suiteName: UUID().uuidString)!
        )

        controller.speak(article)

        XCTAssertEqual(spySession.activateCount, 1)
        XCTAssertEqual(controller.currentArticleID, article.id)
        XCTAssertNotNil(controller.timeline)
        XCTAssertEqual(controller.currentSegmentIndex, 0)

        controller.seek(toSegmentIndex: 1)

        XCTAssertEqual(controller.currentArticleID, article.id)
        XCTAssertEqual(controller.currentSegmentIndex, min(1, max((controller.timeline?.segments.count ?? 1) - 1, 0)))
        XCTAssertTrue(controller.estimatedDuration > 0)
    }

    @MainActor
    func testPodcastScriptSpeechConfiguresAudioSessionAndSupportsTimelineSeek() async throws {
        let artifact = Self.artifact(
            id: "mobile-script",
            type: .podcastScript,
            topic: "aktualne-wydarzenia-mobile",
            path: "research/aktualne-wydarzenia-mobile/podcasts/2026-06-25-1015/script.md",
            date: "2026-06-25",
            time: "10:15"
        )
        let spySession = SpySpeechAudioSession()
        let controller = PodcastScriptSpeechController(
            client: PodcastScriptSpeechClient(fetchText: { _ in
                """
                # Script

                Pierwszy akapit podcastu do odsłuchu.

                Drugi akapit podcastu z rozwinięciem tematu.
                """
            }),
            enableSpeech: false,
            audioSession: spySession,
            rateDefaults: UserDefaults(suiteName: UUID().uuidString)!
        )

        await controller.playOrToggle(artifact: artifact, url: URL(string: "https://example.com/script.md")!)

        XCTAssertEqual(spySession.activateCount, 1)
        XCTAssertEqual(controller.currentArtifactID, artifact.id)
        XCTAssertEqual(controller.timeline?.segments.count, 2)

        controller.seek(toProgress: 1)

        XCTAssertEqual(controller.currentSegmentIndex, 1)
        XCTAssertTrue(controller.estimatedDuration > 0)
    }

    @MainActor
    func testPodcastScriptSpeechCanLoadTranscriptWithoutStartingPlayback() async throws {
        let artifact = Self.artifact(
            id: "mobile-script",
            type: .podcastScript,
            topic: "aktualne-wydarzenia-mobile",
            path: "research/aktualne-wydarzenia-mobile/podcasts/2026-06-25-1015/script.md",
            date: "2026-06-25",
            time: "10:15"
        )
        let controller = PodcastScriptSpeechController(
            client: PodcastScriptSpeechClient(fetchText: { _ in
                """
                # Podcast script

                Pierwszy akapit do transkrypcji.

                Drugi akapit bez markdown.
                """
            }),
            enableSpeech: false,
            rateDefaults: UserDefaults(suiteName: UUID().uuidString)!
        )

        await controller.loadTranscript(artifact: artifact, url: URL(string: "https://example.com/script.md")!)

        XCTAssertEqual(controller.transcriptArtifactID, artifact.id)
        XCTAssertEqual(controller.currentTranscriptText, "Pierwszy akapit do transkrypcji.\n\nDrugi akapit bez markdown.")
        XCTAssertFalse(controller.hasActivePlayback)
        XCTAssertNil(controller.currentArtifactID)
    }

    func testPodcastScriptSpeechTextCleansMarkdownForLocalTTS() throws {
        let markdown = """
        # Podcast script

        [Prowadzący] Dzień dobry.

        ## Polska
        - Pierwszy temat opisuje sytuację bez czytania surowych linków.
        - Źródło: [Gov.pl](https://www.gov.pl/test)

        Więcej kontekstu dla słuchacza.
        """

        let speechText = PodcastScriptSpeechText.clean(markdown)

        XCTAssertTrue(speechText.contains("Dzień dobry."))
        XCTAssertTrue(speechText.contains("Pierwszy temat opisuje sytuację"))
        XCTAssertTrue(speechText.contains("Gov.pl"))
        XCTAssertFalse(speechText.contains("https://"))
        XCTAssertFalse(speechText.contains("##"))
        XCTAssertFalse(speechText.contains("- "))
    }

    @MainActor
    func testRouterStartsOnTodayTab() {
        let router = AppRouter()

        XCTAssertEqual(router.selectedTab, .today)
    }

    @MainActor
    func testRouterRoutesAktualneNotificationToResearchAktualneTab() {
        let router = AppRouter()

        router.handleNotification(
            userInfo: [
                "artifactTopic": "aktualne-wydarzenia-mobile",
                "artifactDate": "2026-06-25",
                "artifactIDs": ["mobile-data"]
            ]
        )

        XCTAssertEqual(router.selectedTab, .research)
        XCTAssertEqual(router.selectedResearchTopic, .aktualne)
        XCTAssertEqual(router.selectedReportDay, "2026-06-25")
        XCTAssertEqual(router.selectedReportArtifactIDs, ["mobile-data"])
    }

    func testDecodesJobsReportDataForNativeJobsUI() throws {
        let report = try JSONDecoder.pavbot.decode(JobsReport.self, from: Self.jobsDataFixtureData)

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.status, "Material update")
        XCTAssertEqual(report.runDate, "2026-06-25")
        XCTAssertEqual(report.runTime, "01:41")
        XCTAssertEqual(report.opportunities.count, 1)
        XCTAssertEqual(report.opportunities[0].company, "CKSource")
        XCTAssertEqual(report.opportunities[0].workMode, "Remote")
        XCTAssertEqual(report.opportunities[0].tags, ["LLM", "Agentic AI"])
        XCTAssertEqual(report.checkedSources[0].title, "CKSource careers")
    }

    func testJobsBriefPresentationBuildsPremiumEditorialSummary() throws {
        let report = try JSONDecoder.pavbot.decode(JobsReport.self, from: Self.jobsDataFixtureData)

        let presentation = JobsBriefPresentation(report: report)

        XCTAssertEqual(presentation.title, "Brief dnia")
        XCTAssertTrue(presentation.lead.contains("rynek AI/LLM"))
        XCTAssertGreaterThanOrEqual(presentation.signals.count, 2)
        XCTAssertEqual(presentation.primaryRecommendation, "Sprawdzić status w kolejnej rundzie")
        XCTAssertLessThanOrEqual(presentation.secondaryRecommendations.count, 2)

        let keywords = presentation.keywords.map(\.title)
        XCTAssertTrue(keywords.contains("CKSource"))
        XCTAssertTrue(keywords.contains("Remote"))
        XCTAssertTrue(keywords.contains("Principal"))
        XCTAssertTrue(keywords.contains("LLM"))
        XCTAssertTrue(keywords.contains("38 000-45 000 PLN"))
    }

    func testJobsBriefPresentationUsesActionFallbackWhenRecommendationsAreMissing() throws {
        let report = JobsReport(
            schemaVersion: 1,
            status: "No material change",
            runDate: "2026-06-25",
            runTime: "07:30",
            executiveSummary: "Rynek AI/LLM bez istotnych nowych zmian.",
            opportunities: [],
            changes: [],
            risks: [],
            recommendedActions: [],
            checkedSources: []
        )

        let presentation = JobsBriefPresentation(report: report)

        XCTAssertEqual(presentation.primaryRecommendation, "Przejrzyj top oferty i zapisz role do obserwacji.")
        XCTAssertGreaterThanOrEqual(presentation.signals.count, 2)
    }

    func testJobsKeywordHighlighterPreservesTextAndFindsPolishKeywords() throws {
        let text = "Wrocław i CKSource pokazują Remote LLM/RAG z budżetem 38 000 PLN."
        let keywords = [
            JobsBriefKeyword(title: "Wrocław", kind: .location),
            JobsBriefKeyword(title: "CKSource", kind: .company),
            JobsBriefKeyword(title: "Remote", kind: .workMode),
            JobsBriefKeyword(title: "LLM", kind: .technology),
            JobsBriefKeyword(title: "RAG", kind: .technology),
            JobsBriefKeyword(title: "38 000 PLN", kind: .compensation)
        ]

        let attributed = JobsKeywordHighlighter.attributedText(text, keywords: keywords)

        XCTAssertEqual(String(attributed.characters), text)
        XCTAssertGreaterThanOrEqual(JobsKeywordHighlighter.highlightedRanges(in: text, keywords: keywords).count, 5)
    }

    func testJobsMarkdownParserBuildsNativeReportFromExistingMarkdown() throws {
        let report = try JobsMarkdownParser().parse(Self.jobsMarkdownFixture)

        XCTAssertEqual(report.status, "Material update")
        XCTAssertEqual(report.runDate, "2026-06-25")
        XCTAssertEqual(report.runTime, "01:41")
        XCTAssertTrue(report.executiveSummary.contains("trzy materialne sygnały"))
        XCTAssertEqual(report.opportunities.count, 2)
        XCTAssertEqual(report.opportunities[0].company, "CKSource / Tiugo Technologies")
        XCTAssertEqual(report.opportunities[0].title, "Principal Applied AI Engineer")
        XCTAssertEqual(report.opportunities[0].workMode, "Remote")
        XCTAssertEqual(report.opportunities[0].compensation, "38 000-45 000 PLN B2B miesięcznie.")
        XCTAssertTrue(report.opportunities[0].tags.contains("Agentic AI"))
        XCTAssertEqual(report.opportunities[1].company, "Accenture")
        XCTAssertEqual(report.checkedSources.count, 2)
    }

    func testJobsMarkdownParserBuildsNativeReportFromEnglishHeadings() throws {
        let report = try JobsMarkdownParser().parse(Self.jobsEnglishMarkdownFixture)

        XCTAssertEqual(report.status, "Material update")
        XCTAssertEqual(report.runDate, "2026-06-24")
        XCTAssertEqual(report.runTime, "19:21")
        XCTAssertTrue(report.executiveSummary.contains("materialny update"))
        XCTAssertEqual(report.opportunities.count, 2)
        XCTAssertEqual(report.opportunities[0].company, "EPAM")
        XCTAssertEqual(report.opportunities[0].title, "Lead AI Engineer")
        XCTAssertEqual(report.opportunities[0].workMode, "Remote")
        XCTAssertTrue(report.opportunities[0].tags.contains("RAG"))
        XCTAssertEqual(report.opportunities[1].company, "ACAISOFT")
        XCTAssertEqual(report.checkedSources.count, 2)
        XCTAssertEqual(report.recommendedActions.count, 1)
    }

    @MainActor
    func testJobsStorePrefersJobsDataArtifactOverMarkdownFallback() async throws {
        let dataArtifact = PavbotArtifact(
            id: "jobs-data",
            type: .jobsData,
            topic: "llm-ai-jobs-wroclaw",
            title: "Jobs data",
            path: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
            url: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
            sizeBytes: 200,
            date: "2026-06-25",
            time: "01:41"
        )
        let markdownArtifact = PavbotArtifact(
            id: "jobs-run",
            type: .run,
            topic: "llm-ai-jobs-wroclaw",
            title: "LLM/AI Jobs Wrocław",
            path: "research/llm-ai-jobs-wroclaw/runs/2026-06-25-0141.md",
            url: "research/llm-ai-jobs-wroclaw/runs/2026-06-25-0141.md",
            sizeBytes: 200,
            date: "2026-06-25",
            time: "01:41"
        )
        let package = TopicReportPackage(topic: .jobs, key: "2026-06-25-0141", artifacts: [dataArtifact, markdownArtifact])
        let client = JobsDataClient(
            fetchData: { _ in Self.jobsDataFixtureData },
            fetchText: { _ in XCTFail("Markdown fallback should not be fetched when jobsData exists"); return Self.jobsMarkdownFixture }
        )
        let store = JobsStore(client: client)

        await store.load(
            packages: [package],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.source, .jobsData)
        XCTAssertEqual(store.report?.opportunities.first?.company, "CKSource")
        XCTAssertEqual(store.selectedPackage?.dataArtifact?.id, "jobs-data")
    }

    @MainActor
    func testJobsStoreFallsBackToMarkdownWhenJobsDataIsMissing() async throws {
        let markdownArtifact = PavbotArtifact(
            id: "jobs-run",
            type: .run,
            topic: "llm-ai-jobs-wroclaw",
            title: "LLM/AI Jobs Wrocław",
            path: "research/llm-ai-jobs-wroclaw/runs/2026-06-25-0141.md",
            url: "research/llm-ai-jobs-wroclaw/runs/2026-06-25-0141.md",
            sizeBytes: 200,
            date: "2026-06-25",
            time: "01:41"
        )
        let package = TopicReportPackage(topic: .jobs, key: "2026-06-25-0141", artifacts: [markdownArtifact])
        let client = JobsDataClient(
            fetchData: { _ in XCTFail("jobsData should not be fetched when absent"); return Data() },
            fetchText: { _ in Self.jobsMarkdownFixture }
        )
        let store = JobsStore(client: client)

        await store.load(
            packages: [package],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.source, .markdownFallback)
        XCTAssertEqual(store.report?.opportunities.first?.company, "CKSource / Tiugo Technologies")
    }

    @MainActor
    func testJobsStoreFallsBackToNextPackageWhenNewestPackageCannotLoad() async throws {
        let brokenLatestData = PavbotArtifact(
            id: "broken-jobs-data",
            type: .jobsData,
            topic: "llm-ai-jobs-wroclaw",
            title: "Jobs data",
            path: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
            url: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
            sizeBytes: 200,
            date: "2026-06-25",
            time: "01:41"
        )
        let olderMarkdown = PavbotArtifact(
            id: "older-jobs-run",
            type: .run,
            topic: "llm-ai-jobs-wroclaw",
            title: "LLM/AI Jobs Wrocław",
            path: "research/llm-ai-jobs-wroclaw/runs/2026-06-24-1921.md",
            url: "research/llm-ai-jobs-wroclaw/runs/2026-06-24-1921.md",
            sizeBytes: 200,
            date: "2026-06-24",
            time: "19:21"
        )
        let packages = [
            TopicReportPackage(topic: .jobs, key: "2026-06-25-0141", artifacts: [brokenLatestData]),
            TopicReportPackage(topic: .jobs, key: "2026-06-24-1921", artifacts: [olderMarkdown])
        ]
        let client = JobsDataClient(
            fetchData: { _ in throw URLError(.badServerResponse) },
            fetchText: { _ in Self.jobsEnglishMarkdownFixture }
        )
        let store = JobsStore(client: client)

        await store.load(
            packages: packages,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.source, .markdownFallback)
        XCTAssertEqual(store.selectedPackage?.key, "2026-06-24-1921")
        XCTAssertEqual(store.report?.opportunities.first?.company, "EPAM")
    }

    @MainActor
    func testJobsStoreLoadsNewestPackageWhenSelectedDayIsStaleWithoutRouteArtifacts() async throws {
        let packages = [
            Self.jobsPackage(date: "2026-06-27", time: "01:41"),
            Self.jobsPackage(date: "2026-06-26", time: "17:41")
        ]
        let client = JobsDataClient(fetchData: { url in
            if url.absoluteString.contains("2026-06-27-0141") {
                return try Self.jobsHistoryData(
                    date: "2026-06-27",
                    time: "01:41",
                    company: "ITDS",
                    title: "Kubernetes & Cloud Infrastructure Engineer - AI Platform",
                    workMode: "Wrocław onsite",
                    sourceURL: "https://example.com/itds"
                )
            }
            return try Self.jobsHistoryData(
                date: "2026-06-26",
                time: "17:41",
                company: "Monterail",
                title: "LLM Engineer - Freelancer",
                workMode: "Remote",
                sourceURL: "https://example.com/monterail"
            )
        }, fetchText: { _ in
            XCTFail("Jobs data should be used for latest package")
            return Self.jobsMarkdownFixture
        })
        let store = JobsStore(client: client, cache: JobsReportCache(defaults: UserDefaults(suiteName: UUID().uuidString)!))

        await store.load(
            packages: packages,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: "2026-06-26",
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.selectedPackage?.key, "2026-06-27-0141")
        XCTAssertEqual(store.report?.runDate, "2026-06-27")
        XCTAssertEqual(store.report?.opportunities.first?.company, "ITDS")
    }

    @MainActor
    func testJobsStoreKeepsRouteArtifactSelectionEvenWhenNewerPackageExists() async throws {
        let newer = Self.jobsPackage(date: "2026-06-27", time: "01:41")
        let older = Self.jobsPackage(date: "2026-06-26", time: "17:41")
        let selectedArtifactID = try XCTUnwrap(older.dataArtifact?.id)
        let client = JobsDataClient(fetchData: { url in
            if url.absoluteString.contains("2026-06-26-1741") {
                return try Self.jobsHistoryData(
                    date: "2026-06-26",
                    time: "17:41",
                    company: "Monterail",
                    title: "LLM Engineer - Freelancer",
                    workMode: "Remote",
                    sourceURL: "https://example.com/monterail"
                )
            }
            return try Self.jobsHistoryData(
                date: "2026-06-27",
                time: "01:41",
                company: "ITDS",
                title: "Kubernetes & Cloud Infrastructure Engineer - AI Platform",
                workMode: "Wrocław onsite",
                sourceURL: "https://example.com/itds"
            )
        }, fetchText: { _ in
            XCTFail("Jobs data should be used for selected package")
            return Self.jobsMarkdownFixture
        })
        let store = JobsStore(client: client, cache: JobsReportCache(defaults: UserDefaults(suiteName: UUID().uuidString)!))

        await store.load(
            packages: [newer, older],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: "2026-06-27",
            selectedArtifactIDs: [selectedArtifactID]
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.selectedPackage?.key, "2026-06-26-1741")
        XCTAssertEqual(store.report?.opportunities.first?.company, "Monterail")
    }

    func testJobsReportCacheSavesEnvelopeMetadataAndReadsLegacyReport() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = JobsReportCache(defaults: defaults)
        let report = try JSONDecoder.pavbot.decode(JobsReport.self, from: Self.jobsDataFixtureData)

        cache.save(report, packageKey: "2026-06-25-0141", source: .jobsData)

        let cached = try XCTUnwrap(cache.load())
        XCTAssertEqual(cached.report.runDate, "2026-06-25")
        XCTAssertEqual(cached.report.runTime, "01:41")
        XCTAssertEqual(cached.packageKey, "2026-06-25-0141")
        XCTAssertEqual(cached.source, .jobsData)
        XCTAssertEqual(cached.reportDate, "2026-06-25")
        XCTAssertEqual(cached.reportTime, "01:41")
        XCTAssertNotNil(cached.cachedAt)

        let legacyDefaults = UserDefaults(suiteName: UUID().uuidString)!
        legacyDefaults.set(Self.jobsDataFixtureData, forKey: "pavbot.cachedJobsReport")
        let legacyCache = JobsReportCache(defaults: legacyDefaults)
        let legacy = try XCTUnwrap(legacyCache.load())

        XCTAssertEqual(legacy.report.runDate, "2026-06-25")
        XCTAssertNil(legacy.packageKey)
        XCTAssertNil(legacy.source)
        XCTAssertNil(legacy.cachedAt)
    }

    @MainActor
    func testJobsHistoryStoreLoadsAnchorDateAndTwoPreviousCalendarDays() async throws {
        let packages = [
            Self.jobsPackage(date: "2026-06-25", time: "17:41"),
            Self.jobsPackage(date: "2026-06-25", time: "01:41"),
            Self.jobsPackage(date: "2026-06-24", time: "19:21"),
            Self.jobsPackage(date: "2026-06-23", time: "17:41"),
            Self.jobsPackage(date: "2026-06-22", time: "01:41")
        ]
        let client = JobsDataClient(fetchData: { url in
            if url.absoluteString.contains("2026-06-22-0141") {
                return try Self.jobsHistoryData(date: "2026-06-22", time: "01:41", company: "OldCo", title: "Legacy AI Engineer", workMode: "Remote", sourceURL: "https://example.com/old")
            }
            if url.absoluteString.contains("2026-06-24-1921") {
                return try Self.jobsHistoryData(date: "2026-06-24", time: "19:21", company: "EPAM", title: "Lead AI Engineer", workMode: "Remote", sourceURL: "https://example.com/epam")
            }
            if url.absoluteString.contains("2026-06-23-1741") {
                return try Self.jobsHistoryData(date: "2026-06-23", time: "17:41", company: "ACAISOFT", title: "Python Engineer AI", workMode: "Remote", sourceURL: "https://example.com/acaisoft")
            }
            if url.absoluteString.contains("2026-06-25-1741") {
                return try Self.jobsHistoryData(date: "2026-06-25", time: "17:41", company: "CKSource", title: "Principal Applied AI Engineer", workMode: "Remote", sourceURL: "https://example.com/cksource")
            }
            return try Self.jobsHistoryData(date: "2026-06-25", time: "01:41", company: "Accenture", title: "Senior GenAI Engineer", workMode: "Hybrid", sourceURL: "https://example.com/accenture")
        }, fetchText: { _ in
            XCTFail("History store should prefer jobsData when it exists")
            return Self.jobsMarkdownFixture
        })
        let store = JobsHistoryStore(client: client)

        await store.load(
            packages: packages,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.snapshot?.includedDates, ["2026-06-25", "2026-06-24", "2026-06-23"])
        XCTAssertEqual(store.snapshot?.reportCount, 4)
        XCTAssertEqual(store.snapshot?.opportunities.count, 4)
        XCTAssertFalse(store.snapshot?.opportunities.contains { $0.opportunity.company == "OldCo" } ?? true)
    }

    func testJobsHistorySnapshotDropsSelectedDateOutsideLoadedWindow() {
        let snapshot = JobsHistorySnapshot(
            anchorDate: "2026-06-27",
            includedDates: ["2026-06-27", "2026-06-26", "2026-06-25"],
            reportCount: 3,
            failedPackageCount: 0,
            sourceBreakdown: [.jobsData: 3],
            opportunities: []
        )

        XCTAssertEqual(snapshot.validatedSelectedDate("2026-06-26"), "2026-06-26")
        XCTAssertNil(snapshot.validatedSelectedDate("2026-06-24"))
        XCTAssertNil(snapshot.validatedSelectedDate(nil))
    }

    @MainActor
    func testJobsHistoryStoreMergesDuplicateOpportunitiesAcrossReports() async throws {
        let packages = [
            Self.jobsPackage(date: "2026-06-25", time: "17:41"),
            Self.jobsPackage(date: "2026-06-24", time: "19:21")
        ]
        let client = JobsDataClient(fetchData: { url in
            let date = url.absoluteString.contains("2026-06-24") ? "2026-06-24" : "2026-06-25"
            let time = url.absoluteString.contains("2026-06-24") ? "19:21" : "17:41"
            return try Self.jobsHistoryData(
                date: date,
                time: time,
                company: "CKSource",
                title: "Principal Applied AI Engineer",
                workMode: "Remote",
                sourceURL: "https://example.com/cksource"
            )
        }, fetchText: { _ in Self.jobsMarkdownFixture })
        let store = JobsHistoryStore(client: client)

        await store.load(
            packages: packages,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil
        )

        let opportunity = try XCTUnwrap(store.snapshot?.opportunities.first)
        XCTAssertEqual(store.snapshot?.opportunities.count, 1)
        XCTAssertEqual(opportunity.occurrenceCount, 2)
        XCTAssertEqual(opportunity.firstSeen, "2026-06-24")
        XCTAssertEqual(opportunity.latestSeen, "2026-06-25")
        XCTAssertEqual(opportunity.reportDates, ["2026-06-25", "2026-06-24"])
        XCTAssertEqual(opportunity.sourceURLs, ["https://example.com/cksource"])
    }

    @MainActor
    func testJobsHistoryStoreKeepsLoadedReportsWhenOnePackageFailsAndFallsBackToMarkdown() async throws {
        let brokenData = Self.jobsPackage(date: "2026-06-25", time: "17:41")
        let markdownOnly = Self.jobsPackage(date: "2026-06-24", time: "19:21", includeData: false, includeRun: true)
        let client = JobsDataClient(fetchData: { _ in
            throw URLError(.badServerResponse)
        }, fetchText: { _ in
            Self.jobsEnglishMarkdownFixture
        })
        let store = JobsHistoryStore(client: client)

        await store.load(
            packages: [brokenData, markdownOnly],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.snapshot?.reportCount, 1)
        XCTAssertEqual(store.snapshot?.failedPackageCount, 1)
        XCTAssertEqual(store.snapshot?.opportunities.first?.opportunity.company, "EPAM")
        XCTAssertEqual(store.snapshot?.sourceBreakdown[.markdownFallback], 1)
    }

    @MainActor
    func testJobsHistorySnapshotFiltersBySearchFilterAndDate() async throws {
        let packages = [
            Self.jobsPackage(date: "2026-06-25", time: "17:41"),
            Self.jobsPackage(date: "2026-06-24", time: "19:21")
        ]
        let client = JobsDataClient(fetchData: { url in
            if url.absoluteString.contains("2026-06-24") {
                return try Self.jobsHistoryData(date: "2026-06-24", time: "19:21", company: "Accenture", title: "Senior GenAI Engineer", workMode: "Hybrid", sourceURL: "https://example.com/accenture")
            }
            return try Self.jobsHistoryData(date: "2026-06-25", time: "17:41", company: "CKSource", title: "Principal Applied AI Engineer", workMode: "Remote", sourceURL: "https://example.com/cksource")
        }, fetchText: { _ in Self.jobsMarkdownFixture })
        let store = JobsHistoryStore(client: client)

        await store.load(
            packages: packages,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil
        )

        let snapshot = try XCTUnwrap(store.snapshot)

        XCTAssertEqual(snapshot.filteredOpportunities(filter: .remote, date: nil, searchText: "CKSource").map(\.opportunity.company), ["CKSource"])
        XCTAssertEqual(snapshot.filteredOpportunities(filter: .all, date: "2026-06-24", searchText: "").map(\.opportunity.company), ["Accenture"])
        XCTAssertTrue(snapshot.filteredOpportunities(filter: .remote, date: "2026-06-24", searchText: "").isEmpty)
    }

    func testResearchAndPodcastKindsExposePdfOutputs() throws {
        XCTAssertEqual(AutomationKind.research.preferredArtifactTypes, [.researchData, .run, .pdf])
        XCTAssertEqual(AutomationKind.podcast.preferredArtifactTypes, [.podcastAudio, .podcastAudioVariant, .podcastScript, .podcastBriefPdf])
    }

    func testAutomationClientBriefProvidesMarketingCopyForEveryAutomationKind() {
        let expectedKeywords: [AutomationKind: String] = [
            .research: "źródłach",
            .podcast: "briefing do odsłuchu",
            .researchAudio: "mobilny pakiet informacji",
            .automation: "procesu operacyjnego"
        ]

        for (kind, keyword) in expectedKeywords {
            let brief = AutomationClientBrief(kind: kind)

            XCTAssertTrue(brief.headline.localizedCaseInsensitiveContains(keyword), "\(kind) headline should mention \(keyword)")
            XCTAssertGreaterThanOrEqual(brief.highlights.count, 4)
            XCTAssertFalse(brief.outputLabel.isEmpty)
        }
    }

    @MainActor
    func testRouterOpensArtifactsForSelectedAutomationFromMarketingCTA() {
        let router = AppRouter()
        router.selectedTab = .automations

        _ = router.openReportsForTopic("tech-news", latestDay: "2026-06-22")

        XCTAssertEqual(router.selectedTab, .research)
        XCTAssertEqual(router.selectedResearchTopic, .techNews)
        XCTAssertEqual(router.selectedReportDay, "2026-06-22")
        XCTAssertTrue(router.artifactPath.isEmpty)
        XCTAssertNil(router.pendingArtifactID)
        XCTAssertNil(router.artifactRoute)
    }

    @MainActor
    func testRouterRoutesTechNotificationToResearchTopicAndDay() throws {
        let router = AppRouter()

        router.handleNotification(
            userInfo: [
                "artifactTopic": "tech-news",
                "artifactDate": "2026-06-22",
                "artifactIDs": ["audio-2026-06-22"]
            ]
        )

        XCTAssertEqual(router.selectedTab, .research)
        XCTAssertEqual(router.selectedResearchTopic, .techNews)
        XCTAssertEqual(router.selectedReportDay, "2026-06-22")
        XCTAssertNil(router.artifactRoute)
    }

    @MainActor
    func testRouterOpensGenericArtifactInArtifactPath() {
        let router = AppRouter()
        let artifact = Self.artifact(
            id: "automation-log-2026-06-22",
            type: .run,
            topic: "codex-agent-automation",
            path: "research/codex-agent-automation/runs/2026-06-22.md",
            date: "2026-06-22"
        )

        router.openArtifact(artifact)

        XCTAssertEqual(router.selectedTab, .artifacts)
        XCTAssertEqual(router.artifactPath.map(\.id), ["automation-log-2026-06-22"])
        XCTAssertNil(router.pendingArtifactID)
        XCTAssertNil(router.artifactRoute)
        XCTAssertTrue(router.jobsPath.isEmpty)
        XCTAssertTrue(router.researchPath.isEmpty)
    }

    @MainActor
    func testRouterResolvesPendingGenericArtifactIntoArtifactPath() throws {
        let router = AppRouter()
        let artifact = Self.artifact(
            id: "automation-log-2026-06-23",
            type: .run,
            topic: "codex-agent-automation",
            path: "research/codex-agent-automation/runs/2026-06-23.md",
            date: "2026-06-23"
        )
        let manifest = try manifestWithAdditionalArtifacts([artifact])

        router.handleOpenURL(try XCTUnwrap(URL(string: "pavbot://artifact?id=automation-log-2026-06-23")))
        router.resolvePendingArtifact(in: manifest)

        XCTAssertEqual(router.selectedTab, .artifacts)
        XCTAssertEqual(router.artifactPath.map(\.id), ["automation-log-2026-06-23"])
        XCTAssertNil(router.pendingArtifactID)
        XCTAssertNil(router.artifactRoute)
    }

    @MainActor
    func testAudioPlaybackServiceTracksAndClearsCurrentArtifact() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let audio = try XCTUnwrap(manifest.artifacts.first { $0.type == .podcastAudio })
        let service = AudioPlaybackService(enableSystemIntegrations: false)
        let url = try XCTUnwrap(URL(string: audio.url))

        service.load(artifact: audio, url: url)

        XCTAssertEqual(service.currentArtifact?.id, "audio-2026-06-22")
        XCTAssertEqual(service.currentURL, url)
        XCTAssertFalse(service.isPlaying)

        service.stop()

        XCTAssertNil(service.currentArtifact)
        XCTAssertNil(service.currentURL)
        XCTAssertFalse(service.isPlaying)
    }

    @MainActor
    func testAudioPlaybackBannerSnapshotAppearsOnlyForActiveAudio() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let audio = try XCTUnwrap(manifest.artifacts.first { $0.type == .podcastAudio })
        let service = AudioPlaybackService(enableSystemIntegrations: false)

        XCTAssertNil(AudioPlaybackBannerSnapshot(service: service))

        let url = try XCTUnwrap(URL(string: audio.url))
        service.load(artifact: audio, url: url)

        let snapshot = try XCTUnwrap(AudioPlaybackBannerSnapshot(service: service))
        XCTAssertEqual(snapshot.title, audio.title)
        XCTAssertEqual(snapshot.topic, "tech-news")
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertEqual(snapshot.playPauseSystemImage, "play.fill")

        service.stop()

        XCTAssertNil(AudioPlaybackBannerSnapshot(service: service))
    }

    func testAudioPlaybackBannerLayoutKeepsPlayerAboveTabBar() {
        XCTAssertEqual(AudioPlaybackBannerLayout.bottomClearance, 20)
    }

    func testAudioActivityAttributesCarryArtifactPlaybackMetadata() {
        let attributes = PavbotAudioActivityAttributes(
            artifactID: "audio-2026-06-22",
            artifactPath: "research/tech-news/podcasts/2026-06-22/podcast.mp3",
            topic: "tech-news"
        )
        let state = PavbotAudioActivityAttributes.ContentState(
            title: "Podcast audio",
            elapsed: 42,
            duration: 300,
            isPlaying: true,
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        XCTAssertEqual(attributes.artifactID, "audio-2026-06-22")
        XCTAssertEqual(attributes.topic, "tech-news")
        XCTAssertEqual(state.title, "Podcast audio")
        XCTAssertEqual(state.elapsed, 42)
        XCTAssertEqual(state.duration, 300)
        XCTAssertTrue(state.isPlaying)
    }

    func testResolvesRelativeArtifactURLAgainstRawManifestRoot() throws {
        let artifact = PavbotArtifact(
            id: "relative",
            type: .run,
            topic: "tech-news",
            title: "Daily Research Report",
            path: "research/tech-news/runs/2026-06-22.md",
            url: "research/tech-news/runs/2026-06-22.md",
            sizeBytes: 100,
            date: "2026-06-22",
            time: nil
        )
        let manifestURL = try XCTUnwrap(URL(string: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"))

        XCTAssertEqual(
            artifact.resolvedURL(manifestURL: manifestURL)?.absoluteString,
            "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/runs/2026-06-22.md"
        )
    }

    func testManifestURLValidationRequiresHTTPSManifestJSON() {
        XCTAssertEqual(ManifestURLValidator.validate("https://example.com/public/pavbot-manifest.json"), .valid)
        XCTAssertEqual(ManifestURLValidator.validate("http://example.com/public/pavbot-manifest.json"), .invalid("Use an HTTPS manifest URL."))
        XCTAssertEqual(ManifestURLValidator.validate("https://example.com/public/manifest.txt"), .invalid("Manifest URL must point to a JSON file."))
        XCTAssertEqual(ManifestURLValidator.validate(""), .invalid("Enter a manifest URL."))
    }

    func testUserFacingErrorsExposePolishCopyAndActions() {
        let manifestError = PavbotUserFacingError.manifest("Set your public GitHub raw manifest URL in Settings.")
        let networkError = PavbotUserFacingError.network(URLError(.notConnectedToInternet), context: .weather)
        let audioError = PavbotUserFacingError.audio("The operation could not be completed.")

        XCTAssertEqual(manifestError.title, "Manifest wymaga konfiguracji")
        XCTAssertEqual(manifestError.actionTitle, "Otwórz ustawienia")
        XCTAssertTrue(manifestError.message.contains("GitHub raw manifest"))
        XCTAssertEqual(networkError.title, "Nie udało się pobrać pogody")
        XCTAssertEqual(networkError.actionTitle, "Spróbuj ponownie")
        XCTAssertEqual(audioError.title, "Nie udało się odtworzyć audio")
        XCTAssertEqual(audioError.actionTitle, "Otwórz plik źródłowy")
    }

    func testReportPackageCopyUsesPolishUserFacingLabels() {
        XCTAssertEqual(ReportPackageCopy.emptyResearchTitle, "Brak raportów Research")
        XCTAssertEqual(ReportPackageCopy.openResearchTitle, "Otwórz raport")
        XCTAssertEqual(ReportPackageCopy.openPDFTitle, "Otwórz PDF")
        XCTAssertEqual(ReportPackageCopy.missingPDFTitle, "Brakuje PDF")
        XCTAssertEqual(ReportPackageCopy.refreshReportsAccessibilityLabel, "Odśwież raporty")
    }

    func testNotificationServerURLValidationAllowsEmptyUntilUserEnablesAlerts() {
        XCTAssertNil(NotificationServerSettings.validationMessage(for: "", required: false))
        XCTAssertEqual(
            NotificationServerSettings.validationMessage(for: "", required: true),
            "Enter a notification server URL before enabling live alerts."
        )
        XCTAssertEqual(
            NotificationServerSettings.validationMessage(for: "http://notify.example.com", required: true),
            "Use an HTTPS notification server URL."
        )
        XCTAssertNil(NotificationServerSettings.validationMessage(for: "https://notify.example.com", required: true))
    }

    @MainActor
    func testManifestStoreIgnoresLegacySavedManifestURL() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: ManifestDefaults.urlDefaultsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ManifestDefaults.urlDefaultsKey)
            } else {
                defaults.removeObject(forKey: ManifestDefaults.urlDefaultsKey)
            }
        }
        defaults.set("https://raw.githubusercontent.com/legacy/pavbot/main/public/pavbot-manifest.json", forKey: ManifestDefaults.urlDefaultsKey)

        let store = ManifestStore(
            client: CountingFailingManifestClient(),
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: SpyArtifactNotifier()
        )

        XCTAssertEqual(
            store.manifestURLString,
            "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json"
        )
        XCTAssertFalse(store.isUsingPlaceholderManifestURL)
    }

    func testNotificationServerSettingsIgnoresLegacySavedServerURL() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: NotificationServerSettings.urlDefaultsKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: NotificationServerSettings.urlDefaultsKey)
            } else {
                defaults.removeObject(forKey: NotificationServerSettings.urlDefaultsKey)
            }
        }
        defaults.set("https://notify.legacy.example.com", forKey: NotificationServerSettings.urlDefaultsKey)

        XCTAssertEqual(NotificationServerSettings.serverURLString, "https://notify.paweltanski.com")
        XCTAssertEqual(NotificationServerSettings.serverURL?.absoluteString, "https://notify.paweltanski.com")
    }

    func testAppDefaultsClientUsesCanonicalBootstrapBeforePreferredNotifierURL() throws {
        let endpoint = try XCTUnwrap(
            AppDefaultsClient.defaultsEndpointURL(preferredServerURLString: "https://notify.example.com/")
        )

        XCTAssertEqual(endpoint.absoluteString, "\(AppDefaultsClient.bootstrapNotifierURLString)/v1/app/defaults")
        XCTAssertEqual(AppDefaultsClient.bootstrapNotifierURLString, "https://notify.paweltanski.com")
    }

    func testAppDefaultsClientIncludesPreferredNotifierURLAsFallbackWhenItIsValid() throws {
        let endpoints = AppDefaultsClient.defaultsEndpointURLs(preferredServerURLString: "https://notify.example.com/")

        XCTAssertEqual(
            endpoints.map(\.absoluteString),
            [
                "\(AppDefaultsClient.bootstrapNotifierURLString)/v1/app/defaults",
                "https://notify.example.com/v1/app/defaults"
            ]
        )
    }

    func testAppDefaultsClientUsesBootstrapNotifierURLWhenPreferredURLIsInvalid() throws {
        let endpoint = try XCTUnwrap(
            AppDefaultsClient.defaultsEndpointURL(preferredServerURLString: "not a url")
        )

        XCTAssertEqual(
            endpoint.absoluteString,
            "\(AppDefaultsClient.bootstrapNotifierURLString)/v1/app/defaults"
        )
    }

    func testAppDefaultsClientFetchesAndValidatesConnectionDefaults() async throws {
        let payload = """
        {
          "schemaVersion": 1,
          "manifestURL": "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json",
          "notificationServerURL": "https://notify.example.com",
          "statusURL": "https://notify.example.com/status"
        }
        """.data(using: .utf8)!
        let requestedURLs = URLRequestCapture()
        let client = AppDefaultsClient(fetchData: { url in
            await requestedURLs.record(url)
            return payload
        })

        let defaults = try await client.fetchDefaults(preferredServerURLString: "")
        let requestedURL = await requestedURLs.first()

        XCTAssertEqual(
            requestedURL?.absoluteString,
            "\(AppDefaultsClient.bootstrapNotifierURLString)/v1/app/defaults"
        )
        XCTAssertEqual(defaults.schemaVersion, 1)
        XCTAssertEqual(defaults.notificationServerURL, "https://notify.example.com")
        XCTAssertNil(defaults.validationError)
    }

    func testAppDefaultsClientFallsBackToPreferredNotifierWhenCanonicalFails() async throws {
        let payload = """
        {
          "schemaVersion": 1,
          "manifestURL": "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json",
          "notificationServerURL": "https://notify.backup.example.com",
          "statusURL": "https://notify.backup.example.com/status"
        }
        """.data(using: .utf8)!
        let requestedURLs = URLRequestCapture()
        let client = AppDefaultsClient(fetchData: { url in
            await requestedURLs.record(url)
            if url.absoluteString == "\(AppDefaultsClient.bootstrapNotifierURLString)/v1/app/defaults" {
                throw AppDefaultsClientError.httpStatus(503)
            }
            return payload
        })

        let defaults = try await client.fetchDefaults(preferredServerURLString: "https://notify.backup.example.com")
        let urls = await requestedURLs.all()

        XCTAssertEqual(
            urls.map(\.absoluteString),
            [
                "\(AppDefaultsClient.bootstrapNotifierURLString)/v1/app/defaults",
                "https://notify.backup.example.com/v1/app/defaults"
            ]
        )
        XCTAssertEqual(defaults.notificationServerURL, "https://notify.backup.example.com")
    }

    func testAppDefaultsClientRejectsInvalidBackendDefaults() async {
        let payload = """
        {
          "schemaVersion": 1,
          "manifestURL": "http://example.com/manifest.txt",
          "notificationServerURL": "http://notify.example.com",
          "statusURL": "http://notify.example.com/status"
        }
        """.data(using: .utf8)!
        let client = AppDefaultsClient(fetchData: { _ in payload })

        do {
            _ = try await client.fetchDefaults(preferredServerURLString: "https://notify.example.com")
            XCTFail("Invalid defaults should throw before Settings overwrites saved URLs.")
        } catch AppDefaultsClientError.invalidDefaults(let message) {
            XCTAssertTrue(message.contains("Manifest URL"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppAppearancePreferencePersistsAndMapsColorScheme() throws {
        let suiteName = "AppAppearanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(AppAppearancePreference.system.preferredColorScheme)
        XCTAssertEqual(AppAppearancePreference.light.preferredColorScheme, .light)
        XCTAssertEqual(AppAppearancePreference.dark.preferredColorScheme, .dark)
        XCTAssertEqual(AppAppearancePreference.load(from: defaults), .system)

        AppAppearancePreference.dark.save(to: defaults)
        XCTAssertEqual(AppAppearancePreference.load(from: defaults), .dark)

        AppAppearancePreference.light.save(to: defaults)
        XCTAssertEqual(AppAppearancePreference.load(from: defaults), .light)
    }

    func testHapticPreferenceDefaultsToEnabledAndPersists() throws {
        let suiteName = "PavbotHapticPreferenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(PavbotHapticPreference.isEnabled(in: defaults))

        PavbotHapticPreference.save(false, in: defaults)
        XCTAssertFalse(PavbotHapticPreference.isEnabled(in: defaults))

        PavbotHapticPreference.save(true, in: defaults)
        XCTAssertTrue(PavbotHapticPreference.isEnabled(in: defaults))
    }

    @MainActor
    func testPavbotHapticsRespectsInteractionTouchPreference() throws {
        let suiteName = "PavbotHapticsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let generator = SpyHapticGenerator()
        let haptics = PavbotHaptics(defaults: defaults, generator: generator)

        PavbotHapticPreference.save(false, in: defaults)
        haptics.play(.selection)
        XCTAssertTrue(generator.events.isEmpty)

        PavbotHapticPreference.save(true, in: defaults)
        haptics.play(.success)
        XCTAssertEqual(generator.events, [.success])
    }

    func testPavbotInteractiveSurfaceConfigurationDisablesPressScaleWhenReduceMotionIsOn() {
        XCTAssertEqual(PavbotInteractiveSurfaceConfiguration(isReduceMotionEnabled: false).pressedScale, 0.975)
        XCTAssertEqual(PavbotInteractiveSurfaceConfiguration(isReduceMotionEnabled: true).pressedScale, 1.0)
        XCTAssertGreaterThan(PavbotInteractiveSurfaceConfiguration(isReduceMotionEnabled: false).shadowRadius, 0)
    }

    func testAccessibilityShowcaseFeaturesCoverAppStoreAccessibilityClaims() {
        let features = AccessibilityShowcaseFeature.allCases

        XCTAssertEqual(features.count, 8)
        XCTAssertEqual(Set(features.map(\.appStoreName)), [
            "Dark Interface",
            "Larger Text",
            "VoiceOver",
            "Voice Control",
            "Sufficient Contrast",
            "Differentiate Without Color Alone",
            "Reduced Motion",
            "Captions"
        ])
        XCTAssertFalse(features.contains { $0.appStoreName == "Audio Descriptions" })
        XCTAssertTrue(features.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty && !$0.accessibilityLabel.isEmpty })
    }

    func testRemoteNotificationDiagnosticsStoresTokenPreviewAndRegistrationError() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let token = Data([0x00, 0xab, 0xcd, 0xef, 0x12, 0x34])

        RemoteNotificationDiagnostics.saveDeviceToken(token, defaults: defaults)
        RemoteNotificationDiagnostics.saveRegistrationError("Missing aps-environment", defaults: defaults)

        XCTAssertEqual(RemoteNotificationDiagnostics.deviceToken(defaults: defaults), "00abcdef1234")
        XCTAssertEqual(RemoteNotificationDiagnostics.deviceTokenPreview(defaults: defaults), "00ab...1234")
        XCTAssertEqual(RemoteNotificationDiagnostics.registrationError(defaults: defaults), "Missing aps-environment")

        RemoteNotificationDiagnostics.clearRegistrationError(defaults: defaults)

        XCTAssertEqual(RemoteNotificationDiagnostics.registrationError(defaults: defaults), "")
    }

    func testLiveNotificationOnboardingPromptsOnceAndRoutesMissingServerURLToSettings() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        XCTAssertTrue(LiveNotificationOnboarding.shouldPrompt(defaults: defaults))
        XCTAssertTrue(LiveNotificationOnboarding.needsSettingsBeforeSystemPrompt(serverURLString: ""))
        XCTAssertFalse(LiveNotificationOnboarding.needsSettingsBeforeSystemPrompt(serverURLString: "https://notify.example.com"))

        LiveNotificationOnboarding.markPromptSeen(defaults: defaults)

        XCTAssertFalse(LiveNotificationOnboarding.shouldPrompt(defaults: defaults))
    }

    func testLiveNotificationSettingsPersistEnabledState() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        XCTAssertFalse(LiveNotificationSettings.isEnabled(defaults: defaults))

        LiveNotificationSettings.setEnabled(true, defaults: defaults)

        XCTAssertTrue(LiveNotificationSettings.isEnabled(defaults: defaults))

        LiveNotificationSettings.setEnabled(false, defaults: defaults)

        XCTAssertFalse(LiveNotificationSettings.isEnabled(defaults: defaults))
    }

    func testRemoteNotificationRegistrationPolicyRequiresEnabledLiveAlertsAndValidServer() {
        XCTAssertTrue(
            RemoteNotificationRegistrationPolicy.shouldRegister(
                liveNotificationsEnabled: true,
                serverURLString: "https://notify.example.com",
                authorizationStatus: .authorized
            )
        )
        XCTAssertFalse(
            RemoteNotificationRegistrationPolicy.shouldRegister(
                liveNotificationsEnabled: false,
                serverURLString: "https://notify.example.com",
                authorizationStatus: .authorized
            )
        )
        XCTAssertFalse(
            RemoteNotificationRegistrationPolicy.shouldRegister(
                liveNotificationsEnabled: true,
                serverURLString: "",
                authorizationStatus: .authorized
            )
        )
        XCTAssertFalse(
            RemoteNotificationRegistrationPolicy.shouldRegister(
                liveNotificationsEnabled: true,
                serverURLString: "http://notify.example.com",
                authorizationStatus: .authorized
            )
        )
        XCTAssertFalse(
            RemoteNotificationRegistrationPolicy.shouldRegister(
                liveNotificationsEnabled: true,
                serverURLString: "https://notify.example.com",
                authorizationStatus: .denied
            )
        )
    }

    func testDailyWeatherNotificationSettingsDefaultToEnabledAndPersist() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!

        XCTAssertTrue(DailyWeatherNotificationSettings.isEnabled(defaults: defaults))

        DailyWeatherNotificationSettings.setEnabled(false, defaults: defaults)

        XCTAssertFalse(DailyWeatherNotificationSettings.isEnabled(defaults: defaults))
    }

    func testRemoteNotificationRegistrationPayloadIncludesDailyWeatherPreference() throws {
        let payload = RemoteNotificationRegistrar.RegistrationPayload(
            deviceToken: "token",
            platform: "ios",
            bundleId: "com.paweltanski.pavbotviewer",
            manifestURL: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            appVersion: "1.0",
            buildNumber: "1",
            dailyWeatherEnabled: true
        )

        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["dailyWeatherEnabled"] as? Bool, true)
    }

    func testRemoteNotificationRegistrarUsesProductionDefaultsWhenLegacyURLsExist() async throws {
        let defaults = UserDefaults.standard
        let previousManifestURL = defaults.string(forKey: ManifestDefaults.urlDefaultsKey)
        let previousNotificationServerURL = defaults.string(forKey: NotificationServerSettings.urlDefaultsKey)
        defer {
            if let previousManifestURL {
                defaults.set(previousManifestURL, forKey: ManifestDefaults.urlDefaultsKey)
            } else {
                defaults.removeObject(forKey: ManifestDefaults.urlDefaultsKey)
            }
            if let previousNotificationServerURL {
                defaults.set(previousNotificationServerURL, forKey: NotificationServerSettings.urlDefaultsKey)
            } else {
                defaults.removeObject(forKey: NotificationServerSettings.urlDefaultsKey)
            }
            CapturingURLProtocol.requestHandler = nil
        }
        defaults.set("https://raw.githubusercontent.com/legacy/pavbot/main/public/pavbot-manifest.json", forKey: ManifestDefaults.urlDefaultsKey)
        defaults.set("https://notify.legacy.example.com", forKey: NotificationServerSettings.urlDefaultsKey)

        let requestStore = CapturedRequestStore()
        CapturingURLProtocol.requestHandler = { request in
            requestStore.record(request, body: request.pavbotCapturedBody)
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        let registrar = RemoteNotificationRegistrar(session: URLSession(configuration: configuration))

        await registrar.register(deviceToken: Data([0xde, 0xad, 0xbe, 0xef]))

        let request = try XCTUnwrap(requestStore.request)
        XCTAssertEqual(request.url?.absoluteString, "https://notify.paweltanski.com/v1/devices")
        let body = try XCTUnwrap(requestStore.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(
            json["manifestURL"] as? String,
            "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json"
        )
    }

    func testSettingsConnectionCopyDoesNotOfferManualURLEditing() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let settingsURL = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Views/SettingsView.swift")
        let source = try String(contentsOf: settingsURL)

        XCTAssertFalse(source.contains("Ręczna edycja"))
        XCTAssertFalse(source.contains("ręczna edycja"))
        XCTAssertFalse(source.contains("Przywróć ustawienia domyślne"))
        XCTAssertFalse(source.contains("Zapisz i odśwież"))
    }

    func testDecodesAndCachesDailyWeatherReport() throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = WeatherBriefCache(defaults: defaults)

        cache.save(report)

        let cached = try XCTUnwrap(cache.load())
        XCTAssertEqual(cached.id, "wroclaw-2026-06-25")
        XCTAssertEqual(cached.city, "Wrocław")
        XCTAssertEqual(cached.weekday, "czwartek")
        XCTAssertEqual(cached.nameDaysLabel, "Łucja, Wilhelm")
        XCTAssertEqual(cached.temperature.currentLabel, "21°C")
        XCTAssertEqual(cached.precipitation.probabilityLabel, "20%")
    }

    func testDecodesHourlyWeatherTimelineForToday() throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)

        XCTAssertEqual(report.hourlyTemperature.count, 3)
        XCTAssertEqual(report.hourlyTemperature[0].time, "2026-06-25T05:00")
        XCTAssertEqual(report.hourlyTemperature[1].temperature, 21.4)
        XCTAssertEqual(report.hourlyTemperature[1].hourLabel, "06:00")
        XCTAssertEqual(report.hourlyTemperature[1].displayTemperature, "21.4°C")
    }

    func testDecodesTemperatureTimelineAndPrefersItForCharts() throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-25T04:45:00Z"))

        XCTAssertEqual(report.temperatureTimeline.map(\.time), ["2026-06-25T06:00", "2026-06-25T07:00"])
        XCTAssertEqual(report.timelineTemperaturePoints(startingAt: now).map(\.time), ["2026-06-25T06:00", "2026-06-25T07:00"])
    }

    func testTemperatureTimelineFallsBackToHourlyTemperatureFromCurrentHour() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.dailyWeatherFixtureData) as? [String: Any])
        json.removeValue(forKey: "temperatureTimeline")
        let data = try JSONSerialization.data(withJSONObject: json)
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: data)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-25T04:45:00Z"))

        XCTAssertTrue(report.temperatureTimeline.isEmpty)
        XCTAssertEqual(report.timelineTemperaturePoints(startingAt: now).map(\.time), ["2026-06-25T06:00", "2026-06-25T07:00"])
    }

    func testWeatherBriefClientBuildsLatestRequestWithLocation() throws {
        let client = WeatherBriefClient()
        let serverURL = try XCTUnwrap(URL(string: "https://notify.example.com"))
        let location = WeatherBriefLocation(latitude: 52.2297, longitude: 21.0122, city: "Warszawa")

        let request = try client.latestRequest(from: serverURL, location: location)
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(components.path, "/v1/weather/daily/latest")
        XCTAssertEqual(query["lat"], "52.2297")
        XCTAssertEqual(query["lon"], "21.0122")
        XCTAssertEqual(query["city"], "Warszawa")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    func testWeatherLocationDisplayNameUsesReadablePlacemarkName() {
        let name = WeatherLocationDisplayName.name(
            locality: "Wrocław",
            subAdministrativeArea: nil,
            administrativeArea: "Dolnośląskie",
            country: "Polska",
            latitude: 51.1079,
            longitude: 17.0385
        )

        XCTAssertEqual(name, "Wrocław, Dolnośląskie")
    }

    func testWeatherLocationDisplayNameFallsBackToCoordinates() {
        let name = WeatherLocationDisplayName.name(
            locality: "  ",
            subAdministrativeArea: nil,
            administrativeArea: nil,
            country: nil,
            latitude: 51.1079,
            longitude: 17.0385
        )

        XCTAssertEqual(name, "51.11, 17.04")
    }

    func testTodayHumorDigestDecodesAndCaches() throws {
        let digest = try JSONDecoder.pavbot.decode(TodayHumorDigest.self, from: Self.todayHumorFixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = TodayHumorCache(defaults: defaults)

        cache.save(digest)

        let cached = try XCTUnwrap(cache.load())
        XCTAssertEqual(cached.id, "humor-2026-06-25-21")
        XCTAssertEqual(cached.items.count, 2)
        XCTAssertEqual(cached.items[0].title, "Kiedy deploy przechodzi za pierwszym razem")
        XCTAssertEqual(cached.items[0].scoreLabel, "1.2k")
        XCTAssertFalse(cached.nextRefreshLabel.isEmpty)
    }

    func testTodayHumorClientBuildsLatestRequest() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://notify.example.com"))
        let request = try TodayHumorClient.request(from: serverURL)
        let url = try XCTUnwrap(request.url)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(url.path, "/v1/humor/latest")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
    }

    @MainActor
    func testWeatherStoreKeepsCachedReportAndShowsNoticeWhenRefreshFails() async throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = WeatherBriefCache(defaults: defaults)
        cache.save(report)
        let store = WeatherBriefStore(
            client: FailingWeatherBriefClient(error: URLError(.notConnectedToInternet)),
            cache: cache,
            cooldown: WeatherRefreshCooldown(defaults: defaults),
            serverURLProvider: { URL(string: "https://notify.example.com") }
        )

        await store.load()

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.report?.id, "wroclaw-2026-06-25")
        XCTAssertEqual(store.cacheNotice, "Pokazuję ostatni zapisany raport. Odświeżenie nie powiodło się.")
    }

    @MainActor
    func testWeatherStoreRefreshNowSavesFreshReportWithLocation() async throws {
        let report = try Self.dailyWeatherReport(city: "Warszawa", id: "warszawa-2026-06-25")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = WeatherBriefCache(defaults: defaults)
        let client = SpyWeatherBriefClient(latestReport: report)
        let store = WeatherBriefStore(
            client: client,
            cache: cache,
            cooldown: WeatherRefreshCooldown(defaults: defaults),
            serverURLProvider: { URL(string: "https://notify.example.com") }
        )
        let location = WeatherBriefLocation(latitude: 52.2297, longitude: 21.0122, city: "Warszawa")

        await store.refreshNow(location: location)

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.report?.id, "warszawa-2026-06-25")
        XCTAssertEqual(store.report?.city, "Warszawa")
        XCTAssertEqual(cache.load()?.hourlyTemperature.count, 3)
        XCTAssertEqual(client.latestLocations.map { $0?.city }, ["Warszawa"])
        XCTAssertEqual(store.locationNotice, "Bieżąca prognoza dla: Warszawa.")
    }

    @MainActor
    func testWeatherStoreRejectsReportForDifferentLocation() async throws {
        let staleReport = try Self.dailyWeatherReport(city: "Wrocław", id: "wroclaw-2026-06-25")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = SpyWeatherBriefClient(latestReport: staleReport)
        let store = WeatherBriefStore(
            client: client,
            cache: WeatherBriefCache(defaults: defaults),
            cooldown: WeatherRefreshCooldown(defaults: defaults),
            serverURLProvider: { URL(string: "https://notify.example.com") }
        )
        let selectedLocation = WeatherBriefLocation(latitude: 52.2297, longitude: 21.0122, city: "Warszawa")

        await store.refreshNow(location: selectedLocation)

        XCTAssertNil(store.report)
        XCTAssertEqual(client.latestLocations.map { $0?.city }, ["Warszawa"])
        if case .failed(let error) = store.state {
            XCTAssertEqual(error.title, "Nie udało się pobrać prognozy dla tej lokalizacji")
            XCTAssertTrue(error.message.contains("Warszawa"))
            XCTAssertTrue(error.message.contains("Wrocław"))
        } else {
            XCTFail("Expected failed state for mismatched weather location")
        }
    }

    @MainActor
    func testWeatherStoreLoadDoesNotUseLocationProviderDuringStartup() async throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = SpyWeatherBriefClient(latestReport: report)
        var providerCalls = 0
        let store = WeatherBriefStore(
            client: client,
            cache: WeatherBriefCache(defaults: defaults),
            cooldown: WeatherRefreshCooldown(defaults: defaults),
            serverURLProvider: { URL(string: "https://notify.example.com") },
            locationProvider: { _ in
                providerCalls += 1
                return WeatherBriefLocation(latitude: 50.0614, longitude: 19.9366, city: "Kraków, Małopolskie")
            }
        )

        await store.load()

        XCTAssertEqual(providerCalls, 0)
        XCTAssertEqual(client.latestLocations.map { $0?.city }, [nil])
        XCTAssertEqual(store.locationNotice, "Bieżąca prognoza dla: Wrocław.")
        XCTAssertEqual(store.state, .loaded)
    }

    @MainActor
    func testWeatherStoreLoadUsesManualLocationWithoutCoreLocationProvider() async throws {
        let report = try Self.dailyWeatherReport(city: "Poznań, Wielkopolskie", id: "poznan-2026-06-25")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = SpyWeatherBriefClient(latestReport: report)
        var providerCalls = 0
        let manualLocation = WeatherBriefLocation(latitude: 52.4064, longitude: 16.9252, city: "Poznań, Wielkopolskie")
        let store = WeatherBriefStore(
            client: client,
            cache: WeatherBriefCache(defaults: defaults),
            cooldown: WeatherRefreshCooldown(defaults: defaults),
            serverURLProvider: { URL(string: "https://notify.example.com") },
            locationProvider: { _ in
                providerCalls += 1
                return WeatherBriefLocation(latitude: 50.0614, longitude: 19.9366, city: "Kraków, Małopolskie")
            },
            manualLocationProvider: { manualLocation }
        )

        await store.load()

        XCTAssertEqual(providerCalls, 0)
        XCTAssertEqual(client.latestLocations.map { $0?.city }, ["Poznań, Wielkopolskie"])
        XCTAssertEqual(store.locationNotice, "Bieżąca prognoza dla: Poznań, Wielkopolskie.")
        XCTAssertEqual(store.state, .loaded)
    }

    @MainActor
    func testWeatherStoreLoadWithCurrentLocationUsesProviderWhenAvailable() async throws {
        let report = try Self.dailyWeatherReport(city: "Kraków, Małopolskie", id: "krakow-2026-06-25")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = SpyWeatherBriefClient(latestReport: report)
        var requestedModes: [WeatherLocationMode] = []
        let store = WeatherBriefStore(
            client: client,
            cache: WeatherBriefCache(defaults: defaults),
            cooldown: WeatherRefreshCooldown(defaults: defaults),
            serverURLProvider: { URL(string: "https://notify.example.com") },
            locationProvider: { mode in
                requestedModes.append(mode)
                return WeatherBriefLocation(latitude: 50.0614, longitude: 19.9366, city: "Kraków, Małopolskie")
            }
        )

        await store.loadWithCurrentLocation()

        XCTAssertEqual(requestedModes, [.useIfAuthorized])
        XCTAssertEqual(client.latestLocations.map { $0?.city }, ["Kraków, Małopolskie"])
        XCTAssertEqual(store.locationNotice, "Bieżąca prognoza dla: Kraków, Małopolskie.")
        XCTAssertEqual(store.state, .loaded)
    }

    @MainActor
    func testWeatherStoreLoadWithCurrentLocationFallsBackToWroclawWhenLocationFails() async throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = SpyWeatherBriefClient(latestReport: report)
        let store = WeatherBriefStore(
            client: client,
            cache: WeatherBriefCache(defaults: defaults),
            cooldown: WeatherRefreshCooldown(defaults: defaults),
            serverURLProvider: { URL(string: "https://notify.example.com") },
            locationProvider: { mode in
                XCTAssertEqual(mode, .useIfAuthorized)
                throw WeatherLocationError.denied
            }
        )

        await store.loadWithCurrentLocation()

        XCTAssertEqual(client.latestLocations.count, 1)
        XCTAssertNil(client.latestLocations.first!)
        XCTAssertEqual(store.locationNotice, "Używam pogody dla Wrocławia. Lokalizacja jest niedostępna albo odmówiona.")
        XCTAssertEqual(store.report?.city, "Wrocław")
    }

    @MainActor
    func testWeatherStoreRefreshNowIgnoresLocalHourlyCooldownBecauseBackendRefreshesHourly() async throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = SpyWeatherBriefClient(latestReport: report)
        let retryAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-25T11:00:00Z"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-25T10:30:00Z"))
        let cooldown = WeatherRefreshCooldown(defaults: defaults, calendar: Calendar(identifier: .gregorian), now: { now })
        cooldown.setRetryAt(retryAt)
        let store = WeatherBriefStore(
            client: client,
            cache: WeatherBriefCache(defaults: defaults),
            cooldown: cooldown,
            serverURLProvider: { URL(string: "https://notify.example.com") }
        )
        store.report = report

        await store.refreshNow(location: .fallback)

        XCTAssertEqual(client.latestLocations.map { $0?.city }, ["Wrocław"])
        XCTAssertEqual(store.state, .loaded)
        XCTAssertNil(store.manualRefreshRetryAt)
        XCTAssertNil(store.cacheNotice)
    }

    @MainActor
    func testWeatherStoreLoadDeduplicatesConcurrentRequests() async throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let client = DelayedWeatherBriefClient(latestReport: report)
        let store = WeatherBriefStore(
            client: client,
            cache: WeatherBriefCache(defaults: defaults),
            cooldown: WeatherRefreshCooldown(defaults: defaults),
            serverURLProvider: { URL(string: "https://notify.example.com") }
        )

        let first = Task { await store.load() }
        let second = Task { await store.load() }
        await first.value
        await second.value

        XCTAssertEqual(client.fetchCount, 1)
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.report?.id, "wroclaw-2026-06-25")
    }

    func testPavbotRootLayoutStyleUsesTabForCompactWidth() {
        XCTAssertEqual(
            PavbotRootLayoutStyle.resolve(horizontalSizeClass: .compact, isRunningOnMac: false),
            .tab
        )
    }

    func testPavbotRootLayoutStyleUsesSplitForRegularWidthAndMac() {
        XCTAssertEqual(
            PavbotRootLayoutStyle.resolve(horizontalSizeClass: .regular, isRunningOnMac: false),
            .split
        )
        XCTAssertEqual(
            PavbotRootLayoutStyle.resolve(horizontalSizeClass: .compact, isRunningOnMac: true),
            .split
        )
    }

    func testWeatherRefreshCooldownBlocksUntilNextHour() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let refreshAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-25T10:15:00Z"))
        let beforeRetry = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-25T10:59:59Z"))
        let afterRetry = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-25T11:00:00Z"))
        let cooldown = WeatherRefreshCooldown(defaults: defaults, calendar: calendar, now: { beforeRetry })

        let retryAt = cooldown.recordRefresh(at: refreshAt)

        XCTAssertEqual(retryAt, afterRetry)
        XCTAssertEqual(cooldown.activeRetryAt(at: beforeRetry), afterRetry)
        XCTAssertNil(cooldown.activeRetryAt(at: afterRetry))
    }

    func testWeatherLocationFallbackUsesWroclaw() {
        let fallback = WeatherBriefLocation.fallback

        XCTAssertEqual(fallback.city, "Wrocław")
        XCTAssertEqual(fallback.latitude, 51.1079)
        XCTAssertEqual(fallback.longitude, 17.0385)
    }

    func testManualWeatherLocationSettingsPersistAndClearLocation() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let location = WeatherBriefLocation(latitude: 54.352, longitude: 18.6466, city: "Gdańsk, Pomorskie")

        ManualWeatherLocationSettings.save(location, defaults: defaults)

        XCTAssertEqual(ManualWeatherLocationSettings.location(defaults: defaults), location)

        ManualWeatherLocationSettings.clear(defaults: defaults)

        XCTAssertNil(ManualWeatherLocationSettings.location(defaults: defaults))
    }

    func testWeatherRangeTileModeTogglesBetweenValueAndChart() {
        var mode = WeatherRangeTileMode.value

        mode.toggle()
        XCTAssertEqual(mode, .chart)

        mode.toggle()
        XCTAssertEqual(mode, .value)
    }

    func testWeatherTimelineChartUsesVisibleZeroBaselineForPositiveTemperatures() throws {
        let report = try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: Self.dailyWeatherFixtureData)
        let model = TemperatureTimelineChartModel(report: report, maxVisibleLabels: 4)

        XCTAssertFalse(model.bars.isEmpty)
        XCTAssertGreaterThan(model.domain.lowerBound, 0)
        XCTAssertLessThan(model.baseline, model.bars.map(\.temperature).min()!)
        XCTAssertTrue(model.bars.allSatisfy { $0.yStart == model.baseline && $0.yEnd > model.baseline })
        XCTAssertLessThanOrEqual(model.visibleLabelIDs.count, 4)
        XCTAssertTrue(model.bars.contains { model.visibleLabelIDs.contains($0.id) && !$0.temperatureLabel.isEmpty })
    }

    func testTodayLiveTopicsSnapshotBuildsPolandAndWorldTopicsFromMobileNewsData() throws {
        let magazine = try JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: Self.mobileNewsDataFixtureData)
        let snapshot = TodayLiveTopicsSnapshot(magazine: magazine)

        XCTAssertEqual(snapshot.poland.title, "Tym żyje Polska")
        XCTAssertEqual(snapshot.world.title, "Tym żyje świat")
        XCTAssertEqual(snapshot.poland.topics.map(\.title), ["Gdańsk jako centrum rozmów", "Nowe decyzje w Sejmie"])
        XCTAssertEqual(snapshot.world.topics.map(\.title), ["Szczyt NATO i bezpieczeństwo regionu", "UE reaguje na napięcia gospodarcze"])
        XCTAssertEqual(snapshot.poland.topics[0].keyFacts.count, 2)
        XCTAssertFalse(snapshot.world.topics[0].reactions.isEmpty)
        XCTAssertEqual(snapshot.world.topics[0].sources.first?.title, "NATO")
    }

    func testDecodesPulseNewsDigestAndBuildsPairedCards() throws {
        let digest = try JSONDecoder.pavbot.decode(PulseNewsDigest.self, from: Self.pulseNewsDataFixtureData)
        let snapshot = TodayLiveTopicsSnapshot(digest: digest)

        XCTAssertEqual(digest.schemaVersion, 1)
        XCTAssertEqual(digest.topic, "puls-dnia-news")
        XCTAssertEqual(digest.items.count, 12)
        XCTAssertEqual(snapshot.displayDate, "2026-06-26 12:00")
        XCTAssertEqual(snapshot.pairs.count, 6)
        XCTAssertTrue(snapshot.pairs.allSatisfy { $0.topics.count == 2 })
        XCTAssertEqual(snapshot.pairs[0].topics.map(\.title), ["Polska: decyzja dnia 1", "Świat: decyzja dnia 2"])
        XCTAssertEqual(snapshot.pairs[0].topics[0].scope, .pulse)
        XCTAssertEqual(snapshot.pairs[0].topics[0].keyFacts.count, 2)
        XCTAssertEqual(snapshot.pairs[0].topics[0].context, "Kontekst tematu 1 i wpływ na kolejne godziny.")
        XCTAssertEqual(snapshot.pairs[0].topics[0].watchNext, ["Obserwuj kolejne komunikaty w sprawie 1."])
    }

    func testPulseNewsPairsRequireEvenItems() throws {
        let digest = PulseNewsDigest(
            schemaVersion: 1,
            topic: "puls-dnia-news",
            runDate: "2026-06-26",
            runTime: "12:00",
            status: "Material update",
            headline: "Puls dnia",
            summary: "Test",
            items: Array(Self.pulseNewsFixtureItems.prefix(3)),
            checkedSources: []
        )

        XCTAssertEqual(digest.pairedItems.map(\.items.count), [2])
    }

    @MainActor
    func testTodayLiveTopicsStorePrefersPulseNewsDataOverMobileNewsFallback() async throws {
        let pulseArtifact = Self.artifact(
            id: "pulse-data",
            type: .pulseNewsData,
            topic: "puls-dnia-news",
            path: "research/puls-dnia-news/data/2026-06-26-1200-pulse-news.json",
            date: "2026-06-26",
            time: "12:00"
        )
        let mobileArtifact = Self.artifact(
            id: "mobile-data",
            type: .mobileNewsData,
            topic: "aktualne-wydarzenia-mobile",
            path: "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json",
            date: "2026-06-25",
            time: "10:15"
        )
        let manifest = try manifestWithAdditionalArtifacts([pulseArtifact, mobileArtifact])
        let store = TodayLiveTopicsStore(
            client: MobileNewsClient(fetchData: { _ in XCTFail("Mobile fallback should not be fetched when pulseNewsData exists"); return Self.mobileNewsDataFixtureData }),
            pulseClient: PulseNewsClient(fetchData: { _ in Self.pulseNewsDataFixtureData })
        )

        await store.load(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.snapshot?.source, .pulseNews)
        XCTAssertEqual(store.snapshot?.pairs.count, 6)
        XCTAssertEqual(store.snapshot?.pairs.first?.topics.first?.title, "Polska: decyzja dnia 1")
    }

    @MainActor
    func testTodayLiveTopicsStoreFallsBackToMobileNewsWhenPulseNewsDataIsMissing() async throws {
        let mobileArtifact = Self.artifact(
            id: "mobile-data",
            type: .mobileNewsData,
            topic: "aktualne-wydarzenia-mobile",
            path: "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json",
            date: "2026-06-25",
            time: "10:15"
        )
        let manifest = try manifestWithAdditionalArtifacts([mobileArtifact])
        let store = TodayLiveTopicsStore(
            client: MobileNewsClient(fetchData: { _ in Self.mobileNewsDataFixtureData }),
            pulseClient: PulseNewsClient(fetchData: { _ in XCTFail("No pulse artifact should be fetched"); return Self.pulseNewsDataFixtureData })
        )

        await store.load(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.snapshot?.source, .mobileNews)
        XCTAssertTrue(store.snapshot?.isFallback ?? false)
        XCTAssertEqual(store.snapshot?.sourceLabel, "Dane fallbackowe z magazynu 10:15")
        XCTAssertEqual(store.snapshot?.pairs.count, 2)
        XCTAssertEqual(store.snapshot?.pairs.first?.topics.map(\.title), ["Gdańsk jako centrum rozmów", "Nowe decyzje w Sejmie"])
    }

    @MainActor
    func testTodayLiveTopicSpeechControllerBuildsCleanArticleText() throws {
        let topic = TodayLiveTopic(
            id: "pulse-speech",
            scope: .pulse,
            section: "Polska",
            title: "Puls dnia: ważny temat",
            lead: "Krótki lead bez linków.",
            keyFacts: ["Pierwszy fakt z linkiem https://example.com/fakt.", "Drugi fakt."],
            reactions: ["Reakcja instytucji."],
            whyItMatters: "Wyjaśnienie, dlaczego to ważne.",
            context: "Szerszy kontekst sprawy.",
            watchNext: ["Co obserwować dalej."],
            sources: [ResearchNewsSource(title: "Źródło", url: "https://example.com/source")],
            tags: ["Polska"],
            priority: "High"
        )

        let text = TodayLiveTopicSpeechController.speechText(for: topic)

        XCTAssertTrue(text.contains("Puls dnia: ważny temat"))
        XCTAssertTrue(text.contains("Najważniejsze fakty."))
        XCTAssertTrue(text.contains("Reakcje na sytuację."))
        XCTAssertTrue(text.contains("Dlaczego to ważne. Wyjaśnienie"))
        XCTAssertTrue(text.contains("Co obserwować dalej."))
        XCTAssertFalse(text.contains("https://"))
        XCTAssertFalse(text.contains("Przeczytaj artykuł"))
    }

    @MainActor
    func testTodayLiveTopicSpeechControllerTracksPlaybackStateAndRate() throws {
        let topic = Self.pulseNewsFixtureTopic(id: "speech-topic", title: "Temat do czytania")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let controller = TodayLiveTopicSpeechController(enableSpeech: false, rateDefaults: defaults)

        controller.speak(topic)

        XCTAssertEqual(controller.currentTopicID, topic.id)
        XCTAssertTrue(controller.isSpeaking)
        XCTAssertFalse(controller.isPaused)

        controller.pause()

        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(controller.currentTopicID, topic.id)

        controller.setSpeechRate(.fast)

        XCTAssertEqual(controller.speechRate, .fast)
        XCTAssertEqual(MobileNewsSpeechRate.saved(in: defaults), .fast)
        XCTAssertEqual(controller.currentTopicID, topic.id)
        XCTAssertTrue(controller.isPaused)

        controller.resume()
        XCTAssertTrue(controller.isSpeaking)

        controller.stop()
        XCTAssertNil(controller.currentTopicID)
        XCTAssertFalse(controller.isSpeaking)
    }

    @MainActor
    func testTodayLiveTopicSpeechRateChangePreservesProgress() throws {
        let topic = TodayLiveTopic(
            id: "progress-topic",
            scope: .pulse,
            section: "Świat",
            title: "Dłuższy temat do odczytania",
            lead: "Pierwszy akapit zawiera wystarczająco dużo słów, żeby timer TTS przesunął odczyt przed zmianą tempa.",
            keyFacts: ["Drugi fragment również ma kilka słów do testu zachowania postępu."],
            reactions: ["Reakcja rynku oraz instytucji publicznych."],
            whyItMatters: "Ten fragment sprawdza, czy odczyt nie wraca do początku po zmianie prędkości.",
            context: "Kontekst testowy dla osi czasu.",
            watchNext: ["Obserwuj kolejne aktualizacje."],
            sources: [],
            tags: ["Świat"],
            priority: "High"
        )
        let controller = TodayLiveTopicSpeechController(enableSpeech: false, rateDefaults: UserDefaults(suiteName: UUID().uuidString)!)

        controller.speak(topic)
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        let elapsedBeforeRateChange = controller.estimatedElapsed
        XCTAssertGreaterThan(elapsedBeforeRateChange, 0)

        controller.setSpeechRate(.slow)

        XCTAssertEqual(controller.currentTopicID, topic.id)
        XCTAssertEqual(controller.speechRate, .slow)
        XCTAssertTrue(controller.isSpeaking)
        XCTAssertGreaterThanOrEqual(controller.estimatedElapsed, elapsedBeforeRateChange * 0.9)
    }

    func testPulseDayTTSButtonOnlyExistsInTopicDetail() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Views/TodayLiveTopicsView.swift")
        let source = try String(contentsOf: sourceURL)
        let rowSource = try XCTUnwrap(
            source.components(separatedBy: "private struct TodayLiveTopicRow").dropFirst().first?
                .components(separatedBy: "private struct TodayLiveTopicsCarouselControls").first
        )

        XCTAssertTrue(source.contains("TodayLiveTopicSpeechPanel"))
        XCTAssertTrue(source.contains("Przeczytaj artykuł"))
        XCTAssertFalse(rowSource.contains("Przeczytaj artykuł"))
    }

    func testJobsRefreshForcesManifestReload() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Views/JobsView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("await store.reload(minimumInterval: 0)"))
    }

    func testPulseDayRefreshAndNotificationRouteForceManifestReload() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Views/PulseDayView.swift")
        let source = try String(contentsOf: sourceURL)

        XCTAssertTrue(source.contains("await reload(refreshManifest: true, minimumInterval: 0)"))
        XCTAssertTrue(source.contains("pulseRouteReloadKey"))
        XCTAssertTrue(source.contains("await manifestStore.reload(minimumInterval: 0)"))
    }

    func testTodayLiveTopicsSavedStorePersistsAndRemovesTopics() throws {
        let suiteName = "TodayLiveTopicsSavedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let topic = Self.pulseNewsFixtureTopic(id: "saved-topic", title: "Temat do zapisania")
        let store = TodayLiveTopicSavedStore(defaults: defaults)

        XCTAssertFalse(store.isSaved(topic))
        XCTAssertTrue(store.savedTopics.isEmpty)

        store.save(topic, source: .pulseNews, displayDate: "2026-06-26 12:00")

        XCTAssertTrue(store.isSaved(topic))
        XCTAssertEqual(store.savedTopics.count, 1)
        XCTAssertEqual(store.savedTopics.first?.topic.title, "Temat do zapisania")
        XCTAssertEqual(store.savedTopics.first?.sourceLabel, "Puls dnia 3h")

        store.remove(topic)

        XCTAssertFalse(store.isSaved(topic))
        XCTAssertTrue(store.savedTopics.isEmpty)
    }

    func testTodayLiveTopicsSavedStoreSortsNewestFirstAndSearchesContent() throws {
        let suiteName = "TodayLiveTopicsSavedSearchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TodayLiveTopicSavedStore(defaults: defaults)

        store.save(
            Self.pulseNewsFixtureTopic(id: "older", title: "Gospodarka i energia"),
            source: .pulseNews,
            displayDate: "2026-06-26 09:00",
            savedAt: Self.date("2026-06-26T09:05:00Z")
        )
        store.save(
            Self.pulseNewsFixtureTopic(id: "newer", title: "Polska i bezpieczeństwo"),
            source: .mobileNews,
            displayDate: "2026-06-26 10:15",
            savedAt: Self.date("2026-06-26T10:20:00Z")
        )

        XCTAssertEqual(store.savedTopics.map(\.topic.id), ["newer", "older"])
        XCTAssertEqual(store.filteredTopics(query: "energia").map(\.topic.id), ["older"])
        XCTAssertEqual(store.filteredTopics(scope: .poland).map(\.topic.id), ["newer"])
    }

    func testTodayLiveTopicsSavedStoreMigratesLegacyArchiveKey() throws {
        let suiteName = "TodayLiveTopicsSavedMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyTopic = Self.pulseNewsFixtureTopic(id: "legacy", title: "Dawniej archiwalny temat")
        let legacyRecord = SavedTodayLiveTopic(
            topic: legacyTopic,
            source: .pulseNews,
            displayDate: "2026-06-26 12:00",
            savedAt: Self.date("2026-06-26T12:05:00Z")
        )
        let legacyData = try JSONEncoder().encode([legacyRecord])
        defaults.set(legacyData, forKey: "pavbot.archivedTodayLiveTopics")

        let store = TodayLiveTopicSavedStore(defaults: defaults)

        XCTAssertEqual(store.savedTopics.map(\.topic.id), ["legacy"])
        XCTAssertTrue(store.isSaved(legacyTopic))
        XCTAssertNotNil(defaults.data(forKey: "pavbot.savedTodayLiveTopics"))
        XCTAssertNil(defaults.data(forKey: "pavbot.archivedTodayLiveTopics"))
    }

    func testTodayLiveTopicsSnapshotHidesSavedTopicsAndKeepsOddSingleCard() throws {
        let digest = try JSONDecoder.pavbot.decode(PulseNewsDigest.self, from: Self.pulseNewsDataFixtureData)
        let snapshot = TodayLiveTopicsSnapshot(digest: digest)
        let suiteName = "TodayLiveTopicsSavedFilteringTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TodayLiveTopicSavedStore(defaults: defaults)
        let savedTopic = try XCTUnwrap(snapshot.pairs.first?.topics.first)

        store.save(savedTopic, source: snapshot.source, displayDate: snapshot.displayDate)
        let visibleSnapshot = snapshot.removingSavedTopics(in: store)

        let visibleTopics = visibleSnapshot.pairs.flatMap(\.topics)
        XCTAssertFalse(visibleTopics.contains(savedTopic))
        XCTAssertEqual(visibleTopics.count, 11)
        XCTAssertEqual(visibleSnapshot.pairs.last?.topics.count, 1)
    }

    func testPulseHistoryShowsSavedAndUnsavedTopicsWhileLatestCanHideSaved() throws {
        let digest = try JSONDecoder.pavbot.decode(PulseNewsDigest.self, from: Self.pulseNewsDataFixtureData)
        let snapshot = TodayLiveTopicsSnapshot(digest: digest)
        let suiteName = "PulseHistorySavedVisibilityTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TodayLiveTopicSavedStore(defaults: defaults)
        let savedTopic = try XCTUnwrap(snapshot.allTopics.first)

        store.save(savedTopic, source: snapshot.source, displayDate: snapshot.displayDate)

        XCTAssertEqual(snapshot.allTopics.count, 12)
        XCTAssertTrue(snapshot.allTopics.contains(savedTopic))
        XCTAssertFalse(snapshot.removingSavedTopics(in: store).allTopics.contains(savedTopic))
    }

    func testPulseHistoryRunPresentationKeepsFullTopicListBehindPreview() throws {
        let digest = try JSONDecoder.pavbot.decode(PulseNewsDigest.self, from: Self.pulseNewsDataFixtureData)
        let snapshot = TodayLiveTopicsSnapshot(digest: digest)
        let presentation = PulseDayHistoryRunPresentation(snapshot: snapshot)

        XCTAssertEqual(presentation.previewTopics.count, 4)
        XCTAssertEqual(presentation.allTopics.count, 12)
        XCTAssertEqual(presentation.previewStatusText, "Pokazano 4 z 12")
        XCTAssertEqual(presentation.openAllButtonTitle, "Zobacz wszystkie artykuły")
    }

    func testPulseNewsHistoryStorePersistsRunsAndPrunesUnsavedAfter48Hours() throws {
        let suiteName = "PulseNewsHistoryRetentionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Self.date("2026-06-26T10:00:00Z")
        let store = PulseNewsHistoryStore(defaults: defaults, now: { now })

        store.save(Self.pulseNewsDigest(runDate: "2026-06-26", runTime: "12:00", headline: "Najnowszy Puls"))
        store.save(Self.pulseNewsDigest(runDate: "2026-06-24", runTime: "12:01", headline: "Jeszcze w retencji"))
        store.save(Self.pulseNewsDigest(runDate: "2026-06-24", runTime: "11:59", headline: "Po retencji"))

        XCTAssertEqual(store.runs.map(\.digest.headline), ["Najnowszy Puls", "Jeszcze w retencji"])

        let reloaded = PulseNewsHistoryStore(defaults: defaults, now: { now })
        XCTAssertEqual(reloaded.runs.map(\.digest.headline), ["Najnowszy Puls", "Jeszcze w retencji"])
        XCTAssertEqual(reloaded.snapshots.first?.headline, "Najnowszy Puls")
    }

    func testPulseNewsHistoryUsesCachedAtWhenRunTimeIsUnreadable() throws {
        let suiteName = "PulseNewsHistoryFallbackDateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Self.date("2026-06-26T10:00:00Z")
        let store = PulseNewsHistoryStore(defaults: defaults, now: { now })

        store.save(
            Self.pulseNewsDigest(runDate: "not-a-date", runTime: "bad-time", headline: "Fallback timestamp"),
            cachedAt: Self.date("2026-06-26T09:55:00Z")
        )
        store.save(
            Self.pulseNewsDigest(runDate: "also-bad", runTime: "bad-time", headline: "Expired fallback"),
            cachedAt: Self.date("2026-06-24T09:55:00Z")
        )

        XCTAssertEqual(store.runs.map(\.digest.headline), ["Fallback timestamp"])
    }

    func testSavedPulseTopicOutlivesExpiredHistoryRunAndDoesNotRestoreAfterRemoval() throws {
        let historySuite = "PulseNewsHistorySavedRetentionTests-\(UUID().uuidString)"
        let savedSuite = "PulseNewsSavedRetentionTests-\(UUID().uuidString)"
        let historyDefaults = UserDefaults(suiteName: historySuite)!
        let savedDefaults = UserDefaults(suiteName: savedSuite)!
        defer {
            historyDefaults.removePersistentDomain(forName: historySuite)
            savedDefaults.removePersistentDomain(forName: savedSuite)
        }
        let now = Self.date("2026-06-26T10:00:00Z")
        let historyStore = PulseNewsHistoryStore(defaults: historyDefaults, now: { now })
        let savedStore = TodayLiveTopicSavedStore(defaults: savedDefaults)
        let expiredDigest = Self.pulseNewsDigest(runDate: "2026-06-24", runTime: "11:59", headline: "Stary Puls")
        let expiredSnapshot = TodayLiveTopicsSnapshot(digest: expiredDigest)
        let topic = try XCTUnwrap(expiredSnapshot.pairs.first?.topics.first)

        historyStore.save(expiredDigest)
        savedStore.save(
            topic,
            source: expiredSnapshot.source,
            displayDate: expiredSnapshot.displayDate,
            savedAt: Self.date("2026-06-24T10:05:00Z")
        )

        XCTAssertTrue(historyStore.runs.isEmpty)
        XCTAssertTrue(savedStore.isSaved(topic))

        savedStore.remove(topic)

        XCTAssertFalse(savedStore.isSaved(topic))
        XCTAssertTrue(historyStore.runs.isEmpty)
    }

    @MainActor
    func testTodayLiveTopicsStoreShowsCachedPulseNewsWhenRemoteFetchFails() async throws {
        let suiteName = "TodayLiveTopicsCachedFallbackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let historyStore = PulseNewsHistoryStore(
            defaults: defaults,
            now: { Self.date("2026-06-26T10:00:00Z") }
        )
        historyStore.save(Self.pulseNewsDigest(runDate: "2026-06-26", runTime: "12:00", headline: "Lokalny Puls"))
        let pulseArtifact = Self.artifact(
            id: "pulse-data",
            type: .pulseNewsData,
            topic: "puls-dnia-news",
            path: "research/puls-dnia-news/data/2026-06-26-1500-pulse-news.json",
            date: "2026-06-26",
            time: "15:00"
        )
        let manifest = try manifestWithAdditionalArtifacts([pulseArtifact])
        let store = TodayLiveTopicsStore(
            client: MobileNewsClient(fetchData: { _ in XCTFail("Mobile fallback should not be fetched when cached pulse data exists"); return Self.mobileNewsDataFixtureData }),
            pulseClient: PulseNewsClient(fetchData: { _ in throw URLError(.notConnectedToInternet) }),
            historyStore: historyStore
        )

        await store.load(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.snapshot?.source, .pulseNews)
        XCTAssertEqual(store.snapshot?.headline, "Lokalny Puls")
        XCTAssertEqual(store.historySnapshots.map(\.headline), ["Lokalny Puls"])
        XCTAssertEqual(store.emptyMessage, "Pokazuję lokalnie zapamiętany Puls Dnia z ostatnich 48h. Odświeżenie nie powiodło się.")
    }

    @MainActor
    func testTodayLiveTopicsStoreCachesSuccessfulPulseNewsRun() async throws {
        let suiteName = "TodayLiveTopicsCacheWriteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let historyStore = PulseNewsHistoryStore(
            defaults: defaults,
            now: { Self.date("2026-06-26T10:00:00Z") }
        )
        let pulseArtifact = Self.artifact(
            id: "pulse-data",
            type: .pulseNewsData,
            topic: "puls-dnia-news",
            path: "research/puls-dnia-news/data/2026-06-26-1200-pulse-news.json",
            date: "2026-06-26",
            time: "12:00"
        )
        let manifest = try manifestWithAdditionalArtifacts([pulseArtifact])
        let store = TodayLiveTopicsStore(
            client: MobileNewsClient(fetchData: { _ in XCTFail("Mobile fallback should not be fetched when pulse data succeeds"); return Self.mobileNewsDataFixtureData }),
            pulseClient: PulseNewsClient(fetchData: { _ in Self.pulseNewsDataFixtureData }),
            historyStore: historyStore
        )

        await store.load(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(historyStore.runs.map(\.digest.id), ["puls-dnia-news-2026-06-26-12:00"])
        XCTAssertEqual(store.historySnapshots.first?.pairs.count, 6)
    }

    func testTodayLiveTopicsLayoutKeepsTwoCardsFullyVisible() {
        let layout = TodayLiveTopicsCarouselLayout(cardCount: 2, compactWidth: true)

        XCTAssertEqual(layout.cardCount, 2)
        XCTAssertGreaterThanOrEqual(layout.cardHeight, 190)
        XCTAssertEqual(layout.pageHeight, layout.cardHeight * 2 + layout.cardSpacing)
    }

    func testTodayLiveTopicsCarouselStatePausesWhileDetailIsOpen() {
        var state = TodayLiveTopicsCarouselState()

        XCTAssertFalse(state.isAutoScrollPaused)

        state.selectedTopic = TodayLiveTopic(
            id: "topic",
            scope: .pulse,
            section: "Polska",
            title: "Temat",
            lead: "Lead",
            keyFacts: ["Fakt"],
            reactions: ["Reakcja"],
            whyItMatters: "Ważne",
            context: "Kontekst",
            watchNext: ["Dalej"],
            sources: [],
            tags: ["Polska"],
            priority: "High"
        )
        XCTAssertTrue(state.isAutoScrollPaused)

        state.selectedTopic = nil
        XCTAssertFalse(state.isAutoScrollPaused)
    }

    func testTodayLiveTopicsCarouselStatePausesWhenReduceMotionIsEnabled() {
        var state = TodayLiveTopicsCarouselState()

        XCTAssertFalse(state.isAutoScrollPaused)

        state.reduceMotionEnabled = true

        XCTAssertTrue(state.isAutoScrollPaused)
    }

    func testTodayLiveTopicsSwipeDecisionMovesToNextOnLeftSwipe() {
        let action = TodayLiveTopicsSwipeDecision.action(
            translation: CGSize(width: -72, height: 6),
            predictedEndTranslation: CGSize(width: -96, height: 8),
            pageCount: 4
        )

        XCTAssertEqual(action, .next)
    }

    func testTodayLiveTopicsSwipeDecisionMovesToPreviousOnRightSwipe() {
        let action = TodayLiveTopicsSwipeDecision.action(
            translation: CGSize(width: 70, height: -4),
            predictedEndTranslation: CGSize(width: 91, height: -5),
            pageCount: 4
        )

        XCTAssertEqual(action, .previous)
    }

    func testTodayLiveTopicsSwipeDecisionUsesPredictedTranslationForQuickFlick() {
        let action = TodayLiveTopicsSwipeDecision.action(
            translation: CGSize(width: -24, height: 3),
            predictedEndTranslation: CGSize(width: -82, height: 6),
            pageCount: 4
        )

        XCTAssertEqual(action, .next)
    }

    func testTodayLiveTopicsSwipeDecisionIgnoresShortAndVerticalDrags() {
        XCTAssertNil(TodayLiveTopicsSwipeDecision.action(
            translation: CGSize(width: -24, height: 2),
            predictedEndTranslation: CGSize(width: -30, height: 4),
            pageCount: 4
        ))
        XCTAssertNil(TodayLiveTopicsSwipeDecision.action(
            translation: CGSize(width: -80, height: 120),
            predictedEndTranslation: CGSize(width: -86, height: 140),
            pageCount: 4
        ))
    }

    func testTodayLiveTopicsSwipeDecisionIgnoresSinglePageAndOpenDetail() {
        XCTAssertNil(TodayLiveTopicsSwipeDecision.action(
            translation: CGSize(width: -72, height: 0),
            predictedEndTranslation: CGSize(width: -96, height: 0),
            pageCount: 1
        ))
        XCTAssertNil(TodayLiveTopicsSwipeDecision.action(
            translation: CGSize(width: -72, height: 0),
            predictedEndTranslation: CGSize(width: -96, height: 0),
            pageCount: 4,
            detailIsOpen: true
        ))
    }

    func testTodayLiveTopicsPageAdvanceWrapsAndStopsWhenDetailIsOpen() {
        XCTAssertEqual(TodayLiveTopicsPageAdvance.nextIndex(currentIndex: 0, pageCount: 4, offset: 1), 1)
        XCTAssertEqual(TodayLiveTopicsPageAdvance.nextIndex(currentIndex: 0, pageCount: 4, offset: -1), 3)
        XCTAssertEqual(TodayLiveTopicsPageAdvance.nextIndex(currentIndex: 5, pageCount: 4, offset: 1), 0)
        XCTAssertNil(TodayLiveTopicsPageAdvance.nextIndex(currentIndex: 0, pageCount: 1, offset: 1))
        XCTAssertNil(TodayLiveTopicsPageAdvance.nextIndex(currentIndex: 0, pageCount: 4, offset: 1, detailIsOpen: true))
    }

    @MainActor
    func testTodayLiveTopicsStoreShowsFallbackWhenNoLiveTopicManifestExists() async {
        let suiteName = "TodayLiveTopicsNoManifestTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TodayLiveTopicsStore(
            historyStore: PulseNewsHistoryStore(defaults: defaults)
        )

        await store.load(
            manifest: nil,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.emptyMessage, "Brak opublikowanego Pulsu dnia. Odśwież manifest albo otwórz Research -> Aktualne.")
    }

    func testDecoderRejectsUnsupportedManifestSchemaVersion() throws {
        let data = """
        {
          "schemaVersion": 99,
          "title": "Pavbot Automation Manifest",
          "generatedAt": "2026-06-22T12:00:00+00:00",
          "rawBaseUrl": "",
          "automations": [],
          "topics": [],
          "artifacts": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder.pavbot.decode(PavbotManifest.self, from: data)) { error in
            XCTAssertEqual(error.localizedDescription, "Unsupported manifest schema version 99.")
        }
    }

    func testDetectsNewArtifactsComparedToPreviousManifest() throws {
        let previous = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        var nextArtifacts = previous.artifacts
        nextArtifacts.insert(Self.newArtifact, at: 0)
        let next = PavbotManifest(
            schemaVersion: previous.schemaVersion,
            title: previous.title,
            generatedAt: previous.generatedAt,
            rawBaseUrl: previous.rawBaseUrl,
            automations: previous.automations,
            topics: previous.topics,
            artifacts: nextArtifacts
        )

        XCTAssertEqual(next.newArtifacts(comparedTo: previous).map(\.id), ["new-run-2026-06-23"])
    }

    func testDetectsNewAutomationsComparedToPreviousManifest() throws {
        let previous = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let next = PavbotManifest(
            schemaVersion: previous.schemaVersion,
            title: previous.title,
            generatedAt: "2026-06-22T12:05:00+00:00",
            rawBaseUrl: previous.rawBaseUrl,
            automations: previous.automations + [Self.newAutomation],
            topics: previous.topics,
            artifacts: previous.artifacts
        )

        XCTAssertEqual(next.newAutomations(comparedTo: previous).map(\.id), ["mobile-current-events"])
    }

    func testArtifactTypesSupportMobilePodcastVariants() throws {
        let audioVariant = try JSONDecoder.pavbot.decode(ArtifactType.self, from: #""podcastAudioVariant""#.data(using: .utf8)!)
        let ttsVariants = try JSONDecoder.pavbot.decode(ArtifactType.self, from: #""podcastTtsVariants""#.data(using: .utf8)!)
        let jobsData = try JSONDecoder.pavbot.decode(ArtifactType.self, from: #""jobsData""#.data(using: .utf8)!)
        let mobileNewsData = try JSONDecoder.pavbot.decode(ArtifactType.self, from: #""mobileNewsData""#.data(using: .utf8)!)

        XCTAssertEqual(audioVariant, .podcastAudioVariant)
        XCTAssertEqual(ttsVariants, .podcastTtsVariants)
        XCTAssertEqual(jobsData, .jobsData)
        XCTAssertEqual(mobileNewsData, .mobileNewsData)
        XCTAssertEqual(audioVariant.label, "Audio variant")
        XCTAssertEqual(ttsVariants.label, "TTS variants")
        XCTAssertEqual(jobsData.label, "Jobs data")
        XCTAssertEqual(mobileNewsData.label, "Mobile news data")

        let artifact = PavbotArtifact(
            id: "variant",
            type: .podcastAudioVariant,
            topic: "aktualne-wydarzenia-mobile",
            title: "Podcast audio - female piper",
            path: "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/audio/female-piper/podcast.mp3",
            url: "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/audio/female-piper/podcast.mp3",
            sizeBytes: 100,
            date: "2026-06-23",
            time: nil
        )
        XCTAssertEqual(artifact.viewerKind, .audio)

        let dataArtifact = PavbotArtifact(
            id: "jobs-data",
            type: .jobsData,
            topic: "llm-ai-jobs-wroclaw",
            title: "Jobs data",
            path: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
            url: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
            sizeBytes: 100,
            date: "2026-06-25",
            time: "01:41"
        )
        XCTAssertEqual(dataArtifact.viewerKind, .json)

        let mobileDataArtifact = PavbotArtifact(
            id: "mobile-news-data",
            type: .mobileNewsData,
            topic: "aktualne-wydarzenia-mobile",
            title: "Mobile news data",
            path: "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json",
            url: "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json",
            sizeBytes: 100,
            date: "2026-06-25",
            time: "10:15"
        )
        XCTAssertEqual(mobileDataArtifact.viewerKind, .json)
    }

    func testTimestampedMobileArtifactDisplayDateIncludesCreationTime() {
        let artifact = PavbotArtifact(
            id: "mobile-report",
            type: .run,
            topic: "aktualne-wydarzenia-mobile",
            title: "Mobile News Brief",
            path: "research/aktualne-wydarzenia-mobile/runs/2026-06-23-1015.md",
            url: "research/aktualne-wydarzenia-mobile/runs/2026-06-23-1015.md",
            sizeBytes: 100,
            date: "2026-06-23",
            time: "10:15"
        )

        XCTAssertEqual(artifact.displayDate, "2026-06-23 10:15")
    }

    func testResearchAudioAutomationKindPrefersAudioWhenOnlyPublicPdfAndAudioExist() throws {
        let kind = try JSONDecoder.pavbot.decode(AutomationKind.self, from: #""researchAudio""#.data(using: .utf8)!)

        XCTAssertEqual(kind, .researchAudio)
        XCTAssertEqual(kind.preferredArtifactTypes, [.mobileNewsData, .podcastScript, .podcastAudioVariant, .podcastAudio, .pdf, .run])

        let automation = PavbotAutomation(
            id: "mobile-current-events",
            name: "Pavbot Aktualne Wydarzenia Mobile 10:15",
            enabled: true,
            kind: .researchAudio,
            topic: "aktualne-wydarzenia-mobile",
            topicPath: "research/aktualne-wydarzenia-mobile",
            cadence: "daily at 10:15 local time",
            sourcePath: "docs/how-to-use.md",
            sourceUrl: "docs/how-to-use.md",
            output: "research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-mobile-brief.pdf",
            outputUrl: nil
        )
        let pdf = PavbotArtifact(
            id: "pdf",
            type: .pdf,
            topic: "aktualne-wydarzenia-mobile",
            title: "Mobile PDF",
            path: "research/aktualne-wydarzenia-mobile/pdfs/2026-06-23-mobile-brief.pdf",
            url: "research/aktualne-wydarzenia-mobile/pdfs/2026-06-23-mobile-brief.pdf",
            sizeBytes: 100,
            date: "2026-06-23",
            time: nil
        )
        let audio = PavbotArtifact(
            id: "audio",
            type: .podcastAudioVariant,
            topic: "aktualne-wydarzenia-mobile",
            title: "Podcast audio - female piper",
            path: "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/audio/female-piper/podcast.mp3",
            url: "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/audio/female-piper/podcast.mp3",
            sizeBytes: 100,
            date: "2026-06-23",
            time: nil
        )
        let manifest = PavbotManifest(
            schemaVersion: 1,
            title: "Pavbot Automation Manifest",
            generatedAt: "2026-06-23T10:00:00+00:00",
            rawBaseUrl: "",
            automations: [automation],
            topics: [],
            artifacts: [pdf, audio]
        )

        XCTAssertEqual(manifest.latestArtifact(for: automation)?.id, "audio")
        XCTAssertEqual(manifest.artifacts.map(\.id), ["pdf", "audio"])
    }

    func testDiagnosticsReportsFreshManifestAndCounts() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-23T11:59:00Z")
        )

        XCTAssertEqual(diagnostics.enabledAutomationCount, 2)
        XCTAssertEqual(diagnostics.topicCount, 1)
        XCTAssertEqual(diagnostics.artifactCount, 5)
        XCTAssertEqual(diagnostics.freshness.severity, .ok)
        XCTAssertEqual(diagnostics.urlStatus.severity, .ok)
        XCTAssertTrue(diagnostics.issues.isEmpty)
    }

    func testDiagnosticsWarnsWhenManifestIsStale() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-23T12:01:00Z")
        )

        XCTAssertEqual(diagnostics.freshness.severity, .warning)
        XCTAssertTrue(diagnostics.issues.contains { $0.title == "Manifest jest nieaktualny" })
    }

    func testDiagnosticsWarnsForPlaceholderURLAndMissingRawBaseURL() throws {
        let loadedManifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let manifest = PavbotManifest(
            schemaVersion: loadedManifest.schemaVersion,
            title: loadedManifest.title,
            generatedAt: loadedManifest.generatedAt,
            rawBaseUrl: "",
            automations: loadedManifest.automations,
            topics: loadedManifest.topics,
            artifacts: loadedManifest.artifacts
        )
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/OWNER/REPO/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-22T13:00:00Z")
        )

        XCTAssertEqual(diagnostics.urlStatus.severity, .warning)
        XCTAssertEqual(diagnostics.rawBaseURLStatus.severity, .warning)
        XCTAssertTrue(diagnostics.issues.contains { $0.title == "Brakuje publicznego raw base URL" })
    }

    func testDiagnosticsFlagsActiveAutomationWithoutArtifacts() throws {
        let loadedManifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let manifest = PavbotManifest(
            schemaVersion: loadedManifest.schemaVersion,
            title: loadedManifest.title,
            generatedAt: loadedManifest.generatedAt,
            rawBaseUrl: loadedManifest.rawBaseUrl,
            automations: loadedManifest.automations,
            topics: loadedManifest.topics,
            artifacts: []
        )
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-22T13:00:00Z")
        )

        XCTAssertEqual(diagnostics.automationStatuses.map(\.severity), [.warning, .warning])
        XCTAssertTrue(diagnostics.issues.contains { $0.title == "Automatyzacja nie ma artefaktów" })
    }

    func testDiagnosticsFindsLatestArtifactForAutomationTopic() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let diagnostics = ManifestDiagnostics(
            manifest: manifest,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            now: Self.date("2026-06-22T13:00:00Z")
        )

        XCTAssertEqual(diagnostics.automationStatuses.map { $0.latestArtifact?.id }, ["run-2026-06-22", "audio-2026-06-22"])
    }

    func testLatestAutomationRunSummaryUsesArtifactTimeAndMatchingAutomationName() throws {
        let loadedManifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let latestAudio = PavbotArtifact(
            id: "audio-2026-06-23",
            type: .podcastAudio,
            topic: "tech-news",
            title: "Podcast audio",
            path: "research/tech-news/podcasts/2026-06-23/podcast.mp3",
            url: "research/tech-news/podcasts/2026-06-23/podcast.mp3",
            sizeBytes: 300,
            date: "2026-06-23",
            time: "09:30"
        )
        let manifest = PavbotManifest(
            schemaVersion: loadedManifest.schemaVersion,
            title: loadedManifest.title,
            generatedAt: loadedManifest.generatedAt,
            rawBaseUrl: loadedManifest.rawBaseUrl,
            automations: loadedManifest.automations,
            topics: loadedManifest.topics,
            artifacts: [latestAudio] + loadedManifest.artifacts
        )

        XCTAssertEqual(manifest.latestAutomationRun?.time, "09:30")
        XCTAssertEqual(manifest.latestAutomationRun?.automationName, "Pavbot Tech Podcast 09:00")
        XCTAssertEqual(manifest.latestAutomationRun?.dashboardSubtitle, "09:30 · Pavbot Tech Podcast 09:00")
    }

    @MainActor
    func testStoreSchedulesNotificationsForNewArtifactsAfterRefresh() async throws {
        let previous = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let next = PavbotManifest(
            schemaVersion: previous.schemaVersion,
            title: previous.title,
            generatedAt: previous.generatedAt,
            rawBaseUrl: previous.rawBaseUrl,
            automations: previous.automations,
            topics: previous.topics,
            artifacts: [Self.newArtifact] + previous.artifacts
        )
        let notifier = SpyArtifactNotifier()
        let store = ManifestStore(
            client: StubManifestClient(manifest: next),
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: notifier,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            liveNotificationsEnabled: { false }
        )
        store.manifest = previous

        await store.load()

        XCTAssertEqual(notifier.notifiedArtifactIDs, ["new-run-2026-06-23"])
        XCTAssertTrue(notifier.notifiedAutomationIDs.isEmpty)
        XCTAssertEqual(store.manifest?.artifacts.first?.id, "new-run-2026-06-23")
    }

    @MainActor
    func testStoreSkipsLocalCatchUpNotificationsWhenLiveNotificationsAreEnabled() async throws {
        let previous = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let next = PavbotManifest(
            schemaVersion: previous.schemaVersion,
            title: previous.title,
            generatedAt: previous.generatedAt,
            rawBaseUrl: previous.rawBaseUrl,
            automations: previous.automations,
            topics: previous.topics,
            artifacts: [Self.newArtifact] + previous.artifacts
        )
        let notifier = SpyArtifactNotifier()
        let store = ManifestStore(
            client: StubManifestClient(manifest: next),
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: notifier,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            liveNotificationsEnabled: { true }
        )
        store.manifest = previous

        await store.load()

        XCTAssertTrue(notifier.notifiedArtifactIDs.isEmpty)
        XCTAssertTrue(notifier.notifiedAutomationIDs.isEmpty)
        XCTAssertEqual(store.lastNewArtifacts.map(\.id), ["new-run-2026-06-23"])
    }

    @MainActor
    func testStoreSchedulesNotificationsForNewAutomationsAfterRefresh() async throws {
        let previous = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let next = PavbotManifest(
            schemaVersion: previous.schemaVersion,
            title: previous.title,
            generatedAt: "2026-06-22T12:05:00+00:00",
            rawBaseUrl: previous.rawBaseUrl,
            automations: previous.automations + [Self.newAutomation],
            topics: previous.topics,
            artifacts: previous.artifacts
        )
        let notifier = SpyArtifactNotifier()
        let store = ManifestStore(
            client: StubManifestClient(manifest: next),
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: notifier,
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            liveNotificationsEnabled: { false }
        )
        store.manifest = previous

        await store.load()

        XCTAssertTrue(notifier.notifiedArtifactIDs.isEmpty)
        XCTAssertEqual(notifier.notifiedAutomationIDs, ["mobile-current-events"])
        XCTAssertEqual(store.lastNewAutomations.map(\.id), ["mobile-current-events"])
    }

    @MainActor
    func testStoreDoesNotReplaceNewerCachedManifestWithOlderRemoteManifest() async throws {
        let cached = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let olderRemote = PavbotManifest(
            schemaVersion: cached.schemaVersion,
            title: cached.title,
            generatedAt: "2026-06-22T11:59:00+00:00",
            rawBaseUrl: cached.rawBaseUrl,
            automations: [],
            topics: [],
            artifacts: []
        )
        let store = ManifestStore(
            client: StubManifestClient(manifest: olderRemote),
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: SpyArtifactNotifier(),
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )
        store.manifest = cached

        await store.load()

        XCTAssertEqual(store.manifest?.automations.map(\.id), ["research", "podcast"])
        XCTAssertEqual(store.state.error?.title, "Pokazuję dane z cache")
        XCTAssertTrue(store.state.error?.message.contains("Remote manifest is older") == true)
    }

    @MainActor
    func testStoreLoadedFromCacheRefreshesToNewerRemoteManifest() async throws {
        let cached = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let newerRemote = PavbotManifest(
            schemaVersion: cached.schemaVersion,
            title: cached.title,
            generatedAt: "2026-06-27T01:07:23+00:00",
            rawBaseUrl: cached.rawBaseUrl,
            automations: cached.automations,
            topics: cached.topics,
            artifacts: [Self.newArtifact] + cached.artifacts
        )
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        ManifestCache(defaults: defaults).save(cached)
        let store = ManifestStore(
            client: StubManifestClient(manifest: newerRemote),
            cache: ManifestCache(defaults: defaults),
            notifier: SpyArtifactNotifier(),
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.manifest?.generatedAt, cached.generatedAt)

        await store.load()

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.manifest?.generatedAt, "2026-06-27T01:07:23+00:00")
        XCTAssertEqual(store.lastNewArtifacts.map(\.id), ["new-run-2026-06-23"])
    }

    @MainActor
    func testReloadGateDeduplicatesAndThrottlesRequests() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let gate = ReloadGate(now: { currentDate })

        XCTAssertTrue(gate.begin(key: "manifest", minimumInterval: 60))
        XCTAssertFalse(gate.begin(key: "manifest", minimumInterval: 60))
        gate.finish(key: "manifest")
        XCTAssertFalse(gate.begin(key: "manifest", minimumInterval: 60))

        currentDate = currentDate.addingTimeInterval(61)
        XCTAssertTrue(gate.begin(key: "manifest", minimumInterval: 60))
        gate.finish(key: "manifest")
    }

    func testManifestClientBuildsNoCacheRequest() throws {
        let url = try XCTUnwrap(URL(string: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"))
        let request = ManifestClient.request(for: url)

        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
    }

    @MainActor
    func testManifestStoreStartsOnlyOneAutoRefreshLoop() {
        let store = ManifestStore(
            client: CountingFailingManifestClient(),
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: SpyArtifactNotifier(),
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        store.startAutoRefreshLoop(intervalSeconds: 60)
        store.startAutoRefreshLoop(intervalSeconds: 60)

        XCTAssertTrue(store.isAutoRefreshLoopRunning)
        XCTAssertEqual(store.autoRefreshLoopStartCount, 1)

        store.stopAutoRefreshLoop()
        store.startAutoRefreshLoop(intervalSeconds: 60)

        XCTAssertTrue(store.isAutoRefreshLoopRunning)
        XCTAssertEqual(store.autoRefreshLoopStartCount, 2)

        store.stopAutoRefreshLoop()
    }

    @MainActor
    func testStoreStartsLoadedWhenCacheContainsManifest() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = ManifestCache(defaults: defaults)
        cache.save(manifest)

        let store = ManifestStore(
            client: StubManifestClient(manifest: manifest),
            cache: cache,
            notifier: SpyArtifactNotifier(),
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.manifest?.artifacts.count, 5)
    }

    @MainActor
    func testStoreDoesNotFetchPlaceholderURLWhenManifestAlreadyAvailable() async throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let client = CountingFailingManifestClient()
        let store = ManifestStore(
            client: client,
            cache: ManifestCache(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            notifier: SpyArtifactNotifier(),
            manifestURLString: ManifestDefaults.legacyPlaceholderManifestURL
        )
        store.manifest = manifest
        store.state = .loaded

        await store.load()

        XCTAssertEqual(client.fetchCount, 0)
        XCTAssertEqual(store.state, .loaded)
    }

    @MainActor
    func testJobsStoreKeepsCachedReportAndShowsNoticeWhenRefreshFails() async throws {
        let report = try JSONDecoder.pavbot.decode(JobsReport.self, from: Self.jobsDataFixtureData)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let cache = JobsReportCache(defaults: defaults)
        cache.save(report, packageKey: "2026-06-25-0141", source: .jobsData)
        let dataArtifact = PavbotArtifact(
            id: "jobs-data",
            type: .jobsData,
            topic: "llm-ai-jobs-wroclaw",
            title: "Jobs data",
            path: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
            url: "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json",
            sizeBytes: 200,
            date: "2026-06-25",
            time: "01:41"
        )
        let package = TopicReportPackage(topic: .jobs, key: "2026-06-25-0141", artifacts: [dataArtifact])
        let store = JobsStore(
            client: JobsDataClient(
                fetchData: { _ in throw URLError(.notConnectedToInternet) },
                fetchText: { _ in throw URLError(.notConnectedToInternet) }
            ),
            cache: cache
        )

        await store.load(
            packages: [package],
            manifestURLString: "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            selectedDay: nil,
            selectedArtifactIDs: []
        )

        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.report?.opportunities.first?.company, "CKSource")
        XCTAssertEqual(store.cacheNotice, "Pokazuję ostatnie zapisane dane Jobs (2026-06-25 01:41, Dane strukturalne). Odświeżenie nie powiodło się.")
    }

    @MainActor
    func testRouterOpensArtifactFromNotificationUserInfo() throws {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        let router = AppRouter()

        router.handleNotification(userInfo: ["artifactID": "audio-2026-06-22"])
        router.resolvePendingArtifact(in: manifest)

        XCTAssertEqual(router.selectedTab, .research)
        XCTAssertEqual(router.selectedResearchTopic, .techNews)
        XCTAssertEqual(router.researchPath.map(\.id), ["audio-2026-06-22"])
        XCTAssertNil(router.pendingArtifactID)
    }

    @MainActor
    func testRouterStoresPendingArtifactFromLiveActivityURL() throws {
        let router = AppRouter()
        let url = try XCTUnwrap(URL(string: "pavbot://artifact?id=audio-2026-06-22"))

        router.handleOpenURL(url)

        XCTAssertEqual(router.selectedTab, .artifacts)
        XCTAssertEqual(router.pendingArtifactID, "audio-2026-06-22")
        XCTAssertTrue(router.artifactPath.isEmpty)
    }

    @MainActor
    func testRouterOpensSettingsFromAutomationNotificationUserInfo() {
        let router = AppRouter()
        router.selectedTab = .today

        router.handleNotification(userInfo: ["automationID": "mobile-current-events"])

        XCTAssertEqual(router.selectedTab, .settings)
        XCTAssertNil(router.pendingArtifactID)
    }

    @MainActor
    func testRouterOpensPulseDayTabFromPulseNewsNotificationUserInfo() {
        let router = AppRouter()
        router.selectedTab = .settings

        router.handleNotification(
            userInfo: [
                "artifactTopic": "puls-dnia-news",
                "artifactDate": "2026-06-26",
                "artifactIDs": ["pulse-data"]
            ]
        )

        XCTAssertEqual(router.selectedTab, .pulseDay)
        XCTAssertEqual(router.selectedReportDay, "2026-06-26")
        XCTAssertEqual(router.selectedReportArtifactIDs, ["pulse-data"])
        XCTAssertNil(router.pendingArtifactID)
        XCTAssertNil(router.artifactRoute)
    }

    @MainActor
    func testRouterOpensArtifactFilterFromSummaryNotificationUserInfo() {
        let router = AppRouter()
        router.selectedTab = .settings

        router.handleNotification(
            userInfo: [
                "artifactTopic": "tech-news",
                "artifactDate": "2026-06-22",
                "artifactIDs": ["run-2026-06-22", "audio-2026-06-22"]
            ]
        )

        XCTAssertEqual(router.selectedTab, .research)
        XCTAssertEqual(router.selectedResearchTopic, .techNews)
        XCTAssertEqual(router.selectedReportDay, "2026-06-22")
        XCTAssertEqual(router.selectedReportArtifactIDs, ["run-2026-06-22", "audio-2026-06-22"])
        XCTAssertTrue(router.artifactPath.isEmpty)
        XCTAssertNil(router.pendingArtifactID)
        XCTAssertNil(router.artifactRoute)
    }

    @MainActor
    func testRouterOpensJobsTabFromJobsNotificationUserInfo() {
        let router = AppRouter()
        router.selectedTab = .settings

        router.handleNotification(
            userInfo: [
                "artifactTopic": "llm-ai-jobs-wroclaw",
                "artifactDate": "2026-06-25",
                "artifactIDs": ["jobs-run-2026-06-25-0141"]
            ]
        )

        XCTAssertEqual(router.selectedTab, .jobs)
        XCTAssertEqual(router.selectedReportDay, "2026-06-25")
        XCTAssertEqual(router.selectedReportArtifactIDs, ["jobs-run-2026-06-25-0141"])
        XCTAssertTrue(router.jobsPath.isEmpty)
        XCTAssertNil(router.pendingArtifactID)
        XCTAssertNil(router.artifactRoute)
    }

    @MainActor
    func testRouterOpensTodayTabFromDailyWeatherNotificationUserInfo() {
        let router = AppRouter()
        router.selectedTab = .settings

        router.handleNotification(
            userInfo: [
                "notificationKind": "dailyWeather",
                "weatherDate": "2026-06-25",
                "city": "Wrocław",
                "reportID": "wroclaw-2026-06-25"
            ]
        )

        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertEqual(router.selectedWeatherDate, "2026-06-25")
        XCTAssertTrue(router.artifactPath.isEmpty)
        XCTAssertNil(router.pendingArtifactID)
        XCTAssertNil(router.artifactRoute)
    }

    private static func artifact(
        id: String,
        type: ArtifactType,
        topic: String,
        path: String,
        date: String,
        time: String? = nil
    ) -> PavbotArtifact {
        PavbotArtifact(
            id: id,
            type: type,
            topic: topic,
            title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            path: path,
            url: path,
            sizeBytes: 100,
            date: date,
            time: time
        )
    }

    private static let techResearchMarkdownFixture = """
    # Daily Research Report: tech-news
    Date: 2026-06-25
    Status: Material update

    ## Podsumowanie
    Dzisiaj AI i infrastruktura pokazują dwa mocne sygnały: OpenAI przyspiesza warstwę inference, a Cloudflare upraszcza produkty dla agentów.

    ## Nowe fakty
    - OpenAI i Broadcom pokazali układ inference dla dużych modeli. Źródła: [OpenAI](https://openai.com/news), [Broadcom](https://broadcom.com/news).
    - Cloudflare rozszerza OAuth dla agentów i produktów AI. Źródło: [Cloudflare](https://blog.cloudflare.com/agents-oauth).

    ## Tematy do podcastu
    | Priorytet | Tytuł | Dlaczego to ważne | Główne źródła |
    | --- | --- | --- | --- |
    | High | Agenci i compute | Łączy chipy, OAuth i produkty AI. | OpenAI; Cloudflare |

    ## Źródła
    - [OpenAI](https://openai.com/news)
    - [Cloudflare](https://blog.cloudflare.com/agents-oauth)
    """

    private static let polskaSwiatResearchMarkdownFixture = """
    # Daily Research Report: polska-swiat
    Date: 2026-06-25
    Status: Material update

    ## Summary
    Polska i świat mają dziś dwa czytelne tematy: bezpieczeństwo państwa oraz gospodarkę energii.

    ## Nowe fakty
    - MON i NATO zapowiedziały dodatkowe działania bezpieczeństwa na wschodniej flance. Source: [NATO](https://nato.int/news).
    - Rząd aktualizuje program energii dla firm i samorządów. Source: [KPRM](https://gov.pl/kprm).

    ## Recommended Actions
    - Obserwować komunikaty MON i KPRM.

    ## Sources
    - [NATO](https://nato.int/news)
    - [KPRM](https://gov.pl/kprm)
    """

    private static let researchDataFixtureData = """
    {
      "schemaVersion": 1,
      "topic": "tech-news",
      "runDate": "2026-06-25",
      "runTime": null,
      "status": "Material update",
      "leadParagraphs": [
        "Dzisiejsze wydanie pokazuje, że AI i produkty agentowe stają się głównym polem zmian.",
        "Najważniejszy wniosek dotyczy praktycznych integracji, kosztu wdrożeń i bezpieczeństwa."
      ],
      "summaryBullets": [
        "AI: OpenAI i Cloudflare rozwijają narzędzia agentowe."
      ],
      "articles": [
        {
          "id": "tech-openai-cloudflare",
          "section": "AI",
          "title": "OpenAI i Cloudflare wzmacniają warstwę agentową",
          "standfirst": "OpenAI i Cloudflare pokazują nowe narzędzia agentowe.",
          "whatHappened": "OpenAI i Cloudflare pokazują nowe narzędzia agentowe.",
          "whyItMatters": "To ważne, bo przyspiesza praktyczne wdrożenia AI.",
          "deeperAnalysis": [
            "Głębszy opis pokazuje wpływ na produkty, integracje i bezpieczeństwo agentów.",
            "Dla zespołów produktowych oznacza to potrzebę szybszego testowania uprawnień, źródeł danych i audytu działań agentów."
          ],
          "contextPoints": [
            "Co się stało: OpenAI i Cloudflare aktualizują warstwę agentową.",
            "Dlaczego ważne: temat wpływa na adopcję narzędzi AI w produktach.",
            "Na co patrzeć dalej: czy integracje przejdą z eksperymentu do produkcji."
          ],
          "sources": [
            { "title": "OpenAI", "url": "https://openai.com/news" },
            { "title": "Cloudflare", "url": "https://blog.cloudflare.com/agents-oauth" }
          ],
          "priority": "High",
          "tags": ["AI", "OpenAI", "Cloudflare"]
        }
      ],
      "podcastTopics": [],
      "checkedSources": [
        { "title": "OpenAI", "url": "https://openai.com/news" },
        { "title": "Cloudflare", "url": "https://blog.cloudflare.com/agents-oauth" }
      ]
    }
    """.data(using: .utf8)!

    private static var pulseNewsFixtureItems: [PulseNewsItem] {
        let sections = [
            "Polska",
            "Świat",
            "Polityka",
            "Bezpieczeństwo",
            "Gospodarka",
            "Technologia",
            "Alerty",
            "Polska",
            "Świat",
            "Gospodarka",
            "Technologia",
            "Bezpieczeństwo"
        ]
        return sections.enumerated().map { offset, section in
            let index = offset + 1
            return PulseNewsItem(
                id: "pulse-\(index)",
                section: section,
                title: "\(section): decyzja dnia \(index)",
                lead: "Krótki opis tematu \(index) z ostatnich godzin.",
                whatHappened: "Co się stało w temacie \(index).",
                keyFacts: ["Potwierdzony fakt \(index).", "Drugi fakt \(index)."],
                reactions: ["Reakcja instytucji \(index)."],
                whyItMatters: "Dlaczego temat \(index) jest ważny dla użytkownika.",
                context: "Kontekst tematu \(index) i wpływ na kolejne godziny.",
                watchNext: ["Obserwuj kolejne komunikaty w sprawie \(index)."],
                sources: [ResearchNewsSource(title: index.isMultiple(of: 2) ? "BBC" : "TVN24", url: "https://example.com/source-\(index)")],
                tags: [section, "Puls dnia"],
                priority: index <= 4 ? "High" : "Medium"
            )
        }
    }

    private static func pulseNewsDigest(
        runDate: String,
        runTime: String,
        headline: String,
        items: [PulseNewsItem] = pulseNewsFixtureItems
    ) -> PulseNewsDigest {
        PulseNewsDigest(
            schemaVersion: 1,
            topic: "puls-dnia-news",
            runDate: runDate,
            runTime: runTime,
            status: "Material update",
            headline: headline,
            summary: "Syntetyczny opis runu testowego.",
            items: items,
            checkedSources: [ResearchNewsSource(title: "TVN24", url: "https://example.com/source")]
        )
    }

    private static func pulseNewsFixtureTopic(id: String, title: String) -> TodayLiveTopic {
        TodayLiveTopic(
            id: id,
            scope: title.localizedCaseInsensitiveContains("Polska") ? .poland : .pulse,
            section: title.localizedCaseInsensitiveContains("Polska") ? "Polska" : "Gospodarka",
            title: title,
            lead: "Krótki opis do zapisania w archiwum.",
            keyFacts: ["Pierwszy fakt.", "Drugi fakt."],
            reactions: ["Reakcja instytucji."],
            whyItMatters: "Dlaczego temat jest ważny.",
            context: "Kontekst i tło tematu.",
            watchNext: ["Co obserwować dalej."],
            sources: [ResearchNewsSource(title: "TVN24", url: "https://example.com/archive")],
            tags: ["Puls dnia"],
            priority: "High"
        )
    }

    private static let pulseNewsDataFixtureData = """
    {
      "schemaVersion": 1,
      "topic": "puls-dnia-news",
      "runDate": "2026-06-26",
      "runTime": "12:00",
      "status": "Material update",
      "headline": "Puls dnia",
      "summary": "Najważniejsze tematy z ostatnich trzech godzin.",
      "items": [
        {
          "id": "pulse-1",
          "section": "Polska",
          "title": "Polska: decyzja dnia 1",
          "lead": "Krótki opis tematu 1 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 1.",
          "keyFacts": ["Potwierdzony fakt 1.", "Drugi fakt 1."],
          "reactions": ["Reakcja instytucji 1."],
          "whyItMatters": "Dlaczego temat 1 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 1 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 1."],
          "sources": [{ "title": "TVN24", "url": "https://example.com/source-1" }],
          "tags": ["Polska", "Puls dnia"],
          "priority": "High"
        },
        {
          "id": "pulse-2",
          "section": "Świat",
          "title": "Świat: decyzja dnia 2",
          "lead": "Krótki opis tematu 2 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 2.",
          "keyFacts": ["Potwierdzony fakt 2.", "Drugi fakt 2."],
          "reactions": ["Reakcja instytucji 2."],
          "whyItMatters": "Dlaczego temat 2 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 2 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 2."],
          "sources": [{ "title": "BBC", "url": "https://example.com/source-2" }],
          "tags": ["Świat", "Puls dnia"],
          "priority": "High"
        },
        {
          "id": "pulse-3",
          "section": "Polityka",
          "title": "Polityka: decyzja dnia 3",
          "lead": "Krótki opis tematu 3 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 3.",
          "keyFacts": ["Potwierdzony fakt 3.", "Drugi fakt 3."],
          "reactions": ["Reakcja instytucji 3."],
          "whyItMatters": "Dlaczego temat 3 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 3 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 3."],
          "sources": [{ "title": "CNN", "url": "https://example.com/source-3" }],
          "tags": ["Polityka", "Puls dnia"],
          "priority": "High"
        },
        {
          "id": "pulse-4",
          "section": "Bezpieczeństwo",
          "title": "Bezpieczeństwo: decyzja dnia 4",
          "lead": "Krótki opis tematu 4 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 4.",
          "keyFacts": ["Potwierdzony fakt 4.", "Drugi fakt 4."],
          "reactions": ["Reakcja instytucji 4."],
          "whyItMatters": "Dlaczego temat 4 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 4 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 4."],
          "sources": [{ "title": "NATO", "url": "https://example.com/source-4" }],
          "tags": ["Bezpieczeństwo", "Puls dnia"],
          "priority": "High"
        },
        {
          "id": "pulse-5",
          "section": "Gospodarka",
          "title": "Gospodarka: decyzja dnia 5",
          "lead": "Krótki opis tematu 5 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 5.",
          "keyFacts": ["Potwierdzony fakt 5.", "Drugi fakt 5."],
          "reactions": ["Reakcja instytucji 5."],
          "whyItMatters": "Dlaczego temat 5 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 5 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 5."],
          "sources": [{ "title": "BBC", "url": "https://example.com/source-5" }],
          "tags": ["Gospodarka", "Puls dnia"],
          "priority": "Medium"
        },
        {
          "id": "pulse-6",
          "section": "Technologia",
          "title": "Technologia: decyzja dnia 6",
          "lead": "Krótki opis tematu 6 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 6.",
          "keyFacts": ["Potwierdzony fakt 6.", "Drugi fakt 6."],
          "reactions": ["Reakcja instytucji 6."],
          "whyItMatters": "Dlaczego temat 6 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 6 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 6."],
          "sources": [{ "title": "CNN", "url": "https://example.com/source-6" }],
          "tags": ["Technologia", "Puls dnia"],
          "priority": "Medium"
        },
        {
          "id": "pulse-7",
          "section": "Alerty",
          "title": "Alerty: decyzja dnia 7",
          "lead": "Krótki opis tematu 7 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 7.",
          "keyFacts": ["Potwierdzony fakt 7.", "Drugi fakt 7."],
          "reactions": ["Reakcja instytucji 7."],
          "whyItMatters": "Dlaczego temat 7 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 7 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 7."],
          "sources": [{ "title": "TVN24", "url": "https://example.com/source-7" }],
          "tags": ["Alerty", "Puls dnia"],
          "priority": "Medium"
        },
        {
          "id": "pulse-8",
          "section": "Polska",
          "title": "Polska: decyzja dnia 8",
          "lead": "Krótki opis tematu 8 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 8.",
          "keyFacts": ["Potwierdzony fakt 8.", "Drugi fakt 8."],
          "reactions": ["Reakcja instytucji 8."],
          "whyItMatters": "Dlaczego temat 8 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 8 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 8."],
          "sources": [{ "title": "TVN24", "url": "https://example.com/source-8" }],
          "tags": ["Polska", "Puls dnia"],
          "priority": "Medium"
        },
        {
          "id": "pulse-9",
          "section": "Świat",
          "title": "Świat: decyzja dnia 9",
          "lead": "Krótki opis tematu 9 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 9.",
          "keyFacts": ["Potwierdzony fakt 9.", "Drugi fakt 9."],
          "reactions": ["Reakcja instytucji 9."],
          "whyItMatters": "Dlaczego temat 9 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 9 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 9."],
          "sources": [{ "title": "BBC", "url": "https://example.com/source-9" }],
          "tags": ["Świat", "Puls dnia"],
          "priority": "Medium"
        },
        {
          "id": "pulse-10",
          "section": "Gospodarka",
          "title": "Gospodarka: decyzja dnia 10",
          "lead": "Krótki opis tematu 10 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 10.",
          "keyFacts": ["Potwierdzony fakt 10.", "Drugi fakt 10."],
          "reactions": ["Reakcja instytucji 10."],
          "whyItMatters": "Dlaczego temat 10 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 10 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 10."],
          "sources": [{ "title": "CNN", "url": "https://example.com/source-10" }],
          "tags": ["Gospodarka", "Puls dnia"],
          "priority": "Medium"
        },
        {
          "id": "pulse-11",
          "section": "Technologia",
          "title": "Technologia: decyzja dnia 11",
          "lead": "Krótki opis tematu 11 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 11.",
          "keyFacts": ["Potwierdzony fakt 11.", "Drugi fakt 11."],
          "reactions": ["Reakcja instytucji 11."],
          "whyItMatters": "Dlaczego temat 11 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 11 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 11."],
          "sources": [{ "title": "BBC", "url": "https://example.com/source-11" }],
          "tags": ["Technologia", "Puls dnia"],
          "priority": "Medium"
        },
        {
          "id": "pulse-12",
          "section": "Bezpieczeństwo",
          "title": "Bezpieczeństwo: decyzja dnia 12",
          "lead": "Krótki opis tematu 12 z ostatnich godzin.",
          "whatHappened": "Co się stało w temacie 12.",
          "keyFacts": ["Potwierdzony fakt 12.", "Drugi fakt 12."],
          "reactions": ["Reakcja instytucji 12."],
          "whyItMatters": "Dlaczego temat 12 jest ważny dla użytkownika.",
          "context": "Kontekst tematu 12 i wpływ na kolejne godziny.",
          "watchNext": ["Obserwuj kolejne komunikaty w sprawie 12."],
          "sources": [{ "title": "NATO", "url": "https://example.com/source-12" }],
          "tags": ["Bezpieczeństwo", "Puls dnia"],
          "priority": "Medium"
        }
      ],
      "checkedSources": [
        { "title": "TVN24", "url": "https://www.tvn24.pl" },
        { "title": "BBC", "url": "https://www.bbc.com/news" },
        { "title": "CNN", "url": "https://www.cnn.com" }
      ]
    }
    """.data(using: .utf8)!

    private static let mobileNewsDataFixtureData = """
    {
      "schemaVersion": 1,
      "topic": "aktualne-wydarzenia-mobile",
      "runDate": "2026-06-25",
      "runTime": "10:15",
      "status": "Material update",
      "headline": "Wydanie dnia",
      "leadParagraphs": [
        "Dzisiejsze wydanie pokazuje, że Polska, bezpieczeństwo i pogoda tworzą najważniejszy kontekst dnia.",
        "Najmocniejszy sygnał dotyczy praktycznych decyzji, które mogą wpłynąć na obywateli i instytucje."
      ],
      "sections": [
        {
          "id": "polska",
          "title": "Polska",
          "summary": "Najważniejsze sygnały krajowe.",
          "articles": [
            {
              "id": "polska-gdansk",
              "section": "Polska",
              "title": "Gdańsk jako centrum rozmów",
              "lead": "Polska jest gospodarzem ważnych rozmów o Ukrainie i bezpieczeństwie regionu.",
              "facts": [
                "KPRM zapowiedziało udział premiera w konferencji.",
                "Rozmowy łączą odbudowę Ukrainy z bezpieczeństwem wschodniej flanki."
              ],
              "analysis": "To łączy dyplomację, gospodarkę i bezpieczeństwo w jednym praktycznym pakiecie.",
              "whyItMatters": "Użytkownik widzi, czy wydarzenie jest tylko ceremonialne, czy może przełożyć się na decyzje i umowy.",
              "sources": [
                { "title": "KPRM", "url": "https://www.gov.pl/web/premier" }
              ],
              "tags": ["Polska", "Ukraina", "Bezpieczeństwo"],
              "ttsText": "Polska jest gospodarzem ważnych rozmów o Ukrainie i bezpieczeństwie regionu. To łączy dyplomację, gospodarkę i bezpieczeństwo w jednym praktycznym pakiecie.",
              "priority": "High"
            }
          ]
        },
        {
          "id": "pogoda",
          "title": "Pogoda",
          "summary": "Ryzyka pogodowe są ważne dla codziennych decyzji.",
          "articles": [
            {
              "id": "pogoda-upaly",
              "section": "Pogoda",
              "title": "Upały i lokalne alerty",
              "lead": "RCB i IMGW wskazują na ryzyko upałów oraz lokalnych incydentów.",
              "facts": ["RCB publikuje komunikaty pogodowe."],
              "analysis": "Pogoda jest dziś tematem praktycznym, a nie tylko tłem dla polityki.",
              "whyItMatters": "To wpływa na zdrowie, transport i organizację dnia.",
              "sources": [
                { "title": "RCB", "url": "https://www.gov.pl/web/rcb" }
              ],
              "tags": ["Pogoda", "RCB"],
              "ttsText": "RCB i IMGW wskazują na ryzyko upałów oraz lokalnych incydentów. Pogoda jest dziś tematem praktycznym.",
              "priority": "Medium"
            }
          ]
        },
        {
          "id": "polityka",
          "title": "Polityka",
          "summary": "Decyzje instytucji państwowych i ich praktyczny kontekst.",
          "articles": [
            {
              "id": "polityka-sejm",
              "section": "Polityka",
              "title": "Nowe decyzje w Sejmie",
              "lead": "Sejmowy kalendarz wskazuje na decyzje, które mogą ustawić ton debaty publicznej.",
              "facts": [
                "Sejm opublikował harmonogram posiedzeń.",
                "Tematy obejmują prace komisji i decyzje legislacyjne."
              ],
              "analysis": "Reakcje polityczne będą zależeć od tego, czy decyzje przełożą się na konkretne głosowania i projekty ustaw.",
              "whyItMatters": "To pomaga odróżnić bieżący spór od spraw, które realnie zmienią prawo lub budżety.",
              "sources": [
                { "title": "Sejm", "url": "https://www.sejm.gov.pl" }
              ],
              "tags": ["Polityka", "Sejm"],
              "ttsText": "Sejmowy kalendarz wskazuje na decyzje, które mogą ustawić ton debaty publicznej. Reakcje polityczne będą zależeć od dalszych prac.",
              "priority": "Medium"
            }
          ]
        },
        {
          "id": "sprawy-zagraniczne",
          "title": "Sprawy zagraniczne",
          "summary": "Najważniejsze sygnały międzynarodowe z punktu widzenia Polski.",
          "articles": [
            {
              "id": "swiat-nato",
              "section": "Sprawy zagraniczne",
              "title": "Szczyt NATO i bezpieczeństwo regionu",
              "lead": "NATO zapowiada kolejne rozmowy o wschodniej flance i wsparciu Ukrainy.",
              "facts": [
                "NATO komunikuje priorytety bezpieczeństwa regionalnego.",
                "Temat Ukrainy pozostaje osią rozmów sojuszniczych."
              ],
              "analysis": "Reakcje państw regionu będą zależeć od skali deklaracji i praktycznych zobowiązań.",
              "whyItMatters": "Dla Polski to sygnał o kierunku odstraszania, zakupów i współpracy wojskowej.",
              "sources": [
                { "title": "NATO", "url": "https://www.nato.int" }
              ],
              "tags": ["NATO", "Bezpieczeństwo", "Ukraina"],
              "ttsText": "NATO zapowiada kolejne rozmowy o wschodniej flance i wsparciu Ukrainy. Dla Polski to sygnał o kierunku bezpieczeństwa.",
              "priority": "High"
            },
            {
              "id": "swiat-ue",
              "section": "Sprawy zagraniczne",
              "title": "UE reaguje na napięcia gospodarcze",
              "lead": "Instytucje Unii Europejskiej pokazują, że gospodarka i bezpieczeństwo są coraz mocniej połączone.",
              "facts": [
                "Komisja Europejska publikuje komunikaty o priorytetach gospodarczych.",
                "Państwa członkowskie szukają wspólnej odpowiedzi na napięcia."
              ],
              "analysis": "Reakcje rynku i rządów będą zależeć od tego, czy zapowiedzi przejdą w instrumenty finansowe.",
              "whyItMatters": "To wpływa na koszty, inwestycje i oczekiwania wobec polityki publicznej.",
              "sources": [
                { "title": "Komisja Europejska", "url": "https://ec.europa.eu" }
              ],
              "tags": ["UE", "Gospodarka"],
              "ttsText": "Instytucje Unii Europejskiej pokazują, że gospodarka i bezpieczeństwo są coraz mocniej połączone.",
              "priority": "Medium"
            }
          ]
        }
      ],
      "checkedSources": [
        { "title": "KPRM", "url": "https://www.gov.pl/web/premier" },
        { "title": "RCB", "url": "https://www.gov.pl/web/rcb" },
        { "title": "Sejm", "url": "https://www.sejm.gov.pl" },
        { "title": "NATO", "url": "https://www.nato.int" },
        { "title": "Komisja Europejska", "url": "https://ec.europa.eu" }
      ],
      "audioArtifacts": []
    }
    """.data(using: .utf8)!

    private static let fixtureData = """
    {
      "schemaVersion": 1,
      "title": "Pavbot Automation Manifest",
      "generatedAt": "2026-06-22T12:00:00+00:00",
      "rawBaseUrl": "https://raw.githubusercontent.com/example/pavbot/main/",
      "automations": [
        {
          "id": "research",
          "name": "Pavbot Tech Research 08:00",
          "enabled": true,
          "kind": "research",
          "topic": "tech-news",
          "topicPath": "research/tech-news",
          "cadence": "daily at 08:00 local time",
          "sourcePath": "docs/how-to-use.md",
          "sourceUrl": "https://raw.githubusercontent.com/example/pavbot/main/docs/how-to-use.md"
        },
        {
          "id": "podcast",
          "name": "Pavbot Tech Podcast 09:00",
          "enabled": true,
          "kind": "podcast",
          "topic": "tech-news",
          "topicPath": "research/tech-news",
          "cadence": "daily at 09:00 local time",
          "sourcePath": "docs/how-to-use.md",
          "sourceUrl": "https://raw.githubusercontent.com/example/pavbot/main/docs/how-to-use.md",
          "output": "research/tech-news/podcasts/YYYY-MM-DD/podcast.mp3",
          "outputUrl": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/podcasts/YYYY-MM-DD/podcast.mp3"
        }
      ],
      "topics": [
        {
          "slug": "tech-news",
          "title": "Topic Contract: tech-news",
          "path": "research/tech-news",
          "topicFilePath": "research/tech-news/topic.md",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/topic.md"
        }
      ],
      "artifacts": [
        {
          "id": "run-2026-06-22",
          "type": "run",
          "topic": "tech-news",
          "title": "Daily Research Report: tech-news",
          "path": "research/tech-news/runs/2026-06-22.md",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/runs/2026-06-22.md",
          "date": "2026-06-22",
          "sizeBytes": 100
        },
        {
          "id": "audio-2026-06-22",
          "type": "podcastAudio",
          "topic": "tech-news",
          "title": "Podcast audio",
          "path": "research/tech-news/podcasts/2026-06-22/podcast.mp3",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/podcasts/2026-06-22/podcast.mp3",
          "date": "2026-06-22",
          "sizeBytes": 100
        },
        {
          "id": "brief-pdf-2026-06-22",
          "type": "podcastBriefPdf",
          "topic": "tech-news",
          "title": "Podcast brief PDF",
          "path": "research/tech-news/podcasts/2026-06-22/brief.pdf",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/podcasts/2026-06-22/brief.pdf",
          "date": "2026-06-22",
          "sizeBytes": 100
        },
        {
          "id": "pdf-2026-06-22",
          "type": "pdf",
          "topic": "tech-news",
          "title": "Research PDF",
          "path": "research/tech-news/pdfs/2026-06-22-tech-news.pdf",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/pdfs/2026-06-22-tech-news.pdf",
          "date": "2026-06-22",
          "sizeBytes": 100
        },
        {
          "id": "run-2026-06-21",
          "type": "run",
          "topic": "tech-news",
          "title": "Daily Research Report: tech-news",
          "path": "research/tech-news/runs/2026-06-21.md",
          "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/runs/2026-06-21.md",
          "date": "2026-06-21",
          "sizeBytes": 100
        }
      ]
    }
    """.data(using: .utf8)!

    private static func dailyWeatherReport(city: String, id: String) throws -> DailyWeatherReport {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: dailyWeatherFixtureData) as? [String: Any])
        json["city"] = city
        json["id"] = id
        json["headline"] = "\(city): częściowe zachmurzenie i 21°C"
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: data)
    }

    private static let dailyWeatherFixtureData = """
    {
      "id": "wroclaw-2026-06-25",
      "city": "Wrocław",
      "date": "2026-06-25",
      "weekday": "czwartek",
      "generatedAt": "2026-06-25T05:31:00+00:00",
      "nameDays": ["Łucja", "Wilhelm"],
      "headline": "Wrocław: częściowe zachmurzenie i 21°C na start dnia",
      "summary": "Czwartek, 25 czerwca 2026. Częściowe zachmurzenie. Imieniny: Łucja, Wilhelm.",
      "recommendation": "Na dziś: dzień powinien obyć się bez większych opadów.",
      "temperature": {
        "current": 21,
        "apparent": 22.1,
        "min": 15.8,
        "max": 26.1,
        "unit": "°C"
      },
      "conditions": {
        "code": 2,
        "label": "Częściowe zachmurzenie"
      },
      "precipitation": {
        "probability": 20,
        "total": 0.4,
        "unit": "mm"
      },
      "wind": {
        "speed": 11.2,
        "unit": "km/h"
      },
      "humidity": 61,
      "sunrise": "2026-06-25T04:39",
      "sunset": "2026-06-25T21:12",
      "hourlyTemperature": [
        {
          "time": "2026-06-25T05:00",
          "temperature": 19.8,
          "unit": "°C"
        },
        {
          "time": "2026-06-25T06:00",
          "temperature": 21.4,
          "unit": "°C"
        },
        {
          "time": "2026-06-25T07:00",
          "temperature": 22.1,
          "unit": "°C"
        }
      ],
      "temperatureTimeline": [
        {
          "time": "2026-06-25T06:00",
          "temperature": 21.4,
          "unit": "°C"
        },
        {
          "time": "2026-06-25T07:00",
          "temperature": 22.1,
          "unit": "°C"
        }
      ],
      "source": "Open-Meteo Forecast API"
    }
    """.data(using: .utf8)!

    private static let todayHumorFixtureData = """
    {
      "id": "humor-2026-06-25-21",
      "title": "Wieczorny przegląd memów",
      "summary": "Na wieczór wpada krótki, trendowy przegląd humoru z sieci.",
      "generatedAt": "2026-06-25T19:15:00+00:00",
      "displayTime": "21:15",
      "nextRefreshAt": "2026-06-26T00:00:00+02:00",
      "refreshIntervalHours": 3,
      "source": "Reddit trend feed",
      "items": [
        {
          "id": "safe1",
          "title": "Kiedy deploy przechodzi za pierwszym razem",
          "caption": "Ten typ humoru zna każdy, kto choć raz czekał na zielone CI.",
          "sourceName": "r/ProgrammerHumor",
          "sourceURL": "https://www.reddit.com/r/ProgrammerHumor/comments/safe1/test/",
          "imageURL": "https://i.redd.it/example.png",
          "score": 1200,
          "comments": 42,
          "tags": ["dev", "tech"]
        },
        {
          "id": "safe2",
          "title": "Mój backlog po weekendzie",
          "caption": "Wygląda mało groźnie, dopóki go nie otworzysz.",
          "sourceName": "Pavbot fallback",
          "sourceURL": "",
          "imageURL": null,
          "score": null,
          "comments": null,
          "tags": ["praca"]
        }
      ]
    }
    """.data(using: .utf8)!

    private static let jobsDataFixtureData = """
    {
      "schemaVersion": 1,
      "status": "Material update",
      "runDate": "2026-06-25",
      "runTime": "01:41",
      "executiveSummary": "Runda przyniosła nowe role LLM/AI.",
      "opportunities": [
        {
          "rank": 1,
          "title": "Principal Applied AI Engineer",
          "company": "CKSource",
          "location": "Remote Poland",
          "workMode": "Remote",
          "compensation": "38 000-45 000 PLN",
          "seniority": "Principal",
          "fitSummary": "Agentic workflows i AI-assisted engineering.",
          "whyInteresting": "Silny praktyczny fit do systemów LLM.",
          "uncertainty": "Tytuł różni się między hubem i kartą.",
          "sourceURLs": ["https://example.com/job"],
          "tags": ["LLM", "Agentic AI"]
        }
      ],
      "changes": ["Nowa oficjalna rola"],
      "risks": ["Drift tytułu"],
      "recommendedActions": ["Sprawdzić status w kolejnej rundzie"],
      "checkedSources": [
        {
          "title": "CKSource careers",
          "url": "https://example.com/careers",
          "status": "checked"
        }
      ]
    }
    """.data(using: .utf8)!

    private static func jobsPackage(
        date: String,
        time: String,
        includeData: Bool = true,
        includeRun: Bool = false
    ) -> TopicReportPackage {
        let compactTime = time.replacingOccurrences(of: ":", with: "")
        var artifacts: [PavbotArtifact] = []

        if includeData {
            artifacts.append(
                PavbotArtifact(
                    id: "jobs-data-\(date)-\(compactTime)",
                    type: .jobsData,
                    topic: "llm-ai-jobs-wroclaw",
                    title: "Jobs data",
                    path: "research/llm-ai-jobs-wroclaw/data/\(date)-\(compactTime)-jobs.json",
                    url: "research/llm-ai-jobs-wroclaw/data/\(date)-\(compactTime)-jobs.json",
                    sizeBytes: 200,
                    date: date,
                    time: time
                )
            )
        }

        if includeRun {
            artifacts.append(
                PavbotArtifact(
                    id: "jobs-run-\(date)-\(compactTime)",
                    type: .run,
                    topic: "llm-ai-jobs-wroclaw",
                    title: "LLM/AI Jobs Wrocław",
                    path: "research/llm-ai-jobs-wroclaw/runs/\(date)-\(compactTime).md",
                    url: "research/llm-ai-jobs-wroclaw/runs/\(date)-\(compactTime).md",
                    sizeBytes: 200,
                    date: date,
                    time: time
                )
            )
        }

        return TopicReportPackage(
            topic: .jobs,
            key: "\(date)-\(compactTime)",
            artifacts: artifacts
        )
    }

    private static func jobsHistoryData(
        date: String,
        time: String,
        company: String,
        title: String,
        workMode: String,
        sourceURL: String
    ) throws -> Data {
        let opportunity = JobOpportunity(
            rank: 1,
            title: title,
            company: company,
            location: workMode.localizedCaseInsensitiveContains("remote") ? "Remote Poland" : "Wrocław",
            workMode: workMode,
            compensation: "38 000-45 000 PLN",
            seniority: title.localizedCaseInsensitiveContains("principal") ? "Principal" : "Senior",
            fitSummary: "Rola zawiera LLM, RAG i agentic workflows.",
            whyInteresting: "Dobre dopasowanie do praktycznych systemów AI.",
            uncertainty: "Wymaga potwierdzenia statusu w kolejnej rundzie.",
            sourceURLs: [sourceURL],
            tags: ["LLM", "RAG"]
        )
        let report = JobsReport(
            schemaVersion: 1,
            status: "Material update",
            runDate: date,
            runTime: time,
            executiveSummary: "Runda \(date) \(time) zawiera role AI/LLM.",
            opportunities: [opportunity],
            changes: ["Nowa lub potwierdzona rola"],
            risks: [],
            recommendedActions: ["Sprawdzić status w kolejnej rundzie"],
            checkedSources: [
                JobsCheckedSource(title: company, url: sourceURL, status: "checked")
            ]
        )
        return try JSONEncoder().encode(report)
    }

    private static let jobsMarkdownFixture = """
    # LLM/AI Jobs Wrocław

    Date: 2026-06-25 01:41 CEST
    Status: Material update

    ## Zakres sprawdzony

    - Sprawdzone źródło: [CKSource careers](https://cksource.com/careers/)
    - Sprawdzone źródło: [Tiugo Technologies - Principal AI Engineer](https://tiugotech.recruitee.com/o/principal-ai-engineer)

    ## Podsumowanie zarządcze

    Runda z `2026-06-25 01:41 CEST` przyniosła trzy materialne sygnały. CKSource
    otworzył nową rolę, a Accenture pokazał klaster GenAI dla Wrocławia.

    ## Najciekawsze nowe lub materialnie zmienione role

    ### 1. CKSource / Tiugo Technologies - Principal Applied AI Engineer

    - Dlaczego interesujące: jedna z najmocniejszych ofert dla praktycznych systemów agentowych.
    - Fit LLM/AI: agentic workflows, AI-assisted development systems, LLM.
    - Lokalizacja/remote: `Remote`; hub kariery pokazuje `Remote Warsaw Poznań`.
    - Wynagrodzenie: `38 000-45 000 PLN` B2B miesięcznie.
    - Niepewność: tytuł ma lekki drift.
    - Źródła: [CKSource](https://cksource.com/careers/), [Tiugo](https://tiugotech.recruitee.com/o/principal-ai-engineer)

    ### 2. Accenture - Senior GenAI Engineer

    - Dlaczego interesujące: produkcyjne systemy agentowe i RAG.
    - Fit LLM/AI: autonomous multi-agent systems, RAG, vector databases.
    - Lokalizacja/remote: `Wrocław`, `Hybrid`.
    - Wynagrodzenie: brak publicznych widełek.
    - Niepewność: mapa miast pochodzi z publicznego mirrora.
    - Źródła: [Accenture](https://www.accenture.com/example)

    ## Zmiany od poprzedniej rundy

    - Dodano CKSource.
    - Dodano Accenture.

    ## Ryzyka i niepewności

    - Accenture wymaga dalszego sprawdzenia lokalizacji.

    ## Rekomendowane akcje

    - Sprawdzić Accenture w kolejnej rundzie.
    """

    private static let jobsEnglishMarkdownFixture = """
    # LLM/AI Jobs Wrocław

    Date: 2026-06-24 19:21 CEST
    Status: Material update

    ## Scope Checked

    - Source checked: [EPAM - Lead AI Engineer](https://careers.epam.com/en/vacancy/lead-ai-engineer)
    - Source checked: [Acaisoft careers](https://www.acaisoft.com/careers)

    ## Executive Summary

    Runda z `2026-06-24 19:21 CEST` przyniosła materialny update z dwóch źródeł:
    EPAM i ACAISOFT. Najmocniejszy sygnał dotyczy remote Poland oraz RAG.

    ## Top New Or Materially Changed Roles

    ### 1. EPAM - Lead AI Engineer

    - Why interesting: AI platform work with LLM-driven solutions.
    - Fit LLM/AI: RAG, agent workflows, LLM platforms and APIs.
    - Location: `Remote in Poland`.
    - Compensation: brak publicznych widełek.
    - Uncertainty: public page does not expose salary.
    - Sources: [EPAM role](https://careers.epam.com/en/vacancy/lead-ai-engineer)

    ### 2. ACAISOFT - Python Engineer with C++ (AI project)

    - Why interesting: AI evaluation and agent systems.
    - Fit LLM/AI: AI project, agent verification, Python.
    - Location: `Remote Poland`.
    - Compensation: not public.
    - Uncertainty: unit not rendered consistently.
    - Sources: [ACAISOFT](https://www.acaisoft.com/job/python-engineer-with-c-ai-project)

    ## Changes Since Previous Run

    - Added EPAM.

    ## Risks

    - Salary data is incomplete.

    ## Recommended Actions

    - Check EPAM again in the next round.
    """

    private func manifestWithAdditionalArtifacts(_ artifacts: [PavbotArtifact]) throws -> PavbotManifest {
        let manifest = try JSONDecoder.pavbot.decode(PavbotManifest.self, from: Self.fixtureData)
        return PavbotManifest(
            schemaVersion: manifest.schemaVersion,
            title: manifest.title,
            generatedAt: manifest.generatedAt,
            rawBaseUrl: manifest.rawBaseUrl,
            automations: manifest.automations,
            topics: manifest.topics,
            artifacts: manifest.artifacts + artifacts
        )
    }

    private static let newArtifact = PavbotArtifact(
        id: "new-run-2026-06-23",
        type: .run,
        topic: "tech-news",
        title: "Daily Research Report: tech-news",
        path: "research/tech-news/runs/2026-06-23.md",
        url: "research/tech-news/runs/2026-06-23.md",
        sizeBytes: 200,
        date: "2026-06-23",
        time: nil
    )

    private static let newAutomation = PavbotAutomation(
        id: "mobile-current-events",
        name: "Pavbot Aktualne Wydarzenia Mobile 10:15",
        enabled: true,
        kind: .research,
        topic: "aktualne-wydarzenia-mobile",
        topicPath: "research/aktualne-wydarzenia-mobile",
        cadence: "daily at 10:15 local time",
        sourcePath: "docs/how-to-use.md",
        sourceUrl: "https://raw.githubusercontent.com/example/pavbot/main/docs/how-to-use.md",
        output: "research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-mobile-brief.pdf",
        outputUrl: "https://raw.githubusercontent.com/example/pavbot/main/research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-mobile-brief.pdf"
    )

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private struct StubManifestClient: ManifestFetching {
    let manifest: PavbotManifest

    func fetchManifest(from url: URL) async throws -> PavbotManifest {
        manifest
    }
}

private final class CountingFailingManifestClient: ManifestFetching {
    private(set) var fetchCount = 0

    func fetchManifest(from url: URL) async throws -> PavbotManifest {
        fetchCount += 1
        throw URLError(.badServerResponse)
    }
}

private final class SpySpeechAudioSession: SpeechAudioSessionConfiguring {
    private(set) var activateCount = 0
    private(set) var deactivateCount = 0

    func activateForSpeech() throws {
        activateCount += 1
    }

    func deactivateAfterSpeech() {
        deactivateCount += 1
    }
}

private final class SpyHapticGenerator: PavbotHapticGenerating {
    private(set) var events: [PavbotHapticEvent] = []

    func play(_ event: PavbotHapticEvent) {
        events.append(event)
    }
}

private struct FailingWeatherBriefClient: WeatherBriefFetching {
    let error: Error

    func fetchLatestReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport {
        throw error
    }
}

private actor URLRequestCapture {
    private var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }

    func first() -> URL? {
        urls.first
    }

    func all() -> [URL] {
        urls
    }
}

private final class CapturedRequestStore {
    private let lock = NSLock()
    private var storedRequest: URLRequest?
    private var storedBody: Data?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    var body: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedBody
    }

    func record(_ request: URLRequest, body: Data?) {
        lock.lock()
        storedRequest = request
        storedBody = body
        lock.unlock()
    }
}

private extension URLRequest {
    var pavbotCapturedBody: Data? {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class CapturingURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
private final class SpyWeatherBriefClient: WeatherBriefFetching {
    let latestReport: DailyWeatherReport
    private(set) var latestLocations: [WeatherBriefLocation?] = []

    init(latestReport: DailyWeatherReport) {
        self.latestReport = latestReport
    }

    func fetchLatestReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport {
        latestLocations.append(location)
        return latestReport
    }
}

@MainActor
private final class DelayedWeatherBriefClient: WeatherBriefFetching {
    let latestReport: DailyWeatherReport
    private(set) var fetchCount = 0

    init(latestReport: DailyWeatherReport) {
        self.latestReport = latestReport
    }

    func fetchLatestReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport {
        fetchCount += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        return latestReport
    }
}

@MainActor
private final class SpyArtifactNotifier: ArtifactNotifying {
    private(set) var notifiedArtifactIDs: [String] = []
    private(set) var notifiedAutomationIDs: [String] = []

    func notify(artifacts: [PavbotArtifact], automations: [PavbotAutomation], manifestURL: URL) async {
        notifiedArtifactIDs = artifacts.map(\.id)
        notifiedAutomationIDs = automations.map(\.id)
    }
}
