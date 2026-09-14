# RESEARCH, DOWODY I ETYKA

**Wspiera:** W0, K0, K1, K2B, K4.

## Research jako test filmu

Research nie służy zgromadzeniu wszystkiego. Służy znalezieniu materiału, który odpowiada na pytania filmu, buduje historię, ujawnia konflikt, daje scenę lub wyznacza granicę tego, co wolno powiedzieć.

Dlatego kolejność ma znaczenie:

1. K0 określa temat analizy oraz 4–8 pytań potrzebnych do decyzji.
2. K1 tworzy dokładny tekst stron PDF albo czyta natywny MD/TXT/SRT/VTT, planuje 100% materiału i analizuje rozłączne paczki.
3. Każdy wynik trafia do append-only ledgera, także wynik bez kandydata.
4. ChatGPT zapisuje `KEY_CHATGPT`, a Dawid osobno `MUST_INCLUDE`, `IMPORTANT_SIDE` lub `REJECTED`.
5. Deterministyczny `editorial-review.md`, związany SHA receipt Dawida, sześć bramek — w tym `editorial_review_ready` — i dwuetapowy kompilator chronią kanoniczną bazę przed niepełnym albo nieaktualnym wynikiem.
6. K2 ujawnia ewentualne precyzyjne luki.
7. K2B sprawdza tylko te luki i dopisuje materiał addytywnie.
8. K4 dopiero po drafcie ocenia prawdziwość i sposób użycia twierdzenia w finalnej narracji.

## Kompresja nie jest cenzurą

Rozliczenie źródła nie oznacza obowiązku utworzenia z niego karty. Źródło może być rezerwą, duplikatem, materiałem technicznym albo znajdować się poza zakresem. Powód musi być jawny. Tylko PDF i jego kanoniczny `<nazwa>--TEXT.md` są automatycznie jednym logicznym materiałem; inne aktywne MD/TXT/SRT/VTT wymagają własnych runów i nie stają się niezależnym potwierdzeniem wyłącznie przez zmianę formatu.

Selekcja K1 odpowiada na pytanie „czy to może zmienić architekturę lub narrację?”. Nie odpowiada jeszcze na pytanie „czy to jest prawdziwe?”. Materiał C/D, teoria, legenda i relacja nadal mogą być rdzeniem historii, jeśli karta wiernie pokazuje treść i miejsce w źródle, a rejestr źródeł zachowuje autora i klasę.

Rozdzielenie rekomendacji ChatGPT od decyzji Dawida zachowuje kontrolę autora, ale nie zmusza go do ręcznego oceniania każdego słabego kandydata. Model wskazuje własne kluczowe rekordy, a Dawid może je zatwierdzić, zdegradować lub jawnie odrzucić.

Przed kompilacją Dawid czyta jeden deterministyczny `editorial-review.md` skupiający najmocniejsze, ryzykowne i kontrowersyjne kandydatury, `KEY_CHATGPT` oraz wybrane konflikty. Receipt `K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1` potwierdza wyłącznie przegląd konkretnego hashowanego widoku, nie akceptację każdego rekordu. Tylko Dawid może potwierdzić konflikt.

## Karta jako ograniczona jednostka

Karta nie jest formularzem do przepisywania metadanych źródła. W `MINIMAL_EVIDENCE_V4_PAGELOC` ma dokładnie cztery pola: `TREŚĆ`, `ŹRÓDŁO_ID`, `LOKALIZACJA`, `QA_K1`. Pozwala szybko odpowiedzieć:

- co dosłownie mówi materiał;
- które logiczne źródło to zawiera;
- gdzie dokładnie można to odtworzyć;
- czy karta przeszła kontrolę K1.

Autor, data i klasa A–D żyją w rejestrze źródeł. Rekomendacja i decyzja redakcyjna żyją w ledgerze. W Narrative V2 przypisanie `REQUIRED`/`SUPPORTING`/`RESERVE` do aktu powstaje dopiero w K2; żadnego z tych pól nie dopisuje się do karty. Nazwy `PRIMARY`/`RESERVE` dotyczą wyłącznie starszych kontraktów legacy.

