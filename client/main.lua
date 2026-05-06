--[[ client/main.lua ]]
-- This file initializes shared variables and runs the main loops.

-- Shared Variables
isMenuOpen, isQuestioning, isDispatchMenuOpen, isJailing, isBusy = false, false, false, false, false
isPoliceActive = true
targetedPed, PlayerJob, calloutBlip, trafficBlip, activeCalloutPedEntity = nil, nil, nil, nil, nil
pedData, vehicleData = {}, {}
pulledOverVehicle = nil
currentActionIndex = 1
menuNavCooldown = 0
isTrafficStopActive = false
isImpounding = false

-- Pursuit variables
activePursuitDriver, activePursuitVehicle = nil, nil
pursuitCheckerThread = nil
pursuitStuckCount = 0

-- Define menu action tables that will be populated in functions.lua
defaultActions, arrestedKeys, arrestedActions, specialQuestionActions, dispatchKeys, dispatchActions = {}, {}, {}, {}, {}, {}

-- QBCore Integration
QBCore = exports['qb-core']:GetCoreObject()

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    PlayerJob = QBCore.Functions.GetPlayerData().job
    debugLog(string.format("Player loaded. Job is now: %s", PlayerJob.name))
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(jobInfo)
    PlayerJob = jobInfo
    debugLog(string.format("Job updated. New job is: %s", PlayerJob.name))
end)

-- Initial job check for script restarts
CreateThread(function()
    Wait(1000)
    if QBCore and not PlayerJob then
        PlayerJob = QBCore.Functions.GetPlayerData().job
        if PlayerJob and PlayerJob.name ~= 'unemployed' then
            debugLog(string.format("Initial job check successful. Job is: %s", PlayerJob.name))
        end
    end
end)