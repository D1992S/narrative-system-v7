# MANDAT DAWIDA

Dawid jest redaktorem naczelnym i właścicielem finalnej decyzji o narracji. System ma ograniczać jego pracę techniczną, ale nie odbierać mu decyzji artystycznej i odpowiedzialności.

## Obowiązkowe decyzje

1. W0 — GO / GO WARUNKOWE / NO-GO; przy `GO WARUNKOWE` także jawne zamknięcie warunku przed przejściem K0 → K1.
2. K2 — wybór kierunku.
3. K5 — finalna akceptacja tekstu.

To są trzy decyzje bramkowe całego filmu. W interaktywnym K1 Dawid otrzymuje krótkie partie najmocniejszych, pobocznych i kontrowersyjnych kandydatów. Kanał ChatGPT może nadać `KEY_CHATGPT`, ale nie zastępuje decyzji Dawida:

- `MUST_INCLUDE` — kandydat koniecznie w bazie;
- `IMPORTANT_SIDE` — ważny kandydat poboczny;
- `REJECTED` — kandydat nie wchodzi do bazy i ta decyzja ma pierwszeństwo przed `KEY_CHATGPT`;
- brak decyzji Dawida nie jest dorozumianą zgodą ani odrzuceniem; nieodrzucone `KEY_CHATGPT` pozostaje jawną rekomendacją modelu;
- przed publikacją Dawid czyta deterministyczny `editorial-review.md` obejmujący najmocniejsze, ryzykowne i kontrowersyjne kandydatury, `KEY_CHATGPT`, konflikty, pokrycie K0, klasy źródeł i `STOP_REASON`;
- po rzeczywistym przeglądzie Dawid wystawia receipt `K1_LITE_V2_EDITORIAL_REVIEW_RECEIPT_V1` z `actor: DAWID`, `verdict: REVIEWED`, hashem snapshotu i SHA-256 konkretnego artefaktu; receipt nie oznacza dorozumianego zatwierdzenia każdego kandydata;
- tylko Dawid może potwierdzić konflikt dotyczący wybranego kandydata; ChatGPT nie może wykonać tego w jego imieniu;
- po zmianie kandydatów, rekomendacji, decyzji lub konfliktów Dawid musi przeczytać nowy widok i wystawić nowy receipt; sama zmiana kontroli obrazu nie unieważnia przeglądu;
- samo `Publish` nadal wymaga sześciu bramek, w tym `editorial_review_ready`, świeżego `ValidateRun` i zgodnych hashy.
- publikacja tworzy osobny `K1_LITE_V2_PUBLISH_RECEIPT_V1`; receipt redakcyjny nie zastępuje publish receiptu ani odwrotnie.

## Dodatkowe decyzje tylko przy ryzyku

- zmiana zakresu,
- słabe lub sprzeczne źródła,
- użycie zarzutu lub treści wysokiego ryzyka w narracji,
- publikacja pochodnego MD z PDF oraz użycie OCR na jawnie wskazanych stronach; oryginalnego PDF nie wolno nadpisywać,
- awaryjne odejście od K1-Lite V2 potwierdzone przez `Approve-K1ManualFallback.ps1 -DawidApproved`; pola meta bez aktualnego `SYSTEM_V7_K1_MANUAL_FALLBACK_RECEIPT_V1` nie wystarczają,
- zastępstwo właściciela etapu potwierdzone przez `Approve-OwnerOverride.ps1 -DawidApproved`,
- zamknięcie warunku W0 przez `Close-W0Condition.ps1 -DawidApproved`,
- blokada lub wznowienie projektu przez `Block-Project.ps1` i `Unblock-Project.ps1` z `-DawidApproved`; oba ruchy zostawiają deterministyczny łańcuch niezmiennych receiptów, którego aktualny head pozostaje wskazany w `meta.md`,
- jeden kierunek K2, akceptacja Q1 albo Q2 w QA oraz decyzja wobec sprzecznego fact-checku — zawsze przez `Approve-EditorialException.ps1 -DawidApproved` po zapisaniu deklaracji w artefakcie;
- w Narrative V2: dokładny AUTHOR_TEXT, wybór i zatwierdzenie VOICE EXEMPLARS, ewentualny HARD_MAX, świadome powtórzenie ruchu otwarcia/zamknięcia, wynik A/B i aktywacja produkcyjna. Narrative V2 nie ma wyjątku od budżetu aktu, ponieważ nie ma budżetów aktów.

## Dawid nie musi

- ręcznie liczyć słów,
- przenosić plików,
- scalać raportów,
- zatwierdzać każdego akapitu,
- szukać ponownie karty już przypisanej przez K2.

Dawid nie musi weryfikować technicznie hashy ani dosłowności kart. Robi to walidator; wynik `ManualCheckCards: 0` nie może zostać zastąpiony deklaracją ręcznego sprawdzenia.

Dawid może zażądać dowolnej zmiany finalnej narracji. System nie odbiera mu tej decyzji, ale w Narrative V2 zmiana znacząca po atestach ma jawny stan CONTINUITY_UNVERIFIED i nie może zostać przedstawiona jako K5_PASS. Poprawną trasą jest formalny reopen, ponowny atest dotkniętych aktów i właściwe soczewki K4.

## Odpowiedzialność końcowa

Dawid odpowiada za finalne brzmienie narracji, sposób przedstawienia bohaterów oraz decyzję, czy tekst jest gotowy. W Narrative V2 publiczne `Approve-K5Final.ps1 -DawidApproved` deleguje do `Approve-K5FinalV2.ps1` i zapisuje zamknięty `SYSTEM_V7_K5_APPROVAL_V2`, związany z aktualnym `K4_PROOF_SET_V2`, continuity chain, draftem, raportami i finałem. Utrzymany tor `2026-08-30_K1_LITE_V2` zachowuje osobny receipt V1 związany z VERIFY. Stan do `COMPLETE` przesuwa `Advance-Stage.ps1 -Apply`. Wpis `DAWID=TAK` bez zgodnego receiptu nie zatwierdza wyjątku objętego kontrolą systemu. Receipty Dawida są audytowalnymi potwierdzeniami przekazanych decyzji, nie kryptograficznym uwierzytelnieniem jego tożsamości. Wszystkie decyzje realizacyjne podejmuje samodzielnie poza tym systemem.
