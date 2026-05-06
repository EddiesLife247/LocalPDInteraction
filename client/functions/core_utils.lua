--[[ client/functions/core_utils.lua ]]
-- Contains all the core, reusable helper functions for the script.

function debugLog(message)
    if Config.Debug then
        print(string.format("[PD-DEBUG | CLIENT] %s", message))
    end
end

function isPlayerPolice()
    if not PlayerJob then return false end
    for _, jobName in ipairs(Config.PoliceJobs) do
        if PlayerJob.name == jobName and PlayerJob.onduty then
            return true
        end
    end
    return false
end

function removeSuspectEntity(ped)
    if DoesEntityExist(ped) then
        debugLog("Removing suspect entity: " .. tostring(ped))
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
    end

    -- cleanup data
    pedData[ped] = nil
    if targetedPed == ped then targetedPed = nil end

    -- cancel pursuit/stop if this was the active suspect
    if ped == activePursuitDriver then
        EndPursuit(ped, activePursuitVehicle, "Suspect jailed/removed")
    end
end


function ForceClearCallout()
    debugLog("Forcing a cleanup of any active callout resources.")
    if activeCalloutPedEntity and DoesEntityExist(activeCalloutPedEntity) then
        SetEntityAsNoLongerNeeded(activeCalloutPedEntity)
    end
    activeCalloutPedEntity = nil

    if calloutBlip and DoesBlipExist(calloutBlip) then
        RemoveBlip(calloutBlip)
        calloutBlip = nil
    end

    if trafficBlip and DoesBlipExist(trafficBlip) then
        RemoveBlip(trafficBlip)
        trafficBlip = nil
    end
end

function updateSyncedPedState(ped, newState)
    local netId = NetworkGetNetworkIdFromEntity(ped);
    TriggerServerEvent("police:syncPedData", netId, newState)
end

function LoadAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict);
        Wait(50)
    end
end

function notify(msg)
    SetNotificationTextEntry("STRING");
    AddTextComponentString(msg);
    DrawNotification(false, true)
end

function GetClosestPed()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestPed, closestDist = nil, Config.InteractionDistance
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, 1) then
            local dist = #(GetEntityCoords(ped) - playerCoords)
            if dist < closestDist then
                closestPed, closestDist = ped, dist
            end
        end
    end
    return closestPed
end

function PlacePedOnGround(ped)
    local x, y, z = table.unpack(GetEntityCoords(ped))
    local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    if foundGround then
        SetEntityCoords(ped, x, y, groundZ, false, false, false, true)
    end
end

function GetVehicleAhead(playerVeh)
    local from = GetEntityCoords(playerVeh)
    local forward = GetEntityForwardVector(playerVeh)
    local to = from + (forward * 60.0)
    local rayHandle = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, 10, playerVeh, 0)
    local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)
    if hit == 1 and DoesEntityExist(entityHit) and IsEntityAVehicle(entityHit) then
        return entityHit
    end
    return nil
end

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function drawText(x, y, text)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextScale(0.0, 0.4)
    SetTextColour(255, 255, 255, 255)
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y) -- This is the actual native function
end