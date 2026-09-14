# K3 — SEKWENCYJNE PISANIE NARRACJI

Właściciel prozy: Claude. Orkiestracja, paczki i walidacja: ChatGPT/Codex. Wyjście kanoniczne: 03-draft.md złożony przez narzędzie.

## Routing

Dla WORKFLOW_REVISION 2026-08-31_NARRATIVE_V2 obowiązuje wyłącznie ten proces. Wcześniejsza rewizja używa własnego template, paczek i walidatora. Nie wolno mieszać ich ścieżek ani pól.

## Warunki startu

K3 rusza dopiero po:

1. ARCHITECTURE_PASS dla STORY_ENGINE_V2;
2. zatwierdzonym profilu głosu i wyborze profilu dla projektu;
3. zamrożeniu jednego MODEL_ID, MODEL_REVISION i SETTINGS_SHA przez Set-K3ModelManifest.ps1;
4. deterministycznym Build-K3PacketsV2.ps1;
5. ważnym constraint preflight bieżącego aktu;
6. ważnym attestem poprzedniego aktu albo kanonicznym START dla pierwszego.

Prefix jest bajtowo stały: K3_RULES_CORE, PROJECT_STORY_SPINE, VOICE_RULES i pełne VOICE_EXEMPLARS. Zmiana prefixu, modelu lub ustawień po rozpoczęciu wymaga formalnego rebase i inwalidacji.

## Jednostka pracy

Jeden akt = jeden świeży kontekst Claude’a. Nie wolno pisać aktów równolegle ani kontynuować rosnącej rozmowy. Każdy run otrzymuje paczkę w stałej kolejności:

1. CORE;
2. STORY_SPINE;
3. VOICE_RULES;
4. VOICE_EXEMPLARS;
5. CONTINUITY_IN;
6. EVIDENCE_SELECTION;
7. ACT_PACKET;
8. ACT_HARD_CONSTRAINTS;
9. DO_NOT_REVEAL;
10. WRITE_COMMAND.

Do autora nie trafia cała baza dowodów ani pełna Biblia narracji. Karty REQUIRED są przekazywane dosłownie i bez skracania; SUPPORTING tylko wtedy, gdy wybrało je K2. RESERVE nigdy nie wchodzi do paczki.

## Ograniczenia

GLOBAL_NON_NEGOTIABLES są w CORE. ACT_HARD_CONSTRAINTS zawiera maksymalnie siedem atomowych CID. SOFT_GUIDANCE jest doradcze i nie może udawać bramki. Każdy obowiązek NQ, NR, VC, embargo, narrator/humor, bridge, completion i CONTINUITY_OUT musi mieć pokrycie w ledgerze. Przeciążona albo nieatomowa paczka nie uruchamia pisania.

## SIMPLE i COMPLEX

Akt SIMPLE przechodzi bezpośrednio do generacji po constraint preflight. Akt COMPLEX najpierw dostaje beat-sheet i niezależny beat preflight. Beat-sheet nie jest prozą i nie może zmieniać kart, funkcji ani ujawnienia.

## PACKET_INSUFFICIENT

Claude ma zatrzymać generację bez prozy, gdy:

- brakuje dowodu do REQUIRED lub ujawnienia;
- paczka jest sprzeczna;
- completion criteria nie da się uczciwie spełnić;
- embargo koliduje z obowiązkiem;
- istnieje realny brak materiału.

Raport wskazuje dokładną lukę, dotknięte ID i najmniejszą proponowaną trasę. K3 nie promuje RESERVE i nie dopisuje źródeł. ChatGPT wykonuje formalny Reopen-Stage K3 → K2B, naprawia tylko konieczny zakres, przebudowuje zależne paczki i uruchamia ponownie świeży kontekst.

## Import prozy

Import-K3Act.ps1 przyjmuje zamknięty K3_ACT_SUBMISSION_V2. Każdy blok ma:

- trace_refs;
- source_p_ids;
- narrative_refs;
- czystą prozę.

Blok ma najwyżej 220 słów wyłącznie po to, by utrzymać dokładny BLOCK_ID/BLOCK_SHA i ślad źródłowy. To nie jest target długości ani limit aktu. Blok bez legalnej karty, z technicznym residue lub niezgodny z paczką jest odrzucany atomowo.

## Continuity

Po imporcie Claude w drugiej turze tej samej sesji proponuje CONTINUITY_OUT na podstawie dokładnych bloków. Osobny świeży kontekst CONTINUITY_ATTEST dostaje tylko ACT_PROSE_BLOCKS, CONTINUITY_IN, CONTINUITY_OUT i schemat. Nie zna Story Spine ani przyszłych aktów.

Atest sprawdza:

- czy każdy stan naprawdę występuje w związanych blokach;
- rozdział FACT, INFERENCE, VIEWER_STATE i REVEAL;
- źródła i BLOCK_REFS;
- arytmetykę NQ oraz działania NR;
- zachowanie niepewności;
- bridge, ruch otwarcia i zamknięcia;
- pełny oczekiwany CONTINUITY_IN następnego aktu.

FAIL blokuje kolejny akt. PASS zapisuje niezmienny attest i wejście następnego aktu. Powtórzone typy ruchów dają REVIEW_ALERT; świadoma repetycja wymaga decyzji Dawida.

## Montaż i długość

Assemble-K3Draft.ps1 składa wyłącznie akty ATTESTED z tym samym prefixem i modelem. Autor ani ChatGPT nie wkleja aktów ręcznie do 03. Narrative V2 nie ma budżetu słów ani znaków na akt. Po montażu Measure-Script.ps1 raportuje rzeczywisty czas. GUIDE jest informacją; HARD_MAX blokuje dopiero K5. Tekst za krótki naprawia się większą wartością źródłową lub zakresem, nigdy wypełniaczem.

## Bramka K3

- wszystkie akty powstały sekwencyjnie w świeżych kontekstach;
- jeden MODEL_ID/revision/settings i jeden PREFIX_SHA;
- preflighty aktualne;
- każdy blok ma legalne karty i ślad;
- każdy akt ma ważny attest;
- brak PREFIX_STALE, MODEL_STALE i CONTINUITY_STALE;
- powtórzenia ruchów są rozliczone;
- 03 powstał przez Assemble-K3Draft.ps1;
- Validate-Project.ps1 zwraca PASS.

Przejście do K4 wykonuje wyłącznie Advance-Stage.ps1.
