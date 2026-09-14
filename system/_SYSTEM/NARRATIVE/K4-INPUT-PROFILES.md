# Zamknięte profile wejść NARRATIVE_V2

K4_QA_SCHEMA: THREE_LENS_QA_V1

Receipt wiąże fizyczny bundle wejściowy i jego manifest. Dowodzi, jakie pliki przygotował system; nie dowodzi jakości osądu ani kryptograficznej tożsamości wykonawcy.

| RUN_TYPE | INPUT_PROFILE | Dozwolone role wejść |
|---|---|---|
| GENERATE_ACT | K3_ACT_V2 | CORE, STORY_SPINE, VOICE_RULES, VOICE_EXEMPLARS, CONTINUITY_IN, EVIDENCE_SELECTION, ACT_PACKET, ACT_HARD_CONSTRAINTS, DO_NOT_REVEAL, WRITE_COMMAND |
| CONSTRAINT_ATOMICITY_PREFLIGHT | CONSTRAINT_PREFLIGHT_V1 | ACT_PACKET, CONSTRAINT_LEDGER, ATOMICITY_SCHEMA |
| BEAT_PREFLIGHT | BEAT_PREFLIGHT_V1 | ACT_PACKET, BEAT_SHEET, BEAT_SCHEMA |
| CONTINUITY_ATTEST | CONTINUITY_BLIND_V1 | ACT_PROSE_BLOCKS, CONTINUITY_IN, CONTINUITY_OUT, CONTINUITY_SCHEMA |
| EDITOR | EDITOR_V2 | FUNDAMENT, ARCHITECTURE, CLEAN_DRAFT, BLOCK_MAP, STORY_SPINE, NQ_NR_VC, VOICE_RULES, VOICE_EXEMPLARS, CONTINUITY_CHAIN, SEMANTIC_PREFLIGHT, EDITOR_CRITERIA, EDITOR_OUTPUT_SCHEMA |
| VERIFY | VERIFY_SOURCE_FIRST_V1 | DRAFT_BLOCKS, EVIDENCE_BASE, SOURCE_FILES, SOURCE_LOCATORS, VERIFY_CRITERIA, VERIFY_OUTPUT_SCHEMA |
| COLD_READER | COLD_READER_BLIND_V1 | CLEAN_NARRATION, COLD_READER_QUESTIONS, COLD_READER_OUTPUT_SCHEMA |
| QA_IMPACT_REVIEW | QA_IMPACT_V1 | OLD_DRAFT, NEW_DRAFT, IMMUTABLE_DIFF, IMPACT_SCHEMA |

Profile są whitelistami zamkniętymi. Nadmiarowe wejście daje `CONTEXT_CONTAMINATION`. `SEMANTIC_PREFLIGHT` jest deterministycznie związany z SHA draftu, rewizją architektury, SHA exemplarów oraz istniejącymi ACT/BLOCK; nieznany typ findingu albo fałszywe wiązanie daje FAIL. Cold Reader dostaje wyłącznie czystą narrację oraz neutralny formularz pytań i schemat odpowiedzi; nie dostaje planu, źródeł, zamiarów autora ani reguł głosu. `EDITOR`, `VERIFY`, `COLD_READER` i `CONTINUITY_ATTEST` używają różnych `TASK_ID` i świeżych kontekstów.

## Neutralne dane wykonania i szkielet

Profile EDITOR, VERIFY i COLD_READER dopuszczają dodatkowo dokładnie role `RUN_CONTEXT` i `RESPONSE_TEMPLATE`. Oficjalny Start-K4Lenses dodaje je do nowych runów. Są opcjonalne wyłącznie dla zgodności wcześniejszych bundli. RUN_CONTEXT zawiera tylko wersję formatu i hash draftu. RESPONSE_TEMPLATE jest deterministyczną projekcją danych tej samej soczewki: nagłówki, identyfikatory oraz puste pola ocen. Nie zawiera domyślnych PASS. Walidator sprawdza zgodność obu plików z wejściem; Cold Reader nie otrzymuje przez nie planu ani źródeł.
