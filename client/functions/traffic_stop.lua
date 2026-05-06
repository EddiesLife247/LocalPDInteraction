--[[ client/functions/traffic_stop.lua ]]

-- Global variables for thread management
local pursuitCheckerThread = nil
local surrenderThreads = {} -- Track surrender animation threads
local TYRE_INDEXES = {0, 1, 2, 3, 4, 5, 45, 47} -- front/back + some rear dually slots; tweak as needed

local function CountBlownTyres(vehicle)
    if not DoesEntityExist(vehicle) then return 0 end
    local blown = 0
    for _, idx in ipairs(TYRE_INDEXES) do
        if IsVehicleTyreBurst(vehicle, idx, false) then
            blown = blown + 1
        end
    end
    return blown
end

function ClearPulledOverVehicleState(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    local vehNetId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerServerEvent("police:server:setPulledOverVehicle", vehNetId, false)
    pulledOverVehicle = nil
end


-- PIT Maneuver Detection Functions
-- Add these functions to your traffic_stop.lua file

function CheckForPITManeuver(suspectVehicle, driver)
    if not DoesEntityExist(suspectVehicle) or not DoesEntityExist(driver) then
        return false
    end
    
    -- Check if vehicle is spinning/losing control (common result of PIT)
    local vehicleSpeed = GetEntitySpeed(suspectVehicle)
    local isSpinning = IsEntityUpsidedown(suspectVehicle) or 
                     GetVehicleWheelSpeed(suspectVehicle, 0) < 0.1 and vehicleSpeed > 5.0
    
    -- Check if vehicle has been hit recently
    local hasBeenDamaged = HasEntityBeenDamagedByAnyVehicle(suspectVehicle)
    
    -- Check if there's a police vehicle very close to the rear quarter panel
    local suspectPos = GetEntityCoords(suspectVehicle)
    local suspectHeading = GetEntityHeading(suspectVehicle)
    
    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, 1) then
            local job = Player(playerId).state.job
            if job and job.name == "police" and job.onduty then
                local policeVeh = GetVehiclePedIsIn(ped, false)
                if policeVeh and policeVeh ~= 0 and policeVeh ~= suspectVehicle then
                    local policePos = GetEntityCoords(policeVeh)
                    local distance = #(policePos - suspectPos)
                    
                    -- Check if police vehicle is close enough (within 4 units)
                    if distance < 4.0 then
                        -- Check if police vehicle contacted the rear quarter panel area
                        local suspectForward = GetEntityForwardVector(suspectVehicle)
                        local suspectRight = vector3(-suspectForward.y, suspectForward.x, 0.0)
                        
                        -- Calculate relative position of police vehicle
                        local relativePos = policePos - suspectPos
                        local forwardDot = relativePos.x * suspectForward.x + relativePos.y * suspectForward.y
                        local rightDot = relativePos.x * suspectRight.x + relativePos.y * suspectRight.y
                        
                        -- Check if police vehicle is at rear quarter (behind and to the side)
                        local isAtRearQuarter = forwardDot < -1.0 and math.abs(rightDot) > 0.5
                        
                        if isAtRearQuarter and hasBeenDamaged and (isSpinning or vehicleSpeed < 10.0) then
                            debugLog("PIT maneuver detected: Police vehicle contacted rear quarter panel")
                            return true, ped -- Return the officer who performed the PIT
                        end
                    end
                end
            end
        end
    end
    
    return false
end

function HandlePITManeuver(suspectVehicle, driver, officerPed)
    if not DoesEntityExist(suspectVehicle) or not DoesEntityExist(driver) then
        return
    end
    
    debugLog("HandlePITManeuver: Suspect vehicle has been PIT maneuvered!")
    notify("~g~PIT maneuver successful! Suspect vehicle immobilized.")
    
    -- Stop the vehicle and disable it
    BringVehicleToHalt(suspectVehicle, 2.0, 1, false)
    SetVehicleEngineOn(suspectVehicle, false, true, true)
    SetVehicleUndriveable(suspectVehicle, true)
    
    -- Clear any existing tasks for the driver
    ClearPedTasksImmediately(driver)
    SetBlockingOfNonTemporaryEvents(driver, false)
    
    -- Small delay to let the vehicle settle
    Wait(2000)
    
    -- Determine what happens next based on damage and random chance
    local vehicleHealth = GetVehicleEngineHealth(suspectVehicle)
    local isVehicleSeverelyDamaged = vehicleHealth < 300
    
    if isVehicleSeverelyDamaged then
        -- If vehicle is severely damaged, force foot pursuit
        debugLog("HandlePITManeuver: Vehicle severely damaged, suspect bailing out")
        notify("~y~Suspect is abandoning the damaged vehicle!")
        StartFootPursuit(driver, suspectVehicle)
    else
        -- Random chance of compliance vs foot bail
        local complianceChance = 70 -- 70% chance of compliance after PIT
        if math.random(1, 100) <= complianceChance then
            debugLog("HandlePITManeuver: Suspect is complying after PIT")
            notify("~g~Suspect is surrendering after the PIT maneuver!")
            
            -- Force surrender
            Wait(1000)
            SetSuspectSurrenderPose(driver)
            
            -- End the pursuit and start interaction
            EndPursuit(driver, suspectVehicle, "PIT maneuver - suspect surrendered")
        else
            debugLog("HandlePITManeuver: Suspect is still resisting, attempting foot escape")
            notify("~y~Suspect is attempting to flee on foot!")
            StartFootPursuit(driver, suspectVehicle)
        end
    end
    
    -- Award bonus to the officer who performed the PIT
    if officerPed then
        local officerSource = NetworkGetPlayerIndexFromPed(officerPed)
        if officerSource then
            TriggerServerEvent('police:server:pitBonus', officerSource)
        end
    end
end

