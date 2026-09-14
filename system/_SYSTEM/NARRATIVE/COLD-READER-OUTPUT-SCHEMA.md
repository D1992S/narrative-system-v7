# K4 Cold Reader — zamknięty format wyjścia V1

Nowe pakiety zawierają `RUN_CONTEXT.json` z dokładnym `draft_sha256` oraz `RESPONSE_TEMPLATE.md` z nagłówkami i rejestrami wyliczonymi z wejścia. Uzupełnij szkielet po wykonaniu analizy; znaczniki `<...>` nie są werdyktami i nie przechodzą walidacji. Nie zmieniaj identyfikatorów ani hashy. Starsze pakiety bez tych plików zachowują poniższy format; hash odczytaj z manifestu: VERIFY z wpisu DRAFT_BLOCKS.sha256, pozostałe soczewki z nazwy clean-narration-<SHA>.md w source_relative.

Wynik musi zawierać dokładnie po jednym z poniższych nagłówków sterujących:

```text
SCHEMA: K4_COLD_READER_OUTPUT_V1
LENS: COLD_READER
DRAFT_SHA256: <64 znaki SHA-256>
VERDICT: PASS|FAIL
CRITICAL_COUNT: <liczba całkowita >= 0>
MAJOR_COUNT: <liczba całkowita >= 0>
MINOR_COUNT: <liczba całkowita >= 0>
REVIEW_ALERT_COUNT: <liczba całkowita >= 0>
```

Następnie musi wystąpić dokładnie 20 niepustych pól: `Q01_RESPONSE` i `Q01_EVIDENCE` aż do `Q10_RESPONSE` i `Q10_EVIDENCE`. Pole `EVIDENCE` wskazuje konkretny fragment lub miejsce w czystej narracji, a nie plan ani domniemaną intencję.

Na końcu muszą wystąpić dokładnie raz niepuste sekcje `## CONFUSION_AND_DROPOFF`, `## PAYOFF_AND_MEMORY` oraz `## FINDINGS`. Każdy problem ma format:

```text
FINDING: C-001 | SEVERITY: CRITICAL|MAJOR|MINOR | LOCATION: <cytat orientacyjny lub miejsce> | OBSERVATION: <konkret> | CLOSURE: <warunek zamknięcia>
```

Jeżeli problemów nie ma, `FINDINGS` zawiera wyłącznie `BRAK`. Liczniki muszą odpowiadać wierszom. `PASS` wymaga zera problemów `CRITICAL`, `MAJOR` i zera alertów przeglądu. Cold Reader nie otrzymuje architektury, źródeł, Story Spine ani zasad głosu.
