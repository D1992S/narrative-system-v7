# AUDYT WYDAJNOŚCI I ZUŻYCIA ZASOBÓW — SYSTEM v7.0 / NARRATIVE V2

Data: 2026-09-12  
Rewizja dokumentu: **2 — po krytycznej weryfikacji**  
Zakres: `E:\projektyoutube\Produkcja tekstów\System-v7.0`  
Status: **POPRAWIONY AUDYT; USPRAWNIENIA SYSTEMU NIEWDROŻONE**  
Obowiązujący workflow nowych projektów: `2026-08-31_NARRATIVE_V2`; status jakości: `PILOT_ONLY`.

Na polecenie Dawida poprawiono wyłącznie audyt. Poniższe propozycje nie są nowymi instrukcjami wykonawczymi ani zgodą na zmianę projektów, parametrów modeli, bramek, manifestów lub historii Git. Pierwotny raport zachowano bez zmiany bajtów w [kopii oryginału](../../_work/krytyka-audytu-wydajnosci-20260912/AUDYT-WYDAJNOSCI-ORYGINAL.md).

## 0. Werdykt krytycznej analizy

Pierwotny audyt jest wartościową listą miejsc do sprawdzenia, ale **nie nadawał się do wdrożenia punkt po punkcie**. Trafnie wskazuje kopiowanie źródeł VERIFY, limit kandydatów K1, trudne komunikaty błędów i problemy nawigacji. Nie dowodzi jednak deklarowanych strat tokenów, rzeczywistego braku cache ani opłacalności proponowanych zmian.

Najpoważniejsze korekty dotyczą zaleceń, które mogłyby obniżyć wiarygodność systemu:

1. **W-06:** brak flagi ryzyka PDF nie dowodzi poprawnej ekstrakcji. Nie znosimy visual QA na tej podstawie.
2. **W-10:** rozmiar i czas modyfikacji nie zastępują hasha treści w bramce integralności.
3. **W-15:** model zadeklarowany w projekcie nie jest dowodem modelu faktycznie wykonującego run. Nie wypełniamy automatycznie metadanych wykonania wartościami oczekiwanymi.
4. **W-05:** nie ograniczamy źródeł VERIFY do sztywnych okien bez możliwości sprawdzenia kontekstu i oryginału.
5. **W-03/W-11:** uporządkowanie plików nie jest jeszcze transportem promptu; zmiana budowniczego nie oznacza automatycznie unieważnienia wszystkich wcześniejszych bundle. Z kolei nowy `RunId` zmienia tożsamość manifestu.
6. **W-01:** narzucone LF wymaga uwzględnienia pliku z mieszanymi końcami linii, już poprawnie związanego z manifestem.

Priorytet mają odtwarzalność stanu, działające wejście do dokumentacji i poprawny pomiar. Zmiany ograniczające kontrolę jakości wymagają osobnego dowodu, że nie pogarszają wykrywania błędów. Brak takiego dowodu nie oznacza zakazu optymalizacji; oznacza, że dana propozycja jest eksperymentem, a nie gotową poprawką.

## 1. Zakres dowodów i pomiar kontrolny

### 1.1 Co sprawdzono ponownie

Odczytano aktualne `AGENTS.md`, Konstytucję, Pipeline, kontrakt Narrative V2, dokumenty i fragmenty implementacji powiązane z W-01–W-20. Wykonano niezależny od narzędzi systemu spis plików i hashy, kontrolę 58 wpisów manifestu, odczyt efektywnych atrybutów Git, analizę AST 84 skryptów PowerShell i kontrolę odwołań wskazanych w audycie. Dodatkowo sprawdzono punkt startowy dokumentacji, co ujawniło W-21.

Dowody kontroli zapisano poza instalacją:

- [snapshot-before.json](../../_work/krytyka-audytu-wydajnosci-20260912/snapshot-before.json): spis plików z SHA-256, parametry pomiaru, Git, manifest i statystyki;
- [snapshot.py](../../_work/krytyka-audytu-wydajnosci-20260912/snapshot.py): odczytowy skrypt odtwarzający te pomiary, JSON na standardowym wyjściu;
- [ast.json](../../_work/krytyka-audytu-wydajnosci-20260912/ast.json): wynik parsera PowerShell;
- [verification-final.json](../../_work/krytyka-audytu-wydajnosci-20260912/verification-final.json): porównanie drzewa przed i po korekcie dokumentu.

Nie uruchomiono ponownie pełnej regresji ani modeli. Nie skanowano korpusów odcinków w poszukiwaniu anonimowego zbioru wykorzystanego przez autora raportu. Wyniki jego pomiarów pozostają oznaczone jako historycznie raportowane, a nie ponownie potwierdzone. Audyt dokumentu nie daje nowego statusu `TECHNICAL PASS`, akceptacji głosu ani wyniku A/B.

### 1.2 Wyniki bieżącej kontroli

Stan **przed zastąpieniem audytu**, z oryginalnym audytem w spisie. Wyłączenia spisu: katalogi `.git` i `__pycache__`. Liczby nie są kosztem kontekstu modelu.

| Pomiar | Wynik i znaczenie |
|---|---|
| Pliki systemu | 190; 2 653 545 bajtów |
| PowerShell | 84 pliki; 1 981 756 bajtów |
| Dokumenty operacyjne `.md` | 67; 255 862 bajty; bez `AUDYT-*`, fixtures i compatibility |
| Składnia PowerShell | 84 pliki, 0 błędów AST; PowerShell 7.6.5 |
| Manifest instrukcji | 58/58 hashy zgodnych |
| Wpisy manifestu śledzone w indeksie Git | 41; pozostałe 17 nieśledzonych |
| Końce linii w manifeście | 57 plików bez CRLF; `TEMPLATES/PROJECT/meta.md` ma 21 CRLF i 60 samych LF |
| Atrybuty `text` i `eol` dla wpisów manifestu | niewskazane przez `git check-attr` |
| `core.autocrlf` | `true`, odziedziczone z konfiguracji instalacji Git |
| HEAD | `aa8e7519c7721babc414d9824424a7fa5386119f`; 6 commitów osiągalnych z HEAD |
| Nieśledzone pliki w zakresie spisu | 129; 1 918 194 bajty; około 67,9% liczby plików i 72,3% bajtów |
| Metoda z pierwotnego W-12 | 1 625 podciągów `throw ` i 956 wyników regexu w 67 plikach; 12 wzmianek podciągowych w dokumentacji operacyjnej |

Pierwotne 189 plików i 2 573 349 bajtów odtwarzają się po odjęciu samego oryginalnego audytu: miał 80 196 bajtów. To różnica zakresu pomiaru. Nie należy interpretować jej jako wzrostu kodu.

Pierwotne 131 plików nieśledzonych, 2 116 051 bajtów i hasło „74% systemu” nie są wynikiem obecnego pomiaru o powyższym zakresie. Nie ustalono przyczyny rozbieżności. Udział musi wskazywać mianownik: liczbę plików albo bajty.

### 1.3 Poprawki metodyczne