function GetNearestPolicePed(coords, radius)
    local nearestPed = nil
    local nearestDist = radius or 50.0

    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, 1) then
            local dist = #(GetEntityCoords(ped) - coords)
            if dist < nearestDist then
                -- Use consistent job check method
                local job = Player(playerId).state.job
                if job and job.name == "police" and job.onduty then
                    nearestPed = ped
                    nearestDist = dist
                end
            end
        end
    end

    return nearestPed
end

function CheckFelonyBox(suspectVeh)
    local suspectPos = GetEntityCoords(suspectVeh)
    local hasFront, hasBack = false, false

    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, 1) then
            local job = Player(playerId).state.job
            if job and job.name == "police" and job.onduty then
                local veh = GetVehiclePedIsIn(ped, false)
                if veh and veh ~= 0 then
                    local vehPos = GetEntityCoords(veh)
                    local dist = #(vehPos - suspectPos)
                    if dist < 12.0 then
                        local forward = GetEntityForwardVector(suspectVeh)
                        local offset = vehPos - suspectPos
                        local dot = forward.x * offset.x + forward.y * offset.y
                        if dot > 0 then hasFront = true else hasBack = true end
                    end
                end
            end
        end
    end

    return (hasFront and hasBack)
end

-- Fixed surrender function with proper standing animation
function SetSuspectSurrenderPose(ped)
    if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, 1) then return end

    pedData[ped] = pedData[ped] or {}
    pedData[ped].surrenderActive = true

    ClearPedTasksImmediately(ped)

    local animDict, animName = "random@mugging3", "handsup_standing_base"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(10) end

    -- Keep them stationary but avoid permanently freezing if you need to move them later.
    -- If you *must* freeze, ensure CleanupSurrenderThread unfreezes.
    FreezeEntityPosition(ped, true)
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0.0, false, false, false)

    CreateThread(function()
        while pedData[ped] and pedData[ped].surrenderActive and DoesEntityExist(ped) and not IsPedDeadOrDying(ped, 1) do
            if not IsEntityPlayingAnim(ped, animDict, animName, 3) then
                TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 1, 0.0, false, false, false)
            end
            Wait(1000)
        end
        -- cleanup when flag flips or ped invalid
        if DoesEntityExist(ped) then
            ClearPedTasks(ped)
            FreezeEntityPosition(ped, false)
        end
    end)
end

-- Clean up surrender thread when ped is cuffed or removed
function CleanupSurrenderThread(ped)
    if not DoesEntityExist(ped) then return end
    
    if pedData[ped] then
        pedData[ped].surrenderActive = false
    end
    
    -- Force clear the animation and unfreeze
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    
    debugLog("CleanupSurrenderThread: Cleared surrender state for ped")
end

function HandleFelonyStop(driver, vehicle)
    if not (DoesEntityExist(driver) and DoesEntityExist(vehicle)) then return end

    debugLog("HandleFelonyStop: Suspect forced into felony stop compliance.")

    -- Delay to simulate panic before giving up
    local delay = math.random(Config.TrafficStop.felonyStopDelay.min, Config.TrafficStop.felonyStopDelay.max)
    TaskVehicleTempAction(driver, vehicle, 27, delay) -- rev engine/accelerate in place
    Wait(delay)

    -- Stop vehicle
    BringVehicleToHalt(vehicle, 3.0, 1, false)
    SetVehicleEngineOn(vehicle, false, true, true)

    -- Loop all occupants (driver + passengers)
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2
    for seat = -1, seats do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            CreateThread(function()
                -- Step 1: Exit vehicle
                TaskLeaveVehicle(ped, vehicle, 0)
                Wait(2000)

                -- Step 2: Walk backwards a little
                local backCoords = GetEntityCoords(ped) - GetEntityForwardVector(ped) * 5.0
                TaskGoStraightToCoord(ped, backCoords.x, backCoords.y, backCoords.z, 1.0, -1, 0.0, 0.0)
                Wait(4000)

                -- Step 3: Set proper surrender pose
                SetSuspectSurrenderPose(ped)
            end)
        end
    end

    -- Cleanup blip / state
    if trafficBlip and DoesBlipExist(trafficBlip) then
        RemoveBlip(trafficBlip)
        trafficBlip = nil
    end

    isBusy = false
    isTrafficStopActive = false
    activePursuitDriver = nil
    activePursuitVehicle = nil

    notify("~g~All suspects have complied with felony stop!")
end

-- Force compliance (taser/tackle during foot pursuit)
function ForceFootCompliance(driver)
    if DoesEntityExist(driver) and not IsPedDeadOrDying(driver, 1) then
        debugLog("ForceFootCompliance: Suspect forced to comply.")
        notify("~g~Suspect has been subdued and is surrendering!")

        -- Set proper surrender pose instead of just hands up
        SetSuspectSurrenderPose(driver)
        startInteraction(driver)

        -- Clean up blip
        if trafficBlip and DoesBlipExist(trafficBlip) then
            RemoveBlip(trafficBlip)
            trafficBlip = nil
        end

        -- Reset pursuit state
        isBusy = false
        isTrafficStopActive = false
        activePursuitDriver = nil
        activePursuitVehicle = nil
    end
end

