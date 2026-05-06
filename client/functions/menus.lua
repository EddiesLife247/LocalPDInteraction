--[[ client/functions/menus.lua ]]
-- This file contains all functions for drawing and handling UI menus.
local lastMaintainPositionTime = 0


-- Add this function to your menus.lua file or make it globally accessible

local function maintainSuspectPosition(ped)
    if not DoesEntityExist(ped) then return end
    
    -- THROTTLE: Only run this function once every 2 seconds to prevent spam
    local currentTime = GetGameTimer()
    if currentTime - lastMaintainPositionTime < 2000 then
        return -- Skip execution if called too recently
    end
    lastMaintainPositionTime = currentTime
    
    local data = pedData[ped]
    if not data then return end
    
    -- Always maintain position during any interaction
    FreezeEntityPosition(ped, true)
    
    -- If they're supposed to be on foot (removed from vehicle), maintain surrender pose
    if data.removedFromVehicle then
        if not IsEntityPlayingAnim(ped, "random@mugging3", "handsup_standing_base", 3) then
            SetSuspectSurrenderPose(ped)
        end
    else
        -- Even if not removed, if they're currently out of vehicle during traffic stop, keep them still
        if pulledOverVehicle and not IsPedInVehicle(ped, pulledOverVehicle, false) then
            if not IsEntityPlayingAnim(ped, "random@mugging3", "handsup_standing_base", 3) then
                SetSuspectSurrenderPose(ped)
            end
        end
    end
    
    debugLog("maintainSuspectPosition: Position maintained for ped during interaction")
end

-- You'll also need the SetSuspectSurrenderPose function if it's not already in menus.lua
function SetSuspectSurrenderPose(ped)
    if not DoesEntityExist(ped) then return end
    
    local animDict = "random@mugging3"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(10)
    end
    
    ClearPedTasksImmediately(ped)
    TaskPlayAnim(ped, animDict, "handsup_standing_base", 8.0, -8.0, -1, 1, 0, false, false, false)
    FreezeEntityPosition(ped, true)
    
    -- Mark surrender as active
    if pedData[ped] then
        pedData[ped].surrenderActive = true
    end
end

-- And the CleanupSurrenderThread function if it's referenced
function CleanupSurrenderThread(ped)
    if pedData[ped] then
        pedData[ped].surrenderActive = false
    end
end

-- NEW: Helper function to force the interaction menu to refresh its state
local function refreshInteractionMenu()
    isMenuOpen = false
    CreateThread(function()
        Wait(150) -- A short delay for the main loop to register the menu is closed
        isMenuOpen = true
        currentActionIndex = 1 -- Reset selection to the top of the new menu
    end)
end

function SetComplianceMode(ped, mode)
    if not DoesEntityExist(ped) then return end
    pedData[ped] = pedData[ped] or {}
    pedData[ped].complianceMode = mode
    debugLog(("SetComplianceMode: %s set to %s"):format(ped, mode))
end


function releaseVehicleAndPeds(vehicle)
    if not DoesEntityExist(vehicle) then return end

    debugLog("Releasing vehicle - restoring normal functionality")

    -- CRITICAL: Restore vehicle to normal working condition
    SetVehicleEngineHealth(vehicle, 1000.0) -- Restore engine health
    SetVehicleEngineOn(vehicle, true, false, false) -- Turn engine back on
    SetVehicleUndriveable(vehicle, false) -- Make it driveable again
    FreezeEntityPosition(vehicle, false) -- Unfreeze
    
    -- Clear any velocity constraints
    SetVehicleForwardSpeed(vehicle, 0.0)
    SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)

    -- Loop through seats and clear compliance mode
    for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, i)
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            if pedData[ped] then
                pedData[ped].complianceMode = nil
                pedData[ped].removedFromVehicle = nil
                pedData[ped].surrenderActive = false
            end
            FreezeEntityPosition(ped, false)
            ClearPedTasksImmediately(ped)
            SetBlockingOfNonTemporaryEvents(ped, false)
        end
    end

    -- Clear compliance monitoring
    isTrafficStopActive = false
    pulledOverVehicle = nil
    ClearPulledOverVehicleState(vehicle)

    notify("~g~Vehicle released and restored to normal operation.")
    debugLog("Vehicle release complete - engine restored, compliance cleared")
end

-- Fixed releaseVehicle function for interactions.lua
-- Replace the existing function in interactions.lua

