# Wallbox Automatisering (Domoticz DZvents)

Slimme EV‑loadbalancing met tarief‑blokkering, soft/hard overload‑beveiliging en automatische pauze‑herstel
Dit DZvents‑script regelt het laadvermogen van een elektrische auto op een manier die vergelijkbaar is met professionele industriële loadcontrollers. Het combineert real‑time netstroommeting, dynamische laadstroomregeling, tarief‑gebaseerde blokkering, veiligheidslogica, en operator‑vriendelijke notificaties in één robuust systeem.
Het script is ontworpen voor Domoticz en werkt met elke wallbox die via een dimmer‑device (laadstroom) en een selector (preset/dynamic) kan worden aangestuurd.

✨ Belangrijkste functies
💡 Tarief‑blokkering (peak/off‑peak control)
Het script kan laden automatisch blokkeren op basis van het actuele energietarief.
- Laden toegestaan tijdens daluren
- Laden geblokkeerd tijdens piekuren
- Handmatige override mogelijk
- Pauze wordt automatisch gezet en weer opgeheven
Dit maakt het ideaal voor dynamische energiecontracten of vaste piek/dal‑tarieven.

🔌 Dynamische loadbalancing (DYNAMIC‑mode)
Het script regelt automatisch de laadstroom op basis van de actuele netbelasting.
- Snelle opbouw bij lage netbelasting
- Langzame opbouw bij hogere belasting
- Automatische afbouw bij dreigende overbelasting
- Handshake‑detectie wanneer de auto nog geen stroom vraagt

⚡ Soft overload (25–30A)
Bij lichte overstroom:
- Geen pauze
- Automatisch terugregelen
- Direct overschakelen naar DYNAMIC
- 1 notificatie per sessie
- “Kleine overbelasting gedetecteerd — laadstroom wordt bijgeregeld.”
🔥 Hard overload (≥30A)Bij zware overstroom:- Laden wordt gepauzeerd
- Dimmer naar 0%
- DYNAMIC‑mode geactiveerd
- FuseProtection actief
- 1 notificatie per overbelasting‑periode
- “Grove overbelasting — laden tijdelijk gepauzeerd voor veiligheid.”
🔄 Hard overload herstelWanneer de netbelasting weer veilig is:- Pauze wordt automatisch opgeheven
- Laadstroom start veilig op 6A
- 1 herstelmelding per periode
- “Grove overbelasting hersteld — laadstroom wordt bijgeregeld.”
🧠 Sessie‑intelligentie- Preset wordt opgeslagen bij sessiestart
- Preset wordt hersteld bij sessie‑einde (indien fuseProtection actief was)
- Notificatie‑latches worden automatisch gereset
- Start in DYNAMIC → altijd veilig terug naar 6A
📊 LoggingHet script logt:- Overload‑detectie
- Pauze‑acties
- Tarief‑blokkering
- Herstelmomenten
- Handshake‑status
- Eindsamenvatting per cyclus
🛡 Veiligheid boven allesHet script is ontworpen met industriële principes:- Hysteresis
- Set/Reset‑latches
- Failsafe‑states
- Geen oscillatie
- Geen notificatie‑spam
- Geen onnodige pauzes
📦 Voor wie is dit script bedoeld?- Domoticz‑gebruikers met een EV‑lader
- Installaties met beperkte hoofdzekeringen
- Situaties waar loadbalancing cruciaal is
- Gebruikers met dynamische energiecontracten
- Engineers die maximale controle en veiligheid willen
