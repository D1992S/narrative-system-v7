# 02 — STORY ENGINE V2

STATUS: ROBOCZY
ARCHITECTURE_SCHEMA: STORY_ENGINE_V2
ARCHITECTURE_REVISION: 1
WYBRANY_KIERUNEK:
ONE_DIRECTION_APPROVAL: BRAK

Poniższy blok JSON jest kanonicznym źródłem Story DNA, rejestrów i projekcji K3. Nie dodawaj budżetów słów, znaków, ekspozycji, nazw, humoru ani kontaktów z widzem. `setup_required` zawiera konkretną instrukcję przygotowania albo `BRAK`; nie używaj `YES/NO`. Każdy reveal musi mieć późniejszą akcję `CONSEQUENCE`.

<!-- NARRATIVE_V2_JSON_BEGIN -->
```json
{
  "schema": "STORY_ENGINE_V2",
  "architecture_revision": 1,
  "selected_direction": "A",
  "directions": [
    {"direction_id": "A", "axis": "", "conflict": "", "promise": "", "core_p_ids": ["#P-001"], "narrative_concrete": "", "risk_advantage": ""},
    {"direction_id": "B", "axis": "", "conflict": "", "promise": "", "core_p_ids": ["#P-001"], "narrative_concrete": "", "risk_advantage": ""}
  ],
  "story_dna": {"central_question": "", "viewer_promise": "", "starting_model": "", "destabilizing_fact": "", "deeper_model": "", "human_stake": "", "external_stake": "", "value_conflict": "", "knowledge_boundary": "", "final_transformation": "", "final_image_or_thought": ""},
  "hook_contract": {"concrete_anomaly_or_consequence": "", "honest_promise": "", "why_it_matters": "", "minimum_context": "", "first_question_or_model_shift": "", "embargo": ""},
  "final_contract": {"central_question_resolution": "", "reveal_consequence": "", "knowledge_boundary": "", "hook_payoff": "", "new_model_or_final_image": "", "must_not_open_new_major_topic": true},
  "questions": [
    {"nq_id": "NQ-001", "question": "", "opened_at": "SW-001", "why_care": "", "expected_form": "ANSWER", "payoff_node": "SW-002", "status": "CLOSED"}
  ],
  "reveals": [
    {"nr_id": "NR-001", "reveal": "", "evidence_p_ids": ["#P-001"], "earliest_legal_node": "SW-001", "target_node": "SW-002", "setup_required": "Zasiej wcześniej konkretną obserwację, która stanie się zrozumiała dopiero przy revealu", "do_not_reveal_before": "SW-002", "consequence": "", "uncertainty_form": ""}
  ],
  "viewer_contacts": [
    {"vc_id": "VC-001", "node": "SW-001", "function": "ORIENT", "level": "MICRO", "purpose": "Skieruj uwagę widza na anomalię bez zdradzania odpowiedzi", "risk": "Nie zamieniaj kontaktu w pustą zaczepkę ani manierę", "author_text": "BRAK", "approval": "NOT_REQUIRED", "approval_receipt_relative": "BRAK", "approval_receipt_sha256": "BRAK"}
  ],
  "scene_weave": [
    {"sw_id": "SW-001", "act_id": "ACT-001", "scene_or_unit": "", "function": "", "entry_knowledge_state": "", "exit_knowledge_state": "", "emotional_pressure": "", "required_evidence": [{"p_id": "#P-001", "function": "", "necessity": ""}], "supporting_p_ids": [], "reserve_p_ids": [], "nq_action": "OPEN:NQ-001", "nr_action": "SETUP:NR-001", "local_stake": "", "bridge_out": "", "completion_criteria": ""},
    {"sw_id": "SW-002", "act_id": "ACT-002", "scene_or_unit": "", "function": "", "entry_knowledge_state": "", "exit_knowledge_state": "", "emotional_pressure": "", "required_evidence": [{"p_id": "#P-001", "function": "", "necessity": ""}], "supporting_p_ids": [], "reserve_p_ids": [], "nq_action": "PAY:NQ-001", "nr_action": "REVEAL:NR-001", "local_stake": "", "bridge_out": "", "completion_criteria": ""},
    {"sw_id": "SW-003", "act_id": "ACT-002", "scene_or_unit": "", "function": "", "entry_knowledge_state": "", "exit_knowledge_state": "", "emotional_pressure": "", "required_evidence": [{"p_id": "#P-001", "function": "", "necessity": ""}], "supporting_p_ids": [], "reserve_p_ids": [], "nq_action": "BRAK", "nr_action": "CONSEQUENCE:NR-001", "local_stake": "", "bridge_out": "END", "completion_criteria": ""}
  ],
  "acts": [
    {"act_id": "ACT-001", "label": "HOOK", "act_function": "", "entry_knowledge_state": "", "intended_emotional_pressure_in": "", "exit_knowledge_state": "", "intended_emotional_pressure_out": "", "state_change_evidence": "SW-001", "failure_if_removed": "", "relative_weight": "LIGHT", "exposition_risk": "LOW", "new_names": [], "complexity_flag": "SIMPLE", "scene_weave_ids": ["SW-001"], "open_nq_ids": [], "nq_actions": ["OPEN:NQ-001"], "nr_actions": ["SETUP:NR-001"], "vc_ids": ["VC-001"], "humor_mode": "FORBIDDEN", "narrator_mode": "DEFAULT", "completion_criteria": [""], "bridge_out": "", "do_not_reveal": ["NR-001 przed SW-002"], "constraints": [{"cid": "CID-001", "source_field": "ACT_FUNCTION", "action": "Zrealizuj funkcję aktu, zmianę stanu i most, a completion potraktuj jako kryterium odbioru tej samej transformacji", "object_ids": ["ACT_FUNCTION:ACT-001", "VIEWER_STATE:ACT-001", "BRIDGE:ACT-001", "COMPLETION:001"], "why_hard": "Akt musi zmienić model widza", "atomicity_reason": "Jedna zależna transformacja aktu z jednym kryterium odbioru", "verification": "Stan wyjściowy, most i kryterium są spełnione"}, {"cid": "CID-002", "source_field": "SW", "action": "Zrealizuj scenę i wymagany dowód", "object_ids": ["SW:SW-001", "REQUIRED:SW-001/#P-001"], "why_hard": "Scena bez dowodu nie działa", "atomicity_reason": "Dowód zasila tę samą scenę", "verification": "SW i karta występują razem"}, {"cid": "CID-003", "source_field": "NQ", "action": "Otwórz pytanie", "object_ids": ["NQ:OPEN:NQ-001"], "why_hard": "Pytanie napędza dalszy ciąg", "atomicity_reason": "Jedna akcja pytania", "verification": "NQ jest otwarte"}, {"cid": "CID-004", "source_field": "NR", "action": "Przygotuj reveal bez przedwczesnego ujawnienia", "object_ids": ["NR:SETUP:NR-001", "DO_NOT_REVEAL:001"], "why_hard": "Reveal wymaga przygotowania i embarga", "atomicity_reason": "Setup i embargo dotyczą jednego revealu", "verification": "Jest setup, brak ujawnienia"}, {"cid": "CID-005", "source_field": "VC", "action": "Zorientuj widza", "object_ids": ["VC:VC-001"], "why_hard": "Kontakt ma funkcję orientującą", "atomicity_reason": "Jedna funkcja kontaktu", "verification": "VC realizuje ORIENT"}, {"cid": "CID-006", "source_field": "HUMOR_MODE", "action": "Nie używaj humoru w tym akcie", "object_ids": ["HUMOR_MODE:ACT-001"], "why_hard": "Humor osłabiłby funkcję hooka", "atomicity_reason": "Jeden zakaz tonu", "verification": "Akt nie zawiera humoru"}, {"cid": "CID-007", "source_field": "CONTINUITY_OUT", "action": "Zwróć pełny CONTINUITY_OUT", "object_ids": ["CONTINUITY_OUT:ACT-001"], "why_hard": "Bez stanu nie wolno odblokować kolejnego aktu", "atomicity_reason": "Jeden obowiązek protokołu", "verification": "OUT przechodzi schemat"}]},
    {"act_id": "ACT-002", "label": "FINAŁ", "act_function": "", "entry_knowledge_state": "", "intended_emotional_pressure_in": "", "exit_knowledge_state": "", "intended_emotional_pressure_out": "", "state_change_evidence": "SW-003", "failure_if_removed": "", "relative_weight": "MEDIUM", "exposition_risk": "LOW", "new_names": [], "complexity_flag": "SIMPLE", "scene_weave_ids": ["SW-002", "SW-003"], "open_nq_ids": ["NQ-001"], "nq_actions": ["PAY:NQ-001"], "nr_actions": ["REVEAL:NR-001", "CONSEQUENCE:NR-001"], "vc_ids": [], "humor_mode": "ALLOWED", "narrator_mode": "DEFAULT", "completion_criteria": [""], "bridge_out": "END", "do_not_reveal": [], "constraints": [{"cid": "CID-001", "source_field": "ACT_FUNCTION", "action": "Zrealizuj funkcję finału, zmianę stanu i zakończenie, a completion potraktuj jako kryterium odbioru tej samej transformacji", "object_ids": ["ACT_FUNCTION:ACT-002", "VIEWER_STATE:ACT-002", "BRIDGE:ACT-002", "COMPLETION:001"], "why_hard": "Finał ma zmienić model, nie streszczać", "atomicity_reason": "Jedna transformacja finału z jednym kryterium odbioru", "verification": "Stan końcowy, END i kryterium są spełnione"}, {"cid": "CID-002", "source_field": "SW", "action": "Zrealizuj scenę revealu i wymagany dowód", "object_ids": ["SW:SW-002", "REQUIRED:SW-002/#P-001"], "why_hard": "Payoff musi być udowodniony", "atomicity_reason": "Dowód zasila scenę revealu", "verification": "SW i karta występują razem"}, {"cid": "CID-003", "source_field": "SW", "action": "Zrealizuj scenę konsekwencji i wymagany dowód", "object_ids": ["SW:SW-003", "REQUIRED:SW-003/#P-001"], "why_hard": "Reveal bez konsekwencji jest pustą informacją", "atomicity_reason": "Dowód zasila scenę konsekwencji", "verification": "Konsekwencja zmienia stan widza"}, {"cid": "CID-004", "source_field": "NQ", "action": "Wypłać pytanie", "object_ids": ["NQ:PAY:NQ-001"], "why_hard": "Obietnica wymaga odpowiedzi", "atomicity_reason": "Jedna akcja payoffu", "verification": "NQ jest zamknięte"}, {"cid": "CID-005", "source_field": "NR", "action": "Ujawnij reveal", "object_ids": ["NR:REVEAL:NR-001"], "why_hard": "Reveal musi zmienić model widza", "atomicity_reason": "Jedna akcja ujawnienia", "verification": "NR ujawnione w SW-002"}, {"cid": "CID-006", "source_field": "NR", "action": "Pokaż konsekwencję revealu", "object_ids": ["NR:CONSEQUENCE:NR-001"], "why_hard": "Reveal bez skutku jest pustą informacją", "atomicity_reason": "Jedna późniejsza akcja konsekwencji", "verification": "Konsekwencja występuje w SW-003"}, {"cid": "CID-007", "source_field": "CONTINUITY_OUT", "action": "Zwróć pełny CONTINUITY_OUT", "object_ids": ["CONTINUITY_OUT:ACT-002"], "why_hard": "Łańcuch musi zostać domknięty", "atomicity_reason": "Jeden obowiązek protokołu", "verification": "OUT przechodzi schemat"}]}
  ],
  "k2b": {"decision": "NIEUSTALONE", "reason": "", "gaps": []}
}
```
<!-- NARRATIVE_V2_JSON_END -->

## Handoff

- K2 kończy się, gdy każdy akt zmienia stan, każde REQUIRED ma funkcję i `SW_ID`, wszystkie pytania i reveale mają legalny cykl łącznie z późniejszą konsekwencją, każdy akt ma semantyczne completion criteria, a density gate przepuszcza maksymalnie siedem atomowych CID łącznie z `CONTINUITY_OUT`.
- `RESERVE` jest niewidoczne dla K3. Awans wymaga jawnej decyzji K2/K2B i zmienia projekcję aktu, nie kanoniczny hash 01.
- `COMPLEXITY_FLAG` wynika z zależności poznawczych, nie długości.
- Kontakt autorski (`AUTHOR` albo `AUTHORIAL`) wymaga dosłownego tekstu Dawida i ważnego receipt utworzonego przed walidacją; zwykły kontakt ma `author_text: BRAK` i `NOT_REQUIRED`.

## Changelog

- R1:
