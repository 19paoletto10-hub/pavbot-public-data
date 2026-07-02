# Topic Backlog: aktualne-wydarzenia-mobile

## Active

| Priority | Item | Reason | Next Step | Status |
| --- | --- | --- | --- | --- |
| High | Recover MP3 rendering after `ffmpeg`/`x265` breakage | Wieczorny run `2026-07-02-1934` ponownie wysypał standardowy render `female-piper` na błędzie `ffmpeg`/`x265`; realny MP3 odzyskano dopiero ręcznym pipeline'em `piper -> ffmpeg` z `DYLD_LIBRARY_PATH` i `DYLD_FALLBACK_LIBRARY_PATH` wskazującymi `libx265.215` z Homebrew `x265/4.1`, więc wspólne środowisko audio nadal jest realnie zepsute i nienaprawione | Review [proposal 2026-06-30](proposals/2026-06-30-recover-audio-pipeline-after-ffmpeg-breakage.md) and repair the shared audio environment or renderer outside the topic run | Open |
| High | Track Orka delivery, MRO and Baltic follow-through | Wieczorny run potwierdził podpisanie umowy na trzy A26, ale publiczne szczegóły wykonawcze nadal są niepełne | In the next run, verify delivery timing, named Polish industrial partners, scope of the MRO buildout, the HMS Södermanland bridge arrangement, and any additional Poland-Sweden/NATO-Baltic commitments | Open |
| High | Track concrete follow-through after Gdańsk package | Dzisiejszy run ma już liczby i deklaracje, ale nie wszystkie projekty mają publiczne listy beneficjentów i wdrożeń | In the next run, check for named projects, signed agreements, and partner readouts expanding the 3,2 mld euro, 1,1 mld euro and 10 mld euro figures | Open |
| High | Stabilize `male-xtts` in current-events pipeline | Czternasty produkcyjny run z rzędu kończy się brakiem męskiego wariantu MP3; wieczór `2026-07-02-1934` znowu wymagał ręcznego przerwania po powtarzalnej zwiesze XTTS zakończonej `KeyboardInterrupt` w generacji waveformu | Review [proposal 2026-06-26](proposals/2026-06-26-stabilize-male-xtts-workflow.md) and align it with the broader audio-pipeline fix from 2026-06-30 | Open |
| Medium | Align public mobile scope with manifest output | Ręczna weryfikacja po runie `2026-07-02-1017` znowu potwierdziła, że `origin/main` publikuje i indeksuje `newspaper.pdf`, choć topic prompt ogranicza publiczny zakres do `mobile-brief`, `script`, `mobile-news` i realnych MP3 | Review [proposal 2026-06-29](proposals/2026-06-29-align-mobile-public-scope-with-manifest.md) and decide whether `newspaper.pdf` should remain local-only or become explicitly public everywhere | Open |
| Medium | Track fallout from the 2 July presidential package | Wieczorny run `2026-07-02-1934` przestawił krajową oś dnia na `5` podpisów, `2` weta i ustawę akcyzową skierowaną do TK, ale bez szybkiej publicznej odpowiedzi rządu lub większości sejmowej | In the next run, check whether the government, coalition or Sejm leadership publicly answer the vetoes and TK referral with revised bills, rebuttals or procedural moves | Open |
| Medium | Monitor legal follow-through on EU temporary protection proposal | Komisja Europejska zaproponowała ochronę tymczasową dla osób uciekających z Ukrainy do 4 marca 2028 roku, ale decyzję musi jeszcze przyjąć Rada UE, a kryteria dla nowych przyjazdów są politycznie czułe | In the next run, check whether the Council has adopted the proposal and how the criteria for new arrivals are being publicly described | Open |
| Medium | Tune trusted source mix | The brief should stay current without repeating low-value items | After three runs, note the sources that produced the strongest confirmed stories | Open |
| Medium | Watch heat, storms and hydrology as a first-rank public risk | Poranny run `2026-07-02-1017` zdjął szerokie ostrzeżenia meteorologiczne, ale zostawił suszę hydrologiczną, `39` pożarów lasów i `2` kolejne utonięcia bez pełnego oficjalnego bilansu szkód po wcześniejszych alertach | In the next run, verify whether the no-warning morning turns into an official damage tally, further drownings, wildfire counts, outages, or new local RCB/IMGW alerts | Open |
| Medium | Track execution of the new resilience plenipotentiary | Wieczorny run potwierdził przyjęcie rozporządzenia, ale publicznie nie widać jeszcze KPI, harmonogramu pracy ani pierwszych działań nowego pełnomocnika | In the next run, check for publication of the regulation text, operational priorities, reporting cadence, and any first cross-government coordination signals | Open |

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
- 2026-06-30: Produkcyjny run `2026-06-30-1015` przesunął akcent z samej Orki
  na odporność państwa: przedłużone stopnie alarmowe do 31 sierpnia 2026 roku,
  wtorkową mapę alertów RCB, suszę hydrologiczną, 4 nowe utonięcia i projekt
  Pełnomocnika Rządu do spraw Wzmocnienia Odporności Państwa w porządku obrad
  Rady Ministrów.
