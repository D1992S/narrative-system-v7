# K1-Lite V2 — izolowany silnik analizy źródeł

## Co to robi

V2 zamienia przygotowany tekst PDF albo natywny MD/TXT/SRT/VTT na małe pakiety zgodne z jednostkami materiału, zbiera **wszystkich** wykrytych kandydatów w niezmiennym dzienniku, lokalnie sprawdza cytaty i buduje widoki do decyzji Dawida. Sam silnik nie zapisuje kanonicznej bazy; kontrolowany import wykonuje nadrzędny kompilator System-v7 po przejściu sześciu bramek.

Najważniejsza zasada: model odkrywa i opisuje materiał, ale lokalny kod rozstrzyga, czy cytat naprawdę znajduje się w deklarowanej lokalizacji strony, globalnych linii albo czasu. Decyzje `MUST_INCLUDE`, `IMPORTANT_SIDE` i `REJECTED`, potwierdzenia konfliktów oraz receipt przeglądu należą do Dawida; `KEY_CHATGPT` może być rekomendacją ChatGPT.

## Przepływ

1. Dla PDF warstwa wejściowa przygotowuje wierny tekst z kotwicami stron i OCR tylko tam, gdzie jest potrzebny. Samodzielny MD/TXT/SRT/VTT pozostaje niezmieniony.
2. `Plan` odczytuje spis sekcji i dzieli źródło na pakiety. Dodatki są traktowane jako treść, a bibliografia i indeks jako osobna warstwa referencyjna — żadna jednostka materiału nie znika.
   Jeżeli run ma K0, do każdego pakietu trafia krótki, hashowany brief filmu zamiast całego obszernego dokumentu.
3. `NextWork` wskazuje kolejny fragment i wcześniejszych kandydatów. Worker czyta cały pakiet i stosuje limit z planu: domyślnie 2; eksperymentalnie 4 albo 8 po jawnym ustawieniu `CandidateLimit` przy tworzeniu nowego runu. Jeżeli ma więcej, zgłasza `PARTIAL_OVERFLOW`, a system wymusza kolejną odpowiedź. Zmiana dziennika podczas odczytu kolejki wymaga ponowienia `NextWork`.
4. `ImportResult` sprawdza znaczniki kontrolne, dokładny cytat, stronę, liczby, identyfikatory i telemetrykę. Dopiero wtedy dopisuje zdarzenia do `ledger.jsonl`. `ImportBatch` stosuje tę samą kontrolę do uporządkowanej partii wyników i publikuje ją po sprawdzeniu całości.
5. Rekomendacje ChatGPT i decyzje Dawida są dopisywane bez modyfikowania wcześniejszych zapisów. Tylko Dawid może potwierdzić konflikt wybranego kandydata.
6. `InspectLayout` wykrywa strony z tabelami, kolumnami, obrotem, nietypowym tekstem albo dużą liczbą wektorów. To kolejka do kontroli, nie automatyczne odrzucenie.
7. `AddVisual` wiąże kontrolę obrazu strony i kadru z hashami źródła oraz cytatu.
8. `VerifyBatch` w jednym odczycie źródła ponownie rozwiązuje wszystkie aktywne cytaty.
9. `BuildViews` generuje pokrycie, pełny rejestr, konflikty, metryki, kontrolę cytatów, deterministyczny `editorial-review.md` i podgląd stagingu. Ponownie liczy również SHA artefaktów wskazanych przez aktywne visual receipts. Telemetria jawnie rozróżnia dane zmierzone od niedostępnych.
10. Dawid czyta `editorial-review.md`. `AddReview` sprawdza receipt `K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1`, jego `snapshot_sha256`, względną ścieżkę i SHA artefaktu, `actor: DAWID` oraz `verdict: REVIEWED`, po czym dopisuje `editorial_review_receipt` do ledgera.
11. Ponowne `BuildViews` i `ValidateRun` muszą potwierdzić sześć bramek: `coverage_ready`, `quotes_ready`, `decisions_current`, `selected_visual_ready`, `selected_conflicts_acknowledged` i `editorial_review_ready`.

## Twarde zabezpieczenia

- Każda ścieżka musi znajdować się w jawnie wskazanym katalogu projektu.
- Źródło, PDF, K0, strony, pakiety, cytaty i obrazy są związane SHA-256.
- Nowe runy, raporty i widoki mają semantykę `CreateNew`; istniejący plik nie jest nadpisywany.
- Ledger jest append-only i wymaga SHA poprzedniej wersji, więc równoległa/stara operacja nie dopisze danych po cichu.
- Widok stagingu ma etykietę `REVIEWED_PREVIEW_REQUIRES_COMPILER`.
- Pełne pokrycie oznacza każdą jednostkę materiału dokładnie raz, również dodatki i referencje.
- Aktywne PDF/MD/TXT/SRT/VTT muszą leżeć bezpośrednio w `sources/`. Obsługiwany plik zagnieżdżony jest błędem; nieobsługiwane pliki techniczne i `_oryginaly/` nie są aktywnymi źródłami.
- Zmiana kandydatów, rekomendacji, decyzji lub konfliktów unieważnia receipt przeglądu. Sama zmiana kontroli obrazu go nie unieważnia.

