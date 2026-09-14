# SYSTEM TWORZENIA NARRACJI DOKUMENTALNYCH v7.0

System prowadzi projekt od pomysłu do zatwierdzonej narracji `05-FINAL-SCRIPT.md` trasą:

`W0 → K0 → K1 → K2 → K2B → K3 → K4 → K5 → COMPLETE`

Od 2026-09-12, na polecenie Dawida, jedyną wersją wybieraną dla nowych projektów jest `2026-08-31_NARRATIVE_V2`. `New-Project.ps1` wybiera ją domyślnie. Status jakości pozostaje `PILOT_ONLY`: uporządkowanie i wybór wersji nie są wynikiem testu A/B ani zatwierdzeniem profilu głosu. Istniejące projekty zachowują swój origin, rewizję, tekst i receipty; nie są automatycznie migrowane. Kod zgodności służy zachowaniu dostępu do tych projektów, nie stanowi drugiej instalacji systemu.

## Co daje Narrative V2

- K1-Lite V2 zamienia duże PDF/MD/TXT/SRT/VTT w małą, lokalizowalną bazę dowodów, zachowując pełne pokrycie korpusu;
- K2 projektuje zmianę wiedzy i napięcia widza przez Story DNA, NQ, NR, VC i Scene Weave;
- K3 nie dostaje całego systemu ani całej bazy: jeden akt powstaje w świeżym kontekście z byte-identical prefixem i małym packetem;
- każdy akt ma najwyżej siedem atomowych twardych obowiązków, a przeciążenie lub brak dowodu zatrzymuje prozę;
- ciągłość jest sprawdzana przez niezależny, ślepy attest przeciwko faktycznym blokom prozy;
- K4 rozdziela Editor V2, Verify source-first i Cold Reader audio-only;
- długość jest mierzona po napisaniu w trybie `GUIDE` albo kontrolowana jako finalny `HARD_MAX`, bez budżetów per akt i bez dolnych progów;
- wszystkie wejścia, runy, proofy, przejścia i wyjątki są związane hashami oraz immutable receiptami.
- 58 kluczowych instrukcji, schematów i szablonów jest związanych zamkniętym manifestem; cicha zmiana któregokolwiek pliku zatrzymuje V2.

## Najprościej: kto za co odpowiada

- Dawid: W0, wybory redakcyjne K1/K2, exact AUTHOR_TEXT, voice profile, polityka czasu, świadome wyjątki, K5 i decyzja o aktywacji;
- ChatGPT/Codex: K0, orkiestracja K1, Story Engine K2/K2B, preflighty, continuity attest, trzy soczewki K4 i kontrola integralności;
- Claude: wyłącznie proza K3, self-check i propozycja `CONTINUITY_OUT`;
- lokalne narzędzia: PDF/OCR, indeks, kompilacja packetów, hashe, receipts, walidacja, assembly i atomowe mutacje.

Model nie może udawać decyzji Dawida. Parserowy PASS nie jest dowodem jakości semantycznej; brak prawdziwego outputu pozostaje `NOT_RUN`.

## K1 w skrócie

1. Oryginalny PDF zostaje nietknięty; obok powstaje tekst z markerami fizycznych stron. Tesseract działa tylko tam, gdzie tekst natywny zawodzi.
2. Plan rozdziela 100% materiału na rozłączne paczki, maksymalnie dla dwóch workerów.
3. Wyniki trafiają do append-only ledgera. ChatGPT może rekomendować `KEY_CHATGPT`, ale Dawid niezależnie wybiera `MUST_INCLUDE`, `IMPORTANT_SIDE` albo `REJECTED`.
4. Dawid czyta `editorial-review.md`; receipt wiąże dokładny widok.
5. Sześć bramek, visual QA, cytaty, lokalizatory i hashe muszą przejść.
6. Preview i Publish tworzą pierwszy `01-baza-dowodow.md` oraz publish receipt. Inne wejście nie może go nadpisać.
7. Suplement jest addytywny i legalny wyłącznie w K2B.

Karta dowodowa V4 zawiera dosłowną treść, `ŹRÓDŁO_ID`, dokładną lokalizację i `QA_K1`. Prawdziwość twierdzenia, niezależność źródeł i poziom pewności sprawdza później Verify K4.