function HandleLastStand(driver, vehicle)
    if not DoesEntityExist(vehicle) then return end

    debugLog("HandleLastStand: Suspect vehicle too damaged, all occupants bailing!")

    -- Stop & disable vehicle
    BringVehicleToHalt(vehicle, 3.0, 1, false)
    SetVehicleEngineOn(vehicle, false, true, true)
    SetEntityAsNoLongerNeeded(vehicle)

    -- Count blown tires
    local blownTires = CountBlownTyres(vehicle)


    -- Calculate desperation fight chance
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local baseChance = 10
    local tireBonus = blownTires * 10                -- +10% per blown tire
    local engineBonus = math.max(0, (1000 - engineHealth) / 10) -- up to +100%

    local fightChance = math.min(80, baseChance + tireBonus + engineBonus)
    debugLog(("HandleLastStand: Fight chance %d%% (tires: %d, engine: %.1f)")
        :format(fightChance, blownTires, engineHealth))

    -- Loop through driver & passengers
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2
    for seat = -1, seats do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            TaskLeaveVehicle(ped, vehicle, 4160)

            CreateThread(function()
                local timeout = 5000
                while IsPedInAnyVehicle(ped, false) and timeout > 0 do
                    Wait(100)
                    timeout = timeout - 100
                end
                if timeout <= 0 then
                    EndPursuit(ped, vehicle, "Failed to exit for last stand")
                    return
                end

                -- Decide fight or flee
                if math.random(0, 100) <= fightChance then
                    -- Fight: knife attack
                    debugLog("HandleLastStand: Ped chooses to FIGHT with knife!")
                    notify("~r~A suspect is making a last stand with a knife!")

                    GiveWeaponToPed(ped, `WEAPON_KNIFE`, 1, false, true)
                    SetPedDropsWeaponsWhenDead(ped, false)

                    local target = GetNearestPolicePed(GetEntityCoords(ped), 50.0)
                    if target then
                        TaskCombatPed(ped, target, 0, 16)
                    else
                        TaskCombatPed(ped, PlayerPedId(), 0, 16) -- fallback
                    end
                else
                    -- Flee on foot
                    debugLog("HandleLastStand: Ped flees on foot after bail-out.")
                    TaskReactAndFleePed(ped, PlayerPedId())
                end
            end)
        end
    end
end



function CheckForPriorPolicePresence(suspectPed)
    debugLog("Checking for prior police presence around the suspect...")
    local suspectCoords = GetEntityCoords(suspectPed)

    -- Find the closest officer within a 300.0 unit radius
    local nearestOfficer = GetNearestPolicePed(suspectCoords, 300.0)

    -- If an officer was found, check if their lights are on
    if nearestOfficer then
        local officerVeh = GetVehiclePedIsIn(nearestOfficer, false)
        if officerVeh ~= 0 and IsVehicleSirenOn(officerVeh) then
            debugLog("-> Prior police presence DETECTED. Suspect is spooked.")
            return true -- A spooked condition is met
        end
    end

    debugLog("-> No prior police presence detected.")
    return false
end

function MakePedFlee(driver, policeVeh)
    if not DoesEntityExist(driver) or not DoesEntityExist(policeVeh) then return end

    debugLog("MakePedFlee: Initiating dynamic fleeing behavior.")
    local vehicle = GetVehiclePedIsIn(driver, false)
    if not vehicle then return end

    SetEntityAsMissionEntity(driver, true, true)
    SetEntityAsMissionEntity(vehicle, true, true)

    -- 1. Baseline recklessness and driving style setup
    local recklessness = math.random(30, 100) -- Scale of 30 (cautious) to 100 (maniac)
    local speed = 80.0 + (recklessness * 0.7)
    local drivingStyle = 512 + 2 + 4 + 8 -- Ignore lights, vehicles, traffic, and roads
    
    local ability = 0.9 - (recklessness / 300.0)      -- Higher recklessness = lower skill
    local aggression = 0.5 + (recklessness / 200.0)  -- Higher recklessness = more aggressive
    SetDriverAbility(driver, ability)
    SetDriverAggressiveness(driver, aggression)

    -- 2. Lock in core fleeing behavior
    SetPedFleeAttributes(driver, 0, true)
    SetPedConfigFlag(driver, 32, true) -- Ignore sirens/events

    -- 3. Initial Task to get them moving
    TaskVehicleDriveWander(driver, vehicle, speed, drivingStyle)

    -- 4. Background thread to manage AI escalation and safety
    CreateThread(function()
        local lastTaskTime = GetGameTimer()
        local inRamMode = false

        while DoesEntityExist(driver) and isTrafficStopActive and activePursuitDriver == driver do
            Wait(3000) -- Check every 3 seconds

            if not isTrafficStopActive or not activePursuitDriver then
                debugLog("MakePedFlee AI Thread: Pursuit has ended externally. Terminating.")
                return
            end

            -- Failsafe: Bail if suspect is cuffed or has surrendered
            if (pedData[driver] and pedData[driver].isCuffed) or 
               IsEntityPlayingAnim(driver, "random@mugging3", "handsup_standing_base", 3) then
                debugLog("MakePedFlee: Suspect surrendered/cuffed, ending flee logic.")
                return
            end

            local dist = #(GetEntityCoords(driver) - GetEntityCoords(policeVeh))

            -- A. Escalation: Close Pursuit
            if dist < 20.0 and not inRamMode then
                debugLog("Flee AI: Police are close, increasing recklessness!")
                aggression = math.min(1.0, aggression + 0.1)
                SetDriverAggressiveness(driver, aggression)
                TaskVehicleDriveWander(driver, vehicle, speed + 20.0, drivingStyle + 1073741824) -- Add ignore all avoidance
                lastTaskTime = GetGameTimer()
            end

            -- B. Escalation: Ram Mode Chance
            if not inRamMode and dist < 15.0 and recklessness > 85 and math.random(1, 4) == 1 then
                debugLog("Flee AI: Suspect has snapped! Entering RAM MODE.")
                notify("~r~Suspect is attempting to ram your vehicle!")
                inRamMode = true
                SetDriverAbility(driver, 0.5) -- Lower skill, more direct
                SetDriverAggressiveness(driver, 1.0)
                TaskVehicleChase(driver, policeVeh)
                lastTaskTime = GetGameTimer()
            end

            -- C. Safety Fallback: Re-task if stuck or idle for too long
            if GetGameTimer() - lastTaskTime > 10000 and not inRamMode then
                 debugLog("Flee AI: Safety fallback, re-tasking wander to prevent freeze.")
                 TaskVehicleDriveWander(driver, vehicle, speed, drivingStyle)
                 lastTaskTime = GetGameTimer()
            end
        end
    end)
