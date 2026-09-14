# K4 Editor — zamknięty format wyjścia V2

Nowe pakiety zawierają `RUN_CONTEXT.json` z dokładnym `draft_sha256` oraz `RESPONSE_TEMPLATE.md` z nagłówkami i rejestrami wyliczonymi z wejścia. Uzupełnij szkielet po wykonaniu analizy; znaczniki `<...>` nie są werdyktami i nie przechodzą walidacji. Nie zmieniaj identyfikatorów ani hashy. Starsze pakiety bez tych plików zachowują poniższy format; hash odczytaj z manifestu: VERIFY z wpisu DRAFT_BLOCKS.sha256, pozostałe soczewki z nazwy clean-narration-<SHA>.md w source_relative.

Wynik musi zawierać dokładnie po jednym z poniższych nagłówków sterujących:

```text
SCHEMA: K4_EDITOR_OUTPUT_V1
LENS: EDITOR
DRAFT_SHA256: <64 znaki SHA-256>
VERDICT: PASS|FAIL
CRITICAL_COUNT: <liczba całkowita >= 0>
MAJOR_COUNT: <liczba całkowita >= 0>
MINOR_COUNT: <liczba całkowita >= 0>
REVIEW_ALERT_COUNT: <liczba całkowita >= 0>
```

Po nagłówkach muszą wystąpić dokładnie raz niepuste sekcje: `## HOOK_AND_PROMISE`, `## QUESTION_REVEAL_LOGIC`, `## TWO_AXES_AND_STATE_CHANGE`, `## EXPOSITION_TRANSITIONS`, `## VOICE_VIEWER_CONTACT`, `## FINALE` oraz `## FINDINGS`.

Cztery sekcje są zamkniętymi rejestrami. W każdej zachowaj kolejność wejścia, nie pomijaj, nie dodawaj i nie powtarzaj rekordów. Po rekordach dodaj dokładnie jeden rzeczowy wiersz `ANALYSIS:` (minimum osiem słów i 50 znaków).

`QUESTION_REVEAL_LOGIC`:

```text
NQ_JSON: {"nq_id":"NQ-001","opened_at":"SW-001","payoff_node":"SW-003","block_ids":["BLOCK-ACT-001-001"],"status":"PASS"}
NR_JSON: {"nr_id":"NR-001","target_node":"SW-003","evidence_p_ids":["#P-001"],"block_ids":["BLOCK-ACT-002-001"],"status":"PASS"}
ANALYSIS: <ocena logiki otwarcia, przygotowania, wypłaty i konsekwencji>
```

`TWO_AXES_AND_STATE_CHANGE`:

```text
ACT_JSON: {"act_id":"ACT-001","block_ids":["BLOCK-ACT-001-001"],"scene_weave_ids":["SW-001"],"state_change_sw_id":"SW-001","status":"PASS"}
ANALYSIS: <ocena zmiany wiedzy i napięcia oraz funkcji aktu>
```

`EXPOSITION_TRANSITIONS`:

```text
REQUIRED_JSON: {"sw_id":"SW-001","p_id":"#P-001","function":"<funkcja>","necessity":"<konieczność>","block_ids":["BLOCK-ACT-001-001"],"status":"PASS"}
ANALYSIS: <ocena pracy dowodu, ekspozycji w miejscu użycia i przejść>
```

`VOICE_VIEWER_CONTACT`:

```text
VC_JSON: {"vc_id":"VC-001","node":"SW-001","function":"ORIENT","level":"MICRO","block_ids":["BLOCK-ACT-001-001"],"status":"PASS"}
PREFLIGHT_JSON: {"finding_id":"SP-001","rule_id":"VOICE_EXEMPLAR_8GRAM_OVERLAP","act_id":"ACT-001","block_id":"BLOCK-ACT-001-001","evidence":"<dokładny sygnał>","status":"PASS"}
ANALYSIS: <ocena funkcji kontaktów, głosu, każdego alertu preflight i ryzyka maniery>
```

Jeżeli dany oczekiwany rejestr jest pusty, wpisz dokładnie `<NAZWA>_JSON: BRAK`; `ANALYSIS:` pozostaje obowiązkowe. Każdy JSON zajmuje jeden wiersz i ma dokładnie pokazane pola. `status` przyjmuje wyłącznie `PASS` albo `FAIL`. `VERDICT: PASS` wymaga `PASS` we wszystkich rekordach maszynowych.

Każdy problem w `FINDINGS` ma być jednym wierszem:

```text
FINDING: E-001 | SEVERITY: CRITICAL|MAJOR|MINOR|REVIEW_ALERT | BLOCK_ID: BLOCK-ACT-001-001|GLOBAL | CRITERION: <konkret> | OBSERVATION: <konkret> | CLOSURE: <warunek zamknięcia>
```

Jeżeli problemów nie ma, sekcja `FINDINGS` zawiera wyłącznie `BRAK`. Liczniki muszą odpowiadać wierszom. `PASS` wymaga zera problemów `CRITICAL`, `MAJOR`, zera alertów przeglądu i pełnej maszynowej kontroli wszystkich oczekiwanych rekordów. Editor nie wykonuje fact-checku z pamięci i nie przepisuje narracji.
