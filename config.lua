Config = {}
-- General Settings
Config.KeyToOpenDispatchMenu = 246 -- Y key
Config.KeyToReopenMenu = 47 -- Keyboard G

Config.InteractionDistance = 4.5
Config.PoliceJobs = {"police", "staff"}
Config.Debug = true -- Set to true for console logs, false for production.

Config.IncidentMemoryTime = 180000
Config.IllegalItemChance = 6

-- NEW: Vehicle Check Settings
Config.VehicleChecks = {
    -- Chance is 1 in X. Lower number = more common.
    stolenChance = 25,      -- 1 in 25 chance a random vehicle is stolen.
    noInsuranceChance = 15, -- 1 in 15 chance of no insurance.
    noTaxChance = 20,       -- 1 in 20 chance of no road tax.
    -- Lists for generating random owner details
    ukCarMakes = {"Ford", "Vauxhall", "Volkswagen", "BMW", "Mercedes-Benz", "Audi", "Nissan", "Toyota", "Hyundai", "Kia", "Peugeot", "Land Rover"},
    ukCarColors = {"Silver", "Black", "White", "Grey", "Blue", "Red", "Green", "Orange", "Yellow"}
}

-- Payouts & Chances
Config.JailPayout = {
    base = 500,
    perCheckBonus = 125, -- Bonus for each completed check (breathalyzer, search, etc.)
    warrantBonus = 400,
    intoxicationBonus = 200,
    drugBonus = 300,
    contrabandBonus = 350
}

Config.CrimeLevelEvents = {
    enabled = true,
    incrementOnCrash = 5,       -- Points to add for any significant vehicle collision
    incrementOnRedLight = 3,    -- Points to add for running a red light
}

Config.TrafficStop = {
    enabled = true,
    GetAwayDistance = 3000,
    pursuitDamage = 200.0,
    fleeChance = 4, -- 1 in 4 chance the suspect will flee instead of pulling over.
    fleeChanceStolen = 4,
    pursuitDuration = { min = 60, max = 450 }, -- Min/Max time in SECONDS a pursuit will last before the AI gives up.
    footBailChance = 4,
    footPursuitDuration = { min = 20, max = 80 }, -- How many seconds the foot chase will last before they surrender
    footGetAwayDistance = 150.0, -- Distance at which a suspect on foot is considered to have escaped
    secondaryFleeChance = 5,
    lastStandDamage = 250.0,
    allowFelonyStopInPursuit = true,
    felonyStopDelay = { min = 2000, max = 3000 }, -- random 2–3s delay
    decisionTime = { min = 1000, max = 4000 }, -- Time in ms suspect 'thinks' before acting
    cancelPursuitOnLightsOffTime = 20000,      -- 20 seconds with lights off to cancel a pursuit
    cancelPursuitOnDistance = 250.0,           -- Distance in meters to cancel a pursuit

}

Config.KeyToForcePursuit = 47 -- G key by default


Config.Fining = {
    officerPayout = 250, -- Fixed amount paid to the officer
    offenseFines = {
        -- ===============================================
        -- ||         PUBLIC & MINOR OFFENSES           ||
        -- ===============================================
        ['Public Intoxication'] = 90,
        ['Disorderly Conduct'] = 90,
        ['Public Nuisance'] = 120,
        ['Littering'] = 150,
        ['Jaywalking / Unsafe Road Crossing'] = 50,

        -- ===============================================
        -- ||        POSSESSION OFFENSES              ||
        -- ===============================================
        ['Possession of Illegal Substances'] = 500,
        ['Possession of Contraband'] = 350,
        ['Possession of an Unlicensed Firearm'] = 1000,
        
        -- ===============================================
        -- || VEHICLE DOCUMENTATION & DISPLAY OFFENSES  ||
        -- ===============================================
        ['No Valid MOT Certificate'] = 1000,
        ['No Valid Road Tax (VED)'] = 150,
        ['Failure to Display License Plate'] = 100,
        ['Illegally Spaced/Styled License Plate'] = 100,

        -- ===============================================
        -- ||        DRIVER BEHAVIOUR OFFENSES          ||
        -- ===============================================
        ['Speeding (Minor, <10 over)'] = 100,
        ['Speeding (Major, 10-20 over)'] = 250,
        ['Speeding (Excessive, 20+ over)'] = 500,
        ['Driving Without Due Care and Attention'] = 300,
        ['Reckless/Dangerous Driving'] = 600,
        ['Running a Red Light / Stop Sign'] = 180,
        ['Illegal U-Turn'] = 100,
        ['Failure to Yield to Emergency Vehicle'] = 250,
        ['Failure to Yield at Junction'] = 130,
        ['Driving on Pavement or Kerb'] = 100,
        ['Mobile Phone Use While Driving'] = 200,
        ['Unlawful Overtaking'] = 150,
        
        -- ===============================================
        -- ||      VEHICLE CONDITION & PARKING          ||
        -- ===============================================
        ['Illegal Parking'] = 60,
        ['Parking on Double Yellow Lines'] = 70,
        ['Causing an Obstruction'] = 100,
        ['Driving an Unroadworthy Vehicle'] = 200,
        ['Defective Lights/Indicators'] = 50,
        ['Excessively Loud Exhaust'] = 80,
    }
}