- 2026-06-30: Wspólny renderer TTS ujawnił nowy błąd `ffmpeg`/`x265` dla
  `female-piper`, a `male-xtts` dziewiąty raz z rzędu skończył się timeoutem;
  run odzyskał jednak realny plik `audio/female-piper/podcast.mp3` ręcznym
  obejściem lokalnym, stan zapisano w
  `podcasts/2026-06-30-1015/tts_variants.json` oraz w proposal
  `proposals/2026-06-30-recover-audio-pipeline-after-ffmpeg-breakage.md`.
- 2026-06-30: Wieczorny run `2026-06-30-1935` potwierdził decyzję rządu o
  Pełnomocniku Rządu do spraw Wzmocnienia Odporności Państwa, dołożył nocny
  alert RCB z ryzykiem przerw w dostawie prądu oraz unijną wypłatę 3,9 mld
  euro na drony dla Ukrainy.
- 2026-06-30: `female-piper` udało się odzyskać dzięki lokalnemu obejściu
  `DYLD_FALLBACK_LIBRARY_PATH`, ale `male-xtts` dziesiąty raz z rzędu
  przekroczył timeout; stan zapisano w
  `podcasts/2026-06-30-1935/tts_variants.json`.
- 2026-06-30: Publikacja i zdalna weryfikacja runu `2026-06-30-1935`
  potwierdziły ponownie niespójność zakresu publicznego: `origin/main`
  zawiera `pdfs/2026-06-30-1935-newspaper.pdf`, mimo że prompt tematu nie
  traktuje tego PDF-u jako artefaktu publicznego.
- 2026-07-01: Produkcyjny run `2026-07-01-1017` przesunął poranny ciężar dnia
  na nowy alert RCB `1.07/2.07`, utrzymane ostrzeżenia upałowe i burzowe,
  bilans `3` utonięć oraz dwa obowiązujące od rana postanowienia o użyciu PKW
  dla Rumunii, Bułgarii i Turcji.
- 2026-07-01: Run `2026-07-01-1017` dołożył też nowy wykonawczy fakt po stronie
  UE: wejście w życie tymczasowego `3 euro` cła od sztuki dla przesyłek do
  `150 euro` spoza UE oraz dobrowolne identyfikatory produktów przed
  obowiązkiem od `1 listopada 2026`.
- 2026-07-01: `female-piper` udało się ponownie odzyskać tylko dzięki lokalnym
  wrapperom `ffmpeg`/`ffprobe` i `DYLD_FALLBACK_LIBRARY_PATH`, a `male-xtts`
  jedenasty raz z rzędu nie dostarczył MP3; stan zapisano w
  `podcasts/2026-07-01-1017/tts_variants.json`.
- 2026-07-01: Publikacja i ręczna kontrola po `git fetch origin` potwierdziły,
  że `origin/main:public/pavbot-manifest.json` nadal indeksuje
  `pdfs/2026-07-01-1017-newspaper.pdf`, mimo że prompt tematu ogranicza
  publiczny zakres do `mobile-brief`, `script`, `mobile-news` i realnych MP3.
