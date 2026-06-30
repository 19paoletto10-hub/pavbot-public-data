import SwiftUI

enum PavbotViewportClass: Equatable {
    case phone
    case tablet
    case wide

    static func resolve(
        width: CGFloat?,
        horizontalSizeClass: UserInterfaceSizeClass?,
        isRunningOnMac: Bool = ProcessInfo.processInfo.isiOSAppOnMac
    ) -> PavbotViewportClass {
        if let width {
            if width < 700, !isRunningOnMac {
                return .phone
            }
            if width >= 1100 || isRunningOnMac {
                return .wide
            }
            return .tablet
        }

        if isRunningOnMac {
            return .wide
        }
        return horizontalSizeClass == .regular ? .tablet : .phone
    }
}

struct PavbotAdaptiveLayout: Equatable {
    let viewport: PavbotViewportClass

    static func resolve(
        width: CGFloat?,
        horizontalSizeClass: UserInterfaceSizeClass?,
        isRunningOnMac: Bool = ProcessInfo.processInfo.isiOSAppOnMac
    ) -> PavbotAdaptiveLayout {
        PavbotAdaptiveLayout(
            viewport: PavbotViewportClass.resolve(
                width: width,
                horizontalSizeClass: horizontalSizeClass,
                isRunningOnMac: isRunningOnMac
            )
        )
    }

    static let phone = PavbotAdaptiveLayout(viewport: .phone)

    var isPhone: Bool {
        viewport == .phone
    }

    var usesDashboardLayout: Bool {
        viewport != .phone
    }

    var contentMaxWidth: CGFloat? {
        switch viewport {
        case .phone:
            nil
        case .tablet:
            1040
        case .wide:
            1520
        }
    }

    var horizontalPadding: CGFloat {
        switch viewport {
        case .phone:
            20
        case .tablet:
            28
        case .wide:
            36
        }
    }

    var verticalPadding: CGFloat {
        switch viewport {
        case .phone:
            18
        case .tablet:
            24
        case .wide:
            30
        }
    }

    var sectionSpacing: CGFloat {
        switch viewport {
        case .phone:
            18
        case .tablet:
            22
        case .wide:
            26
        }
    }

    var cardSpacing: CGFloat {
        switch viewport {
        case .phone:
            12
        case .tablet:
            16
        case .wide:
            20
        }
    }

    var cardCornerRadius: CGFloat {
        switch viewport {
        case .phone:
            18
        case .tablet:
            22
        case .wide:
            26
        }
    }

    var weatherTileMinHeight: CGFloat {
        switch viewport {
        case .phone:
            156
        case .tablet:
            172
        case .wide:
            188
        }
    }

    var weatherMetricsMaxWidth: CGFloat {
        switch viewport {
        case .phone:
            .infinity
        case .tablet:
            460
        case .wide:
            520
        }
    }

    var humorCardMinWidth: CGFloat {
        switch viewport {
        case .phone:
            250
        case .tablet:
            280
        case .wide:
            320
        }
    }

    var humorCardMinHeight: CGFloat {
        switch viewport {
        case .phone:
            286
        case .tablet:
            304
        case .wide:
            322
        }
    }

    var jobsCardMinWidth: CGFloat {
        switch viewport {
        case .phone:
            260
        case .tablet:
            300
        case .wide:
            340
        }
    }

    var artifactTileMinWidth: CGFloat {
        switch viewport {
        case .phone:
            156
        case .tablet:
            220
        case .wide:
            280
        }
    }

    var artifactTileMaxWidth: CGFloat {
        switch viewport {
        case .phone:
            230
        case .tablet:
            300
        case .wide:
            360
        }
    }

    var infoCardMinWidth: CGFloat {
        switch viewport {
        case .phone:
            260
        case .tablet:
            320
        case .wide:
            380
        }
    }

    var sheetMinWidth: CGFloat? {
        switch viewport {
        case .phone:
            nil
        case .tablet:
            920
        case .wide:
            1120
        }
    }

    var sheetIdealWidth: CGFloat? {
        switch viewport {
        case .phone:
            nil
        case .tablet:
            1040
        case .wide:
            1320
        }
    }

