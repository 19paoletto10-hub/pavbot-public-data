# Push Before Notify

## Summary
Wprowadzić repo-wide zasadę publikacji: najpierw `git push` artefaktów wynikowych, dopiero potem wysłanie powiadomienia o nowo utworzonych wynikach.

To ma objąć wszystkie automatyzacje publikujące artefakty do `research/<topic>/` i notifier iOS. Celem jest, żeby iOS oraz backend zawsze widziały już wypchnięty stan repo zanim pojawi się alert.

## Proposed Changes
- Zmienić dokumentację publikacji tak, aby obowiązkowa kolejność była:
  1. zapis artefaktów do `research/<topic>/`
  2. `scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>`
  3. powiadomienie / ingest dopiero po potwierdzonym pushu
- Doprecyzować notifier docs, żeby `POST /v1/humor/digest` lub analogiczny ingest nie był opisywany jako wcześniejszy niż push do gita.
- Dodać jednoznaczny zapis w kontrakcie automatyzacji, że nowy rezultat nie może zostać ogłoszony bez udanego `git push`.
- Jeżeli istnieje kodowa ścieżka publikacji, zacieśnić ją tak, by kolejność push -> notify była wymuszona, a nie tylko opisana.

## Files Likely To Change
- `docs/automation-operations.md`
- `docs/how-to-use.md`
- `docs/live-ios-notifications-macbook-cloudflare.md`
- `backend/pavbot-notifier/README.md`
- ewentualnie skrypt publikacji, jeśli ma dostać twardy guard na kolejność

## Risks
- Zmiana dotyka wszystkich automatyzacji publikujących wyniki, więc błędny zapis mógłby zablokować wysyłkę albo spowodować rozjazd między gitem a notifierem.
- Jeśli notifier i publish script nie zostaną zsynchronizowane, dokumentacja może obiecywać kolejność, której kod nie egzekwuje.

## Acceptance Criteria
- Każda instrukcja publikacji mówi jasno: push przed notify.
- Nie ma już żadnego miejsca, które sugeruje publikację powiadomienia przed pushowaniem artefaktów.
- Weryfikacja workspace nadal przechodzi.

## Notes
- To jest propozycja, nie wdrożenie. Repo-wide instrukcje publikacji są traktowane jako zmiana podwyższonego ryzyka i powinny przejść przez osobny review przed aplikacją.
