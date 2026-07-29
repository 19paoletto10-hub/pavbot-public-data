# Wstęp

Dzień dobry. Dzisiejszy odcinek ma jedną wyraźną oś: sztuczna inteligencja przestaje być opowieścią o pojedynczym modelu, a coraz bardziej staje się opowieścią o tym, kto ma prawo przyspieszać, kto kontroluje otwarte modele, jak zmienia się podział pracy i gdzie kończy się software, a zaczyna infrastruktura.

To ważne także z polskiej perspektywy. Jeśli koszt modeli, chmury i storage będzie się przesuwał między dostawcami, od razu odczuje to rynek firm, uczelnie i startupy, które budują produkty na cudzym stacku. W praktyce to znaczy większe znaczenie dla zakupów chmurowych, bezpieczeństwa i planowania budżetów technicznych.

Dlatego dziś bierzemy pięć newsów, które razem pokazują cały ten układ: front governance, spór o open weights, realne dane o task crossover, agentowe scientific computing i na końcu storage, czyli warstwę, o której łatwo zapomnieć, a bez której AI po prostu nie działa.

# 1. Pacing the Frontier przenosi debatę do środka branży

Pierwszy temat to statement „Pacing the Frontier”. To nie jest zwykły list protestacyjny ani marketingowa deklaracja. Na stronie projektu widać jasno, że podpisali go pracownicy frontier AI companies, dokładnie 1178 osób. Ich prośba jest konkretna: rząd Stanów Zjednoczonych ma wesprzeć międzynarodowy wysiłek, który stworzy techniczne i governance’owe narzędzia pozwalające świadomie spowalniać tempo automatyzacji badań nad AI.

To ważne, bo rozmowa przestaje być tylko zewnętrznym naciskiem regulatorów albo krytyków branży. Tu presja wychodzi z samego środka ekosystemu. Sygnatariusze mówią wprost, że dziś pojedyncze firmy i pojedyncze państwa są pod ogromną presją konkurencji i nie chcą unilateralnie zwalniać, nawet jeśli widzą ryzyka. W praktyce to prośba o wspólne zasady, które kupią czas na testy, zabezpieczenia i nadzór.

Warto też zauważyć, jak brzmi język tego statementu. Nie mówi on: „zatrzymajmy AI”. Mówi raczej: „dajmy sobie narzędzia, żeby móc to tempo kontrolować”. To subtelna, ale bardzo ważna różnica. Zamiast moralnej paniki mamy coraz wyraźniejszy spór o mechanizmy. A jeśli taki spór trafi do polityki, później trafi też do enterprise procurement, do wymagań audytowych i do regulacji po obu stronach Atlantyku.

# 2. Open weights stają się osią sporu politycznego

Drugi temat to open weights. Microsoft opublikował własny tekst o otwartych wagach i amerykańskim przywództwie AI. Firma przekonuje, że open weights zwiększają dostęp, konkurencję, bezpieczeństwo i kontrolę po stronie klientów. W tym ujęciu chodzi nie tylko o ideologię otwartości, ale o gospodarkę: o to, żeby startupy, uczelnie, firmy i instytucje publiczne mogły korzystać z zaawansowanych modeli bez trenowania wszystkiego od zera i bez płacenia frontierowych cen za każdy pojedynczy task.

Anthropic odpowiada na to własnym stanowiskiem i tu robi się ciekawie. Dario Amodei pisze wprost, że firma nie popiera zakazu open weights jako kategorii. Modele bez niebezpiecznych zdolności nazywa wręcz dobrem publicznym. Ale jednocześnie dodaje, że nie wolno udawać, iż sama otwartość rozwiązuje problem bezpieczeństwa. Anthropic chce działań na kilku punktach nacisku: na chipach, na przemysłowej distillacji i na obowiązkowych testach bezpieczeństwa dla mocnych modeli.

To przesuwa spór z prostego hasła „otwarte kontra zamknięte” do bardziej precyzyjnego pytania, gdzie są realne dźwignie kontroli. Czy państwo ma regulować dostęp do compute? Czy ma ograniczać transfery sprzętu? Czy ma wymagać testów przed publikacją? I jak odróżnić zwykłe uczenie się na cudzych rozwiązaniach od nielegalnego wyciągania wartości z zamkniętych modeli?

Dla zwykłego użytkownika brzmi to abstrakcyjnie. Ale dla rynku to bardzo konkretne. Bo jeśli open weights mają być dalej dostępne, a jednocześnie mają wejść twardsze zasady wokół chipów, distillacji i testów, to cała mapa wdrożeń się zmienia. Część firm będzie stawiać na self-hosting. Część na zamknięte API. Część na hybrydę. I właśnie o to toczy się dziś realna walka.

# 3. AI już miesza role zawodowe

Trzeci news to raport OpenAI „How AI is expanding what people do at work”. Tu mamy jeden z najciekawszych twardych sygnałów dnia. OpenAI przeanalizowało ponad 800 tysięcy wiadomości od użytkowników z USA i znalazło, że 16,8 procent wiadomości związanych z pracą oraz 43,5 procent wiadomości specyficznych dla zawodu dotyczy zadań przypisanych do innego zawodu. Innymi słowy: ludzie coraz częściej używają AI nie tylko do szybszego wykonywania własnych obowiązków, ale do wchodzenia w zadania, które kiedyś wymagały innej specjalizacji.