-- UK Breathalyzer Settings
Config.Breathalyzer = {
    ukLimit = 35, -- Micrograms per 100ml of breath (England/Wales limit)
    passMessage = "BAC Result: ~g~%s mg. You are under the legal limit.",
    failMessage = "BAC Result: ~r~%s mg. You are OVER the legal limit.",
    drunkReadingRange = {min = 36, max = 240},
    soberReadingRange = {min = 0, max = 35}
}

-- NEW: Scenarios for resisting arrest.
Config.Scenarios = {
    enabled = true,
    -- Chance is 1 in X. A lower number means more frequent events.
    pullKnifeChance = 20, -- 1 in 20 chance the suspect will pull a knife.
    attemptEscapeChance = 15, -- 1 in 15 chance the suspect will try to run.
    chargePlayerChance = 30,
    warrantModifier = 10 -- Add this line. The amount to increase the chance by.
}

-- Add this entire new table to config.lua
Config.Blips = {
    -- Style for the main callout tracking blip
    calloutTracker = {
        name = "Callout Location", -- This will be overridden by the specific callout name
        sprite = 1,
        color = 1,
        scale = 1.2,
        route = true,  -- Show route on GPS
        flashes = true,
        duration = 45, -- Duration in SECONDS

    },
    -- Style for a traffic violation tracker
    trafficTracker = {
        name = "Traffic Violation",
        sprite = 1,
        color = 1,
        scale = 1.0,
        route = false,
        flashes = true,

    },
    -- Style for a temporary dispatch alert (e.g., shots fired)
    dispatchAlert = {
        name = "Dispatch Alert", -- This will be overridden by the specific alert title
        sprite = 1,
        color = 1,
        scale = 1.5,
        duration = 45, -- Duration in SECONDS
        route = false,
        flashes = true,
    }
}

