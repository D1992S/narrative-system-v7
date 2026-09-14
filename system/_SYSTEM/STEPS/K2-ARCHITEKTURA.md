# K2 — STORY ENGINE I ARCHITEKTURA

Właściciel: ChatGPT/Codex. Decyzja kierunku: Dawid. Wyjście: 02-architektura-odcinka.md.

## Routing rewizji

Najpierw odczytaj WORKFLOW_REVISION. Dla 2026-08-31_NARRATIVE_V2 obowiązuje STORY_ENGINE_V2 opisany poniżej. Wcześniejsza rewizja korzysta z własnego template i walidatora; jej pól nie wolno przenosić do V2.

## Wejście

K2 rusza tylko na kanonicznym 01-baza-dowodow.md z GATE_READY, ManualCheckCards: 0, aktualnym publish receiptem albo ważnym receipt fallbacku. Używa wyłącznie kart QA_K1: GOTOWA. REZERWA nie trafia do paczki K3, dopóki K2/K2B nie zmieni jej roli.

Najpierw czytaj fundament, pokrycie, handoff, rdzeń i sceny-kotwice. Pełne karty otwieraj po ID wtedy, gdy są potrzebne do decyzji. K2 nie wykonuje ponownego researchu i nie rozstrzyga prawdziwości tez z pamięci.

## Kierunki i decyzja

Przed architekturą przedstaw 2–3 realnie odmienne kierunki: oś, konflikt, obietnicę, konkrety, karty rdzeniowe, przewagę i ryzyko. Nie twórz sztucznego wariantu. Jeden uczciwy kierunek wymaga decyzji Dawida i aktualnego K2_ONE_DIRECTION receipt.

## Story DNA

Architektura zapisuje:

- CENTRAL_QUESTION i VIEWER_PROMISE;
- STARTING_MODEL, DESTABILIZING_FACT i DEEPER_MODEL;
- HUMAN_STAKE, EXTERNAL_STAKE i VALUE_CONFLICT;
- KNOWLEDGE_BOUNDARY;
- FINAL_TRANSFORMATION i FINAL_IMAGE_OR_THOUGHT;
- zamknięty kontrakt hooka i finału.

Hook ma konkretną anomalię lub konsekwencję, uczciwą obietnicę, znaczenie, minimalny kontekst, pierwsze pytanie lub zmianę modelu i embargo. Finał rozwiązuje centralne pytanie w granicy wiedzy, wypłaca hook i nie otwiera nowego dużego tematu.

## Rejestry

- NQ: pytanie, miejsce otwarcia, dlaczego obchodzi widza, oczekiwana forma odpowiedzi, payoff i status.
- NR: ujawnienie, dowody, najwcześniejszy legalny węzeł, setup, embargo, konsekwencja i forma niepewności.
- VC: opcjonalny kontakt z widzem, jedna funkcja, poziom, cel i ryzyko. AUTHOR/AUTHORIAL wymaga dokładnego AUTHOR_TEXT i receipt Dawida.
- Scene Weave: scena lub jednostka, funkcja, stan wejścia i wyjścia, emocjonalne ciśnienie, REQUIRED z nazwaną funkcją i koniecznością, SUPPORTING, RESERVE, działania NQ/NR, stawka, most i completion criteria.

Zero VC i zero humoru jest legalne. Nie wolno wpisywać liczbowych targetów kontaktów, żartów, nowych nazw ani ekspozycji.

## Akty

Każdy akt:

- zmienia stan wiedzy widza i wskazuje Scene Weave dowodzący tej zmiany;
- ma jedną funkcję, failure_if_removed, względną wagę i ryzyko ekspozycji;
- deklaruje SIMPLE albo COMPLEX;
- przypisuje Scene Weave, otwarte NQ, działania NQ/NR i opcjonalne VC;
- ma HUMOR_MODE, NARRATOR_MODE, completion criteria, most i embarga;
- posiada zamknięty CONSTRAINT_LEDGER z maksymalnie siedmioma atomowymi CID, w tym dokładnie jednym obowiązkiem CONTINUITY_OUT.

CID obejmuje wszystkie obowiązki twarde. Nie wolno ukrywać wielu poleceń w jednym polu albo jednej liście. Tylko legalne grupy zależne mogą współdzielić CID: transformacja aktu z jednym completion, jeden SW z jego REQUIRED oraz setup NR z jednym embargiem tego samego NR. Preflight modelowy nie omija kontroli deterministycznej.

## Długość

V2 nie planuje słów ani znaków per akt. TARGET_MINUTES ma tryb GUIDE albo zatwierdzony HARD_MAX i jest oceniany po napisaniu. relative_weight opisuje ciężar funkcji, nie objętość. Akt kończy się po wykonaniu funkcji i completion criteria; brak materiału prowadzi do PACKET_INSUFFICIENT, nie do wypełniacza.

## Bramka K2

- wybrany kierunek i legalny wyjątek jednego kierunku, jeśli potrzebny;
- STORY_ENGINE_V2 z dokładnym, zamkniętym schematem;
- spójne Story DNA, hook i finał;
- NQ/NR/VC mają legalne węzły i relacje;
- każdy Scene Weave należy do dokładnie jednego aktu;
- każdy REQUIRED istnieje, ma QA_K1: GOTOWA, funkcję i necessity;
- RESERVE nie jest wymaganym wejściem K3;
- każdy akt zmienia stan i ma completion criteria;
- wszystkie obowiązki są pokryte maksymalnie siedmioma atomowymi CID;
- brak pól budżetowych i mieszanego schematu;
- Validate-Architecture.ps1 zwraca ARCHITECTURE_PASS.

Po PASS przejście wykonuje wyłącznie Advance-Stage.ps1.

## Rewizja wcześniejsza

Dla 2026-08-30_K1_LITE_V2 źródłem prawdy pozostają istniejący 02, template tej rewizji i legacy branch Validate-Architecture.ps1. Projektu nie migruje się przez ręczną zmianę WORKFLOW_REVISION.
