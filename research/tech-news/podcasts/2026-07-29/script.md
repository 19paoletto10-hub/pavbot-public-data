# Wstęp

Dzień dobry. Dzisiejszy odcinek ma jedną oś: sztuczna inteligencja przestaje być opowieścią o pojedynczym modelu, a staje się opowieścią o tempie rozwoju, otwartości, podziale pracy i infrastrukturze.

Z polskiej perspektywy to ważne, bo jeśli koszty modeli, chmury i storage będą się przesuwać, odczuje to każdy, kto buduje produkt na cudzym stacku. W praktyce oznacza to większe znaczenie dla zakupów chmurowych i bezpieczeństwa.

Dlatego dziś bierzemy pięć newsów: statement o pace frontier AI, spór o open weights, dane OpenAI o task crossover, agentowe scientific computing i sygnał z Seagate, że storage nadal jest jednym z głównych beneficjentów boomu AI.

# 1. Pacing the Frontier przenosi debatę do środka branży

Pierwszy temat to statement „Pacing the Frontier”. Na stronie projektu widać jasno, że podpisało go 1178 pracowników frontier AI companies. Ich prośba jest konkretna: rząd Stanów Zjednoczonych ma wesprzeć międzynarodowy wysiłek, który stworzy techniczne i governance'owe narzędzia pozwalające świadomie spowalniać tempo automatyzacji badań nad AI.

To ważne, bo rozmowa przestaje być tylko zewnętrznym naciskiem regulatorów albo krytyków branży. Tu presja wychodzi z samego środka ekosystemu. Sygnatariusze mówią wprost, że pojedyncze firmy i państwa są pod ogromną presją konkurencji i nie chcą unilateralnie zwalniać, nawet jeśli widzą ryzyka. W praktyce to prośba o wspólne zasady, które kupią czas na testy, zabezpieczenia i nadzór.

To wezwanie nie brzmi „zatrzymajmy AI”, tylko: miejmy narzędzia do kontrolowania tempa. Jeśli taki spór trafi do polityki, potem trafi też do procurementu, audytów i regulacji.

# 2. Open weights stają się osią sporu politycznego

Drugi temat to open weights. Microsoft przekonuje, że otwarte wagi zwiększają dostęp, konkurencję, bezpieczeństwo i kontrolę po stronie klientów. W tym ujęciu chodzi nie tylko o ideologię otwartości, ale o gospodarkę: o to, żeby startupy, uczelnie, firmy i instytucje publiczne mogły korzystać z zaawansowanych modeli bez trenowania wszystkiego od zera i bez płacenia frontierowych cen za każdy pojedynczy task.

Anthropic odpowiada na to własnym stanowiskiem i tu robi się ciekawie. Dario Amodei pisze wprost, że firma nie popiera zakazu open weights jako kategorii. Modele bez niebezpiecznych zdolności nazywa wręcz dobrem publicznym. Ale jednocześnie dodaje, że sama otwartość nie rozwiązuje problemu bezpieczeństwa. Anthropic chce działań na kilku punktach nacisku: na chipach, na przemysłowej distillacji i na obowiązkowych testach bezpieczeństwa dla mocnych modeli.

To przesuwa spór z prostego hasła „otwarte kontra zamknięte” do pytania, gdzie są realne dźwignie kontroli: compute, transfery sprzętu i testy przed publikacją.

Dla rynku to bardzo konkretne, bo jeśli open weights mają być dalej dostępne, a jednocześnie mają wejść twardsze zasady wokół chipów, distillation i testów, to mapa wdrożeń się zmienia. Część firm będzie stawiać na self-hosting, część na zamknięte API, a część na hybrydę.

# 3. AI już miesza role zawodowe

Trzeci news to raport OpenAI „How AI is expanding what people do at work”. Tu mamy jeden z najciekawszych twardych sygnałów dnia. OpenAI przeanalizowało ponad 800 tysięcy wiadomości od użytkowników z USA i znalazło, że 16,8 procent wiadomości związanych z pracą oraz 43,5 procent wiadomości specyficznych dla zawodu dotyczy zadań przypisanych do innego zawodu. Innymi słowy: ludzie coraz częściej używają AI nie tylko do szybszego wykonywania własnych obowiązków, ale do wchodzenia w zadania, które kiedyś wymagały innej specjalizacji.

