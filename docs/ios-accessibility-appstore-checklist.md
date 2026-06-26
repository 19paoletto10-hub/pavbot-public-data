# Pavbot iOS Accessibility Checklist

This checklist documents the App Store Connect accessibility features that Pavbot
can honestly report for iPhone/iPad after the iOS accessibility pass.

## Supported In App Store Connect

- VoiceOver: primary tabs, article cards, audio controls, TTS controls, saved
  states, weather charts, and Pulse Day carousel expose descriptive labels,
  hints, values, or accessibility actions.
- Voice Control: key commands use visible, natural action names such as
  "Odtwórz audio", "Pauza", "Stop", "Zapisz artykuł", and "Następna para
  tematów".
- Larger Text: primary reading surfaces use Dynamic Type-friendly SwiftUI text
  and avoid clipping important descriptions.
- Dark Interface: the app supports system, light, and dark appearance modes.
- Differentiate Without Color Alone: important states use icons or text labels
  in addition to color.
- Sufficient Contrast: primary text, cards, badges, and status labels use
  semantic iOS colors intended to remain readable in light and dark modes.
- Reduced Motion: Pulse Day auto-scroll is disabled when iOS Reduce Motion is
  enabled, while manual swipe and arrow navigation remain available.
- Captions: podcast script artifacts and local TTS expose source text or a clear
  missing-transcript state.

## Not Supported In v1

- Audio Descriptions: Pavbot does not currently provide separate audio
  descriptions for visual or video-only content. Do not mark this feature as
  supported in App Store Connect for v1.

## Manual Smoke Before Submission

- Test VoiceOver navigation through Dzisiaj, Puls Dnia, Jobs, Research, and
  Ustawienia.
- Test Voice Control commands for the main audio, TTS, save, and carousel
  actions.
- Test Dynamic Type at the largest accessibility size.
- Test Light, Dark, Increase Contrast, Differentiate Without Color, and Reduce
  Motion.
- Confirm podcast transcript text appears when `podcastScript` is available.
