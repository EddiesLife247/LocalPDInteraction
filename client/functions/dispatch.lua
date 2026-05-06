--[[ client/functions/dispatch.lua ]]
-- Contains all functions related to dispatch alerts and blips.

function CreateBlip(target, blipData)
    if not isPlayerPolice() then return end
    if blipData.isTracker and _G[blipData.isTracker] and DoesBlipExist(_G[blipData.isTracker]) then
        RemoveBlip(_G[blipData.isTracker])
    end

    local newBlip
    local targetType = type(target)

    if targetType == 'vector3' then
        newBlip = AddBlipForCoord(target.x, target.y, target.z)
    elseif targetType == 'number' and DoesEntityExist(target) then
        newBlip = AddBlipForEntity(target)
    else
        debugLog("CreateBlip failed: Invalid target type or entity does not exist.")
        return nil
    end

    SetBlipSprite(newBlip, blipData.sprite)
    SetBlipColour(newBlip, blipData.color)
    SetBlipScale(newBlip, blipData.scale)
    if blipData.flashes then SetBlipFlashes(newBlip, true) end
    if blipData.route then SetBlipRoute(newBlip, true) end

    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(blipData.name)
    EndTextCommandSetBlipName(newBlip)

    if blipData.duration and blipData.duration > 0 then
        CreateThread(function()
            Wait(blipData.duration * 1000)
            if DoesBlipExist(newBlip) then RemoveBlip(newBlip) end
        end)
    end
    return newBlip
end

function TriggerDispatchAlert(alertType, position)
    if not isPlayerPolice() or not isPoliceActive then return end

    debugLog(string.format("Triggering dispatch alert of type: %s", alertType))
    local alertData = Config.Dispatch.alerts[alertType]
    if not alertData then
        debugLog("-> FAILED: Invalid alert type.");
        return
    end

    local _, streetNameHash = GetStreetNameAtCoord(position.x, position.y, position.z)
    local street = GetStreetNameFromHashKey(streetNameHash)
    local dispatchInfo = {
        title = alertData.title,
        description = alertData.description,
        coords = position,
        street = street,
        blipType = alertData.blipType
    }

    if Config.Dispatch.integration == 'ps-dispatch' then
        local fullDescription = string.format("%s At/Near %s", dispatchInfo.description, dispatchInfo.street)
        local blipData = Config.Blips[dispatchInfo.blipType]
        if not blipData then
            debugLog("-> FAILED: Blip data not found in Config for blipType: " .. tostring(dispatchInfo.blipType))
            return
        end
        local alertPayload = {
            coords = dispatchInfo.coords,
            message = dispatchInfo.title,
            description = fullDescription,
            blipSprite = blipData.sprite,
            blipColour = blipData.color,
            blipScale = blipData.scale,
            blipLength = blipData.duration,
            radius = 0,
            gender = true,
            sound = "ALERT",
            recipientList = Config.PoliceJobs
        }
        exports["ps-dispatch"]:CustomAlert(alertPayload)
    elseif Config.Dispatch.integration == 'custom' then
        if not alertData.customPayload then
            debugLog("-> FAILED: 'custom' integration is enabled, but 'customPayload' is missing for alert type: " .. alertType)
            return
        end
        local payloadToSend = deepcopy(alertData.customPayload)
        local function processPayload(tbl)
            for k, v in pairs(tbl) do
                if type(v) == 'table' then
                    processPayload(v)
                elseif type(v) == 'string' then
                    if v == '%coords%' then
                        tbl[k] = position
                    else
                        v = v:gsub('%%street%%', street)
                        v = v:gsub('%%title%%', alertData.title)
                        v = v:gsub('%%description%%', alertData.description)
                        tbl[k] = v
                    end
                end
            end
        end
        processPayload(payloadToSend)
        TriggerServerEvent(Config.Dispatch.customServerEvent, payloadToSend)
    else
        TriggerServerEvent('police:broadcastDispatchAlert', dispatchInfo)
    end
end