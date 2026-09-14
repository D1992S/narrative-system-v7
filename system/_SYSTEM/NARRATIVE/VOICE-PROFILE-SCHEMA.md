# Schemat profilu głosu

SCHEMA: SYSTEM_V7_VOICE_PROFILE_V1

Profil jest centralnym, wersjonowanym źródłem `VOICE_RULES` i `VOICE_EXEMPLARS`. Nie nadaje modelowi prawa do tworzenia osobistych stanowisk Dawida.

## Zamknięte pola nagłówka

- `VOICE_PROFILE_SCHEMA`
- `VOICE_PROFILE_REVISION`
- `STATUS`: `CANDIDATE` albo `APPROVED`
- `APPROVED_BY`: przy aktywnym profilu wyłącznie `DAWID`
- `APPROVAL_RECEIPT_PATH`
- `APPROVAL_RECEIPT_SHA256`
- `RULES_SHA256`
- `EXEMPLAR_REGISTRY_SHA256`
- `EXEMPLARS_SHA256`

## VOICE RULES

Reguły opisują formalność, rozkład długości zdań, przejście fakt → interpretacja, niepewność, emocję, relację z widzem, przejścia, humor, użycie `ja/my/ty` oraz zakazane maniery. Nie zawierają liczbowych norm kontaktów, humoru ani długości rozdziału.

## VOICE EXEMPLARS

Sekcja `VOICE EXEMPLARS` zawiera dokładnie jeden kanoniczny obiekt JSON `VOICE_EXEMPLAR_REGISTRY_V1`. Każdy dosłowny fragment ma zamknięty rekord: `exemplar_id`, `project_name`, `artifact_path`, `artifact_sha256`, `exact_text_sha256`, `approval_status: DAWID_APPROVED`, `demonstrates[]` i `exact_text`. Łącznie rekordy muszą pokrywać funkcje: `STRONG_OPENING`, `SCENE`, `UNCERTAINTY`, `KNOWLEDGE_BOUNDARY`, `VIEWER_CONTACT`, `TRANSITION` i `PAYOFF`.

Produkcyjny `artifact_path` musi wskazywać fizyczny `05-FINAL-SCRIPT.md` projektu posiadającego prawidłowy origin. Hash artefaktu i dosłowna obecność fragmentu są sprawdzane ponownie przy każdym użyciu profilu. Draft, książka, tekst konkurencyjnego kanału, ścieżka bez originu albo ręcznie ustawiony status bez kanonicznego receiptu zawsze dają FAIL.

Receipt `SYSTEM_V7_VOICE_PROFILE_APPROVAL_V1` wiąże rewizję, profil, hashe reguł, rejestru i skompilowanych exemplarów oraz każdy rekord źródłowy. `STATUS: APPROVED` bez tego receiptu nie jest akceptacją.

Łączny materiał powinien zwykle mieć 300–500 słów, ale spójność i pokrycie funkcji są ważniejsze niż mechaniczne trafienie w liczbę. Tekst musi pochodzić z prozy rzeczywiście zaakceptowanej przez Dawida. Fragment z książki, konkurencyjnego kanału, niezatwierdzonego draftu albo wygenerowany jako substytut daje FAIL. Exemplars uczą rozkładu głosu; ich treści, charakterystycznych metafor i fraz nie wolno kopiować.

Zmiana zasad lub choćby jednego bajtu exemplarów wymaga nowej `VOICE_PROFILE_REVISION`. Trwający projekt nie przełącza profilu automatycznie.
