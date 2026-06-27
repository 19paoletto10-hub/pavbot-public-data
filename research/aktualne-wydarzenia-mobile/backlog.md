# Topic Backlog: aktualne-wydarzenia-mobile

## Active

| Priority | Item | Reason | Next Step | Status |
| --- | --- | --- | --- | --- |
| High | Track concrete follow-through after Gdańsk package | Dzisiejszy run ma już liczby i deklaracje, ale nie wszystkie projekty mają publiczne listy beneficjentów i wdrożeń | In the next run, check for named projects, signed agreements, and partner readouts expanding the 3,2 mld euro, 1,1 mld euro and 10 mld euro figures | Open |
| High | Stabilize `male-xtts` in current-events pipeline | Czwarty produkcyjny run z rzędu kończy się brakiem męskiego wariantu MP3 mimo poprawnego `female-piper` | Review [proposal 2026-06-26](proposals/2026-06-26-stabilize-male-xtts-workflow.md) and decide whether to implement timeout and fallback hardening outside the topic run | Open |
| Medium | Monitor legal follow-through on EU temporary protection proposal | Komisja Europejska zaproponowała ochronę tymczasową dla osób uciekających z Ukrainy do 4 marca 2028 roku, ale decyzję musi jeszcze przyjąć Rada UE, a kryteria dla nowych przyjazdów są politycznie czułe | In the next run, check whether the Council has adopted the proposal and how the criteria for new arrivals are being publicly described | Open |
| Medium | Tune trusted source mix | The brief should stay current without repeating low-value items | After three runs, note the sources that produced the strongest confirmed stories | Open |
| Medium | Watch heat and hydrology as a first-rank public risk | Dzisiejszy run przesunął ryzyko krajowe z możliwych ostrzeżeń 3. stopnia do formalnych alertów RCB, temperatur do 42°C, suszy i wysokiego ryzyka pożarowego | In the next run, verify whether alerts escalate, ease, or move regionally and whether burze zaczynają realnie zmieniać sytuację hydrologiczną i pożarową | Open |

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

## Done

| Date | Item | Outcome |
| --- | --- | --- |
| 2026-06-26 | Review first three mobile news runs | Po czterech produkcyjnych przebiegach potwierdziło się, że źródłowo i wizualnie format działa, a główny problem operacyjny koncentruje się na `male-xtts`. |
