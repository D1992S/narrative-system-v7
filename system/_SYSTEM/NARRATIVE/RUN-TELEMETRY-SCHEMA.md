# Telemetria runu Narrative V2

SCHEMA: `NARRATIVE_RUN_TELEMETRY_V1`

Telemetria służy do mierzenia kosztu i czasu. Nie jest bramką jakości, nie zastępuje receiptu i nie zapisuje ukrytego toku rozumowania modelu.

## Dane obowiązkowe w każdym poprawnym run receipcie

System zawsze oblicza lokalnie: liczbę bajtów wejścia i wyjścia, ostrożne estymacje tokenów metodą `UTF8_BYTES_DIV4_CEILING`, czas od `started_at_utc` do `completed_at_utc`, status runu oraz przyczynę fail/repack. Kanoniczny receipt dowodowy ma `run_status: COMPLETED` i `failure_or_repack_reason: BRAK`; nieudana próba nie może podszyć się pod poprawny dowód.

## Opcjonalny raport wykonawcy

Jeżeli wykonawca udostępnia dokładne metryki, zapisuje bez BOM plik:

`_work/narrative-runs/<RUN_ID>/provider-telemetry.json`

Plik ma dokładnie schemat:

```json
{
  "schema": "MODEL_RUN_TELEMETRY_V1",
  "input_tokens": 0,
  "prefix_tokens": 0,
  "source_card_tokens": 0,
  "output_tokens": 0,
  "cache_read_tokens": 0,
  "cache_write_tokens": 0,
  "retry_count": 0,
  "cost_amount": null,
  "cost_currency": "BRAK"
}
```

Wartości tokenów i retry są nieujemnymi liczbami całkowitymi; retry nie może przekroczyć 100. Koszt jest `null` z walutą `BRAK` albo nieujemną liczbą i trzyznakowym kodem waluty. Cache ma stan `HIT`, `WRITE_ONLY` albo `MISS` wyłącznie na podstawie faktycznych wartości read/write.

Brak raportu daje `AUTOMATIC_ONLY`. Poprawny raport daje `PROVIDER_REPORTED`. Błędna ścieżka, brak pliku, BOM albo błędny schemat daje `PROVIDER_REJECTED_NON_BLOCKING`: prawidłowy output pozostaje ważny, ale system nie przypisuje mu niezweryfikowanych metryk. Cache miss i błąd telemetrii nigdy nie zmieniają treści ani nie blokują pilota.
