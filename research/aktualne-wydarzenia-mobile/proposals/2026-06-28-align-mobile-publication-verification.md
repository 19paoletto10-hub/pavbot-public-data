# Proposal: Align mobile publication verification with public scope

Date: 2026-06-28
Topic: aktualne-wydarzenia-mobile
Risk: Medium

## Proposed Change

Dopasować logikę zdalnej weryfikacji dla `research/aktualne-wydarzenia-mobile`
tak, aby sprawdzała dokładnie ten sam publiczny zakres, który definiuje topic
prompt i kontrakt automatyzacji.

Rekomendowany wariant:

- w `scripts/pavbot_commit_and_push_outputs.sh` dla mobile-public topic nie
  wymagać obecności `*-newspaper.pdf` w zdalnym manifeście podczas
  `verify_remote_publication`, jeśli topic prompt traktuje ten plik jako lokalny
  artefakt redakcyjny, a nie publiczny output iOS/webhooka.

Alternatywny wariant do decyzji:

- jeśli `newspaper.pdf` ma jednak być artefaktem publicznym, wyrównać topic
  prompt, manifest generator i publikacyjny kontrakt tak, aby to było jawnie
  zapisane i spójne w całym repo.

## Reason

Run `2026-06-28-1017` został wypchnięty na `origin/main`, a zdalnie obecne są
wszystkie artefakty wskazane w publicznym zakresie topic promptu:

- `data/2026-06-28-1017-mobile-news.json`
- `pdfs/2026-06-28-1017-mobile-brief.pdf`
- `podcasts/2026-06-28-1017/script.md`
- `podcasts/2026-06-28-1017/audio/female-piper/podcast.mp3`

Dodatkowo sam plik `pdfs/2026-06-28-1017-newspaper.pdf` również trafił na
`origin/main`, ale `public/pavbot-manifest.json` go nie indeksuje, co jest
zgodne z obecnym topic promptem mówiącym, by nie publikować dodatkowych PDF-ów.

Mimo tego `scripts/pavbot_commit_and_push_outputs.sh --isolated
research/aktualne-wydarzenia-mobile` zakończył się błędem weryfikacji zdalnej,
bo oczekuje obecności `newspaper.pdf` w manifeście. To tworzy niespójność
między:

- topic promptem,
- zakresem publicznych artefaktów,
- generowaniem manifestu,
- logiką weryfikacji publikacji.

## Files Or Settings Affected

- `scripts/pavbot_commit_and_push_outputs.sh`
- ewentualnie `scripts/generate_pavbot_manifest.py`
- ewentualnie `research/aktualne-wydarzenia-mobile/automation-prompt.md`
- ewentualnie repo instructions opisujące publiczny zakres mobile topicu

## Acceptance Criteria

- `scripts/pavbot_commit_and_push_outputs.sh --isolated research/aktualne-wydarzenia-mobile`
  kończy się sukcesem, jeśli `origin/main` zawiera dokładnie wymagany publiczny
  zestaw artefaktów dla topic promptu.
- Zdalna weryfikacja nie zgłasza brakującego `newspaper.pdf`, jeśli ten plik ma
  pozostać nieindeksowany publicznie.
- Albo odwrotnie: jeśli decyzja brzmi, że `newspaper.pdf` jest publiczny, to
  manifest i topic prompt oba jasno to odzwierciedlają.

## Rollback

Przywrócić poprzednią logikę weryfikacji publikacji lub wcześniejszy opis
publicznego zakresu mobile topicu, jeśli po wdrożeniu okaże się, że aplikacja
iOS albo webhook wymagają innego zestawu artefaktów niż obecnie zakładany.
