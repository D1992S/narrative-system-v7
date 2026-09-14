# Protokół ślepego testu A/B Narrative V2

STATUS_PROTOKOŁU: GOTOWY_DO_UŻYCIA
WORKFLOW_REVISION: 2026-08-31_NARRATIVE_V2
AKTYWACJA_V2: PILOT_ONLY

## Cel

Test odpowiada wyłącznie na pytanie, czy Narrative V2 daje Dawidowi lepszą narrację niż gałąź legacy przy tych samych źródłach, fundamencie i modelu. Nie służy do automatycznej aktywacji systemu i nie zastępuje oceny prawdziwości materiału.

## Trzy obowiązkowe benchmarki

1. Historia dokumentalna oparta na źródłach, z konfliktem relacji albo stopniami pewności.
2. Historia postaci lub zdarzenia, w której najważniejsze są przemiana, przyczynowość i payoff.
3. Materiał złożony albo kontrowersyjny, wymagający kontrargumentu, granicy wiedzy i świadomego kontaktu z widzem.

Każdy benchmark używa identycznej bazy dowodów, identycznego fundamentu K0, tego samego modelu i tej samej wersji materiału wejściowego. Nie wolno poprawiać tylko jednej wersji po zobaczeniu wyniku drugiej.

## Procedura

1. Powstają dwie wersje: legacy i Narrative V2.
2. Osoba przygotowująca test losuje oznaczenia `TEKST A` i `TEKST B` oraz zapisuje mapowanie poza kartą oceny.
3. Dawid czyta oba teksty bez informacji, który powstał w V2.
4. Dla każdej pary ocenia w skali 1–5: ciekawość, klarowność, przyczynowość, napięcie i payoff, naturalność głosu, brak lania wody, uczciwość wobec źródeł oraz chęć dalszego oglądania.
5. Dawid wybiera zwycięzcę pary albo remis i krótko podaje powód.
6. Dopiero po zapisaniu oceny odsłania się mapowanie.

## Warunek rekomendacji aktywacji

Narrative V2 może zostać zarekomendowany do aktywacji dopiero, gdy:

- wygra co najmniej 2 z 3 benchmarków;
- nie pogorszy uczciwości wobec źródeł ani prawidłowego oznaczania niepewności;
- nie uzyska żadnego zwycięstwa dzięki dopisaniu faktów bez pokrycia;
- Dawid jawnie zatwierdzi zmianę po obejrzeniu pełnych wyników.

Remis, brak trzech ocen albo niejednoznaczna tożsamość wejść oznacza `NOT_RUN` albo `INCONCLUSIVE`, nigdy automatyczne `PASS`.

## Granica automatyzacji

Narzędzia mogą przygotować pary, policzyć oceny i sprawdzić kompletność. Nie mogą wystawić ocen za Dawida, podrobić ślepego wyboru ani zmienić `PILOT_ONLY` na podstawie testu technicznego.
