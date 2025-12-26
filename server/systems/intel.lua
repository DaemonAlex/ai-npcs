--[[
    TIME-SENSITIVE INTEL SYSTEM
    NPCs share actionable intelligence that expires
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Intel types and their properties
local INTEL_TYPES = {
    -- Criminal opportunities
    house_robbery = {
        category = "crime",
        baseValue = 500,
        expiryHours = 4,
        minTrust = 30,
        description = "Location of an easy score"
    },
    store_robbery = {
        category = "crime",
        baseValue = 300,
        expiryHours = 2,
        minTrust = 20,
        description = "Store with light security"
    },
    bank_job = {
        category = "heist",
        baseValue = 2500,
        expiryHours = 24,
        minTrust = 70,
        description = "Bank vulnerability info"
    },
    vault_codes = {
        category = "heist",
        baseValue = 5000,
        expiryHours = 6,
        minTrust = 85,
        description = "Security codes for a vault"
    },
    drug_shipment = {
        category = "drugs",
        baseValue = 1500,
        expiryHours = 8,
        minTrust = 50,
        description = "Drug shipment arrival"
    },
    stash_location = {
        category = "drugs",
        baseValue = 2000,
        expiryHours = 12,
        minTrust = 60,
        description = "Hidden drug stash"
    },
    weapon_cache = {
        category = "weapons",
        baseValue = 3000,
        expiryHours = 24,
        minTrust = 75,
        description = "Weapon stockpile location"
    },
    car_boost = {
        category = "vehicles",
        baseValue = 800,
        expiryHours = 6,
        minTrust = 35,
        description = "High-value vehicle location"
    },

    -- Information intel
    cop_patrol = {
        category = "info",
        baseValue = 200,
        expiryHours = 1,
        minTrust = 15,
        description = "Police patrol routes"
    },
    snitch_identity = {
        category = "info",
        baseValue = 1000,
        expiryHours = 48,
        minTrust = 55,
        description = "Identity of a snitch"
    },
    gang_meeting = {
        category = "info",
        baseValue = 1500,
        expiryHours = 3,
        minTrust = 65,
        description = "Gang meeting location/time"
    },
    safe_house = {
        category = "info",
        baseValue = 800,
        expiryHours = 72,
        minTrust = 45,
        description = "Hidden safe house location"
    },

    -- Special intel
    dirty_cop = {
        category = "special",
        baseValue = 5000,
        expiryHours = 168,  -- 1 week
        minTrust = 90,
        description = "Corrupt officer identity"
    },
    witness_location = {
        category = "special",
        baseValue = 3500,
        expiryHours = 12,
        minTrust = 80,
        description = "Witness in protective custody"
    },
    evidence_room = {
        category = "special",
        baseValue = 4000,
        expiryHours = 24,
        minTrust = 85,
        description = "Evidence room access info"
    },
}

-----------------------------------------------------------
-- CREATE INTEL
-----------------------------------------------------------
function CreateIntel(npcId, intelType, details, options)
    options = options or {}

    local intelConfig = INTEL_TYPES[intelType]
    if not intelConfig then
        if Config.Debug.enabled then
            print(("[AI NPCs] Unknown intel type: %s"):format(intelType))
        end
        return nil
    end

    -- Calculate expiry
    local expiryHours = options.expiryHours or intelConfig.expiryHours
    local expiresAt = os.date("%Y-%m-%d %H:%M:%S", os.time() + (expiryHours * 3600))

    -- Calculate value (can be modified)
    local value = options.value or intelConfig.baseValue
    if options.quality then
        value = math.floor(value * options.quality)  -- quality is a multiplier
    end

    local intelId = MySQL.insert.await([[
        INSERT INTO ai_npc_intel
        (npc_id, intel_type, category, title, details, value, trust_required, expires_at, max_buyers)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        npcId,
        intelType,
        intelConfig.category,
        options.title or intelConfig.description,
        json.encode(details),
        value,
        options.minTrust or intelConfig.minTrust,
        expiresAt,
        options.maxBuyers or 1
    })

    if Config.Debug.enabled then
        print(("[AI NPCs] Intel created: %s (%s) by %s, expires in %d hours"):format(
            intelType, intelId, npcId, expiryHours
        ))
    end

    return intelId
end

-----------------------------------------------------------
-- GET AVAILABLE INTEL FOR PLAYER
-----------------------------------------------------------
function GetAvailableIntel(playerId, npcId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return {} end

    local citizenid = Player.PlayerData.citizenid

    -- Get player's trust with this NPC
    local trustResult = MySQL.scalar.await([[
        SELECT trust_value FROM ai_npc_trust
        WHERE citizenid = ? AND npc_id = ?
    ]], {citizenid, npcId})

    local trust = trustResult or 0

    -- Get intel this NPC has that player qualifies for
    local intel = MySQL.query.await([[
        SELECT i.*,
               (SELECT COUNT(*) FROM ai_npc_intel_purchases WHERE intel_id = i.id) as buyers
        FROM ai_npc_intel i
        WHERE i.npc_id = ?
        AND i.expires_at > NOW()
        AND i.trust_required <= ?
        AND i.id NOT IN (
            SELECT intel_id FROM ai_npc_intel_purchases WHERE citizenid = ?
        )
        HAVING buyers < i.max_buyers
        ORDER BY i.value DESC
    ]], {npcId, trust, citizenid})

    return intel or {}
end

-----------------------------------------------------------
-- PURCHASE INTEL
-----------------------------------------------------------
function PurchaseIntel(playerId, intelId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false, "no_player" end

    local citizenid = Player.PlayerData.citizenid

    -- Get intel details
    local intel = MySQL.single.await([[
        SELECT i.*,
               (SELECT COUNT(*) FROM ai_npc_intel_purchases WHERE intel_id = i.id) as buyers
        FROM ai_npc_intel i
        WHERE i.id = ?
    ]], {intelId})

    if not intel then return false, "intel_not_found" end

    -- Check expiry
    if intel.expires_at and os.time() > ParseMySQLDate(intel.expires_at) then
        return false, "intel_expired"
    end

    -- Check max buyers
    if intel.buyers >= intel.max_buyers then
        return false, "intel_sold_out"
    end

    -- Check trust
    local trustResult = MySQL.scalar.await([[
        SELECT trust_value FROM ai_npc_trust
        WHERE citizenid = ? AND npc_id = ?
    ]], {citizenid, intel.npc_id})

    if (trustResult or 0) < intel.trust_required then
        return false, "insufficient_trust"
    end

    -- Check if already purchased
    local alreadyBought = MySQL.scalar.await([[
        SELECT id FROM ai_npc_intel_purchases WHERE intel_id = ? AND citizenid = ?
    ]], {intelId, citizenid})

    if alreadyBought then
        return false, "already_purchased"
    end

    -- Check if player has money
    if intel.value > 0 then
        local cash = Player.PlayerData.money.cash or 0
        if cash < intel.value then
            return false, "not_enough_money"
        end

        Player.Functions.RemoveMoney('cash', intel.value, 'intel-purchase')
    end

    -- Record purchase
    MySQL.insert([[
        INSERT INTO ai_npc_intel_purchases (intel_id, citizenid, price_paid)
        VALUES (?, ?, ?)
    ]], {intelId, citizenid, intel.value})

    -- Parse intel details
    local details = json.decode(intel.details or "{}")

    if Config.Debug.enabled then
        print(("[AI NPCs] Intel purchased: %s bought intel #%d from %s for $%d"):format(
            citizenid, intelId, intel.npc_id, intel.value
        ))
    end

    return true, {
        type = intel.intel_type,
        category = intel.category,
        title = intel.title,
        details = details,
        expiresAt = intel.expires_at
    }
end

-----------------------------------------------------------
-- HELPER: Parse MySQL datetime
-----------------------------------------------------------
function ParseMySQLDate(dateStr)
    if not dateStr then return 0 end
    local pattern = "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)"
    local year, month, day, hour, min, sec = dateStr:match(pattern)
    if year then
        return os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec)
        })
    end
    return 0
end

-----------------------------------------------------------
-- BUILD INTEL CONTEXT FOR AI
-----------------------------------------------------------
function BuildIntelContext(npcId, citizenid)
    local context = ""

    -- Check what intel this NPC has available
    local trustResult = MySQL.scalar.await([[
        SELECT trust_value FROM ai_npc_trust
        WHERE citizenid = ? AND npc_id = ?
    ]], {citizenid, npcId})

    local trust = trustResult or 0

    local availableIntel = MySQL.query.await([[
        SELECT intel_type, category, title, value, trust_required,
               TIMESTAMPDIFF(HOUR, NOW(), expires_at) as hours_left
        FROM ai_npc_intel
        WHERE npc_id = ?
        AND expires_at > NOW()
        AND id NOT IN (
            SELECT intel_id FROM ai_npc_intel_purchases WHERE citizenid = ?
        )
        ORDER BY trust_required ASC
        LIMIT 5
    ]], {npcId, citizenid})

    if availableIntel and #availableIntel > 0 then
        context = "\n=== INTEL YOU CAN OFFER ===\n"
        context = context .. "You have information the player might want to buy:\n"

        for _, intel in ipairs(availableIntel) do
            local canOffer = trust >= intel.trust_required
            local urgency = intel.hours_left <= 2 and " (URGENT - expires soon!)" or ""

            if canOffer then
                context = context .. string.format(
                    "- %s ($%d) - %s%s\n",
                    intel.title, intel.value, intel.category, urgency
                )
            else
                context = context .. string.format(
                    "- [LOCKED - needs %d trust] %s hint about it to build interest\n",
                    intel.trust_required, intel.category
                )
            end
        end

        context = context .. "\nIf player asks about intel or info, you can:\n"
        context = context .. "- Offer to sell what they qualify for\n"
        context = context .. "- Hint at locked intel to motivate trust building\n"
        context = context .. "- Mention time sensitivity if intel expires soon\n"
    end

    return context
end

-----------------------------------------------------------
-- GENERATE INTEL FOR NPC (called periodically or on events)
-----------------------------------------------------------
function GenerateIntelForNPC(npcId, npcData)
    if not npcData then return end

    -- Check what intel types this NPC would know about
    local validTypes = {}

    if npcData.trustCategory == "criminal" then
        validTypes = {"house_robbery", "store_robbery", "car_boost", "cop_patrol", "safe_house"}
    elseif npcData.trustCategory == "gang" then
        validTypes = {"drug_shipment", "stash_location", "weapon_cache", "gang_meeting", "snitch_identity"}
    elseif npcData.trustCategory == "underground" then
        validTypes = {"bank_job", "vault_codes", "dirty_cop", "witness_location", "evidence_room"}
    else
        return  -- Legitimate NPCs don't have criminal intel
    end

    -- Check how much intel this NPC already has active
    local activeCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM ai_npc_intel
        WHERE npc_id = ? AND expires_at > NOW()
    ]], {npcId})

    -- Max 3 active intel per NPC
    if (activeCount or 0) >= 3 then return end

    -- Random chance to generate intel
    if math.random(100) > 30 then return end  -- 30% chance

    -- Pick a random intel type
    local intelType = validTypes[math.random(#validTypes)]
    local intelConfig = INTEL_TYPES[intelType]

    -- Generate details based on type
    local details = GenerateIntelDetails(intelType)

    -- Quality modifier (affects price)
    local quality = 0.8 + (math.random() * 0.4)  -- 0.8 to 1.2

    CreateIntel(npcId, intelType, details, {
        quality = quality,
        title = GenerateIntelTitle(intelType, details)
    })
end

-----------------------------------------------------------
-- GENERATE INTEL DETAILS
-----------------------------------------------------------
function GenerateIntelDetails(intelType)
    local details = {}

    -- Generate location-based details
    local locations = {
        "Vinewood Hills", "Downtown LS", "Vespucci", "Del Perro", "Paleto Bay",
        "Sandy Shores", "Grapeseed", "Mirror Park", "La Mesa", "Davis",
        "Rancho", "Cypress Flats", "El Burro Heights", "Textile City", "Pillbox Hill"
    }

    details.location = locations[math.random(#locations)]

    -- Type-specific details
    if intelType == "house_robbery" then
        details.security = math.random(1, 3)  -- 1-3 difficulty
        details.estimated_value = math.random(5, 20) * 1000
        details.occupants_away = math.random(1, 4)  -- hours

    elseif intelType == "drug_shipment" then
        details.arrival_hour = math.random(18, 23)
        local quantities = {"small", "medium", "large"}
        details.quantity = quantities[math.random(#quantities)]
        details.guards = math.random(2, 6)

    elseif intelType == "bank_job" then
        local banks = {"Fleeca", "Paleto", "Pacific Standard"}
        local vulns = {"guard rotation gap", "camera blind spot", "vault timer exploit"}
        details.bank_type = banks[math.random(#banks)]
        details.vulnerability = vulns[math.random(#vulns)]
        details.window_hours = math.random(2, 6)

    elseif intelType == "cop_patrol" then
        details.patrol_time = math.random(0, 23)
        details.officers = math.random(2, 4)
        details.response_time = math.random(2, 8)  -- minutes

    elseif intelType == "stash_location" then
        local contents = {"cash", "drugs", "weapons", "mixed"}
        details.contents = contents[math.random(#contents)]
        details.estimated_value = math.random(10, 50) * 1000
        details.guarded = math.random(100) > 60

    elseif intelType == "weapon_cache" then
        local weapons = {"handguns", "SMGs", "rifles", "heavy"}
        details.weapons = weapons[math.random(#weapons)]
        details.quantity = math.random(5, 20)
        details.guarded = math.random(100) > 40

    elseif intelType == "car_boost" then
        local cars = {"Zentorno", "T20", "Adder", "Entity", "Turismo", "Vacca"}
        local security = {"unlocked", "basic alarm", "advanced alarm", "GPS tracked"}
        details.vehicle = cars[math.random(#cars)]
        details.security = security[math.random(#security)]

    elseif intelType == "snitch_identity" then
        details.alias = "The information points to someone close"
        local factions = {"Vagos", "Ballas", "Families", "Marabunta", "Lost MC"}
        details.faction = factions[math.random(#factions)]

    elseif intelType == "dirty_cop" then
        local depts = {"LSPD", "BCSO", "SASP"}
        local corruption = {"takes bribes", "runs protection", "tips off raids", "plants evidence"}
        details.department = depts[math.random(#depts)]
        details.corruption_type = corruption[math.random(#corruption)]
    end

    return details
end

-----------------------------------------------------------
-- GENERATE INTEL TITLE
-----------------------------------------------------------
function GenerateIntelTitle(intelType, details)
    local titles = {
        house_robbery = {
            "Easy Score in " .. (details.location or "Vinewood"),
            "Empty House - " .. (details.location or "Unknown"),
            "Rich Target - Low Security"
        },
        drug_shipment = {
            "Shipment Tonight",
            "Product Coming In",
            "Fresh Supply Arriving"
        },
        bank_job = {
            (details.bank_type or "Bank") .. " Vulnerability",
            "Inside Info on " .. (details.bank_type or "a bank"),
            "Security Gap Found"
        },
        cop_patrol = {
            "Patrol Schedule",
            "Police Routes",
            "When the Heat's Light"
        },
        stash_location = {
            "Hidden Stash",
            "Unguarded Product",
            "Someone's Nest Egg"
        },
        weapon_cache = {
            "Gun Stash Location",
            "Weapons for the Taking",
            "Armed & Unguarded"
        },
        car_boost = {
            (details.vehicle or "Exotic") .. " Location",
            "Premium Ride Spotted",
            "Easy Boost"
        },
        snitch_identity = {
            "Rat in the Ranks",
            "Who's Talking",
            "The Leak"
        },
        dirty_cop = {
            "Badge for Sale",
            "Crooked Blue",
            "Inside Man"
        },
        vault_codes = {
            "Access Codes",
            "The Combination",
            "Keys to the Kingdom"
        },
        gang_meeting = {
            "Meeting Tonight",
            "Where They'll Be",
            "Gathering Intel"
        },
        safe_house = {
            "Hideout Location",
            "Safe Spot",
            "Off the Grid"
        },
        witness_location = {
            "The Witness",
            "Protected Location",
            "Who Saw What"
        },
        evidence_room = {
            "Evidence Access",
            "Getting to the Proof",
            "Inside the Lockup"
        },
        store_robbery = {
            "Easy Store Hit",
            "Light Security Target",
            "Quick Cash"
        }
    }

    local options = titles[intelType] or {"Information Available"}
    return options[math.random(#options)]
end

-----------------------------------------------------------
-- PERIODIC INTEL GENERATION
-----------------------------------------------------------
CreateThread(function()
    Wait(60000)  -- Wait 1 minute after server start

    while true do
        -- Every 30 minutes, potentially generate intel for NPCs
        for _, npc in pairs(Config.NPCs or {}) do
            if npc.trustCategory and npc.trustCategory ~= "legitimate" then
                GenerateIntelForNPC(npc.id, npc)
            end
        end

        Wait(1800000)  -- 30 minutes
    end
end)

-----------------------------------------------------------
-- CLEANUP EXPIRED INTEL
-----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(3600000)  -- Every hour

        MySQL.update([[
            DELETE FROM ai_npc_intel
            WHERE expires_at < DATE_SUB(NOW(), INTERVAL 24 HOUR)
        ]])

        if Config.Debug.enabled then
            print("[AI NPCs] Cleaned up expired intel")
        end
    end
end)

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
exports('CreateIntel', CreateIntel)
exports('GetAvailableIntel', GetAvailableIntel)
exports('PurchaseIntel', PurchaseIntel)
exports('BuildIntelContext', BuildIntelContext)
exports('GenerateIntelForNPC', GenerateIntelForNPC)

-----------------------------------------------------------
-- EVENTS
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:purchaseIntel', function(intelId)
    local src = source
    local success, result = PurchaseIntel(src, intelId)

    if success then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Intel Acquired',
            description = result.title,
            type = 'success'
        })
        TriggerClientEvent('ai-npcs:client:intelReceived', src, result)
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Transaction Failed',
            description = result,
            type = 'error'
        })
    end
end)

-- Request available intel list
RegisterNetEvent('ai-npcs:server:getIntelList', function(npcId)
    local src = source
    local intel = GetAvailableIntel(src, npcId)
    TriggerClientEvent('ai-npcs:client:showIntelList', src, intel)
end)

print("^2[AI NPCs]^7 Time-Sensitive Intel system loaded")
