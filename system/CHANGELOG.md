# CHANGELOG

## Konsolidacja do jednej wersji — 2026-09-12

Od 2026-09-12, na polecenie Dawida, jedyną wersją wybieraną dla nowych projektów jest `2026-08-31_NARRATIVE_V2`. `New-Project.ps1` wybiera ją domyślnie. Status jakości pozostaje `PILOT_ONLY`: uporządkowanie i wybór wersji nie są wynikiem testu A/B ani zatwierdzeniem profilu głosu. Istniejące projekty zachowują swój origin, rewizję, tekst i receipty; nie są automatycznie migrowane. Kod zgodności służy zachowaniu dostępu do tych projektów, nie stanowi drugiej instalacji systemu.

- Jedna instalacja `Produkcja tekstów/System-v7.0` i jedna Biblia `BIBLIA/`.
- Stare osobne kopie i Biblia wycofane po sprawdzeniu zależności oraz backupu SHA-256.
- `k1-lite` zachowany jako potrzebna warstwa PDF/OCR; to część K1-Lite V2.
- Szablony zgodności przeniesione pod `tools/compatibility/`; testy starszych projektów wybierają fixture jawnie.
- Wyniki projektów i testów historycznych oraz recovery Źródłownika pozostają zachowane.
- Wyniki bieżącej weryfikacji znajdują się w `_work/porzadkowanie-systemu-20260912` w korzeniu workspace.

Dalsze wpisy są historią rozwoju, nie instrukcjami wyboru wersji.


## v7.0 — Narrative V2, pilot najwyższej jakości — 2026-08-31

Nowa, równoległa rewizja `2026-08-31_NARRATIVE_V2` jest wdrożona technicznie jako `PILOT_ONLY`. Nie migruje projektów `2026-08-30_K1_LITE_V2` i nie staje się domyślna bez ślepego testu A/B oraz jawnej decyzji Dawida.

- Story Engine V2 zastępuje plan oparty na długości: Story DNA, kontrakt hooka i finału, NQ/NR/VC, Scene Weave, completion criteria i maksymalnie siedem atomowych twardych obowiązków na akt. Nie ma budżetów słów, znaków, dolnych progów ani liczbowych norm humoru i kontaktu z widzem.
- Claude pisze jeden akt w świeżym kontekście z małego packetu, pełnych legalnych kart bieżącego aktu, zatwierdzonego profilu głosu i stabilnego prefixu. Model, ustawienia, prefix, źródła i zależności są zamrożone oraz fail-closed inwalidowane.
- Akty `COMPLEX` mają beat sheet i osobny preflight. Każdy akt wymaga constraint preflight, strukturalnego outputu, propozycji `CONTINUITY_OUT` i niezależnego blind attest przed uruchomieniem następnego aktu. Draft jest montowany deterministycznie.
- K4 rozdziela trzy świeże konteksty: `EDITOR_V2` z semantic preflight, `VERIFY_SOURCE_FIRST_V1` z prawdziwymi źródłami oraz `COLD_READER_BLIND_V1` z samą narracją. Proof set, raporty, poprawki, impact review i carry-forward są związane hashami oraz receiptami.
- K5 akceptuje byte-identical czystą narrację. `COMPLETE/K5_PASS` osiąga wyłącznie oficjalne `Advance-Stage.ps1 -Apply` po ważnym receipcie Dawida; walidator nie akceptuje ręcznie ustawionego stanu.
- 58 kluczowych instrukcji, schematów i szablonów jest chronionych kodowym allowlistem oraz `_SYSTEM/NARRATIVE/NARRATIVE-INSTRUCTION-MANIFEST.json`. Manifest odtwarza wyłącznie jawne narzędzie maintenance, a regresja testuje tamper i dokładne przywrócenie bajtów.
- Zdefiniowano trzybenchmarkowy, ślepy protokół A/B. Jego stan pozostaje `NOT_RUN_REQUIRES_DAWID`; profil głosu pozostaje kandydatem bez zmyślonych exemplarów, a real-model test Verify pozostaje `NOT_RUN` bez prawdziwego outputu i receiptu.
- Gałąź legacy zachowuje stare narzędzia oraz reguły wyłącznie dla zgodności. Mieszanie `_work/k3-pakiety`, starych receiptów K4/K5 lub limitów aktu z Narrative V2 jest blokowane.
- Dodano osobną regresję Narrative V2 obejmującą dispatch rewizji, voice profile, duration policy, atomicity, semantic preflight, zależności, reopen, powtórzenia ruchów, K3 SIMPLE/COMPLEX, continuity, exact K4, carry-forward, K5 i oficjalny łańcuch W0→COMPLETE. Końcowe wyniki są wpisywane do `AUDYT-KOMPLETNOSCI.md`; ten changelog nie zastępuje raportu testów.

