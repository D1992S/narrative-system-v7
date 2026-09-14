# QA IMPACT V1

Mechanicznie bezpieczne jest wyłącznie `BYTE_IDENTICAL`. Każda różnica bajtowa — także przecinek, negacja, odstęp lub inna interpunkcja — otrzymuje `SEMANTIC_REVIEW_REQUIRED` i trafia do świeżego kontekstu `QA_IMPACT_REVIEW`. Interpunkcja może zmienić sens, dlatego nie wolno przenosić PASS wyłącznie na podstawie normalizacji znaków.

Każda soczewka otrzymuje osobną decyzję `RERUN_REQUIRED` albo `CARRYFORWARD_ALLOWED`. Niepewność zawsze oznacza rerun. Zmiana twierdzenia, źródła, sceny, reveal, struktury, obietnicy albo zakresu nie może zostać mechanicznie uznana za bezpieczną.

Wynik świeżego przeglądu ma zamknięty format:

```text
SCHEMA: QA_IMPACT_OUTPUT_V1
DIFF_SHA256: <SHA-256>
OLD_DRAFT_SHA256: <SHA-256>
NEW_DRAFT_SHA256: <SHA-256>
CHANGE_CLASS: SEMANTIC_REVIEW_REQUIRED
CHANGED_BLOCK_IDS: <lista rozdzielona przecinkami>|BRAK
EDITOR_DECISION: RERUN_REQUIRED|CARRYFORWARD_ALLOWED
EDITOR_REASON: <konkret>
EDITOR_AFFECTED_SCOPE: <konkret>
EDITOR_CONFIDENCE: HIGH|MEDIUM|LOW
VERIFY_DECISION: RERUN_REQUIRED|CARRYFORWARD_ALLOWED
VERIFY_REASON: <konkret>
VERIFY_AFFECTED_SCOPE: <konkret>
VERIFY_CONFIDENCE: HIGH|MEDIUM|LOW
COLD_READER_DECISION: RERUN_REQUIRED|CARRYFORWARD_ALLOWED
COLD_READER_REASON: <konkret>
COLD_READER_AFFECTED_SCOPE: <konkret>
COLD_READER_CONFIDENCE: HIGH|MEDIUM|LOW
```

`CARRYFORWARD_ALLOWED` wymaga `HIGH` oraz konkretnego uzasadnienia opartego na przekazanym diffie. `MEDIUM`, `LOW`, brak możliwości rozstrzygnięcia albo zmiana mogąca dotknąć daną soczewkę oznaczają `RERUN_REQUIRED`.
