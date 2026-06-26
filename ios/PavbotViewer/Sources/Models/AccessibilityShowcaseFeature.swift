import Foundation

enum AccessibilityShowcaseFeature: String, CaseIterable, Identifiable {
    case darkInterface
    case largerText
    case voiceOver
    case voiceControl
    case sufficientContrast
    case differentiateWithoutColor
    case reducedMotion
    case captions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .darkInterface:
            "Tryb jasny i ciemny"
        case .largerText:
            "Duży tekst"
        case .voiceOver:
            "VoiceOver"
        case .voiceControl:
            "Voice Control"
        case .sufficientContrast:
            "Wysoki kontrast"
        case .differentiateWithoutColor:
            "Nie tylko kolor"
        case .reducedMotion:
            "Redukcja ruchu"
        case .captions:
            "Transkrypcje audio"
        }
    }

    var appStoreName: String {
        switch self {
        case .darkInterface:
            "Dark Interface"
        case .largerText:
            "Larger Text"
        case .voiceOver:
            "VoiceOver"
        case .voiceControl:
            "Voice Control"
        case .sufficientContrast:
            "Sufficient Contrast"
        case .differentiateWithoutColor:
            "Differentiate Without Color Alone"
        case .reducedMotion:
            "Reduced Motion"
        case .captions:
            "Captions"
        }
    }

    var summary: String {
        switch self {
        case .darkInterface:
            "Pavbot może działać zgodnie z systemem albo wymusić jasny lub ciemny wygląd."
        case .largerText:
            "Główne ekrany korzystają z Dynamic Type, żeby ważne opisy pozostały czytelne."
        case .voiceOver:
            "Najważniejsze kafelki, odtwarzanie, TTS i akcje mają opisowe etykiety."
        case .voiceControl:
            "Akcje używają naturalnych nazw, np. Odtwórz audio, Pauza, Zapisz artykuł."
        case .sufficientContrast:
            "Interfejs używa semantycznych kolorów i czytelnych stanów w jasnym oraz ciemnym trybie."
        case .differentiateWithoutColor:
            "Statusy mają tekst i ikony, więc nie opierają się wyłącznie na kolorze."
        case .reducedMotion:
            "Gdy iOS ogranicza ruch, automatyczne przewijanie i animacje są redukowane."
        case .captions:
            "Dla podcastów i TTS aplikacja pokazuje tekst źródłowy albo jasny brak transkrypcji."
        }
    }

    var systemImage: String {
        switch self {
        case .darkInterface:
            "circle.lefthalf.filled"
        case .largerText:
            "textformat.size"
        case .voiceOver:
            "ear.badge.waveform"
        case .voiceControl:
            "mic.circle.fill"
        case .sufficientContrast:
            "circle.righthalf.filled"
        case .differentiateWithoutColor:
            "checkmark.seal.fill"
        case .reducedMotion:
            "pause.circle.fill"
        case .captions:
            "captions.bubble.fill"
        }
    }

    var accessibilityLabel: String {
        "\(title). \(summary)"
    }
}