## v7.0 — integralność stanu i receipty — 2026-08-31

- Nowe projekty otrzymują `.system-v7/project-origin.json` związany z identyfikatorem, nazwą i bezwzględną ścieżką. Wspierane projekty historyczne wymagają jednorazowego `Register-LegacyProject.ps1 -DawidApproved` i osobnego `.system-v7/legacy-origin.json`; rejestracja umożliwia tylko walidację archiwalną. Start/Advance/Block/Unblock odmawiają `LEGACY_PROJECT_IS_VALIDATION_ONLY`, a wznowienie pracy wymaga jawnej migracji do nowego bieżącego projektu.
- Wszystkie wspierane mutatory współdzielą `.system-v7/meta-write.lock`. Zapis `meta.md` ma trwały journal, atomowy `File.Replace`, zachowanie wersji wypartej i fail-closed recovery. Advance utrzymuje lock przez walidację, pełny rekurencyjny manifest SHA-256 i fizyczną barierę odczytu oraz wykonuje kontrolę bezpośrednio przed i po CAS.
- `CURRENT_STAGE`, `STAGE_OWNER`, `LAST_GATE` i pola blokady zmieniają wyłącznie `Advance-Stage.ps1`, `Block-Project.ps1` i `Unblock-Project.ps1`. Block/Unblock używają deterministycznego `intent_sha256`, bezpiecznie odzyskują identyczny orphan receipt po przerwaniu i tworzą trwały łańcuch wskazywany przez `LAST_STATE_RECEIPT_PATH/SHA256`; walidacja pozostaje aktywna po Unblock i kolejnych Advance.
- W0 pozostawia `LAST_GATE: PROJECT_INITIALIZED` do chwili Advance. `GO WARUNKOWE` może wejść do K0 jako `OPEN`, ale K0 → K1 wymaga `Close-W0Condition.ps1` i receiptu `SYSTEM_V7_W0_CONDITION_CLOSURE_V1`. `NO-GO` przechodzi przez `Block-Project.ps1 -NoGo`.
- Zastępstwo właściciela wymaga `Approve-OwnerOverride.ps1` i `SYSTEM_V7_OWNER_OVERRIDE_RECEIPT_V1`; sam tekst `OWNER_OVERRIDE` nie wystarcza.
- Jeden kierunek K2, wyjątek budżetu K3, akceptacja Q1 albo Q2 K4 i decyzja wobec sprzecznego fact-checku wymagają `Approve-EditorialException.ps1` oraz `SYSTEM_V7_EDITORIAL_EXCEPTION_RECEIPT_V1` związanego z originem i SHA artefaktu; sam tekst lub status w tabeli nie wystarcza.
- Manual fallback wymaga `Approve-K1ManualFallback.ps1` i `SYSTEM_V7_K1_MANUAL_FALLBACK_RECEIPT_V1` związanego z originem, K0, aktywnym korpusem i powodem.
- Rozdzielono dwa receipty K1: editorial receipt potwierdza przeczytanie widoku Dawida, natomiast `K1_LITE_V2_PUBLISH_RECEIPT_V1` wiąże kanoniczną bazę z podglądem, ledgerem i pełną linią runów.
- Identyczne ponowienie przerwanego Publish jest odzyskiwalne i idempotentne: kompilator zwraca `PUBLISHED_RECOVERED_OR_REUSED`, a suplement przy zgodnym canonical/backup/meta `SUPPLEMENT_PUBLISHED_RECOVERED_OR_REUSED`; inne wejścia nadal nie mogą nadpisywać bazy.
- Suplement K2B tworzy kolejny publish receipt wskazujący poprzedni receipt, poprzedni hash bazy i kopię odzyskiwania. Dopiero potem aktualizuje się architekturę, paczki i stan.
- K4 wymaga `SYSTEM_V7_K4_VERIFY_RECEIPT_V1` z exact, case-sensitive tożsamością agenta/zadania z `04B`; K5 wiąże także SHA całego receiptu K4. Oba formaty mają zamknięte payloady związane łącznie z notatką i czasem oraz kanoniczne bajty UTF-8 bez BOM.
- Receipty z `actor: DAWID` i przełączniki `-DawidApproved` są audytowalnymi potwierdzeniami przekazanych decyzji, nie kryptograficznym uwierzytelnieniem tożsamości.
- Finalne wyniki pełnej regresji tej zmiany zostaną wpisane po zakończeniu testów; ten wpis nie ogłasza PASS.