-- NEW: Callout system.
Config.Callouts = {
    enabled = true,
    playSound = true, -- NEW: Play a dispatch tone when a new callout is received.
    -- NEW SETTINGS FOR RANDOM CALLOUTS
    randomCalloutsEnabled = true,
    randomCalloutInterval = {min = 2, max = 15}, -- Time in MINUTES between random callouts.
    blip = {sprite = 1, color = 1, scale = 1.5, duration = 3000}, -- Blip settings (duration in seconds)
    callouts = {
        {
            name = "Drunk and Disorderly",
            description = 'There is a person shouting from the rooftops holding a bottle of beer!',
            ped = {model = "a_m_y_beachves_01", weapon = "WEAPON_BOTTLE"},
            scenario = "wander",
            walkstyle = "move_m@drunk@verydrunk", -- Add this line
            state = {
                isDrunk = true,
                isOnDrugs = false,
                hasIllegalItems = false,
                warrants = false
            },
            blip = {
                sprite = 1,
                color = 1,
                scale = 1.0,
                updateInterval = 1500 -- Add this line (1500ms = 1.5 seconds)
            }
        }, {
            name = "Suspected Drug Deal",
            description = 'Someone was seen handing something off to another person',
            ped = {model = "g_m_y_ballas_01", weapon = "WEAPON_PISTOL"},
            scenario = "wander",
            walkstyle = "move_m@drunk@verydrunk", -- Add this line
            blip = {
                sprite = 1,
                color = 1,
                scale = 1.0,
                updateInterval = 1500 -- Add this line (1500ms = 1.5 seconds)
            },
            state = {
                isDrunk = true,
                isOnDrugs = true,
                drugType = "Cocaine",
                hasIllegalItems = true,
                illegalItemFound = "a baggie of white powder",
                warrants = true,
                warrantDetails = {"Possession with Intent to Supply"}
            }
        }, {
            name = "Public Disturbance (Fight)",
            description = 'A person is acting drunk and disorderly in a public area.',
            ped = {model = "s_m_y_dealer_01", weapon = "WEAPON_KNIFE"},
            scenario = "fight",
            opponent_model = "g_m_y_lost_01", -- The model for the second ped.
            blip = {
                sprite = 1,
                color = 1,
                scale = 1.0,
                updateInterval = 1500 -- Add this line (1500ms = 1.5 seconds)
            },
            state = {
                isDrunk = false,
                isOnDrugs = false,
                hasIllegalItems = false,
                warrants = false
            }
        }, {
            name = "Suspected Drunk Driver",
            description = "Reports of a vehicle being driven erratically.",
            scenario = "drunk_driver", -- A unique name for our new scenario
            blip = {
                sprite = 1,
                color = 1,
                scale = 1.0,
                updateInterval = 1500 -- Add this line (1500ms = 1.5 seconds)
            },
            state = {
                isDrunk = true, -- Pre-set the ped's state
                warrants = false
            }
        }, {
            name = "Domestic Disturbance",
            description = "Reports of two individuals in a heated argument.",
            scenario = "domestic", -- A unique name for our new scenario
            blip = {
                sprite = 1,
                color = 1,
                scale = 1.0,
                updateInterval = 1500 -- Add this line (1500ms = 1.5 seconds)
            },
            state = {
                isDrunk = false,
                isOnDrugs = false,
                hasIllegalItems = true,
                warrants = true
            }
        },         {
            name = "Welfare Check",
            description = "Reports of an individual who has collapsed and is unresponsive.",
            scenario = 'welfare_check', -- Custom scenario name
            blip = { sprite = 1, color = 3, scale = 1.0, updateInterval = 5000 },
            ped = { model = 'a_m_m_homeless_01' },
            state = { isDrunk = false, isOnDrugs = true, warrants = false }
        },
        {
            name = "Public Disturbance",
            description = "An individual is shouting and acting aggressively towards the public.",
            scenario = 'public_disturbance',
            walkstyle = 'move_m@brave', -- Makes the ped walk aggressively
            blip = { sprite = 1, color = 1, scale = 1.0, updateInterval = 2000 },
            ped = { model = 'g_m_y_famdnf_01' },
            state = { isDrunk = true, warrants = true, warrantDetails = {"Public Order Offence"} }
        },
        {
            name = "Suspicious Person",
            description = "An individual is reported to be loitering and looking into vehicles.",
            scenario = 'suspicious_person',
            walkstyle = 'move_m@shadyped@a', -- Makes the ped walk shiftily
            blip = { sprite = 1, color = 5, scale = 1.0, updateInterval = 2000 },
            ped = { model = 'a_m_y_soucent_01' },
            state = { hasIllegalItems = true, illegalItemFound = "a set of lockpicks" }
        },
        {
            name = "Stolen Vehicle Report",
            description = "A vehicle matching the description of a recently stolen car has been spotted.",
            scenario = 'stolen_vehicle', -- Matches the drunk_driver logic but with a different state
            blip = { sprite = 523, color = 1, scale = 1.2, updateInterval = 1000 }, -- Car blip
            state = { warrants = true, warrantDetails = {"Grand Theft Auto"} }
        }
    }
}

Config.DrunkDriver = {
    drivingStyle = 786491, -- A style that includes speeding, ignoring lights, and swerving
    updateInterval = 1500, -- How often to update the blip position (in ms)
    blip = {
        sprite = 1,
        color = 5,
        scale = 1.2,
        updateInterval = 1500 -- Add this line (1500ms = 1.5 seconds)
    }
}

