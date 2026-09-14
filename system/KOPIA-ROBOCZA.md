# Kopia robocza — optymalizacja PDF/OCR i K1

Ta kopia została utworzona 2026-09-14 na polecenie Dawida. Nie zastępuje instalacji produkcyjnej i nie zmienia statusu PILOT_ONLY. Oryginał pozostaje w E:\projektyoutube\Produkcja tekstów\System-v7.0.

Źródłem pełnej kopii było 335 plików, w tym .git. Manifest oryginału znajduje się w ../original-sha256.json. Nie uruchamiaj git push z tej kopii bez sprawdzenia skopiowanej konfiguracji repozytorium.

## Wprowadzone usprawnienia

1. Convert-PdfToMarkdown.ps1 automatycznie korzysta z projektowego `_work/K1/k1-lite/page-cache.sqlite3`. Nie jest to źródło dowodów ani akceptacja OCR. Zapis następuje po każdej poprawnie odczytanej stronie; awaria bazy powoduje odczyt bez cache. Uszkodzone wpisy są przeliczane. Klucz obejmuje hash PDF, stronę, metodę, wersję PyMuPDF, kod konwertera, a dla OCR także plik wykonywalny Tesseract, modele językowe, wersję, języki, DPI i PSM. Jeżeli lokalizacji modeli nie da się potwierdzić, ponowne wykorzystanie OCR jest wyłączone. Końcowy wynik zachowuje format i kontrolę oryginału. Istniejących opublikowanych plików nie nadpisujemy; ponowienie zakończonej konwersji wymaga nowego WorkDirectory, ale korzysta ze wspólnego cache.
2. Invoke-K1LiteV2.ps1 -Action NextWork zwraca pierwsze niewykonane zadanie, numer kontynuacji, ścieżkę niezmienionego pakietu, wcześniej zgłoszonych kandydatów i hash dziennika. Nie zapisuje niczego ani nie uruchamia modelu. ANALYSIS_COMPLETE_REVIEW_REQUIRED oznacza koniec odczytu, nie zaliczenie K1.
3. -Action ImportBatch -ResultPaths przyjmuje do 100 plików wynikowych w podanej kolejności. Odczytuje źródło raz; każdy wynik przechodzi normalną walidację. Wyniki kolejnych kontynuacji muszą zachować kolejność. Zapis dziennika następuje po walidacji całej partii, a błąd zapisu wycofuje nowe pliki receiptów. Wywołuj przez wrapper PowerShell, który trzyma blokadę projektu, tak jak przy pojedynczym imporcie.
4. -Action Plan -CandidateLimit 4 (lub 8) tworzy nowy przebieg z większym limitem kandydatów na odpowiedź. Limit jest zapisany w planie i instrukcji, respektowany przy imporcie i weryfikacji dziennika. Domyślnie nadal 2; stare przebiegi bez pola pozostają zgodne. Większy limit jest eksperymentem jakościowym, nie globalnie zatwierdzoną polityką. Nie zmieniaj limitu w istniejącym run.json.
5. Obliczanie pokrycia grupuje zdarzenia jednokrotnie zamiast przeszukiwać cały dziennik osobno dla każdego fragmentu.

## Obsługa

Używaj wrapperów z tej kopii oraz wyłącznie izolowanych projektów testowych do czasu ostatecznego przeglądu. Najpierw NextWork; jeżeli jest zadanie, przeczytaj pełny wskazany pakiet, uwzględnij continuation_no i poprzednich kandydatów. Importuj wynik z aktualnym hashem dziennika. ImportBatch służy zebranym wynikom, nie uruchamia analizy modelowej. Przy odrzuceniu partii żaden wynik z niej nie jest opublikowany.

## Zachowane zabezpieczenia i granice

Pełne pokrycie źródeł, dosłowne cytaty, lokalizatory, visual QA, decyzje Dawida, kontrola zmian wejść i kompilator kanonicznej bazy pozostają wymagane. Nie przenosimy automatycznie interpretacji między różnymi briefami. Nie wprowadzono RAGFlow ani zamiany OCR na Docling; nie ma jeszcze porównania jakości uzasadniającego taką zamianę. Cache oszczędza ponowną konwersję, nie przyspiesza samego pierwszego odczytu trudnego skanu. Nie dodano rozliczeń API ani opłat.
