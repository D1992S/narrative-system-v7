# Schemat ciągłości NARRATIVE_V2

CONTINUITY_SCHEMA: CONTINUITY_ATTEST_V1

## Zakres ślepego atestu

Świeży kontekst kontrolny otrzymuje wyłącznie cztery wejścia: `ACT_PROSE_BLOCKS`, zatwierdzony `CONTINUITY_IN`, deklarowany `CONTINUITY_OUT` i ten dokument. Nie otrzymuje Story Spine, architektury, paczki aktu ani planu revealów. Ma sprawdzić wyłącznie, czy OUT jest wiernym i kompletnym odczytem przekazanej prozy oraz czy arytmetyka IN→OUT jest spójna.

## CONTINUITY_IN_V1

Obiekt ma dokładnie pola:

```text
schema, act_id, source_act_id, source_act_sha256, source_attest_sha256,
text_states[], viewer_inferences[], open_nq_ids[], prepared_nr_ids[],
active_embargoes[], world_state[], bridge, opening_move_history[],
closing_move_history[], emotional_pressure
```

To stan potwierdzony poprzednim atestem, bez pełnej prozy poprzednich aktów. Nie wolno dopisywać do niego nowego faktu ani zmieniać klasy inferencji.

## CONTINUITY_OUT_V1

Obiekt ma dokładnie pola:

```text
schema, act_id, records[], nq_paid[], nq_opened[], nq_reframed[],
open_nq_ids_out[], nr_revealed[], nr_consequences[], nr_setup_only[],
character_and_world_state[], bridge_realized, bridge_block_refs[],
opening_move_type, opening_block_refs[], closing_move_type,
closing_block_refs[], uncertainties_preserved[]
```

Każdy `records[]` ma dokładnie:

```json
{"state_id":"STATE-001","category":"FACT|INFERENCE|QUESTION|REVEAL|BRIDGE|WORLD_STATE|KNOWLEDGE_BOUNDARY","value":"dokładna treść","class":"TEXT_ASSERTED|VIEWER_INFERENCE","block_refs":[{"block_id":"BLOCK-ACT-001-001","block_sha256":"<SHA256>"}],"related_ids":["SW-001"],"source_p_ids":["#P-001"]}
```

- `STATE_ID` jest unikalne i sekwencyjnie czytelne (`STATE-001` itd.).
- `related_ids` może zawierać wyłącznie rzeczywiste `NQ/NR/VC/SW` należące do bieżącego aktu.
- `BLOCK_REFS` wskazuje faktyczne bloki i ich aktualne hashe. Wartość `TEXT_ASSERTED` musi występować dosłownie w co najmniej jednym wskazanym bloku.
- `FACT` i `REVEAL` wymagają kart `#P` faktycznie obecnych w tych blokach. Rekord `REVEAL` wiąże legalny `NR_ID`, token `REVEAL:NR_ID`, `nr_revealed` i wszystkie karty dowodowe revealu w tym samym bloku.

Każdy `character_and_world_state[]` ma dokładnie:

```json
{"world_state_id":"WORLD-001","value":"dokładna treść","class":"TEXT_ASSERTED|VIEWER_INFERENCE","block_refs":[{"block_id":"BLOCK-ACT-001-001","block_sha256":"<SHA256>"}],"source_p_ids":["#P-001"]}
```

`TEXT_ASSERTED` wymaga co najmniej jednej karty P i dosłownego zakotwiczenia `value` w podanym bloku. `VIEWER_INFERENCE` zachowuje jawną klasę inferencji; nie wolno awansować go na fakt.

Każdy `uncertainties_preserved[]` ma dokładnie:

```json
{"uncertainty_id":"UNCERTAINTY-001","value":"dokładna granica wiedzy z tekstu","block_refs":[{"block_id":"BLOCK-ACT-001-001","block_sha256":"<SHA256>"}],"source_p_ids":["#P-001"]}
```

Wartość niepewności musi występować dosłownie w jednym ze wskazanych bloków. `opening_block_refs` musi obejmować pierwszy blok aktu; `closing_block_refs` i `bridge_block_refs` muszą obejmować ostatni blok. Każdy ref ma dokładnie `block_id` i `block_sha256`.

