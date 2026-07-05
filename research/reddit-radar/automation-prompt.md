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
zdalny manifest, a dopiero potem wyślij finalny digest na endpoint produkcyjny.

Nie używaj Reddit OAuth. Nie klikaj vote/like/comment/share, nie wysyłaj
formularzy, nie publikuj postów ani komentarzy i nie omijaj login/CAPTCHA.

Kolejność przebiegu:

1. Zbierz kandydatów i zapisz artefakty:
   `python3 scripts/collect_safari_reddit_humor.py --subreddits Polska_wpz,memes,ProgrammerHumor,Polska,technology,AskReddit,mildlyinfuriating,OutOfTheLoop,facepalm --max-items 8 --replace-count 8 --interval-hours 6`
2. Ręcznie lub przez read-only Computer Use/Safari review potwierdź komentarze
   każdego publikowanego itemu. Każdy item musi mieć status `reviewed` albo
   `no_safe_comments`.
3. Nie publikuj słabego, zduplikowanego lub zbyt krótkiego zestawu. Jeśli po
   filtrach nie ma wystarczająco dobrych nowych tematów, zostaw poprzedni
   produkcyjny digest bez zmian i zapisz diagnozę w `runs/`.
4. Opublikuj audit i manifest:
   `scripts/pavbot_commit_and_push_outputs.sh --isolated research/reddit-radar`
5. Zweryfikuj zdalny pakiet:
   `python3 scripts/pavbot_publication_contract.py verify-remote research/reddit-radar --ref origin/main`
6. Dopiero po udanym pushu i verify-remote wyślij finalny digest do notifiera
   produkcyjnego przez obsługiwaną ścieżkę skryptu albo endpoint notifiera.

Wymagane artefakty topicu:

- `research/reddit-radar/data/YYYY-MM-DD-HHMM-reddit-radar-raw.json`
- `research/reddit-radar/data/YYYY-MM-DD-HHMM-reddit-radar.json`
- `research/reddit-radar/runs/YYYY-MM-DD-HHMM-reddit-radar.md`

Publikacja notifiera bez wcześniejszego `origin/main` i zdalnego manifestu jest
stanem częściowym/nieudanym, nie sukcesem.
```