function releaseVehicle()
    if not targetedVehicle or not DoesEntityExist(targetedVehicle) then
        return
    end
    local driver = GetPedInVehicleSeat(targetedVehicle, -1)
    if not DoesEntityExist(driver) then
        notify("~r~Cannot release: Driver not found.")
        return
    end

    debugLog("Releasing vehicle and driver to normal behavior.")
    
    -- CRITICAL: Restore vehicle to full working condition
    SetVehicleEngineHealth(targetedVehicle, 1000.0) -- Restore engine health
    SetVehicleEngineOn(targetedVehicle, true, false, false) -- Turn engine back on
    SetVehicleUndriveable(targetedVehicle, false) -- Make it driveable again
    SetEntityAsNoLongerNeeded(targetedVehicle) -- Release mission entity status
    FreezeEntityPosition(targetedVehicle, false)
    
    -- Clear velocity constraints
    SetVehicleForwardSpeed(targetedVehicle, 0.0)
    SetEntityVelocity(targetedVehicle, 0.0, 0.0, 0.0)
    
    -- Release driver
    FreezeEntityPosition(driver, false)
    ClearPedTasksImmediately(driver)
    SetBlockingOfNonTemporaryEvents(driver, false)
    
    -- Clear driver's compliance data
    if pedData[driver] then
        pedData[driver].complianceMode = nil
        pedData[driver].removedFromVehicle = nil
        pedData[driver].surrenderActive = false
    end
    
    -- Give driver normal driving task
    TaskVehicleDriveWander(driver, targetedVehicle, 20.0, 786603)
    
    -- Clear traffic stop state
    isTrafficStopActive = false
    ClearPulledOverVehicleState(targetedVehicle)

    if trafficBlip and DoesBlipExist(trafficBlip) then
        RemoveBlip(trafficBlip)
        trafficBlip = nil
    end
    
    pulledOverVehicle, isBusy, isTrafficStopActive = nil, false, false
    notify("~g~Vehicle has been released and restored to normal operation.")
    isVehicleMenuOpen, targetedVehicle = false, nil
    
    debugLog("Vehicle release complete - engine restored, driver freed")
end




function DrawAndHandleInteractionMenu()
    if not targetedPed or not DoesEntityExist(targetedPed) then
        closeInteractionMenu(true); return
    end
    local d = pedData[targetedPed]
    if not d then
        closeInteractionMenu(true); return
    end

    local keys, actions, title

    if isJailing then
        title = "Jailing Report"
        keys, actions = {}, {}
        if d.warrants then
            for _, charge in ipairs(d.warrantDetails) do
                table.insert(keys, "Warrant: " .. charge)
            end
        end
        if d.isDrunk then table.insert(keys, "Public Intoxication") end
        if d.isOnDrugs then table.insert(keys, "Possession of " .. d.drugType) end
        if d.hasIllegalItems then table.insert(keys, "Possession of Contraband") end
        table.insert(keys, "Confirm and Jail")
        table.insert(keys, "Go Back")

        actions = {
["Confirm and Jail"] = function()
    if not targetedPed or not pedData[targetedPed] then
        notify("~r~No suspect data available.")
        return
    end

    local d = pedData[targetedPed]
    local totalPayout = Config.JailPayout.base
    local breakdown = { string.format("Base: £%s", Config.JailPayout.base) }

    if d.warrants then
        totalPayout = totalPayout + (Config.JailPayout.warrantBonus or 0)
        table.insert(breakdown, string.format("Warrants: +£%s", Config.JailPayout.warrantBonus or 0))
    end
    if d.isDrunk then
        totalPayout = totalPayout + (Config.JailPayout.intoxicationBonus or 0)
        table.insert(breakdown, string.format("Intoxication: +£%s", Config.JailPayout.intoxicationBonus or 0))
    end
    if d.isOnDrugs then
        totalPayout = totalPayout + (Config.JailPayout.drugBonus or 0)
        table.insert(breakdown, string.format("Drugs: +£%s", Config.JailPayout.drugBonus or 0))
    end
    if d.hasIllegalItems then
        totalPayout = totalPayout + (Config.JailPayout.contrabandBonus or 0)
        table.insert(breakdown, string.format("Contraband: +£%s", Config.JailPayout.contrabandBonus or 0))
    end

    -- 📥 Ask officer for jail time (minutes) before confirm
    local inputs = lib.inputDialog("Confirm Jail Processing", {
        { type = "number", label = "Jail Time (minutes)", default = Config.JailPayout.defaultJailTime or 10, min = 1, max = 120, required = true }
    })

    if not inputs then
        notify("~y~Jail canceled.")
        return
    end

    local jailTime = inputs[1]

    local confirm = lib.alertDialog({
        header = "Final Confirmation",
        content = ("Suspect: %s\n\nCharges/Bonuses:\n- %s\n\nTotal Payout: £%s\nJail Time: %s minutes"):format(
            d.name or "Unknown",
            table.concat(breakdown, "\n- "),
            totalPayout,
            jailTime
        ),
        centered = true,
        cancel = true
    })

    if confirm == "confirm" then
        -- 💰 Reward officer
        TriggerServerEvent('police:processJailPayout', totalPayout)

        -- 📡 Callout completion if needed
        if d.isCalloutPed then
            TriggerServerEvent('police:calloutCompleted', 'arrested')
        end

        -- 🚔 Send to jail (server handles jail logic)
        local netId = NetworkGetNetworkIdFromEntity(targetedPed)
        TriggerServerEvent('police:server:jailPed', netId, jailTime)

        -- 🧹 Clean up locally so suspect doesn't walk off
        if DoesEntityExist(targetedPed) then
            DeleteEntity(targetedPed)
        end
        pedData[targetedPed] = nil
        targetedPed = nil
        closeInteractionMenu(true)

        notify("~g~Suspect jailed for " .. jailTime .. " minutes.")
    else
        notify("~y~Jail canceled.")
    end
end,



            ["Go Back"] = function() isJailing, currentActionIndex = false, 1 end
        }
    elseif isQuestioning then
    if targetedPed and DoesEntityExist(targetedPed) then
        maintainSuspectPosition(targetedPed)
    end
        title = "Questioning"
        keys, actions = {}, {}