## v7.0 — pełne wdrożenie K1-Lite V2 — 2026-08-30

Nowa rewizja workflow: `2026-08-30_K1_LITE_V2`. Silnik `2.1.0` zachowuje schemat kart `MINIMAL_EVIDENCE_V4_PAGELOC` i dodaje `LOCATOR_POLICY: MIXED_V1`: cytaty są wiązane z fizyczną stroną PDF, globalnymi liniami MD/TXT albo przedziałem czasu SRT/VTT.

Zmiany:

- **PDF ma kanoniczny tekst stron; tekst natywny nie jest sztucznie konwertowany.** Lokalna konwersja PDF zachowuje oryginał, fizyczne markery stron i hashe; Tesseract działa tylko na stronach bez wystarczającego tekstu natywnego. Samodzielne MD/TXT/SRT/VTT otrzymują własne runy.
- **Plan obejmuje 100% jednostek materiału.** Paczki są rozłączne, workery działają maksymalnie po dwa, a overflow jest jawny.
- **Append-only ledger jest źródłem audytu.** Zachowuje kandydatów, wyniki bez kandydatów, decyzje, unieważnienia, metryki i kontrolę obrazu.
- **Rekomendacja i decyzja są rozdzielone.** `KEY_CHATGPT` należy do ChatGPT; `MUST_INCLUDE`, `IMPORTANT_SIDE` i `REJECTED` należą do Dawida. Jawne `REJECTED` ma pierwszeństwo.
- **Sześć bramek jest obowiązkowych.** Kompilacja wymaga pełnego pokrycia, odtwarzalnych cytatów, aktualnych decyzji, kontroli obrazu, rozstrzygniętych konfliktów i aktualnego `editorial_review_ready`. Obraz jest wymagany dla PDF i `NOT_APPLICABLE` dla samodzielnego tekstu.
- **Pierwsza publikacja jest dwuetapowa.** `Compile-K1LiteV2.ps1` obsługuje `Preview` i `Publish`; zgodne hashe oraz `CreateNew` chronią istniejący plik, a publish receipt zachowuje jego linię pochodzenia.
- **K2B ma fizyczny mechanizm scalania.** `Merge-K1LiteV2Supplement.ps1` deduplikuje, kontynuuje ID, wymaga trzech hashy, zachowuje kopię odzyskiwania i ponownie wymaga `GATE_READY`.
- **Schemat V4 używa mieszanych, jednoznacznych lokalizatorów.** `Pxxxx/Lx-Ly` wskazuje PDF, `Lx-Ly` samodzielny MD/TXT, a `[czas-czas]` SRT/VTT.
- **Fallback jest jawny.** `Build-SourceManifest.ps1` i `Search-Sources.ps1` pozostają ścieżką awaryjną lub zgodnościową; w bieżącej rewizji wymagają zgodnych pól meta i aktualnego receiptu manual fallback. System nie przełącza się na fallback po cichu.
- **VERIFY pozostaje wyłącznie w K4.** Kontrola K1 jest mechaniczna; osobny kontekst nie może zastąpić precyzyjnego lokalizatora ani wyniku `ManualCheckCards: 0`.
- Zaktualizowano Konstytucję, pipeline, mandaty, kroki K0/K1/K2B, automatyzacje, szablony projektu, walidatory, mapy, Canvas, Biblię researchu, README i audyt kompletności. Starsze projekty i historyczne wpisy changelogu pozostają bez migracji.