## Najważniejsze polecenia

```powershell
$project = 'E:\projektyoutube\_work\system-optimization-20260914\projekty-testowe\Nazwa filmu'
$run = "$project\_work\K1\k1-lite-v2\run-001"
$tool = 'E:\projektyoutube\_work\system-optimization-20260914\System-v7.0-KOPIA-ROBOCZA\tools\k1-lite-v2\Invoke-K1LiteV2.ps1'

& $tool -Action Plan `
  -ProjectDirectory $project `
  -SourcePath '<tekst--TEXT.md>' -ExpectedSourceSha256 '<SHA>' `
  -PdfPath '<źródło.pdf>' -ExpectedPdfSha256 '<SHA>' `
  -K0Path '<00-fundament-projektu.md>' -ExpectedK0Sha256 '<SHA>' `
  -RunDirectory $run

& $tool -Action ImportResult -ProjectDirectory $project -RunDirectory $run -ResultPath '<wynik.json>' -ExpectedLedgerSha256 CREATE_NEW
& $tool -Action AddDecisions -ProjectDirectory $project -RunDirectory $run -DecisionPath '<decyzje.json>' -ExpectedLedgerSha256 '<aktualny SHA ledgeru>'
& $tool -Action InspectLayout -ProjectDirectory $project -RunDirectory $run -OutputPath "$run\qa\layout-001.json"
& $tool -Action VerifyBatch -ProjectDirectory $project -RunDirectory $run -OutputPath "$run\qa\quotes-001.json"
& $tool -Action BuildViews -ProjectDirectory $project -RunDirectory $run -OutputDirectory "$run\views\build-001"
& $tool -Action AddReview -ProjectDirectory $project -RunDirectory $run `
  -ReceiptPath "$run\editorial-review-receipt-001.json" `
  -ExpectedLedgerSha256 '<aktualny SHA ledgeru>'
& $tool -Action BuildViews -ProjectDirectory $project -RunDirectory $run -OutputDirectory "$run\views\build-002"
& $tool -Action ValidateRun -ProjectDirectory $project -RunDirectory $run
```

Po pierwszym imporcie zamiast `CREATE_NEW` zawsze należy podawać SHA aktualnego `ledger.jsonl`.

Dla samodzielnego MD/TXT/SRT/VTT w `Plan` pomiń `-PdfPath` i `-ExpectedPdfSha256`; każdy taki plik otrzymuje osobny run. Receipt wejściowy `AddReview` musi leżeć wewnątrz runu i zawierać co najmniej dwuwyrazową notatkę długości 12 znaków.

## Co ogląda człowiek

- `sections.json` — granice rozdziałów i dodatków.
- `chunks.jsonl` — pełna mapa pakietów i stron.
- `worker-input/` — dane wysyłane do modelu.
- `ledger.jsonl` — jedyne źródło prawdy o wynikach i decyzjach.
- `qa/layout-*.json` — strony wymagające obejrzenia.
- `qa/quotes-*.json` — zbiorcza kontrola cytatów.
- `views/.../candidate-register.md` — pełna lista kandydatów.
- `views/.../conflicts.json` — sprzeczne liczby lub daty do rozstrzygnięcia.
- `views/.../editorial-review.md` — deterministyczny widok, który Dawid musi przeczytać przed `AddReview`.
- `views/.../compile-report.json` — bramki gotowości i zużycie zasobów.
- `views/.../staging-preview.md` — wyłącznie izolowany podgląd, bez importu.

## Testy

```powershell
pwsh -NoProfile -File .\tests\Test-K1LiteV2.ps1
```

Szablony danych wejściowych znajdują się w `templates/`.


## Usprawnienia w kopii roboczej 2026-09-14

Opis cache stron, NextWork, ImportBatch i testowego CandidateLimit: [KOPIA-ROBOCZA.md](../../KOPIA-ROBOCZA.md). Produkcyjne bramki jakości pozostają wymagane.

Zalecana obsługa analizy w kopii: [WORK-CYCLE.md](WORK-CYCLE.md). Cykl `Prepare → Accept → Prepare` zachowuje odpowiedzi, uzupełnia metadane lokalnie i zapobiega ponownemu importowi. `Recover` odzyskuje zapisany wynik bez nowego wywołania modelu. `PreviewBatch` oddziela poprawne wyniki od błędnych przed publikacją. Model nadal uruchamia operator; domyślny limit kandydatów wynosi 2.
