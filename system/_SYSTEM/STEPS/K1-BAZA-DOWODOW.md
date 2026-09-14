# K1 — K1-LITE V2 I BAZA DOWODÓW

**Właściciel procesu:** ChatGPT. **Decyzje redakcyjne:** Dawid.
**Silnik:** K1-Lite V2 `2.1.0`.
**Schemat kanoniczny:** `MINIMAL_EVIDENCE_V4_PAGELOC` z `LOCATOR_POLICY: MIXED_V1`.
**Wyjście:** jeden `01-baza-dowodow.md` utworzony semantyką `CreateNew`.

## Cel

Przeczytać cały dostarczony korpus małymi pakietami, zachować każdego wykrytego kandydata i zbudować krótką, sprawdzalną bazę bez ładowania całych książek do głównego kontekstu ChatGPT. K1 potwierdza wierność twierdzenia źródłu. Ocena prawdziwości i niezależności należy do K4.

## Zamknięty przepływ

`PDF → --TEXT.md` albo `natywny MD/TXT/SRT/VTT → plan całego materiału → małe pakiety → analiza workerów → append-only ledger → rekomendacje ChatGPT i decyzje Dawida → kontrola cytatów, lokalizacji, obrazu PDF i konfliktów → BuildViews → przegląd editorial-review.md przez Dawida → AddReview → ponowne BuildViews/ValidateRun → podgląd V4 → jawna publikacja 01 → GateReady`

Nie wolno pominąć żadnej fizycznej strony PDF ani żadnego zakresu samodzielnego tekstu/napisów. Dodatki są treścią, a bibliografia i indeks osobną warstwą referencyjną, lecz także muszą zostać rozliczone.

## 1. Przygotowanie źródła

1. Materiały aktywne PDF/MD/TXT/SRT/VTT leżą bezpośrednio w katalogu głównym `sources/`; obsługiwany plik zagnieżdżony jest błędem, a zaplecze duplikatu może leżeć w `sources/_oryginaly/`.
2. Dla PDF najpierw uruchom `tools/k1-lite/Convert-PdfToMarkdown.ps1 -Action InspectNative`.
3. Gdy warstwa tekstowa jest dobra, generuj podgląd bez OCR. OCR uruchamiaj tylko dla jawnie wskazanych stron.
4. Publikacja tekstu tworzy nowy `<nazwa PDF>--TEXT.md`; nie nadpisuje PDF ani istniejącego MD.
5. Każda strona tekstu ma numer fizyczny, SHA-256 i informację `NATIVE` albo `OCR`.
6. Samodzielne MD/TXT/SRT/VTT nie przechodzą konwersji PDF. Każdy z nich ma własny run; MD/TXT używa globalnych linii, a SRT/VTT natywnych przedziałów czasu.

Konwersja jest przygotowaniem technicznym, nie dowodem i nie selekcją.

## 2. Plan pełnego czytania

`Invoke-K1LiteV2.ps1 -Action Plan` otrzymuje jawny `-ProjectDirectory`, K0 i oczekiwane SHA-256. Dla PDF otrzymuje jednocześnie PDF i jego kanoniczny `--TEXT.md`; dla samodzielnego MD/TXT/SRT/VTT wyłącznie ścieżkę źródła, bez argumentu PDF. Run musi leżeć pod:

`<projekt>/_work/K1/k1-lite-v2/<run-id>/`

Plan tworzy:

- `run.json` — tożsamość runu i hashe;
- `sections.json` — rozdziały, dodatki i warstwa referencyjna;
- `chunks.jsonl` — pełna mapa jednostek materiału bez luk i nakładania;
- `worker-input/` — pakiety około 12–18 tys. znaków z krótkim, hashowanym briefem K0.

## 3. Analiza workerów