- **Bajty, znaki i tokeny to odrębne miary.** Dzielenie bajtów UTF-8 przez cztery jest wskaźnikiem przybliżonym dla tekstu; nie jest pomiarem tokenów ani gwarantowanym górnym ograniczeniem. Nie nadaje się do wyceny PDF-ów i PNG-ów.
- **Bundle na dysku nie oznacza identycznej zawartości jednego promptu.** Model może odczytywać jego fragmenty narzędziami. Do pomiaru wejścia potrzebny jest rzeczywisty transport, log odczytów lub dane wykonawcy.
- **Zdarzenie `chunk_result` jest importem wyniku, nie pełnym dziennikiem wywołań.** Nie ujawnia wszystkich nieudanych prób ani kosztów retry. Suma `elapsed_ms` nie jest czasem ukończenia projektu przy współbieżności.
- **228,8 s wobec 185,72 s to różnica około 23,2%, nie potwierdzona regresja wydajności.** Brakuje kontrolowanego środowiska, powtórzeń i porównywalnego zakresu testów. Dwa zmierzone czasy 228,8 + 148,2 dają 377,0 s, czyli 6 min 17 s; osiem minut całego zestawu było szacunkiem.
- **Regex nie rozpoznaje semantyki błędów.** Zlicza także słowa rozpoczynające komunikaty, np. `STAGE_OWNER`, i może pomijać kody dynamiczne, wieloliniowe oraz Python. Wzmianka w Markdown nie jest instrukcją naprawy.
- **Mało dosłownych powtórzeń nie dowodzi braku powtórzeń znaczeniowych.** Skrypt pierwotnego §11.3 mierzył `len(str)`, czyli znaki, nazywając je bajtami. 1 029/262 190 to około 0,39%, a nie literalne zero; dodatkowo licznik i mianownik nie miały spójnych jednostek.
- **Nie wyceniamy zmian liczbą edytowanych linii.** Wersjonowanie, kompatybilność istniejących runów, testy i dokumentacja mogą dominować nad samą edycją kodu.

## 2. Zweryfikowane ustalenia W-01–W-21

Znaczenie ocen: **potwierdzone** oznacza odtworzony fakt w plikach lub konfiguracji; **częściowo potwierdzone** oznacza poprawną obserwację z nieudowodnionym skutkiem; **wycofana rekomendacja** dotyczy proponowanej naprawy, nie negowania kosztu. P1: przed operacją zależną lub pilotażem optymalizacji; P2: planowane usprawnienie; P3: porządek o niższym priorytecie. Nie stwierdzono trwającej awarii manifestu.

### W-01 — Ryzyko konwersji końców linii i hashy instrukcji

**Ocena: potwierdzone ryzyko; pierwotna naprawa wymaga korekty. Priorytet P1 przed odtwarzaniem plików przez Git.**

Dowód: efektywne `core.autocrlf=true`, niewskazane `text/eol` dla wszystkich 58 wpisów, 41 pozycji w indeksie Git. Manifest obecnie jest poprawny. `TEMPLATES/PROJECT/meta.md` jest wyjątkiem od tezy „wszystko jest LF”: ma mieszane zakończenia, uwzględnione w aktualnym SHA-256.

Nie każda operacja Git przepisuje każdy plik. `reset --hard` dodatkowo odtwarza starą treść, a brakujące w historii pliki V2 stanowią odrębny problem W-02. Nie wolno sprowadzać wszystkich przypadków niedziałającego odtworzenia do CRLF.

