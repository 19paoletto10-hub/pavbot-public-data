# Draft: Podcast Tech 2026-06-21

Robocza konstrukcja odcinka na podstawie raportu `research/tech-news/runs/2026-06-21.md` oraz krótkiego fresh checku publicznych źródeł.

## Teza odcinka

Dzisiejszy odcinek pokazuje, że rynek przesuwa się z samego zachwytu agentami na ich infrastrukturę, kontrolę i skutki uboczne. Agenci mają łatwiej deployować kod, ale jednocześnie wymagają mocniejszych barier bezpieczeństwa, monitoringu, zasad eksportowych, kontroli prywatności i odporności repozytoriów pakietów.

## Segmenty

1. **Cloudflare Temporary Accounts**
   - Agent może uruchomić tymczasowy deploy Workera bez standardowej rejestracji konta.
   - Człowiek może przejąć konto, a nieprzejęty zasób wygasa po sześćdziesięciu minutach.
   - Ważne: to praktyczna infrastruktura agent-ready, nie tylko produkt marketingowy.

2. **Google DeepMind AI Control Roadmap**
   - DeepMind traktuje agentów jako potencjalne insider threats i opisuje defense-in-depth.
   - Ważne: rozmowa przechodzi z alignmentu modelu na kontrolę uprawnień, sandboxing, monitoring i reakcję.

3. **Anthropic, Fable, Mythos i eksport frontier models**
   - Anthropic potwierdził dyrektywę USA blokującą dostęp cudzoziemców do Fable 5 i Mythos 5.
   - Axios i Bloomberg Law rozwijają kontekst bezpieczeństwa narodowego.
   - Ważne: frontier models zaczynają wyglądać jak aktywa eksportowe.

4. **AUR i supply-chain security**
   - Arch Linux/aur-general i Phoronix pokazują duży incydent z malicious packages.
   - HN potwierdza silny sygnał społeczności technicznej.
   - Ważne: po GitHub malware z poprzednich dni mamy kolejny przykład ryzyka dla ludzi i agentów pobierających kod.

5. **Microsoft Teams workplace check-in**
   - Microsoft Learn opisuje auto-detekcję lokalizacji pracy przez peryferia biurkowe i Wi-Fi; BI Polska pokazuje obawy pracowników.
   - Ważne: funkcja produktywności szybko staje się sporem o prywatność i politykę powrotu do biur.

6. **Wrocławskie tramwaje i AI poza chatbotami**
   - Business Insider Polska opisuje system antykolizyjny Skody w tramwajach MPK Wrocław.
   - Ważne: lokalny przykład AI w czujnikach, transporcie i bezpieczeństwie pasażerów.

## Weryfikacja redakcyjna

- Źródła pierwotne: Cloudflare, Google DeepMind, Anthropic, Microsoft Learn, Arch Linux/aur-general.
- Źródła redakcyjne: Axios, Bloomberg Law, Phoronix, Business Insider Polska.
- Sygnały społecznościowe: Hacker News, Product Hunt.
- Nie używać Reddita jako źródła faktów.
- Wątki security opisać informacyjnie, bez instrukcji operacyjnych.

