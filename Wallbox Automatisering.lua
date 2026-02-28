----------------------------------------------------------------------------------------
--  Date: 23-02-2026
--  Wallbox Automatisering v0.3.18
--  Engineer    : XtremerNL
--
--  Notificaties:
--    Soft overload (1x per sessie):
--       "Kleine overbelasting gedetecteerd — laadstroom wordt bijgeregeld."
--
--    Hard overload (1x per overbelasting-periode):
--       "Grove overbelasting — laden tijdelijk gepauzeerd voor veiligheid."
--
--    Hard overload herstel (1x per herstelperiode):
--       "Grove overbelasting hersteld — laadstroom wordt bijgeregeld."
--
--    Communicatie-failsafe (ALTIJD melden):
--       "Netmeting verlopen — laden tijdelijk gepauzeerd voor veiligheid."
--       "Netmeting hersteld — laden hervat op veilige stroom."
--
--  Gedrag:
--    - Soft overload → naar DYNAMIC + rustig terugregelen, geen pauze
--    - Hard overload → pauze + fuseProtection + notificatie (gelatcht)
--    - Pauze-release → dynamic 6A + herstelmelding (gelatcht)
--    - Communicatie-failsafe → pauze + ALTIJD melding + herstelmelding
--    - Variabele opbouwsnelheid:
--         < FastIncreaseThreshold  → snelle opbouw
--         ≥ FastIncreaseThreshold → langzame opbouw
--    - Hysteresis opbouw/afbouw (HYST_LOW / HYST_HIGH)
--    - Handshake logging (auto vraagt nog geen stroom)
--    - END logging (statusoverzicht)
--    - Sessie start in DYNAMIC → dimmer terug naar 6A
----------------------------------------------------------------------------------------

local Script_Name    = 'Wallbox Automatisering'
local Script_Version = '0.3.18'

-- IDX mapping (koppeling naar Domoticz devices)
local IDX_TARIEF                = 366   -- Tariefschakeling (peak/dal) voor tarief-blokkering
local IDX_MODE                  = 477   -- Handmatige modus (Auto / Alleen-dal / Uit)
local IDX_PAUSE                 = 593   -- Pauzeer-knop van de wallbox (On/Off)
local IDX_LAADSTROOM_DIMMER     = 594   -- Dimmer die de laadstroom (6–16A) aanstuurt
local IDX_LADER                 = 590   -- Wallbox status (On = laden, Off = geen sessie)
local IDX_SELECTOR              = 592   -- Preset selector (6A/8A/10A/13A/16A of Dynamic)

-- Wallbox stroommetingen per fase
local IDX_WB_I_L1               = 576   -- Wallbox stroom L1 (A)
local IDX_WB_I_L2               = 577   -- Wallbox stroom L2 (A)
local IDX_WB_I_L3               = 578   -- Wallbox stroom L3 (A)

-- Netstroommetingen per fase
local IDX_NET_I_L1              = 197   -- Netstroom L1 (A)
local IDX_NET_I_L2              = 198   -- Netstroom L2 (A)
local IDX_NET_I_L3              = 199   -- Netstroom L3 (A)


-- Settings (gedrag van de loadbalancing en beveiligingen)
local LOOP_INTERVAL             = 10    -- Interval (sec) voor opbouw/afbouw van laadstroom
local MIN_AMPERE                = 6     -- Minimale laadstroom (veiligheidswaarde)

-- Dynamische opbouw/afbouw snelheden
local CurrentIncreasing         = 0.10  -- Langzame opbouw (A per interval) bij hogere netbelasting
local CurrentFastIncreasing     = 1.00  -- Snelle opbouw (A per interval) bij lage netbelasting
local FastIncreaseThreshold 	= 20   	-- Onder deze netstroom mag de laadstroom snel omhoog
local CurrentDecreasing         = 0.50  -- Afbouw (A per interval) bij soft overload

-- Overload drempels
local OVERLOAD_SOFT             = 25    -- Soft overload drempel (A) → terugregelen, geen pauze
local OVERLOAD_HARD_MIN         = 30    -- Hard overload drempel (A) → directe pauze

