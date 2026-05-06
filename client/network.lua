--[[ client/network.lua ]]
-- This file contains all network event handlers for the client.

RegisterNetEvent("police:updatePedData", function(netId, data)
    debugLog(string.format("Received 'police:updatePedData' for Net ID: %s", netId))
    local ped
    local timeout = 2000
    while not DoesEntityExist(ped) and timeout > 0 do
        ped = NetworkGetEntityFromNetworkId(netId)
        Wait(50)
        timeout = timeout - 50
    end

    if not DoesEntityExist(ped) then
        debugLog("-> Ped does not exist on client after waiting. Ignoring update.")
        return
    end

    local hadCuffs = pedData[ped] and pedData[ped].isCuffed or false
    pedData[ped] = data

    if not pedData[ped].checksCompleted then
        pedData[ped].checksCompleted = { breathalyze = false, drugtest = false, search = false, fingerprint = false }
    end

    if pedData[ped].isCuffed then
        if not hadCuffs and not IsPedInAnyVehicle(ped, false) then
            debugLog("-> Ped state changed to cuffed, playing animation and freezing position.")
            ClearPedTasksImmediately(ped)
            LoadAnimDict("mp_arresting")
            TaskPlayAnim(ped, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
            FreezeEntityPosition(ped, true)
        end
    elseif hadCuffs then
        debugLog("-> Ped state changed to uncuffed, unfreezing position.")
        FreezeEntityPosition(ped, false)
        ClearPedTasks(ped)
    end
end)

RegisterNetEvent('police:client:forceLeaveVehicle', function(vehNetId, seatIndex, requestingPlayerSrc)
    local vehicle = NetToVeh(vehNetId)
    if not vehicle or not DoesEntityExist(vehicle) then return end

    local suspect = GetPedInVehicleSeat(vehicle, seatIndex)
    if not suspect or not DoesEntityExist(suspect) then return end

    debugLog("Received command from server to make owned ped exit vehicle.")
    TaskLeaveVehicle(suspect, vehicle, 0)
    
    if pedData[suspect] then
        pedData[suspect].inVehicle = false
        updateSyncedPedState(suspect, {inVehicle = false})
    end

    -- Only the officer who made the request gets the notification and menu
    if GetPlayerServerId(PlayerId()) == requestingPlayerSrc then
        notify("Suspect is exiting the vehicle.")
        CreateThread(function()
            local timeout = 5000
            while IsPedInAnyVehicle(suspect, false) and timeout > 0 do
                Wait(100)
                timeout = timeout - 100
            end
            if timeout > 0 and DoesEntityExist(suspect) then
                Wait(500)
                startInteraction(suspect)
            end
        end)
    end
end)



RegisterNetEvent("police:clearPedDataClient", function(netId)
    debugLog(string.format("Received 'police:clearPedDataClient' for Net ID: %s", netId))
    local ped = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(ped) then
        if ped == activePursuitDriver then
            EndPursuit(ped, activePursuitVehicle, "Ped data cleared by server")
        end
        pedData[ped] = nil
    end
end)

RegisterNetEvent("police:newCallout", function(calloutData, coords, pedNetId, opponentNetId)
    ForceClearCallout()
    debugLog("Received 'police:newCallout' event from server.")
    if not isPlayerPolice() or not isPoliceActive then
        debugLog("-> Ignoring callout, player is not police or is inactive.")
        return
    end

    if Config.Callouts.playSound then
        PlaySoundFrontend(-1, "Event_Start_Text", "GTAO_FM_Events_Soundset", true)
    end

    local calloutPed = NetworkGetEntityFromNetworkId(pedNetId)
    if not DoesEntityExist(calloutPed) then Wait(1000); calloutPed = NetworkGetEntityFromNetworkId(pedNetId) end
    if not DoesEntityExist(calloutPed) then debugLog("-> FAILED: Could not find primary callout ped on client."); return end

    activeCalloutPedEntity = calloutPed
    SetEntityAsMissionEntity(calloutPed, true, true)
    if calloutData.walkstyle then
        RequestAnimSet(calloutData.walkstyle)
        while not HasAnimSetLoaded(calloutData.walkstyle) do Wait(50) end
        SetPedMovementClipset(calloutPed, calloutData.walkstyle, 1.0)
    end
    
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z))
    notify("~b~[DISPATCH] New Callout: ~w~" .. calloutData.name)
    notify("~y~[DISPATCH] Details: ~w~" .. calloutData.description .. " at/near " .. street)
    
    local entityToBlip = calloutPed
    if calloutData.scenario == "drunk_driver" or calloutData.scenario == "stolen_vehicle" then
        local vehicle = GetVehiclePedIsIn(calloutPed, false)
        if vehicle and DoesEntityExist(vehicle) then
            entityToBlip = vehicle
        end
    end

    if calloutBlip and DoesBlipExist(calloutBlip) then RemoveBlip(calloutBlip) end
    calloutBlip = AddBlipForEntity(entityToBlip)
    SetBlipSprite(calloutBlip, Config.Callouts.blip.sprite)
    SetBlipColour(calloutBlip, Config.Callouts.blip.color)
    SetBlipScale(calloutBlip, Config.Callouts.blip.scale)
    SetBlipRoute(calloutBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(calloutData.name)
    EndTextCommandSetBlipName(calloutBlip)
end)