## v7.0 — karta minimalna — 2026-08-22

Diagnoza: koszt K1 nie leżał w liczbie kart, tylko w tym, że każda karta wymagała decyzji. Rekord miał dziewięć pól obowiązkowych, z czego `WAGA`, `STATUS_W_ŹRÓDLE` i `UŻYCIE_K2` wymagały osądu redakcyjnego przy każdym fragmencie, a `FORMA: PARAFRAZA` wymuszała osobny, ludzki przebieg kontrolny — bo maszyna nie rozstrzygnie, czy parafraza zachowała sens.

Sprawdzenie, kto te pola faktycznie czyta, dało jednoznaczny wynik: **żadne narzędzie w dół pipeline'u ich nie używa**. `Validate-Architecture.ps1` czyta z karty wyłącznie ID i `QA_K1`; przypisanie `PRIMARY`/`RESERVE` do aktów bierze z własnej tabeli architektury, nie z `WAGA`. `Build-K3Packets.ps1` kopiuje blok karty dosłownie i również do pól nie zagląda. Sześć pól obowiązkowych istniało wyłącznie po to, żeby walidator mógł sprawdzić ich obecność.

Zmiany:

- Nowy schemat `MINIMAL_EVIDENCE_V3` i rewizja workflow `2026-08-22_MINIMAL_EVIDENCE`. Projekty w `COMPACT_EVIDENCE_V1` i `V2` pozostają obsługiwane bez zmian i nie są migrowane.
- **Karta ma cztery pola:** `TREŚĆ`, `ŹRÓDŁO_ID`, `LOKALIZACJA`, `QA_K1`. Usunięte: `WAGA`, `STATUS_W_ŹRÓDLE`, `FORMA`, `ATRYBUCJA`, `UŻYCIE_K2`, `CYTAT_DOSŁOWNY`, `OGRANICZENIE`, `FLAGI_K4`, `SPRZECZNE_Z`. Walidator ostrzega o każdym polu spoza schematu.
- **`TREŚĆ` jest dosłownym fragmentem źródła.** K1 nie parafrazuje. Dzięki temu `TREŚĆ` sama pełni rolę cytatu w kontroli maszynowej i osobne pole `CYTAT_DOSŁOWNY` przestało być potrzebne.
- **Kontrola K1 jest w całości maszynowa.** Zniknął ludzki przebieg kontrolny i wymóg rozdzielenia `LEAD_AGENT_ID` od `VERIFY_AGENT_ID` w K1 — kontrola semantyczna istniała po to, żeby oceniać parafrazę, a karta bez parafrazy nie ma czego oceniać. Tryb `VERIFY` pozostaje wyłącznie w K4.
- **Bramka wierności jest twardsza.** `SOURCE_FIDELITY_CHECK: PASS` jest teraz błędem, dopóki walidator nie zwróci `ManualCheckCards: 0`. Karta bez potwierdzenia maszynowego blokuje etap i nie ma ścieżki „sprawdzone ręcznie”.
- **Karta bez statusu treści.** Ocena, czy materiał jest faktem, relacją, legendą czy spekulacją, powstaje w K3 i K4 na kompletnym drafcie. Powód jest konkretny: przy kanale o tematach z pogranicza etykieta nadawana przed napisaniem sceny kosztowała pracę i niczego nie zabezpieczała.
- **Atrybucja przeniesiona do rejestru źródeł.** Autor należy do pliku, nie do każdego fragmentu z osobna.
- Zaktualizowano Konstytucję (§3, §5, §6, §7, §8, §11), krok K1, mandat ChatGPT, macierz ról, automatyzacje, K2B, szablony `01-baza-dowodow.md`, `meta.md`, `03-draft.md` oraz `README.md` i `tools/README.md`.
- **Paczka K3 niesie atrybucję.** Karta minimalna ma sam `ŹRÓDŁO_ID`, więc autor
  narracji dostawał kod `#S-001` bez informacji, czyje to źródło — i nie mógł podać
  atrybucji, nie zmyślając jej. `Build-K3Packets.ps1` dokłada teraz sekcję
  `## Źródła tych kart` z wierszami rejestru wyłącznie dla źródeł użytych w paczce.
