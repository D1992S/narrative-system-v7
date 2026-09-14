# 04B — NIEZALEŻNY FACT-CHECK CHATGPT VERIFY

AKTUALNY_WERDYKT: NIEURUCHOMIONY
DRAFT_REVISION:
DRAFT_SHA256:
DATE:
MODEL/OSOBA: ChatGPT VERIFY
VERIFY_AGENT_ID:
VERIFY_TASK_ID:
BRAK_UDZIAŁU_W_K3: DO POTWIERDZENIA
ŹRÓDŁA_DOSTĘPNE: NIE
K4_QA_SCHEMA: THREE_LENS_QA_V1
VERIFY_RUN_RECEIPT: BRAK
VERIFY_PROOF_STATUS: MISSING

## Zakres

- Zgodność twierdzeń z przypisanymi źródłami:
- Cytaty (100%):
- Prawo/zdrowie/pieniądze (100%):
- Nośne daty, liczby i nazwiska (wyrywkowo):
- Nowe konkrety po poprawkach (100%):

## Rejestr

Dozwolone wyniki: `POTWIERDZONE`, `CZĘŚCIOWO`, `ZGODNE ZE ŹRÓDŁEM — NIEZWERYFIKOWANE`, `SPRZECZNE`, `NIEZGODNE ZE ŹRÓDŁEM`, `NIE DOTYCZY`.

| ID | Lokalizacja draftu | Twierdzenie | Karta/źródło | Zgodność ze źródłem | Status faktograficzny | Minimalna korekta narracji | Rozstrzygnięcie |
|---|---|---|---|---|---|---|---|
| FC-001 |  |  |  |  |  |  |  |

Każda unikalna karta `#P` użyta w drafcie musi wystąpić w kolumnie „Karta/źródło”. Dla `SPRZECZNE` i `NIEZGODNE ZE ŹRÓDŁEM` pole „Rozstrzygnięcie” ma format `POPRAWIONE: <konkretny opis>` albo `DAWID=TAK; DECYZJA=<konkretny opis>`; dla pozostałych wpisz konkretną decyzję lub `NIE DOTYCZY`.

## Kontrola zmian po QA

- Rewizja:
- SHA-256:
- Nowe konkrety:
- Wynik:

## Werdykt

W rewizji NARRATIVE_V2 po zakończeniu utwórz wspólny receipt runu narzędziem `New-NarrativeRunReceipt.ps1`. Receipt wiąże fizyczny bundle z zamkniętego profilu `VERIFY_SOURCE_FIRST_V1`, wynik, draft, bazę dowodów i źródła. Stary `New-K4VerifyReceipt.ps1` pozostaje wyłącznie dla walidacji wcześniejszej rewizji.