RegisterNetEvent("police:clearCallout", function(reason)
    if not isPlayerPolice() then return end
    ForceClearCallout()
    debugLog(string.format("Received 'police:clearCallout' event. Reason: %s", reason or 'N/A'))
    
    local message = "~b~[DISPATCH]~w~ The active callout has been resolved."
    if reason == 'arrested' or reason == 'completed' then
        message = "~b~[DISPATCH]~w~ All units stand down. Incident is Code 4, suspect detained."
    elseif reason == 'prank' then
        message = "~b~[DISPATCH]~w~ All units, disregard previous. Believed to be a false report."
    elseif reason == 'timeout' then
        message = "~b~[DISPATCH]~w~ The active call has timed out. All units resume patrol."
    end
    notify(message)
end)

RegisterNetEvent('police:showDispatchAlert', function(dispatchInfo)
    if not isPlayerPolice() or not isPoliceActive or #(GetEntityCoords(PlayerPedId()) - dispatchInfo.coords) < 50.0 then
        return
    end
    notify("~b~Dispatch Alert:~w~ " .. dispatchInfo.title)
    notify("~y~Location:~w~ " .. dispatchInfo.street)
    -- Your CreateBlip logic would handle showing this on the map
end)

RegisterNetEvent('police:findLocalPedsForCallout', function(calloutData, coords)
    CreateThread(function()
        debugLog("-> Received request from server to find local peds for callout.")
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        local timer = 2000
        while not HasCollisionLoadedAroundEntity(PlayerPedId()) and timer > 0 do
            Wait(100)
            timer = timer - 100
        end
        Wait(1500) -- Allow peds to spawn into the loaded area

        local nearbyPedsNetIds = {}
        local allPeds = GetGamePool('CPed')

        for i = 1, #allPeds do
            local ped = allPeds[i]
            if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, 1) and not IsEntityAMissionEntity(ped) then
                local netId = NetworkGetNetworkIdFromEntity(ped)
                if netId and netId > 0 and #(GetEntityCoords(ped) - coords) < 150.0 then
                    local pedIsValidForScenario = false
                    
                    -- Logic to find a suitable ped based on the callout type
                    if calloutData.scenario == "drunk_driver" or calloutData.scenario == "stolen_vehicle" then
                        -- For these scenarios, we ONLY want peds who are in the driver's seat.
                        local vehicle = GetVehiclePedIsIn(ped, false)
                        if vehicle and GetPedInVehicleSeat(vehicle, -1) == ped then
                            pedIsValidForScenario = true
                        end
                    else
                        -- For ALL OTHER scenarios, we ONLY want peds on foot.
                        if not IsPedInAnyVehicle(ped, false) then
                            pedIsValidForScenario = true
                        end
                    end

                    if pedIsValidForScenario then
                        table.insert(nearbyPedsNetIds, {
                            netId = netId,
                            isMale = IsPedMale(ped)
                        })
                    end
                end
            end
        end

        debugLog(string.format("-> Found %d suitable peds for callout. Sending to server.", #nearbyPedsNetIds))
        TriggerServerEvent('police:foundLocalPeds', nearbyPedsNetIds, calloutData, coords)
    end)
end)

RegisterNetEvent('police:updateVehicleData', function(vehicleNetId, data)
    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)
    if DoesEntityExist(vehicle) then
        debugLog('Received synced data for vehicle Net ID: ' .. vehicleNetId)
        local plate = GetVehicleNumberPlateText(vehicle)
        data.plate = plate -- Ensure the plate is correct on the client
        vehicleData[vehicle] = data
    end
end)

RegisterNetEvent("police:client:deleteEntity", function(netId)
    local ped = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(ped) then
        debugLog(string.format("Received command from server to delete entity with Net ID: %s", netId))
        SetEntityAsNoLongerNeeded(ped)
        DeleteEntity(ped)
    end
end)