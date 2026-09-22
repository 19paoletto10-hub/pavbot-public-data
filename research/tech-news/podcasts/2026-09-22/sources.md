# Źródła — 22 września 2026

## Zakres i ograniczenia

Raport `research/tech-news/runs/2026-09-22.md` nie istniał podczas uruchomienia automatyzacji. Zastosowano awaryjny skrócony research publicznych serwisów. Punktem wyjścia był raport z 20 września 2026 (`runs/2026-09-20-1933.md`), a następnie sprawdzono publiczne publikacje z 17–21 września. Nie użyto źródeł wymagających logowania. Część materiału ma charakter branżowego komentarza lub deklaracji producenta.

## Źródła wykorzystane

- The Hacker News, „DeepSeek Harness Flaw Let AI Agents Disable Their Own File Sandbox Without Approval”, 9 września 2026: https://thehackernews.com/2026/09/deepseek-harness-flaw-let-ai-agents.html — opis CVE-2026-82533, mechanizmu wyłączenia sandboxa i poprawki.
- Axios, „Forget doomsday: The AI hacking crisis is already here”, 17 września 2026: https://www.axios.com/2026/09/17/ai-cyber-doomsday-hacking-threats — kontekst incydentów OpenAI i ocena, że problemem są także klasyczne słabości bezpieczeństwa.
- Associated Press, „OpenAI flags concerning new AI behavior and vows to track it more closely”, 17 września 2026: https://apnews.com/article/089e75b95bc935af092da7b79d92706d — niezależna relacja o ujawnionych zachowaniach agentów; szczegóły traktowane ostrożnie.
- NVIDIA Blog, „AI Security Is an Engineering Problem — How to Solve It at Every Layer of the Agent Stack”, 21 września 2026: https://blogs.nvidia.com/blog/ai-security-engineering-problem/ — stanowisko producenta o warstwach kontroli; nie jest niezależnym audytem.
- The Hacker News, „Plugin4Shell Lets Repository Owners ...”, wrzesień 2026: https://thehackernews.com/2026/09/plugin4shell-lets-repository-owners.html — opis klasy ryzyka w pluginach agentów kodujących; status poprawek może się zmieniać.
- xAI, „Grok Voice Transcribe 2”, wrzesień 2026: https://x.ai/news/grok-voice-transcribe-2 — deklaracje funkcji i dokładności producenta; brak niezależnego benchmarku polskiego.
- TechCrunch, „The fix for rogue AI agents could be more AI”, 17 września 2026: https://techcrunch.com/2026/09/17/the-fix-for-rogue-ai-agents-could-be-more-ai/ — kontekst obserwowalności dużych zbiorów działań agentów.
- AWS Security Blog, „Agentic security: Detection and response at machine speed”, 2 września 2026: https://aws.amazon.com/blogs/security/agentic-security-detection-and-response-at-machine-speed/ — dodatkowy kontekst architektury detekcji; materiał dostawcy chmury.

## Ocena pewności

- Wysoka: istnienie publicznego opisu luki DeepSeek Harness i wskazanej poprawki.
- Średnia: opisy incydentów ewaluacyjnych, ponieważ publiczne relacje nie zawierają pełnych logów ani niezależnego audytu.
- Niska do średniej: przewaga jakościowa Grok Voice Transcribe 2.0, ponieważ „dwa razy lepsza dokładność” pochodzi od xAI.
