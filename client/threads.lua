--[[ client/threads.lua ]]
-- This file contains all continuous, long-running loops.

-- Main Game Loop (Input, Menu Drawing)
CreateThread(function()
    while true do
        Wait(5)
        if menuNavCooldown > 0 then menuNavCooldown = menuNavCooldown - 1 end

        if (isMenuOpen or isDispatchMenuOpen or isVehicleMenuOpen) and not isPlayerPolice() then
            isMenuOpen, isDispatchMenuOpen, isVehicleMenuOpen = false, false, false
            closeInteractionMenu(true)
        end

        if IsControlJustReleased(0, Config.KeyToReopenMenu) and isPlayerPolice() and not isMenuOpen and not isDispatchMenuOpen and not isVehicleMenuOpen and not isBusy then
            if targetedPed and DoesEntityExist(targetedPed) and pedData[targetedPed] and pedData[targetedPed].isCuffed then
                if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(targetedPed)) < 5.0 then
                    startInteraction(targetedPed)
                else
                    notify("You are too far away to re-open the menu.")
                end
            end
        end

        if IsControlJustReleased(0, Config.KeyToOpenDispatchMenu) and isPlayerPolice() and isPoliceActive and not isMenuOpen and not isVehicleMenuOpen and not isBusy then
            isDispatchMenuOpen, currentActionIndex = not isDispatchMenuOpen, 1
        end

        if isMenuOpen then DrawAndHandleInteractionMenu()
        elseif isVehicleMenuOpen then DrawAndHandleVehicleMenu()
        elseif isDispatchMenuOpen then DrawAndHandleDispatchMenu()
        elseif isImpounding then DrawAndHandleImpoundMenu() end
    end
end)


-- Pursuit Distance Check Loop
CreateThread(function()
    while true do
        Wait(5000)
        if isTrafficStopActive and activePursuitVehicle and DoesEntityExist(activePursuitVehicle) then
            if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(activePursuitVehicle)) > Config.TrafficStop.GetAwayDistance then
                notify("~y~Pursuit canceled: Suspect has gotten away!")
                EndPursuit(activePursuitDriver, activePursuitVehicle, "Player got too far away")
                if pursuitCheckerThread then TerminateThread(pursuitCheckerThread); pursuitCheckerThread = nil end
            end
        end
    end
end)

-- Instant 'E' Key Detection for Traffic Stops
CreateThread(function()
    while true do
        Wait(0)
        if isPlayerPolice() and isPoliceActive and not isBusy and not isMenuOpen then
            local playerVeh = GetVehiclePedIsIn(PlayerPedId(), false)
            if playerVeh ~= 0 and IsVehicleSirenOn(playerVeh) and IsControlJustPressed(0, 38) then -- E key
                local targetVeh = GetVehicleAhead(playerVeh)
                if targetVeh and GetPedInVehicleSeat(targetVeh, -1) ~= 0 and not IsPedAPlayer(GetPedInVehicleSeat(targetVeh, -1)) then
                    StartTrafficStop(targetVeh)
                end
            end
        end
    end
end)