Config.TrafficScenarios = {
    enabled = true,
    checkInterval = 10000, -- Check for potential violators every 10 seconds.
    checkRadius = 80.0, -- Check for vehicles within this radius.
    triggerChance = 15, -- 1 in 15 chance to trigger a scenario during a check (lower is more frequent).
    blipDuration = 120, -- **FIX**: Added missing duration in SECONDS for how long the blip lasts.
    scenarios = {
        speeding = {
            chance = 2, -- Relative chance of this scenario occurring.
            speed = 45.0, -- Speed in m/s (approx 100 mph).
            drivingStyle = 2621444 -- A mix of flags to drive fast and ignore some rules.
        },
        dangerousDriving = {
            chance = 2, -- Relative chance of this scenario occurring.
            drivingStyle = 786603, -- Reckless driving style flag.
            drunkChance = 3, -- 1 in 3 chance for the dangerous driver to also be drunk.
            drugChance = 4 -- 1 in 4 chance for the dangerous driver to be on drugs.
        },
        brokenDown = {
            chance = 2, -- Higher chance as it's a common event
        },
        noInsurance = {
            chance = 1, -- Same chance as dangerous driving
            drivingStyle = 786603, -- Ignores traffic laws, drives aggressively

        }
    }
}

Config.Names = {
    maleFirstNames = {
        "Liam", "Noah", "Oliver", "George", "Leo", "Arthur", "Muhammad",
        "Oscar", "Henry", "Theodore", "Freddie", "Harry", "Jack", "Charlie",
        "Archie", "Theo", "Alfie", "Jacob", "Thomas", "Finley", "James",
        "William", "Lucas", "Isaac", "Teddy", "Alexander", "Daniel", "Roman",
        "Logan", "Ethan", "Max", "Mohammed", "Reuben", "Adam", "Reggie",
        "Edward", "Riley", "Joseph", "Louie", "Arlo", "Jaxon", "Samuel",
        "Benjamin", "Mason", "Tommy", "Rory", "Joshua", "Jude", "Albie",
        "Ezra", "Carter", "Luca", "Sebastian", "Caleb", "David", "Ryan"
    },
    femaleFirstNames = {
        "Olivia", "Amelia", "Isla", "Ava", "Mia", "Ivy", "Lily", "Isabella",
        "Rosie", "Sophia", "Freya", "Florence", "Willow", "Emily", "Grace",
        "Poppy", "Ella", "Evelyn", "Charlotte", "Daisy", "Sofia", "Phoebe",
        "Matilda", "Ruby", "Alice", "Elsie", "Sienna", "Luna", "Harper",
        "Jessica", "Scarlett", "Maisie", "Chloe", "Millie", "Evie", "Penelope",
        "Layla", "Aria", "Hallie", "Ada", "Robyn", "Bonnie", "Lottie",
        "Eleanor", "Thea", "Erin", "Violet", "Bella", "Aurora", "Clara",
        "Esme", "Mila", "Nancy", "Zara", "Maya"
    },
    lastNames = {
        "Smith", "Jones", "Taylor", "Brown", "Williams", "Wilson", "Johnson",
        "Roberts", "Robinson", "Thompson", "Walker", "White", "Edwards",
        "Green", "Wood", "Harris", "Lewis", "Martin", "Jackson", "Clarke",
        "Clark", "Turner", "Hill", "Moore", "King", "Wright", "Davies", "Evans",
        "Davis", "Baker", "Hall", "Allen", "Morris", "James", "Scott",
        "Phillips", "Watson", "Bailey", "Cook", "Cooper", "Morgan", "Kelly",
        "Richardson", "Cox", "Parker", "Bell", "Murray", "Hughes", "Price",
        "Young", "Stewart", "Mitchell", "Shaw", "Bennett", "Carter", "Gray"
    }
}

