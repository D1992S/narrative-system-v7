# Beat Preflight

SCHEMA: BEAT_PREFLIGHT_V1

Dla aktu `COMPLEX` sprawdź bez pisania prozy: zgodność beatów z dozwolonymi `SW_ID`, kartami P, stanami wejścia/wyjścia oraz działaniami NQ/NR/VC. Beat-sheet nie może dodać źródła, revealu ani obowiązku spoza paczki.

Zwróć dokładnie:

```text
VERDICT: PASS|FAIL
ACT_ID: ACT-000
SCHEMA_CHECK: PASS|FAIL
IDENTIFIER_CHECK: PASS|FAIL
STATE_TRANSITION_CHECK: PASS|FAIL
NO_ADDED_SOURCE_OR_REVEAL: PASS|FAIL
DISCREPANCIES: BRAK albo konkretna lista
REASON: konkretnie
```
