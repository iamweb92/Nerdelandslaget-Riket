# Nerdelandslaget: Riket

En WoW: Forever-addon for alle guilder med «nerd» i navnet: Nerdelandslaget, Nerdelandslaget II og vennene deres. Laget av Neophyte.

Riket ligger som en egen fane i guildvinduet (J) og gir deg:

- **Felles guild chat:** /g i én nerd-guild vises i guild chatten til de andre, med lenker som fortsatt kan klikkes.
- **Medlemmer:** hvem som er pålogget i alle guildene, med level, guild, rank og Discord-navn. Klikk på en kolonne for å sortere.
- **Yrker:** alle sine professions med skill og lenke til oppskriftene.

## Installere

1. Last ned `Nerdelandslaget_Riket-x.y.z.zip` fra [Releases](../../releases/latest). Ikke bruk «Download ZIP» på kodesiden, for da får mappen feil navn.
2. Pakk ut zip-filen, slik at mappen `Nerdelandslaget_Riket` ligger rett i `World of Warcraft\_forever_\Interface\AddOns\`.
3. Start spillet og skriv inn Discord-navnet ditt når Riket spør. Addonen gjør ingenting før det er gjort.

Mer om bruk og kommandoer står i [Nerdelandslaget_Riket/README.md](Nerdelandslaget_Riket/README.md).

## For utviklere

- `Nerdelandslaget_Riket/`: selve addonen.
- `tests/riket_test.lua`: en offline test som simulerer flere klienter i flere guilder. Kjør den med `luajit tests/riket_test.lua Nerdelandslaget_Riket`.
- `build.sh`: lager zip-filen som legges ut under Releases.
- `tools/make_round.py`: lager de runde NL-ikonene i `media/`.
