# Narrative System v7 + panel

Jedno repozytorium zawierające system produkcji narracji dokumentalnych oraz jego lokalny panel monitorujący. Obie części są wersjonowane wspólnie, ponieważ panel korzysta z tych samych reguł walidacji co system.

Status jakości: **Narrative V2 / PILOT_ONLY**. Zapisanie kodu na GitHubie nie zastępuje testu jakości A/B, zgód Dawida ani aktywacji produkcyjnej. Istniejące odcinki zachowują swoje pliki, origin i rewizję.

## Struktura

| Folder | Zawartość |
|---|---|
| `system/` | System-v7.0: Biblia, instrukcje, szablony, narzędzia, schematy, testy i zgodność ze starszymi projektami |
| `panel/` | Panel tylko do odczytu, wraz z kontrolami K1–K5 i testami |
| `docs/` | Informacje o pochodzeniu wersji i jej weryfikacji |

Repozytorium obejmuje kod i zasady działania. Nie zawiera prywatnych źródeł odcinków, gotowych scenariuszy, logów rozmów, cache OCR ani konfiguracji uwierzytelnienia. PDF w `system/_SYSTEM/NARRATIVE/TEST-FIXTURES/` jest małym materiałem testowym systemu.

## Wymagania

- Windows 10/11, Python 3.10+ z Tkinter; testowano na Python 3.11.
- PowerShell 7.5+ (`pwsh` w PATH); testowano na 7.6.6.
- PyMuPDF: `python -m pip install -r requirements.txt`.
- Node.js do testów logiki interfejsu; panel nie wymaga Node do działania.
- Tesseract oraz odpowiednie modele językowe do OCR skanów. Instalacja OCR jest opisana w [warstwie PDF](system/tools/k1-lite/README.md).

Nie są potrzebne klucze API do działania panelu ani do lokalnych testów opisanych poniżej.

## Uruchomienie panelu

Dwuklik `panel/Panel.bat`, następnie wybór istniejącego folderu projektu Narrative V2. Można też przeciągnąć folder projektu na plik BAT.

Z terminala w katalogu repozytorium:

```powershell
python -B -X utf8 panel/panel.py "D:\Moje odcinki\Nazwa projektu"
```

Panel odczytuje kod z `system/` obok siebie. Nie zależy od położenia repozytorium na dysku E. Nie zmienia projektu i nie uruchamia modelu. Nie należy zmieniać rewizji starego projektu tylko po to, żeby otworzyć go w panelu.

Panel pokazuje aktywność dostępną w lokalnych logach Codex/Claude Code. To wniosek z logów, nie bezpośredni pomiar działania modelu. Okresowe odświeżanie, walidacja dowodów i wskazywanie nieaktualnych danych są opisane w [notatce wydania](docs/RELEASE-2026-09-14.md).

## Nowy projekt

Zacznij od [system/START.md](system/START.md) i [zasad systemu](system/AGENTS.md). Przykład z katalogu repozytorium:

```powershell
& ./system/tools/New-Project.ps1 -ProjectName "Nazwa filmu" -DestinationRoot "D:\Moje odcinki" -TargetMinutes 45 -TargetDurationMode GUIDE -NarrativeV2Pilot
```

Zalecane jest przechowywanie odcinków poza repozytorium. Lokalny folder `projects/` jest również wykluczony z Git. Nie podmieniaj instalacji obsługującej istniejący projekt bez sprawdzenia jego originu i zgodności.

## Testy

```powershell
python -B -X utf8 panel/tests/test_panel.py
node panel/tests/test_frontend.cjs
pwsh -NoProfile -File system/tools/Test-NarrativeV2.ps1
```

Testy korzystają z lokalnych fixture'ów i nie wymagają generowania odpowiedzi LLM. Pełny zestaw narzędzi i dodatkowe testy: [system/tools/README.md](system/tools/README.md).

## Wersjonowanie i bajty plików

`.gitattributes` wyłącza automatyczne przepisywanie końców linii. System wiąże instrukcje, cytaty i receipty hashami, dlatego checkout musi zachować oryginalne bajty. Nie uruchamiaj automatycznego formatowania całego systemu.

Dokumenty wewnątrz `system/` zachowano bajtowo, wraz z historycznymi ścieżkami i opisem kopii roboczej. W tym repozytorium punktem wejścia jest niniejszy README; aktualne położenie kodu to `system/`. Repozytorium nie kopiuje historycznego katalogu `.git` ani danych tymczasowych.

## Automatyczna kontrola na GitHubie

W zakładce **Actions → Kontrola systemu i panelu** znajdziesz wynik ostatniego sprawdzenia. Kontrola uruchamia się po zmianach na `main`, przy pull requestach i przez przycisk **Run workflow**.

- Ruff przegląda Python, a PSScriptAnalyzer PowerShell w systemie, panelu i skryptach CI.
- Wykonywane są testy panelu, JavaScript, K1, cache PDF i pełnego procesu Narrative V2.
- Podsumowanie pokazuje liczbę uwag; pełne raporty JSON można pobrać jako artefakt przez 7 dni. Zielony wynik oznacza przejście testów i brak błędów blokujących, nie brak wszystkich ostrzeżeń.
- Kontrola niczego nie poprawia automatycznie i nie używa LLM-a.
- Dependabot co tydzień proponuje aktualizacje bibliotek Python i akcji. Pull requesty wymagają przeglądu; nie ma automatycznego scalania.

Szczegóły i ograniczenia: [docs/AUTOMATYCZNA-KONTROLA.md](docs/AUTOMATYCZNA-KONTROLA.md).