end

function EndFootPursuit(driver, reason)
    debugLog(string.format("EndFootPursuit called. Reason: %s", reason))

    if reason == "surrendered" then
        if DoesEntityExist(driver) and not IsPedDeadOrDying(driver, 1) then
            notify("~g~Suspect is surrendering on foot!")
            -- Use proper surrender pose instead of hands up
            SetSuspectSurrenderPose(driver)
            startInteraction(driver)
        end
    elseif reason == "escaped" then
        notify("~y~Suspect has escaped!")
        if DoesEntityExist(driver) then
            CleanupSurrenderThread(driver) -- Clean up any surrender threads
            SetEntityAsNoLongerNeeded(driver)
        end
    end

    if trafficBlip and DoesBlipExist(trafficBlip) then
        RemoveBlip(trafficBlip)
        trafficBlip = nil
    end

    isBusy = false
    isTrafficStopActive = false
    activePursuitDriver = nil
    activePursuitVehicle = nil
end

function StartFootPursuit(driver, vehicle)
    notify("~r~Suspect is bailing out on foot!")
    debugLog("Transitioning from vehicle to foot pursuit.")

    -- Make sure nothing is frozen before bailout
    FreezeEntityPosition(driver, false)
    CleanupSurrenderThread(driver) -- Clean up any existing surrender animations
    
    if DoesEntityExist(vehicle) then
        FreezeEntityPosition(vehicle, false)
    end

    BringVehicleToHalt(vehicle, 3.0, 1, false)
    SetVehicleEngineOn(vehicle, false, true, true)
    SetEntityAsNoLongerNeeded(vehicle)
    TaskLeaveVehicle(driver, vehicle, 4160)

    local timeout = 5000
    while IsPedInAnyVehicle(driver, false) and timeout > 0 do
        Wait(100)
        timeout = timeout - 100
    end
    if timeout <= 0 then
        EndPursuit(driver, vehicle, "Failed to exit vehicle")
        return
    end

    TaskReactAndFleePed(driver, PlayerPedId())

    if trafficBlip and DoesBlipExist(trafficBlip) then
        RemoveBlip(trafficBlip)
    end
    trafficBlip = AddBlipForEntity(driver)
    SetBlipSprite(trafficBlip, 1)
    SetBlipColour(trafficBlip, 1)
    SetBlipAsShortRange(trafficBlip, true)
    SetBlipFlashes(trafficBlip, true)

    -- Compliance detection thread (runs only during foot pursuit)
    CreateThread(function()
        while isTrafficStopActive and DoesEntityExist(driver) and not IsPedDeadOrDying(driver, 1) do
            Wait(200)

            -- TASER check
            if IsPedBeingStunned(driver, 0) then
                ForceFootCompliance(driver)
                return
            end

            -- TACKLE check (ragdoll + close to player)
            if IsPedRagdoll(driver) then
                local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(driver))
                if dist < 2.5 then
                    ForceFootCompliance(driver)
                    return
                end
            end
        end
    end)

    -- Timer thread for foot pursuit duration
    CreateThread(function()
        local footChaseEndTime = GetGameTimer() +
            math.random(Config.TrafficStop.footPursuitDuration.min, Config.TrafficStop.footPursuitDuration.max) * 1000

        while isTrafficStopActive and DoesEntityExist(driver) and not IsPedDeadOrDying(driver, 1) do
            Wait(1000)

            local playerCoords = GetEntityCoords(PlayerPedId())
            local suspectCoords = GetEntityCoords(driver)

            if #(playerCoords - suspectCoords) > Config.TrafficStop.footGetAwayDistance then
                EndFootPursuit(driver, "escaped")
                break
            end

            if GetGameTimer() > footChaseEndTime then
                EndFootPursuit(driver, "surrendered")
                break
            end
        end
    end)
end

function CancelPursuit(driver, vehicle, reason)
    debugLog(string.format("CancelPursuit called. Reason: %s", reason))
    notify("~y~Pursuit has been canceled: " .. reason)

    if DoesEntityExist(driver) and not IsPedDeadOrDying(driver, 1) then
        -- Clean up any surrender animations
        CleanupSurrenderThread(driver)
        -- Release the ped back to normal AI
        ClearPedTasks(driver)
        SetBlockingOfNonTemporaryEvents(driver, false)
        SetPedFleeAttributes(driver, 0, false)
        FreezeEntityPosition(driver, false)
        -- Tell them to drive away normally
        if DoesEntityExist(vehicle) and IsPedInVehicle(driver, vehicle, false) then
            -- Fully restore vehicle functionality
            SetVehicleEngineHealth(vehicle, 1000.0) -- Restore engine health
            SetVehicleUndriveable(vehicle, false) -- Make driveable
            FreezeEntityPosition(vehicle, false) -- Unfreeze vehicle when canceling
            SetVehicleEngineOn(vehicle, true, false, false) -- Allow engine to start
            TaskVehicleDriveWander(driver, vehicle, 25.0, 786603)
        end
    end
ClearPulledOverVehicleState(vehicle)

    -- Clean up blip
    if trafficBlip and DoesBlipExist(trafficBlip) then
        RemoveBlip(trafficBlip)
        trafficBlip = nil
    end

    -- Reset all pursuit state flags
    isBusy = false
    isTrafficStopActive = false
    activePursuitDriver = nil
    activePursuitVehicle = nil
    pulledOverVehicle = nil -- Clear pulled over vehicle reference
end

