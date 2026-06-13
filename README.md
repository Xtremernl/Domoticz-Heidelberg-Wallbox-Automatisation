📘 #Wallbox Automatisering (Domoticz DZvents)
Slimme EV‑loadbalancing met tarief‑blokkering, soft/hard overload‑beveiliging, automatische pauze‑herstel en optionele thuisbatterij‑integratie.

Dit DZvents‑script regelt het laadvermogen van een elektrische auto op een manier die vergelijkbaar is met professionele industriële loadcontrollers.
Het combineert real‑time netstroommeting, dynamische laadstroomregeling, tarief‑gebaseerde blokkering, veiligheidslogica en operator‑vriendelijke notificaties in één robuust systeem.

Het script is ontworpen voor Domoticz en werkt met elke wallbox die via een dimmer‑device (laadstroom) en een selector (preset/dynamic) kan worden aangestuurd.

✨ Belangrijkste functies
💡 Tarief‑blokkering (peak/off‑peak control)
Het script kan laden automatisch blokkeren op basis van het actuele energietarief.

Laden toegestaan tijdens daluren

Laden geblokkeerd tijdens piekuren

Handmatige override mogelijk

Pauze wordt automatisch gezet en weer opgeheven

Ideaal voor dynamische energiecontracten of vaste piek/dal‑tarieven.

🔌 Dynamische loadbalancing (DYNAMIC‑mode)
Het script regelt automatisch de laadstroom op basis van de actuele netbelasting.

Snelle opbouw bij lage netbelasting

Langzame opbouw bij hogere belasting

Automatische afbouw bij dreigende overbelasting

Handshake‑detectie wanneer de auto nog geen stroom vraagt

⚡ Soft overload (25–30A)
Bij lichte overstroom:

Geen pauze

Automatisch terugregelen

Direct overschakelen naar DYNAMIC

1 notificatie per sessie

“Kleine overbelasting gedetecteerd — laadstroom wordt bijgeregeld.”

🔥 Hard overload (≥30A)
Bij zware overstroom:

Laden wordt gepauzeerd

Dimmer naar 0%

DYNAMIC‑mode geactiveerd

FuseProtection actief

1 notificatie per overbelasting‑periode

“Grove overbelasting — laden tijdelijk gepauzeerd voor veiligheid.”

🔄 Hard overload herstel
Wanneer de netbelasting weer veilig is:

Pauze wordt automatisch opgeheven

Laadstroom start veilig op 6A

1 herstelmelding per periode

“Grove overbelasting hersteld — laadstroom wordt bijgeregeld.”

🧠 Sessie‑intelligentie
Preset wordt opgeslagen bij sessiestart

Preset wordt hersteld bij sessie‑einde (indien fuseProtection actief was)

Notificatie‑latches worden automatisch gereset

Start in DYNAMIC → altijd veilig terug naar 6A

📊 Logging
Het script logt:

Overload‑detectie

Pauze‑acties

Tarief‑blokkering

Herstelmomenten

Handshake‑status

Eindsamenvatting per cyclus

🛡 Veiligheid boven alles
Het script is ontworpen met industriële principes:

Hysteresis

Set/Reset‑latches

Failsafe‑states

Geen oscillatie

Geen notificatie‑spam

Geen onnodige pauzes

🔋 Thuisbatterij‑integratie (optioneel)
Vanaf versie v0.3.19 ondersteunt het script optionele integratie met een thuisaccu.
Doel: voorkomen dat een thuisbatterij ontlaadt om de EV te voeden tijdens het laden.

Het script gebruikt hiervoor een Domoticz‑schakelaar:

IDX 610 – “Batterijen Ontladen”

On  → thuisaccu mag ontladen

Off → thuisaccu wordt geblokkeerd (ontladen niet toegestaan)

Automatisch gedrag
Auto is actief aan het laden  
→ thuisaccu‑ontladen wordt geblokkeerd

Laden is gepauzeerd (tarief, overload, failsafe, handmatig)
→ thuisaccu mag ontladen

Laadsessie eindigt  
→ thuisaccu mag ontladen

Deze functie is volledig optioneel:
als IDX 610 niet bestaat, wordt de functie automatisch genegeerd.

📦 Voor wie is dit script bedoeld?
Domoticz‑gebruikers met een EV‑lader

Installaties met beperkte hoofdzekeringen

Situaties waar loadbalancing cruciaal is

Engineers die maximale controle en veiligheid willen
