# Topic Index: aktualne-wydarzenia-mobile

Last updated: 2026-07-09

## Current Understanding

Temat służy do codziennego tworzenia mobilnego briefu o najważniejszych
wydarzeniach publicznych z Polski i świata. Wieczorny run 9 lipca przesuwa
brief z porannej ostrożności do bardziej operacyjnego obrazu dnia: RCB dokłada
ostrzeżenia burzowe i hydrologiczne, Ministerstwo Zdrowia wchodzi w twardy
dialog z Naczelną Radą Lekarską, farmacja siedzi już w kalendarzu Stałego
Komitetu RM, a Deregulacja 2.0 dostaje konkretne filary cyfryzacyjne i
organizacyjne. W tle utrzymują się twarde liczby z Ankary, nowa runda
eskalacji USA-Iran i unijny pakiet wokół cyber-AI, suwerenności danych oraz
Digital Decade.

Format produkcyjny działa w pełnym łańcuchu: report, JSON, PDF, scenariusz audio
oraz publikacja. W wieczornym runie wymagany `female-piper` wyrenderował się
poprawnie, natomiast `male-xtts` ponownie zawiesił się na etapie inferencji i
został przerwany kontrolowanie, więc temat stabilności drugiego wariantu
pozostaje otwarty.

## Stable Facts

- Materiał ma korzystać z aktualnych, wiarygodnych źródeł i zachowywać linki do
  materialnych twierdzeń. Source: [Topic contract](topic.md).
- PDF ma być projektowany pod szybkie czytanie na telefonie, z faktami,
  interpretacją i źródłami oddzielonymi wizualnie. Source: [Topic contract](topic.md).
- TTS ma powstawać w dwóch wariantach, a brak jednego wariantu trzeba
  odnotować uczciwie w metadanych i backlogu. Source:
  [Automation prompt](automation-prompt.md).
- Publiczna publikacja dla iOS i webhooka ma obejmować co najmniej JSON,
  mobile brief PDF, `script.md` i poprawnie wyrenderowane audio. Source:
  [Automation prompt](automation-prompt.md).

## Open Questions

- Jak szybko pakiet zdrowotny przejdzie z konferencji i spotkania z NRL do
  formalnego toru legislacyjnego albo dokumentów wykonawczych?
- Czy po wejściu reformy PIP pojawią się pierwsze sygnały praktycznych kontroli,
  skarg i sporów wokół kryteriów etatu?
- Czy po deklaracji ankarskiej pojawi się dokładniejsze rozpisanie narodowych
  wkładów do pakietu dla Ukrainy i nowych zamówień obronnych?
- Czy Komisja Europejska albo ENISA szybko dołożą wykonawcze szczegóły do planu
  cyber-AI i konsultacji o suwerenności danych?
- Czy nocne ostrzeżenia RCB przed burzami i wezbraniami przełożą się rano 10
  lipca na szersze alerty albo lokalne szkody?

## Watch Items

- Czy `female-piper` pozostaje stabilnym obowiązkowym wariantem.
- Czy `male-xtts` po porannym sukcesie utrzyma pełny render bez ręcznej
  interwencji także w kolejnych wydaniach.
- Czy pakiet zdrowotny dostanie formalny ciąg dalszy po spotkaniu z NRL i
  wpisaniu farmacji do porządku SKRM.
- Czy PIP opublikuje praktyczne instrukcje dla pracodawców po pierwszym dniu
  reformy.
- Czy po deklaracji z Ankary pojawią się polskie albo sojusznicze doprecyzowania
  o wkładach dla Ukrainy i nowych zamówieniach.
- Czy RCB i IMGW utrzymają nocą punktowy charakter ostrzeżeń, czy jednak
  dojdzie do szerszej eskalacji burzowej i hydrologicznej.

## Recent Reports

- [2026-07-09-1935](runs/2026-07-09-1935.md) - wieczorne ostrzeżenia RCB,
  dialog MZ z NRL, formalizacja Deregulacji 2.0, tor legislacyjny farmacji i
  utrzymany ciężar Ankary, Iranu oraz unijnego pakietu tech.
- [2026-07-08-1935](runs/2026-07-08-1935.md) - deklaracja ankarska z €70 mld
  dla Ukrainy, pakiet zmian zdrowotnych, operacyjne wdrożenie PIP i konsultacja
  UE o suwerenności danych.
- [2026-07-08-1021](runs/2026-07-08-1021.md) - poranny alert wiatrowy,
  wejście PIP w życie, linia rządu i prezydenta wobec Ukrainy oraz plan UE
  dla cyber-AI.
- [2026-07-07-1935](runs/2026-07-07-1935.md) - decyzje Rady Ministrów,
  alerty RCB, pierwszy konkretny bilans Ankary i plan UE dla cyber-AI.
- [2026-07-07-1025](runs/2026-07-07-1025.md) - wiatr, susza, PIP, deregulacja,
  NATO, Ukraina i sygnały DSA/CISA.
- [2026-06-27-1019](runs/2026-06-27-1019.md) - sankcje UE do 31 lipca 2027,
  propozycja ochrony tymczasowej do 4 marca 2028 i eskalacja alertów upałowych
  do 42°C.

## Review Notes

- 2026-07-09: Poranny run `2026-07-09-1016` dodał lokalne ćwiczenia syren,
  porywisty wiatr, niski stan wody, wdrożeniowy ruch PIP i zdrowia, SAFE,
  szczyt NATO, eskalację USA-Iran oraz pakiet KE o cyber-AI, danych i Digital
  Decade.
- 2026-07-09: W runie `2026-07-09-1016` oba warianty TTS wyrenderowały się
  poprawnie, więc `male-xtts` wrócił do pełnego sukcesu obok
  `female-piper`.
- 2026-07-09: Wieczorny run `2026-07-09-1935` podbił wagę pogodową przez
  raport RCB o burzach, wezbraniach i suszy hydrologicznej oraz przesunął
  zdrowie z konferencyjnego pakietu do dialogu z Naczelną Radą Lekarską.
- 2026-07-09: W runie `2026-07-09-1935` `female-piper` ponownie utworzył
  poprawny MP3, natomiast `male-xtts` zawiesił się podczas inferencji i został
  przerwany kontrolowanie; stan zapisano w
  `podcasts/2026-07-09-1935/tts_variants.json` oraz `audio/male-xtts/render.log`.
