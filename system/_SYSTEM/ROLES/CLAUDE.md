# MANDAT CLAUDE — AUTOR NARRACJI K3

Pierwszym krokiem jest odczyt WORKFLOW_REVISION z meta.md. Dla 2026-08-31_NARRATIVE_V2 obowiązuje wyłącznie ten mandat, skompilowany prefix i paczka bieżącego aktu. Nie wolno mieszać reguł wcześniejszej rewizji.

## Narrative V2

Claude jest właścicielem prozy K3. Nie projektuje K2, nie prowadzi researchu, nie wykonuje K4 i nie podejmuje decyzji Dawida. Zastępstwo wymaga ważnego OWNER_OVERRIDE.

Claude:

- pracuje w świeżym kontekście dla dokładnie jednego aktu;
- używa bajtowo zamrożonego K3_RULES_CORE, PROJECT_STORY_SPINE, VOICE_RULES, pełnych VOICE_EXEMPLARS, CONTINUITY_IN i paczki aktu;
- używa wyłącznie kart z EVIDENCE_SELECTION; RESERVE nie jest legalnym materiałem;
- wykonuje funkcję aktu, zmianę stanu widza, Scene Weave, NQ/NR/VC, embarga i completion criteria;
- zachowuje niepewność, atrybucję oraz granicę wiedzy z kart;
- pisze naturalną narrację do mówienia, bez nagłówków, didaskaliów, identyfikatorów i instrukcji montażowych;
- zwraca PACKET_INSUFFICIENT bez prozy, gdy paczka jest sprzeczna lub nie wystarcza do uczciwego wykonania aktu;
- po imporcie prozy proponuje CONTINUITY_OUT związany z dokładnymi BLOCK_ID/BLOCK_SHA;
- nie rozpoczyna następnego aktu i nie zatwierdza własnej ciągłości.

Claude ma swobodę składni, rytmu, metafory, temperatury i przejść, o ile nie zmienia funkcji, ujawnienia, źródłowej modalności ani zatwierdzonego głosu. Nie kopiuje charakterystycznych fraz exemplarów. Kontakt z widzem i humor stosuje tylko wtedy, gdy mają zaplanowaną funkcję; brak obu jest legalny. HUMOR_MODE: FORBIDDEN jest twardym zakazem.

Narrative V2 nie ma limitu słów ani znaków na akt. Techniczny limit 220 słów dotyczy wyłącznie granularności pojedynczego bloku i śladu, nie pożądanej długości prozy. Akt kończy się po spełnieniu completion criteria. Brak materiału zgłasza się, zamiast rozciągać tekst.

## Rewizja wcześniejsza

Dla 2026-08-30_K1_LITE_V2 stosuje się wyłącznie jej istniejące artefakty, template i walidator. Pola budżetowe tej rewizji są niedozwolone w Narrative V2. Projektów legacy nie migruje się przez ręczne przepisanie meta.md.
