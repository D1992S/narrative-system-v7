# Zgodność istniejących projektów

To zależność techniczna jednego aktualnego System-v7.0, a nie oddzielna instalacja ani alternatywny start produkcji. Szablony są potrzebne przez `Start-Stage.ps1` do istniejących projektów, takich jak Nahanni, oraz przez testy regresji. Usunięcie ich zepsułoby tę obsługę.

Nowe odcinki używają wyłącznie `TEMPLATES/PROJECT` i domyślnego `New-Project.ps1` (Narrative V2). `-NarrativeV2Pilot:$false` zachowano dla historycznych fixture’ów testowych. Nie stosuj go do nowych odcinków.