    var sheetMaxWidth: CGFloat {
        switch viewport {
        case .phone:
            .infinity
        case .tablet:
            1180
        case .wide:
            1540
        }
    }

    var sheetMinHeight: CGFloat? {
        switch viewport {
        case .phone:
            nil
        case .tablet:
            760
        case .wide:
            840
        }
    }

    var sheetIdealHeight: CGFloat? {
        switch viewport {
        case .phone:
            nil
        case .tablet:
            920
        case .wide:
            1040
        }
    }

    func adaptiveColumns(minimum: CGFloat, maximum: CGFloat? = nil, spacing: CGFloat? = nil) -> [GridItem] {
        let resolvedSpacing = spacing ?? cardSpacing
        if let maximum {
            return [GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: resolvedSpacing)]
        }
        return [GridItem(.adaptive(minimum: minimum), spacing: resolvedSpacing)]
    }
}

private struct PavbotAdaptiveLayoutKey: EnvironmentKey {
    static let defaultValue = PavbotAdaptiveLayout.phone
}

extension EnvironmentValues {
    var pavbotAdaptiveLayout: PavbotAdaptiveLayout {
        get { self[PavbotAdaptiveLayoutKey.self] }
        set { self[PavbotAdaptiveLayoutKey.self] = newValue }
    }
}

struct PavbotUserFacingError: Equatable {
    enum Context: Equatable {
        case manifest
        case jobs
        case weather
        case notifier
        case audio
        case preview
    }

    let title: String
    let message: String
    let actionTitle: String
    let actionSystemImage: String
    let systemImage: String
    let tint: Color

    static func == (lhs: PavbotUserFacingError, rhs: PavbotUserFacingError) -> Bool {
        lhs.title == rhs.title
            && lhs.message == rhs.message
            && lhs.actionTitle == rhs.actionTitle
            && lhs.actionSystemImage == rhs.actionSystemImage
            && lhs.systemImage == rhs.systemImage
    }

    static func manifest(_ message: String) -> PavbotUserFacingError {
        PavbotUserFacingError(
            title: "Manifest wymaga konfiguracji",
            message: "Wklej publiczny GitHub raw manifest URL w ustawieniach. \(polishMessage(from: message))",
            actionTitle: "Otwórz ustawienia",
            actionSystemImage: "gearshape",
            systemImage: "doc.badge.gearshape",
            tint: .orange
        )
    }

    static func custom(
        title: String,
        message: String,
        actionTitle: String = "Spróbuj ponownie",
        actionSystemImage: String? = nil,
        systemImage: String = "exclamationmark.triangle",
        tint: Color = .orange
    ) -> PavbotUserFacingError {
        PavbotUserFacingError(
            title: title,
            message: polishMessage(from: message),
            actionTitle: actionTitle,
            actionSystemImage: actionSystemImage ?? Self.actionSystemImage(for: actionTitle),
            systemImage: systemImage,
            tint: tint
        )
    }

    static func network(_ error: Error, context: Context) -> PavbotUserFacingError {
        let rawMessage = polishMessage(from: error.localizedDescription)
        switch context {
        case .weather:
            return PavbotUserFacingError(
                title: "Nie udało się pobrać pogody",
                message: "Sprawdź połączenie z notifierem i spróbuj ponownie. Szczegóły: \(rawMessage)",
                actionTitle: "Spróbuj ponownie",
                actionSystemImage: "arrow.clockwise",
                systemImage: "cloud.sun.fill",
                tint: .blue
            )
        case .jobs:
            return PavbotUserFacingError(
                title: "Nie udało się pobrać danych Jobs",
                message: "Aplikacja pokaże ostatnie zapisane dane, jeśli są dostępne. Szczegóły: \(rawMessage)",
                actionTitle: "Odśwież dane",
                actionSystemImage: "arrow.clockwise",
                systemImage: "briefcase.fill",
                tint: .indigo
            )
        case .notifier:
            return PavbotUserFacingError(
                title: "Notifier jest niedostępny",
                message: "Sprawdź Docker, Cloudflare Tunnel i adres serwera powiadomień. Szczegóły: \(rawMessage)",
                actionTitle: "Sprawdź status",
                actionSystemImage: "antenna.radiowaves.left.and.right",
                systemImage: "antenna.radiowaves.left.and.right",
                tint: .orange
            )
        case .preview:
            return PavbotUserFacingError(
                title: "Nie udało się otworzyć podglądu",
                message: "Plik może być chwilowo niedostępny albo manifest wskazuje nieaktualny URL. Szczegóły: \(rawMessage)",
                actionTitle: "Spróbuj ponownie",
                actionSystemImage: "arrow.clockwise",
                systemImage: "doc.text.magnifyingglass",
                tint: .red
            )
        case .audio:
            return audio(rawMessage)
        case .manifest:
            return manifest(rawMessage)
        }
    }