OpenAI nazywa ten wzorzec task crossover. I to jest bardzo trafne określenie, bo nie mówimy już wyłącznie o automatyzacji pojedynczych czynności. Mówimy o przesuwaniu granic między rolami. Sprzedawca może przeanalizować dane klienta, marketer może samodzielnie diagnozować problem na stronie, a właściciel małej firmy może napisać prosty draft umowy albo zrobić podstawową analizę finansową bez czekania na specjalistę.

Najważniejsze jest jednak to, że zjawisko jest wyraźniejsze w mniejszych firmach. To ma duży sens: tam zwykle nie ma wyspecjalizowanych zespołów do każdego zadania, więc AI staje się generalistycznym narzędziem do wypełniania luk. W dużych organizacjach częściej działają już ustalone procesy, a w małych AI po prostu przejmuje część funkcji, które wcześniej były poza zasięgiem.

Dlaczego to ważne? Bo to oznacza, że AI nie musi najpierw „zabrać pracy”, żeby zmienić rynek pracy. Wystarczy, że zmieni granice kompetencji. Zmieni, kto pierwszy dotyka problemu, kto go rozwiązuje i kiedy trzeba uruchomić specjalistę. To jest bardziej cicha, ale też bardziej realna reorganizacja niż wiele głośnych prognoz o masowych zwolnieniach.

# 4. Agenci wchodzą do scientific computing

Czwarty temat to kolejny raport OpenAI, tym razem „Scientific computing in the age of agentic AI”. I tu znowu chodzi nie o pokazowy demo, tylko o bardzo praktyczną pracę. OpenAI opisuje osiem projektów agentowo wspieranego scientific computing, głównie w life sciences. Pięć z nich korzystało wyłącznie z Codex, a trzy z kombinacji Codex i Claude Code.

Najważniejsza lekcja z tych case studies jest prosta: agenci przyspieszają implementację i utrzymanie, ale człowiek nadal musi robić najtrudniejszą część pracy, czyli weryfikację i orkiestrację. To badacz albo maintainer wyznacza cel, definiuje kryteria poprawności i decyduje, kiedy wynik jest wystarczająco dobry, żeby go wypuścić dalej.

To przesuwa ciężar z „pisania kodu” na „sprawdzanie i utrzymywanie kodu”. W jednym miejscu OpenAI wprost pisze, że bottleneckiem nie jest już samo wytwarzanie zmian, tylko walidacja wyników i długoterminowa opieka nad software’em. To bardzo ważne, bo pokazuje, gdzie realnie pojawia się wartość: nie w spektakularnym generowaniu nowych aplikacji, lecz w odgruzowywaniu starego, kruchego, źle utrzymywanego research software’u.

Dla nauki i biotechu to sygnał, że coding agents wchodzą w bardziej nudną, ale bardziej dochodową warstwę pracy. I jeśli ten wzorzec się utrzyma, to największy efekt AI może nie przyjść z nowego benchmarku, tylko z cichej modernizacji narzędzi, których nikt wcześniej nie miał czasu poprawić.

# 5. Seagate przypomina, że AI potrzebuje storage

Piąty news to Seagate. W wynikach za rok fiskalny dwa tysiące dwudziesty szósty firma podała przychody na poziomie 12,2 miliarda dolarów i free cash flow na poziomie 3,1 miliarda dolarów. Co ważniejsze, zarząd mówi wprost o robust cloud data center demand i o durable long-term demand for mass capacity storage.

To nie jest detal dla księgowych. To jest bardzo konkretny sygnał, że AI to nie tylko GPU i energia. To również ogromna warstwa przechowywania danych. Im więcej modeli, pipeline’ów i logów, tym większa potrzeba taniego, masowego storage’u. A skoro Seagate mówi o trwałym popycie i daje guidance na pierwszy kwartał roku fiskalnego dwa tysiące dwudziestego siódmego na poziomie 4,1 miliarda dolarów, to znaczy, że ten segment nie wygląda jak jednorazowy skok, tylko jak część dłuższego cyklu infrastrukturalnego.

Dlaczego to ma znaczenie dla słuchacza w Polsce? Bo kiedy myślimy o koszcie AI, zwykle widzimy tylko abonament albo licencję. Tymczasem prawdziwa ekonomia leży niżej: w compute, storage, energetyce, sieci i umowach z dostawcami. To właśnie te warstwy zdecydują, czy AI będzie szeroko dostępna, czy pozostanie drogim luksusem dla największych graczy.

# Zakończenie

Jeśli złożyć te pięć historii w jedną całość, wychodzi z nich bardzo spójny obraz. AI nie jest już tylko wyścigiem modeli. To rywalizacja o tempo rozwoju, o granice otwartości, o reorganizację pracy, o realną użyteczność agentów i o infrastrukturę, która musi to wszystko unieść.

Statement „Pacing the Frontier” pokazuje presję na kontrolę tempa od środka branży. Microsoft i Anthropic zamieniają open weights w prawdziwy spór polityczny. OpenAI pokazuje, że AI już miesza role zawodowe i wchodzi do naukowego back-office. A Seagate przypomina, że za całą tą opowieścią stoi bardzo twardy rynek storage’u.

I właśnie dlatego najważniejsze pytanie na dziś nie brzmi: który model jest najmocniejszy. Brzmi: kto kontroluje tempo, kto kontroluje dostęp i kto naprawdę zapłaci za całą resztę tej transformacji.
