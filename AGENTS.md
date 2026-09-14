# Narrative System v7 — repozytorium systemu i panelu

- `system/` zawiera kompletny System-v7.0 wraz z Biblią, szablonami, narzędziami i testami.
- `panel/` to lokalny monitor tylko do odczytu, korzystający z sąsiedniego `system/`.
- Zacznij od `system/START.md` i `system/AGENTS.md`. Wszystkie reguły integralności systemu pozostają obowiązujące.
- Narrative V2 ma status `PILOT_ONLY`; publikacja kodu nie jest akceptacją A/B ani aktywacją produkcyjną.
- Nie migruj rewizji istniejących projektów ani nie podmieniaj ich originów podczas aktualizacji kodu.
- Pliki odcinków, materiały źródłowe, logi sesji, cache i sekrety pozostają poza repozytorium.
- Nie normalizuj końców linii w plikach systemu: manifesty są związane z bajtami. Kontrolowane zmiany instrukcji wymagają właściwego procesu manifestów.
- Testy panelu: `python -B -X utf8 panel/tests/test_panel.py` oraz `node panel/tests/test_frontend.cjs`.
- Test systemu Narrative V2: `pwsh -NoProfile -File system/tools/Test-NarrativeV2.ps1`. Pozostałe testy i zależności opisuje dokumentacja w system/tools.