Pola NQ raportują wykonane ruchy: `nq_opened`, `nq_paid`, `nq_reframed[{from_id,to_id,close_from}]`, a `open_nq_ids_out` jest stanem netto. Arytmetyka: `OPEN_OUT = OPEN_IN - PAID_OR_CLOSED + NEWLY_OPENED`.

Pola NR raportują akcje w kolejności scen: `SETUP`, `REVEAL`, `CONSEQUENCE`. Nie istnieje akcja `KEEP`. `nr_setup_only` zawiera tylko reveale przygotowane, lecz jeszcze nieujawnione na końcu aktu. `nr_revealed` zawiera reveale ujawnione w tym akcie, a `nr_consequences` ich późniejsze konsekwencje wykonane w tym akcie.

Ruchy otwarcia: `SCENA`, `ANOMALIA`, `DOKUMENT`, `KONSEKWENCJA`, `KONTRAST`, `KONTAKT_Z_WIDZEM`, `POWRÓT_DO_MOTYWU`. Ruchy zamknięcia: `DECYZJA`, `REVEAL`, `PAYOFF`, `KONSEKWENCJA`, `GRANICA_WIEDZY`, `NOWA_PĘTLA`, `POWRÓT_DO_MOTYWU`.

## Dokładny wynik CONTINUITY_ATTEST_RESULT_V1

Zwróć wyłącznie jeden poprawny obiekt JSON zgodny z poniższymi polami. Kolejność kluczy i wcięcia nie wymagają kolejnego wywołania modelu. Operator zapisuje odpowiedź jako `raw-response.json` wewnątrz runu i uruchamia `tools/Normalize-ContinuityResponse.ps1 -ProjectPath <projekt> -RunId <run> -RawPath <plik>`. Narzędzie zachowuje oryginał, odrzuca powtórzone klucze i zapisuje kanoniczne `output.md` oraz wiązanie hashy. Nie nadaje PASS ani nie tworzy receiptu modelu. Dopiero normalny walidator i `New-NarrativeRunReceipt.ps1` sprawdzają całą treść. Odpowiedź już kanoniczna pozostaje obsługiwana dotychczasową drogą. Przykład postaci kanonicznej:

```json
{"act_id":"ACT-001","missing_state_change":false,"question_arithmetic_verdict":"PASS","reason":"Pełny, konkretny powód końcowego werdyktu","record_results":[{"reason":"Konkretny powód oparty na wskazanym bloku","state_id":"STATE-001","verdict":"PASS"},{"reason":"Konkretny powód oparty na wskazanym bloku","state_id":"WORLD-001","verdict":"PASS"},{"reason":"Konkretny powód oparty na wskazanym bloku","state_id":"UNCERTAINTY-001","verdict":"PASS"},{"reason":"Most jest widoczny w ostatnim bloku","state_id":"BRIDGE","verdict":"PASS"},{"reason":"Typ otwarcia odpowiada pierwszemu blokowi","state_id":"OPENING_MOVE","verdict":"PASS"},{"reason":"Typ zamknięcia odpowiada ostatniemu blokowi","state_id":"CLOSING_MOVE","verdict":"PASS"}],"schema":"CONTINUITY_ATTEST_RESULT_V1","verdict":"PASS"}
```

`record_results` musi zawierać dokładnie po jednym rekordzie dla każdego `STATE-*`, `WORLD-*`, `UNCERTAINTY-*` z OUT oraz zawsze dla specjalnych identyfikatorów `BRIDGE`, `OPENING_MOVE`, `CLOSING_MOVE`. Nie dodawaj innych identyfikatorów. Każdy rekord ma dokładnie `state_id`, `verdict`, `reason`; do przyjęcia atestu każdy `verdict` i werdykt globalny muszą być `PASS`, `missing_state_change=false`, a `question_arithmetic_verdict=PASS`. Jeżeli którykolwiek warunek nie zachodzi, nie deklaruj PASS i nie próbuj tworzyć receiptu zaliczającego.