- **Paczka odchudzona pod autora.** Z kart w paczce znikają `QA_K1` (w paczce zawsze
  `GOTOWA`) i `LOKALIZACJA` (służy kontroli K4, która pracuje na bazie). W bazie oba
  pola zostają — paczka jest artefaktem dla piszącego, baza dla walidatora.
- **Ciągłe fragmenty.** Karty z tego samego źródła i sąsiadujących linii są w paczce
  wskazane jako jeden ciągły fragment. Bez tego autor dostaje wyliczankę faktów tam,
  gdzie w źródle jest jedna scena.
- `Test-System.ps1` przepisany na V3: fixture kart z dosłowną treścią, test zmyślonego konkretu, test lokalizacji rozjechanej z treścią, test bramki `ManualCheckCards` i test ostrzeżenia o polu spoza schematu.

Efekt uboczny wart odnotowania: rekord karty schudł z trzynastu linii do pięciu, więc w tym samym budżecie kontekstu paczka K3 mieści około trzy razy więcej materiału dla autora narracji.

## v7.0 — selection-first K1 — 2026-08-19

Diagnoza: wadliwa nie była warstwa kart, architektury ani paczek dla autora, lecz wszystko, co je poprzedzało. Dokumentacja nakazywała czytać selektywnie, ale system nie dawał narzędzia do selektywnego wyszukiwania. W efekcie agent budował własną, ciężką infrastrukturę: konwersje wszystkich plików, lustra Markdown w vaulcie, globalny indeks treści i wielokrotne kopie tego samego materiału. Etap K1 potrafił trwać kilka godzin i wytworzyć setki plików pochodnych, z których korzystano w znikomym stopniu.

Zmiany:

- Nowy schemat bazy `COMPACT_EVIDENCE_V2` i rewizja workflow `2026-08-19_SELECTION_FIRST_K1`. Projekty w `COMPACT_EVIDENCE_V1` pozostają obsługiwane bez zmian.
- **Postać źródeł:** jedno logiczne źródło to jeden kanoniczny plik `.md` w `sources/`. Zaplecze techniczne (PDF, VTT, SRT, JSON, skany) leży w `sources/_oryginaly/` i jest rozliczane jednym wierszem roli `TECHNICZNE`. System niczego nie konwertuje.
- **Nowe narzędzie `Search-Sources.ps1`:** celowane wyszukiwanie fragmentów według celów K0, z zakresem linii, timestampem i trafionymi hasłami. Tryb `-QueryPack` obsługuje cały pakiet celów w jednym przebiegu; `-CountOnly` pokazuje rozkład trafień po źródłach. Dopasowanie ignoruje wielkość liter i polskie znaki diakrytyczne.
- **Nowe narzędzie `Build-SourceManifest.ps1`** zastępuje `Build-SourceInventory.ps1`: liczy SHA-256 per źródło, odczytuje nagłówki `ŹRÓDŁO-*` i pomija zaplecze.
- **Unieważnianie per źródło.** Zniknął globalny `VERIFIED_SOURCE_TREE_SHA256`, przez który podmiana jednego pliku unieważniała cały etap K1. Zmiana pliku unieważnia teraz wyłącznie jego rekord i zależne karty; dopisanie źródła w K2B nie unieważnia niczego.
- **Maszynowa kontrola wierności.** Walidator sprawdza sam zgodność hasha źródła, mieszczenie się zakresu linii w pliku, istnienie timestampu i obecność nowego pola `CYTAT_DOSŁOWNY` we wskazanym miejscu. Kontroler-człowiek dostaje liczniki `AutoCheckedCards`/`ManualCheckCards` i zajmuje się wyłącznie sensem parafrazy, atrybucją i zakresem.
- **Odciążenie REZERWY.** Źródło `REZERWA` wymaga tylko ID, pliku i powodu odłożenia. Autor, data, klasa, zakres i hash stają się obowiązkowe dopiero po awansie do `CELOWE`/`RDZEŃ`.
- **Zakazy w Konstytucji i mandacie ChatGPT:** brak konwersji źródeł, luster Markdown, kopii materiału w wielu katalogach, globalnego indeksu treści i czytania źródła w całości przed wyszukaniem.
- **K0 steruje wyszukiwaniem:** każdy cel `Q-...` ma priorytet i hasła wyszukiwania; pakiet trafia do `_work/K1/pytania-k0.txt`.
- **Higiena `_work/`:** katalog przechowuje manifest, pakiet zapytań i notatki, nie materiał źródłowy; opisano orientacyjny limit i politykę czyszczenia.
- Poprawiono nieaktualne ścieżki absolutne w `_SYSTEM/04-START-I-KOMENDY.md`.
- `Test-System.ps1` rozszerzony o manifest, wyszukiwarkę, pakiet zapytań, limit długości fragmentu, unieważnianie per źródło, maszynową kontrolę wierności i odciążenie REZERWY.

