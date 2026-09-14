# Role i odpowiedzialność

NARRATIVE_V2_CONTRACT: 2026-08-31_NARRATIVE_V2

| Rola | Własność | Nie wolno |
|---|---|---|
| Dawid | W0, kierunek K2, polityka czasu, exact AUTHOR_TEXT, profil głosu, K5, A/B, aktywacja | zastępować jego decyzji automatem |
| ChatGPT/Codex | K0, K1, K2, K2B, kompilatory, walidacja, trzy runy K4 | pisać prozy K3 w kanonicznym przebiegu, udawać akceptacji Dawida |
| Claude | jeden akt K3 w świeżym kontekście | K1/K2/K4/K5, modyfikacja packetu, własny continuity attest |
| System lokalny | locki, hashe, schematy, receipts, kompilacja | oceniać semantyki, której nie potrafi dowieść deterministycznie |

## Narrative V2

- Claude otrzymuje stabilny prefix i wyłącznie pakiet jednego aktu. Zwraca `PACKET_INSUFFICIENT`, beat sheet dla COMPLEX albo prozę zgodną z formatem.
- Constraint preflight, beat preflight, continuity attest, EDITOR, VERIFY, COLD_READER i QA impact wykonuje ChatGPT/Codex jako niezależne runy z własnymi task ID.
- Ten sam model nie może wystawić dowodu za dwie niezależne role w jednym tasku.
- K4 EDITOR nie zatwierdza faktów; VERIFY nie redaguje dla rytmu; COLD_READER nie widzi planu ani źródeł.
- Dawid zatwierdza exact tekst, nie abstrakcyjną intencję. Receipt jest audytowalnym zapisem decyzji, nie kryptograficznym dowodem tożsamości.

## Override

Zmiana właściciela wymaga `Approve-OwnerOverride.ps1`, konkretnego powodu, zakresu i receiptu związanego z projektem. Pole wpisane ręcznie albo odziedziczone z innego projektu jest nieważne.

## Tor legacy

Projekty `2026-08-30_K1_LITE_V2` zachowują dotychczasowy podział, ale również obowiązuje wyłączność Dawida na decyzje i zakaz ręcznego fałszowania stanu. Narrative V2 nie rozszerza automatycznie ich kontraktu.
