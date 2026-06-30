# Proposal: Align mobile public scope with manifest

Date: 2026-06-29
Topic: aktualne-wydarzenia-mobile
Risk: Medium

## Proposed Change

Dopasować logikę publikacji i generowania manifestu dla
`research/aktualne-wydarzenia-mobile` tak, aby publiczny zakres artefaktów był
spójny z topic promptem i kontraktem automatyzacji.

Rekomendowany wariant:

- usunąć `*-newspaper.pdf` z publicznego zakresu dla tego tematu, jeśli topic
  prompt nadal definiuje jako publiczne tylko:
  `data/YYYY-MM-DD-HHMM-mobile-news.json`,
  `pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf`,
  `podcasts/YYYY-MM-DD-HHMM/script.md` oraz istniejące
  `podcasts/YYYY-MM-DD-HHMM/audio/*/podcast.mp3`;
- odpowiednio skorygować `scripts/generate_pavbot_manifest.py` i logikę
  publikacji/weryfikacji, żeby `newspaper.pdf` mógł pozostać lokalnym
  artefaktem redakcyjnym bez pojawiania się na `origin/main` i bez wpisu w
  `public/pavbot-manifest.json`.

Alternatywny wariant do decyzji:

- jeśli `newspaper.pdf` ma jednak być artefaktem publicznym, jawnie wyrównać
  tematowy prompt automatyzacji, repo instructions, generator manifestu i
  publikacyjny kontrakt tak, aby dodatkowy PDF był jednoznacznie dozwolony i
  wymagany.

## Reason

Wieczorny run `2026-06-29-1934` poprawnie opublikował wymagane artefakty
publiczne, ale `origin/main` ujawnił też dodatkowy plik:

- `research/aktualne-wydarzenia-mobile/pdfs/2026-06-29-1934-newspaper.pdf`

oraz dodał go do `public/pavbot-manifest.json`, mimo że topic prompt dla
automatyzacji wskazuje tylko `mobile-brief.pdf` jako publiczny PDF. To tworzy
niespójność między:

- topic promptem,
- rzeczywistym zbiorem plików wypychanych przez publikację,
- indeksem w `public/pavbot-manifest.json`,
- oczekiwaniami aplikacji i webhooka.

Bez decyzji poza aktywnym tematem nie da się wiarygodnie nazwać tego zakresu w
pełni zgodnym z kontraktem.

## Files Or Settings Affected

- `scripts/generate_pavbot_manifest.py`
- `scripts/pavbot_commit_and_push_outputs.sh`
- ewentualnie `scripts/pavbot_publication_contract.py`
- ewentualnie `research/aktualne-wydarzenia-mobile/automation-prompt.md`
- ewentualnie repo instructions opisujące publiczny zakres mobile topicu

## Acceptance Criteria

- `public/pavbot-manifest.json` na `origin/main` odzwierciedla dokładnie
  publiczny zakres zatwierdzony dla `aktualne-wydarzenia-mobile`.
- Jeśli `newspaper.pdf` ma pozostać niepubliczny, nie jest pushowany ani
  indeksowany w manifeście.
- Jeśli `newspaper.pdf` ma być publiczny, topic prompt i kontrakt publikacji
  mówią to wprost i bez sprzeczności.
- `scripts/pavbot_commit_and_push_outputs.sh --isolated research/aktualne-wydarzenia-mobile`
  kończy się sukcesem tylko wtedy, gdy zdalny stan odpowiada temu samemu
  zakresowi artefaktów.

## Rollback

Przywrócić poprzednią logikę generatora manifestu i publikacji albo poprzedni
opis zakresu publicznego, jeśli po wdrożeniu okaże się, że aplikacja iOS lub
webhook w praktyce zależą od `newspaper.pdf`.
