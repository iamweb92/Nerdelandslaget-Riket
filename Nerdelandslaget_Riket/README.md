# Nerdelandslaget: Riket (WoW: Forever)

Laget av Neophyte.

En liten, frittstående addon for alle guilder med «nerd» i navnet, for eksempel Nerdelandslaget, Nerdelandslaget II og Nerdealtslaget. Riket ligger som en egen fane i guildvinduet (J) og gjør tre ting:

1. **Felles guild chat:** det som skrives i /g i én guild, vises i guild chatten til de andre, som `[Nerdelandslaget II] [Navn]: tekst`. Lenker til items og spells kan fortsatt klikkes.
2. **Medlemmer:** hvem som er pålogget i alle guildene, med nivå, klasse, guild, guild rank og Discord-navn. Klikk på en kolonneoverskrift for å sortere, og klikk igjen for å snu rekkefølgen. Klikk på et navn for å whispre, høyreklikk for å invitere.
3. **Yrker:** alle sine professions med nivå og lenke. Klikk på lenken for å se oppskriftene, shift-klikk for å lime den inn i chat.

## Installere

Legg mappen `Nerdelandslaget_Riket` rett i `World of Warcraft\_forever_\Interface\AddOns\`.

## Første gang: Discord-navn

Riket gjør ingenting før du har skrevet inn Discord-navnet ditt. Første gang du logger inn med addonen, spør den om navnet. Det gjelder alle karakterene på kontoen, og de andre i nerd-guildene ser det ved siden av karakteren din.

Har ranken din lov til å endre guild note, spør Riket også om den skal skrive Discord-navnet i guild noten din. Da vises det i guildlista i spillet også. Du kan endre navnet senere med `/riket discord`.

## Bruk

- **Åpne:** trykk J og velg NL-fanen på høyre side av guildvinduet. `/riket` (eller `/nll`), NL-knappen ved minikartet og Riket i addon-lista under minikartet åpner også guildvinduet rett på Riket.
- **Lite guildvindu:** i det lille chat-modus har guildvinduet ikke plass til Riket. Gjør vinduet stort igjen, så kommer fanen tilbake.
- **Andre kommandoer:** `/riket chat`, `/riket members`, `/riket professions`, `/riket discord` (bytt Discord-navn), `/riket note` (skriv Discord-navnet i guild noten), `/riket status` og `/riket button` (viser eller skjuler minimap-knappen).
- **Lenker til yrker:** åpne hvert av dine yrkesvinduer én gang. Spillet gir bare ut lenken mens vinduet er åpent.

## Greit å vite

- **Hvem som ser hva:** bare de som har addonen ser de andre guildenes chat og lister. Det holder at én person med addonen er pålogget i hver guild.
- **Under bosskamper:** spillet skjuler guild chat for addons, så de linjene blir ikke sendt over.
- **Eldre versjoner:** folk med eldre versjon av Riket ser fortsatt chatten og medlemslistene, men ikke rank og Discord-navn.
- **Andre addons:** Riket har egen kanal (`NLRiketNet`), egne lagrede data (`NLRiketDB`) og egne kommandoer, og kan være på samtidig med andre Nerdelandslaget-addons.