function EndPursuit(driver, vehicle, reason)
    debugLog(string.format("EndPursuit: Called to end pursuit. Reason: %s", reason or "Unknown"))

    -- Stop pursuit checker thread
    if pursuitCheckerThread then
        TerminateThread(pursuitCheckerThread)
        pursuitCheckerThread = nil
    end

    if DoesEntityExist(driver) then
        if not IsPedDeadOrDying(driver, 1) then
            -- Suspect alive -> Surrender
            notify("~g~Suspect is giving up!")
            ClearPedTasksImmediately(driver)
            SetBlockingOfNonTemporaryEvents(driver, false)
            if DoesEntityExist(vehicle) then
                BringVehicleToHalt(vehicle, 5.0, 1, false)
            end
            Wait(1000)
            SetSuspectSurrenderPose(driver)
            startInteraction(driver)
        else
            -- Suspect dead
            notify("~r~Suspect is deceased.")
            debugLog("EndPursuit: Suspect is dead.")
            CleanupSurrenderThread(driver)

            if DoesEntityExist(vehicle) then
                SetVehicleEngineOn(vehicle, false, true, true)
            end

            -- ✅ Clear pulled over vehicle since suspect is gone
            ClearPulledOverVehicleState(vehicle)
        end
    end

    -- Clean up pursuit blip
    if trafficBlip and DoesBlipExist(trafficBlip) then
        RemoveBlip(trafficBlip)
        trafficBlip = nil
    end

    debugLog("Setting Default Flags")
    isBusy = false
    isTrafficStopActive = false
    activePursuitDriver = nil
    activePursuitVehicle = nil
    pursuitStuckCount = 0
    debugLog("Pursuit cleanup complete.")
end

function IsPedInActivePursuit(ped)
    return activePursuitDriver == ped or 
           (activePursuitVehicle and DoesEntityExist(activePursuitVehicle) and 
            IsPedInVehicle(ped, activePursuitVehicle, false))
end


function HandlePursuitConclusion(driver, vehicle)
    debugLog("Handling pursuit conclusion...")
    if math.random(1, Config.TrafficStop.footBailChance) == 1 then
        StartFootPursuit(driver, vehicle)
    else
        EndPursuit(driver, vehicle, "Surrendered")
    end
end

function HandleFleeingSuspect(vehicle, driver)
    notify("~r~Suspect is fleeing!")
    TriggerDispatchAlert('SUSPECT_FLEEING', GetEntityCoords(vehicle))

    -- CRITICAL: Stop compliance monitoring immediately
    debugLog("HandleFleeingSuspect: Stopping compliance monitoring for fleeing suspect")
    
    -- Restore vehicle functionality for fleeing
    SetVehicleEngineHealth(vehicle, 1000.0)
    SetVehicleUndriveable(vehicle, false)
    FreezeEntityPosition(vehicle, false)
    SetVehicleEngineOn(vehicle, true, false, false)

    -- Prevent AI from reacting to sirens/events
    SetBlockingOfNonTemporaryEvents(driver, true)

    -- Set global variables for pursuit tracking
    activePursuitDriver = driver
    activePursuitVehicle = vehicle
    isTrafficStopActive = true
    pursuitStuckCount = 0

    -- Clear pulled over vehicle state since they're now fleeing
    pulledOverVehicle = nil

    debugLog('Calling MakePedFlee')
    -- Call MakePedFlee to handle fleeing behavior
    local playerPed = PlayerPedId()
    local policeVeh = GetVehiclePedIsIn(playerPed, false)
    MakePedFlee(driver, policeVeh)

    -- Create a tracking blip for the pursuit
    local blipData = deepcopy(Config.Blips.trafficTracker)
    blipData.isTracker = 'trafficBlip'
    trafficBlip = CreateBlip(vehicle, blipData)

    -- Start a new thread to manage the pursuit's end conditions
    pursuitCheckerThread = CreateThread(function()
        local pursuitTime = GetGameTimer() +
                                math.random(
                                    Config.TrafficStop.pursuitDuration.min,
                                    Config.TrafficStop.pursuitDuration.max) *
                                1000
        local stuckTimer = 0
        local lightsOffStart = nil
        local lastVehiclePosition = GetEntityCoords(vehicle)

        while isTrafficStopActive and DoesEntityExist(driver) and DoesEntityExist(vehicle) do
            Wait(1000) -- Check every second

            -- Check if police lights are off
            if not IsVehicleSirenOn(policeVeh) and not IsVehicleSirenSoundOn(policeVeh) then
                if not lightsOffStart then
                    lightsOffStart = GetGameTimer()
                    debugLog("Pursuit: Police lights OFF detected, starting cancel timer...")
                elseif GetGameTimer() - lightsOffStart > 20000 then
                    debugLog("Pursuit: Lights off for 20s, ending pursuit.")
                    CancelPursuit(driver, vehicle, "Police lights off")
                    return
                end
            else
                -- reset timer if lights come back on
                lightsOffStart = nil
            end

            -- Check for immediate end conditions
            if IsPedDeadOrDying(driver, 1) then
                debugLog("Pursuit ending: Driver died.")
                EndPursuit(driver, vehicle, "Driver died")
                break
            end

local pitDetected, officerPed = CheckForPITManeuver(vehicle, driver)
if pitDetected then
    debugLog("Pursuit: PIT maneuver detected, ending pursuit.")
    HandlePITManeuver(vehicle, driver, officerPed)
    break
end

            -- Check for felony stop conditions
            if Config.TrafficStop.allowFelonyStopInPursuit and CheckFelonyBox(vehicle) then
                debugLog("Pursuit: Suspect boxed in by police. Initiating felony stop sequence.")

                -- Delay to simulate suspect revving/panicking before compliance
                local delay = math.random(Config.TrafficStop.felonyStopDelay.min, Config.TrafficStop.felonyStopDelay.max)
                TaskVehicleTempAction(driver, vehicle, 27, delay) -- rev engine/accelerate in place
                Wait(delay)

                -- Force felony stop compliance sequence
                HandleFelonyStop(driver, vehicle)
                break
            end

            if not IsPedInAnyVehicle(driver, false) then
                -- This can happen if they crash and fall out. Treat it as a foot chase.
                debugLog("Pursuit ending: Driver exited vehicle unexpectedly.")
                StartFootPursuit(driver, vehicle)
                break
            end

            -- Check for conditions that lead to a conclusion (surrender or bail)
            local blownTireCount = 0
            for i = 0, GetVehicleNumberOfWheels(vehicle) - 1 do
                if IsVehicleTyreBurst(vehicle, i, false) then
                    blownTireCount = blownTireCount + 1
                end
            end

            if blownTireCount >= 3 or GetVehicleEngineHealth(vehicle) < Config.TrafficStop.lastStandDamage then
                debugLog("Pursuit: Vehicle too damaged, suspect going last stand mode.")
                HandleLastStand(driver, vehicle)
                break
            end

            -- Check if the vehicle is stuck
            if GetEntitySpeed(vehicle) < 1.0 and
                #(GetEntityCoords(vehicle) - lastVehiclePosition) < 2.0 then
                stuckTimer = stuckTimer + 1
            else
                stuckTimer = 0
                pursuitStuckCount = 0 -- Reset if moving freely
            end

            if stuckTimer >= 5 then -- Stuck for 5 seconds
                pursuitStuckCount = pursuitStuckCount + 1
                stuckTimer = 0 -- Reset timer for next check

                if pursuitStuckCount >= 2 then
                    debugLog("Pursuit conclusion triggered due to being stuck.")
                    HandlePursuitConclusion(driver, vehicle)
                    break
                else
                    debugLog("Safety thread: Vehicle appears stuck, re-tasking.")
                    TaskVehicleMissionPedTarget(
                        driver,
                        vehicle,
                        PlayerPedId(), -- police target
                        6,             -- flee
                        GetEntitySpeed(vehicle) + 40.0, -- push them faster
                        1074528293,    -- driving style = reckless/ignores
                        10.0,
                        -1.0,
                        true
                    )
                end
            end
            lastVehiclePosition = GetEntityCoords(vehicle)
        end
        pursuitCheckerThread = nil -- Clear the thread variable once the loop is done
    end)
