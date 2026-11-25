# Nerdelandslaget: Riket

En WoW: Forever-addon for alle guilder med «nerd» i navnet: Nerdelandslaget, Nerdelandslaget II og vennene deres. Laget av Neophyte.

Alt ligger i guildvinduet (J):

- **Felles guild chat:** guild chatten i J-vinduet viser alle nerd-guildenes /g sammen, sortert etter tid. Lenker kan fortsatt klikkes.
- **Members:** egen fane med hvem som er pålogget i alle guildene, med level, guild, rank og Discord-navn. Klikk på en kolonne for å sortere.
- **Professions:** egen fane med alle sine yrker, skill og lenke til oppskriftene.
- **Discord:** egen fane der hver spiller skriver inn Discord-navnet sitt. Det er obligatorisk.

## Installere

1. Last ned `Nerdelandslaget_Riket-x.y.z.zip` fra [Releases](../../releases/latest). Ikke bruk «Download ZIP» på kodesiden, for da får mappen feil navn.
2. Pakk ut zip-filen, slik at mappen `Nerdelandslaget_Riket` ligger rett i `World of Warcraft\_forever_\Interface\AddOns\`.
3. Start spillet, trykk J og skriv inn Discord-navnet ditt i Discord-fanen. Addonen gjør ingenting før det er gjort.

Mer om bruk og kommandoer står i [Nerdelandslaget_Riket/README.md](Nerdelandslaget_Riket/README.md).

## For utviklere

- `Nerdelandslaget_Riket/`: selve addonen.
- `tests/riket_test.lua`: en offline test som simulerer flere klienter i flere guilder. Kjør den med `luajit tests/riket_test.lua Nerdelandslaget_Riket`.
- `build.sh`: lager zip-filen som legges ut under Releases.
- `tools/make_round.py`: lager de runde NL-ikonene i `media/`.
