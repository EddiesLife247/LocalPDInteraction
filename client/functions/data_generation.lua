--[[ client/functions/data_generation.lua ]]

function generateRandomName(entity)
    local isMale

    -- First, check if we have a valid ped to get the gender from
    if entity and DoesEntityExist(entity) and IsEntityAPed(entity) then
        -- If yes, use the ped's actual gender
        isMale = IsPedMale(entity)
    else
        -- If not, fall back to a random gender (for generating fictional owners, etc.)
        isMale = (math.random(1, 2) == 1)
    end

    -- The rest of the function works correctly with the right isMale value
    local fname = isMale and Config.Names.maleFirstNames[math.random(#Config.Names.maleFirstNames)] or Config.Names.femaleFirstNames[math.random(#Config.Names.femaleFirstNames)]
    return fname .. " " .. Config.Names.lastNames[math.random(#Config.Names.lastNames)]
end

function generateRandomPedData(ped, wasSpooked)
    if pedData[ped] then return pedData[ped] end

    local crimeLevel = math.random(0, 50)
    local crimes = {} -- New table to store list of crimes

    local hasWarrants = (math.random(1, 20) == 1)
    if hasWarrants then
        crimeLevel = crimeLevel + 25
        table.insert(crimes, "Has Outstanding Warrants")
    end

    local isDrunk = (math.random(1, 20) == 1)
    if isDrunk then
        crimeLevel = crimeLevel + 10
        table.insert(crimes, "Public Intoxication")
    end

    local isOnDrugs = (math.random(1, 30) == 1)
    if isOnDrugs then
        crimeLevel = crimeLevel + 10
        table.insert(crimes, "Under the Influence")
    end

    local hasIllegal = (math.random(1, 15) == 1)
    if hasIllegal then
        crimeLevel = crimeLevel + 20
        table.insert(crimes, "Possession of Contraband")
    end

    if wasSpooked then
        crimeLevel = crimeLevel + 15
        table.insert(crimes, "Spooked by Police Presence")
    end

    local newData = {
        name = generateRandomName(ped),
        age = math.random(18, 70),
        warrants = hasWarrants,
        warrantDetails = hasWarrants and {Config.WarrantCharges[math.random(#Config.WarrantCharges)]} or {},
        isDrunk = isDrunk,
        isOnDrugs = isOnDrugs,
        hasIllegalItems = hasIllegal,
        illegalItemFound = hasIllegal and Config.IllegalItems[math.random(#Config.IllegalItems)] or nil,
        crimeLevel = math.min(crimeLevel, 100), -- clamp to 100
        crimes = crimes, -- Store the list of crimes
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

    local plate = GetVehicleNumberPlateText(vehicle)
    local driverData = pedData[driverPed] or generateRandomPedData(driverPed)
    local driverName = driverData.name

    local ownerName, isStolen, hasPermission
    if math.random(1, 100) <= 80 then
        ownerName, isStolen, hasPermission = driverName, false, true
    else
        ownerName = generateRandomName(driverPed)
        while ownerName == driverName do
            ownerName = generateRandomName(driverPed)
        end
        if math.random(1, 100) <= 20 then
            isStolen, hasPermission = false, true
        else
            isStolen, hasPermission = true, false
        end
    end

    local hasIllegal = (math.random(1, 8) == 1)

    local data = {
        plate = plate,
        isStolen = isStolen,
        hasPermission = hasPermission,
        hasInsurance = (math.random(1, Config.VehicleChecks.noInsuranceChance) ~= 1),
        hasTax = (math.random(1, Config.VehicleChecks.noTaxChance) ~= 1),
        owner = ownerName,
        make = Config.VehicleChecks.ukCarMakes[math.random(#Config.VehicleChecks.ukCarMakes)],
        color = Config.VehicleChecks.ukCarColors[math.random(#Config.VehicleChecks.ukCarColors)],
        hasIllegalItems = hasIllegal,
        illegalItemFound = Config.IllegalItems[math.random(#Config.IllegalItems)]
    }

    vehicleData[vehicle] = data

    -- 🚨 Feed into driver’s crime level
    if isStolen then driverData.crimeLevel = math.min(driverData.crimeLevel + 30, 100) end
    if not data.hasInsurance then driverData.crimeLevel = driverData.crimeLevel + 5 end
    if not data.hasTax then driverData.crimeLevel = driverData.crimeLevel + 5 end
    if hasIllegal then driverData.crimeLevel = math.min(driverData.crimeLevel + 15, 100) end

    return data
end
