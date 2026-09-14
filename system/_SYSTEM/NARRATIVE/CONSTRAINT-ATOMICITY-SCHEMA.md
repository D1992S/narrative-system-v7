# Constraint Atomicity Preflight

SCHEMA: CONSTRAINT_ATOMICITY_PREFLIGHT_V1

Oceniaj wyłącznie atomowość i kompletność `CONSTRAINT_LEDGER` względem `ACT_PACKET`. Nie pisz prozy.

PASS wymaga jednocześnie:

- najwyżej siedmiu CID łącznie;
- dokładnie jednego protokołowego CID `CONTINUITY_OUT`;
- osobnego CID dla każdego niezależnego NQ, NR, VC i konkretnego embarga;
- `ACT_FUNCTION + VIEWER_STATE + BRIDGE` wolno połączyć jako jedną transformację aktu; dokładnie jedno `COMPLETION` może być jej kryterium odbioru;
- `SW + wszystkie REQUIRED należące do tego samego SW` tworzą jedną nierozdzielną, udowodnioną scenę;
- `NR:SETUP + jedno embargo` wolno połączyć tylko wtedy, gdy embargo wskazuje dokładnie ten sam `NR`; reveal i consequence zawsze są osobnymi CID;
- osobnego CID dla `HUMOR_MODE: FORBIDDEN` i każdego niedomyślnego `NARRATOR_MODE`;
- braku innych połączeń; proza w `atomicity_reason` nie może zalegalizować grupy, której nie dopuszcza powyższa zamknięta lista;
- braku konfliktu między obowiązkami;
- zgodności `OBJECT_IDS` z packetem.

Zwróć wyłącznie:

```text
VERDICT: PASS|FAIL
UNBUNDLED_CONSTRAINT_COUNT: <rzeczywista liczba atomowych CID po zastosowaniu wyłącznie trzech legalnych grup zależnych; 1–7>
MISSING_ACTIONS: <BRAK albo lista>
BUNDLED_ACTIONS: <BRAK albo lista CID>
CONFLICTS: <BRAK albo lista>
REASON: <konkretnie>
```
