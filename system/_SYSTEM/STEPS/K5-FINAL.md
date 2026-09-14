# K5 — FINALNA DECYZJA I CZYSTA NARRACJA

Właściciel decyzji: Dawid. Narrative V2 nie pozwala zamaskować późnej zmiany prozy jako wcześniejszego PASS.

## Wejście V2

K5 wymaga:

- CURRENT_STAGE: K5 i LAST_GATE: K4_PASS;
- aktualnego 03-draft.md z kompletną mapą techniczną;
- ważnego K4 proof set dla dokładnego SHA draftu;
- ważnego continuity chain wszystkich aktów;
- 04 i 04B skompilowanych z aktualnych outputs;
- braku PREFIX_STALE, MODEL_STALE i CONTINUITY_STALE;
- rozliczonego trybu czasu.

## Czysty final

05-FINAL-SCRIPT.md zawiera metadane techniczne poza sekcją mówioną, a sekcja NARRACJA DO NAGRANIA jest byte-identical z czystym eksportem 03. W narracji nie może być:

- nagłówków rozdziałów ani etykiet aktów;
- BLOCK_ID, #P, tabel, JSON i komentarzy;
- didaskaliów, SFX, instrukcji montażu i kart wymowy;
- dodatkowego zdania nieobjętego K3/K4.

Approve-K5FinalV2.ps1 sprawdza pełne wiązanie i tworzy receipt decyzji Dawida. Bez -DawidApproved nie powstaje akceptacja.

## Długość

GUIDE nie ma dolnego progu i nie blokuje. HARD_MAX blokuje K5, jeśli rzeczywista narracja go przekracza. System nie rozciąga ani nie skraca automatycznie tekstu do czasu. Zmiana HARD_MAX wymaga Set-DurationPolicy.ps1 i decyzji Dawida.

## Zmiana po K4

Każda zmiana narracji po atestach otwiera K3. Zmiana faktu, modalności, revealu, struktury, obietnicy lub sceny wymaga ponownego atestu dotkniętych aktów i właściwych soczewek. Nie wolno wpisać CONTINUITY_STATUS: PASS ręcznie.

Dawid zachowuje pełne prawo do zmiany tekstu. Jeżeli wybiera publikację wersji zmienionej bez re-atestu, system może ją oznaczyć CONTINUITY_UNVERIFIED, ale nie nadaje K5_PASS ani COMPLETE. Poprawna integracja wymaga formalnego reopen.

## Bramka

- final jest czystą narracją i odpowiada aktualnemu draftowi;
- proof set, raporty i continuity są aktualne;
- VERIFY zachowuje atrybucję i poziom pewności;
- brak technicznego residue;
- HARD_MAX spełniony, jeśli aktywny;
- Dawid jawnie zaakceptował dokładne bajty finalu;
- Approve-K5FinalV2.ps1 zwraca ważny receipt;
- Validate-Project.ps1 zwraca PASS.

Po PASS przejście K5 → COMPLETE wykonuje wyłącznie Advance-Stage.ps1 -Apply. Stan końcowy to CURRENT_STAGE: COMPLETE, LAST_GATE: K5_PASS i STAGE_OWNER: Dawid.

## Rewizja wcześniejsza

Dla 2026-08-30_K1_LITE_V2 obowiązuje Approve-K5Final.ps1 i receipt tej rewizji. Nie jest on wymienny z K5 receipt Narrative V2.