Bez zmian pozostają: kompaktowe karty `#P`, architektura K2, mikropętla K2B, hashowane paczki `PRIMARY` dla K3, bramka K4 i zakończenie na K5.

## v7.0 — wyłącznie tworzenie narracji — 2026-08-17

- Decyzją Dawida całkowicie usunięto aktywny tor realizacyjny po scenariuszu. System kończy się teraz na `K5 → COMPLETE`, gdzie `COMPLETE` oznacza zatwierdzoną finalną narrację.
- Usunięto pięć instrukcji etapów realizacyjnych, pięć odpowiadających im szablonów projektu oraz pięć produkcyjnych rozdziałów Biblii. Pliki istniejące w projektach użytkownika pozostają nietknięte.
- Nowy projekt nie tworzy katalogu `assets/`; kanoniczny łańcuch plików kończy się na `05-FINAL-SCRIPT.md`.
- W0 bada pojemność narracyjną zamiast wykonalności realizacyjnej i nie tworzy hipotez tytułu ani miniatury.
- K2 używa `Scena/konkret narracyjny` oraz `Budżet słów` zamiast obowiązkowego planu obrazu i dźwięku.
- K4 nie prowadzi kontroli produkcyjności. ChatGPT odpowiada wyłącznie za research, architekturę i kontrolę narracji.
- Walidatory, testy, role, dokumentacja i Canvas blokują powrót wycofanych etapów i prowadzą bezpośrednio z K5 do `COMPLETE`.

## v7.0 — ChatGPT i kompaktowa baza dowodów — 2026-08-17

