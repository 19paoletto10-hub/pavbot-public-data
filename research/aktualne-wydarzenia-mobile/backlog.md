# Topic Backlog: aktualne-wydarzenia-mobile

## Active

| Priority | Item | Reason | Next Step | Status |
| --- | --- | --- | --- | --- |
| High | Track Orka delivery, MRO and Baltic follow-through | Wieczorny run potwierdził podpisanie umowy na trzy A26, ale publiczne szczegóły wykonawcze nadal są niepełne | In the next run, verify delivery timing, named Polish industrial partners, scope of the MRO buildout, the HMS Södermanland bridge arrangement, and any additional Poland-Sweden/NATO-Baltic commitments | Open |
| High | Track concrete follow-through after Gdańsk package | Dzisiejszy run ma już liczby i deklaracje, ale nie wszystkie projekty mają publiczne listy beneficjentów i wdrożeń | In the next run, check for named projects, signed agreements, and partner readouts expanding the 3,2 mld euro, 1,1 mld euro and 10 mld euro figures | Open |
| High | Stabilize `male-xtts` in current-events pipeline | Ósmy produkcyjny run z rzędu kończy się brakiem męskiego wariantu MP3 mimo poprawnego `female-piper` | Review [proposal 2026-06-26](proposals/2026-06-26-stabilize-male-xtts-workflow.md) and decide whether to implement timeout and fallback hardening outside the topic run | Open |
| Medium | Align public mobile scope with manifest output | Run `2026-06-29-1934` potwierdził, że `origin/main` nadal publikuje i indeksuje `newspaper.pdf`, choć topic prompt ogranicza publiczny zakres do `mobile-brief`, `script`, `mobile-news` i realnych MP3 | Review [proposal 2026-06-29](proposals/2026-06-29-align-mobile-public-scope-with-manifest.md) and decide whether `newspaper.pdf` should remain local-only or become explicitly public everywhere | Open |
| Medium | Monitor legal follow-through on EU temporary protection proposal | Komisja Europejska zaproponowała ochronę tymczasową dla osób uciekających z Ukrainy do 4 marca 2028 roku, ale decyzję musi jeszcze przyjąć Rada UE, a kryteria dla nowych przyjazdów są politycznie czułe | In the next run, check whether the Council has adopted the proposal and how the criteria for new arrivals are being publicly described | Open |
| Medium | Tune trusted source mix | The brief should stay current without repeating low-value items | After three runs, note the sources that produced the strongest confirmed stories | Open |
| Medium | Watch heat, storms and hydrology as a first-rank public risk | Poranny run utrzymał szeroki upał, lokalne alerty burzowe, suszę hydrologiczną oraz dołożył bardzo wysoki dobowy bilans utonięć | In the next run, verify whether burze przyniosły szkody, awarie, pożary, problemy energetyczne, kolejne utonięcia lub lokalną poprawę sytuacji hydrologicznej oraz czy alerty się przesunęły regionalnie | Open |

## Review Notes

- 2026-06-23: Topic created for a daily mobile-first current events brief with
  two TTS variants.
- 2026-06-23: Testowy run utworzył raport, PDF i dwa warianty MP3. Test obrazu
  PDF potwierdził, że renderer utrzymuje zawijane punkty Markdown jako pojedyncze
  karty mobilnego briefu.
- 2026-06-23: Produkcyjny run zastąpił testowy brief pełnym raportem na bazie
  KPRM, Prezydenta RP, RCB, IMGW, Consilium, NATO, MSZ i AP.
- 2026-06-24: Produkcyjny run przestawił akcent z samych zapowiedzi na
  operacyjny przebieg wizyty w Turcji, ostrzeżenia przed upałem i mocniejszy
  publiczny sygnał IAEA wobec Iranu.
- 2026-06-24: Wariant `female-piper` utworzył poprawny MP3, natomiast
  `male-xtts` zawiesił się podczas renderu i został zakończony kontrolowanie;
  szczegóły błędu zapisano w `podcasts/2026-06-24/tts_variants.json`.
- 2026-06-25: Produkcyjny run przeniósł główny ciężar briefu do Gdańska:
  Ukraine Recovery Conference, Szczyt Wschodniej Flanki oraz krajowe ryzyka
  upału, suszy i lokalnych pożarów.
