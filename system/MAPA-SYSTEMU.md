# MAPA SYSTEMU v7.0

Od 2026-09-12, na polecenie Dawida, jedyną wersją wybieraną dla nowych projektów jest `2026-08-31_NARRATIVE_V2`. `New-Project.ps1` wybiera ją domyślnie. Status jakości pozostaje `PILOT_ONLY`: uporządkowanie i wybór wersji nie są wynikiem testu A/B ani zatwierdzeniem profilu głosu. Istniejące projekty zachowują swój origin, rewizję, tekst i receipty; nie są automatycznie migrowane. Kod zgodności służy zachowaniu dostępu do tych projektów, nie stanowi drugiej instalacji systemu.

```mermaid
flowchart LR
    W0["W0: decyzja Dawida"] --> K0["K0: pytania i zakres"]
    K0 --> K1["K1-Lite V2: pełny korpus → baza dowodów"]
    K1 --> K2["K2: STORY_ENGINE_V2"]
    K2 --> K2B{"K2B: packet wystarczający?"}
    K2B -->|nie| SUP["celowany suplement + repack"]
    SUP --> K2B
    K2B -->|tak| K3["K3: sekwencyjne akty"]
    K3 --> K4["K4: trzy niezależne soczewki"]
    K4 -->|korekta prozy| RK3["Reopen → K3"]
    K4 -->|źródła / architektura| RK2B["Reopen → K2B"]
    RK3 --> K3
    RK2B --> K2B
    K4 --> K5["K5: decyzja Dawida"]
    K5 --> END["COMPLETE / K5_PASS"]
```

## K1: duże źródła bez przepalania kontekstu

```mermaid
flowchart TB
    PDF["oryginalny PDF"] --> TXT["tekst + markery stron + punktowy OCR"]
    NAT["MD / TXT / SRT / VTT"] --> PLAN["plan 100% jednostek"]
    TXT --> PLAN
    PLAN --> WORK["maks. 2 rozłączne workery"]
    WORK --> LEDGER["append-only ledger"]
    LEDGER --> REVIEW["rekomendacje ChatGPT + decyzje Dawida"]
    REVIEW --> SIX["editorial review + 6 bramek + visual QA"]
    SIX --> PUB["Preview → Publish → 01 + receipt"]
```

Compile działa tylko w K1, a Merge tylko w K2B. Narzędzia odczytują etap ponownie pod blokadą, wiążą source snapshot i nie zostawiają rezultatu po odmowie. Źródła nie są pomijane; oszczędność bierze się z lokalnej konwersji, małych paczek i ponownego użycia wyników po hashach.

## K2 i packet

Story Engine opisuje Story DNA, stan wiedzy oraz nacisk emocjonalny widza, pytania NQ, reveale NR, kontakt VC, Scene Weave, funkcje REQUIRED/SUPPORTING/RESERVE i completion criteria. Nie używa budżetu słów ani znaków.

```mermaid
flowchart LR
    E["01 + 02"] --> PFX["stable prefix"]
    PFX --> PACK["ACT_PACKET + legalne pełne karty"]
    PACK --> CID["constraint ledger ≤ 7 CID"]
    CID --> PRE["niezależny atomicity preflight"]
    PRE -->|FAIL| REPACK["K2B repack / redukcja"]
    PRE -->|PASS| WRITE["świeży kontekst Claude'a"]
```

Pełna Biblia narracji jest zapleczem K2/K4. Autor K3 dostaje tylko skompilowany `K3-RULES-CORE`, voice profile, Story Spine, continuity i packet bieżącego aktu.

## Wnętrze K3

```mermaid
flowchart LR
    A["packet READY"] --> G["GENERATE_ACT: świeży kontekst"]
    G -->|PACKET_INSUFFICIENT| B["zero prozy + formalny reopen"]
    G -->|SIMPLE| PROSE["bloki prozy + ślady"]
    G -->|COMPLEX| BEAT["beat sheet → blind preflight"]
    BEAT --> PROSE
    PROSE --> OUT["CONTINUITY_OUT"]
    OUT --> ATT["świeży blind CONTINUITY_ATTEST"]
    ATT -->|FAIL| FIX["naprawa tego aktu"]
    ATT -->|PASS| NEXT["następny akt"]
    NEXT --> ASM["Assemble-K3Draft"]
```

Następny akt nie może wyprzedzić PASS. OUT wiąże stan do exact `BLOCK_ID/BLOCK_SHA`, nie do zamiaru autora. Zmiana wcześniejszego aktu unieważnia zależną ciągłość. Powtórzenie ruchu otwarcia/zamknięcia daje alert, a świadomy wyjątek wymaga decyzji Dawida.

## K4: opowieść, prawda i doświadczenie

```mermaid
flowchart TB
    D["aktualny 03 + continuity complete"] --> E["EDITOR_V2\nplan + głos + semantic preflight"]
    D --> V["VERIFY_SOURCE_FIRST\ndraft + baza + źródła + lokalizatory"]
    D --> C["COLD_READER_BLIND\ntylko czysta narracja"]
    E --> PROOF["K4_PROOF_SET_V2"]
    V --> PROOF
    C --> PROOF
    PROOF --> R["04 + 04B"]
```

Każda soczewka ma inny `RUN_ID`, `TASK_ID` i świeży kontekst. Semantic preflight wykrywa m.in. skopiowaną frazę exemplarów i nieplanowany kontakt, a zakazany humor jest twardym FAIL. Verify blokuje zawyżoną pewność. Cold Reader nie zna planu. Po zmianie draftu soczewka ma świeży run albo ważny carry-forward oparty na aktualnym dependency fingerprint; zmiana semantic preflight wymusza ponowną ocenę Editora.

## Długość i finał

`GUIDE` informuje po napisaniu. `HARD_MAX` ogranicza finalną całość. Żaden tryb nie tworzy dolnego progu ani targetu per akt. K5 wiąże czystą narrację, proof set, continuity i wynik pomiaru; akceptację daje tylko Dawid.

## Stan mechaniczny

`Advance-Stage.ps1` bez `-Apply` pokazuje ruch, a z `-Apply` wykonuje go po PASS. `Reopen-Stage.ps1` jest jedynym powrotem Narrative V2. Origin, project lock, pełny manifest, CAS, journal i rollback chronią stan. Ręczna zmiana `meta.md` nie zastępuje mutatora ani receiptu.

Gałąź legacy zachowuje stare narzędzia i schematy tylko dla zgodności. `_work/k3-pakiety/`, budżet aktu i `K3_BUDGET_OVERRIDE` są niedozwolone w Narrative V2.