- ChatGPT przejął W0, K0, K1, K2, K2B, K4, P1, P5 i wsparcie P4 po dwóch usuniętych rolach AI; Claude pozostaje domyślnym autorem K3.
- Ujednolicono właścicieli w Konstytucji, pipeline, macierzy ról, krokach, szablonach, narzędziach i Canvasie.
- Wprowadzono `COMPACT_EVIDENCE_V1`: krótki indeks źródeł, celowaną ekstrakcję według celów `Q-...`, zwięzłą kartę `#P`, rozdział `PRIMARY/RESERVE` i bramkę pokrycia zamiast normy liczby kart.
- K0 przestał kopiować kanał, długość, WPM, styl i hipotezy opakowania; zawiera tylko decyzje potrzebne researchowi oraz 4–8 celów `Q`.
- K1 działa w trzech przebiegach: K1A indeks i selekcja, K1B ekstrakcja celowana, K1C kompresja, niezależna kontrola i przekazanie do K2.
- Dodano `tools/Build-SourceInventory.ps1`; K1A automatycznie liczy pliki, SHA-256, dokładne duplikaty i sygnaturę drzewa. `VERIFIED_SOURCE_TREE_SHA256` unieważnia K1 po każdej zmianie źródeł.
- Dodano `tools/Validate-EvidenceBase.ps1`; pusta, zduplikowana, nieodtwarzalna albo niepokrywająca celów baza nie może przejść K1.
- Dodano `tools/Validate-Architecture.ps1`; uproszczona lub pusta mapa aktu bez funkcji, zmiany stanu, pytania, wypłaty, kart, obrazu i budżetu nie może przejść K2.
- Dodano `tools/Build-K3Packets.ps1`; K3 otrzymuje pełne rekordy `PRIMARY` tylko dla bieżącego aktu, a `RESERVE` pozostaje niezaładowana do czasu jawnego awansu w K2/K2B.
- Generator i walidator wykrywają paczki osierocone po zmianie aktów; ich usunięcie wymaga jawnego `-PruneOrphans`.
- K2B stał się mikropętlą aktualizującą kanoniczne `01-baza-dowodow.md` i `02-architektura-odcinka.md` w miejscu. Trzy dawne szablony suplementu usunięto z aktywnego systemu; pliki istniejące w projektach historycznych pozostają nietknięte.
- `Validate-Project.ps1`, `Start-Stage.ps1`, `New-Project.ps1` i `Test-System.ps1` dostosowano do nowej macierzy ról i bramek; zmiana właściciela wymaga teraz jawnego `OWNER_OVERRIDE`.
- Inicjalizacja nie zalicza W0: wymagane są jawne `W0_DECISION` i zgodny `LAST_GATE`; markerów nowego workflow nie można po cichu zdegradować do legacy.
- K4 wymaga osobnego kontekstu ChatGPT VERIFY, deklaracji braku udziału w K3 oraz hasha kontrolowanej rewizji draftu.
- `Validate-Project.ps1` sprawdza ukończenie aktualnego etapu przed zmianą `CURRENT_STAGE`; wymaga świeżych, fizycznych paczek K3, poprawnych śladów `#P`, źródeł dostępnych dla VERIFY oraz wyłącznie werdyktu `GOTOWE DO K5`.
- K4 wymaga `OPEN_Q0: 0`, `OPEN_Q1_UNAPPROVED: 0`, baseline'u i maksymalnie 20% zmian; K5 odrzuca techniczne ślady `#P`.
- Projekty starsze pozostają czytelne: brak nowego schematu daje ostrzeżenie `LEGACY_UNCHECKED`, a historyczny K5 zachowuje dotychczasowe minimum `STATUS: ZATWIERDZONY`, bez automatycznego cofania ani przepisywania historii.

Poniższe wpisy opisują historię systemu sprzed tej rewizji i nie określają bieżących właścicieli ani aktywnych artefaktów.

## v7.0 — Antigravity, lżejszy fact-check i narzędzia — 2026-07-20

