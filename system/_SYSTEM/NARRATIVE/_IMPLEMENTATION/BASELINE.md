# Baseline wdrożenia NARRATIVE_V2

STATUS: ZAMROŻONY
PLAN_PATH: C:\Users\dawid\OneDrive\Pulpit\FINALNY-PLAN-NARRACJI-SYSTEM-V7.md
PLAN_SHA256: F47D42CDCBF172CA75C1B7C2FA87F41F15586122D1C2708DA46B7226FC30A4B3
PREIMPLEMENTATION_BACKUP: E:\projektyoutube\_BACKUPS\System-v7.0_PRE_NARRATIVE_V2_20260831-133547
BACKUP_SOURCE_FILES: 247
BACKUP_TARGET_FILES: 247
BACKUP_SOURCE_BYTES: 2028564
BACKUP_TARGET_BYTES: 2028564

## Stan początkowy

- Aktywna rewizja przed wdrożeniem: `2026-08-30_K1_LITE_V2`.
- Katalog Git był już zmieniony przed wdrożeniem. Nie wykonano resetu ani cofania cudzych zmian.
- `Test-AdvanceAtomicity.ps1`: PASS.
- `Test-ProjectMutationLocks.ps1`: PASS.
- `Test-System.ps1`: FAIL na błędnym regexie dawnych nazw etapów, który mylił je z priorytetami audytu. To zapisany błąd baseline, nie przemilczany PASS.
- Tymczasowe katalogi testowe po baseline zostały usunięte przez istniejące testy.

Pełny, fizyczny wykaz plików, rozmiarów i hashy znajduje się w `BASELINE-MANIFEST.json`. Manifest jest generowany przez `tools/New-SystemV7Manifest.ps1`; jego agregat obejmuje ścieżkę względną, liczbę bajtów i SHA-256 każdego aktywnego pliku z wyłączeniem `.git`, `_test-run` i `__pycache__`.

## Zasada odzyskania

W razie krytycznej awarii źródłem odtworzenia jest wyłącznie wskazana kopia `PRE_NARRATIVE_V2`. Nie wolno używać `git reset --hard`, ponieważ baseline zawierał wcześniejsze, należące do użytkownika zmiany.
