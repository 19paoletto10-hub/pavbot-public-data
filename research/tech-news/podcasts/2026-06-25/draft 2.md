# Podcast Tech Draft: 2026-06-25

## Baza

Dzisiejszy raport `research/tech-news/runs/2026-06-25.md` istnieje i jest główną bazą odcinka. Po raporcie wykonano świeży check źródeł publicznych: OpenAI, Broadcom, Qualcomm/Business Wire, Google, Micron, GitHub, Product Hunt, Hacker News, Reddit oraz publiczne omówienia Reutersa dotyczące Anthropic/Alibaba.

## Teza odcinka

AI przestaje być wyłącznie konkursem modeli. Najmocniejsze historie dnia pokazują przejście do kontroli pełnego stacku: chipów inference, pamięci, agentowych API, delegated access, model extraction, kosztów energii oraz operacyjnego review pracy generowanej przez agentów.

## Segmenty robocze

1. OpenAI i Broadcom: Jalapeño.
   - Pierwszy OpenAI Intelligence Processor do inference LLM.
   - Istotne: full-stack AI od modelu po chip, networking i serving.
   - Ryzyko: brak niezależnych benchmarków; deployment dopiero planowany do końca 2026 roku.

2. Qualcomm: Modular, Hugging Face, Meta i data center.
   - Przejęcie Modular, rozszerzenie relacji z Hugging Face, strategiczna umowa CPU z Meta.
   - Istotne: edge-to-cloud AI stack i konkurencja z dominacją GPU.
   - Ryzyko: część obietnic to forward-looking targets.

3. Google: Interactions API i Gemini computer use.
   - Interactions API ma GA i jest głównym interfejsem dla Gemini models/agents.
   - Computer use w Gemini 3.5 Flash przenosi agentów do realnych interfejsów.
   - Istotne: stateful API, sandbox, background tasks, prompt-injection safeguards.

4. Anthropic kontra Alibaba/Qwen.
   - Reuters opisuje zarzuty Anthropic: 28,8 mln interakcji i prawie 25 tys. fałszywych kont.
   - Istotne: model extraction/distillation jako nowy front IP, bezpieczeństwa i geopolityki AI.
   - Ryzyko: zarzuty, brak publicznie rozstrzygniętego incydentu i brak natychmiastowego komentarza Alibaba.

5. Micron/Anthropic i fizyczne koszty AI.
   - Rekordowy wynik Microna, umowa z Anthropic, HBM i storage jako bottleneck.
   - Uzupełnienie: Ratepayer Protection Act, woda, chłodzenie Nvidii.
   - Istotne: AI to pamięć, energia, sieć, chłodzenie i umowy podaży, nie tylko GPU.

6. Drugi koszt AI: tokeny, PR-spam i agenci w narzędziach pracy.
   - GitHub PR limits, Greptile/OpenClaw, 404 Media tokenpocalypse.
   - Product Hunt i HN pokazują agentowe narzędzia jako bieżący sygnał.
   - Istotne: operational governance, review bandwidth, koszt tokenów i odpowiedzialność za output agentów.

## Decyzje redakcyjne

- Nie używać w scenariuszu surowych URL-i.
- Liczby pisać przyjaźnie dla TTS: „dwadzieścia osiem przecinek osiem miliona”, „prawie dwadzieścia pięć tysięcy”.
- Przy Qualcomm i Micron unikać tonu inwestycyjnego.
- Przy Anthropic/Alibaba mówić „Anthropic oskarża” i „Reuters opisał”, nie traktować sprawy jako rozstrzygniętej.
- Przy NVIDIA cooling używać „twierdzenie dostawcy”, a nie fakt niezależnie potwierdzony.