Config.Dispatch = {
    integration = 'ps-dispatch',
    customServerEvent = 'my-dispatch:server:CreateAlert', -- The server event to trigger for 'custom' integration
    alerts = {
        PULLS_KNIFE = {
            title = "Officer in Distress",
            description = "Suspect has pulled a knife on an officer during an arrest!",
            blip = {sprite = 1, color = 1, scale = 1.2, duration = 600}, -- Red blip
            -- NEW: Define the exact data structure you want to send for this alert
            customPayload = {
                event = "10-13", -- Your custom field
                title = "URGENT: Officer requires immediate assistance!", -- Your custom title
                details = "%description% Location: %street%", -- Mix static text with dynamic data
                location = "%coords%", -- This will be replaced with the coordinates vector
                priority = "HIGH", -- Your custom field
                jobs = Config.PoliceJobs -- You can even reference other parts of the config
            },
        blipType = 'dispatchAlert'

        },
        SUSPECT_FLEEING = {
        title = "Pursuit in Progress",
        description = "A suspect is fleeing from a traffic stop.",
        blipType = "trafficTracker", -- Uses the existing traffic blip style
            blip = {sprite = 1, color = 5, scale = 1.0, duration = 600}, -- Yellow blip
            customPayload = {
                code = "311-B",
                message = "Foot Pursuit in progress near %street%",
                coords = "%coords%",
                jobs = Config.PoliceJobs
            },
        },
        FLEES_ON_FOOT = {
            title = "Foot Pursuit",
            description = "Suspect is fleeing on foot from an officer.",
            blip = {sprite = 1, color = 5, scale = 1.0, duration = 600}, -- Yellow blip
            customPayload = {
                code = "311-B",
                message = "Foot Pursuit in progress near %street%",
                coords = "%coords%",
                jobs = Config.PoliceJobs
            },
        blipType = 'dispatchAlert'

        },
        SPEEDING_VEHICLE = {
            title = "Vehicle Speeding",
            description = "Officer is flagging a vehicle for excessive speed.",
            blip = {sprite = 1, color = 5, scale = 1.0, duration = 600},
            customPayload = {
                callType = "TRAFFIC",
                title = "%title%", -- Re-use the default title
                info = "%description%", -- Re-use the default description
                street = "%street%",
                pos = "%coords%",
                jobs = Config.PoliceJobs
            },
        blipType = 'dispatchAlert'

        },
        DANGEROUS_DRIVING = {
            title = "Dangerous Driving",
            description = "Officer has spotted a vehicle driving erratically.",
            blip = {sprite = 1, color = 5, scale = 1.0, duration = 600},
            customPayload = {
                callType = "TRAFFIC",
                title = "%title%", -- Re-use the default title
                info = "%description%", -- Re-use the default description
                street = "%street%",
                pos = "%coords%",
                jobs = Config.PoliceJobs
            },
        blipType = 'dispatchAlert'

        },
        ['OFFICER_IN_DANGER'] = {
            title = "Officer Under Attack",
            description = "An officer is being attacked by a suspect.",
            blip = {
                sprite = 487, -- Skull icon
                color = 1, -- Red
                scale = 1.5,
                duration = 600
            },
            -- NEW: Define the exact data structure you want to send for this alert
            customPayload = {
                event = "10-13", -- Your custom field
                title = "URGENT: Officer requires immediate assistance!", -- Your custom title
                details = "%description% Location: %street%", -- Mix static text with dynamic data
                location = "%coords%", -- This will be replaced with the coordinates vector
                priority = "HIGH", -- Your custom field
                jobs = Config.PoliceJobs -- You can even reference other parts of the config
            },
        blipType = 'dispatchAlert'

        }
    },
}

