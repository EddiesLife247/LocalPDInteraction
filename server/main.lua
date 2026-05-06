--[[ Server-Side Police Interaction Script ]]
-- Author: YourName
-- Version: 2.7.8 (Server-Side Fix)

local QBCore = exports['qb-core']:GetCoreObject()
local syncedPeds = {}
local syncedVehicles = {}
local activeCallout = false
local activeCalloutPedNetId = nil
local activeCalloutOpponentNetId = nil
local playerStates = {} -- Add this line
local pulledOverVehicles = {}

local DispatchResponses = {
    ["State 1 (On Duty)"] = "10-4, unit is 10-41 (Beginning Tour of Duty).",
    ["State 2 (On Patrol)"] = "10-4, unit is 10-8 (In Service / Available).",
    ["State 4 (Break)"] = "10-4, unit is 10-7 (Out of Service / On Break).",
    ["State 5 (En Route)"] = "10-4, unit is 10-79 (En Route to Scene).",
    ["State 6 (At Scene)"] = "10-4, unit is 10-97 (Arrived at Scene).",
    ["State 9 (Prisoner Transport)"] = "10-4, unit is 10-15 (Transporting Prisoner)."
}


local function debugLog(message)
    if Config.Debug then
        print(string.format("[PD-DEBUG | SERVER] %s", message))
    end
end

debugLog("Script starting up and events are being registered.")