-- Background Traffic Violation Scanner
CreateThread(function()
    if not Config.TrafficScenarios.enabled then return end
    while true do
        Wait(Config.TrafficScenarios.checkInterval)
        if isPlayerPolice() and isPoliceActive and IsPedInAnyVehicle(PlayerPedId(), false) and not isTrafficStopActive then
            local playerVeh = GetVehiclePedIsIn(PlayerPedId(), false)
            local potentialViolators = {}
            for _, vehicle in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(vehicle) and vehicle ~= playerVeh and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) < Config.TrafficScenarios.checkRadius then
                    local driver = GetPedInVehicleSeat(vehicle, -1)
                    if DoesEntityExist(driver) and not IsPedAPlayer(driver) and NetworkGetNetworkIdFromEntity(driver) then
                        table.insert(potentialViolators, { vehicle = vehicle, driver = driver })
                    end
                end
            end
            if #potentialViolators > 0 and math.random(1, Config.TrafficScenarios.triggerChance) == 1 then
                local selected = potentialViolators[math.random(#potentialViolators)]
                startTrafficViolation(selected.vehicle, selected.driver, 'DANGEROUS_DRIVING')
            end
        end
    end
end)

TriggerServerEvent('police:server:requestPulledOverVehicles')


CreateThread(function()
    local lightsOffStartTime = nil
    while true do
        Wait(2000) -- Check every 2 seconds

        -- Only run this logic if a pursuit is active
        if isTrafficStopActive and activePursuitDriver then
            local playerPed = PlayerPedId()
            local policeVeh = GetVehiclePedIsIn(playerPed, false)
            
            -- Condition 1: Player drives too far away
            if #(GetEntityCoords(playerPed) - GetEntityCoords(activePursuitDriver)) > Config.TrafficStop.cancelPursuitOnDistance then
                debugLog("Pursuit canceled: Officer is too far from the suspect.")
                CancelPursuit(activePursuitDriver, activePursuitVehicle, "Officer disengaged")
            end

            -- Condition 2: Player turns off lights/siren for too long
            if DoesEntityExist(policeVeh) and not IsVehicleSirenOn(policeVeh) then
                if not lightsOffStartTime then
                    lightsOffStartTime = GetGameTimer()
                    debugLog("Pursuit: Police lights OFF detected, starting cancel timer...")
                elseif GetGameTimer() - lightsOffStartTime > Config.TrafficStop.cancelPursuitOnLightsOffTime then
                    debugLog("Pursuit: Lights off for duration, canceling.")
                    CancelPursuit(activePursuitDriver, activePursuitVehicle, "Officer disengaged")
                end
            else
                lightsOffStartTime = nil -- Lights are on, reset the timer
            end
        else
            -- No pursuit active, ensure timer is reset
            lightsOffStartTime = nil
        end
    end
end)

-- NEW: Manual Pursuit Keybind Thread (G Key)
CreateThread(function()
    while true do
        Wait(0)
        -- Check if player is police, in a car with lights on, not busy, and presses G
        if isPlayerPolice() and not isBusy and not isTrafficStopActive and IsControlJustPressed(0, Config.KeyToForcePursuit) then
            local policeVeh = GetVehiclePedIsIn(PlayerPedId(), false)
            if policeVeh ~= 0 and IsVehicleSirenOn(policeVeh) then
                local targetVeh = GetVehicleAhead(policeVeh)
                if targetVeh then
                    local driver = GetPedInVehicleSeat(targetVeh, -1)
                    if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
                        notify("~r~Forcing suspect to flee!")
                        debugLog("Manual pursuit forced with G key.")
                        isBusy = true
                        isTrafficStopActive = true
                        generateRandomPedData(driver)
                        updateSyncedPedState(driver, pedData[driver])
                        HandleFleeingSuspect(targetVeh, driver)
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    if not Config.CrimeLevelEvents.enabled then return end

    local lastCrashTime = 0
    local lastRedLightTime = 0

    while true do
        Wait(500) -- Check every half-second

        if isTrafficStopActive and activePursuitVehicle and DoesEntityExist(activePursuitVehicle) then
            local driver = GetPedInVehicleSeat(activePursuitVehicle, -1)
            if DoesEntityExist(driver) and driver == activePursuitDriver then
                local currentTime = GetGameTimer()
                
                -- 1. Check for crashes
                if GetEntitySpeed(activePursuitVehicle) < 5.0 and HasEntityCollidedWithAnything(activePursuitVehicle) and (currentTime - lastCrashTime > 5000) then
                    debugLog("Pursuit Watchdog: Suspect has crashed. Incrementing crime level.")
                    TriggerServerEvent('police:server:incrementCrimeLevel', PedToNet(driver), Config.CrimeLevelEvents.incrementOnCrash)
                    lastCrashTime = currentTime
                    -- Reset the collision status to prevent it from firing repeatedly
                    ClearEntityLastDamageEntity(activePursuitVehicle)
                end

                -- 2. Check for running red lights
                if IsVehicleStoppedAtTrafficLight(activePursuitVehicle) and (currentTime - lastRedLightTime > 10000) then
                    local _, trafficLightState = GetVehicleLightState(activePursuitVehicle)
                    -- 1 = Red light
                    if trafficLightState == 1 then
                        debugLog("Pursuit Watchdog: Suspect ran a red light. Incrementing crime level.")
                        TriggerServerEvent('police:server:incrementCrimeLevel', PedToNet(driver), Config.CrimeLevelEvents.incrementOnRedLight)
                        lastRedLightTime = currentTime
                    end
                end
            end
        end
    end
end)

-- client/functions/data_generation.lua (add near bottom)

function ensureChecksTable(ped)
    pedData[ped] = pedData[ped] or generateRandomPedData(ped)
    local data = pedData[ped]

    if not data.checksCompleted then
        data.checksCompleted = {
            breathalyze = false,
            drugtest = false,
            search = false,
            fingerprint = false
        }
    end

    return data.checksCompleted
end