Jedna karta może obejmować kilka bliskich szczegółów z jednego ciągłego fragmentu. Nie rozbijaj każdego zdania na osobną kartę, jeśli nie zmienia się źródło ani lokalizacja.

## Evidence trail

Twórca musi potrafić odtworzyć drogę:

`zdanie filmu → karta #P → lokalizacja → logiczne źródło #S → oryginalny plik/URL`

W K1–K3 ta droga potwierdza wierność materiałowi. W K4 służy także ocenie prawdziwości.

## K1-COMPILED nie jest bazą finalną

K1-Lite V2 zachowuje run w `_work/K1/k1-lite-v2/`. `Compile-K1LiteV2.ps1 -Action Preview` buduje sprawdzalny podgląd V4. `-Action Publish` wymaga hashy ledgera i podglądu, tworzy pierwsze `01` przez `CreateNew` i uruchamia ścisłą walidację.

Karta bez lokalizatora zgodnego z `MIXED_V1` pozostawia `ManualCheckCards > 0` i blokuje K1. Dla PDF wymagany jest kanoniczny tekst strony i `Pxxxx/Lx-Ly`; dla MD/TXT globalne `Lx-Ly`; dla SRT/VTT odtwarzalny `[czas-czas]`. Odpowiedzią na brak tekstu PDF jest konwersja lub OCR konkretnej strony, nie ręczne obejście bramki.

## Dwie różne kontrole

W K1 kontrola wierności jest mechaniczna: karta zawiera dosłowny fragment, więc walidator rozstrzyga, czy tekst rzeczywiście występuje we wskazanym miejscu. Osobny kontekst `VERIFY` nie występuje w K1 i nie może zastąpić `ManualCheckCards: 0`.

Świeży kontekst `VERIFY` pojawia się dopiero w K4. Wtedy porównuje kompletny draft ze źródłami i ocenia prawdziwość, atrybucję, zakres pewności oraz finalny sposób użycia twierdzenia.

## Warunek nasycenia

Research nie kończy się na liczbie kart. Kończy się, gdy 100% jednostek materiału i paczek ma jawny wynik, wszystkie sześć bramek jest spełnionych, receipt Dawida jest aktualny, cele K0 są pokryte albo mają jawną lukę, a rdzeń wystarcza do realnych kierunków K2. Powód zatrzymania zapisuje się w `STOP_REASON`.

## Sprzeczności i świadkowie

Gdy dwa źródła podają różne wersje, zachowaj osobne karty i opisz konflikt w sekcji sprzeczności bazy. Nie dopisuj do minimalnej karty pola `SPRZECZNE_Z` i nie syntetyzuj sztucznego kompromisu. Znaczenie sporu dla filmu ocenia K2, a status faktograficzny K4.

Wiarygodność świadka zależy od dostępu do wydarzenia, czasu, interesu, stabilności wersji i rozdzielenia obserwacji od interpretacji. K1 zapisuje relację w zakresie potrzebnym filmowi; pełny kontekst musi pozostać odtwarzalny.

## Fallback i K2B

`Build-SourceManifest.ps1` oraz `Search-Sources.ps1` pozostają fallbackiem, nie równoległym domyślnym pipeline'em. Użycie wymaga `K1_RESEARCH_MODE: MANUAL_APPROVED` oraz `K1_MANUAL_REASON: DAWID=TAK; POWÓD=<min. 15 znaków>`; nie wolno przełączyć procesu po cichu tylko dla wygody.

K2B wraca do K1-Lite V2 z jednym precyzyjnym pytaniem. `Merge-K1LiteV2Supplement.ps1` deduplikuje, kontynuuje ID, wymaga hashy ledgera, podglądu i bieżącej bazy oraz zachowuje kopię odzyskiwania. Nie otwiera drugiego pełnego researchu.

## Etyka i aktualność

Przed zatwierdzeniem finalnej narracji rozważ nierównowagę sił, możliwość szkody, prywatność, zgodę, kontekst, prawo do odpowiedzi i interes publiczny.

Informacja zmienna wymaga daty dostępu i ponownej kontroli w K4. Przy zdrowiu, prawie, finansach, żyjących osobach i bieżących konfliktach preferuj aktualne źródła pierwotne i oficjalne dokumenty.