end

-- =============================================================================
-- || Handle Suspect Compliance                                               ||
-- =============================================================================
function HandleComplyingSuspect(vehicle, driver)
    if not (DoesEntityExist(vehicle) and DoesEntityExist(driver)) then
        debugLog("HandleComplyingSuspect: Vehicle or driver does not exist.")
        return
    end

    notify("~y~Vehicle is pulling over...")
    debugLog("HandleComplyingSuspect: Suspect is complying with stop request.")

    -- Clear active driving
    ClearPedTasksImmediately(driver)
    SetPedIntoVehicle(driver, vehicle, -1)

    -- Find roadside
    local pullOverPos = GetOffsetFromEntityInWorldCoords(vehicle, 4.5, 30.0, 0.0)
    local found, roadsidePoint = GetClosestVehicleNode(pullOverPos.x, pullOverPos.y, pullOverPos.z, 1, 3.0, 0)
    if not found then
        roadsidePoint = GetEntityCoords(vehicle) + GetEntityForwardVector(vehicle) * 25.0
        debugLog("HandleComplyingSuspect: No roadside node found, using forward offset.")
    else
        debugLog(("HandleComplyingSuspect: Roadside node found at %.2f %.2f %.2f")
            :format(roadsidePoint.x, roadsidePoint.y, roadsidePoint.z))
    end

    -- Ask AI to drive to roadside
    TaskVehicleDriveToCoord(driver, vehicle, roadsidePoint.x, roadsidePoint.y, roadsidePoint.z,
        15.0, 1.0, GetEntityModel(vehicle), 786603, 5.0)

    CreateThread(function()
        local timeout = 15000
        while timeout > 0 and DoesEntityExist(vehicle) and GetEntitySpeed(vehicle) > 0.1 do
            Wait(100)
            timeout = timeout - 100
        end

        if timeout <= 0 then
            debugLog("HandleComplyingSuspect: Timed out while trying to pull over, treating as pursuit.")
            notify("~r~Driver is failing to stop! Treating as a pursuit.")
            HandleFleeingSuspect(vehicle, driver)
            return
        end

        -- Forcefully halt
        TaskVehicleTempAction(driver, vehicle, 27, 3000)
        Wait(1500)

-- Lock down vehicle COMPLETELY
SetVehicleForwardSpeed(vehicle, 0.0)
SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
FreezeEntityPosition(vehicle, true)

-- Disable engine directly without the problematic thread
SetVehicleEngineOn(vehicle, false, true, true)
SetVehicleUndriveable(vehicle, true)
SetVehicleEngineHealth(vehicle, 0.0)
SetVehicleBodyHealth(vehicle, 999.0)

debugLog("HandleComplyingSuspect: Vehicle completely disabled and frozen.")

        -- Driver compliance
        ClearPedTasksImmediately(driver)
        SetPedIntoVehicle(driver, vehicle, -1)
SetBlockingOfNonTemporaryEvents(driver, true)
-- DO NOT freeze the ped, let them stay interactable
if not IsPedInVehicle(driver, vehicle, false) then
    SetPedIntoVehicle(driver, vehicle, -1)
end
TaskLookAtEntity(driver, PlayerPedId(), -1, 2048, 3)

        pulledOverVehicle = vehicle
        isBusy = false
        notify("~g~Vehicle has pulled over and suspects are compliant.")

        -- Start monitoring compliance
        StartComplianceMonitor(vehicle, driver)

        -- Start chance of secondary flee
        StartSecondaryFleeCheck(vehicle, driver)
    end)