    static func audio(_ message: String) -> PavbotUserFacingError {
        PavbotUserFacingError(
            title: "Nie udało się odtworzyć audio",
            message: polishMessage(from: message),
            actionTitle: "Otwórz plik źródłowy",
            actionSystemImage: "arrow.up.right.square",
            systemImage: "waveform.badge.exclamationmark",
            tint: .purple
        )
    }

    static func preview(_ message: String) -> PavbotUserFacingError {
        PavbotUserFacingError(
            title: "Podgląd jest niedostępny",
            message: polishMessage(from: message),
            actionTitle: "Otwórz plik źródłowy",
            actionSystemImage: "arrow.up.right.square",
            systemImage: "doc.text.magnifyingglass",
            tint: .red
        )
    }

    static func polishMessage(from message: String) -> String {
        switch message {
        case let value where value.contains("Set your public GitHub raw manifest URL"):
            "Wklej adres GitHub raw manifest URL, którego używa repozytorium automatyzacji."
        case let value where value.contains("Enter a valid manifest URL"):
            "Wpisz poprawny adres manifestu."
        case let value where value.contains("Showing cached data"):
            "Pokazuję dane z pamięci, bo odświeżenie nie powiodło się."
        case let value where value.contains("Reddit OAuth credentials"):
            "Radar memów wymaga konfiguracji Reddit OAuth w notifierze."
        case let value where value.contains("cancelled") || value.contains("The request timed out"):
            "Połączenie trwało zbyt długo. Sprawdź internet, Docker i Cloudflare Tunnel."
        case let value where value.contains("offline") || value.contains("not connected"):
            "Brak połączenia z siecią albo serwer notifiera jest niedostępny."
        case let value where value.isEmpty:
            "Spróbuj ponownie za chwilę."
        default:
            message
        }
    }

    private static func actionSystemImage(for actionTitle: String) -> String {
        let normalized = actionTitle.lowercased()
        if normalized.contains("ustaw") {
            return "gearshape"
        }
        if normalized.contains("status") {
            return "antenna.radiowaves.left.and.right"
        }
        if normalized.contains("plik") || normalized.contains("źród") || normalized.contains("zrodl") {
            return "arrow.up.right.square"
        }
        return "arrow.clockwise"
    }
}

enum PavbotLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(PavbotUserFacingError)

    var isLoading: Bool {
        self == .loading
    }

    var error: PavbotUserFacingError? {
        if case .failed(let error) = self {
            return error
        }
        return nil
    }
}

enum PavbotCacheNoticeCopy {
    static func refreshFailed(context: String) -> String {
        "Nie pobrano świeżych danych. Pokazuję zapisane dane: \(context)."
    }

    static func refreshing(context: String) -> String {
        "Odświeżam dane: \(context)..."
    }
}

struct PavbotInteractiveSurfaceConfiguration: Equatable {
    let isReduceMotionEnabled: Bool

    var pressedScale: CGFloat {
        isReduceMotionEnabled ? 1.0 : 0.975
    }

    var shadowRadius: CGFloat {
        isReduceMotionEnabled ? 0 : 12
    }

    var shadowOpacity: Double {
        isReduceMotionEnabled ? 0 : 0.08
    }

    var borderOpacity: Double {
        0.16
    }
}

struct PavbotInteractiveSurfaceButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var isSelected = false
    var cornerRadius: CGFloat = 17

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let surface = PavbotInteractiveSurfaceConfiguration(isReduceMotionEnabled: accessibilityReduceMotion)

        configuration.label
            .scaleEffect(configuration.isPressed ? surface.pressedScale : 1.0)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.70) : tint.opacity(surface.borderOpacity), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: Color.black.opacity(surface.shadowOpacity), radius: surface.shadowRadius, x: 0, y: 6)
            .animation(accessibilityReduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct PavbotScreenHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PavbotPremiumScreenScaffold<Content: View>: View {
    let layout: PavbotAdaptiveLayout
    var spacing: CGFloat?
    let content: Content

    init(
        layout: PavbotAdaptiveLayout,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.layout = layout
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing ?? layout.sectionSpacing) {
                content
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.vertical, layout.verticalPadding)
            .frame(maxWidth: layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(PavbotPremiumScreenBackground())
    }
}

struct PavbotPremiumScreenBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0.74),
                    Color.blue.opacity(0.045),
                    Color.green.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct PavbotTabInfoContent: Identifiable {
    let id: String
    let title: String
    let eyebrow: String
    let summary: String
    let systemImage: String
    let tint: Color
    let sections: [PavbotTabInfoSection]
    let tips: [String]

    static let today = PavbotTabInfoContent(
        id: "today",
        title: "Dzisiaj",
        eyebrow: "Daily cockpit",
        summary: "Karta zbiera najważniejsze sygnały dnia: kartkę z datą i polskim powiedzeniem, pogodę, opady godzinowe, Reddit Radar oraz następne kroki pod radarem.",
        systemImage: "sun.max.fill",
        tint: .blue,
        sections: [
            PavbotTabInfoSection(
                title: "Jak korzystać",
                systemImage: "hand.tap.fill",
                body: "Zacznij od tytułu dnia i kartki z kalendarza, potem sprawdź kartę decyzji pogodowej. Tapnij Opady, żeby zobaczyć poradę i miniwykres godzinowy."
            ),
            PavbotTabInfoSection(
                title: "Co możesz sprawdzić",
                systemImage: "cloud.rain.fill",
                body: "Zobacz praktyczny opis pogody, godziny możliwych opadów, zakres temperatur, posty Reddit Radar z obrazami oraz skróty do kolejnych sekcji pod radarem."
            )
        ],
        tips: [
            "Kartka z kalendarza zmienia się codziennie i działa offline.",
            "Przesuwaj Reddit Radar w bok, żeby porównać posty po opisie i obrazie.",
            "Następne kroki znajdziesz pod Reddit Radar, żeby najpierw zobaczyć najświeższy kontekst."
        ]
    )

    static func pulseDay(subtabTitle: String) -> PavbotTabInfoContent {
        let isHistory = subtabTitle == "Historia"
        return PavbotTabInfoContent(
            id: "pulse-day-\(subtabTitle)",
            title: "Puls Dnia · \(subtabTitle)",
            eyebrow: isHistory ? "Historia briefingów" : "Najnowszy briefing",
            summary: isHistory
                ? "Ta podzakładka pokazuje poprzednie wydania Pulsu Dnia, żeby szybko wrócić do kontekstu z ostatnich publikacji."
                : "Ta podzakładka pokazuje aktualny skrót najważniejszych tematów bez mieszania go z technicznymi plikami.",
            systemImage: isHistory ? "clock.arrow.circlepath" : "globe.europe.africa.fill",
            tint: .orange,
            sections: [
                PavbotTabInfoSection(
                    title: "Jak korzystać",
                    systemImage: isHistory ? "calendar" : "newspaper.fill",
                    body: isHistory
                        ? "W historii widzisz jeden wspólny widok zapisanych i wcześniejszych briefingów bez dodatkowych podzakładek. Otwórz temat, żeby wrócić do szczegółów."
                        : "Czytaj najnowszy briefing od góry, otwieraj temat po szczegóły i zapisuj lokalnie newsy, do których chcesz wrócić."
                ),
                PavbotTabInfoSection(
                    title: "Co możesz sprawdzić",
                    systemImage: "checklist",
                    body: isHistory
                        ? "Sprawdzisz archiwalne tematy, ich źródła oraz materiały zapisane lokalnie. Historia runów może być czyszczona, ale lokalnie zapisane newsy zostają."
                        : "Zobaczysz bieżące tematy, świeżość publikacji, źródła i lokalne akcje zapisu najważniejszych newsów."
                )
            ],
            tips: isHistory
                ? [
                    "Widok zapisanych pokazuje wszystkie lokalnie zapisane newsy razem.",
                    "Historia pomaga porównać kilka wydań bez opuszczania karty."
                ]
                : [
                    "Najpierw otwórz top temat, potem przejdź do mniej pilnych kart.",
                    "Zapisuj tylko materiały, do których realnie chcesz wrócić później."
                ]
        )
    }

    static func jobs(subtabTitle: String) -> PavbotTabInfoContent {
        let isAllOffers = subtabTitle == "Wszystkie oferty"
        return PavbotTabInfoContent(
            id: "jobs-\(subtabTitle)",
            title: "Jobs · \(subtabTitle)",
            eyebrow: isAllOffers ? "Pełny radar ofert" : "Brief dnia",
            summary: isAllOffers
                ? "Ta podzakładka służy do przeglądania szerszej historii ról AI/LLM, filtrowania i porównywania ofert między raportami."
                : "Ta podzakładka daje szybki skrót najważniejszych ról AI/LLM i zmian w najnowszym raporcie.",
            systemImage: isAllOffers ? "rectangle.grid.2x2.fill" : "briefcase.fill",
            tint: .indigo,
            sections: [
                PavbotTabInfoSection(
                    title: "Jak korzystać",
                    systemImage: "slider.horizontal.3",
                    body: isAllOffers
                        ? "Filtruj po typie roli, używaj wyszukiwarki dla firm i stacku, a potem otwieraj szczegóły konkretnych ofert."
                        : "Najpierw przeczytaj brief dnia. Jeśli potrzebujesz więcej kontekstu, rozwiń hero i przejdź do top ról lub historii ofert."
                ),
                PavbotTabInfoSection(
                    title: "Co możesz sprawdzić",
                    systemImage: "sparkles",
                    body: isAllOffers
                        ? "Porównasz role z kilku runów, ich status, lokalizację, tryb pracy i powtarzalność ofert."
                        : "Zobaczysz nowe lub zmienione oferty, dopasowanie do AI/LLM, lokalizację, tryb pracy i wynagrodzenie, jeśli jest dostępne."
                )
            ],
            tips: isAllOffers
                ? [
                    "Używaj historii, gdy chcesz sprawdzić, czy oferta powtarza się w kolejnych raportach.",
                    "Szukaj po firmie albo technologii, jeśli interesuje Cię konkretny stack."
                ]
                : [
                    "Brief jest najlepszy do szybkiego porannego przeglądu bez przeładowania ekranu.",
                    "Otwórz szczegóły oferty, żeby zobaczyć kontekst i link do źródła."
                ]
        )
    }

    static func research(topicTitle: String, topicSystemImage: String, topicTint: Color) -> PavbotTabInfoContent {
        PavbotTabInfoContent(
            id: "research-\(topicTitle)",
            title: "Research · \(topicTitle)",
            eyebrow: "Wybrany temat",
            summary: "Ta podzakładka pokazuje aktualnie wybrany temat Research: raporty, artykuły, PDF-y, audio i zapisane materiały w jednym miejscu.",
            systemImage: topicSystemImage,
            tint: topicTint,
            sections: [
                PavbotTabInfoSection(
                    title: "Jak korzystać",
                    systemImage: "rectangle.stack.fill",
                    body: "Wybierz temat \(topicTitle), przeglądaj najnowsze wydanie, a metryki w hero rozwijaj tylko wtedy, gdy potrzebujesz więcej kontekstu."
                ),
                PavbotTabInfoSection(
                    title: "Co możesz sprawdzić",
                    systemImage: "bookmark.fill",
                    body: "Sprawdzisz najważniejsze sygnały, pełniejsze opisy, PDF-y, audio, źródła oraz lokalnie zapisane materiały dla tej części biblioteki."
                )
            ],
            tips: [
                "Dymki w hero są zwinięte, żeby główna lista treści była widoczna szybciej.",
                "Zapisane materiały są najlepszym miejscem na własną listę do późniejszego czytania."
            ]
        )
    }
}