- Każdy worker czyta cały przypisany pakiet.
- Domyślnie jedna odpowiedź zawiera najwyżej dwóch kandydatów. W kopii testowej można utworzyć nowy run przez `Plan -CandidateLimit 4` albo `8`; worker stosuje wtedy limit zapisany w planie i pakiecie. Większy limit pozostaje eksperymentem jakościowym. Nie zmieniaj limitu istniejącego runu.
- W kopii roboczej preferuj `Invoke-K1WorkCycle.ps1`: `Prepare` przygotowuje następny fragment lub kontynuację, `Accept` zapisuje odpowiedź przed walidacją, `Recover` ponawia lokalny import, a `Status` pokazuje postęp. Szczegóły: [WORK-CYCLE.md](../../tools/k1-lite-v2/WORK-CYCLE.md). Powtórne `Prepare` nie jest zgodą na kolejne wywołanie modelu. Po błędzie najpierw wykorzystaj zachowaną odpowiedź; poprawiaj tylko wskazane błędy, jeżeli kontekst jest wystarczający. Zakończenie analizy nie zastępuje kontroli cytatów i przeglądu dowodów.
- `NextWork` pozostaje dostępnym odczytem kolejki: wskazuje niewykonany fragment, numer kontynuacji i wcześniejszych kandydatów. `NEXT_WORK_LEDGER_CHANGED` oznacza konieczność ponowienia odczytu. Polecenie nie zastępuje pełnego czytania pakietu ani przeglądu dowodów.
- Zebrane wyniki można wczytać przez `ImportBatch -ResultPaths` z aktualnym hashem dziennika. Zachowaj kolejność kontynuacji; błędna partia nie jest publikowana.
- Dalsze mocne kandydatury wymagają `PARTIAL_OVERFLOW` i kolejnej odpowiedzi.
- Brak kandydatury jest zapisywany jako `SCANNED_NO_CANDIDATE`, a nie pomijany.
- Wynik musi przejść lokalną kontrolę lokalizatora strony/linii/czasu, dokładnego cytatu, liczb, markerów i telemetryki.
- Wszystkie kandydatury, odrzucenia, kontynuacje i receipts pozostają w `ledger.jsonl`; widoki Markdown nie są źródłem prawdy.

## 4. Rekomendacje i decyzje

ChatGPT może nadać rekomendację `KEY_CHATGPT`. Dawid może niezależnie nadać:

- `MUST_INCLUDE` — koniecznie w bazie;
- `IMPORTANT_SIDE` — ważny wątek poboczny;
- `REJECTED` — nie wchodzi do bazy.

Kanał rekomendacji ChatGPT i kanał decyzji Dawida są przechowywane osobno. Decyzja Dawida ma pierwszeństwo; `REJECTED` blokuje automatyczne wejście nawet przy `KEY_CHATGPT`. Nowe decyzje są dopisywane do ledgera z oczekiwanym SHA poprzedniej wersji. Historia nie jest edytowana.

Potwierdzenie konfliktu jest osobną decyzją i może je zapisać wyłącznie Dawid. ChatGPT nie może wystawić `conflict_acknowledge`; wybrany kandydat objęty konfliktem wymaga zarówno decyzji Dawida, jak i jego jawnego potwierdzenia konfliktu.

## 5. Przegląd redakcyjny Dawida

1. `BuildViews` tworzy deterministyczny `editorial-review.md` z najmocniejszymi, ryzykownymi i kontrowersyjnymi kandydaturami, `KEY_CHATGPT`, wybranymi konfliktami, pokryciem K0, klasami źródeł oraz `STOP_REASON`.
2. Dawid czyta ten konkretny artefakt. Przegląd nie zmusza go do nadania decyzji każdemu słabemu kandydatowi i nie jest dorozumianą zgodą na wszystkie rekordy.
3. Po przeczytaniu powstaje JSON `K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1` z `run_id`, `snapshot_sha256`, kanoniczną względną ścieżką `review_artifact_relative`, `review_artifact_sha256`, `actor: DAWID`, `verdict: REVIEWED` i konkretną notatką.
4. `AddReview` weryfikuje run, aktualny SHA ledgera, snapshot, ścieżkę i hash artefaktu, po czym dopisuje zdarzenie `editorial_review_receipt` do ledgera.
5. Po `AddReview` trzeba utworzyć nowe widoki i uruchomić świeży `ValidateRun`. Zmiana kandydatów, rekomendacji, decyzji lub konfliktów unieważnia receipt i wymaga nowego przeglądu; sama zmiana kontroli obrazu go nie unieważnia.

