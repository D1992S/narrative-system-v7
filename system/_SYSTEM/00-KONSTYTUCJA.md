# Konstytucja System-v7.0

NARRATIVE_V2_CONTRACT: 2026-08-31_NARRATIVE_V2
NARRATIVE_V2_STATUS: PILOT_ONLY

## 1. Cel i nadrzędność

System tworzy źródłowo uczciwą, angażującą narrację YouTube bez odbierania Dawidowi decyzji redakcyjnych. Dla projektu zawsze obowiązuje rewizja zapisana w jego `meta.md`; pamięć, stary plan ani nazwa pliku nie mogą jej zastąpić.

Kolejność nadrzędności dla `2026-08-31_NARRATIVE_V2`:

1. ta Konstytucja i `AGENTS.md`;
2. `_SYSTEM/NARRATIVE/NARRATIVE-CONTRACT-V2.md`;
3. procedura bieżącego etapu;
4. schemat konkretnego artefaktu;
5. Biblia narracji i Kanon dramaturgii jako wiedza doradcza;
6. miękkie wskazówki stylu.

Źródła, granica wiedzy, bezpieczeństwo i jawne decyzje Dawida zawsze wygrywają z dramaturgią.

## 2. Obsługiwane tory

- `2026-08-31_NARRATIVE_V2`: jedyny domyślny wybór dla nowych projektów od 2026-09-12 na polecenie Dawida; status jakości nadal `PILOT_ONLY`.
- `2026-08-30_K1_LITE_V2`: zgodność z istniejącymi projektami i testami, bez automatycznej migracji; nie jest wyborem dla nowej produkcji.
- starsze pary rewizja–schema: validation-only; jawna rejestracja legacy nadaje wyłącznie możliwość walidacji i nigdy nie przywraca aktywnej pracy.

Mieszanie pól, szablonów, komend, receiptów lub walidatorów różnych torów jest twardym FAIL. Migracja projektu wymaga osobnego procesu, kopii bezpieczeństwa i zgody Dawida.

## 3. Etapy i właściciele

`W0 Dawid → K0 ChatGPT → K1 ChatGPT → K2 ChatGPT → K2B ChatGPT → K3 Claude → K4 ChatGPT → K5 Dawid → COMPLETE`

- Właściciel odpowiada za rezultat etapu; inne role mogą jedynie wspierać.
- Zastępstwo jest legalne tylko z ważnym `OWNER_OVERRIDE` receiptem.
- System nigdy sam nie podejmuje decyzji Dawida ani nie interpretuje milczenia jako zgody.
- `COMPLETE` wymaga fizycznego K5 PASS i jawnej akceptacji Dawida.

## 4. Stan i przejścia

- `meta.md` jest jedynym kanonicznym stanem bieżącym, ale każde przejście jest związane z immutable receiptem.
- Ręczna zmiana `CURRENT_STAGE`, `LAST_GATE`, statusu blokady, profilu głosu lub właściciela nie daje legalnego stanu.
- Mutacja odbywa się pod project lockiem, atomowo, z porównaniem wejść, postwalidacją i rollbackiem.
- `BLOCKED` i `UNBLOCK` są osobnymi decyzjami. Aktywny etap z head receiptem `BLOCK` jest nieważny.
- Reopen może cofać tylko do dozwolonego etapu i unieważnia wszystkie zależne artefakty.

## 5. Źródła i dowody

- Używamy najpierw materiałów dostarczonych do projektu.
- Karta dowodu zachowuje dosłowny fragment, identyfikator źródła, dokładną lokalizację i status pewności.
- Streszczenie, routing, wynik wyszukiwania ani cudza interpretacja nie są samodzielnym dowodem.
- Kontrowersyjne lub niepotwierdzone twierdzenie pozostaje tylko z proporcjonalną atrybucją i niepewnością.
- VERIFY ma prawo cofnąć tekst niezależnie od jego jakości narracyjnej.

## 6. K2 Narrative V2