struct PavbotTabInfoSection: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let body: String
}

struct PavbotTabInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let content: PavbotTabInfoContent

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let layout = PavbotAdaptiveLayout.resolve(
                    width: proxy.size.width,
                    horizontalSizeClass: horizontalSizeClass
                )

                PavbotPremiumScreenScaffold(layout: layout, spacing: 18) {
                    PavbotCommandHero(
                        eyebrow: content.eyebrow,
                        title: "Jak działa karta \(content.title)",
                        subtitle: content.summary,
                        systemImage: content.systemImage,
                        tint: content.tint
                    )

                    LazyVGrid(columns: layout.adaptiveColumns(minimum: layout.infoCardMinWidth), spacing: 14) {
                        ForEach(content.sections) { section in
                            PavbotTabInfoSectionCard(section: section, tint: content.tint)
                        }
                    }

                    PavbotReadingCard(title: "Praktyczne wskazówki", systemImage: "lightbulb.fill", tint: content.tint) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(content.tips.enumerated()), id: \.offset) { index, tip in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.black))
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(content.tint.gradient, in: Circle())

                                    Text(tip)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .environment(\.pavbotAdaptiveLayout, layout)
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Zamknij") {
                        dismiss()
                    }
                    .font(.callout.weight(.semibold))
                }
            }
        }
    }
}

