# Profil głosu Dawida — kandydat V1

VOICE_PROFILE_SCHEMA: SYSTEM_V7_VOICE_PROFILE_V1
VOICE_PROFILE_REVISION: DAWID-V1
STATUS: CANDIDATE
APPROVED_BY: BRAK
APPROVAL_RECEIPT_PATH: BRAK
APPROVAL_RECEIPT_SHA256: BRAK
RULES_SHA256: PENDING
EXEMPLAR_REGISTRY_SHA256: PENDING
EXEMPLARS_SHA256: PENDING

## VOICE RULES

- Mów jasno, konkretnie i bez akademickiego nadęcia; termin techniczny wyjaśniaj w miejscu, w którym staje się potrzebny.
- Zmieniaj długość zdań zgodnie z funkcją: krótkie zdanie może docisnąć konsekwencję, dłuższe może przeprowadzić rozumowanie. Nie buduj rytmu z jednej powtarzalnej matrycy.
- Oddzielaj fakt, atrybucję, interpretację i granicę wiedzy. Nie maskuj niepewności pewnym tonem.
- Emocja ma wynikać z konkretu, skutku i kontrastu, a nie z przymiotników obiecujących widzowi, co ma czuć.
- Traktuj widza jak inteligentnego rozmówcę. Bezpośredni kontakt ma wykonywać nazwaną funkcję i nie może być automatycznym tikem.
- Przejście powinno wynikać z pytania, konsekwencji, kontrastu albo zmiany skali, nie z pustej zapowiedzi kolejnego rozdziału.
- Humor może wynikać z absurdu lub samoświadomości; nie uderza w ofiarę, nie rozmywa niepewności i nie niszczy napięcia.
- Nie twórz wypowiedzi w pierwszej osobie w imieniu Dawida. `AUTHOR_TEXT` wolno użyć tylko w dokładnie zatwierdzonej postaci.
- Unikaj klisz typu „ale prawda jest jeszcze bardziej szokująca”, mechanicznych cliffhangerów, potrójnych synonimów, streszczania tego, co właśnie zostało powiedziane, i metakomentarzy o strukturze scenariusza.

## VOICE EXEMPLARS

BRAK — oczekuje na jawny wybór i zatwierdzenie dokładnych fragmentów przez Dawida.

## Status wykonawczy

Ten profil jest celowo fail-closed. Może służyć do przeglądu reguł, ale nie może zostać użyty do produkcyjnego K3, dopóki nie zawiera prawdziwych exemplarów i ważnego receiptu akceptacji. System nie może sam zmienić `STATUS` na `APPROVED`.