end
 
-- =============================================================================
-- || Compliance Monitor (keep them compliant)                                ||
-- =============================================================================
-- Compliance monitor keeps suspects compliant during a traffic stop
function StartComplianceMonitor(vehicle, driver)
    CreateThread(function()
        while isTrafficStopActive
          and pulledOverVehicle == vehicle
          and DoesEntityExist(vehicle)
          and DoesEntityExist(driver) do

            -- CRITICAL: Stop monitoring if pursuit has started
            if activePursuitDriver == driver or activePursuitVehicle == vehicle then
                debugLog("Compliance monitor: Pursuit started, ending compliance monitoring")
                break
            end

            -- CRITICAL: Completely disable engine from starting
            SetVehicleEngineOn(vehicle, false, true, true)
            SetVehicleUndriveable(vehicle, true)
            SetVehicleEngineHealth(vehicle, 0.0) -- Prevent engine from working
            
            -- Additional engine prevention
            if GetIsVehicleEngineRunning(vehicle) then
                SetVehicleEngineOn(vehicle, false, true, true)
                debugLog("Compliance monitor: Forced engine off - suspect was trying to rev.")
            end

            -- Prevent AI driver from doing anything
            if not IsPedAPlayer(driver) then
                SetBlockingOfNonTemporaryEvents(driver, true)
                SetPedKeepTask(driver, true)
            end

            -- Get ped state data
            local pedData = pedData[driver] or {}
            local wasRemoved = pedData.removedFromVehicle or false
            local isFollowing = pedData.isFollowing or false
            local isCuffed = pedData.isCuffed or false
            local isEscorted = pedData.isEscorted or false
            local isTargeted = (targetedPed == driver) -- Player is currently interacting with this ped

            debugLog(string.format("Compliance check - wasRemoved: %s, isFollowing: %s, isCuffed: %s, isTargeted: %s", 
                tostring(wasRemoved), tostring(isFollowing), tostring(isCuffed), tostring(isTargeted)))

            -- Skip compliance enforcement if ped is in a legitimate activity
            if isFollowing or isCuffed or isEscorted then
                debugLog("Compliance monitor: Skipping enforcement - ped is following/cuffed/escorted")
                Wait(500)
                goto continue
            end

            -- CRITICAL: If player is actively interacting with this ped, respect that interaction
            if isTargeted and (isMenuOpen or isQuestioning) then
                debugLog("Compliance monitor: Player interacting with ped, respecting current state")
                -- Don't force them anywhere, let the interaction continue
                Wait(500)
                goto continue
            end

            -- MAIN COMPLIANCE LOGIC: Once removed from vehicle, they stay out
            if wasRemoved then
                debugLog("Compliance monitor: Ped was removed from vehicle, maintaining on-foot compliance")
                -- They should be on foot in surrender pose
                if not IsEntityPlayingAnim(driver, "random@mugging3", "handsup_standing_base", 3) then
                    SetSuspectSurrenderPose(driver)
                    debugLog("Compliance monitor: Reset surrender pose on foot.")
                end
            else
                debugLog("Compliance monitor: Ped should be in vehicle")
                -- They should be in the vehicle ONLY if not removed
                if not IsPedInVehicle(driver, vehicle, false) then
                    TaskWarpPedIntoVehicle(driver, vehicle, -1)
                    debugLog("Compliance monitor: Returned driver to vehicle seat.")
                end
                TaskLookAtEntity(driver, PlayerPedId(), -1, 2048, 3)
            end

            ::continue::
            Wait(500) -- check twice per second
        end

        debugLog("Compliance monitor ended.")
    end)
end


function DisableVehicleCompletely(vehicle)
    if not DoesEntityExist(vehicle) then return end
    local playerPed = PlayerPedId()
local playerVehicle = GetVehiclePedIsIn(playerPed, false)

-- Don't disable player's vehicle
if vehicle == playerVehicle then
    debugLog("DisableVehicleCompletely: Skipping player vehicle")
    return
end
    -- Multiple layers of engine disabling
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleUndriveable(vehicle, true)
    SetVehicleEngineHealth(vehicle, 0.0)
    SetVehicleBodyHealth(vehicle, 999.0) -- Keep body intact but engine dead
    
    -- Disable specific controls ONLY for the pulled over vehicle
    CreateThread(function()
        while pulledOverVehicle == vehicle and DoesEntityExist(vehicle) and isTrafficStopActive do
            -- Only affect the specific pulled over vehicle
            local driver = GetPedInVehicleSeat(vehicle, -1)
            if DoesEntityExist(driver) and not IsPedAPlayer(driver) then
                -- Disable controls for NPC drivers only
                local playerPed = PlayerPedId()
                if IsPedInVehicle(playerPed, vehicle, false) then
                    -- If player is somehow in the suspect vehicle, don't disable their controls
                    goto continue
                end
                
                DisableControlAction(0, 71, true) -- W key (accelerate)
                DisableControlAction(0, 72, true) -- S key (reverse)
                DisableControlAction(0, 85, true) -- Q key (radio wheel)
                
                -- Force engine off if it somehow starts
                if GetIsVehicleEngineRunning(vehicle) then
                    SetVehicleEngineOn(vehicle, false, true, true)
                end
            end
            
            ::continue::
            Wait(0) -- Run every frame for tight control
        end
    end)
    
    debugLog("Vehicle completely disabled - engine cannot start")
end



