# Topic Backlog: aktualne-wydarzenia-mobile

## Active

| Priority | Item | Reason | Next Step | Status |
| --- | --- | --- | --- | --- |
| High | Monitor weather and hydrology through the week | Wieczorny run z 9 lipca dokłada ostrzeżenia RCB przed burzami i wezbraniami przy utrzymanej suszy hydrologicznej | In the next run, check whether overnight alerts escalate, ease, or convert into local damage reports and whether hydrology changes regionally | Open |
| High | Track PIP implementation after 8 July | Reforma właśnie weszła w życie i może szybko przejść z komunikatu w praktykę kontrolną | In the next run, check for employer guidance, control activity, and public reactions | Open |
| High | Track health reform package after 8 July | Pakiet zdrowotny wszedł 9 lipca w otwarty dialog z NRL i jednocześnie ma ślad w agendzie SKRM, więc rośnie szansa na szybki konflikt albo formalny postęp | In the next run, check for NRL response, legislative follow-up, and concrete implementation notes from the government side | Open |
| High | Follow NATO Ankara declaration into implementation | Szczyt dał €70 mld dla Ukrainy w 2026 roku i ponad 50 mld dolarów nowych zamówień, ale krajowe wkłady i harmonogramy pozostają nieostre | In the next run, check for national follow-up, procurement detail, and Poland-specific readouts | Open |
| Medium | Track EU cyber-AI implementation follow-up | Komisja opublikowała plan cyber-AI i dopisała go do istniejących ram, ale wykonawcze szczegóły mogą jeszcze dojść | In the next run, check whether EU bodies, regulators, platforms, or vendors respond with concrete implementation steps | Open |
| High | Verify `male-xtts` repeatability in current-events pipeline | Poranny sukces z 9 lipca nie utrzymał się wieczorem; wariant znów zawiesił się na etapie XTTS inference i wymagał kontrolowanego przerwania | In the next run, try the standard pipeline again and confirm whether failure repeats with the same inference pattern while keeping `female-piper` as the required stable output | Open |

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
- 2026-07-07: Dzisiejszy run przeszedł na temat wiatru, suszy, PIP,
  deregulacji, NATO, Ukrainy oraz cyfrowych sygnałów DSA/CISA.
- 2026-07-07: `female-piper` wyrenderował się poprawnie, natomiast
  `male-xtts` znów zawiesił się na etapie GPT inference i został przerwany
  kontrolowanie; stan zapisano w
  `podcasts/2026-07-07-1025/tts_variants.json` oraz `audio/male-xtts/render.log`.
- 2026-07-07: Wieczorny run `2026-07-07-1935` przesunął środek ciężkości z
  preview na wykonanie: decyzje Rady Ministrów, alerty RCB, zakupy NATO liczone
  w dziesiątkach miliardów, wzrost wydatków obronnych i plan UE dla cyber-AI.
- 2026-07-07: `female-piper` ponownie utworzył poprawny MP3, natomiast
  `male-xtts` znów zawiesił się podczas renderu i został przerwany
  kontrolowanie; stan zapisano w
  `podcasts/2026-07-07-1935/tts_variants.json` oraz `audio/male-xtts/render.log`.
- 2026-07-08: Rano alert RCB zawęził się do Warmińsko-Mazurskiego, a raport
  dobowy nadal pokazuje wiatr, wezbrania i suszę hydrologiczną jednocześnie.
- 2026-07-08: Reforma PIP weszła w życie, KPRM nadal domyka pakiet z 7 lipca,
  a szczyt NATO w Ankarze przestawił się na zamówienia i liczby.
- 2026-07-08: Komisja Europejska opublikowała plan cyber-AI i dopisała go do
  AI Act, NIS2, DORA i Cyber Resilience Act.
- 2026-07-08: Wieczorny run `2026-07-08-1935` domknął przejście z zapowiedzi
  do zobowiązań: deklaracja ankarska dała €70 mld dla Ukrainy w 2026 roku,
  Ministerstwo Zdrowia opublikowało pakiet zmian, a PIP doprecyzowała model
  egzekwowania z ZUS i KAS.
- 2026-07-08: Komisja Europejska otworzyła konsultację o suwerenności danych,
  poszerzając dzisiejszy wątek technologiczny z cyber-AI na zależności danych i
  dostęp państw trzecich.
- 2026-07-08: W runie `2026-07-08-1935` wariant `female-piper` ponownie
  wyrenderował poprawny MP3, natomiast `male-xtts` znów zakończył się
  kontrolowanym przerwaniem po długim CPU; stan zapisano w
  `podcasts/2026-07-08-1935/tts_variants.json` oraz `audio/male-xtts/render.log`.
- 2026-07-09: Wieczorny run `2026-07-09-1935` dołożył raport RCB o burzach i
  wezbraniach, dialog MZ z NRL oraz publiczne filary Deregulacji 2.0.
- 2026-07-09: W runie `2026-07-09-1935` `female-piper` ponownie wyrenderował
  poprawny MP3, natomiast `male-xtts` zawiesił się podczas inferencji i został
  przerwany kontrolowanie; stan zapisano w
  `podcasts/2026-07-09-1935/tts_variants.json` oraz `audio/male-xtts/render.log`.

## Done

| Date | Item | Outcome |
| --- | --- | --- |
| 2026-06-26 | Review first three mobile news runs | Po czterech produkcyjnych przebiegach potwierdziło się, że źródłowo i wizualnie format działa, a główny problem operacyjny koncentruje się na `male-xtts`. |