OpenAI nazywa ten wzorzec task crossover. I to jest trafne określenie, bo nie mówimy już wyłącznie o automatyzacji pojedynczych czynności. Mówimy o przesuwaniu granic między rolami. Sprzedawca może przeanalizować dane klienta, marketer może samodzielnie diagnozować problem na stronie, a właściciel małej firmy może napisać prosty draft umowy albo zrobić podstawową analizę finansową bez czekania na specjalistę.

Zjawisko jest wyraźniejsze w mniejszych firmach, gdzie zwykle nie ma wyspecjalizowanych zespołów do każdego zadania. W praktyce AI staje się tam generalistycznym narzędziem do wypełniania luk.

Dlaczego to ważne? Bo AI nie musi najpierw „zabrać pracy”, żeby zmienić rynek pracy. Wystarczy, że zmieni granice kompetencji i to, kiedy trzeba uruchomić specjalistę. To bardziej cicha, ale też bardziej realna reorganizacja niż wiele głośnych prognoz o masowych zwolnieniach.

# 4. Agenci wchodzą do scientific computing

Czwarty temat to kolejny raport OpenAI, tym razem „Scientific computing in the age of agentic AI”. I tu znowu chodzi nie o pokazowe demo, tylko o bardzo praktyczną pracę. OpenAI opisuje osiem projektów agentowo wspieranego scientific computing, głównie w life sciences. Pięć z nich korzystało wyłącznie z Codex, a trzy z kombinacji Codex i Claude Code.

Najważniejsza lekcja jest prosta: agenci przyspieszają implementację i utrzymanie, ale człowiek nadal musi robić najtrudniejszą część pracy, czyli weryfikację i orkiestrację. Badacz albo maintainer wyznacza cel, definiuje kryteria poprawności i decyduje, kiedy wynik jest wystarczająco dobry, żeby go wypuścić dalej.

To przesuwa ciężar z „pisania kodu” na „sprawdzanie i utrzymywanie kodu”. OpenAI wprost pisze, że bottleneckiem nie jest już samo wytwarzanie zmian, tylko walidacja wyników i długoterminowa opieka nad software'em.

Dla nauki i biotechu to sygnał, że coding agents wchodzą w bardziej nudną, ale dochodową warstwę pracy. Największy efekt AI może więc nie przyjść z nowego benchmarku, tylko z cichej modernizacji narzędzi, których nikt wcześniej nie miał czasu poprawić.

# 5. Seagate przypomina, że AI potrzebuje storage

Piąty news to Seagate. W wynikach za rok fiskalny dwa tysiące dwudziesty szósty firma podała przychody na poziomie 12,2 miliarda dolarów i free cash flow na poziomie 3,1 miliarda dolarów. Co ważniejsze, zarząd mówi wprost o robust cloud data center demand i o durable long-term demand for mass capacity storage.

To nie jest detal dla księgowych. AI to nie tylko GPU i energia, ale też ogromna warstwa przechowywania danych. Im więcej modeli, pipeline'ów i logów, tym większa potrzeba taniego, masowego storage'u. A skoro Seagate daje guidance na pierwszy kwartał roku fiskalnego dwa tysiące dwudziestego siódmego na poziomie 4,1 miliarda dolarów, to ten segment wygląda jak część dłuższego cyklu infrastrukturalnego.

Dlaczego to ma znaczenie dla słuchacza w Polsce? Bo kiedy myślimy o koszcie AI, zwykle widzimy tylko abonament albo licencję. Tymczasem prawdziwa ekonomia leży niżej: w compute, storage, energetyce i sieci.

# Zakończenie

Jeśli złożyć te pięć historii w jedną całość, wychodzi bardzo spójny obraz. AI nie jest już tylko wyścigiem modeli. To rywalizacja o tempo rozwoju, o granice otwartości, o reorganizację pracy, o realną użyteczność agentów i o infrastrukturę, która musi to wszystko unieść.

Statement „Pacing the Frontier” pokazuje presję na kontrolę tempa od środka branży. Microsoft i Anthropic zamieniają open weights w prawdziwy spór polityczny. OpenAI pokazuje, że AI miesza role zawodowe i wchodzi do naukowego back-office, a Seagate przypomina, że za całą tą opowieścią stoi twardy rynek storage'u.

I właśnie dlatego najważniejsze pytanie na dziś nie brzmi: który model jest najmocniejszy. Brzmi: kto kontroluje tempo, kto kontroluje dostęp i kto naprawdę zapłaci za całą resztę tej transformacji.
