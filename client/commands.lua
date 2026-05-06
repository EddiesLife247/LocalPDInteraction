RegisterCommand('droplocal', function()
    -- Check if the player is a police officer and on duty
    if not isPlayerPolice() then
        notify("~r~You are not authorized to use this command.")
        return
    end

    -- Check if there is a targeted ped and if they are currently being escorted
    if not targetedPed or not pedData[targetedPed] or
        not pedData[targetedPed].isEscorted then
        notify("You are not escorting anyone.")
        return
    end

    local pedToDrop = targetedPed
    local pedDataToDrop = pedData[pedToDrop]

    -- Update the ped's state to not be escorted
    pedDataToDrop.isEscorted = false
    updateSyncedPedState(pedToDrop, {isEscorted = false})

    -- Detach the ped from the player
    DetachEntity(pedToDrop, true, false)
    ClearPedTasks(pedToDrop)

    -- We can make them stand still for a moment before they walk away
    TaskStandStill(pedToDrop, 5000)

    -- Use the forceClear parameter to fully release and forget the ped
    closeInteractionMenu(true)
    notify(pedDataToDrop.name .. " has been released.")

end, false)

RegisterCommand('togglestate', function()
    if not isPlayerPolice() then
        notify("~r~You must be on-duty police to use this command.")
        return
    end

    isPoliceActive = not isPoliceActive

    if isPoliceActive then
        notify("~g~You are now ACTIVE and will receive callouts.")
    else
        notify("~y~You are now INACTIVE and will not receive callouts.")
        -- Forcibly clear any current callout blips from the mapW
        ForceClearCallout()
    end
end, false)

RegisterCommand('cancelcallout', function()
    if isPlayerPolice() then
        TriggerServerEvent('police:clearCalloutServer', 'prank')
    else
        notify("~r~You are not authorized to use this command.")
    end
end, false)

RegisterCommand('checkvehiclereg', function(source, args)
    if not isPlayerPolice() then
        notify("~r~You are not authorized to use this command.")
        return
    end

    local plateInput = args[1]
    if not plateInput then
        notify("~y~Usage:~w~ /checkvehiclereg [plate]")
        return
    end

    local foundVehicle = nil
    plateInput = string.upper(plateInput):gsub("%s+", "") -- Convert to uppercase and remove spaces

    local vehicles = GetGamePool('CVehicle')
    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local currentPlate =
                string.upper(GetVehicleNumberPlateText(vehicle)):gsub("%s+", "")
            if currentPlate == plateInput then
                if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) <
                    150.0 then
                    foundVehicle = vehicle
                    break
                end
            end
        end
    end

    if foundVehicle then
        local data = generateRandomVehicleData(foundVehicle)
        notify("~b~[PNC]~w~ Found vehicle with registration: " .. data.plate)
        Wait(2000)
        notify(string.format("~b~[PNC]~w~ Vehicle: %s %s.", data.color,
                             data.make))
        notify(string.format("~b~[PNC]~w~ Registered Owner: %s.", data.owner))
        if data.hasTax then
            notify("~b~[PNC]~g~ Road Tax: VALID")
        else
            notify("~b~[PNC]~r~ Road Tax: EXPIRED")
        end
        if data.hasInsurance then
            notify("~b~[PNC]~g~ Insurance: SHOWING INSURED")
        else
            notify("~b~[PNC]~r~ Insurance: NO POLICY FOUND")
        end
        if data.isStolen then
            notify("~b~[PNC]~r~ MARKER: VEHICLE REPORTED STOLEN")
        end
    else
        notify("~b~[PNC]~y~ No vehicle with that registration found nearby.")
    end
end, false)

RegisterCommand("forcepursuit", function()
    local playerPed = PlayerPedId()
    local playerVeh = GetVehiclePedIsIn(playerPed, false)

    if playerVeh == 0 then
        lib.notify({
            title = "Force Pursuit",
            description = "You must be in a vehicle with sirens on.",
            type = "error"
        })
        return
    end

    -- Use raycast to find vehicle ahead
    local targetVeh = GetVehicleAhead(playerVeh)
    if not targetVeh then
        lib.notify({
            title = "Force Pursuit",
            description = "No NPC vehicle ahead.",
            type = "error"
        })
        return
    end

    local driver = GetPedInVehicleSeat(targetVeh, -1)
    if not DoesEntityExist(driver) or IsPedAPlayer(driver) then
        lib.notify({
            title = "Force Pursuit",
            description = "No valid NPC driver found.",
            type = "error"
        })
        return
    end

    notify("~r~Forced pursuit started! Suspect fleeing for 20 seconds.")

    -- Force NPC to flee
    MakePedFlee(driver, playerVeh)

    -- End pursuit automatically after 20 seconds
    CreateThread(function()
        Wait(20000) -- 20 seconds
        if DoesEntityExist(driver) and DoesEntityExist(targetVeh) then
            EndPursuit(driver, targetVeh, "Forced 20-second pursuit ended")
        end
    end)
end, false)