## K2–K5 w skrócie

K2 tworzy `STORY_ENGINE_V2` bez budżetów słów i znaków. Każdy akt ma funkcję, zmianę stanu, completion criteria, legalne karty dowodowe i zamknięty rejestr działań narracyjnych.

W K3 kolejność jest bezwzględna:

`packet → constraint preflight → świeży kontekst autora → opcjonalny beat preflight → proza → CONTINUITY_OUT → świeży continuity attest → następny akt`

Po wszystkich atestach `Assemble-K3Draft.ps1` montuje jeden draft. K4 uruchamia trzy różne konteksty i trzy zamknięte input profiles. Poprawka nie jest nanoszona po cichu: wymaga formalnego reopen do K3 albo K2B, a później świeżego runu lub ważnego carry-forward każdej dotkniętej soczewki.

K5 akceptuje wyłącznie czystą narrację powiązaną z aktualnym proof setem K4, pełnym łańcuchem continuity i polityką czasu. Dopiero realny `Advance-Stage.ps1 -Apply` ustawia `COMPLETE/K5_PASS`.

## Bezpieczeństwo stanu

Nowy projekt ma niezmienny `.system-v7/project-origin.json`. Mutatory używają wspólnego locka, ponownego odczytu stanu pod blokadą, pełnego manifestu, CAS, journala i rollbacku. Ręczne przepisywanie `CURRENT_STAGE`, rewizji, modelu, prefixu, voice profile, czasu albo proofów jest zabronione.

`Advance-Stage.ps1` jest jedyną drogą naprzód, a `Reopen-Stage.ps1` jedyną drogą wstecz dla Narrative V2. Block/Unblock, owner override i decyzje Dawida mają własne receipts.

## Szybki start pilota

```powershell
$tools = "E:\projektyoutube\Produkcja tekstów\System-v7.0\tools"
& "$tools\New-Project.ps1" `
  -ProjectName "Nazwa filmu" `
  -DestinationRoot "E:\projektyoutube\Produkcja tekstów\projekty" `
  -TargetMinutes 45 -TargetDurationMode GUIDE -NarrativeV2Pilot
```

Potem umieść źródła bezpośrednio w `sources/` i pracuj według [`_SYSTEM/04-START-I-KOMENDY.md`](_SYSTEM/04-START-I-KOMENDY.md). Przed każdym przejściem uruchom podgląd `Advance-Stage.ps1`; po kontroli dopiero `-Apply`.

## Walidacja i regresja

```powershell
& "$tools\Validate-NarrativeV2Project.ps1" -ProjectPath "<PROJECT_PATH>"
& "$tools\Test-NarrativeV2.ps1"
& "$tools\Test-AdvanceAtomicity.ps1"
& "$tools\Test-ProjectMutationLocks.ps1"
& "$tools\Test-System.ps1"
```

`New-NarrativeInstructionManifest.ps1 -Write` nie jest zwykłą walidacją. Uruchamia go wyłącznie maintainer po świadomej zmianie kontrolowanych instrukcji, a następnie wykonuje cały powyższy zestaw testów. Nie używaj `-Write` do „naprawiania” nieoczekiwanego błędu manifestu, bo zatwierdziłoby to przypadkową zmianę.

Real-model test zawyżonej pewności jest osobnym testem semantycznym. Bez rzeczywistego outputu Verify i receiptu wynik ma pozostać `NOT_RUN`, nigdy PASS. Ślepy pilot jest zdefiniowany w `_SYSTEM/NARRATIVE/AB-TEST-PROTOCOL.md`; obecny stan `NOT_RUN_REQUIRES_DAWID` nie jest wynikiem negatywnym ani pozytywnym.

## Legacy

Nowe projekty zawsze rozpoczynaj domyślnym `New-Project.ps1` w Narrative V2. Szablony w `tools/compatibility/` oraz stare gałęzie walidatorów są zależnościami istniejących projektów. Historyczny przełącznik `-NarrativeV2Pilot:$false` jest zachowany wyłącznie do tworzenia fixture’ów testów zgodności. Jeszcze starsze projekty z `legacy-origin.json` są validation-only; ich wznowienie wymaga jawnej migracji. Nie zmieniaj rewizji ani originu gotowego odcinka w ramach porządkowania folderów.
