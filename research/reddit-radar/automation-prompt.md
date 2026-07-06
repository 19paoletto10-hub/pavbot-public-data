# Automation Prompt: Pavbot Reddit Safari Humor Radar

```text
$daily-research-agent

Uruchom workflow `Pavbot Reddit Safari Humor Radar` dla
`research/reddit-radar`. Pracuj zgodnie z `research/reddit-radar/topic.md`,
tym kontraktem oraz `AGENTS.md`.

Cel: użyj zalogowanej lokalnej sesji Safari wyłącznie do odczytu publicznych
stron Reddita. Wybierz bezpieczne, nowe i niepowtarzające się tematy do sekcji
iOS `Dzisiaj -> Śmiechowy radar`, przygotuj polską analizę posta i wybranych
komentarzy, zapisz lokalny audit, opublikuj audit do `origin/main`, zweryfikuj
zdalny manifest, a dopiero potem wystaw finalny digest przez CloudKit
Briefing gate.

Nie używaj Reddit OAuth. Nie klikaj vote/like/comment/share, nie wysyłaj
formularzy, nie publikuj postów ani komentarzy i nie omijaj login/CAPTCHA.

Konfliktowe lub polaryzujące posty są dozwolone, jeśli nadal działają jako
humor/internet absurd i po read-only review da się wybrać bezpieczne komentarze.
Nie publikuj zestawów opartych na mowie nienawiści, dehumanizacji, atakach na
cechy chronione, wezwaniu do przemocy albo komentarzach napędzających pile-on.

Kolejność przebiegu:

1. Zbierz kandydatów i zapisz artefakty:
   `python3 scripts/collect_safari_reddit_humor.py --subreddits Polska_wpz,memes,ProgrammerHumor,Polska,technology,AskReddit,mildlyinfuriating,OutOfTheLoop,facepalm --max-items 8 --replace-count 8 --interval-hours 6`
2. Ręcznie lub przez read-only Computer Use/Safari review potwierdź komentarze
   każdego publikowanego itemu. Każdy item musi mieć status `reviewed` albo
   `no_safe_comments`.
3. Nie publikuj słabego, zduplikowanego lub zbyt krótkiego zestawu. Dopuszczaj
   konfliktowe tematy tylko wtedy, gdy absurd/punchline jest czytelny, a
   wybrane komentarze są bezpieczne. Jeśli po filtrach nie ma
   wystarczająco dobrych nowych tematów, zostaw poprzedni produkcyjny digest
   bez zmian i zapisz diagnozę w `runs/`.
4. Opublikuj audit i manifest jednym wspólnym skryptem:
   `scripts/pavbot_commit_and_push_outputs.sh --isolated research/reddit-radar`
5. Dopiero po sukcesie tego skryptu uznaj digest za produkcyjnie opublikowany.
   Skrypt publikacji jest jedyną bramką produkcyjną; sam odświeża manifest,
   publikuje artefakty na origin/main, weryfikuje zdalny stan oraz tworzy i
   weryfikuje CloudKit Briefing. Produkcyjny flow iOS pozostaje: artefakty +
   `public/pavbot-manifest.json` na origin/main, potem CloudKit Briefing w
   `iCloud.com.paweltanski.pavbotviewer` / `production` / `SP774TZZU8`, potem
   APNs. Jeśli skrypt zwróci błąd, traktuj przebieg jako failed albo partially
   published; ręczne komendy są dozwolone wyłącznie do diagnostyki, nie do
   dokańczania produkcyjnej publikacji.

Wymagane artefakty topicu:

- `research/reddit-radar/data/YYYY-MM-DD-HHMM-reddit-radar-raw.json`
- `research/reddit-radar/data/YYYY-MM-DD-HHMM-reddit-radar.json`
- `research/reddit-radar/runs/YYYY-MM-DD-HHMM-reddit-radar.md`

Publikacja bez wcześniejszego `origin/main`, zdalnego manifestu i CloudKit gate
jest stanem częściowym/nieudanym, nie sukcesem.
```
