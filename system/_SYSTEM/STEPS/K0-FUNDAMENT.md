# K0 — KONTRAKT RESEARCHOWY

**Właściciel:** ChatGPT.  
**Wyjście:** `00-fundament-projektu.md` i zaktualizowany `meta.md`.

## Cel

Przełożyć zatwierdzone W0 na krótki kontrakt, który ogranicza research do potrzeb filmu. K0 nie powtarza analizy wszystkich źródeł i nie wymaga osobnej akceptacji Dawida, jeśli nie zmienia W0.

## Obowiązkowe pola

- pytanie główne, obietnica i konflikt;
- `W FILMIE` oraz `POZA FILMEM`;
- jeden zwięzły `TEMAT ANALIZY K1-LITE V2`, opisujący czego szukać bez przesądzania tezy;
- 4–8 numerowanych celów badawczych `Q-001...`, każdy z priorytetem i hasłami wyszukiwania;
- wątki obowiązkowe;
- `TRYB RESEARCHU` identyczny z `RESEARCH_MODE` w `meta.md`: `SOURCES_ONLY` albo `SOURCES_PLUS_WEB_AFTER_CONFIRMATION`; przy pierwszym trybie `ZGODA NA WEB: NIE`, przy drugim `ZGODA NA WEB: TYLKO PO POTWIERDZENIU DAWIDA`;
- `SOURCE_FIRST_K4`;
- powód eskalacji tylko wtedy, gdy K0 zmienia W0 lub ujawnia nowe ryzyko.

## Cel badawczy steruje analizą

K0 jest miejscem, w którym powstaje zwarty brief dla pełnej analizy K1. Każdy cel dostaje:

- **priorytet** `MUST` albo `OPCJONALNY`;
- **hasła wyszukiwania**: terminy polskie i angielskie, nazwiska własne, warianty pisowni i synonimy, rozdzielone średnikiem;
- **minimalny warunek pokrycia**, czyli co wystarczy, aby uznać cel za zamknięty.

Hasła mają być konkretne. `historia` niczego nie zawęża; `Bimini Road; beachrock; Cayce reading` zawęża. Jeżeli nie potrafisz podać haseł, cel jest jeszcze zbyt ogólny, aby wejść do K1.

Kanał, format, widz, długość, WPM i styl są już zapisane w `meta.md`, profilu kanału lub W0. K0 ich nie kopiuje. To kontrakt researchu, nie drugi brief narracji.

Temat analizy i hasła są wejściem dla K1-Lite V2, ale nie dowodem. Jeżeli źródła są w innym języku, dodaj oczywiste odpowiedniki nazw i terminów w języku materiałów. W systemowym przebiegu K1 przekazuj dokładny katalog projektu, aby run pozostał w jego `_work/K1/k1-lite-v2/`.

Cel badawczy jest pytaniem potrzebnym do decyzji K2, nie hasłem typu „zbadaj temat”. Każdy cel powinien wskazywać, co zmieni odpowiedź i kiedy można uznać go za pokryty.

## Czego K0 nie ustala

- finalnej tezy i zwycięskiej interpretacji;
- punktu zwrotnego i kolejności aktów;
- finalnego hooka;
- prawdziwości materiału źródłowego;
- liczby kart K1.

## Eskalacja do Dawida

Wróć do Dawida tylko wtedy, gdy K0:

- zmienia pytanie lub obietnicę W0;
- rozszerza albo zawęża zakres w sposób wpływający na film;
- ujawnia nowe ryzyko prawne/etyczne;
- wymaga webu albo materiału, na który nie ma zgody.

## Bramka K0

- [ ] Wszystkie obowiązkowe pola są konkretne.
- [ ] Jest 4–8 testowalnych celów `Q-...`.
- [ ] Jest konkretny `TEMAT ANALIZY K1-LITE V2` zgodny z pytaniem i granicą filmu.
- [ ] Każdy cel ma priorytet i konkretne hasła wyszukiwania.
- [ ] Granica `W FILMIE/POZA FILMEM` jest jednoznaczna.
- [ ] Zakres i cele respektują parametry czasu zapisane w `meta.md`.
- [ ] Fundament nie zmienia W0 albo zmiana ma decyzję Dawida.
- [ ] `POLITYKA WERYFIKACJI: SOURCE_FIRST_K4`.
- [ ] Nagłówek ma `STATUS: GOTOWY` i `ZGODNOŚĆ_Z_W0: POTWIERDZONA`.
- [ ] Sekcja bramki ma `WERDYKT: PASS`.

Jeżeli W0 miało `GO WARUNKOWE`, przed przejściem do K1 uruchom `Close-W0Condition.ps1 -DawidApproved`; status musi być `CLOSED`, a receipt aktualny. Po PASS uruchom `Advance-Stage.ps1` jako podgląd, a następnie z `-Apply`. Narzędzie ustawia `CURRENT_STAGE: K1`, `STAGE_OWNER: ChatGPT` i `LAST_GATE: K0_PASS`.
