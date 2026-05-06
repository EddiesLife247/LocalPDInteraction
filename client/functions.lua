--[[ client/functions.lua ]]
-- This file contains all the core functions for the script.

-- =============================================================================
-- || CORE UTILITY FUNCTIONS                                                  ||
-- =============================================================================

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

function notify(msg)
    SetNotificationTextEntry("STRING");
    AddTextComponentString(msg);
    DrawNotification(false, true)
end

function refreshInteractionMenu()
    isMenuOpen = false
    CreateThread(function()
        Wait(150)
        isMenuOpen = true
        currentActionIndex = 1
    end)
end

function GetClosestPed()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestPed, closestDist = nil, Config.InteractionDistance

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedDeadOrDying(ped, 1) then
            local dist = #(GetEntityCoords(ped) - playerCoords)
            if dist < closestDist then
                closestPed = ped
                closestDist = dist
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

-- =============================================================================
-- || DATA GENERATION FUNCTIONS                                               ||
-- =============================================================================

function generateRandomName(entity)
    local isMale
    if entity and DoesEntityExist(entity) and IsEntityAPed(entity) then
        isMale = IsPedMale(entity)
    else
        isMale = math.random(1, 2) == 1
    end
    local fname = isMale and Config.Names.maleFirstNames[math.random(#Config.Names.maleFirstNames)] or Config.Names.femaleFirstNames[math.random(#Config.Names.femaleFirstNames)]
    return fname .. " " .. Config.Names.lastNames[math.random(#Config.Names.lastNames)]
end

function generateRandomAge() return math.random(18, 70) end

function generateRandomPedData(ped)
    if pedData[ped] then return pedData[ped] end
    local hasIllegal, hasWarrants = (math.random(1, 15) == 1), (math.random(1, 20) == 1)
    local newData = {
        name = generateRandomName(ped),
        age = generateRandomAge(),
        warrants = hasWarrants,
        warrantDetails = hasWarrants and {Config.WarrantCharges[math.random(#Config.WarrantCharges)]} or {},
        isDrunk = (math.random(1, 20) == 1),
        isOnDrugs = (math.random(1, 30) == 1),
        hasIllegalItems = hasIllegal,
        illegalItemFound = hasIllegal and Config.IllegalItems[math.random(#Config.IllegalItems)] or nil,
        isCuffed = false, isEscorted = false, inVehicle = IsPedInAnyVehicle(ped, false),
        isFollowing = false, hasID = (math.random(1, 5) ~= 1), idVerified = false, idAttempted = false,
        checksCompleted = { breathalyze = false, drugtest = false, search = false, fingerprint = false }
    }
    if newData.isOnDrugs then
        newData.drugType = Config.SpecificDrugs[math.random(#Config.SpecificDrugs)]
    end
    pedData[ped] = newData
    return newData
end

function generateRandomVehicleData(vehicle, driverPed)
    if vehicleData[vehicle] then return vehicleData[vehicle] end
    debugLog("Generating new linked data for vehicle entity: " .. vehicle)
    local plate = GetVehicleNumberPlateText(vehicle)
    local driverData = pedData[driverPed] or generateRandomPedData(driverPed)
    local driverName = driverData.name
    local ownerName, isStolen, hasPermission
    if math.random(1, 100) <= 80 then
        ownerName, isStolen, hasPermission = driverName, false, true
    else
        ownerName = generateRandomName()
        while ownerName == driverName do ownerName = generateRandomName() end
        if math.random(1, 100) <= 20 then
            isStolen, hasPermission = false, true
        else
            isStolen, hasPermission = true, false
        end
    end
    local data = {
        plate = plate, isStolen = isStolen, hasPermission = hasPermission,
        hasInsurance = (math.random(1, Config.VehicleChecks.noInsuranceChance) ~= 1),
        hasTax = (math.random(1, Config.VehicleChecks.noTaxChance) ~= 1),
        owner = ownerName,
        make = Config.VehicleChecks.ukCarMakes[math.random(#Config.VehicleChecks.ukCarMakes)],
        color = Config.VehicleChecks.ukCarColors[math.random(#Config.VehicleChecks.ukCarColors)],
        hasIllegalItems = (math.random(1, 8) == 1),
        illegalItemFound = Config.IllegalItems[math.random(#Config.IllegalItems)]
    }
    vehicleData[vehicle] = data
    return data
end