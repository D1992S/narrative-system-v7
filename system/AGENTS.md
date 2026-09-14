# Instrukcje wykonawcze System-v7.0

NARRATIVE_V2_CONTRACT: 2026-08-31_NARRATIVE_V2
NARRATIVE_V2_STATUS: PILOT_ONLY

## Start każdej pracy

1. Odczytaj bieżący `meta.md` projektu i fizyczne pliki etapu.
2. Ustal `WORKFLOW_REVISION`, `CURRENT_STAGE`, `LAST_GATE`, właściciela, origin i status blokady.
3. Dla `2026-08-31_NARRATIVE_V2` stosuj `_SYSTEM/NARRATIVE/NARRATIVE-CONTRACT-V2.md` oraz narzędzia V2.
4. Dla `2026-08-30_K1_LITE_V2` stosuj tor legacy. Nie mieszaj templatek, receiptów ani walidatorów między rewizjami.
5. Nowe projekty twórz domyślnym `New-Project.ps1`, wyłącznie w `2026-08-31_NARRATIVE_V2` (wybór Dawida z 2026-09-12). Jedyna Biblia to `BIBLIA/`. Rewizja `2026-08-30_K1_LITE_V2` jest zachowana tylko dla istniejących projektów i testów zgodności. Jeszcze starsze rewizje są validation-only; jawna rejestracja legacy umożliwia wyłącznie ich walidację i nie przywraca mutacji.

## Własność

- Dawid: W0, decyzja kierunku, zgoda na czas, exact `AUTHOR_TEXT`, profil głosu, K5, A/B i aktywacja produkcyjna.
- ChatGPT/Codex: K0, K1, K2, K2B, kompilatory, walidatory i K4.
- Claude: wyłącznie proza K3. Nie zleca się Claude’owi K4 ani decyzji Dawida.
- `OWNER_OVERRIDE` wymaga jawnego receiptu. Nie wolno wpisać akceptacji człowieka na podstawie założenia.

## Pipeline

`W0 → K0 → K1 → K2 → K2B → K3 → K4 → K5 → COMPLETE`

- Etap przechodzi wyłącznie przez `Advance-Stage.ps1` po pozytywnym walidatorze i komplecie receiptów.
- `BLOCKED` wymaga `Block-Project.ps1`; powrót wymaga `Unblock-Project.ps1`. Ręczna zmiana meta jest nieważna.
- Reopen w V2 wykonuje tylko `Reopen-Stage.ps1` po dozwolonej trasie i z kodem przyczyny.

## K1 i źródła

- Aktywne materiały trafiają bezpośrednio do `sources/`; techniczne oryginały tylko do `sources/_oryginaly/`.
- K1 Lite V2 działa w izolowanym runie. Kanoniczne `01-baza-dowodow.md` powstaje dopiero przez kompilator po pełnym pokryciu i walidacji.
- K2B może dołączyć suplement add-only; nie wolno ręcznie nadpisać opublikowanego K1.
- Karta dowodu musi zachować dosłowny fragment, źródło, lokalizację i granicę pewności. Routing lub streszczenie nie jest dowodem.

## Narrative V2

- K2 używa `STORY_ENGINE_V2`, NQ/NR/VC, Scene Weave oraz jednego zamkniętego ledgeru CID.
- Maksymalnie siedem atomowych CID na akt. Tylko trzy grupy zależne są legalne: transformacja ACT z jednym completion; SW z jego REQUIRED; SETUP NR z jednym embargiem tego samego NR. Modelowy PASS nie omija kontroli maszynowej.
- V2 nie używa budżetów słów, znaków, ekspozycji ani rozdziału. Czas jest GUIDE lub jawnie zatwierdzonym HARD_MAX.
- Profil głosu musi przejść `Approve-VoiceProfile.ps1`, a projekt `Set-VoiceProfileForProject.ps1`. Nie wolno ręcznie ustawić `APPROVED`.
- Model K3 i ustawienia zamraża `Set-K3ModelManifest.ps1`. Zmiana wymaga `Rebase-K3Model.ps1` i regeneracji.
- Każdy akt powstaje w świeżym kontekście. Wymagane są constraint preflight, dla COMPLEX także beat preflight, a po prozie niezależny continuity attest.
- Kolejny akt nie rusza przed ważnym attestem poprzedniego. Draft składa wyłącznie `Assemble-K3Draft.ps1`.
- K4 to trzy niezależne runy: EDITOR, VERIFY, COLD_READER. Nie wolno przekazywać COLD_READEROWI architektury ani źródeł.
- K5 V2 jest byte-identical. Jakakolwiek zmiana narracji otwiera K3.

## Tekst mówiony

- Finalny skrypt to sama narracja: bez nagłówków technicznych, tabel, komentarzy, kart wymowy i śladów `#P`.
- Fakt, atrybucja, interpretacja i granica wiedzy muszą być rozdzielone.
- Nie wolno kopiować charakterystycznych fraz exemplarów. VC i humor mają wynikać z funkcji, nie z norm ilościowych.
- Inline stage directions, SFX i instrukcje wykonawcze w prozie są zabronione.

## Bezpieczeństwo zmian

- Najpierw inwentaryzacja i walidacja, potem mutacja pod lockiem, zapis atomowy, postwalidacja i rollback przy błędzie.
- Nie usuwaj ani nie nadpisuj pracy użytkownika bez jawnej zgody. Nie poprawiaj wyników projektu testowego, gdy zadaniem jest ulepszenie systemu.
- Nie ogłaszaj PASS na podstawie samego istnienia pliku. Podawaj fizyczne wyniki testów, hashe i znane bramki ludzkie.
- Narrative V2 pozostaje `PILOT_ONLY`, dopóki Dawid nie zatwierdzi A/B 2/3 i aktywacji.