for _, qData in ipairs(Config.Questioning) do
    table.insert(keys, qData.label)
    if qData.action and specialQuestionActions[qData.action] then
        actions[qData.label] = specialQuestionActions[qData.action]
    elseif qData.responses then
        actions[qData.label] = function()
            maintainSuspectPosition(targetedPed)  -- Add this line
            local pedState = pedData[targetedPed]
            local isGuilty = pedState.isDrunk or pedState.isOnDrugs or pedState.hasIllegalItems or pedState.warrants
            local responseList = (isGuilty and qData.responses.illegal) or qData.responses.legal
            notify(pedState.name .. " says: \"" .. responseList[math.random(#responseList)] .. "\"")
        end
    end
end
        table.insert(keys, "Go Back")
        actions["Go Back"] = function() isQuestioning, currentActionIndex = false, 1 end
    elseif d.isCuffed then
        title = "Arrest Options"
        actions = arrestedActions
        keys = {}
        if d.isEscorted then table.insert(keys, "Stop Escorting") else table.insert(keys, "Escort") end
        if d.isFollowing then table.insert(keys, "Stop Following") else table.insert(keys, "Follow Me") end
        table.insert(keys, "Place in Vehicle")
        table.insert(keys, "Jail")
        table.insert(keys, "Uncuff")
    else
        title = "Interaction Menu"
        actions = defaultActions
        keys = {"Question"}
        if d.idAttempted and not d.idVerified then table.insert(keys, "Fingerprint") end
        if d.isFollowing then table.insert(keys, "Stop Following") else table.insert(keys, "Follow Me") end
        table.insert(keys, "Breathalyze"); table.insert(keys, "Drug Test"); table.insert(keys, "Search")
        table.insert(keys, "Issue Fine"); table.insert(keys, "Arrest"); table.insert(keys, "Let Go")
    end

    DrawRect(0.15, 0.4, 0.22, 0.45, 0, 0, 0, 180)
    drawText(0.06, 0.22, title)
    for i, name in ipairs(keys) do
        local textToShow = (i == currentActionIndex) and ("~b~" .. name) or ("~w~" .. name)
        drawText(0.06, 0.25 + (i * 0.03), textToShow)
    end

    if menuNavCooldown > 0 then return end
    if IsControlJustReleased(0, 172) then -- Up
        currentActionIndex = currentActionIndex - 1
        if currentActionIndex < 1 then currentActionIndex = #keys end
        menuNavCooldown = 15
    elseif IsControlJustReleased(0, 173) then -- Down
        currentActionIndex = currentActionIndex + 1
        if currentActionIndex > #keys then currentActionIndex = 1 end
        menuNavCooldown = 15
    elseif IsControlJustReleased(0, 191) then -- Select (Enter/E)
        local actionKey = keys[currentActionIndex]
        if actions[actionKey] then
            actions[actionKey]()
            menuNavCooldown = 15
        end
    end
    if IsControlJustReleased(0, 177) then closeInteractionMenu(false) end
end
local function askPedToExit(ped, vehicle, startInteractionAfter)
    if not DoesEntityExist(ped) then return end

    -- If this was a compliant traffic stop, clear restraints
    if vehicle == pulledOverVehicle then
        FreezeEntityPosition(ped, false)
        CleanupSurrenderThread(ped)
        ClearPedTasksImmediately(ped)
        SetBlockingOfNonTemporaryEvents(ped, false)
    end

    pedData[ped] = pedData[ped] or {}
    pedData[ped].removedFromVehicle = true

    TaskLeaveVehicle(ped, vehicle, 0)

    CreateThread(function()
        Wait(2000)
        if DoesEntityExist(ped) then
            SetComplianceMode(ped, "onFoot")
            SetSuspectSurrenderPose(ped)

            if not pedData[ped] then
                pedData[ped] = generateRandomPedData(ped)
                updateSyncedPedState(ped, pedData[ped])
            end

            if startInteractionAfter then
                startInteraction(ped)
            end
        end
    end)
end
function DrawAndHandleVehicleMenu()
    if not targetedVehicle or not DoesEntityExist(targetedVehicle) then
        isVehicleMenuOpen, targetedVehicle = false, nil; return
    end
    local data = vehicleData[targetedVehicle]
    if not data then
        isVehicleMenuOpen, targetedVehicle = false, nil; return
    end

    local driver = GetPedInVehicleSeat(targetedVehicle, -1)
    local isUnoccupied = not DoesEntityExist(driver) or IsPedDeadOrDying(driver, 1)

    -- Detect passengers
    local passengers = {}
    for i = 0, GetVehicleMaxNumberOfPassengers(targetedVehicle) - 1 do
        local p = GetPedInVehicleSeat(targetedVehicle, i)
        if DoesEntityExist(p) and not IsPedAPlayer(p) and p ~= driver then
            table.insert(passengers, p)
        end
    end

    local vehicleSpeed = GetEntitySpeed(targetedVehicle) * 2.237
    local isSlowOrStopped = vehicleSpeed < 2.0

    local title = "Vehicle Options (" .. data.plate .. ")"
    local keys, actions = {}, {}

    -- Base options
    table.insert(keys, "Check ANPR")
    actions["Check ANPR"] = function()
        notify("~b~[ANPR]~w~ Checking: " .. data.plate); Wait(2500)
        notify(string.format("~b~[ANPR]~w~ Vehicle: %s %s.", data.color, data.make))
        notify(string.format("~b~[ANPR]~w~ Owner: %s.", data.owner))
        if data.hasTax then notify("~b~[ANPR]~g~ Road Tax: VALID") else notify("~b~[ANPR]~r~ Road Tax: EXPIRED") end
        if data.hasInsurance then notify("~b~[ANPR]~g~ Insurance: SHOWING INSURED") else notify("~b~[ANPR]~r~ Insurance: NO POLICY FOUND") end
        if data.isStolen then notify("~b~[ANPR]~r~ MARKER: VEHICLE REPORTED STOLEN") end
        isVehicleMenuOpen = false
    end

    table.insert(keys, "Search Vehicle")
    actions["Search Vehicle"] = function()
        isVehicleMenuOpen, isBusy = false, true
        notify("Searching the vehicle...")
        Wait(8000)
        if data.hasIllegalItems then
            notify("~y~Search Result:~r~ Found " .. data.illegalItemFound .. "!")
        else
            notify("~y~Search Result:~g~ Nothing illegal was found.")
        end
        isBusy = false
    end

    -- Driver options
    if not isUnoccupied then
        table.insert(keys, "Speak to Driver")
        actions["Speak to Driver"] = function()
            isVehicleMenuOpen, targetedVehicle = false, nil
            startInteraction(driver)
        end

        if isSlowOrStopped then
            table.insert(keys, "Ask Driver to Exit")
            actions["Ask Driver to Exit"] = function()
                isVehicleMenuOpen, isBusy = false, true
                askPedToExit(driver, targetedVehicle, true)
                isBusy = false
            end
        else
            table.insert(keys, "Initiate Traffic Stop")
            actions["Initiate Traffic Stop"] = function()
                isVehicleMenuOpen, targetedVehicle = false, nil
                notify("~b~Signaling vehicle to pull over...")
                StartTrafficStop(targetedVehicle)
            end
        end
    end

    -- Passenger options
    if #passengers > 0 and isSlowOrStopped then
        for i, p in ipairs(passengers) do
            table.insert(keys, ("Ask Passenger %d to Exit"):format(i))
            actions[("Ask Passenger %d to Exit"):format(i)] = function()
                isVehicleMenuOpen, isBusy = false, true
                askPedToExit(p, targetedVehicle, true)
                isBusy = false
            end
        end

        table.insert(keys, "Ask All Passengers to Exit")
        actions["Ask All Passengers to Exit"] = function()
            isVehicleMenuOpen, isBusy = false, true
            for _, p in ipairs(passengers) do
                askPedToExit(p, targetedVehicle, false)
            end
            notify("~b~All passengers have been asked to exit the vehicle.")
            isBusy = false
        end
    elseif #passengers > 0 and not isSlowOrStopped then
        table.insert(keys, "Initiate Traffic Stop")
        actions["Initiate Traffic Stop"] = function()
            isVehicleMenuOpen, targetedVehicle = false, nil
            notify("~b~Signaling vehicle to pull over...")
            StartTrafficStop(targetedVehicle)
        end
    end

    -- Special pulled over vehicle options
    if targetedVehicle == pulledOverVehicle then
        if #passengers > 0 then
            table.insert(keys, "Ask Passengers to Exit")
            actions["Ask Passengers to Exit"] = askPassengersToExit
        end
table.insert(keys, "Release Vehicle")
actions["Release Vehicle"] = function()
    releaseVehicleAndPeds(targetedVehicle)
    isVehicleMenuOpen, targetedVehicle = false, nil
end
    end

    if targetedVehicle == pulledOverVehicle or isUnoccupied then
        table.insert(keys, "Impound Vehicle")
actions["Impound Vehicle"] = function()
    -- Clear pulled over state globally before impound
    ClearPulledOverVehicleState(targetedVehicle)
    isVehicleMenuOpen, isImpounding, currentActionIndex = false, true, 1
end

    end

    table.insert(keys, "Close Menu")
    actions["Close Menu"] = function()
        isVehicleMenuOpen, targetedVehicle = false, nil
    end

    -- Draw UI
    DrawRect(0.15, 0.4, 0.22, 0.45, 0, 0, 0, 180)
    drawText(0.06, 0.22, title)
    for i, name in ipairs(keys) do
        local textToShow = (i == currentActionIndex) and ("~b~" .. name) or ("~w~" .. name)
        drawText(0.06, 0.25 + (i * 0.03), textToShow)
    end

    if menuNavCooldown > 0 then return end
    if IsControlJustReleased(0, 172) then
        currentActionIndex = currentActionIndex - 1
        if currentActionIndex < 1 then currentActionIndex = #keys end
        menuNavCooldown = 15
    elseif IsControlJustReleased(0, 173) then
        currentActionIndex = currentActionIndex + 1
        if currentActionIndex > #keys then currentActionIndex = 1 end
        menuNavCooldown = 15
    elseif IsControlJustReleased(0, 191) then
        local actionKey = keys[currentActionIndex]
        if actions[actionKey] then actions[actionKey]() end
        menuNavCooldown = 15
    end
    if IsControlJustReleased(0, 177) then
        isVehicleMenuOpen, targetedVehicle = false, nil
    end
end



function DrawAndHandleDispatchMenu()
    local title = "Dispatch Menu"
    local keys = {"Request Callout", "Request Callout Info"}
    DrawRect(0.15, 0.4, 0.22, 0.45, 0, 0, 0, 180);
    drawText(0.06, 0.22, title)
    for i, name in ipairs(keys) do
        local textToShow = (i == currentActionIndex) and ("~b~" .. name) or ("~w~" .. name)
        drawText(0.06, 0.25 + (i * 0.03), textToShow)
    end
    if menuNavCooldown > 0 then return end
    if IsControlJustReleased(0, 172) then currentActionIndex = currentActionIndex - 1; if currentActionIndex < 1 then currentActionIndex = #keys end; menuNavCooldown = 15
    elseif IsControlJustReleased(0, 173) then currentActionIndex = currentActionIndex + 1; if currentActionIndex > #keys then currentActionIndex = 1 end; menuNavCooldown = 15
    elseif IsControlJustReleased(0, 191) then local actionKey = keys[currentActionIndex]; if dispatchActions[actionKey] then dispatchActions[actionKey]() end; menuNavCooldown = 15 end
    if IsControlJustReleased(0, 177) then isDispatchMenuOpen = false end
end
function DrawAndHandleImpoundMenu()
    local title = "Impound / Penalty Menu"
    local impoundReasons = {
        ["No Insurance"] = {fine = 300, reason = "No Insurance"},
        ["No Tax"] = {fine = 100, reason = "No Road Tax"},
        ["Stolen Vehicle"] = {fine = 0, reason = "Stolen Vehicle"},
        ["Dangerous Condition"] = {fine = 250, reason = "Dangerous Condition"},
        ["Abandonment"] = {fine = 50, reason = "Vehicle Abandonment"},
        ["Suspect Under Arrest"] = {fine = 500, reason = "Suspect Under Arrest"},
        ["No Parking Zone"] = {fine = 50, reason = "No Parking Zone"},
        ["Obstruction"] = {fine = 75, reason = "Causing Obstruction"},
        ["Drink Driving"] = {fine = 500, reason = "Seized for Drink Driving"},
        ["Drug Driving"] = {fine = 500, reason = "Seized for Drug Driving"},
        ["Section 59 Warning"] = {fine = 200, reason = "Anti-Social Driving (s59 Police Reform Act)"},
        ["Unlicensed Driver"] = {fine = 300, reason = "No Valid Driving Licence"},
        ["Invalid MOT"] = {fine = 150, reason = "No Valid MOT Certificate"},
        ["Illegal Modifications"] = {fine = 200, reason = "Vehicle Has Illegal Modifications"},
        ["Crime Scene Evidence"] = {fine = 0, reason = "Vehicle Held as Evidence"},
        ["DVLA Clamp/Seizure"] = {fine = 100, reason = "DVLA Clamp or Seizure"},
        ["Hit and Run"] = {fine = 400, reason = "Involved in Fail to Stop Collision"}
    }

    local keys = {}
    for k in pairs(impoundReasons) do table.insert(keys, k) end
    
    -- ✨ Add Penalty Charge Notice option
    table.insert(keys, "Issue Penalty Charge Notice")
    table.insert(keys, "Go Back")
    
    DrawRect(0.15, 0.4, 0.22, 0.45, 0, 0, 0, 180)
    drawText(0.06, 0.22, title)
    for i, name in ipairs(keys) do
        local textToShow = (i == currentActionIndex) and ("~b~" .. name) or ("~w~" .. name)
        drawText(0.06, 0.25 + (i * 0.03), textToShow)
    end
    
    if menuNavCooldown > 0 then return end
    if IsControlJustReleased(0, 172) then 
        currentActionIndex = currentActionIndex - 1; 
        if currentActionIndex < 1 then currentActionIndex = #keys end; 
        menuNavCooldown = 15
    elseif IsControlJustReleased(0, 173) then 
        currentActionIndex = currentActionIndex + 1; 
        if currentActionIndex > #keys then currentActionIndex = 1 end; 
        menuNavCooldown = 15
    elseif IsControlJustReleased(0, 191) then
        local actionKey = keys[currentActionIndex]
        if actionKey == "Go Back" then
            isImpounding = false; currentActionIndex = 1
        elseif actionKey == "Issue Penalty Charge Notice" then
            -- 📋 Ask officer to fill PCN details
            local inputs = lib.inputDialog("Penalty Charge Notice", {
                { type = "input", label = "Offence", required = true },
                { type = "number", label = "Fine (£)", default = 50, min = 20, max = 1000, required = true }
            })
            if inputs then
                local offence, fine = inputs[1], inputs[2]
                TriggerServerEvent("police:server:issuePCN", GetVehicleNumberPlateText(targetedVehicle), offence, fine)
                notify("~g~Penalty Charge Notice issued for ~y~" .. offence .. "~w~ (£" .. fine .. ")")
            else
                notify("~y~PCN canceled.")
            end
        else
            local reasonData = impoundReasons[actionKey]
            if reasonData then impoundVehicle(reasonData.reason, reasonData.fine) end
        end
        menuNavCooldown = 15
    end
    if IsControlJustReleased(0, 177) then isImpounding, currentActionIndex = false, 1 end
end