-- =============================================================================
-- || Secondary Flee Logic                                                    ||
-- =============================================================================
function StartSecondaryFleeCheck(vehicle, driver)
    CreateThread(function()
        Wait(10000) -- give them 10s before checking

        if not (isTrafficStopActive and pulledOverVehicle == vehicle) then
            debugLog("Secondary flee canceled (stop not active).")
            return
        end

        if math.random(1, Config.TrafficStop.secondaryFleeChance) == 1 then
            -- Decide flee type: 50/50 vehicle vs foot
            local fleeType = (math.random(1, 2) == 1) and "vehicle" or "foot"
            debugLog(("StartSecondaryFleeCheck: Suspect initiating secondary flee (%s)!"):format(fleeType))
            notify("~r~Suspect is taking off again!")

            -- Close menus if open
            if lib and lib.hideContext then lib.hideContext() end

            -- Cleanup
            CleanupSurrenderThread(driver)
            FreezeEntityPosition(driver, false)
            FreezeEntityPosition(vehicle, false)
            ClearPedTasks(driver)

            if fleeType == "vehicle" then
                -- Vehicle flee
                SetVehicleEngineOn(vehicle, true, false, false)
                HandleFleeingSuspect(vehicle, driver)
            else
                -- Foot flee
                StartFootPursuit(driver, vehicle)
            end
        else
            debugLog("StartSecondaryFleeCheck: Suspect remained compliant, no secondary flee.")
        end
    end)
end


function StartTrafficStop(vehicle)
    if isBusy or isTrafficStopActive then return end
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if not DoesEntityExist(driver) or IsPedAPlayer(driver) then return end

    isBusy = true
    isTrafficStopActive = true
    debugLog("StartTrafficStop: Initiating a new traffic stop.")

    local wasSpooked = CheckForPriorPolicePresence(driver)

    -- Generate or fallback ped data
    local driverData = generateRandomPedData(driver, wasSpooked) or {
        name = "Unknown Suspect",
        age = math.random(18, 70),
        crimeLevel = 0,
        crimes = {},
        warrants = false,
        warrantDetails = {},
        isDrunk = false,
        isOnDrugs = false,
        hasIllegalItems = false,
        illegalItemFound = nil,
        isCuffed = false,
        isEscorted = false,
        inVehicle = IsPedInAnyVehicle(driver, false),
        isFollowing = false,
        hasID = true,
        idVerified = false,
        idAttempted = false,
        checksCompleted = {
            breathalyze = false,
            drugtest = false,
            search = false,
            fingerprint = false
        }
    }

    if not driverData.crimeLevel then driverData.crimeLevel = 0 end
    if not driverData.crimes then driverData.crimes = {} end

    -- Sync ped data across server
    updateSyncedPedState(driver, driverData)

    -- Sync vehicle ANPR data
    TriggerServerEvent("police:requestVehicleData", VehToNet(vehicle))

    -- ✅ NEW: mark this vehicle as pulled over for all PD
    local vehNetId = VehToNet(vehicle)
    TriggerServerEvent("police:server:setPulledOverVehicle", vehNetId, true)

    notify("~b~Signaling vehicle to pull over...")

    local decisionTime = math.random(Config.TrafficStop.decisionTime.min, Config.TrafficStop.decisionTime.max)
    Wait(decisionTime)

    if not DoesEntityExist(driver) or not DoesEntityExist(vehicle) then
        isBusy, isTrafficStopActive = false, false
        return
    end

    local fleeChance = math.max(2, 10 - math.floor(driverData.crimeLevel / 20))
    debugLog(string.format("Suspect crimeLevel is %d. Flee chance is 1 in %d.", driverData.crimeLevel, fleeChance))

    if #driverData.crimes > 0 then
        for i, crime in ipairs(driverData.crimes) do
            debugLog(string.format(" -> Offense #%d: %s", i, crime))
        end
    else
        debugLog(" -> No specific offenses found.")
    end

    if math.random(1, fleeChance) == 1 then
        debugLog("StartTrafficStop: Suspect will flee.")
        HandleFleeingSuspect(vehicle, driver)
    else
        debugLog("StartTrafficStop: Suspect will comply and pull over.")
        HandleComplyingSuspect(vehicle, driver)
    end
end


-- Clean up function to call when ped is cuffed or script unloads
function CleanupAllSurrenderThreads()
    for p, data in pairs(pedData) do
        if data.surrenderActive then
            data.surrenderActive = false
            if DoesEntityExist(p) then
                FreezeEntityPosition(p, false)
                ClearPedTasks(p)
            end
        end
    end
end

-- Call this when a ped gets cuffed to stop surrender animation
function OnPedCuffed(ped)
    if pedData[ped] then
        pedData[ped].isCuffed = true
        CleanupSurrenderThread(ped) -- this unfreezes via loop exit
    end
end

-- Keep local cache in sync
RegisterNetEvent('police:client:updatePulledOverVehicle', function(vehNetId, isPulledOver)
    if isPulledOver then
        pulledOverVehicle = NetworkGetEntityFromNetworkId(vehNetId)
    elseif pulledOverVehicle and NetworkGetNetworkIdFromEntity(pulledOverVehicle) == vehNetId then
        pulledOverVehicle = nil
    end
end)

RegisterNetEvent('police:client:initPulledOverVehicles', function(serverPulledOver)
    for vehNetId, officerSrc in pairs(serverPulledOver) do
        pulledOverVehicle = NetworkGetEntityFromNetworkId(vehNetId)
    end
end)
RegisterCommand('backup', function(source, args, rawCommand)
    if not isPlayerPolice() then return end
    
    local reason = table.concat(args, ' ') or 'Officer requesting immediate backup'
    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    
    -- Get location
    local streetName, crossingRoad = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetName)
    local crossing = GetStreetNameFromHashKey(crossingRoad)
    local location = crossing and crossing ~= "" and (street .. " / " .. crossing) or street
    
    TriggerServerEvent('police:server:requestBackup', {
        reason = reason,
        location = location,
        coords = coords
    })
    
    notify("Backup request sent: " .. reason, "warning")
end, false)