private struct PavbotTabInfoSectionCard: View {
    let section: PavbotTabInfoSection
    let tint: Color

    var body: some View {
        PavbotPremiumCard(tint: tint, cornerRadius: 24, horizontalPadding: 18, verticalPadding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                Text(section.title)
                    .font(.headline.weight(.bold))

                Text(section.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title). \(section.body)")
    }
}

private struct PavbotTabInfoModifier: ViewModifier {
    let infoContent: PavbotTabInfoContent
    @State private var presentedInfo: PavbotTabInfoContent?

    func body(content view: Content) -> some View {
        view
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentedInfo = infoContent
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.headline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(infoContent.tint)
                    .accessibilityLabel("Otwórz instrukcję karty \(infoContent.title)")
                    .accessibilityHint("Pokazuje, jak korzystać z tej zakładki i jakie informacje można w niej sprawdzić.")
                }
            }
            .sheet(item: $presentedInfo) { info in
                PavbotTabInfoSheet(content: info)
                    .pavbotLargeObjectPresentation()
            }
    }
}

extension View {
    func pavbotTabInfo(_ content: PavbotTabInfoContent) -> some View {
        modifier(PavbotTabInfoModifier(infoContent: content))
    }
}

struct PavbotCommandHero: View {
    var eyebrow: String?
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor
    var insights: [PavbotInsight] = []
    var startsCollapsed = false
    var footnote: String?
    @State private var isExpanded = true

    init(
        eyebrow: String? = nil,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color = .accentColor,
        insights: [PavbotInsight] = [],
        startsCollapsed: Bool = false,
        footnote: String? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.insights = insights
        self.startsCollapsed = startsCollapsed
        self.footnote = footnote
        _isExpanded = State(initialValue: !startsCollapsed)
    }

    var body: some View {
        PavbotPremiumCard(tint: tint, cornerRadius: 28, horizontalPadding: 20, verticalPadding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: tint.opacity(0.24), radius: 12, x: 0, y: 7)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 7) {
                        if let eyebrow {
                            Text(eyebrow)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(tint)
                                .textCase(.uppercase)
                                .tracking(0.8)
                        }

                        Text(title)
                            .font(.largeTitle.weight(.bold))
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !insights.isEmpty {
                    if startsCollapsed {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Label(isExpanded ? "Ukryj szczegóły" : "Pokaż szczegóły", systemImage: "slider.horizontal.3")
                                    .font(.callout.weight(.bold))
                                Spacer(minLength: 8)
                                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .font(.headline.weight(.semibold))
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(tint.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isExpanded ? "Ukryj szczegóły karty \(title)" : "Pokaż szczegóły karty \(title)")
                    }

                    if isExpanded {
                        PavbotStatusRail(insights: insights)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                if let footnote {
                    Text(footnote)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct PavbotSignalCard: View {
    let title: String
    let value: String
    var subtitle: String?
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct PavbotStatusRail: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    var title: String?
    let insights: [PavbotInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.headline.weight(.semibold))
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(insights) { insight in
                    PavbotSignalCard(
                        title: insight.title,
                        value: insight.value,
                        systemImage: insight.systemImage,
                        tint: insight.tint
                    )
                }
            }
        }
    }

    private var columns: [GridItem] {
        layout.usesDashboardLayout
            ? layout.adaptiveColumns(minimum: 150, maximum: 260, spacing: 10)
            : [GridItem(.flexible()), GridItem(.flexible())]
    }
}

struct PavbotActionTrayAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    init(
        id: String? = nil,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) {
        self.id = id ?? title
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }
}

struct PavbotActionTray: View {
    var title = "Szybkie akcje"
    var subtitle: String?
    let actions: [PavbotActionTrayAction]

