# K4 — TRZY NIEZALEŻNE SOCZEWKI

Właściciel: ChatGPT/Codex. K4 diagnozuje i dowodzi kontroli; nie przepisuje kanonicznej prozy.

## Start Narrative V2

Start-K4Lenses.ps1 wymaga CURRENT_STAGE: K4, kompletnego łańcucha atestów, aktualnego draftu i rozliczonego alertu powtórzeń. Tworzy trzy odrębne input bundle z unikalnymi RUN_ID/TASK_ID. Żaden wynik soczewki nie jest wejściem innej.

### EDITOR_V2

Editor otrzymuje fundament, architekturę, czysty draft, mapę bloków, Story Spine, NQ/NR/VC, reguły i exemplars głosu, continuity chain, SEMANTIC_PREFLIGHT oraz zamknięte kryteria.

Sprawdza:

- hook, obietnicę i wypłatę;
- zmianę stanu każdego aktu i dwie osie ruchu;
- pełną logikę NQ/NR;
- funkcję REQUIRED, ekspozycji i przejść;
- powtórzenia funkcji;
- każdy VC i każdy PREFLIGHT_JSON;
- głos bez kopiowania fraz;
- zakaz humoru w aktach FORBIDDEN;
- finał zmieniający model zamiast streszczenia.

Nieplanowany kontakt i ośmiowyrazowe podobieństwo do exemplara są REVIEW_ALERT do osądu. Brak kontaktu i brak humoru są PASS. Rzeczywisty żart przy FORBIDDEN blokuje PASS nawet wtedy, gdy heurystyka go nie wykryła.

### VERIFY_SOURCE_FIRST_V1

Verify otrzymuje techniczny draft z BLOCK_ID/P, kanoniczną bazę, aktywne źródła, lokalizatory i kryteria Verify. Nie dostaje reguł stylu, Story Spine ani wyniku Editora.

Sprawdza każdy blok i każdą używaną kartę, cytaty, atrybucję, chronologię, przyczynowość, legalność karty, lokalizator i granicę wnioskowania. Modalność źródła jest obowiązkowa: niepewność, hipoteza lub spór zamienione w pewnik dają finding i FAIL. Zgodność cytatu z kartą nie dowodzi prawdziwości tezy.

### COLD_READER_V1

Cold Reader dostaje wyłącznie czystą narrację. Nie dostaje 00, 01, 02, mapy bloków, źródeł, rejestrów, głosu ani innych raportów. Odpowiada na dziesięć zamkniętych pytań o obietnicę, orientację, przewidywalność, powtórzenie, punkt porzucenia, pamięć, finał, wypłatę, przeciążenie i przypadkowo otwarte pytanie. Jest proxy, nie prognozą retencji.

## Receipty i wyniki

Każdy run:

- używa zamkniętej whitelisty i kanonicznych ścieżek;
- ma aktualny output zgodny ze schematem;
- ma oddzielny TASK_ID;
- kończy się SYSTEM_V7_NARRATIVE_RUN_RECEIPT_V1;
- wiąże model, prompt revision, settings, wejścia, output i deklarację niezależności.

Receipt dowodzi wejść i bajtów, nie jakości osądu. Compile-K4ProofSet.ps1 wymaga dokładnie jednego aktualnego dowodu per soczewka. Editor i Cold Reader trafiają do 04-raport-qa.md, Verify do 04B-fact-check.md; Compile-K4Reports.ps1 nie usuwa sprzeczności.

## Findings

Dozwolone klasy to CRITICAL, MAJOR, MINOR i REVIEW_ALERT. Liczniki muszą dokładnie odpowiadać wierszom. PASS wymaga zera CRITICAL, MAJOR i nierozstrzygniętych REVIEW_ALERT oraz PASS całych rejestrów maszynowych.

## Korekty

ChatGPT scala listę w kolejności:

1. prawda, zakres i pewność;
2. ciągłość, obietnica i reveale;
3. jasność, redundancja, rytm i głos.

Zmiana prozy wymaga Reopen-Stage K4 → K3 i pozostawia Claude’a właścicielem. Zmiana 01/02 wymaga K4 → K2B. Po zmianie 03 każda soczewka ma świeży run albo ważny QA_CARRYFORWARD prowadzący do aktualnego SHA. Jakakolwiek różnica bajtowa domyślnie wymaga SEMANTIC_REVIEW_REQUIRED; tylko BYTE_IDENTICAL jest mechanicznie bezpieczne.

Zmiana twierdzenia, dowodu, revealu, struktury, obietnicy lub zakresu wymaga odpowiednich świeżych soczewek. Niepewność daje RERUN_REQUIRED. Łańcuch carry-forward musi być acykliczny i hash-bound.

## Bramka

- trzy niezależne bundle bez kontaminacji;
- trzy ważne outputs i receipty;
- zamknięte rejestry z pełnym pokryciem;
- SOURCE_FIRST_K4 zachowane;
- brak nierozwiązanych problemów krytycznych i poważnych;
- po zmianach aktualny run albo ważny carry-forward każdej soczewki;
- proof set i raporty odpowiadają aktualnemu draftowi;
- Validate-Project.ps1 zwraca PASS.

## Rewizja wcześniejsza

Dla 2026-08-30_K1_LITE_V2 obowiązuje jej LEAD/VERIFY, 04/04B i stare receipty. Nie są dowodem K4 Narrative V2 i nie wolno ich dołączyć do proof set V2.