## 6. Kontrole przed kompilacją

Przed podglądem kanonicznej bazy wszystkie bramki raportu muszą mieć `true`:

- `coverage_ready` — każdy pakiet zakończony;
- `quotes_ready` — każdy aktywny cytat ponownie odnaleziony w zadeklarowanej lokalizacji;
- `decisions_current` — brak decyzji związanych ze starą wersją cytatu;
- `selected_visual_ready` — każda wybrana karta PDF ma aktualny receipt obrazu strony i kadru; dla samodzielnego MD/TXT/SRT/VTT bramka ma stan `NOT_APPLICABLE` i nie wolno dodawać fikcyjnego obrazu;
- `selected_conflicts_acknowledged` — sprzeczne liczby lub daty wybranych kandydatów mają decyzję i jawne potwierdzenie Dawida;
- `editorial_review_ready` — najnowszy deterministyczny `editorial-review.md` ma aktualny, związany SHA receipt `K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1` z `actor: DAWID`.

`InspectLayout` tworzy kolejkę stron ryzykownych: kolumny, tabele, obrót, nietypowy tekst, gęste wektory albo mało tekstu native. Flaga nie odrzuca strony automatycznie. Każde `BuildViews` ponownie liczy SHA artefaktów wskazanych przez aktywne visual receipts; brakujący albo zmieniony plik blokuje `selected_visual_ready`.

## 7. Kompilacja V4

Każde aktywne źródło musi mieć ukończony run. Dla jednego źródła użyj `Compile-K1LiteV2.ps1 -Action Preview`. Gdy `sources/` zawiera więcej niż jeden logiczny materiał, pojedynczy kompilator celowo zwraca `CORPUS_REQUIRES_MULTI_RUN_COMPILER`; wtedy użyj `Compile-K1LiteV2Corpus.ps1` z listą wszystkich runów i ich hashy.

Kompilator korpusu:

1. sprawdza, że każdy aktywny plik jest reprezentowany przez ukończony run jako tekst albo backing PDF;
2. ponownie uruchamia sześć bramek każdego runu, w tym `editorial_review_ready`;
3. zachowuje osobne ścieżki nawet dla plików o identycznej treści;
4. łączy ledgery, deduplikuje karty i nadaje ciągłe globalne ID;
5. promuje analizowane źródła do `RDZEŃ` i odmawia publikacji przy jakimkolwiek nieprzeczytanym pliku.

`tools/Compile-K1LiteV2.ps1 -Action Preview` dla pojedynczego runu:

1. ponownie sprawdza SHA ledgera;
2. waliduje run i buduje świeże widoki;
3. wymaga kompletu sześciu bramek i aktualnego receiptu Dawida;
4. wybiera tylko `MUST_INCLUDE`, `IMPORTANT_SIDE` albo nieodrzucone `KEY_CHATGPT`;
5. tworzy nowy `K1-COMPILED-<run-id>.md` w katalogu runu;
6. generuje rejestr wszystkich plików `sources/` i karty z lokalizatorem `Pxxxx/Lx-Ly`, `Lx-Ly` albo `[czas-czas]`, zależnie od rodzaju źródła;
7. uruchamia `Validate-EvidenceBase.ps1 -PendingReview`.

Podgląd nie jest bazą kanoniczną.