Jawne `text/eol` steruje konwersją; `eol=lf` ma sens dla plików, których wzorcem są bajty LF. Samo dodanie atrybutu nie zmienia bieżących bajtów, ale późniejsza normalizacja lub odtworzenie może je zmienić. [Dokumentacja Git: gitattributes](https://git-scm.com/docs/gitattributes).

**Poprawione zalecenie:** najpierw kopia bajtowa i spis hashy, potem polityka końców linii sprawdzona dla wszystkich plików manifestu. Wariant przejściowy może zachować bajty mieszanego pliku przez jawne wyłączenie konwersji dla tej ścieżki; docelowe ujednolicenie wymaga świadomego przeglądu i aktualizacji manifestu zgodnie z kontraktem. Nie wpisywać bez sprawdzenia ogólnego `*.md text eol=lf` jako naprawy „bez wpływu na hashe”. Zmiana lokalnego `core.autocrlf` nie zastępuje wersjonowanej polityki repozytorium.

**Kryterium odbioru:** odtworzenie zamierzonego snapshotu w osobnym katalogu daje te same bajty instrukcji albo jawnie zatwierdzony nowy manifest. Oryginalne projekty i historyczne receipts nie są normalizowane przy okazji.

### W-02 — Brak wersjonowanego punktu odniesienia dla obecnego V2

**Ocena: potwierdzone; określenia „nigdy” i „jedyną drogą jest ręczne odtworzenie” były zbyt mocne. P1.**

Dowód: stary HEAD, zmienione pliki śledzone i 129 aktualnie nieśledzonych plików w zakresie spisu. To potwierdza brak obecnego stanu w bieżącym commicie. Sam status Git nie dowodzi nieobecności we wszystkich dawnych gałęziach, reflogu i backupach.

Istnieją `E:\projektyoutube\_work\porzadkowanie-systemu-20260912\odzyskiwanie-przed-porzadkowaniem.zip` oraz `backup-manifest.json`. Potwierdzono obecność i odczytano manifest; nie wykonywano odtworzenia ani nie potwierdzono kompletności tej kopii względem dzisiejszej instalacji. ZIP pozostaje materiałem odzyskiwania, nie bieżącą instalacją ani instrukcją.

**Poprawione zalecenie:** zabezpieczyć bieżące bajty, ustalić listę plików do wersjonowania i dopiero po przeglądzie zrobić punkt odniesienia. Nie zalecać bezwarunkowego „commitu całości” w brudnym repozytorium. Oddzielić materiały prywatne, dane tymczasowe, wyniki testów i historyczny stan. `git diff` nadal działa dla plików śledzonych; problem dotyczy przede wszystkim braku wersji bazowej dla nowej warstwy.

**Kryterium odbioru:** spis plików zamierzonej wersji zgadza się z odtworzonym stanem; manifest przechodzi; wiadomo, które materiały pozostają poza historią i gdzie jest ich kopia. Lokalny commit nie jest sam w sobie kopią na innym nośniku.

### W-03 — Kolejność manifestu nie gwarantuje stabilnego początku promptu

**Ocena: sortowanie potwierdzone, utrata cache niezmierzona. P2.**

Dowód: `tools/Narrative-Receipts.ps1:6` deklaruje role stałe przed zmiennymi, a `New-SystemV7NarrativeInputBundle` w liniach 183–185 sortuje role ordinalnie. `ACT_HARD_CONSTRAINTS` i `ACT_PACKET` trafiają przed `CORE`. `tools/Start-K3Act.ps1:49–50` zwraca manifest i instrukcję uruchomienia kontekstu, a nie utrwalony request do dostawcy.

Jeżeli wykonawca skleja pliki według tych wpisów, zmienny początek ogranicza reuse stabilnej części. Nie pokazano jednak takiego wykonawcy ani rzeczywistego requestu. Walidator wiąże zbiór i bajty wejść; nie określa sam przez się ich kolejności transportowej. Nie wolno pisać, że cache jest niemożliwy w każdym środowisku lub że inna kolejność czytania automatycznie unieważnia manifest.

W Claude cache wymaga identycznej zawartości odpowiedniego początku promptu; istotne są też ustawienia cache i warunki jego dostępności. Sam `PREFIX_SHA256` ani uporządkowanie katalogu nie dowodzi trafienia. [Dokumentacja Anthropic: prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching).

**Poprawione zalecenie:** najpierw jawny kontrakt serializacji rzeczywistego promptu: stały rdzeń, Story Spine, voice rules i exemplars, potem dane aktu. Zapisać dowód kolejności i tożsamości prefixu. Dopiero w tym kontekście wybierać zmianę buildera. Nie przepisywać istniejących manifestów.

Zmiana kolejności nowo tworzonych wpisów zmienia ich hash, ale **nie unieważnia automatycznie dawnych bundle**: `Get-SystemV7NarrativeInputBundleState` odtwarza hash z zapisanych `data.entries` (`tools/Narrative-Receipts.ps1:317–318`), bez wymuszenia nowej kolejności. Zgodność trzeba sprawdzić, zamiast z góry zalecać rebase wszystkich runów.

**Kryterium odbioru:** dwa różne akty mają identyczny początek rzeczywistego wejścia; zachowane są reguły profilu i walidacja wcześniejszych runów. Oszczędność jest uznana dopiero po metrykach wykonawcy, nie po samym hashu.

### W-04 — Limit dwóch kandydatów wymusza dodatkowe strony wyników K1

**Ocena: mechanizm potwierdzony; skala kosztu i efekt zmiany wymagają eksperymentu. P2.**

Dowód: `tools/k1-lite-v2/k1_lite_v2_core.py:803` nakazuje maksymalnie dwóch kandydatów; `:1471–1472` egzekwuje limit; `:1449–1460` kontroluje kontynuacje; `:2951–2953` wiąże niezmieniony plik pakietu hashem. Domyślny zakres chunkowania to 12–18 tys. znaków, nie tokenów i nie gwarantowany rozmiar całego promptu.

W prostym modelu N kandydatów potrzebuje co najmniej `ceil(N/limit)` stron wyników, jeśli każda poza ostatnią wykorzystuje limit. Nie jest to liczba płatnych requestów dowiedziona przez kod. Kontynuacja może odbywać się z historią lub cache; dodatkowe instrukcje i retry też kosztują. Zapisany wynik i stały plik wejścia nie mówią, ile razy całość przeszła przez kontekst.

**Poprawione zalecenie:** porównać limit 2 z np. 4 i 8 na tych samych fragmentach i konfiguracji, zachowując pełne pokrycie, overflow, exact cytat i lokalizator. Sprawdzać również pominiętych kandydatów, a nie tylko poprawność zwróconych. Ewentualny nowy limit powinien być jawnie związany z wersją planu/instrukcji i runem. Zmiana nie ogranicza się bezpiecznie do dwóch linii: dotyka dokumentacji, testów i zgodności wznowień.

Wariant „limit zależy od liczby stron” nie ma wykazanego związku z gęstością dowodów. Lista wcześniej zgłoszonych kandydatów może ograniczyć duplikaty, ale sama nie gwarantuje mniejszego wejścia ani pełnego odczytu źródła.

**Kryterium odbioru:** mniejszy zmierzony koszt lub czas przy utrzymanym pokryciu i jakości; stare runy pozostają odtwarzalne. Żadnego podniesienia limitu w bieżącej korekcie audytu.

### W-05 — VERIFY kopiuje cały katalog źródeł

**Ocena: koszt dyskowy potwierdzony; przekroczenie kontekstu nieudowodnione. P2.**

Dowód: `tools/Start-K4Lenses.ps1:114` przekazuje `sources/` jako `SOURCE_FILES`. `tools/Narrative-Receipts.ps1:202–216` kopiuje rekurencyjnie pliki, pomijając `.git` i `__pycache__`, bez wykluczenia `_oryginaly/`. To realny koszt kopii i hashy, niezależnie od sposobu pracy modelu.

Nie wynika z tego, że cały katalog jest wysyłany w jednym promptcie. PDF może być potrzebnym wejściem wizualnym lub źródłem odczytywanym narzędziem; nie jest z definicji „binarium, którego model nie przeczyta”. Receipt potwierdza powiązanie artefaktów, a raport VERIFY deklaruje pokrycie. Żadne z nich, nawet dla krótkiego wycinka, samo nie dowodzi faktycznego przeczytania przez model.

`SOURCE_LOCATORS_V1` (`Start-K4Lenses.ps1:94–95`) zawiera `source_id` i lokalizator. Rozwiązanie ID do pliku oraz relacji tekst–PDF wymaga rejestru źródeł. Nie jest gotowym selektorem pełnego kontekstu wszystkich twierdzeń.

**Poprawione zalecenie:** mierzyć oddzielnie bajty skopiowane i treść odczytaną. Rozważyć etapowe czytanie źródeł wskazanych przez użyte karty, z obowiązkowym rozszerzeniem kontekstu, jeśli fragment nie rozstrzyga twierdzenia. Zachować dostęp do powiązanego oryginału i kontrolę 100% wymaganych bloków, cytatów oraz twierdzeń wysokiego ryzyka. Brak kontekstu musi blokować PASS.

Nie przyjmować stałego „±2 strony” jako dowodowej kompletności ani usuwać wszystkich PDF-ów. Nie wprowadzać limitu dyskowych bajtów jako zamiennika limitu rzeczywistego kontekstu. Redukcja zakresu dependency fingerprint jest osobną decyzją i wymaga zgodności z rzeczywistymi zależnościami, zob. W-10.

**Kryterium odbioru:** wykrywane są także błędy wymagające przypisu, następnej strony, ilustracji, tabeli lub odległego zastrzeżenia; każda odczytana treść ma źródło i hash. Oszczędność dyskowa i modelowa są raportowane odrębnie.

### W-06 — Visual QA dla wybranych cytatów PDF jest świadomą bramką

**Ocena: koszt potwierdzony; zalecenie zwolnienia z kontroli na podstawie flag wycofane.**

Dowód: `tools/k1-lite-v2/k1_lite_v2_core.py:2784–2822` wymaga visual receipt dla wybranych kandydatów `PDF_PAIR`. Konwerter `tools/k1-lite/pdf_to_markdown.py:238–240` oznacza OCR jako `LAYOUT_REVIEW_REQUIRED`. Rdzeń parsuje `method/flags`, ale nie znaleziono bezpośredniego odczytu tych pól przy decyzji o zwolnieniu z visual QA.

`NATIVE` i `FLAGS: NONE` opisują sposób ekstrakcji, a nie certyfikat poprawności. Heurystyki geometrii nie dowodzą braku błędu odczytu, podpisu, kolejności lub znaczenia. Dlatego zdania „render nie wnosi nowej informacji” i „gwarancja się nie obniża” zostały wycofane. Reguła dotyczy **wybranych kandydatów**, nie każdej strony korpusu.

**Poprawione zalecenie:** najpierw deduplikować rendery tej samej strony przy pełnym powiązaniu z SHA PDF, numerem strony, ustawieniami i wersją renderera. Grupować przegląd, zachowując osobny werdykt i powiązanie każdego cytatu. Ewentualne selektywne pomijanie kontroli traktować jako zmianę gwarancji wymagającą benchmarku błędów niewykrytych i osobnej decyzji kontraktowej.

**Kryterium odbioru bez zmiany bramki:** każdy wybrany cytat PDF nadal ma ważną kontrolę obrazu; mniej redundantnych renderów lub czynności przeglądu. Same nazwy `reviewer` w przykładzie JSON nie dowodzą liczby wywołań vision ani czasu pracy człowieka.

### W-07 — Obietnica reuse po hashach wymaga doprecyzowania

**Ocena: nie znaleziono automatycznego cache między runami; twierdzenie o koniecznym pełnym przetwarzaniu przy K2B wycofane. P2.**

Dowód: `MAPA-SYSTEMU.md:37` mówi o „ponownym użyciu wyników po hashach”. Dwa wystąpienia `packet_sha256` w rdzeniu K1 to zapis i kontrola aktualności (`:880`, `:2952`), nie indeks wyników. Ta obserwacja nie wyklucza zachowania już zaimportowanych wyników i kontynuowania tego samego runu.

`tools/Merge-K1LiteV2Supplement.ps1` pracuje na dotychczasowej bazie i wskazanym runie suplementu, a przy preview korzysta z `InternalAllowCorpusSubset` (`:252–290`). Nie ma tu dowodu, że dołączenie jednego źródła zmusza do ponownego wysłania wszystkich wcześniejszych źródeł modelowi.

**Poprawione zalecenie:** dokumentacja powinna rozdzielać wznowienie istniejącego runu, reuse już opublikowanej bazy w suplemencie, cache dostawcy i ewentualny cache wyników między runami. Ten ostatni wymaga tożsamości źródła, briefu, instrukcji, ustawień, stanu kontynuacji i legalnego pochodzenia wyniku; sam hash pakietu nie wystarcza jako uniwersalny klucz.

**Kryterium odbioru:** obietnica odpowiada konkretnej ścieżce kodu; wznowienie i suplement są przetestowane bez powtórnej ekstrakcji niezmienionych materiałów tam, gdzie kontrakt już na to pozwala.

### W-08 — Telemetria istnieje, lecz nie daje jeszcze poprawnego bilansu kosztu

**Ocena: potwierdzona potrzeba raportowania; hasło „system nie potrafi zmierzyć kosztu” było zbyt ogólne. P1 przed eksperymentami.**

Dowód: K1 dopuszcza `MEASURED` i `UNAVAILABLE`, z zerami technicznymi w drugim stanie (`k1_lite_v2_core.py:1379–1399`). Narrative V2 ma odrębny schemat: `tools/Narrative-Receipts.ps1:391–450` zapisuje metryki lokalne oraz opcjonalne wartości dostawcy; brak raportu dostawcy daje m.in. `null`, `AUTOMATIC_ONLY` i `NOT_REPORTED`, a nie wyłącznie zera K1.

**Nowe ważne ustalenie:** lokalne `input_tokens_estimated` liczy `ceil(sum(entry.bytes)/4)` ze wszystkich ról (`:400–403`). Przy katalogu VERIFY obejmuje to również PDF-y i obrazy. Agregowanie takiej liczby bez klasyfikacji plików może dać pozorną precyzję zużycia tokenów. `duration_ms` jest czasem między podanym startem a utworzeniem receiptu; nie musi być czasem inferencji.

**Poprawione zalecenie:** raport oddziela bajty dyskowe, tekst odczytany/wysłany, obrazy, estymację tekstową i rzeczywiste usage. Pokazuje pokrycie metrykami, brak danych zamiast „koszt 0”, runy nieukończone, retry oraz czas ścienny osobno od sumy czasów prób. W K1 licznik importów nie zastępuje logu wszystkich wywołań. Koszty w różnych walutach i estymacje nie mogą być sumowane jak jeden pomiar.

**Kryterium odbioru:** brak telemetrii i uszkodzony rekord są jawne; duplikaty/kopie runów nie podwajają wyniku; nieudane próby pozostają widoczne. Raport nie staje się bramką narracyjnej jakości.

### W-09 — Limit dwóch workerów jest regułą orkiestracji

**Ocena: częściowo potwierdzone; brak ogranicznika w rdzeniu nie oznacza nieskutecznej reguły. P3.**

Dowód: limit występuje w `MAPA-SYSTEMU.md:30`, `_SYSTEM/ROLES/CODEX.md:12` i `_SYSTEM/04-START-I-KOMENDY.md:39`. Cytowanego w pierwotnym raporcie zdania nie ma w obecnym `AGENTS.md`. Rdzeń nie steruje uruchamianiem agentów.

Import przez `tools/k1-lite-v2/Invoke-K1LiteV2.ps1:96–101` jest objęty project lockiem dla `ImportResult` i innych mutacji. Nie należy jednak przypisywać samemu `import_worker_result` w Pythonie gwarancji serializacji wielu procesów: `append_ledger` sprawdza oczekiwany hash, a gwarancję wrappera trzeba zachować na każdej używanej ścieżce wejścia.

**Poprawione zalecenie:** zapisać powód limitu i wskazać warstwę, która go stosuje. Ewentualnie zwiększać liczbę równoległych analiz przy nadal serializowanym imporcie i poprawnym odczycie najnowszego hasha ledgera. Uwzględnić limity wykonawcy, retry i obciążenie przeglądu redakcyjnego. Rozłączne chunki nie gwarantują liniowego przyspieszenia.

**Kryterium odbioru:** brak utraty i podwójnego importu zdarzeń, poprawna obsługa konfliktu hasha, zmierzony czas ukończenia tego samego korpusu.

### W-10 — Pełne hashowanie drzewa źródeł jest kosztem integralności

**Ocena: mechanizm potwierdzony; koszt czasowy niezmierzony. Cache oparty tylko na czasie i rozmiarze wycofany. P2.**

Dowód: `tools/Narrative-Receipts.ps1:310` kontroluje żywe źródła, a `:1074` buduje fingerprint zależności VERIFY. Odczytywany jest cały objęty zakresem zestaw plików. Pierwotny raport podał komendę pomiaru, ale nie wynik uzasadniający „dziesiątki sekund”.

Zmiana bajtów przy zachowanym rozmiarze i przywróconym czasie modyfikacji nie może uchodzić za niezmienione źródło. Cache `LastWriteTime + size` bez ponownej kontroli treści obniża gwarancję wykrywania tamperu.

**Poprawione zalecenie:** najpierw pomiar liczby i czasu odczytów. Rozważyć niezmienne snapshoty lub ograniczenie redundantnych odczytów wewnątrz jasno określonej transakcji, bez przenoszenia niezweryfikowanego wyniku między mutacjami. Project lock nie powstrzymuje dowolnego zewnętrznego edytora.

W-05 i W-10 muszą zachować spójność zakresu zależności, ale nie obowiązuje literalne „nigdy osobno”: można usprawnić sposób czytania promptu bez ograniczania fingerprintu albo przyspieszyć operacje bez zmiany zakresu. Dopiero **zawężenie tego zakresu** wymaga wspólnego projektu kontraktu.

**Kryterium odbioru:** zmiana źródła o tej samej długości i znaczniku czasu nadal unieważnia kontrolę; niezmienione wejścia mogą korzystać z legalnej optymalizacji.

### W-11 — Nowy run i ponowienie nieukończonej operacji to różne przypadki

**Ocena: zakaz ponownego tworzenia istniejącego runu potwierdzony; ogólny nakaz nowego ID po każdym błędzie niepotwierdzony. P2.**

Dowód: builder i `Start-*` zgłaszają `RUN_BUNDLE_ALREADY_EXISTS`. To dotyczy ponownego startu budowy. `New-NarrativeRunReceipt.ps1` sprawdza `RUN_RECEIPT_ALREADY_EXISTS` przed publikacją i usuwa nowo zapisany receipt przy rollbacku. Nie dowodzi to, że błąd przed publikacją wymaga nowego bundla; zależy to od etapu, pozostawionych artefaktów i semantyki faktycznie wykonanego modelowego runu.

Manifest obejmuje `run_id` i ścieżki `bundle_relative` (`Narrative-Receipts.ps1:226–235`); walidator wymusza ścieżki `_work/narrative-runs/<run_id>/inputs/` (`:274–277`). **Nie można przypisać nowego ID istniejącemu bundlowi i jednocześnie wymagać identycznego `input_manifest_sha256`**, jak sugerował pierwotny raport.

**Poprawione zalecenie:** opisać dozwolone wznowienie importu/receiptu przed ich zatwierdzeniem oraz oddzielić je od nowego wykonania modelu. Ewentualny współdzielony magazyn niezmiennych wejść wymaga nowego kontraktu tożsamości treści niezależnego od ID próby, z zachowaniem osobnych śladów wykonania. Nie jest drobnym przełącznikiem `-Retry`.

**Kryterium odbioru:** przerwanie przed zapisem nie zostawia sprzecznego stanu; zatwierdzone outputy i receipts nie są nadpisywane; nowa próba zachowuje własną tożsamość; rezygnacja z kopii nie pozwala zmienić historycznego wejścia.

### W-12 — Brakuje praktycznego katalogu diagnostyki, nie dowodu „944 nieopisanych błędów”

**Ocena: luka ergonomiczna potwierdzona, liczby wymagają właściwej etykiety. P2.**

Odtworzono pierwotną metodę: 956 wyników regexu i 12 wzmianek podciągowych. Pełne skanowanie wszystkich 84 plików PowerShell daje 1 153 takich kandydatów, z udziałem fixtures. Żadna z tych liczb nie jest kompletnym słownikiem semantycznych kodów systemu. W dokumentacji operacyjnej występuje 11 dokładnie dopasowanych tokenów z pierwotnego zbioru. Część to nazwy stanów, nie samodzielne kody.

Samo `rg` szybko wskazuje miejsce rzutu; konieczność przeczytania 1,89 MB kodu przy każdym błędzie nie została zmierzona. Nie ma danych, by nazwać to najdroższą pozycją całego systemu.

**Poprawione zalecenie:** indeks kod → źródło → znaczenie → bezpieczny kolejny krok, początkowo dla błędów rzeczywiście spotykanych. Automatyczny indeks lokacji oznaczać jako indeks, nie instrukcję naprawy. Oddzielić narzędzia operacyjne, testy, legacy i Python. Nie zalecać ręcznej zmiany meta/hashów, by uciszyć błąd.

**Kryterium odbioru:** konkretne błędy dają krótszą diagnozę; odwołania są aktualne; nieznany/dynamiczny kod pozostaje jawnie nieopisany. Nie trzeba tworzyć tysiąca opisów przed pierwszym użytecznym wydaniem.

### W-13 — Zbiorcze komunikaty można wzbogacić bez zmiany bramki

**Ocena: potwierdzone. P2.**

Dowód: `tools/Start-K3Act.ps1:35` łączy sześć warunków kodem `CONSTRAINT_PREFLIGHT_CURRENT_PACKET_BINDING_INVALID`. Istnieje też dobry wzorzec kolekcji `Errors`, używany przy walidacji bundle.

Fail-fast i fail-closed nie są sprzecznymi modelami. Pierwszy opisuje moment przerwania, drugi zakaz przejścia po błędzie. Nie każda diagnoza wymaga sześciu powtórzeń; to możliwy koszt, nie zmierzony wynik.

**Poprawione zalecenie:** pozostawić kod główny i dopisać nazwy niezgodnych pól. Agregować tylko niezależne kontrole, dla których istnieją poprawne wejścia; brak pliku lub wadliwy schemat musi nadal blokować zależne odczyty. Zachować short-circuit tam, gdzie chroni przed nielegalną operacją.

**Kryterium odbioru:** kilka niezależnych niezgodności jest widocznych naraz, nic nie zapisuje się po błędzie, kod główny pozostaje kompatybilny z odbiorcami.

### W-14 — Długie linie utrudniają przegląd

**Ocena: potwierdzone; mnożnik tokenów niezmierzony. P3, przy okazji innych zmian.**

Pomiar: `Narrative-Receipts.ps1` ma maksimum 1 593 znaki i 257 linii ponad 200 znaków; `Narrative-V2.ps1`: 1 770 i 210; `Validate-NarrativeV2Project.ps1`: 986 i 132. Długie linie pogarszają lokalizację zmian i czytelność diffu. Nie oznacza to dosłownej niemożności czytania lub bezpiecznej edycji.

**Poprawione zalecenie:** formatować nowe i rzeczywiście zmieniane funkcje, bez masowego przepisywania. Oddzielać refaktor układu od zmiany zachowania. Preferować naturalną kontynuację składni PowerShell; nie dodawać mechanicznie backticków.

**Kryterium odbioru:** czytelniejszy diff, brak zmiany zachowania i odpowiednie testy dotkniętego obszaru. Sam AST potwierdza składnię, a nie równoważność wykonania.

### W-15 — Parametry receiptu potwierdzają wykonanie, a nie tylko konfigurację

**Ocena: narzut ręcznego wpisywania potwierdzony; automatyczne podstawianie pięciu parametrów wycofane.**

Dowód: `tools/New-NarrativeRunReceipt.ps1:1–14` wymaga dziesięciu parametrów. Linie 29–35 porównują rolę i prompt revision z oczekiwaniami, a **tylko dla `GENERATE_ACT`** model i ustawienia z projektem. Pozostałe runy są kontrolami ChatGPT/Codex; nie wolno przypisywać im modelu K3 z `meta.md`.

Nawet dla K3 wartość oczekiwana nie potwierdza, że wykonawca jej użył. Zastąpienie rzeczywistych parametrów konfiguracją może ukryć uruchomienie innego modelu. Czas utworzenia bundla również nie zastępuje `StartedAt`: między przygotowaniem plików a wykonaniem może upłynąć dowolny czas.

**Poprawione zalecenie:** ograniczyć przepisywanie przez odczyt jawnych metadanych faktycznego wykonania albo przygotowanie formularza wartości oczekiwanych z osobnym potwierdzeniem wykonawcy. Zachować porównanie wartości faktycznych z wymaganymi. Rola i prompt revision mogą być prezentowane jako oczekiwania; nie udają poświadczenia użytej konfiguracji.

**Kryterium odbioru:** celowo błędny model/revision/settings nie może zostać „naprawiony” automatycznym odczytem meta; poprawne runy VERIFY zachowują własną tożsamość modelu; brak dowodu nie tworzy pozornej zgodności.

### W-16 — Regresja potrzebuje lepszej informacji o postępie; filtrowanie nie jest bezkosztowe

**Ocena: brak filtra potwierdzony; ogólna teza o całkowitej ciszy i tanim podziale wymaga korekty. P2/P3.**

Sygnatury czterech `Test-*` przywołanych w pierwotnym raporcie nie oferują `-Only`. Test Narrative V2 tworzy wspólny sandbox i przechodzi sekwencję zależnych etapów; nazwy pól podsumowania nie dowodzą istnienia niezależnych testów. `Test-System.ps1` emituje m.in. ostrzeżenie fixture'u, zatem „oba nie produkują żadnego wyjścia” nie jest twierdzeniem dosłownie poprawnym.

**Poprawione zalecenie:** najpierw komunikaty postępu i czas sekcji na strumieniu niedodającym obiektów do maszynowego wyniku. Następnie wydzielić testy z jawnym setupem i zależnościami. Nie uruchamiać pełnej regresji po samej korekcie audytu; po zmianach kodu dobierać testy do ryzyka i wymagań kontraktu, z pełnym przebiegiem przed przyjęciem wersji.

**Kryterium odbioru:** domyślne pełne uruchomienie zachowuje zakres; wynik z filtrem ma jawny zakres i status częściowy; da się ustalić, w której sekcji zatrzymało się wykonanie. Nie obiecywać „małej zmiany” bez oceny wspólnych fixtures.

### W-17 — Nawigacja po stanie jest rozproszona

**Ocena: potwierdzona potrzeba; brak jakiejkolwiek mapy oraz obowiązkowe 65 tys. tokenów na start były nadinterpretacją. P2.**

Istnieją `MAPA-SYSTEMU.md`, `_SYSTEM/04-START-I-KOMENDY.md`, pliki ról i etapów, `meta.md` z `NEXT_ACTION` oraz walidatory. Nie znaleziono jednego `Get-NextAction`, który łączy je w bezpieczną podpowiedź. Rozmiar całej dokumentacji nie oznacza, że całość trzeba ładować w każdym kroku. Rzeczywistą awarię linków opisuje W-21.

**Poprawione zalecenie:** pomocnik pokazuje zweryfikowaną rewizję, etap, blokadę, braki i najbliższą legalną czynność. Czyta istniejące reguły walidacji, zamiast tworzyć alternatywny silnik stanu. Może wskazać potrzebną decyzję lub brak danych, zamiast zawsze podawać komendę.

Nie wolno wypełniać z powietrza `TaskId`, metadanych wykonania, akceptacji Dawida ani `-DawidApproved`. Podpowiedź nie gwarantuje, że stan nie zmienił się później; mutator nadal waliduje ponownie. Jeśli odczyt bierze lock, należy jawnie uwzględnić ewentualne utworzenie pliku technicznego; nie nazywać takiej operacji bezwarunkowo „zero zapisów”.

**Kryterium odbioru:** dla starego originu, blokady i brakującej zgody narzędzie nie sugeruje nielegalnego przejścia. Każdy etap dostaje krótką mapę wymaganej lektury zgodną z nadrzędnymi instrukcjami.

### W-18 — Wyłączony ogólny builder ma nieosiągalny ogon

**Ocena: potwierdzone; zalecenie usunięcia całego pliku jako bezryzykownego wycofane. P3.**

Dowód: `tools/Build-NarrativeRunBundle.ps1:25` bezwarunkowo zwraca `GENERIC_NARRATIVE_BUNDLE_DISABLED`, wskazując właściwy wrapper. Linie 26–34 są nieosiągalne. Po wyłączeniu samego audytu nie znaleziono wywołania w sprawdzanych plikach Markdown/PowerShell/JSON.

To może być celowo pozostawiony punkt odmowy dla dawnych lub zewnętrznych wywołań. Brak wewnętrznego odwołania nie dowodzi braku takich klientów. Komunikat jest użyteczniejszy od „plik nie istnieje”.

**Poprawione zalecenie:** zachować jawną odmowę i mapę legalnych `Start-*`, ewentualnie usunąć wyłącznie nieosiągalny ogon po sprawdzeniu. Nie przywracać ogólnego buildera obchodzącego kanoniczne powiązania ról.

**Kryterium odbioru:** każda próba użycia ogólnego wejścia nadal jest odrzucana i wskazuje legalną ścieżkę bez mutacji projektu.

### W-19 — Brakuje instrukcji użycia `Approve-AuthorText.ps1`

**Ocena: potwierdzone; jest to bramka warunkowa i musi być opisana na właściwym etapie. P1/P2.**

Dowód: narzędzie nie jest opisane w operacyjnych `.md`; odwołanie jest w `_SYSTEM/NARRATIVE/TEST-FIXTURES/Test-NarrativeV2.K3.ps1:102`. `tools/Approve-AuthorText.ps1:30` dopuszcza zatwierdzanie wyłącznie w **K2 lub K2B**. Nie wystarczy dodać go dopiero obok działań przygotowania K3.

Akceptacja jest obowiązkowa, gdy projekt używa `AUTHOR_TEXT`; nie każdy odcinek musi go mieć. Narzędzie normalizuje LF i obcina otaczające białe znaki (`:19`), a następnie wiąże tekst z receiptem. Instrukcja powinna pokazać dokładną postać zatwierdzanego tekstu, aby nie mylić bajtów pliku wejściowego z kanoniczną reprezentacją receiptu.

**Poprawione zalecenie:** udokumentować K2/K2B, wymagany VC, tekst i notatkę oraz rzeczywistą zgodę Dawida. Nie dostarczać automatycznie zatwierdzonej przykładowej treści. Przy wykryciu braku dopiero w K3 wskazać legalną trasę powrotu, nie ręczne przestawienie etapu.

**Kryterium odbioru:** użytkownik rozumie, kiedy i co zatwierdza; brak zgody i niewłaściwy etap są odrzucane. Edycja `_SYSTEM/04-START-I-KOMENDY.md` wymaga procedury manifestu, bo plik jest objęty kontrolą.

### W-20 — Narzędzia zgodności trzeba oznaczyć, nie przenosić mechanicznie

**Ocena: mieszane nazewnictwo potwierdzone; sama obecność legacy nie jest wadą. P3.**

`Test-System.ps1` obejmuje reguły starszej rewizji i mechanizmy wspólne. Testowanie starych budżetów słów dla starego projektu nie narusza zakazu budżetów w Narrative V2. Rozmiar pliku mieszanego nie może być w całości zaliczony do „martwego kodu”. `Register-LegacyProject` ma też znaczenie dla starszych rewizji validation-only; nie wszystkie wymienione narzędzia obsługują wyłącznie jedną rewizję.

**Poprawione zalecenie:** zacząć od tabeli narzędzie → rewizja → przeznaczenie, wraz z ostrzeżeniem przy starych wejściach. Fizyczne przenoszenie rozważać dopiero po ustaleniu klientów i ścieżek. `$PSScriptRoot`, fixtures i historyczne instrukcje mogą zależeć od miejsca pliku.

**Kryterium odbioru:** stare projekty zachowują obsługę i origin; nowe wybierają Narrative V2; testy wspólne nadal przechodzą. Zmiana katalogu nie jest konieczna do osiągnięcia korzyści nawigacyjnej.

### W-21 — Rzeczywisty punkt startowy jest uszkodzony — pominięcie pierwotnego audytu

**Ocena: potwierdzone przez sprawdzenie ścieżek. P1.**

Instrukcja workspace każe zaczynać od `Produkcja tekstów/START.md`. Ten plik nie istnieje. Istnieje `Produkcja tekstów/System-v7.0/START.md`, ale jego pięć względnych odwołań nie prowadzi do istniejących plików z tej lokalizacji:

- `System-v7.0/README.md`;
- `System-v7.0/BIBLIA/README.md`;
- `System-v7.0/_SYSTEM/04-START-I-KOMENDY.md`;
- `System-v7.0/MAPA-SYSTEMU.md`;
- `Materiały%20warsztatowe/README.md`.

Treść wygląda na przygotowaną dla katalogu nadrzędnego. Potwierdzono niedziałające ścieżki, nie ustalono historii powstania błędu. To konkretny problem startu sesji, którego nie rozwiązuje samo napisanie `Get-NextAction`.

**Poprawione zalecenie:** w osobnym wdrożeniu przywrócić jeden jasno wskazany punkt startowy zgodny z instrukcją workspace oraz poprawić względne linki w istniejącym `START.md`. Krótki odsyłacz jest lepszy od dwóch rozjeżdżających się kopii instrukcji. Nie tworzyć drugiej instalacji systemu.

**Kryterium odbioru:** istnieje ścieżka wskazana przez workspace, wszystkie odwołania startowe prowadzą do właściwych aktualnych plików, a historyczny ZIP i testy nie są przedstawiane jako aktualne instrukcje.

## 3. Poprawiona kolejność usprawnień

| Kolejność | Zakres | Dlaczego teraz | Warunek przyjęcia |
|---|---|---|---|
| 1 | W-02 + W-01: snapshot i polityka bajtów/Git | Odtwarzalność przed kolejną zmianą | Odtworzenie w izolacji, świadomy zakres, zgodne hashe |
| 2 | W-21 + W-19 + doprecyzowanie W-07 | Konkretne błędy wejścia i instrukcji | Działające linki, poprawny etap AUTHOR_TEXT, brak fałszywej obietnicy cache |
| 3 | W-08: poprawna agregacja i pomiar | Bez niej nie da się uczciwie ocenić optymalizacji | Brakujące usage jawne; tekst oddzielony od binariów; retry i zakresy rozliczone |
| 4 | W-13, wybrane W-12, postęp W-16 | Krótsza diagnoza bez zmiany reguł jakości | Te same odmowy i stan, lepszy komunikat |
| 5 | W-17: pomocnik stanu i lektury | Mniej ręcznej rekonstrukcji procesu | Wspólne walidatory, brak domyślnych zgód i fikcyjnych metadanych |
| 6 | Eksperyment W-03 i W-04 | Potencjalne oszczędności modelu | Rzeczywiste wejście/usage i utrzymana jakość |
| 7 | Projekt W-05/W-10/W-11 | Największa złożoność kontraktowa i zgodności | Pełny kontekst dowodowy, wykrywanie zmian, odtwarzalne historyczne runy |
| 8 | W-06 bez redukcji kontroli, W-09, W-14, W-18, W-20 | Dalsza ergonomia i ograniczenie pracy powtarzalnej | Konkretna korzyść bez obniżenia gwarancji i bez migracji istniejących projektów |

Nie ma etapu „tanie i bez skutków ubocznych”. Nawet generator indeksu może się zestarzeć, filtr testów może ominąć setup, a automatyczne uzupełnianie pól może ukryć niewłaściwe wykonanie. Ryzyko powinno być nazwane proporcjonalnie, bez deklarowania zerowego kosztu weryfikacji.

## 4. Minimalny plan eksperymentów wydajnościowych

To plan przyszłego badania, **nie test wykonany w tej korekcie** i nie zamiennik narracyjnego A/B wymaganego do aktywacji V2.

1. **Zamrozić próbę:** konkretne źródła i ich hashe, plan, chunk IDs, model/revision/settings, instrukcje, rzeczywisty sposób dostarczenia wejść. Wybrać materiał rzadki i gęsty w kandydatów, natywny tekst oraz trudny PDF/OCR. Zapisać regułę doboru przed obejrzeniem wyniku.
2. **Ustalić jakość:** niezależnie przygotować zestaw istotnych kandydatów i błędów do wykrycia. Mierzyć wierność cytatów, lokalizację, zachowanie niepewności, pominięcia, duplikaty i nieukończone chunki. Same pozytywne wyniki walidatorów nie wystarczą.
3. **Zmieniać jeden czynnik:** np. limit 2/4/8 albo kolejność realnego promptu. Zachować pozostałe wejścia. Osobno rozpatrzyć zimny i ciepły cache, jeśli wykonawca daje takie dane. Wykonać powtórzenia i pokazać rozrzut, nie tylko najlepszy czas.
4. **Mierzyć różne koszty osobno:** liczba prób, zaimportowanych wyników, retry, usage dostawcy, tekstowy wolumen wejścia, cache, czas ścienny, suma czasów prób i czas ręcznej kontroli. Nie traktować braku pomiaru jako zera.
5. **Sprawdzić przypadki negatywne:** zmienione źródło o tym samym rozmiarze i czasie; inny model; przerwane wykonanie; brak kontekstu poza wycinkiem; zastrzeżenie w przypisie; próba carry-forward po zmianie zależności; wznowienie starego runu.
6. **Przyjąć zmianę dopiero po ustalonym kryterium:** korzyść kosztowa/czasowa i brak utraty krytycznych właściwości na tej próbie. Gdy wynik jakości jest niejednoznaczny, zachować dotychczasową bramkę. Nie podawać procentu oszczędności bez wskazania próby i pokrycia metrykami.

## 5. Historyczne liczby, których nie należy przedstawiać jako nowego pomiaru

Wartości zachowano dla śladu audytowego. Autor pierwotnego raportu nie podał ścieżek i hashy korpusu, pełnej listy runów ani surowych wyników pozwalających przypiąć poniższe liczby do zamkniętej próby.

| Historycznie raportowane | Status po weryfikacji |
|---|---|
| `Test-NarrativeV2` PASS, 228,8 s; `Test-System` PASS, 148,2 s | Nie uruchamiano ponownie. Istnieją również wcześniejsze logi PASS w katalogu porządkowania; nie ustalono ich tożsamości z tą próbą czasową. |
| 987 pierwszych wyników, 450 kontynuacji, razem 1 437 | Nieodtworzone: nie wskazano zamkniętej listy runów. Licznik importów, nie dowód kompletu wywołań. |
| 8,34 h + 6,40 h = 14,74 h; 43% na kontynuacje | Arytmetycznie spójne; charakter i kompletność `elapsed_ms` niepotwierdzone. To nie czas ścienny całego procesu. |
| 9 805 883 + 4 139 514 = 13 945 397 bajtów; około 30% na kontynuacje | Skrypt sumował rozmiar pakietu raz na zdarzenie. To wskaźnik wolumenu powiązanego z importami, nie rzeczywiste tokeny wysłane. |
| „3,49 mln tokenów”, „1,03 mln ponownego wejścia” | Estymacje `/4`; nie są measured usage ani kwotą oszczędności możliwą do odzyskania. |
| Statusy: 522 `CANDIDATE`, 551 `SCANNED_NO_CANDIDATE`, 364 `PARTIAL_OVERFLOW`; retry 90; średnio 36,9 s | Nieodtworzone. Statusy sumują się do 1 437; retry nie ujawnia pełnej treści i kosztu nieudanych prób. |
| Ten sam chunk do 8×, „w runach zbiorczych do 41×” | Nieodtworzone. Wymaga tożsamości `(projekt, run, chunk, continuation)` i odróżnienia kopii ledgera. Sam `C0001` nie jest globalnym ID. |
| 261 MB źródeł; 17 PDF, 16 MD; 8 076 193 bajty tekstu | Nieodtworzone. Nie można nazywać pojedynczej niewskazanej próby „typowym projektem”. |
| 501 PNG, 149 MB | Nieodtworzone; liczba plików nie dowodzi liczby ocen vision ani godzin ręcznego przeglądu. |
| 1 437/1 437 rekordów K1 z `UNAVAILABLE` | Nieodtworzone; nie wolno rozciągać tego na wszystkie runy K1 oraz inny schemat Narrative V2. |
| 147 ms dot-source + 29 ms hashowania | Historycznie raportowane bez nowego pomiaru; nie podstawa do generalizacji narzutu każdego entrypointu. |

Pierwotny skrypt agregacji filtrował ledgery głębokością ścieżki `p.count(os.sep) == 1`, pomijał błędny JSON i wpisy bez oczekiwanej struktury, a brak rozmiaru pakietu zastępował zerem. Nie weryfikował deklarowanego schematu zdarzenia i nie utrwalał listy hashy wejścia. Taki skrypt może pomagać w eksploracji, ale nie jest wystarczającym dowodem wydajności.

Docelowa agregacja powinna otrzymywać jawną listę runów, kontrolować schemat, hashe i duplikaty, raportować odrzucone/niekompletne rekordy oraz oddzielać nieznane wartości od zer. Pojawienie się kilku rekordów `MEASURED` nie rozwiązuje problemu brakującego pokrycia reszty próby.

## 6. Odtworzenie bieżącej weryfikacji — PowerShell

Poniższe polecenia odczytują stan. Nie normalizują plików, nie odbudowują manifestu, nie tworzą projektu i nie uruchamiają modeli. Wynik inwentarza po korekcie różni się rozmiarem audytu; pozostałe zmiany należy oceniać przez porównanie hashy z zapisanym snapshotem.

```powershell
$systemRoot = 'E:\projektyoutube\Produkcja tekstów\System-v7.0'
$reviewRoot = 'E:\projektyoutube\_work\krytyka-audytu-wydajnosci-20260912'
python -X utf8 (Join-Path $reviewRoot 'snapshot.py') $systemRoot
```

Samodzielna kontrola hashy manifestu:

```powershell
$systemRoot = 'E:\projektyoutube\Produkcja tekstów\System-v7.0'
$manifestPath = Join-Path $systemRoot '_SYSTEM\NARRATIVE\NARRATIVE-INSTRUCTION-MANIFEST.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$problems = @(
    foreach ($entry in $manifest.entries) {
        $path = Join-Path $systemRoot $entry.path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            "MISSING: $($entry.path)"
        } elseif ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $entry.sha256.ToUpperInvariant()) {
            "HASH_MISMATCH: $($entry.path)"
        }
    }
)
[pscustomobject]@{ Entries = $manifest.entries.Count; Problems = $problems }
```

Ta kontrola nie zastępuje pełnego walidatora kontraktu: sprawdza wpisane ścieżki i hashe, a nie samą zamkniętą allowlistę, reguły markerów i origin projektu. Aktualizacja manifestu `-Write` nie jest poleceniem diagnostycznym.

Przykładowe wyszukiwanie mechanizmów bez polegania wyłącznie na starych numerach linii:

```powershell
$systemRoot = 'E:\projektyoutube\Produkcja tekstów\System-v7.0'
rg -n 'CANDIDATE_PAGE_LIMIT_EXCEEDED|packet_sha256|visual_required' (Join-Path $systemRoot 'tools\k1-lite-v2\k1_lite_v2_core.py')
rg -n 'New-SystemV7NarrativeInputBundle|inputEstimate|INPUT_MANIFEST_BINDING_MISMATCH' (Join-Path $systemRoot 'tools\Narrative-Receipts.ps1')
git -C $systemRoot config --show-origin --get core.autocrlf
git -C $systemRoot check-attr text eol -- TEMPLATES/PROJECT/meta.md
```

Numery linii w ustaleniach odnoszą się do snapshotu tej kontroli. Przyszłe zmiany kodu wymagają ponownej lokalizacji i weryfikacji; nie należy „naprawiać” systemu według historycznego numeru linii bez sprawdzenia funkcji.

## 7. Granica tej korekty

Zastąpiono pierwotne wnioski skorygowanymi ocenami W-01–W-20, dodano pominięte W-21, rozdzielono pomiary od hipotez i zapisano kryteria przyszłych wdrożeń. Oryginalny dokument zachowano z SHA-256:

`408872549CAA8C36A1DF43981D14F0A0D72D7FA6BDED509BC98D605DC8FE31A9`.

W tej pracy **nie wdrożono żadnego z proponowanych usprawnień systemu**. Kod, obowiązujące instrukcje, manifest, konfiguracja Git i projekty odcinków pozostają poza zakresem zmian. Wynik kontroli po zapisie jest w `verification-final.json`. Status `PILOT_ONLY`, oczekiwany test A/B i decyzje Dawida pozostają jawne.