- 2026-06-25: Wariant `female-piper` ponownie utworzył poprawny MP3, natomiast
  `male-xtts` znowu utknął podczas renderu; zachowano tylko prawdziwe audio i
  zapisano błąd w `podcasts/2026-06-25/tts_variants.json`.
- 2026-06-26: Produkcyjny run `2026-06-26-1021` dodał twarde liczby z Gdańska:
  3,2 mld euro pierwszej transzy dla Ukrainy, ponad 1,1 mld euro nowych umów
  finansowych i Deklarację Gdańską po Szczycie Wschodniej Flanki.
- 2026-06-26: `female-piper` ponownie utworzył poprawny MP3, natomiast
  `male-xtts` trzeci raz z rzędu utknął podczas renderu i został przerwany
  kontrolowanie; szczegóły zapisano w `podcasts/2026-06-26-1021/tts_variants.json`
  oraz w proposal `proposals/2026-06-26-stabilize-male-xtts-workflow.md`.
- 2026-06-27: Produkcyjny run `2026-06-27-1019` przesunął główną zmianę dnia z
  samych liczb z Gdańska do dłuższego horyzontu: sankcji UE wobec Rosji do
  31 lipca 2027 roku, propozycji ochrony tymczasowej do 4 marca 2028 roku oraz
  formalnych alertów RCB przed upałem do 42°C.
- 2026-06-27: `female-piper` ponownie utworzył poprawny MP3, natomiast
  `male-xtts` czwarty raz z rzędu zawiesił się podczas renderu i został
  przerwany kontrolowanie; stan zapisano w
  `podcasts/2026-06-27-1019/tts_variants.json`.
- 2026-06-28: Produkcyjny run `2026-06-28-1017` dołożył do skrajnego upału
  oficjalne ostrzeżenia burzowe RCB i mocniejszy europejski kontekst z WMO,
  który osadza Polskę w rekordowej późnoczerwcowej fali upałów.
- 2026-06-28: `female-piper` ponownie utworzył poprawny MP3, natomiast
  `male-xtts` piąty raz z rzędu zawiesił się podczas renderu i został
  przerwany kontrolowanie; stan zapisano w
  `podcasts/2026-06-28-1017/tts_variants.json`.
- 2026-06-28: Wieczorny run `2026-06-28-1935` przesunął polityczny środek
  ciężkości na jutrzejsze konsultacje polsko-szwedzkie w Gdyni i publiczną
  zapowiedź podpisania umowy na trzy A26 dla programu Orka.
- 2026-06-28: `female-piper` ponownie utworzył poprawny MP3, natomiast
  `male-xtts` szósty raz z rzędu zawiesił się podczas renderu i został
  przerwany kontrolowanie; stan zapisano w
  `podcasts/2026-06-28-1935/tts_variants.json`.
- 2026-06-29: Poranny run `2026-06-29-1017` doprecyzował obraz dnia do układu
  upał plus burze plus susza plus 17 utonięć oraz przesunął Gdynię z etapu
  zapowiedzi do szczegółowego harmonogramu dnia z planowanym podpisaniem A26 o
  12:45.
- 2026-06-29: `female-piper` ponownie utworzył poprawny MP3, natomiast
  `male-xtts` siódmy raz z rzędu zawiesił się podczas renderu i został
  przerwany kontrolowanie; stan zapisano w
  `podcasts/2026-06-29-1017/tts_variants.json`.
- 2026-06-29: Wieczorny run `2026-06-29-1934` domknął Gdynię podpisaną umową
  na trzy A26, dołożył szczegóły przemysłowe od Saab: około 47 mld SEK,
  pakiet uzbrojenia, szkoleniowo-wsparciowy, MRO w Polsce i pomostowy HMS
  Södermanland.
- 2026-06-29: `female-piper` ponownie utworzył poprawny MP3, natomiast
  `male-xtts` ósmy raz z rzędu zawiesił się podczas renderu i został
  przerwany kontrolowanie; stan zapisano w
  `podcasts/2026-06-29-1934/tts_variants.json`.

## Done

| Date | Item | Outcome |
| --- | --- | --- |
| 2026-06-26 | Review first three mobile news runs | Po czterech produkcyjnych przebiegach potwierdziło się, że źródłowo i wizualnie format działa, a główny problem operacyjny koncentruje się na `male-xtts`. |