- Fact-check K4 przypisano do Antigravity (Konstytucja, pipeline, role, K4, szablon 04B, Canvas); dodano mandat `_SYSTEM/ROLES/ANTIGRAVITY.md`.
- Zawężono obowiązkowy zakres fact-checku do: cytatów, twierdzeń o prawie/zdrowiu/pieniądzach oraz nowych konkretów po poprawkach; nośne daty, liczby i nazwiska sprawdzane wyrywkowo. Teorie, legendy, relacje i spekulacje obecne w źródłach nie wymagają potwierdzenia; rekomendacje kontrpunktu zatwierdza Dawid.
- Konstytucja §3: uzupełniono zadania Codexa o P1 i P5.
- Usunięto martwy werdykt `PASS WARUNKOWY`.
- Walidator: status `BLOCKED` zgłasza błąd zamiast cichego PASS; pliki 04 i 04B wymagane już od K4.
- Nowe narzędzie `tools/Compare-Draft.ps1` — pomiar procentu zmian draftu względem baseline'u K4 (reguła 20%).
- `tools/Measure-Script.ps1`: tempo czytane automatycznie z `meta.md` projektu, odporniejsze liczenie słów (liczby typu 3,5, linie-placeholdery, brak separatora) i raport wykonania budżetu.
- Decyzją Dawida usunięto obowiązkową kontrolę zarzutów wobec żyjących osób i instytucji z zakresu fact-checku (K4, mandat Antigravity, szablon 04B, Konstytucja). Pozostają: atrybucja z kart `#P`, decyzja Dawida o publikacji zarzutu i zakaz przedstawiania zarzutu jako potwierdzonego faktu.
- Kontrola powtórzeń wpięta w walidator: każde uruchomienie `Validate-Project.ps1` na projekcie z draftem automatycznie zgłasza powtórzone frazy i wspólne karty jako ostrzeżenia — nie trzeba o niej pamiętać.
- Anty-powtórzenia w K3: rejestr aktów w nagłówku draftu (autor przed aktem czyta krótki rejestr zamiast pełnego tekstu poprzednich aktów) oraz nowy `tools/Check-Repetition.ps1`, który bez użycia AI wykrywa wspólne karty `#P` i powtórzone frazy między aktami.
- Przegląd ochrony teorii i legend: kontrargument, debunking i rama publikacyjna w K4, Storytellingu, Pismaku i Biblii 06 są rekomendacjami zatwierdzanymi przez Dawida, nie obowiązkiem. Teoria obecna w źródłach nie może zostać usunięta ani osłabiona bez jego decyzji.

## v7.0 — rewizja SOURCE_FIRST_K4 — 2026-07-16

- Ustanowiono zasadę: jeżeli materiał rzeczywiście znajduje się w źródłach i ma kartę `#P`, może wejść do draftu niezależnie od klasy źródła i stopnia potwierdzenia.
- Usunięto fact-check, debunking i obowiązkowe równoważenie teorii z etapów W0–K3.
- K1 zapisuje `STATUS_W_ŹRÓDLE`, nie wydaje werdyktu o prawdziwości.
- K2 buduje najmocniejszą historię z materiału i odkłada pytania faktograficzne na listę K4.
- K3 pisze pełny draft bez zatrzymywania się z powodu braku niezależnego potwierdzenia.
- K4 stał się pierwszym etapem weryfikacji: oddziela zgodność ze źródłem od potwierdzenia faktu i wykonuje ewentualny debunking dopiero po pełnym rozwinięciu historii.
- Dodano wynik `ZGODNE ZE ŹRÓDŁEM — NIEZWERYFIKOWANE`, który wymaga właściwej prezentacji, ale nie automatycznego usunięcia treści.
- Dodano pole projektu `VERIFICATION_POLICY: SOURCE_FIRST_K4` oraz kontrolę w walidatorze.

## v7.0 — 2026-07-15

- Ustanowiono jedno źródło prawdy i rozdzielono reguły wykonawcze od Biblii.
- Zachowano rygor dowodowy, atomy `#P`, architekturę, jeden draft, jeden QA i niezależny fact-check z v6.1.
- Rozdzielono tor tekstu `K0–K5` od produkcji `P1–P5`.
- Bramka K2B stała się obowiązkowym rozstrzygnięciem, ale suplement jest warunkowy.
- Ograniczono decyzje użytkownika do trzech głównych akceptacji.
- Wprowadzono selektywne ładowanie kontekstu oraz paczki kart przypisane do aktów.
- Dodano manifest wizualny, prawa/licencje i decyzję o oznaczeniu materiałów AI.
- Dodano produkcyjny scratch VO, plan montażu, QC i postmortem.
- Zaktualizowano publikację o natywne testy A/B tytułów i miniatur.
- Usunięto z procesu ensemble modeli, master-listę QA, `draft-v2` i dodatkowy QA-FINAL.
- Reporter został zastąpiony trybem dziennikarskim zgodnym z zasadą empatii i bez uderzania w słabszych.
- Dodano szablony oraz narzędzia PowerShell do inicjalizacji, pomiaru i walidacji.