    var body: some View {
        PavbotPremiumCard(tint: .blue, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(actions) { action in
                        Button(action: action.action) {
                            PavbotCompactStoryRow(
                                title: action.title,
                                subtitle: action.subtitle,
                                systemImage: action.systemImage,
                                tint: action.tint
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.title)
                    }
                }
            }
        }
    }
}

struct PavbotReadingCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String = "doc.text.fill"
    var tint: Color = .accentColor
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "doc.text.fill",
        tint: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 7)
        .accessibilityElement(children: .contain)
    }
}

struct PavbotPremiumCard<Content: View>: View {
    var tint: Color = .accentColor
    var cornerRadius: CGFloat = 24
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 18
    let content: Content

    init(
        tint: Color = .accentColor,
        cornerRadius: CGFloat = 24,
        horizontalPadding: CGFloat = 18,
        verticalPadding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        tint.opacity(0.08),
                        Color(.secondarySystemBackground).opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 9)
    }
}

struct PavbotInsight: Identifiable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    init(
        id: String? = nil,
        title: String,
        value: String,
        systemImage: String,
        tint: Color
    ) {
        self.id = id ?? "\(title)-\(value)-\(systemImage)"
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
    }
}

struct PavbotInsightStrip: View {
    let title: String
    let insights: [PavbotInsight]

