
-- Add these variables at the top of your file
local isEscorting = false
local escortedPed = nil
local escortThread = nil
local lastMaintainPositionTime = 0

-- Add these helper functions somewhere in interactions.lua

function IsPedCuffed(ped)
    return pedData[ped] and pedData[ped].isCuffed == true
end

function IsBeingEscorted(ped)
    return pedData[ped] and pedData[ped].isEscorted == true
end


--[[ client/functions/interactions.lua ]] -- This file contains all functions related to direct interactions with peds and vehicles.
function refreshInteractionMenu()
    isMenuOpen = false
    CreateThread(function()
        Wait(150) -- A short delay for the main loop to register the menu is closed
        isMenuOpen = true
        currentActionIndex = 1 -- Reset selection to the top of the new menu
    end)
end

-- Add this at the beginning of each questioning response function:
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

function setPostInteractionState(ped)
    if not DoesEntityExist(ped) then return end
    
    local data = pedData[ped]
    if not data then return end
    
    debugLog("setPostInteractionState: Managing ped state after interaction")
    
    if data.isCuffed then
        -- Cuffed peds should stay in arrest pose
        LoadAnimDict("mp_arresting")
        TaskPlayAnim(ped, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
        FreezeEntityPosition(ped, true)
    elseif data.removedFromVehicle and pulledOverVehicle then
        -- Traffic stop suspects should maintain surrender pose
        SetSuspectSurrenderPose(ped)
    else
        -- Others get a neutral standing pose to prevent wandering
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
        FreezeEntityPosition(ped, true)
    end
end

function ensurePedOutOfVehicleForInteraction(ped)
    if not pulledOverVehicle or not DoesEntityExist(pulledOverVehicle) then
        return -- Not a traffic stop
    end
    
    local driver = GetPedInVehicleSeat(pulledOverVehicle, -1)
    if driver ~= ped then
        return -- Not the driver
    end
    
    if not IsPedInVehicle(ped, pulledOverVehicle, false) then
        return -- Already out of vehicle
    end
    
    debugLog("ensurePedOutOfVehicleForInteraction: Making suspect exit for interaction")
    
    -- Mark as removed from vehicle
    pedData[ped] = pedData[ped] or {}
    pedData[ped].removedFromVehicle = true
    updateSyncedPedState(ped, {removedFromVehicle = true})
    
    -- Make them exit
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    TaskLeaveVehicle(ped, pulledOverVehicle, 0)
    
    -- Set them up in surrender pose after exit
    CreateThread(function()
        local timeout = 5000
        while IsPedInAnyVehicle(ped, false) and timeout > 0 do
            Wait(100)
            timeout = timeout - 100
        end
        
        if not IsPedInAnyVehicle(ped, false) then
            SetSuspectSurrenderPose(ped)
            debugLog("ensurePedOutOfVehicleForInteraction: Suspect now on foot in surrender pose")
        end
    end)
end

-- =============================================================================
-- || INTERACTION START/STOP FUNCTIONS                                        ||
-- =============================================================================

function startInteraction(ped)
    if isMenuOpen or not ped or isDispatchMenuOpen or isBusy then return end

ensurePedOutOfVehicleForInteraction(ped)
    local isReopening = pedData[ped] and pedData[ped].isCuffed
    targetedPed = ped

    if not isReopening then
        if not IsPedInAnyVehicle(ped, false) then
            ClearPedTasksImmediately(ped)
            TaskTurnPedToFaceEntity(ped, PlayerPedId(), -1)
            Wait(750)
            TaskStartScenarioInPlace(ped, "CODE_HUMAN_POLICE_CROWD_CONTROL", 0,
                                     true)
            FreezeEntityPosition(ped, true)
        else
            TaskLookAtEntity(ped, PlayerPedId(), -1, 2048, 3)
        end
    end

    if not pedData[ped] then
        -- This generates the full profile locally
        generateRandomPedData(ped)
        -- --- <<< MODIFIED: This now sends the COMPLETE profile to the server >>>
        updateSyncedPedState(ped, pedData[ped])
    end

    isMenuOpen = true
    currentActionIndex = 1
end

function startVehicleInteraction(vehicle)
    if isMenuOpen or isVehicleMenuOpen or isDispatchMenuOpen or isBusy then
        return
    end
    targetedVehicle = vehicle
    isVehicleMenuOpen = true
    currentActionIndex = 1

    if not vehicleData[vehicle] then
        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        TriggerServerEvent('police:requestVehicleData', vehicleNetId)
    end
end

function closeInteractionMenu(forceClear)
    if targetedPed and DoesEntityExist(targetedPed) then
        local d = pedData[targetedPed]
        
        -- Only clear tasks if not cuffed or being escorted
        if not (d and d.isCuffed and d.inVehicle) and
            (forceClear or (d and not d.isCuffed)) then
            
            if not IsPedInAnyVehicle(targetedPed, false) then
                FreezeEntityPosition(targetedPed, false)
            end
            
            -- Better task management for post-interaction
            if forceClear then
                -- Complete release - let them roam
                ClearPedTasks(targetedPed)
                if d then
                    d.surrenderActive = false
                end
            else
                -- Normal menu close - check if they should maintain position
                if pulledOverVehicle and d and d.removedFromVehicle then
                    -- They're part of a traffic stop and should stay in surrender pose
                    SetSuspectSurrenderPose(targetedPed)
                else
                    -- Give them a neutral standing task
                    ClearPedTasks(targetedPed)
                    TaskStartScenarioInPlace(targetedPed, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
                end
            end
        end
    end
    
    isMenuOpen, isQuestioning, isJailing, isBusy = false, false, false, false

    local shouldClearTarget = true
    if targetedPed and pedData[targetedPed] and pedData[targetedPed].isCuffed then
        shouldClearTarget = false
    end
    if forceClear or shouldClearTarget then 
        targetedPed = nil 
    end
end

-- =============================================================================
-- || VEHICLE-RELATED ACTIONS                                                 ||
-- =============================================================================

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
    SetEntityAsNoLongerNeeded(targetedVehicle) -- Release mission entity status
    FreezeEntityPosition(targetedVehicle, false)
    FreezeEntityPosition(driver, false)
    ClearPedTasksImmediately(driver)
    TaskVehicleDriveWander(driver, targetedVehicle, 20.0, 786603)
    isTrafficStopActive = false -- This now correctly ends the stop

    if trafficBlip and DoesBlipExist(trafficBlip) then
        RemoveBlip(trafficBlip);
        trafficBlip = nil
    end
    pulledOverVehicle, isBusy, isTrafficStopActive = nil, false, false
    notify("~g~Vehicle has been released.")
    isVehicleMenuOpen, targetedVehicle = false, nil
end

function impoundVehicle(reason, fine)
    isVehicleMenuOpen, isBusy = false, true
    isImpounding = false
    notify("~y~Impounding vehicle for: " .. reason .. ".")
    Wait(3000)

    if not targetedVehicle or not DoesEntityExist(targetedVehicle) then
        return
    end

    local driver = GetPedInVehicleSeat(targetedVehicle, -1)
    if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
        TaskLeaveVehicle(driver, targetedVehicle, 0)
        Wait(2000)
        FreezeEntityPosition(driver, true)
    end

    SetEntityAsNoLongerNeeded(targetedVehicle)
    DeleteEntity(targetedVehicle)

    if DoesEntityExist(driver) then
        TaskStartScenarioInPlace(driver, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
        Wait(100)
        FreezeEntityPosition(driver, false)
        notify("~g~Vehicle has been impounded. Driver is released.")
    else
        notify("~g~Vehicle has been impounded.")
    end
    pulledOverVehicle, isBusy, isTrafficStopActive, isVehicleMenuOpen, targetedVehicle =
        nil, false, false, false, nil
end

function askPassengersToExit()
    if not targetedVehicle or not DoesEntityExist(targetedVehicle) then
        return
    end
    isVehicleMenuOpen, isBusy = false, true
    local playerPed = PlayerPedId()
    local passengers = {}
    for i = 0, GetVehicleMaxNumberOfPassengers(targetedVehicle) - 1 do
        if not IsVehicleSeatFree(targetedVehicle, i) then
            local passenger = GetPedInVehicleSeat(targetedVehicle, i)
            if DoesEntityExist(passenger) and not IsPedAPlayer(passenger) then
                table.insert(passengers, passenger)
            end
        end
    end

    if #passengers > 0 then
        notify("~y~Asking passengers to exit the vehicle...")
        for i, passenger in ipairs(passengers) do
            TaskLeaveVehicle(passenger, targetedVehicle, 0)
            Wait(2000)
            local pos = GetEntityCoords(playerPed) +
                            GetEntityForwardVector(playerPed) * (-1.5 - i * 1.0)
            SetEntityCoords(passenger, pos.x, pos.y, pos.z, false, false, false,
                            true)
            FreezeEntityPosition(passenger, true)
            TaskTurnPedToFaceEntity(passenger, playerPed, -1)
            if not pedData[passenger] then
                pedData[passenger] = generateRandomPedData(passenger)
                updateSyncedPedState(passenger, pedData[passenger])
            end
        end
        notify(string.format("~g~All %d passengers have exited.", #passengers))
    else
        notify("~y~There are no passengers in this vehicle.")
    end
    isBusy = false
end

-- =============================================================================
-- || ACTION TABLES                                                           ||
-- =============================================================================

defaultActions = {
["Question"] = function() 
    -- Remove the maintainSuspectPosition call from here
    ensurePedOutOfVehicleForInteraction(targetedPed)
    -- Only call maintain position once when starting questioning
    if targetedPed and DoesEntityExist(targetedPed) then
        FreezeEntityPosition(targetedPed, true)
        local data = pedData[targetedPed]
        if data and data.removedFromVehicle then
            SetSuspectSurrenderPose(targetedPed)
        end
    end
    isQuestioning, currentActionIndex = true, 1 
end,

["Breathalyze"] = function()
    if isBusy then return end
    maintainSuspectPosition(targetedPed)

    isBusy = true
    isMenuOpen = false
    
    local playerPed = PlayerPedId()
    local suspectPed = targetedPed
    
    -- Critical: Ensure ped won't despawn during interaction
    SetEntityAsMissionEntity(suspectPed, true, true)
    SetEntityAsNoLongerNeeded(suspectPed, false)
    SetPedAsNoLongerNeeded(suspectPed, false)
    
    -- Store original position before any changes
    local originalPos = GetEntityCoords(suspectPed)
    local originalHeading = GetEntityHeading(suspectPed)
    
    -- Load animation dictionaries for proper breathalyzer interaction
    local playerAnimDict = "mp_common"
    local suspectAnimDict = "random@mugging3"
    
    RequestAnimDict(playerAnimDict)
    RequestAnimDict(suspectAnimDict)
    
    while not HasAnimDictLoaded(playerAnimDict) or not HasAnimDictLoaded(suspectAnimDict) do
        Wait(10)
    end
    
    notify("Performing breathalyzer test...")
    
    -- Clear any existing tasks but don't move the ped yet
    ClearPedTasksImmediately(suspectPed)
    ClearPedTasksImmediately(playerPed)
    
    -- Use the ped's current position (don't try to reposition)
    local playerPos = GetEntityCoords(playerPed)
    local suspectPos = GetEntityCoords(suspectPed)
    
    -- Calculate face-to-face heading
    local dx = playerPos.x - suspectPos.x
    local dy = playerPos.y - suspectPos.y
    local suspectHeading = math.atan2(dy, dx) * 180.0 / math.pi - 90.0
    
    -- Only adjust heading, keep ped at their current position
    SetEntityHeading(suspectPed, suspectHeading)
    
    -- Wait for heading adjustment
    Wait(200)
    
    -- Freeze in current position (already on ground)
    FreezeEntityPosition(suspectPed, true)
    SetBlockingOfNonTemporaryEvents(suspectPed, true)
    
    -- Play appropriate animations - player extends hand, suspect complies
TaskPlayAnim(playerPed, "gestures@m@standing@casual", "gesture_point", 8.0, -8.0, 5000, 48, 0, false, false, false)
    TaskPlayAnim(suspectPed, suspectAnimDict, "handsup_standing_base", 8.0, -8.0, 5000, 1, 0, false, false, false)
    
    -- Wait for test duration
    Wait(5000)
    
    -- Clear animations
    ClearPedTasks(playerPed)
    ClearPedTasks(suspectPed)
    
    -- Restore ped to controlled interaction state
    SetBlockingOfNonTemporaryEvents(suspectPed, false)
    
    -- Process test results
    local data = pedData[suspectPed]
local checks = ensureChecksTable(suspectPed)
    local result = data.isDrunk and
                   math.random(Config.Breathalyzer.drunkReadingRange.min, Config.Breathalyzer.drunkReadingRange.max) or
                   math.random(Config.Breathalyzer.soberReadingRange.min, Config.Breathalyzer.soberReadingRange.max)
    
    if result > Config.Breathalyzer.ukLimit then
        notify(string.format(Config.Breathalyzer.failMessage, result))
    else
        notify(string.format(Config.Breathalyzer.passMessage, result))
    end
    
checks.breathalyze = true
updateSyncedPedState(suspectPed, {checksCompleted = checks})
    
    -- Restore normal interaction state
    TaskTurnPedToFaceEntity(suspectPed, playerPed, -1)
    FreezeEntityPosition(suspectPed, true)
    setPostInteractionState(suspectPed)
    isBusy = false
    isMenuOpen = true
end,
    ["Drug Test"] = function()
        if isBusy then return end
    maintainSuspectPosition(targetedPed)
        isMenuOpen, isBusy = false, true
        local playerPed = PlayerPedId()
        ClearPedTasksImmediately(targetedPed)
        LoadAnimDict("mini@repair")
TaskPlayAnim(playerPed, "gestures@m@standing@casual", "gesture_point", 8.0, -8.0, 5000, 48, 0, false, false, false)

        notify("Performing drug swab test...")
        Wait(6000)
        ClearPedTasks(playerPed)
local data = pedData[targetedPed]
local checks = ensureChecksTable(targetedPed)
        if data.isOnDrugs then
            notify(string.format("~y~Test Result:~r~ POSITIVE ~w~for %s.",
                                 data.drugType))
        else
            notify("~y~Test Result:~g~ NEGATIVE ~w~for all substances.")
        end
checks.drugtest = true
updateSyncedPedState(targetedPed, {checksCompleted = checks})
setPostInteractionState(targetedPed)
        isBusy, isMenuOpen = false, true
    end,
["Search"] = function()
    if isBusy then 
        notify("~r~Cannot perform search - officer is currently busy.")
        return 
    end
    maintainSuspectPosition(targetedPed)
    isBusy, isMenuOpen = true, false
    
    local playerPed = PlayerPedId()
    local suspectPed = targetedPed
    
    -- Ensure ped won't despawn during search
    SetEntityAsMissionEntity(suspectPed, true, true)
    SetEntityAsNoLongerNeeded(suspectPed, false)
    
    -- Load required animation dictionaries (using known working animations)
    local playerAnimDict = "anim@gangops@hostage@"
    local suspectAnimDict = "random@mugging3"
    
    RequestAnimDict(playerAnimDict)
    RequestAnimDict(suspectAnimDict)
    
    while not HasAnimDictLoaded(playerAnimDict) or not HasAnimDictLoaded(suspectAnimDict) do
        Wait(10)
    end
    
    -- Clear existing tasks 
    ClearPedTasksImmediately(suspectPed)
    ClearPedTasksImmediately(playerPed) 
    
    -- Position suspect to face away from player for pat down
    local playerPos = GetEntityCoords(playerPed)
    local suspectPos = GetEntityCoords(suspectPed)
    
    -- Calculate heading for suspect to face away from player
    local dx = playerPos.x - suspectPos.x
    local dy = playerPos.y - suspectPos.y
    local awayHeading = math.atan2(dy, dx) * 180.0 / math.pi + 90.0 -- Face away
    
    SetEntityHeading(suspectPed, awayHeading)
    Wait(500)
    
    -- CRITICAL: Freeze suspect BEFORE animations
    FreezeEntityPosition(suspectPed, true)
    SetBlockingOfNonTemporaryEvents(suspectPed, true)
    
    notify("Conducting pat down search...")
    
    -- Phase 1: Hands up position
    TaskPlayAnim(suspectPed, suspectAnimDict, "handsup_standing_base", 8.0, -8.0, -1, 1, 0, false, false, false)
    Wait(1000)
    
    -- Phase 2: Player search animation
    notify("Searching for contraband...")
    TaskPlayAnim(playerPed, playerAnimDict, "perp_patdown", 8.0, -8.0, 6000, 1, 0, false, false, false)
    Wait(6000)
    
    -- Clear animations
    ClearPedTasks(playerPed)
    ClearPedTasks(suspectPed)
    
    -- Process search results
    local data = pedData[suspectPed]
local checks = ensureChecksTable(suspectPed)

    if data.hasIllegalItems then
        notify(string.format("~y~Search Result:~r~ Found %s!", data.illegalItemFound))
    else
        notify("~y~Search Result:~g~ Nothing illegal was found.")
    end
    
checks.search = true
updateSyncedPedState(suspectPed, {checksCompleted = checks})
    
    -- Restore suspect state but keep them controlled
    SetBlockingOfNonTemporaryEvents(suspectPed, false)
    TaskTurnPedToFaceEntity(suspectPed, playerPed, -1)
    FreezeEntityPosition(suspectPed, true)
    setPostInteractionState(suspectPed)

    isBusy, isMenuOpen = false, true
end,
    ["Fingerprint"] = function()
        if isBusy then return end
    maintainSuspectPosition(targetedPed)
        isMenuOpen, isBusy = false, true
        notify("Taking fingerprints for identification...")
        Wait(5000)
        local data = pedData[targetedPed]
local checks = ensureChecksTable(targetedPed)

        notify(string.format("~y~ID Confirmed:~w~ %s, Age %s.", data.name,
                             data.age))
        if data.warrants then
            notify("~o~Dispatch:~r~ Subject has outstanding warrants!")
            for _, charge in ipairs(data.warrantDetails) do
                notify("~r~WARRANT: " .. charge)
            end
        else
            notify("~b~Dispatch:~g~ Subject has a clean record.")
        end
data.idVerified = true
checks.fingerprint = true
updateSyncedPedState(targetedPed, {
    idVerified = true,
    checksCompleted = checks
})
    setPostInteractionState(targetedPed)

        isBusy, isMenuOpen = false, true
    end,
["Issue Fine"] = function()
    if isBusy then return end
    maintainSuspectPosition(targetedPed)
    isBusy = true
    isMenuOpen = false

    local ped = targetedPed
    local pedData = pedData[ped]
    if not pedData then isBusy, isMenuOpen = false, true; return end

    local fineOptions = {}
    for reason, amount in pairs(Config.Fining.offenseFines) do
        table.insert(fineOptions, {
            label = reason,
            value = reason,
            description = "Default fine: £" .. amount
        })
    end
    
    -- Open the input dialog using ox_lib
    local inputs = lib.inputDialog('Issue Fine', {
        {
            type = 'select',
            label = 'Offense',
            options = fineOptions,
            required = true,
            -- <<< NEW: This event updates the amount when you select a reason >>>
            onSelect = function(value, L, id)
                local defaultAmount = Config.Fining.offenseFines[value]
                if defaultAmount then
                    lib.setDialogInputValue(id, 2, defaultAmount) -- Set value for the second input field
                end
            end
        },
        {
            type = 'number',
            label = 'Fine Amount (£)',
            placeholder = 'e.g., 150',
            required = true,
            min = 10,
            max = 5000,
            default = Config.Fining.offenseFines[fineOptions[1].value] -- Set initial default value
        },
    })

    if inputs then
        local reason = inputs[1]
        local amount = inputs[2]

        TriggerServerEvent('police:server:issueFine', {
            pedName = pedData.name,
            reason = reason,
            amount = amount
        })

        notify(string.format("You issued a fine of £%s to %s.", amount, pedData.name))
        closeInteractionMenu(true)
    else
        notify("Fining canceled.")
        isBusy, isMenuOpen = false, true -- Restore state if canceled
    end
end,
["Arrest"] = function()
    if isBusy or IsPedInAnyVehicle(targetedPed, false) then return end
    isBusy, isMenuOpen = true, false
    local ped = targetedPed
    local playerPed = PlayerPedId()
    
    -- CRITICAL: Ensure ped data exists before proceeding
    if not pedData[ped] then
        generateRandomPedData(ped)
        updateSyncedPedState(ped, pedData[ped])
    end
    
    local data = pedData[ped]
    if not data then
        notify("~r~Error: Unable to arrest - ped data not available")
        isBusy, isMenuOpen = false, true
        return
    end
    
    local animDict = "mp_arresting"
    LoadAnimDict(animDict)
    SetEntityHeading(ped, GetEntityHeading(playerPed))
    Wait(500)
    TaskGoToEntity(playerPed, ped, 1.5, -1.0, 1.0, 1073741824, 1)
    Wait(1500)
    notify("Cuffing the suspect...")
    TaskPlayAnim(ped, animDict, "crim_p2_back_left", 8.0, -8.0, -1, 0, 0,
                 false, false, false)
    TaskPlayAnim(playerPed, animDict, "cop_p2_back_left", 8.0, -8.0, -1, 0,
                 0, false, false, false)
    Wait(5000)
    ClearPedTasks(playerPed)
    TaskTurnPedToFaceEntity(ped, playerPed, -1)
    Wait(1000)
    ClearPedTasksImmediately(ped)
    TaskPlayAnim(ped, animDict, "idle", 8.0, -8.0, -1, 49, 0, false, false,
                 false)
    FreezeEntityPosition(ped, true)
    
    -- Update ped state
    data.isCuffed = true
    updateSyncedPedState(ped, {isCuffed = true})
    
    -- Safe notification with fallback name
    local pedName = data.name or "the suspect"
    notify("You have arrested " .. pedName)
    
    if ped == activeCalloutPedEntity then
        TriggerServerEvent('police:calloutCompleted', 'arrested')
    end
    isMenuOpen, isBusy = true, false
    currentActionIndex = 1
end,
["Let Go"] = function()
    if not targetedPed then return end
    
    -- Clean ped state completely
    if pedData[targetedPed] then
        pedData[targetedPed].isCuffed = false
        pedData[targetedPed].isEscorted = false
        pedData[targetedPed].isFollowing = false
        pedData[targetedPed].complianceMode = nil
        pedData[targetedPed].removedFromVehicle = nil
        pedData[targetedPed].surrenderActive = false -- Clear surrender flag
    end

    -- CRITICAL: Properly clear surrender animation and state
    CleanupSurrenderThread(targetedPed)
    ClearPedTasksImmediately(targetedPed)
    SetBlockingOfNonTemporaryEvents(targetedPed, false)
    FreezeEntityPosition(targetedPed, false)
    
    -- Give them a normal idle task to prevent wandering
    TaskStartScenarioInPlace(targetedPed, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
    
    -- Wait a moment then give them freedom
    CreateThread(function()
        Wait(2000) -- Let them settle in idle pose
        if DoesEntityExist(targetedPed) then
            ClearPedTasks(targetedPed)
            TaskWanderStandard(targetedPed, 10.0, 10)
            debugLog("Let Go: Suspect fully released and free to roam")
        end
    end)

    -- If this ped was the driver of the pulled over vehicle, release the vehicle too
    if pulledOverVehicle and DoesEntityExist(pulledOverVehicle) then
        local driver = GetPedInVehicleSeat(pulledOverVehicle, -1)
        if not DoesEntityExist(driver) or driver == targetedPed then
            releaseVehicleAndPeds(pulledOverVehicle)
        end
    end

    notify("~g~Suspect released and free to go.")
    closeInteractionMenu(true)
end,

["Follow Me"] = function()
    local ped = targetedPed

    if not pedData[ped] then generateRandomPedData(ped) end
    local data = pedData[ped]
    if not data then return end

    data.isFollowing = true
    updateSyncedPedState(ped, {isFollowing = true})

    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    TaskFollowToOffsetOfEntity(ped, PlayerPedId(), 0.0, -2.0, 0.0, 1.5, -1, 2.0, true)

    notify(data.name .. " is now following you.")
    refreshInteractionMenu()
end,

["Stop Following"] = function()
    local ped = targetedPed

    if not pedData[ped] then
        generateRandomPedData(ped)
        updateSyncedPedState(ped, pedData[ped])
    end

    local data = pedData[ped]
    if not data then return end

    data.isFollowing = false
    updateSyncedPedState(ped, {isFollowing = false})

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)

    if data.isCuffed then
        RequestAnimDict("mp_arresting")
        while not HasAnimDictLoaded("mp_arresting") do Wait(10) end
        TaskPlayAnim(ped, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
    else
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
    end

    FreezeEntityPosition(ped, true)
    notify(data.name .. " has stopped following.")
    refreshInteractionMenu()
end,
}

arrestedActions = {
-- Escort (drag/attach)
["Escort"] = function()
    if isBusy then return end
    isBusy = true
    local ped = targetedPed
    local playerPed = PlayerPedId()

    if not pedData[ped] or not pedData[ped].isCuffed then
        notify("~r~You must cuff the suspect first!")
        isBusy = false
        return
    end

    pedData[ped].isEscorted = true
    updateSyncedPedState(ped, {isEscorted = true})

    isEscorting = true
    escortedPed = ped

    -- Clear and attach ped
    ClearPedTasksImmediately(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)

    RequestAnimDict("mp_arresting")
    while not HasAnimDictLoaded("mp_arresting") do Wait(10) end
    TaskPlayAnim(ped, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)

    AttachEntityToEntity(
        ped, playerPed,
        11816, -- player hand bone
        0.45, 0.15, 0.0, -- offset
        0.0, 0.0, 0.0,  -- rotation
        false, false, false, false, 2, true
    )

    local pedName = pedData[ped].name or "the suspect"
    notify("~g~You are now escorting " .. pedName)
    isBusy = false
    refreshInteractionMenu()
end,

["Stop Escorting"] = function()
    if not isEscorting or escortedPed ~= targetedPed then
        notify("~r~You are not escorting this person.")
        return
    end

    local ped = escortedPed
    pedData[ped].isEscorted = false
    updateSyncedPedState(ped, {isEscorted = false})

    isEscorting = false
    escortedPed = nil

    DetachEntity(ped, true, false)

    ClearPedTasksImmediately(ped)
    RequestAnimDict("mp_arresting")
    while not HasAnimDictLoaded("mp_arresting") do Wait(10) end
    TaskPlayAnim(ped, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
    FreezeEntityPosition(ped, true)

    local pedName = pedData[ped].name or "the suspect"
    notify("~g~Stopped escorting " .. pedName)
    refreshInteractionMenu()
end,

-- Follow (AI walk behind you)
["Follow Me"] = function()
    local ped = targetedPed

    if not pedData[ped] then generateRandomPedData(ped) end
    local data = pedData[ped]
    if not data then return end

    data.isFollowing = true
    updateSyncedPedState(ped, {isFollowing = true})

    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    TaskFollowToOffsetOfEntity(ped, PlayerPedId(), 0.0, -2.0, 0.0, 1.5, -1, 2.0, true)

    notify(data.name .. " is now following you.")
    refreshInteractionMenu()
end,

["Stop Following"] = function()
    local ped = targetedPed

    if not pedData[ped] then
        generateRandomPedData(ped)
        updateSyncedPedState(ped, pedData[ped])
    end

    local data = pedData[ped]
    if not data then return end

    data.isFollowing = false
    updateSyncedPedState(ped, {isFollowing = false})

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)

    if data.isCuffed then
        RequestAnimDict("mp_arresting")
        while not HasAnimDictLoaded("mp_arresting") do Wait(10) end
        TaskPlayAnim(ped, "mp_arresting", "idle", 8.0, -8.0, -1, 49, 0, false, false, false)
    else
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
    end

    FreezeEntityPosition(ped, true)
    notify(data.name .. " has stopped following.")
    refreshInteractionMenu()
end,

    ["Place in Vehicle"] = function()
        if isBusy then return end
        isBusy = true
        local ped = targetedPed
        if pedData[ped].isEscorted then
            arrestedActions["Stop Escorting"]();
            Wait(500)
        end
        local vehicle = GetClosestVehicle(GetEntityCoords(ped), 5.0, 0, 70)
        if not vehicle or not DoesEntityExist(vehicle) then
            notify("No vehicle nearby.");
            isBusy = false;
            return
        end
        local freeSeat = nil
        for i = GetVehicleMaxNumberOfPassengers(vehicle) - 1, -1, -1 do
            if IsVehicleSeatFree(vehicle, i) then
                freeSeat = i;
                break
            end
        end
        if freeSeat then
TaskWarpPedIntoVehicle(ped, vehicle, freeSeat)
pedData[ped].inVehicle = true
pedData[ped].removedFromVehicle = false -- ✅ they’re back in now
updateSyncedPedState(ped, {inVehicle = true})
            notify("Suspect placed in vehicle.")
            closeInteractionMenu(false)
        else
            notify("No free seats in the vehicle.")
        end
        isBusy = false
    end,
    ["Jail"] = function() isJailing, currentActionIndex = true, 1 end,
["Uncuff"] = function()
    if isBusy then return end
    isBusy = true
    local ped = targetedPed
    
    -- Ensure pedData exists and has required fields
    if not pedData[ped] then
        generateRandomPedData(ped)
        updateSyncedPedState(ped, pedData[ped])
    end
    
    local data = pedData[ped]
    if not data then 
        notify("Error: Unable to uncuff - ped data not found")
        isBusy = false
        return 
    end
    
    data.isCuffed = false
    updateSyncedPedState(ped, {isCuffed = false})
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    
    -- Safe string concatenation with fallback
    local pedName = data.name or "the suspect"
    notify("You have uncuffed " .. pedName)
    
    Wait(500)
    isBusy = false
    refreshInteractionMenu()
end,

}

specialQuestionActions = {
['id_check'] = function()
    maintainSuspectPosition(targetedPed)
    local data = pedData[targetedPed]
    
    -- CRITICAL: If this is a traffic stop and suspect is in vehicle, make them exit first
    if pulledOverVehicle and DoesEntityExist(pulledOverVehicle) then
        local driver = GetPedInVehicleSeat(pulledOverVehicle, -1)
        if driver == targetedPed and IsPedInVehicle(targetedPed, pulledOverVehicle, false) then
            debugLog("ID Check: Making suspect exit vehicle for ID check")
            
            -- Mark them as removed from vehicle BEFORE they exit
            data.removedFromVehicle = true
            updateSyncedPedState(targetedPed, {removedFromVehicle = true})
            
            -- Make them exit vehicle
            FreezeEntityPosition(targetedPed, false)
            ClearPedTasksImmediately(targetedPed)
            TaskLeaveVehicle(targetedPed, pulledOverVehicle, 0)
            
            -- Wait for them to exit, then set surrender pose
            CreateThread(function()
                local timeout = 5000
                while IsPedInAnyVehicle(targetedPed, false) and timeout > 0 do
                    Wait(100)
                    timeout = timeout - 100
                end
                
                if not IsPedInAnyVehicle(targetedPed, false) then
                    SetSuspectSurrenderPose(targetedPed)
                    debugLog("ID Check: Suspect exited vehicle and is in surrender pose")
                else
                    debugLog("ID Check: Suspect failed to exit vehicle in time")
                end
            end)
            
            -- Give them time to exit before continuing
            Wait(2000)
        end
    end
    
    -- Now proceed with ID check
    data.idAttempted = true
    if data.hasID then
        data.idVerified = true
        notify("ID Verified: " .. data.name .. ", Age: " .. data.age)
    else
        notify("The individual does not have any ID on them.")
    end
    updateSyncedPedState(targetedPed, {
        idAttempted = true, 
        idVerified = data.idVerified,
        removedFromVehicle = true  -- Ensure this flag is set
    })
end,
    ['ask_activity'] = function()
    maintainSuspectPosition(targetedPed)
        notify(pedData[targetedPed].name ..
                   " says: \"Just minding my own business, officer.\"")
    end,
    ['ask_ownership'] = function()
    maintainSuspectPosition(targetedPed)
        if not pulledOverVehicle or not DoesEntityExist(pulledOverVehicle) then
            notify("You are not in an active traffic stop.")
            return
        end

        local vehData = vehicleData[pulledOverVehicle]
        local driverData = pedData[targetedPed]

        -- Failsafe: Do not proceed if either data table is missing.
        if not vehData or not driverData or not driverData.name or
            not vehData.owner then
            debugLog(
                "ask_ownership: Data not synced, defaulting to suspicious response.")
            notify((driverData and driverData.name or "He") ..
                       " says: \"Uh... yeah, it's mine. Why do you ask?\"")
            return
        end

        if vehData.owner == driverData.name then
            notify(driverData.name ..
                       " says: \"Yes, of course it's my vehicle, officer.\"")
        elseif vehData.hasPermission then
            notify(driverData.name .. " says: \"No, it belongs to " ..
                       vehData.owner .. ". They let me borrow it.\"")
        else -- Stolen
            notify(driverData.name ..
                       " says: \"Uh... yeah, it's mine. Why do you ask?\"")
        end
    end
}

dispatchActions = {
    ["Request Callout"] = function()
        TriggerServerEvent("police:requestNewCallout")
        isDispatchMenuOpen = false
    end,
    ["Request Callout Info"] = function()
        if activeCalloutPedEntity and DoesEntityExist(activeCalloutPedEntity) then
            notify("~y~[DISPATCH] Info: ~w~" ..
                       GetPedDescription(activeCalloutPedEntity))
        else
            notify("There is no active callout.")
        end
        isDispatchMenuOpen = false
    end
}

function MakeSuspectExitVehicle(ped, vehicle)
    if not DoesEntityExist(ped) or not DoesEntityExist(vehicle) then return end

    pedData[ped] = pedData[ped] or {}
    pedData[ped].removedFromVehicle = true -- <<< CRITICAL: tell compliance loop to stop reseating them

    -- Unfreeze and clear their tasks
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)

    -- Task them to step out
    TaskLeaveVehicle(ped, vehicle, 0)

    -- After they step out, keep them under control
    CreateThread(function()
        local timeout = 5000
        while IsPedInAnyVehicle(ped, false) and timeout > 0 do
            Wait(100)
            timeout -= 100
        end
        if not IsPedInAnyVehicle(ped, false) then
            FreezeEntityPosition(ped, true)
            TaskTurnPedToFaceEntity(ped, PlayerPedId(), -1)
            debugLog("MakeSuspectExitVehicle: Ped exited and is now compliant outside.")
        else
            debugLog("MakeSuspectExitVehicle: Ped failed to exit vehicle in time.")
        end
    end)
end