- Kanonicznym artefaktem jest `STORY_ENGINE_V2`.
- Każdy akt musi zmieniać stan wiedzy widza, mieć Scene Weave, funkcjonalne REQUIRED i jedno semantyczne completion.
- NQ, NR i VC mają jawne rejestry oraz legalne węzły. Reveal wymaga dowodu, przygotowania, embarga i późniejszej konsekwencji.
- Jedna akcja nie może udawać czterech obowiązków przez listę lub spójniki.
- Maksymalnie siedem atomowych CID obejmuje wszystkie hard constraints i `CONTINUITY_OUT`. Modelowy preflight nie może nadpisać wyniku kontroli deterministycznej.

## 7. Głos, kontakt i humor

- Produkcyjny profil głosu wymaga exact exemplarów z ważnych finałów K5 oraz receiptu Dawida.
- Profil musi być jawnie przypięty do projektu przed prefix freeze; nie zmienia się automatycznie w trwającym projekcie.
- Exemplar przenosi rozkład głosu, nie treść ani charakterystyczne frazy.
- `AUTHOR_TEXT` jest używany wyłącznie byte-for-byte z projektem-bound receiptem.
- Kontakt z widzem i humor nie mają norm liczbowych. Każdy przypadek musi wynikać z funkcji, sceny i ryzyka.

## 8. K3

- Claude pisze tylko jeden akt w jednym świeżym kontekście.
- Stabilny prefix zawiera rdzeń reguł, Story Spine, zatwierdzone VOICE RULES i VOICE EXEMPLARS. Jego manifest wiąże pełne hashe profilu i rejestru.
- Model, rewizja i ustawienia są zamrożone. Rebase oznacza pełną regenerację zależnej prozy.
- `PACKET_INSUFFICIENT` jest legalnym zatrzymaniem, nie zgodą na improwizację.
- Akt SIMPLE wymaga constraint preflight; COMPLEX dodatkowo beat sheet i beat preflight.
- Po każdym akcie osobny kontekst tworzy continuity attest. Kolejny akt nie startuje bez zaakceptowanego attestu poprzedniego.
- Draft składa kompilator; autor nie nadaje sobie identyfikatorów bloków ani śladów.

## 9. K4 i K5

- EDITOR ocenia narrację i plan, VERIFY źródła i lokalizacje, COLD_READER wyłącznie czysty tekst.
- Trzy runy są niezależne, mają unikalne task ID, osobne input bundles i receipty.
- Raporty K4 tworzy kompilator dopiero po potwierdzeniu pełnego pokrycia bloków i wymaganych kart.
- Korekta po K4 wymaga impact review i ponowienia dotkniętych kontroli; carry-forward musi być hash-bound i add-only.
- K5 V2 akceptuje wyłącznie byte-identical final. Zmiana tekstowa cofa do K3.

## 10. Czas i długość

- Narrative V2 nie narzuca liczby słów, znaków ani długości aktu.
- `TARGET_MINUTES` w trybie GUIDE nie jest powodem dopisywania lub wycinania treści.
- `HARD_MAX` wymaga jawnego, audytowalnego wyboru Dawida i jest sprawdzany dopiero po kompletności.
- Nie skraca się dowodów, logiki, scen, przejść ani granicy wiedzy w celu trafienia w licznik.

## 11. Aktywacja

Implementacja techniczna nie jest wynikiem testu jakości. Rewizja pozostaje `PILOT_ONLY`, dopóki trzy benchmarki nie przejdą ślepego A/B, wariant V2 nie wygra co najmniej dwóch oraz Dawid nie zapisze decyzji aktywacyjnej. Osobną decyzją z 2026-09-12 Dawid wybrał najnowszą wersję jako jedyną dla nowej produkcji: domyślne `New-Project.ps1` tworzy Narrative V2. Ten wybór nie dopisuje wyniku A/B, nie zatwierdza profilu głosu i nie migruje istniejących projektów.
