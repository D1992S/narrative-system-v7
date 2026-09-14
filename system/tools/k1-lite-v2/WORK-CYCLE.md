# Cykl K1 ograniczający powtarzanie pracy

Wersja transportu: `K1_WORK_TASK_V1` / `K1_WORK_REPLY_V1`. Działa lokalnie i nie uruchamia LLM, nie korzysta z API ani nie przyznaje akceptacji dowodów. Domyślny limit kandydatów nadal wynosi 2. `ledger.jsonl` pozostaje źródłem prawdy.

Nowe zadania mają `input_revision: 2`: wejście zawiera wymagane pola kandydata, dozwolone statusy i regułę pustego `probe_answers: {}` dla kontynuacji. Pierwsza odpowiedź nadal musi zawierać odpowiedzi PROBE. Tekst źródła pozostaje pełny. Już przygotowane zadania bez tego pola zachowują wejście i identyfikator w rewizji 1; ich kontynuacje również wymagają pustego `probe_answers` zgodnie z walidatorem, mimo starszej ogólnej instrukcji w pakiecie. Nie przepisuj zapisanego `input.md` ręcznie.

## Podstawowa obsługa

W katalogu tej kopii ustaw ścieżki do izolowanego projektu i jego istniejącego runu:

```powershell
$tool = Join-Path (Get-Location) 'tools\k1-lite-v2\Invoke-K1WorkCycle.ps1'
$project = 'E:\projektyoutube\_work\system-optimization-20260914\projekty-testowe\Nazwa filmu'
$run = Join-Path $project '_work\K1\k1-lite-v2\run-001'
$task = & $tool -Action Prepare -ProjectDirectory $project -RunDirectory $run | ConvertFrom-Json
```

`READY_FOR_WORK` zwraca `task_id`, `input_path`, `response_path`. Worker czyta cały `input_path` i zapisuje jeden JSON odpowiedzi. Ten plik zawiera cały tekst kanonicznego fragmentu ze znacznikami, brief i zasady. Pominięto tylko techniczne nagłówki run/hash i żądanie telemetryki; oryginalny pakiet nie jest zmieniany. Znaczenie dowodów, cytaty, fakty i odpowiedzi kontrolne nadal pochodzą od workera.

```powershell
& $tool -Action Accept -ProjectDirectory $project -RunDirectory $run `
  -TaskId $task.task_id -ResultPath $task.response_path
