# K4 Verify — zamknięty format wyjścia V1

Nowe pakiety zawierają `RUN_CONTEXT.json` z dokładnym `draft_sha256` oraz `RESPONSE_TEMPLATE.md` z nagłówkami i rejestrami wyliczonymi z wejścia. Uzupełnij szkielet po wykonaniu analizy; znaczniki `<...>` nie są werdyktami i nie przechodzą walidacji. Nie zmieniaj identyfikatorów ani hashy. Starsze pakiety bez tych plików zachowują poniższy format; hash odczytaj z manifestu: VERIFY z wpisu DRAFT_BLOCKS.sha256, pozostałe soczewki z nazwy clean-narration-<SHA>.md w source_relative.

Wynik musi zawierać dokładnie po jednym z poniższych nagłówków sterujących:

```text
SCHEMA: K4_VERIFY_OUTPUT_V1
LENS: VERIFY
DRAFT_SHA256: <64 znaki SHA-256>
VERDICT: PASS|FAIL
CRITICAL_COUNT: <liczba całkowita >= 0>
MAJOR_COUNT: <liczba całkowita >= 0>
MINOR_COUNT: <liczba całkowita >= 0>
REVIEW_ALERT_COUNT: <liczba całkowita >= 0>
```

Po nagłówkach muszą wystąpić dokładnie raz niepuste sekcje: `## CLAIM_COVERAGE`, `## SOURCE_LOCATORS_CHECKED`, `## ATTRIBUTION_UNCERTAINTY`, `## CONTRADICTIONS` oraz `## FINDINGS`.

`CLAIM_COVERAGE` jest zamkniętym rejestrem. Musi zawierać, w kolejności mapy bloków, dokładnie jeden wiersz na każdy blok oraz dokładnie jeden rzeczowy wiersz `ANALYSIS:`:

```text
COVERAGE_JSON: {"block_id":"BLOCK-ACT-001-001","p_ids":["#P-001"],"status":"PASS"}
ANALYSIS: <co sprawdzono i gdzie występuje ryzyko; minimum osiem słów i 50 znaków>
```

`p_ids` musi być identyczne z mapą wejściową, także gdy jest pustą tablicą. Nie wolno pominąć, dodać ani powtórzyć bloku.

`SOURCE_LOCATORS_CHECKED` musi zawierać, w kolejności pierwszego użycia kart w blokach, dokładnie jeden wiersz na każdą użytą kartę P oraz jeden wiersz `ANALYSIS:`:

```text
LOCATOR_JSON: {"p_id":"#P-001","source_id":"SRC-001","locator":"strona 12","status":"PASS"}
ANALYSIS: <co fizycznie sprawdzono w źródłach i lokalizatorach>
```

Jeżeli oczekiwany rejestr jest pusty, zamiast wierszy JSON wpisz dokładnie `<NAZWA>_JSON: BRAK`; `ANALYSIS:` nadal jest obowiązkowe. Każdy JSON jest jednym wierszem i ma dokładnie pokazane pola. `status` przyjmuje wyłącznie `PASS` albo `FAIL`. Ogólny `VERDICT: PASS` wymaga `PASS` w każdym wierszu maszynowym.

Każdy problem w `FINDINGS` ma być jednym wierszem:

```text
FINDING: V-001 | SEVERITY: CRITICAL|MAJOR|MINOR | BLOCK_ID: BLOCK-ACT-001-001 | P_ID: #P-001|BRAK | SOURCE_ID: <id>|BRAK | LOCATOR: <dokładna lokalizacja>|BRAK | OBSERVATION: <konkret> | CLOSURE: <minimalna korekta albo dowód>
```

Jeżeli problemów nie ma, sekcja `FINDINGS` zawiera wyłącznie `BRAK`. Liczniki muszą odpowiadać wierszom. `PASS` wymaga zera problemów `CRITICAL`, `MAJOR`, zera alertów przeglądu i pełnej maszynowej kontroli wszystkich oczekiwanych rekordów. Verify używa wyłącznie przekazanej bazy, lokalizatorów i fizycznych źródeł; nie ocenia atrakcyjności narracji.
