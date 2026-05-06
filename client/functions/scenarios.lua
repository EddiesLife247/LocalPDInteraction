function startTrafficViolation(vehicle, driver, alertType)
    if trafficBlip and DoesBlipExist(trafficBlip) then
        debugLog("-> A traffic violation is already active. Ignoring new one.")
        return
    end

    debugLog(string.format("Starting new traffic violation for vehicle: %s",
                           vehicle))
    TriggerDispatchAlert(alertType, GetEntityCoords(vehicle))

    local blipData = deepcopy(Config.Blips.trafficTracker)
    blipData.isTracker = 'trafficBlip' -- Tell the function which global var to clear
    trafficBlip = CreateBlip(vehicle, blipData)

    local driverNetId = NetworkGetNetworkIdFromEntity(driver)
    pedData[driver] = pedData[driver] or {}
    pedData[driver].isTrafficViolator = true

    CreateThread(function()
        local timeout = Config.TrafficScenarios.blipDuration * 1000
        while timeout > 0 and DoesEntityExist(vehicle) and
            DoesBlipExist(trafficBlip) do
            Wait(1000)
            timeout = timeout - 1000
        end
        if DoesBlipExist(trafficBlip) then
            RemoveBlip(trafficBlip)
            trafficBlip = nil
        end
        if pedData[driver] and pedData[driver].isTrafficViolator then
            TriggerServerEvent("police:clearPedData", driverNetId)
        end
    end)
end