```

Po `IMPORTED` można wywołać kolejne `Prepare`. Odpowiedź zawiera już wskazanie następnego fragmentu bez ponownego parsowania źródła w tym samym wywołaniu. `ANALYSIS_COMPLETE_REVIEW_REQUIRED` kończy kolejkę analizy, ale nie przegląd i kompilację bazy.

Powtórne `Prepare` bez odpowiedzi zwraca to samo zadanie jako `WAITING_FOR_RESPONSE`. Nie wysyłaj go automatycznie jeszcze raz. Kontynuuj istniejącą pracę albo rozstrzygnij, czy wynik został dostarczony. Nie ma automatycznego wygasania zadania ani niejawnego ponawiania LLM.

## Awaria i odzyskiwanie

```powershell
& $tool -Action Recover -ProjectDirectory $project -RunDirectory $run -TaskId $task.task_id
& $tool -Action Status -ProjectDirectory $project -RunDirectory $run
```

- `RETRY_LOCAL` / `CONFIRMATION_PENDING`: odpowiedź jest zachowana; użyj `Recover`, bez nowej analizy.
- `ALREADY_IMPORTED`: dziennik i receipt potwierdzają ten sam wynik; niczego nie dopisano drugi raz.
- `NEEDS_CORRECTION`: odpowiedź zachowano; przeczytaj plik `detail_path` i popraw wskazany problem.
- `STALE_OR_BLOCKED` / `STALE_OR_SUPERSEDED`: wejście lub stan zadania zmieniły się; nie generuj automatycznie kolejnej odpowiedzi. Sprawdź przyczynę, zachowując dawny wynik.
- `ERROR`: operacja nie została bezpiecznie zakończona. Nie interpretuj błędu jako prośby o ponowny LLM.

Surowe odpowiedzi są zapisywane atomowo przed walidacją w `jobs/<task_id>/aNNNNNN-<SHA>.json`. Oryginalny JSON jest zachowany również przy błędzie cytatu lub nieaktualnym źródle. Kanoniczne wyniki i diagnostyka są osobnymi plikami. Żadne wyniki nie są nadpisywane. Uszkodzony plik lub zmienione wejście blokuje użycie.

Zapis używa atomowego tworzenia plików przez hard link; testowano na NTFS. Na systemie plików bez tej możliwości zapis kończy się błędem zamiast stosowania niebezpiecznego nadpisania. Blokady są zwalniane przez system operacyjny po zakończeniu procesu. Resztki nieopublikowanych `.work-*.tmp` po zabiciu procesu nie są traktowane jako wyniki.

## Krótka odpowiedź modelu

```json
{
  "schema": "K1_WORK_REPLY_V1",
  "task_id": "identyfikator otrzymanego zadania",
  "status": "CANDIDATE",
  "more_strong_candidates": false,
  "probe_answers": {},
  "candidates": []
}
```

To schemat kształtu, nie gotowy poprawny wynik: status, kandydaci i odpowiedzi PROBE muszą odpowiadać rzeczywistemu zadaniu. Dla braku kandydatów status to `SCANNED_NO_CANDIDATE`; dla dalszych mocnych dowodów `PARTIAL_OVERFLOW` i `more_strong_candidates: true`. Struktura kandydata pozostaje taka jak w `templates/worker-result.example.json`.

Adapter uzupełnia znane hashe i identyfikatory. Tokeny pozostają `UNAVAILABLE`; zera są wymaganym technicznym zapisem braku pomiaru, nie deklaracją zerowego zużycia. Opcjonalne `-Model` i `-Effort` opisują uzgodnione wykonanie; bez nich model jest `UNSPECIFIED`. Pełny wynik V1 pozostaje obsługiwany dla zgodności; jego pomiary powinny pochodzić z wykonania, nie ze zgadywania przez model.

## Naprawa pojedynczych kandydatów

Diagnostyka wskazuje błędne identyfikatory i pełną stronę źródła, o ile lokalizacja należy do fragmentu. Gdy brakuje kontekstu, wróć do całego niezmienionego wejścia. Naprawa może zawierać:

```json
{
  "schema": "K1_WORK_REPAIR_V1",
  "task_id": "identyfikator zadania",
  "base_response_sha256": "SHA pierwotnej odpowiedzi z diagnostyki",
  "replacements": [{"local_id": "A", "quote": "...", "claim": "..."}]
}
```

Każdy zamiennik musi zawierać kompletną kartę kandydata ze wszystkimi wymaganymi polami. Nie wolno dodać/usunąć kandydata ani zmienić ID, pokrycia, PROBE lub numeru kontynuacji tą operacją. Poprawiona całość przechodzi ponownie normalną walidację. Łańcuchy napraw nie są obsługiwane: kolejna poprawka odnosi się do oryginalnej odpowiedzi i zawiera wszystkie potrzebne zamienniki albo jest nową kompletną odpowiedzią.

## Walidacja partii

`PreviewBatch -ResultPaths` przyjmuje zapisane kanoniczne wyniki V1, odczytuje źródło raz i zwraca `valid_inputs` z hashami oraz konkretne błędy. Nie publikuje wyników. Poprawne pliki pozostają dostępne. Jawnie wybraną poprawną partię publikuje dotychczasowy `Invoke-K1LiteV2.ps1 -Action ImportBatch`; kontrola „wszystko albo nic” pozostaje.

Import utrwala manifest transakcji przed receiptami. Dzięki temu ponowienie tej samej operacji może wykorzystać własne osierocone receipty po przerwaniu. Nie adoptuje obcych plików ani plików z inną zawartością. Błąd po wymianie ledgera nie usuwa receiptów, na które dziennik już się powołuje.

Historię manifestów odczytuje się przy odzyskiwaniu istniejących receiptów, również gdy w międzyczasie przyjęto inny fragment. Zwykły import nowego wyniku nie skanuje tej historii. Uszkodzony manifest potrzebny do odzyskiwania blokuje operację czytelnym błędem lokalnym. Błędy odczytu, zapisu wyniku i raportu diagnostycznego prowadzą do `RETRY_LOCAL`, bez prośby o nową analizę. Ścieżki projektu i blokady przez dowiązania/junction są odrzucane przed zapisem blokady.

## Próba 2 kontra 4

Etap jakościowy pozostaje oddzielny: nowe runy z identycznego źródła/briefu i parametrów dzielenia, jeden z `-CandidateLimit 2`, drugi z `4`. Porównuj ten sam krótki fragment i to samo wykonanie modelu. Limit jest maksimum, nie nakazem tworzenia tylu kart. Maksymalnie cztery rzeczywiste wywołania łącznie; bez ukończenia obu wariantów wynik jest nierozstrzygający. Obecny adapter plikowy nie uruchamia ani nie liczy wywołań dostawcy, więc tej granicy musi pilnować operator lub przyszły adapter wykonania.

Nie uruchomiono modelowego A/B przy wdrażaniu kodu. Nie ma potwierdzonego procentu oszczędności tokenów ani zgody na domyślne 4/8. W pierwszej kolejności wdrożenie usuwa powtarzanie poprawnie zapisanej pracy i ogranicza metadane odpowiedzi.