-- Dynamic Questioning Options
Config.Questioning = {
    {label = "Ask for ID", action = 'id_check'},
    {label = "Ask about recent activity", action = 'ask_activity'}, 
{
    label = "Ask about vehicle ownership",
    action = 'ask_ownership', -- This triggers the new special action
},
{
        label = "Do you know why I've pulled you over?",
        responses = {
            legal = {
                "I'm not sure, officer. Was there a problem with my driving?",
                "No idea. I thought I was driving perfectly fine.",
                "Is one of my tail lights out? I've been meaning to get that checked."
            },
            illegal = {
                "Look, I might have been a bit quick, but I'm in a hurry.",
                "Was I speeding? C'mon mate, it's a quiet road.",
                "I'm just trying to get home, what's the big deal?"
            }
        }
    }, {
        label = "Are you under the influence of any drugs?",
        responses = {
            legal = {
                "Absolutely not, officer.",
                "No, I don't use them.",
                "I'm on some prescription medication, I can show you if needed."
            },
            illegal = { -- Responses for someone on drugs
                "What? No! Why would you ask that?",
                "Nah man, I'm just tired, it's been a long day.",
                "My eyes are red because of allergies, that's all."
            }
        }
    }, {
        label = "Do you have anything illegal on you?",
        responses = {
            legal = {
                "No, of course not.",
                "Absolutely not, officer. You are welcome to check.",
                "I have a pocket knife in my bag for work, but that's all."
            },
            illegal = { -- Responses for someone with illegal items
                "Uh, no. Nothing like that.",
                "Why? You got a warrant or something?",
                "Just my wallet and keys, mate."
            }
        }
    }, {
    label = "What's your reason for being in the area today?",
    responses = {
        legal = {
            "I live just around the corner, heading home.",
            "Just passing through on my way to Roxwood.",
            "I was visiting a mate who lives on this estate.",
            "I'm a bit lost, trying to find the industrial estate."
        },
        illegal = {
            "Just killing time, you know.",
            "Am I not allowed to be here or something?",
            "I'm just waiting for a mate... he should be here soon.",
            "What's it to you? Just minding my own business."
        }
    }
},
{
    label = "Where are you going to today?",
    responses = {
        legal = {
            "Just on my way home from work.",
            "Heading into town to meet some friends.",
            "Dropping my mate off at his place",
            "I'm a bit lost, actually, looking for the Theme Park."
        },
        illegal = {
            "Just out for a drive, no particular place.",
            "Nowhere special, just heading that way.",
            "Look, does it matter? I'm not doing anything wrong.",
            "Not sure yet, just seeing where the road takes me."
        }
    }
}, {
        label = "Is this your vehicle, sir/ma'am?",
        responses = {
            legal = {
                "Yes, it's mine. Registered in my name.",
                "No, it belongs to my partner. I'm insured to drive it, of course.",
                "It's a company car, officer."
            },
            illegal = {
                "Yeah, it's mine... I think. Just bought it.",
                "I'm borrowing it from a mate.",
                "Why are you asking so many questions? It's just a car."
            }
        }
    }, {
        label = "Have you been drinking in the last 24 hours?",
        responses = {
            legal = {
                "No, nothing at all. I'm on my way to work.",
                "I'm the designated driver tonight, haven't touched a drop.",
                "No officer, I don't drink and drive."
            },
            illegal = { -- Responses for a drunk person
                "Nah, just had one pint with dinner last night, I'm fine.",
                "Just a couple with my mates at the pub, but I feel fine to drive.",
                "Look... maybe a little, but I can handle it."
            }
        }
    }, 
}

-- Data for random ped generation
Config.WarrantCharges = {
    "Common Assault (Section 39)", "Grievous Bodily Harm (GBH)",
    "Actual Bodily Harm (ABH)", "Theft", "Burglary", "Robbery",
    "Possession of a Controlled Substance", "Public Order Offence",
    "Failure to Appear in Court", "Breach of Bail Conditions"
}
Config.IllegalItems = {
    "an illegal firearm", "a switchblade", "a bag of narcotics",
    "counterfeit currency", "a fake ID", "a large amount of cash"
}
Config.SpecificDrugs = {
    "Cocaine", "Methamphetamine", "Marijuana", "Ecstasy", "Psilocybin Mushrooms"
}

-- Dispatch Radio Codes
Config.DispatchStates = {
    ["State 1 (On Duty)"] = "You have radioed in: State 1, on duty.",
    ["State 2 (On Patrol)"] = "You have radioed in: State 2, on patrol.",
    ["State 4 (Break)"] = "You have radioed in: State 4, taking a break.",
    ["State 5 (En Route)"] = "You have radioed in: State 5, en route to call.",
    ["State 6 (At Scene)"] = "You have radioed in: State 6, at scene.",
    ["State 9 (Prisoner Transport)"] = "You have radioed in: State 9, transporting a prisoner.",
    ["IC1 (White/Caucasian)"] = "You have radioed in: IC1 identity.",
    ["IC2 (Black/Afro-Caribbean)"] = "You have radioed in: IC2 identity.",
    ["IC3 (Asian)"] = "You have radioed in: IC3 identity.",
    ["IC9 (Unknown/Other)"] = "You have radioed in: IC9 identity."
}