- 2026-07-01: Wieczorny run `2026-07-01-1933` zawęził warstwę pogodową do
  nowego alertu RCB dla części Dolnego Śląska, dołożył sygnał o formalnych
  rozmowach o stałej bazie USA, mocniejszy przekaz NATO z Berlina oraz nowy
  alarm OCHA dla Gazy.
- 2026-07-01: W runie `2026-07-01-1933` `female-piper` udało się odzyskać
  tylko ręcznym pipeline'em `piper -> ffmpeg` z `DYLD_LIBRARY_PATH`, a
  `male-xtts` dwunasty raz z rzędu zawiesił się i wymagał przerwania;
  szczegóły zapisano w `podcasts/2026-07-01-1933/tts_variants.json`.
- 2026-07-02: Poranny run `2026-07-02-1017` zdjął szerokie ostrzeżenia
  meteorologiczne, ale zostawił suszę hydrologiczną prawie w całym kraju,
  `39` pożarów lasów, `2` kolejne utonięcia oraz formalne odliczanie do Ankary
  przez oficjalną zapowiedź wizyty Prezydenta RP i overview szczytu NATO.
- 2026-07-02: W runie `2026-07-02-1017` standardowy `female-piper` ponownie
  rozbił się o `ffmpeg`/`x265`, ale został odzyskany ręcznym pipeline'em
  `piper -> ffmpeg` z `DYLD_LIBRARY_PATH=/opt/homebrew/Cellar/x265/4.1/lib:/opt/homebrew/lib`;
  `male-xtts` trzynasty raz z rzędu zawiesił się i wymagał ręcznego przerwania,
  a stan zapisano w `podcasts/2026-07-02-1017/tts_variants.json`.
- 2026-07-02: Publikacja runu `2026-07-02-1017` przeszła technicznie i zdalnie
  zweryfikowała wymagane artefakty, ale ręczna kontrola po `git fetch origin`
  potwierdziła ponownie, że `origin/main:public/pavbot-manifest.json` nadal
  indeksuje `pdfs/2026-07-02-1017-newspaper.pdf`, mimo że prompt tematu
  ogranicza publiczny zakres do `mobile-brief`, `script`, `mobile-news` i
  realnych MP3.
- 2026-07-02: Wieczorny run `2026-07-02-1934` przesunął środek ciężkości z
  porannej osi pogodowej na pakiet decyzji Prezydenta RP oraz rosyjski atak na
  Kijów, a technologicznie dołożył nowy ruch Rady UE w sprawie walki z
  nadużyciami wobec dzieci online.
- 2026-07-02: W runie `2026-07-02-1934` standardowy `female-piper` znowu
  rozbił się o `ffmpeg`/`x265`, ale został odzyskany ręcznym pipeline'em
  `piper -> ffmpeg` z `DYLD_LIBRARY_PATH` i `DYLD_FALLBACK_LIBRARY_PATH`;
  `male-xtts` czternasty raz z rzędu zawiesił się i wymagał ręcznego
  przerwania, a stan zapisano w `podcasts/2026-07-02-1934/tts_variants.json`.
- 2026-07-02: Publikacja runu `2026-07-02-1934` przeszła technicznie i zdalnie
  zweryfikowała wymagane artefakty, ale ręczna kontrola po `git fetch origin`
  potwierdziła ponownie, że `origin/main:public/pavbot-manifest.json` nadal
  indeksuje `pdfs/2026-07-02-1934-newspaper.pdf`, mimo że prompt tematu
  ogranicza publiczny zakres do `mobile-brief`, `script`, `mobile-news` i
  realnych MP3.

## Done

| Date | Item | Outcome |
| --- | --- | --- |
| 2026-06-30 | Confirm the resilience-state decisions after the 30 June cabinet agenda | Wieczorny run `2026-06-30-1935` potwierdził formalne przyjęcie rozporządzenia o Pełnomocniku Rządu do spraw Wzmocnienia Odporności Państwa oraz wygaszenie pełnomocnika SAFE. |
| 2026-06-26 | Review first three mobile news runs | Po czterech produkcyjnych przebiegach potwierdziło się, że źródłowo i wizualnie format działa, a główny problem operacyjny koncentruje się na `male-xtts`. |