`Compile-K1LiteV2.ps1 -Action Publish` wymaga dokładnej ścieżki podglądu i oczekiwanego SHA-256. Dla korpusu przyjmuje `RunDirectory` i połączony hash zwrócone przez kompilator korpusu. W zwykłym przebiegu tworzy nowy `01-baza-dowodow.md`; istniejący canonical akceptuje wyłącznie jako identyczny stan przerwanej lub ukończonej tej samej publikacji. Tworzy w katalogu publikującego runu `publish-receipt.json` w schemacie `K1_LITE_V2_PUBLISH_RECEIPT_V1`, aktualizuje pola runu i `K1_PUBLISH_RECEIPT_PATH/SHA256` w `meta.md`, uruchamia ścisłą walidację i wycofuje własny zapis przy błędzie. Identyczne ponowienie odzyskuje lub dokańcza ten sam stan i zwraca `PUBLISHED_RECOVERED_OR_REUSED`; różne wejście nadal jest odrzucane.

Receipt `K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1` w ledgerze potwierdza przeczytanie konkretnego widoku przez Dawida. Publish receipt wiąże kanoniczną bazę z podglądem, ledgerem i kompletną linią runów. Są to dwa różne wymagania i żadne nie zastępuje drugiego.

## Tryb awaryjny `MANUAL_APPROVED`

Sam wpis w `meta.md` nie zezwala na fallback. Po ustawieniu zgodnego `K1_RESEARCH_MODE` i `K1_MANUAL_REASON` uruchom `Approve-K1ManualFallback.ps1 -DawidApproved` z tym samym konkretnym powodem. Receipt `SYSTEM_V7_K1_MANUAL_FALLBACK_RECEIPT_V1` wiąże origin projektu, K0 i aktywny korpus. Zmiana któregokolwiek elementu unieważnia zgodę. Receipt jest audytowalnym potwierdzeniem decyzji, nie kryptograficznym uwierzytelnieniem Dawida. Ręczna baza nadal musi przejść pełny V4 i nie otrzymuje automatycznego publish receiptu.

## 8. Bramka K1

K1 przechodzi wyłącznie, gdy:

- `01-baza-dowodow.md` istnieje i ma `MINIMAL_EVIDENCE_V4_PAGELOC`;
- wszystkie pliki `sources/` są rozliczone w rejestrze;
- wszystkie karty mają istniejące `#S`, dokładny lokalizator zgodny z `MIXED_V1` i `QA_K1: GOTOWA`;
- `ManualCheckCards: 0`;
- `STRUCTURE_CHECK`, `SOURCE_FIDELITY_CHECK` i `SATURATION_CHECK` mają `PASS`;
- `K1_VERDICT: GOTOWE_DO_K2`;
- `meta.md` wskazuje istniejący run i prawdziwy SHA `ledger.jsonl`;
- w `K1_LITE_V2` `meta.md` wskazuje aktualny publish receipt odpowiadający bazie, publikującemu runowi i całej linii źródłowej; w `MANUAL_APPROVED` pola runu/publish mają `BRAK`, a aktualny jest receipt fallbacku;
- świeży `ValidateRun` wskazanego runu potwierdza wszystkie sześć bramek, w tym `editorial_review_ready`;
- ledger zawiera aktualny receipt Dawida związany SHA z najnowszym `editorial-review.md`, a konflikty wybranych kandydatów potwierdził wyłącznie Dawid.

## Zakazy

- Nie używaj podglądu ani ledgera jako wejścia K2/K3.
- Nie nadpisuj istniejącego `01-baza-dowodow.md`.
- Nie pomijaj pakietów bez kandydatów.
- Nie usuwaj odrzuconych kandydatur z ledgera.
- Nie wystawiaj receiptu przeglądu ani potwierdzenia konfliktu w imieniu Dawida.
- Nie uznawaj cytatu zgodnego ze źródłem za fakt potwierdzony.
- Nie uruchamiaj OCR dla całej książki, jeżeli potrzebują go tylko pojedyncze strony.
- Nie przekazuj workerom całego K0 ani całej książki, gdy wystarcza brief i jeden pakiet.

Po PASS uruchom `Advance-Stage.ps1` jako podgląd, a następnie z `-Apply`. Narzędzie przechodzi do K2 i zapisuje `LAST_GATE: K1_PASS`.