RegisterNetEvent('police:requestVehicleData', function(vehicleNetId)
    local src = source
    if not syncedVehicles[vehicleNetId] then
        debugLog('Generating new synced data for vehicle Net ID: ' .. vehicleNetId)
        -- Generate the data once on the server
        local isMaleOwner = math.random(1, 2) == 1
        local ownerName
        if isMaleOwner then
            ownerName = Config.Names.maleFirstNames[math.random(#Config.Names.maleFirstNames)] .. " " .. Config.Names.lastNames[math.random(#Config.Names.lastNames)]
        else
            ownerName = Config.Names.femaleFirstNames[math.random(#Config.Names.femaleFirstNames)] .. " " .. Config.Names.lastNames[math.random(#Config.Names.lastNames)]
        end

        syncedVehicles[vehicleNetId] = {
            isStolen = (math.random(1, Config.VehicleChecks.stolenChance) == 1),
            hasInsurance = (math.random(1, Config.VehicleChecks.noInsuranceChance) ~= 1),
            hasTax = (math.random(1, Config.VehicleChecks.noTaxChance) ~= 1),
            owner = ownerName,
            make = Config.VehicleChecks.ukCarMakes[math.random(#Config.VehicleChecks.ukCarMakes)],
            color = Config.VehicleChecks.ukCarColors[math.random(#Config.VehicleChecks.ukCarColors)],
            hasIllegalItems = (math.random(1, 8) == 1),
            illegalItemFound = Config.IllegalItems[math.random(#Config.IllegalItems)]
        }
    end
    -- Send the definitive data to all clients
    TriggerClientEvent('police:updateVehicleData', -1, vehicleNetId, syncedVehicles[vehicleNetId])
end)


RegisterNetEvent('police:syncPedData', function(netId, data)
    -- If no data exists for this ped yet, create an empty table first
    if not syncedPeds[netId] then
        syncedPeds[netId] = {}
    end

    -- Merge the new data into the existing data on the server
    -- This prevents fields like 'name' from being erased by partial updates
    for key, value in pairs(data) do
        syncedPeds[netId][key] = value
    end

    -- Broadcast the complete, merged data table back to all clients
    TriggerClientEvent('police:updatePedData', -1, netId, syncedPeds[netId])
end)



RegisterNetEvent('police:setPlayerState', function(state)
    local src = source
    playerStates[src] = state
    debugLog(string.format("Player %s set state to: %s", src, state))

    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    -- Step 1: Update the player's status in the dispatch system
    if Config.Dispatch.integration == 'ps-dispatch' then
        local statusData = DispatchStatusMap[state]
        if statusData then
            exports["ps-dispatch"]:SetPlayerStatus(src, statusData.status, statusData.message)
            debugLog(string.format("Updated player %s status via ps-dispatch to: %s", src, statusData.message))
        end
    end

    -- Step 2: Create a notification message for other officers
    local responseMessage = DispatchStatusMap[state] and DispatchStatusMap[state].message or state
    local callsign = player.PlayerData.metadata['callsign'] or player.PlayerData.charinfo.firstname
    local notification = string.format("~b~[RADIO]~w~ Unit %s is now %s", callsign, responseMessage)

    -- Step 3: Broadcast this message to all other on-duty police officers
    local players = QBCore.Functions.GetPlayers()
    for _, playerId in ipairs(players) do
        if playerId ~= src then -- Don't send the notification to the person who changed their own status
            local targetPlayer = QBCore.Functions.GetPlayer(playerId)
            if targetPlayer then
                for _, jobName in ipairs(Config.PoliceJobs) do
                    if targetPlayer.PlayerData.job.name == jobName and targetPlayer.PlayerData.job.onduty then
                        TriggerClientEvent('police:showStatusUpdate', playerId, notification)
                        break
                    end
                end
            end
        end
    end
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(player)
    if playerStates[player.PlayerData.source] then
        playerStates[player.PlayerData.source] = nil
        debugLog(string.format("Cleared state for disconnected player %s.", player.PlayerData.source))
    end
end)

RegisterNetEvent('police:server:incrementCrimeLevel', function(pedNetId, amount)
    if syncedPeds[pedNetId] then
        -- Increase the crimeLevel and clamp it at 100
        syncedPeds[pedNetId].crimeLevel = math.min(100, (syncedPeds[pedNetId].crimeLevel or 0) + amount)
        debugLog(string.format("Crime level for ped %d increased by %d to %d", pedNetId, amount, syncedPeds[pedNetId].crimeLevel))

        -- Broadcast the updated data to all clients
        TriggerClientEvent('police:updatePedData', -1, pedNetId, syncedPeds[pedNetId])
    end
end)

RegisterNetEvent("police:clearPedData", function(pedNetworkId)
    debugLog(string.format("Received 'police:clearPedData' for Net ID: %s", pedNetworkId))
    syncedPeds[pedNetworkId] = nil
    TriggerClientEvent("police:clearPedDataClient", -1, pedNetworkId)
end)

RegisterNetEvent('police:broadcastDispatchAlert', function(dispatchInfo)
    TriggerClientEvent('police:showDispatchAlert', -1, dispatchInfo)
end)

RegisterNetEvent('police:processJailPayout', function(payoutAmount)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if player then
        player.Functions.AddMoney('cash', payoutAmount)
        TriggerClientEvent('QBCore:Notify', src, string.format("You have been paid £%s for the arrest.", payoutAmount), "success")
    end
end)

RegisterNetEvent("police:server:issuePCN", function(plate, offence, fine)
    local src = source
    local officer = GetPlayerName(src)

    -- 💸 Charge vehicle owner / government logging
    -- Replace this with your billing/bank logic
    print(("PCN issued by %s | Plate: %s | Offence: %s | Fine: £%s"):format(officer, plate, offence, fine))
        player.Functions.AddMoney('cash', 200)
        TriggerClientEvent('QBCore:Notify', src, string.format("You have been paid £%s for the PCN Notice.", 200), "success")
end)


RegisterNetEvent('police:server:issueFine', function(fineData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Officer payout for issuing fine
    if Config.Fining and Config.Fining.officerPayout then
        Player.Functions.AddMoney('cash', Config.Fining.officerPayout)
        TriggerClientEvent('QBCore:Notify', src,
            string.format("You received £%s for issuing the fine.", Config.Fining.officerPayout),
            "success"
        )
    end

    -- Log it for debugging/admin purposes
    print(string.format(
        "[Police] Officer %s (%s) issued a fine of £%d to '%s' for: %s",
        src,
        Player.PlayerData.citizenid,
        fineData.amount or 0,
        fineData.pedName or "Unknown",
        fineData.reason or "No reason provided"
    ))
end) 



-- NEW: Event to handle paying the officer for issuing a fine
RegisterNetEvent('police:processFine', function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if player and Config.Fining and Config.Fining.officerPayout then
        player.Functions.AddMoney('cash', Config.Fining.officerPayout)
        TriggerClientEvent('QBCore:Notify', src, string.format("You received £%s for issuing the fine.", Config.Fining.officerPayout), "success")
    end
end)

RegisterNetEvent('police:server:requestLeaveVehicle', function(vehNetId, seatIndex)
    local source = source
local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if not vehicle or not DoesEntityExist(vehicle) then return end

    local pedInSeat = GetPedInVehicleSeat(vehicle, seatIndex)
    if not pedInSeat or not DoesEntityExist(pedInSeat) then return end

    local pedOwner = NetworkGetEntityOwner(pedInSeat)
    if pedOwner and GetPlayerFromIndex(pedOwner) then
        debugLog(string.format("Relaying leave vehicle request for ped in seat %d to owner %s.", seatIndex, pedOwner))
        -- Tell the client that owns the ped to execute the task
        TriggerClientEvent('police:client:forceLeaveVehicle', pedOwner, vehNetId, seatIndex, source)
    else
        debugLog("Could not find owner for ped to execute leave vehicle task.")
    end
end)

function TriggerNewCallout(source)
    debugLog("Attempting to trigger a new callout...")
    if activeCallout then
        debugLog("-> FAILED: A callout is already active.")
        if source then TriggerClientEvent('QBCore:Notify', source, "A callout is already active.", "error") end
        return false
    end
    debugLog("-> OK: No active callout found.")

    local onDutyPolice = {}
    local players = QBCore.Functions.GetPlayers()
    for _, playerId in ipairs(players) do
        local player = QBCore.Functions.GetPlayer(playerId)
        if player then
            for _, jobName in ipairs(Config.PoliceJobs) do
                if player.PlayerData.job.name == jobName and player.PlayerData.job.onduty then
                    table.insert(onDutyPolice, player.PlayerData.source)
                    break
                end
            end
        end
    end

    if #onDutyPolice == 0 then
        debugLog("-> FAILED: No on-duty police officers found.")
        if source then TriggerClientEvent('QBCore:Notify', source, "No police officers are on duty.", "error") end
        return false
    end

    --- NEW DYNAMIC SPAWNING LOGIC ---
    -- 1. Select a random on-duty officer to base the location on.
    local randomOfficerSource = onDutyPolice[math.random(#onDutyPolice)]
    local officerPed = GetPlayerPed(randomOfficerSource)
    local officerCoords = GetEntityCoords(officerPed)

-- 2. Generate a random location 150-300m away from that officer.
    local angle = math.random() * 2 * math.pi
    local radius = math.random(150, 300)
    local x = officerCoords.x + radius * math.cos(angle)
    local y = officerCoords.y + radius * math.sin(angle)
    -- The server only needs to pick a general area (X, Y). The Z-coordinate is irrelevant for the search.
    local coords = vector3(x, y, 0.0)
    --- END OF NEW LOGIC ---

    local calloutData = Config.Callouts.callouts[math.random(#Config.Callouts.callouts)]
    debugLog(string.format("-> Selected callout: '%s' near coordinates: %s", calloutData.name, tostring(coords)))

    local closestOfficer, closestDist = nil, -1
    for _, officerSource in ipairs(onDutyPolice) do
        local ped = GetPlayerPed(officerSource)
        local dist = #(GetEntityCoords(ped) - coords)
        if not closestOfficer or dist < closestDist then
            closestOfficer = officerSource
            closestDist = dist
        end
    end

    if closestOfficer then
        debugLog(string.format("-> Asking closest client %s to find local peds near %s", closestOfficer, tostring(coords)))
        TriggerClientEvent('police:findLocalPedsForCallout', closestOfficer, calloutData, coords)
    else
        debugLog("-> FAILED: Could not determine a closest officer.")
        return false
    end
    return true
end

RegisterNetEvent('police:foundLocalPeds', function(pedNetIds, calloutData, coords)
    local source = source
    debugLog(string.format("-> Received %s peds from client %s.", #pedNetIds, source))

    local requiredPeds = 1
    if calloutData.scenario == "fight" then requiredPeds = 2 end

    if #pedNetIds < requiredPeds then
        debugLog(string.format("-> FAILED: Client did not find enough local peds for a %s scenario.", calloutData.scenario or 'default'))
        return
    end

    -- FIX: Extract the numerical ID from the table element to ensure it's a number
    activeCalloutPedNetId = pedNetIds[1].netId
    activeCalloutOpponentNetId = nil

    if calloutData.scenario == "fight" then
        -- FIX: Extract the numerical ID for the opponent as well
        activeCalloutOpponentNetId = pedNetIds[2].netId
    end

    -- FIX: Generate a proper random name instead of just "Unknown"
    local pedInfo = calloutData.state or {}
    pedInfo.name = Config.Names.maleFirstNames[math.random(#Config.Names.maleFirstNames)] .. " " .. Config.Names.lastNames[math.random(#Config.Names.lastNames)]
    pedInfo.age = math.random(18, 70)
    syncedPeds[activeCalloutPedNetId] = pedInfo
    -- Pass the plain number ID to the client
    TriggerClientEvent("police:updatePedData", -1, activeCalloutPedNetId, syncedPeds[activeCalloutPedNetId])

    if activeCalloutOpponentNetId then
        local opponentInfo = { 
            name = Config.Names.maleFirstNames[math.random(#Config.Names.maleFirstNames)] .. " " .. Config.Names.lastNames[math.random(#Config.Names.lastNames)], 
            age = math.random(18, 70) 
        }
        syncedPeds[activeCalloutOpponentNetId] = opponentInfo
        -- Pass the plain number ID to the client
        TriggerClientEvent("police:updatePedData", -1, activeCalloutOpponentNetId, opponentInfo)
    end

    activeCallout = true
    debugLog("-> Triggering 'police:newCallout' client event for all players...")
    -- Pass the plain number IDs to the client
    TriggerClientEvent("police:newCallout", -1, calloutData, coords, activeCalloutPedNetId, activeCalloutOpponentNetId)
    debugLog("-> New callout dispatched successfully.")

    SetTimeout(300000, function()
        if activeCallout then
            debugLog("-> Callout timed out after 5 minutes. Cleaning up.")
            TriggerEvent('police:clearCalloutServer', 'timeout')
        end
    end)
end)



CreateThread(function()
    if not Config.Callouts.randomCalloutsEnabled then return end
    while true do
        local waitTime = math.random(Config.Callouts.randomCalloutInterval.min * 60000, Config.Callouts.randomCalloutInterval.max * 60000)
        debugLog(string.format("Random callout timer: Waiting for %s minutes.", waitTime / 60000))
        Wait(waitTime)
        local policeCount = 0
        local players = QBCore.Functions.GetPlayers()
        for _, playerId in ipairs(players) do
            local player = QBCore.Functions.GetPlayer(playerId)
            if player then
                for _, jobName in ipairs(Config.PoliceJobs) do
                    if player.PlayerData.job.name == jobName and player.PlayerData.job.onduty then
                        policeCount = policeCount + 1
                        break
                    end
                end
            end
        end
        if policeCount > 0 then
            debugLog(string.format("-> Timer elapsed, %s police on duty. Attempting to dispatch random callout.", policeCount))
            TriggerNewCallout()
        else
            debugLog("-> Timer elapsed but no police are on duty. Skipping random callout.")
        end
    end
end)

RegisterNetEvent('police:clearCalloutServer', function(reason)
    if not activeCallout then return end
    debugLog(string.format("Received 'police:clearCalloutServer'. Reason: %s", reason or 'N/A'))
    
    -- When clearing, we just tell the clients to handle it.
    -- We don't need to delete entities here as clients will manage them.
    
    activeCallout = false
    activeCalloutPedNetId = nil
    activeCalloutOpponentNetId = nil
    TriggerClientEvent('police:clearCallout', -1, reason)
end)

RegisterCommand("newcallout", function(source, args, rawCommand)
    debugLog(string.format("'/newcallout' command executed by source: %s", source))
    if not Config.Callouts.enabled then debugLog("-> FAILED: Callouts are disabled in config.lua."); return end
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return end
    local isPolice = false
    for _, jobName in ipairs(Config.PoliceJobs) do
        if player.PlayerData.job.name == jobName and player.PlayerData.job.onduty then isPolice = true; break end
    end
    if not isPolice then
        debugLog("-> FAILED: Player is not an on-duty police officer.")
        TriggerClientEvent('QBCore:Notify', source, "You are not an on-duty police officer.", "error")
        return
    end
    debugLog("-> Player is an on-duty police officer. Proceeding...")
    local success = TriggerNewCallout(source)
    if not success and source ~= 0 then
        debugLog("-> TriggerNewCallout() returned false. Notifying user that a callout may be active.")
    else
        debugLog("-> TriggerNewCallout() returned true. Callout started.")
    end
end, false)

RegisterNetEvent('police:calloutCompleted', function(reason)
    reason = reason or 'completed'
    debugLog("Received 'police:calloutCompleted' event. Reason: " .. reason)
    if activeCallout then
        -- We trigger the clear server event to handle cleanup properly
        TriggerEvent('police:clearCalloutServer', reason)
    end
end)

-- Officer marks a vehicle as pulled over
RegisterNetEvent('police:server:setPulledOverVehicle', function(vehNetId, isPulledOver)
    local src = source
    if isPulledOver then
        pulledOverVehicles[vehNetId] = src
        debugLog(("Vehicle %s marked as pulled over by officer %s"):format(vehNetId, src))
    else
        pulledOverVehicles[vehNetId] = nil
        debugLog(("Vehicle %s cleared from pulled over state by officer %s"):format(vehNetId, src))
    end
    -- Broadcast to all clients so everyone stays synced
    TriggerClientEvent('police:client:updatePulledOverVehicle', -1, vehNetId, isPulledOver)
end)

-- Send initial list when a new PD client joins
AddEventHandler('QBCore:Server:OnPlayerLoaded', function(player)
    local src = player.PlayerData.source
    local job = player.PlayerData.job
    if job and job.name == "police" and job.onduty then
        TriggerClientEvent('police:client:initPulledOverVehicles', src, pulledOverVehicles)
    end
end)

-- Cleanup if officer disconnects (optional)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(player)
    local src = player.PlayerData.source
    for vehNetId, officerSrc in pairs(pulledOverVehicles) do
        if officerSrc == src then
            pulledOverVehicles[vehNetId] = nil
            TriggerClientEvent('police:client:updatePulledOverVehicle', -1, vehNetId, false)
        end
    end
end)

-- Sync pulled over list to new officers (when they request it)
RegisterNetEvent('police:server:requestPulledOverVehicles', function()
    local src = source
    TriggerClientEvent('police:client:initPulledOverVehicles', src, pulledOverVehicles)
end)