-- Pauze-release drempel
local PAUSE_RELEASE             = 17    -- Onder deze netstroom mag de pauze worden opgeheven

-- Hysteresis band voor opbouw/afbouw
local HYST_LOW                  = 23    -- Onder deze waarde mag laadstroom langzaam omhoog
local HYST_HIGH                 = 25    -- Boven deze waarde moet laadstroom omlaag

-- Communicatie failsafe
local NETCOMM_TIMEOUT           = 10    -- Max leeftijd (sec) van netmetingen; ouder = pauze failsafe

-----------------------------------------------------------------------
-- Helper functions
-----------------------------------------------------------------------

local function presetToAmp(level)
    if level == 10 then return 6 end
    if level == 20 then return 8 end
    if level == 30 then return 10 end
    if level == 40 then return 13 end
    if level == 50 then return 16 end
    return nil
end

local function dimmerToAmp(level)
    return 6 + (level / 10)
end

local function ampToDimmerLevel(amp)
    local lvl = (amp - 6) * 10
    if lvl < 0 then lvl = 0 end
    if lvl > 100 then lvl = 100 end
    return lvl
end

local function wallboxCurrent(dz)
    local i1 = tonumber(dz.devices(IDX_WB_I_L1).sValue) or 0
    local i2 = tonumber(dz.devices(IDX_WB_I_L2).sValue) or 0
    local i3 = tonumber(dz.devices(IDX_WB_I_L3).sValue) or 0
    return math.max(i1, i2, i3)
end

-----------------------------------------------------------------------
-- Script
-----------------------------------------------------------------------

