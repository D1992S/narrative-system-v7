# K2B — CELOWANA NAPRAWA I SUPLEMENT

Właściciel: ChatGPT/Codex. K2B nie jest drugim pełnym researchem. Zmienia najmniejszy zakres potrzebny do uczciwego przejścia K3.

## Wejście

K2B może wynikać z luki wykrytej w K2 albo z formalnego PACKET_INSUFFICIENT po Reopen-Stage. Raport musi wskazywać dotknięte ACT/SW/NQ/NR/VC/P i konkretną przyczynę. Ręczna zmiana CURRENT_STAGE jest nieważna.

## Kolejność decyzji

1. Usuń sprzeczność lub błąd mapowania, jeśli materiał już istnieje.
2. Zmniejsz zakres albo rozdziel przeciążony akt.
3. Jeżeli legalna karta RESERVE rozwiązuje lukę, jawnie zmień jej rolę w K2 i przebuduj projekcję wyboru.
4. Dopiero przy realnym braku uruchom celowany run K1 Lite V2 dla konkretnego źródła lub pytania.

Claude nie promuje RESERVE i nie wykonuje K2B.

## Suplement źródłowy

Każdy nowy materiał przechodzi pełny run, przegląd redakcyjny Dawida, bramki obrazu/tekstu i ValidateRun. Następnie:

1. Merge-K1LiteV2Supplement.ps1 Preview;
2. jawne Publish z ExpectedCanonicalSha256;
3. kopia odzyskiwania i nowy publish receipt wskazujący poprzedni;
4. ponowny GATE_READY całego 01;
5. punktowa aktualizacja 02;
6. Validate-Architecture.ps1;
7. Build-K3PacketsV2.ps1;
8. walidacja zakresu inwalidacji;
9. Advance-Stage.ps1.

Suplement jest add-only. Nie wolno usuwać ani przepisywać istniejących kart po cichu.

## Inwalidacja Narrative V2

- zmiana karty użytej przez akt przebudowuje EVIDENCE_SELECTION i paczkę tego aktu oraz jego downstream continuity;
- zmiana nieużytej karty rewaliduje korpus, ale nie regeneruje niepowiązanej prozy;
- lokalna zmiana ACT_PROJECTION zachowuje wcześniejsze akty;
- zmiana globalnego Story Spine, profilu głosu, modelu albo prefixu unieważnia cały K3;
- zmiana wcześniejszego revealu lub stanu wymaga rebase późniejszych aktów;
- każda ścieżka zapisuje receipt reopen i niezmienny zakres archiwizacji.

K2B nie tworzy limitów słów ani znaków. Jeśli film po uczciwej naprawie nie mieści się w GUIDE, Dawid decyduje o zakresie. HARD_MAX zmienia wyłącznie Set-DurationPolicy.ps1.

## Bramka

- luka ma dokładny zakres i właściciela;
- 01 pozostaje kanoniczne, add-only i GATE_READY;
- 02 ponownie przechodzi STORY_ENGINE_V2;
- żaden RESERVE nie trafił bez jawnej zmiany roli;
- wszystkie zależne paczki i atesty są właściwie STALE albo przebudowane;
- zmiana lokalna nie naruszyła wcześniejszych artefaktów;
- Validate-Project.ps1 zwraca PASS dla K2B.

## Rewizja wcześniejsza

Dla 2026-08-30_K1_LITE_V2 stosuje się jej istniejący Merge, paczki i validator. Nie wolno przenosić do niej schematów continuity V2 ani odwrotnie.
