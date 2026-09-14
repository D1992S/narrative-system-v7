# W0 — POMYSŁ I ŹRÓDŁA

**Właściciel:** Dawid. **Wsparcie:** ChatGPT.  
**Wejście:** pomysł, luźne materiały, wiedza o kanale.  
**Wyjście:** decyzja GO/GO WARUNKOWE/NO-GO, katalog projektu i źródła gotowe do K0.

## Cel

Sprawdzić, czy temat ma wystarczającą ciekawość, konflikt, materiał źródłowy i pojemność narracyjną, zanim system zainwestuje czas w celowany research K1.

## Ocena pomysłu

Oceń w skali 0–3:

1. **Pytanie:** czy da się je wypowiedzieć jednym zdaniem?
2. **Stawka:** co widz traci, zyskuje lub rozumie inaczej?
3. **Napięcie:** jakie dwie siły, wersje lub wartości się ścierają?
4. **Materiał źródłowy:** czy istnieje dość treści, aby opowiedzieć pełną historię, nawet jeśli źródła są wtórne, kontrowersyjne albo niepotwierdzone?
5. **Bohater/ruch:** kto czego chce i co mu przeszkadza?
6. **Pojemność narracyjna:** czy materiał daje sceny, decyzje, zwroty, mechanizmy albo odkrycia, a nie tylko listę informacji?
7. **Nowość dla widza:** co odróżnia narrację od najbardziej dostępnej wersji tematu?
8. **Dopasowanie kanału:** czy widz rozpozna obietnicę kanału?
9. **Ryzyko:** prawo, zdrowie, osoby żyjące, ofiary, materiały drastyczne, aktualność.

Wynik nie jest mechanicznym werdyktem. Niska klasa źródeł sama nie blokuje tematu. Blokować może brak materiału, brak możliwości wskazania jego pochodzenia albo ryzyko prawne lub etyczne.

## Postać źródeł

K1-Lite V2 `2.1.0` skanuje aktywne materiały PDF, Markdown, TXT, SRT i VTT. Pliki przeznaczone do badania leżą bezpośrednio w `sources/`:

- automatyczną parą jednego materiału jest wyłącznie PDF i jego kanoniczny `<nazwa>--TEXT.md`, który deklaruje hash tego PDF; każdy inny aktywny MD/TXT/SRT/VTT wymaga własnego runu, a zbędną kopię techniczną przenosi się do `_oryginaly/`;
- `sources/_oryginaly/` przechowuje wyłącznie zaplecze materiału już reprezentowanego aktywnym źródłem i nie jest skanowane;
- film może pozostać SRT/VTT z odtwarzalnymi znacznikami albo mieć kanoniczną transkrypcję tekstową;
- PDF z warstwą tekstową może wejść do skanu i selekcji, ale bez odpowiadającego mu sprawdzalnego tekstu zablokuje później `ManualCheckCards: 0`;
- zalecany nagłówek tekstowego źródła: `ŹRÓDŁO-TYTUŁ`, `ŹRÓDŁO-AUTOR`, `ŹRÓDŁO-DATA`, `ŹRÓDŁO-TYP`.

Analiza nie zmienia oryginalnego PDF. Konwersja tworzy obok kanoniczny MD z mapą fizycznych stron, a OCR Tesseract działa tylko na stronach bez wystarczającego tekstu natywnego. Każda zmiana źródła unieważnia zależny run i wymaga ponownego planu.

## Gotowość źródeł

- [ ] Utworzono `sources/` oraz `sources/_oryginaly/`.
- [ ] Wszystkie aktywne materiały przeznaczone do skanu leżą w `sources/`, a pary formatów są rozpoznawalne jako jeden materiał logiczny.
- [ ] `_oryginaly/` nie zawiera jedynej kopii materiału potrzebnego do researchu.
- [ ] Jest przynajmniej jeden wystarczająco pojemny filar źródłowy albo kilka uzupełniających się materiałów.
- [ ] Twierdzenia wrażliwe mają rozpoznanego autora/źródło i są oznaczone do kontroli w K4.
- [ ] Pliki mają czytelne nazwy; duplikaty i artefakty techniczne są rozpoznane.
- [ ] Ustalono `SOURCES_ONLY` albo `SOURCES_PLUS_WEB_AFTER_CONFIRMATION`.
- [ ] Dla nowego projektu `K1_RESEARCH_MODE` ma `K1_LITE_V2`; fallback wymaga osobnej decyzji i konkretnego powodu.
- [ ] Aktywna praca odbywa się w nowym/bieżącym projekcie z ważnym `.system-v7/project-origin.json`. `.system-v7/legacy-origin.json` służy wyłącznie walidacji archiwalnej; legacy nie może wejść do W0 ani zmieniać stanu.

## Werdykt

- `GO` — pomysł i źródła wystarczają do K0.
- `GO WARUNKOWE` — lista konkretnych braków ma właściciela i termin.
- `NO-GO` — brak wystarczającego materiału źródłowego, pojemności narracyjnej, odrębności albo akceptowalnego ryzyka. Sam brak niezależnego potwierdzenia teorii nie jest powodem `NO-GO`.

Szkielet projektu istnieje już na W0. Dawid zapisuje decyzję jako dane wejściowe, ale nie zmienia ręcznie stanu:

- przy `GO`: `W0_CONDITIONS: BRAK`, `W0_CONDITION_STATUS: NOT_APPLICABLE`, a wynik, data i oba pola receiptu pozostają `BRAK`;
- przy `GO WARUNKOWE`: `W0_CONDITIONS` ma format `WARUNEK=<min. 10 znaków>; OWNER=<osoba>; TERMIN=YYYY-MM-DD`, `W0_CONDITION_STATUS: OPEN`, a pola zamknięcia pozostają `BRAK`;
- do chwili przejścia `LAST_GATE` pozostaje `PROJECT_INITIALIZED`.

Najpierw uruchom `Advance-Stage.ps1` jako podgląd, a po PASS `Advance-Stage.ps1 -Apply -DawidApproved`. Dopiero narzędzie zapisuje `W0_GO` albo `W0_GO_WARUNKOWE` i przechodzi do K0. Warunek może pozostać `OPEN` w K0, ale musi zostać zamknięty przez `Close-W0Condition.ps1 -DawidApproved` przed przejściem K0 → K1. `NO-GO` zapisuje wyłącznie `Block-Project.ps1 -NoGo -DawidApproved`, z `LAST_GATE: W0_NO_GO`. Nie pisze się jeszcze tezy filmu.
