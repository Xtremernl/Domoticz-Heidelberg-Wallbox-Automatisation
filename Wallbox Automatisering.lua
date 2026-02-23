----------------------------------------------------------------------------------------
--  Date: 21-02-2026
--  Wallbox Automatisering v0.3.16
--
--  Notificaties:
--    Soft overload (1x per sessie):
--       "Kleine overbelasting gedetecteerd — laadstroom wordt bijgeregeld."
--
--    Hard overload (1x per overbelasting-periode, geen spam):
--       "Grove overbelasting — laden tijdelijk gepauzeerd voor veiligheid."
--
--    Hard overload herstel (1x per herstelperiode):
--       "Grove overbelasting hersteld — laadstroom wordt bijgeregeld."
--
--  Gedrag:
--    - Soft overload → naar DYNAMIC + rustig terugregelen, geen pauze
--    - Hard overload → pauze + fuseProtection + notificatie (gelatcht)
--    - Pauze-release → dynamic 6A + herstelmelding (gelatcht)
--    - Variabele opbouwsnelheid (<20A snel, ≥20A langzaam)
--    - Handshake logging
--    - END logging
--    - Sessie start in DYNAMIC → dimmer terug naar 6A
----------------------------------------------------------------------------------------

local Script_Name    = 'Wallbox Automatisering'
local Script_Version = '0.3.16'

-- IDX mapping
local IDX_TARIEF                = 366
local IDX_MODE                  = 477
local IDX_PAUSE                 = 593
local IDX_LAADSTROOM_DIMMER     = 594
local IDX_LADER                 = 590
local IDX_SELECTOR              = 592

local IDX_WB_I_L1               = 576
local IDX_WB_I_L2               = 577
local IDX_WB_I_L3               = 578

local IDX_NET_I_L1              = 197
local IDX_NET_I_L2              = 595
local IDX_NET_I_L3              = 199

-- Settings
local LOOP_INTERVAL             = 10
local MIN_AMPERE                = 6

local CurrentIncreasing         = 0.10
local CurrentFastIncreasing     = 1.00
local CurrentDecreasing         = 0.50

local OVERLOAD_SOFT             = 25
local OVERLOAD_HARD_MIN         = 30
local PAUSE_RELEASE             = 17
local HYST_LOW                  = 23
local HYST_HIGH                 = 25

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
        level = domoticz.LOG_INFO,
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
        hardRecoveredNotified = { initial = false }
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
        -- 3. Tarief / Mode → Pauze
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
        -- 4. Stop als lader uit staat
        --------------------------------------------------------------------
        if lader.state ~= 'On' then return end

        --------------------------------------------------------------------
        -- 5. Loadbalancing basis
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
        -- 6. HARD OVERLOAD → dimmer 0%, DYNAMIC, pauze + gelatchte notificatie
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
        -- 7. Pauze-release → DYNAMIC op 6A + herstelmelding (gelatcht)
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
        -- 8. SOFT OVERLOAD (25–30A) → naar DYNAMIC + terugregelen + 1x notificatie
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
        -- 9. 6A niet genoeg → pauze (hard overload route)
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
        -- 10. Handshake logging
        --------------------------------------------------------------------
        if dz.data.dynamicStarted and maxAllowedA >= MIN_AMPERE and wbI < 2 then
            dz.log("Auto vraagt nog geen stroom → wachten op handshake")
            return
        end

        --------------------------------------------------------------------
        -- 11. Cap
        --------------------------------------------------------------------
        if sessionMaxA ~= nil and maxAllowedA > sessionMaxA then
            maxAllowedA = sessionMaxA
        end

        dz.data.maxAllowedA = maxAllowedA

        --------------------------------------------------------------------
        -- 12. Dimmer-aansturing
        --------------------------------------------------------------------
        modeLB = ((selector.level or 0) == 0) and 'DYNAMIC' or 'PRESET'

        if modeLB == 'DYNAMIC' then
            dimmer.setLevel(ampToDimmerLevel(maxAllowedA))
        end

        --------------------------------------------------------------------
        -- 13. Interval-regeling (opbouw / afbouw)
        --------------------------------------------------------------------
        local last = dz.data.lastRun or 0
        if now - last >= LOOP_INTERVAL then
            dz.data.lastRun = now

            local newA = maxAllowedA

            if dz.data.dynamicStarted then
                if wbI >= newA - 2 and wbI <= newA + 2 then

                    if maxNet < HYST_LOW then
                        if maxNet < 20 then
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
        -- 14. END-logging
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