return {
    on = {
        devices = {
            IDX_TARIEF, IDX_MODE, IDX_PAUSE, IDX_SELECTOR,
            IDX_NET_I_L1, IDX_NET_I_L2, IDX_NET_I_L3,
            IDX_WB_I_L1, IDX_WB_I_L2, IDX_WB_I_L3,
            IDX_LADER
        },
        timer = { 'every 10 seconds' },
        system = { 'start' }
    },

    logging = {
        -- level = domoticz.LOG_DEBUG,      -- UnComment voor Debug logging.
        marker = Script_Name .. ' v' .. Script_Version
    },

    data = {
        maxAllowedA           = { initial = nil },
        sessionMaxA           = { initial = nil },
        pauseBySystem         = { initial = false },
        dynamicStarted        = { initial = false },
        lastRun               = { initial = 0 },
        sessionActive         = { initial = false },
        fuseProtectionActive  = { initial = false },
        sessionPresetLevel    = { initial = nil },
        sessionPresetAmp      = { initial = nil },
    
        -- Notificatie flags
        softNotified          = { initial = false },
    
        hardOverloadActive    = { initial = false },
        hardOverloadNotified  = { initial = false },
        hardRecoveredNotified = { initial = false },
    
        -- Communicatie failsafe status
        netCommFaultActive    = { initial = false }
    },

    execute = function(dz)

        local now      = os.time()
        local tarief   = dz.devices(IDX_TARIEF)
        local mode     = dz.devices(IDX_MODE)
        local pause    = dz.devices(IDX_PAUSE)
        local selector = dz.devices(IDX_SELECTOR)
        local dimmer   = dz.devices(IDX_LAADSTROOM_DIMMER)
        local lader    = dz.devices(IDX_LADER)

        --------------------------------------------------------------------
        -- 1. Sessiestart
        --------------------------------------------------------------------
        if lader.state == 'On' and not dz.data.sessionActive then
            dz.data.sessionActive         = true
            dz.data.fuseProtectionActive  = false

            dz.data.softNotified          = false
            dz.data.hardOverloadActive    = false
            dz.data.hardOverloadNotified  = false
            dz.data.hardRecoveredNotified = false

            local startLevel = selector.level or 0
            local startAmp   = presetToAmp(startLevel)

            dz.data.sessionPresetLevel = startLevel
            dz.data.sessionPresetAmp   = startAmp

            dz.log("Sessie gestart → preset opgeslagen")

            -- Start in DYNAMIC → dimmer terug naar 6A
            if startLevel == 0 then
                dz.log("Sessie start in DYNAMIC → dimmer terug naar 6A")
                dz.data.maxAllowedA    = MIN_AMPERE
                dz.data.dynamicStarted = true
                dimmer.setLevel(ampToDimmerLevel(MIN_AMPERE))
            end
        end

        --------------------------------------------------------------------
        -- 2. Sessie-einde
        --------------------------------------------------------------------
        if lader.state == 'Off' and dz.data.sessionActive then

            if dz.data.fuseProtectionActive
               and dz.data.sessionPresetLevel ~= nil
               and dz.data.sessionPresetLevel ~= 0
            then
                dz.log("Sessie geëindigd → preset herstellen")
                selector.setLevel(dz.data.sessionPresetLevel)
            end

            -- Reset notificatie flags
            dz.data.softNotified          = false
            dz.data.hardOverloadActive    = false
            dz.data.hardOverloadNotified  = false
            dz.data.hardRecoveredNotified = false

            dz.data.sessionActive        = false
            dz.data.sessionMaxA          = nil
            dz.data.maxAllowedA          = nil
            dz.data.dynamicStarted       = false
            dz.data.pauseBySystem        = false
            dz.data.fuseProtectionActive = false
            dz.data.sessionPresetLevel   = nil
            dz.data.sessionPresetAmp     = nil

            return
        end
		
		--------------------------------------------------------------------
		-- 3. Failsafe: netmeting te oud → pauze
		--------------------------------------------------------------------

		if lader.state == 'On' then

			-- Leeftijd van alle drie de fases bepalen
			local ageL1 = dz.devices(IDX_NET_I_L1).lastUpdate.secondsAgo
			local ageL2 = dz.devices(IDX_NET_I_L2).lastUpdate.secondsAgo
			local ageL3 = dz.devices(IDX_NET_I_L3).lastUpdate.secondsAgo


			-- Als één van de drie ouder is dan NETCOMM_TIMEOUT → FAILSAFE
			local commFault =
				(ageL1 > NETCOMM_TIMEOUT) or
				(ageL2 > NETCOMM_TIMEOUT) or
				(ageL3 > NETCOMM_TIMEOUT)

			if commFault then

				-- Meld ALTIJD wanneer de netmeting verlopen is
				dz.notify("Wallbox",
					"Netmeting verlopen — laden tijdelijk gepauzeerd voor veiligheid.",
					dz.PRIORITY_HIGH)

				-- Activeer failsafe-status
				dz.data.netCommFaultActive    = true

				-- Pauzeer laden
				dz.data.pauseBySystem        = true
				dz.data.dynamicStarted       = false
				dz.data.maxAllowedA          = MIN_AMPERE
				dz.data.fuseProtectionActive = true

				dimmer.setLevel(0)
				selector.setLevel(0)
				pause.switchOn()

				-- In failsafe blijven, niets anders doen
				return
			end

			-- Herstel: alle drie de fases zijn weer vers (< NETCOMM_TIMEOUT)
			if dz.data.netCommFaultActive then

				-- Meld ALTIJD wanneer de netmeting hersteld is
				dz.notify("Wallbox",
					"Netmeting hersteld — laden hervat op veilige stroom.",
					dz.PRIORITY_NORMAL)

				-- Reset failsafe-status
				dz.data.netCommFaultActive = false

				-- Herstel naar veilige DYNAMIC 6A
				dz.data.pauseBySystem  = false
				dz.data.dynamicStarted = true
				dz.data.maxAllowedA    = MIN_AMPERE

				selector.setLevel(0)
				dimmer.setLevel(ampToDimmerLevel(MIN_AMPERE))
				pause.switchOff()
			end
		end

        --------------------------------------------------------------------
        -- 4. Tarief / Mode → Pauze
        --------------------------------------------------------------------
        local modeLevel   = mode.level
        local tariefLevel = tarief.level

        local finalPause =
            (modeLevel == 30) or
            (modeLevel == 20 and tariefLevel ~= 10)

        if finalPause and pause.state ~= 'On' then
            pause.switchOn()
            return
        end

        if not finalPause and pause.state ~= 'Off' and not dz.data.pauseBySystem then
            pause.switchOff()
        end

        --------------------------------------------------------------------
        -- 5. Stop als lader uit staat
        --------------------------------------------------------------------
        if lader.state ~= 'On' then return end

        --------------------------------------------------------------------
        -- 6. Loadbalancing basis
        --------------------------------------------------------------------
        local selectorLevel = selector.level or 0
        local presetA       = presetToAmp(selectorLevel)
        local dimmerA       = dimmerToAmp(dimmer.level)

        if presetA ~= nil then
            dz.data.sessionMaxA = presetA
        end

        local sessionMaxA = dz.data.sessionMaxA
        local maxAllowedA = dz.data.maxAllowedA or sessionMaxA or dimmerA

        local netI1 = tonumber(dz.devices(IDX_NET_I_L1).sValue) or 0
        local netI2 = tonumber(dz.devices(IDX_NET_I_L2).sValue) or 0
        local netI3 = tonumber(dz.devices(IDX_NET_I_L3).sValue) or 0
        local maxNet = math.max(netI1, netI2, netI3)

        local wbI   = wallboxCurrent(dz)
        local modeLB = (selectorLevel == 0) and 'DYNAMIC' or 'PRESET'

        --------------------------------------------------------------------
        -- 7. HARD OVERLOAD → dimmer 0%, DYNAMIC, pauze + gelatchte notificatie
        --------------------------------------------------------------------
        if maxNet >= OVERLOAD_HARD_MIN then

            dz.log("HARD OVERLOAD → dimmer 0%, DYNAMIC, pauze")

            -- Latch: we zitten in een hard-overload periode
            if not dz.data.hardOverloadActive then
                dz.data.hardOverloadActive    = true
                dz.data.hardRecoveredNotified = false -- herstelmelding opnieuw mogelijk
            end

            -- Notificatie: 1x per overbelasting-periode
            if not dz.data.hardOverloadNotified then
                dz.notify("Wallbox", "Grove overbelasting - laden tijdelijk gepauzeerd voor veiligheid.", dz.PRIORITY_HIGH)
                dz.data.hardOverloadNotified = true
            end

            dimmer.setLevel(0)
            selector.setLevel(0)

            dz.data.pauseBySystem        = true
            dz.data.dynamicStarted       = false
            dz.data.maxAllowedA          = MIN_AMPERE
            dz.data.fuseProtectionActive = true

            pause.switchOn()
            return
        end

        --------------------------------------------------------------------
        -- 8. Pauze-release → DYNAMIC op 6A + herstelmelding (gelatcht)
        --------------------------------------------------------------------
        if dz.data.pauseBySystem and maxNet < PAUSE_RELEASE then

            dz.log("Pauze opgeheven → DYNAMIC op 6A")

            -- We verlaten de hard-overload periode
            if dz.data.hardOverloadActive then
                dz.data.hardOverloadActive   = false
                dz.data.hardOverloadNotified = false -- nieuwe overload mag weer melden

                -- Herstelmelding: 1x per herstelperiode
                if not dz.data.hardRecoveredNotified then
                    dz.notify("Wallbox", "Grove overbelasting hersteld - laadstroom wordt bijgeregeld.", dz.PRIORITY_NORMAL)
                    dz.data.hardRecoveredNotified = true
                end
            end

            dz.data.pauseBySystem  = false
            dz.data.dynamicStarted = true
            dz.data.maxAllowedA    = MIN_AMPERE

            selector.setLevel(0)
            dimmer.setLevel(ampToDimmerLevel(MIN_AMPERE))

            pause.switchOff()
            return
        end

        if dz.data.pauseBySystem then return end

        --------------------------------------------------------------------
        -- 9. SOFT OVERLOAD (25–30A) → naar DYNAMIC + terugregelen + 1x notificatie
        --------------------------------------------------------------------
        if maxNet > OVERLOAD_SOFT and maxNet < OVERLOAD_HARD_MIN then

            dz.log("SOFT OVERLOAD → naar DYNAMIC + rustig terugregelen (geen pauze)")

            if not dz.data.softNotified then
                dz.notify("Wallbox", "Kleine overbelasting gedetecteerd - laadstroom wordt bijgeregeld.", dz.PRIORITY_NORMAL)
                dz.data.softNotified = true
            end

            selector.setLevel(0)
            dz.data.dynamicStarted = true

            local newA = math.max(MIN_AMPERE, maxAllowedA - CurrentDecreasing)
            dz.data.maxAllowedA = newA

            dimmer.setLevel(ampToDimmerLevel(newA))

            return
        end

        --------------------------------------------------------------------
        -- 10. 6A niet genoeg → pauze (hard overload route)
        --------------------------------------------------------------------
        if maxAllowedA <= MIN_AMPERE and maxNet > OVERLOAD_SOFT then

            dz.log("6A niet genoeg → dimmer 0%, DYNAMIC, pauze")

            -- Latch hard overload periode
            if not dz.data.hardOverloadActive then
                dz.data.hardOverloadActive    = true
                dz.data.hardRecoveredNotified = false
            end

            if not dz.data.hardOverloadNotified then
                dz.notify("Wallbox", "Grove overbelasting - laden tijdelijk gepauzeerd voor veiligheid.", dz.PRIORITY_HIGH)
                dz.data.hardOverloadNotified = true
            end

            dimmer.setLevel(0)
            selector.setLevel(0)

            dz.data.pauseBySystem        = true
            dz.data.dynamicStarted       = false
            dz.data.maxAllowedA          = MIN_AMPERE
            dz.data.fuseProtectionActive = true

            pause.switchOn()
            return
        end

        --------------------------------------------------------------------
        -- 11. Handshake logging
        --------------------------------------------------------------------
        if dz.data.dynamicStarted and maxAllowedA >= MIN_AMPERE and wbI < 2 then
            dz.log("Auto vraagt nog geen stroom → wachten op handshake")
            return
        end

        --------------------------------------------------------------------
        -- 12. Cap
        --------------------------------------------------------------------
        if sessionMaxA ~= nil and maxAllowedA > sessionMaxA then
            maxAllowedA = sessionMaxA
        end

        dz.data.maxAllowedA = maxAllowedA

        --------------------------------------------------------------------
        -- 13. Dimmer-aansturing
        --------------------------------------------------------------------
        modeLB = ((selector.level or 0) == 0) and 'DYNAMIC' or 'PRESET'

        if modeLB == 'DYNAMIC' then
            dimmer.setLevel(ampToDimmerLevel(maxAllowedA))
        end

        --------------------------------------------------------------------
        -- 14. Interval-regeling (opbouw / afbouw)
        --------------------------------------------------------------------
        local last = dz.data.lastRun or 0
        if now - last >= LOOP_INTERVAL then
            dz.data.lastRun = now

            local newA = maxAllowedA

            if dz.data.dynamicStarted then
                if wbI >= newA - 2 and wbI <= newA + 2 then

                    if maxNet < HYST_LOW then
                        if maxNet < FastIncreaseThreshold then
                            newA = newA + CurrentFastIncreasing
                        else
                            newA = newA + CurrentIncreasing
                        end
                    elseif maxNet > HYST_HIGH then
                        newA = math.max(MIN_AMPERE, newA - CurrentDecreasing)
                    end
                end
            end

            if sessionMaxA ~= nil and newA > sessionMaxA then
                newA = sessionMaxA
            end

            dz.data.maxAllowedA = newA

            if modeLB == 'DYNAMIC' then
                dimmer.setLevel(ampToDimmerLevel(newA))
            end
        end

        --------------------------------------------------------------------
        -- 15. END-logging
        --------------------------------------------------------------------
        dz.log(string.format(
            "END | WB=%.2fA | Net=%.2fA | maxAllowedA=%.2fA | Mode=%s | Pause=%s | FuseProtection=%s | sessionPresetLevel=%s | sessionPresetAmp=%s",
            wbI, maxNet, dz.data.maxAllowedA, modeLB, tostring(pause.state),
            tostring(dz.data.fuseProtectionActive),
            dz.data.sessionPresetLevel and tostring(dz.data.sessionPresetLevel) or "nil",
            dz.data.sessionPresetAmp and tostring(dz.data.sessionPresetAmp) or "nil"
        ))

    end
}
