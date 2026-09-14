# Automatyczna kontrola repozytorium

Workflow: `.github/workflows/repository-checks.yml`.

## Obsługa

Po wejściu w Actions wybierz „Kontrola systemu i panelu”. Otwórz uruchomienie, aby zobaczyć podsumowanie i poszczególne kroki. **Run workflow** uruchamia pełną kontrolę ręcznie. Na dole uruchomienia dostępny jest artefakt „raport-kontroli” z raportami JSON.

Kontrola jest uruchamiana na zmianach `main` i pull requestach. Nie uruchamia się według codziennego harmonogramu. Dla tej samej gałęzi/PR nowe uruchomienie zastępuje stare. Jeden job Windows ma limit 20 minut. Artefakty są usuwane po 7 dniach. Korzysta to z limitu minut i przestrzeni GitHub Actions na koncie; konfiguracja nie zmienia płatnego budżetu konta ani nie gwarantuje niewyczerpania darmowego limitu.

## Co oznacza wynik

- **Czerwony**: błąd blokujący analizatora, nieudany test, problem instalacji narzędzi albo pominięta wymagana kontrola.
- **Zielony z ostrzeżeniami**: testy przeszły, ale raport zawiera uwagi do dalszego przeglądu. Zielony nie oznacza „brak błędów w całym systemie”.

Ruff raportuje reguły E4, E7, E9, F i B (Pyflakes oraz Bugbear). Blokujące są E9, F63, F7, F82 i błędy składni. Pozostałe uwagi są zachowane w `ruff.json`. PSScriptAnalyzer raportuje wszystkie domyślne reguły; Error/ParseError blokują, Warning/Information pozostają w `powershell.json`. W interfejsie wyświetla się maksymalnie 20 adnotacji na analizator, lecz pełne raporty zawierają wszystkie wyniki. Są to jawne kryteria pierwszego wdrożenia, bez wyciszania konkretnych plików ani tworzenia listy ignorowanych usterek.

Nie wykonujemy `ruff --fix`, formatowania ani przepisywania plików systemu. Jego manifesty wymagają zachowania bajtów. Interpretacja dokumentów Markdown i jakość narracji nadal wymagają przeglądu merytorycznego; testy systemowe sprawdzają tylko zakodowane kontrakty i scenariusze.

## Testy

Workflow uruchamia istniejące zestawy:

1. `panel/tests/test_panel.py`.
2. `panel/tests/test_frontend.cjs`.
3. `system/tools/k1-lite-v2/tests/Test-K1LiteV2.ps1` (silnik K1, wydajność, work cycle, layout PDF).
4. `system/tools/k1-lite/tests/Test-PdfToMarkdownUnit.py` i `test_page_cache.py`.
5. `system/tools/Test-NarrativeV2.ps1` (pełny proces na izolowanych fixture'ach).

Testy są lokalnymi operacjami na runnerze. Nie wywołują płatnych modeli ani produkcyjnych projektów użytkownika. Testy OCR korzystające z makiet nie zastępują kontroli prawdziwych skanów; nie instalujemy Tesseracta w tym workflow.

## Dependabot

`.github/dependabot.yml` obejmuje pakiety Python z katalogu głównego i używane GitHub Actions. Sprawdza aktualizacje co poniedziałek, grupuje je i ogranicza liczbę zwykłych otwartych PR do dwóch na ekosystem. Osobne alerty bezpieczeństwa zależą od ustawienia Dependabot alerts w repozytorium. Automatyczne scalanie jest wyłączone.

## Uprawnienia

Workflow korzysta z `contents: read`, nie otrzymuje sekretów ani prawa zapisu do kodu. Używa `pull_request`, nie `pull_request_target`. Akcje są przypięte do SHA; Ruff i PSScriptAnalyzer mają określone wersje. Aktualizacje Dependabota wymagają ponownego przejścia testów i przeglądu.
