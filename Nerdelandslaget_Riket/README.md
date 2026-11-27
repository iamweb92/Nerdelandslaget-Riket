# Nerdelandslaget: Riket (WoW: Forever)

Laget av Neophyte.

En liten, frittstående addon for alle guilder med «nerd» i navnet, for eksempel Nerdelandslaget, Nerdelandslaget II og Nerdealtslaget. Alt ligger i guildvinduet (J):

1. **Felles guild chat:** guild chatten i J-vinduet viser de andre nerd-guildenes /g sammen med din egen, sortert etter tid, som `[Nerdelandslaget II] [Navn]: tekst`. Du skriver som før i feltet under. Lenker til items og spells kan fortsatt klikkes.
2. **Members** (egen fane): hvem som er pålogget i alle guildene, med level, klasse, guild, guild rank og Discord-navn. Klikk på en kolonneoverskrift for å sortere, og klikk igjen for å snu rekkefølgen. Klikk på et navn for å whispre, høyreklikk for å invitere. Kryss av «Show offline players» for å også se dem som har vært pålogget de siste 30 dagene, grået ut og med hvor lenge siden.
3. **Professions** (egen fane): alle sine yrker med skill. Klikk på et yrke for å se oppskriftene personen kan, med søk. Klikk på en oppskrift for å whispre «Can you make [oppskrift]?», shift-klikk for å lime den inn i chat.
4. **Discord** (egen fane): her skriver du inn Discord-navnet ditt. Det er obligatorisk.

## Installere

Legg mappen `Nerdelandslaget_Riket` rett i `World of Warcraft\_forever_\Interface\AddOns\`.

## Første gang: Discord-navn

Riket gjør ingenting før du har skrevet inn Discord-navnet ditt. Første gang du logger inn med addonen, ber den deg åpne Discord-fanen i guildvinduet. Der skriver du navnet og trykker Save. Navnet gjelder alle karakterene på kontoen, og de andre i nerd-guildene ser det ved siden av karakteren din.

Har ranken din lov til å endre guild note, kan du med én knapp i Discord-fanen også legge navnet i guild noten. Da vises det i guildlista i spillet, også for dem uten Riket.

## Bruk

- **Åpne:** trykk J. Riket-fanene ligger på høyre side av vinduet, under Blizzards egne faner. `/riket` (eller `/nll`), NL-knappen ved minikartet og Riket i addon-lista under minikartet åpner også J-vinduet rett på Riket.
- **Lite guildvindu:** i det lille chat-moduset har ikke guildvinduet plass til Riket-fanene. Gjør vinduet stort igjen, så kommer de tilbake.
- **Officer chat:** officer chatten er som før og blir aldri blandet med de andre guildene.
- **Andre kommandoer:** `/riket members`, `/riket professions`, `/riket discord`, `/riket check` (viser hva Riket ser i guildvinduet), `/riket status` og `/riket button` (viser eller skjuler minimap-knappen).
- **Oppskrifter:** åpne hvert av dine yrkesvinduer én gang med Riket 1.4.4 eller nyere. Da leser Riket hvilke oppskrifter du kan og deler dem, også med dem som ser lista mens du er offline. WoW: Forever åpner ikke andres yrkeslenker, så Riket viser oppskriftene selv.

## Greit å vite

- **Hvem som ser hva:** bare de som har addonen ser de andre guildenes chat og lister. Det holder at én person med addonen er pålogget i hver guild.
- **Under bosskamper:** spillet skjuler guild chat for addons, så de linjene blir ikke sendt over.
- **Hvis noe ikke vises:** Riket skriver i chatten hvis noe feiler i guildvinduet, og `/riket check` forteller hva den ser.
- **Eldre versjoner:** folk med eldre versjon av Riket ser fortsatt chatten og medlemslistene, men ikke rank og Discord-navn. Hvem som er offline i en annen guild kommer fra den guildens relay når den har 1.4.3 eller nyere; før det ser du bare dem Riket har sett pålogget.
- **Andre addons:** Riket har egen kanal (`NLRiketNet`), egne lagrede data (`NLRiketDB`) og egne kommandoer, og kan være på samtidig med andre Nerdelandslaget-addons.