    init(title: String = "Co wymaga uwagi", insights: [PavbotInsight]) {
        self.title = title
        self.insights = insights
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 9)], spacing: 9) {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 7) {
                        Image(systemName: insight.systemImage)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(insight.tint)
                            .frame(width: 28, height: 28)
                            .background(insight.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.value)
                                .font(.callout.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(insight.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground).opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(insight.title): \(insight.value)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PavbotFreshnessBadge: View {
    let label: String
    var systemImage: String = "checkmark.seal.fill"
    var tint: Color = .green

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct PavbotCompactStoryRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor
    var trailingText: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let trailingText {
                Text(trailingText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.10), in: Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground).opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PavbotPrimaryActionCapsule: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(.white)
                .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct PavbotStateView: View {
    let error: PavbotUserFacingError
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: error.systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(error.tint)
                .frame(width: 52, height: 52)
                .background(error.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(error.title)
                    .font(.headline.weight(.semibold))
                Text(error.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action {
                Button(action: action) {
                    Label(error.actionTitle, systemImage: error.actionSystemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PavbotRefreshButton: View {
    let isRefreshing: Bool
    let accessibilityLabel: String
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 32, height: 32)
        }
        .disabled(isRefreshing)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

struct PavbotRefreshToolbarButton: View {
    let isRefreshing: Bool
    let accessibilityLabel: String
    var accessibilityHint: String?
    let action: () -> Void

    var body: some View {
        PavbotRefreshButton(
            isRefreshing: isRefreshing,
            accessibilityLabel: accessibilityLabel,
            accessibilityHint: accessibilityHint,
            action: action
        )
    }
}

struct PavbotArticleKeywordRows<Content: View>: View {
    var horizontalSpacing: CGFloat = 7
    var verticalSpacing: CGFloat = 6
    let content: Content

    init(
        horizontalSpacing: CGFloat = 7,
        verticalSpacing: CGFloat = 6,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        PavbotTwoLineFlowLayout(
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        ) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PavbotArticleTagChip: View {
    let title: String
    let systemImage: String
    let tint: Color
    var accessibilityPrefix = "Tag"

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.10), in: Capsule())
            .accessibilityLabel("\(accessibilityPrefix): \(title)")
    }
}

struct PavbotSourceCountBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        if count > 0 {
            Label("\(count) źr.", systemImage: "link")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(tint.opacity(0.10), in: Capsule())
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        count == 1 ? "1 użyte źródło" : "\(count) użytych źródeł"
    }
}

private struct PavbotTwoLineFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    var maxRows = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? idealSingleLineWidth(for: subviews)
        let layout = arrangedSubviews(subviews, maxWidth: maxWidth)
        return CGSize(width: proposal.width ?? layout.size.width, height: layout.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangedSubviews(subviews, maxWidth: bounds.width)
        for item in layout.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
            )
        }
    }

    private func arrangedSubviews(_ subviews: Subviews, maxWidth: CGFloat) -> (items: [PavbotFlowItem], size: CGSize) {
        let availableWidth = max(maxWidth, 0)
        var items: [PavbotFlowItem] = []
        var row = 1
        var rowHeight: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0

        for index in subviews.indices {
            let proposedWidth = availableWidth > 0 ? availableWidth : nil
            let measuredSize = subviews[index].sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            let itemSize = CGSize(
                width: availableWidth > 0 ? min(measuredSize.width, availableWidth) : measuredSize.width,
                height: measuredSize.height
            )
            let nextX = x > 0 ? x + horizontalSpacing : x

            if nextX > 0, nextX + itemSize.width > availableWidth {
                guard row < maxRows else { break }
                row += 1
                x = 0
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            let originX = x > 0 ? x + horizontalSpacing : x
            items.append(PavbotFlowItem(index: index, origin: CGPoint(x: originX, y: y), size: itemSize))
            x = originX + itemSize.width
            rowHeight = max(rowHeight, itemSize.height)
            usedWidth = max(usedWidth, x)
        }

        let height = items.isEmpty ? 0 : y + rowHeight
        return (items, CGSize(width: usedWidth, height: height))
    }

    private func idealSingleLineWidth(for subviews: Subviews) -> CGFloat {
        subviews.indices.reduce(CGFloat.zero) { width, index in
            let size = subviews[index].sizeThatFits(.unspecified)
            return width + size.width + (index == subviews.startIndex ? 0 : horizontalSpacing)
        }
    }

    private struct PavbotFlowItem {
        let index: Int
        let origin: CGPoint
        let size: CGSize
    }
}

extension View {
    func pavbotLargeObjectPresentation() -> some View {
        modifier(PavbotLargeObjectPresentationModifier())
    }
}

private struct PavbotLargeObjectPresentationModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var layout: PavbotAdaptiveLayout {
        PavbotAdaptiveLayout.resolve(width: nil, horizontalSizeClass: horizontalSizeClass)
    }

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: layout.sheetMinWidth,
                idealWidth: layout.sheetIdealWidth,
                maxWidth: layout.sheetMaxWidth,
                minHeight: layout.sheetMinHeight,
                idealHeight: layout.sheetIdealHeight,
                maxHeight: .infinity
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
    }
}

struct PavbotActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct PavbotConnectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PavbotScreenHeader(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
            content()
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        }
    }
}

struct PavbotCacheNoticeBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "externaldrive.fill.badge.checkmark")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var subtitle: String?
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct ArtifactIconBadge: View {
    let kind: ArtifactViewerKind

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.headline)
            .foregroundStyle(kind.tint)
            .frame(width: 38, height: 38)
            .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension ArtifactViewerKind {
    var systemImage: String {
        switch self {
        case .markdown:
            "doc.text"
        case .pdf:
            "doc.richtext"
        case .audio:
            "waveform"
        case .json:
            "curlybraces"
        case .file:
            "doc"
        }
    }

    var tint: Color {
        switch self {
        case .markdown:
            .blue
        case .pdf:
            .red
        case .audio:
            .purple
        case .json:
            .orange
        case .file:
            .secondary
        }
    }
}

extension Int {
    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
