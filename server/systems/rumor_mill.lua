--[[
    RUMOR MILL SYSTEM
    NPCs know about player actions and gossip about them
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Cache of recent rumors per player
local rumorCache = {}  -- { [citizenid] = { rumors } }

-----------------------------------------------------------
-- RECORD PLAYER ACTIONS (Called by other scripts)
-----------------------------------------------------------
function RecordPlayerAction(citizenid, actionType, details)
    details = details or {}

    -- Determine visibility based on action type
    local visibility = "street"
    local heatLevel = 50
    local expiresInDays = 7

    -- Configure based on action type
    local actionConfig = {
        -- Major crimes
        bank_robbery = { visibility = "citywide", heat = 90, expires = 14 },
        jewelry_heist = { visibility = "citywide", heat = 85, expires = 14 },
        casino_heist = { visibility = "legendary", heat = 100, expires = 30 },
        pacific_standard = { visibility = "legendary", heat = 100, expires = 30 },

        -- Drug activity
        drug_sale = { visibility = "street", heat = 30, expires = 3 },
        drug_bust = { visibility = "underground", heat = 40, expires = 5 },
        large_drug_deal = { visibility = "underground", heat = 60, expires = 7 },
        meth_cook = { visibility = "underground", heat = 50, expires = 5 },

        -- Violence
        murder = { visibility = "street", heat = 80, expires = 14 },
        gang_kill = { visibility = "underground", heat = 70, expires = 10 },
        cop_kill = { visibility = "citywide", heat = 100, expires = 30 },
        assault = { visibility = "street", heat = 40, expires = 3 },

        -- Misc
        car_theft = { visibility = "street", heat = 25, expires = 2 },
        house_robbery = { visibility = "street", heat = 45, expires = 5 },
        store_robbery = { visibility = "street", heat = 35, expires = 3 },
        arrested = { visibility = "underground", heat = 60, expires = 7 },
        escaped_custody = { visibility = "citywide", heat = 75, expires = 10 },

        -- Positive/Neutral
        large_purchase = { visibility = "street", heat = 20, expires = 3 },
        business_deal = { visibility = "street", heat = 15, expires = 5 },
        helped_gang = { visibility = "underground", heat = 30, expires = 7 },
    }

    local config = actionConfig[actionType] or { visibility = "street", heat = 50, expires = 7 }
    visibility = config.visibility
    heatLevel = config.heat
    expiresInDays = config.expires

    -- Calculate expiry
    local expiresAt = os.date("%Y-%m-%d %H:%M:%S", os.time() + (expiresInDays * 86400))

    -- Insert rumor
    MySQL.insert([[
        INSERT INTO ai_npc_rumors (citizenid, action_type, action_details, visibility, heat_level, witnesses, is_public, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        actionType,
        json.encode(details),
        visibility,
        heatLevel,
        details.witnesses or 0,
        details.isPublic or false,
        expiresAt
    })

    -- Also log to player actions
    MySQL.insert([[
        INSERT INTO ai_npc_player_actions (citizenid, action_category, action_type, target_type, target_id, location, value, severity, witnesses, reported_to_police)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        details.category or 'crime',
        actionType,
        details.targetType,
        details.targetId,
        details.location,
        details.value or 0,
        math.floor(heatLevel / 10),
        details.witnesses or 0,
        details.reportedToPolice or false
    })

    -- Clear cache for this player
    rumorCache[citizenid] = nil

    if Config.Debug.enabled then
        print(("[AI NPCs] Recorded action: %s did %s (heat: %d, visibility: %s)"):format(
            citizenid, actionType, heatLevel, visibility
        ))
    end
end

-----------------------------------------------------------
-- GET RUMORS ABOUT A PLAYER
-----------------------------------------------------------
function GetRumorsAboutPlayer(citizenid, npcVisibilityAccess)
    -- NPC visibility access determines what they can know
    -- criminal NPCs know "underground", street NPCs know "street", etc.
    npcVisibilityAccess = npcVisibilityAccess or "street"

    local visibilityLevels = {
        underground = {"underground", "street", "citywide", "legendary"},
        street = {"street", "citywide", "legendary"},
        citywide = {"citywide", "legendary"},
        legendary = {"legendary"}
    }

    local allowedLevels = visibilityLevels[npcVisibilityAccess] or visibilityLevels.street

    -- Check cache first
    local cacheKey = citizenid .. "_" .. npcVisibilityAccess
    if rumorCache[cacheKey] and (os.time() - rumorCache[cacheKey].time) < 300 then
        return rumorCache[cacheKey].rumors
    end

    -- Build visibility filter
    local placeholders = {}
    for i = 1, #allowedLevels do
        placeholders[i] = "?"
    end
    local visibilityFilter = table.concat(placeholders, ", ")

    -- Query recent rumors
    local params = {citizenid}
    for _, level in ipairs(allowedLevels) do
        table.insert(params, level)
    end

    local query = string.format([[
        SELECT action_type, action_details, visibility, heat_level, created_at
        FROM ai_npc_rumors
        WHERE citizenid = ?
        AND visibility IN (%s)
        AND (expires_at IS NULL OR expires_at > NOW())
        AND heat_level > 20
        ORDER BY heat_level DESC, created_at DESC
        LIMIT 5
    ]], visibilityFilter)

    local rumors = MySQL.query.await(query, params) or {}

    -- Cache result
    rumorCache[cacheKey] = {
        time = os.time(),
        rumors = rumors
    }

    return rumors
end

-----------------------------------------------------------
-- FORMAT RUMORS FOR NPC CONTEXT
-----------------------------------------------------------
function FormatRumorsForContext(rumors, playerName)
    if not rumors or #rumors == 0 then
        return nil
    end

    local rumorTexts = {
        bank_robbery = "word on the street is %s hit a bank recently",
        jewelry_heist = "heard %s cleaned out a jewelry store",
        casino_heist = "%s pulled off a casino job - that takes balls",
        pacific_standard = "everyone's talking about how %s hit Pacific Standard",
        drug_sale = "%s has been moving product around town",
        large_drug_deal = "%s made a big deal recently - serious weight",
        meth_cook = "heard %s knows their way around a lab",
        murder = "people say %s has blood on their hands",
        gang_kill = "%s put in work for somebody",
        cop_kill = "%s dropped a cop - that's heavy heat",
        car_theft = "%s has been boosting cars",
        house_robbery = "word is %s hit some houses",
        store_robbery = "%s has been hitting stores",
        arrested = "%s got picked up recently - wonder if they talked",
        escaped_custody = "%s broke out - cops are pissed",
        helped_gang = "%s did a solid for some people",
    }

    local formatted = {}
    for _, rumor in ipairs(rumors) do
        local template = rumorTexts[rumor.action_type]
        if template then
            local text = string.format(template, playerName)
            local details = json.decode(rumor.action_details or "{}")

            -- Add details if available
            if details.location then
                text = text .. " near " .. details.location
            end
            if details.value and details.value > 10000 then
                text = text .. string.format(" (big score - $%dk+)", math.floor(details.value / 1000))
            end

            table.insert(formatted, {
                text = text,
                heat = rumor.heat_level,
                when = rumor.created_at
            })
        end
    end

    return formatted
end

-----------------------------------------------------------
-- DECAY HEAT OVER TIME
-----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(3600000)  -- Every hour

        MySQL.update([[
            UPDATE ai_npc_rumors
            SET heat_level = GREATEST(0, heat_level - 5)
            WHERE heat_level > 0
        ]])

        if Config.Debug.enabled then
            print("[AI NPCs] Decayed rumor heat levels")
        end
    end
end)

-----------------------------------------------------------
-- BUILD RUMOR CONTEXT FOR AI PROMPT
-----------------------------------------------------------
function BuildRumorContext(npcId, citizenid, npcData)
    -- Determine NPC's access level based on their type
    local accessLevel = "street"

    if npcData then
        if npcData.trustCategory == "gang" or npcData.trustCategory == "underground" then
            accessLevel = "underground"
        elseif npcData.trustCategory == "criminal" then
            accessLevel = "street"
        elseif npcData.trustCategory == "legitimate" then
            accessLevel = "citywide"  -- Only knows public info
        end
    end

    -- Get rumors about this player
    local rumors = GetRumorsAboutPlayer(citizenid, accessLevel)

    if not rumors or #rumors == 0 then
        return ""
    end

    -- Get player name for formatting
    local Player = exports['qb-core']:GetCoreObject().Functions.GetPlayerByCitizenId(citizenid)
    local playerName = Player and Player.PlayerData.charinfo.firstname or "this person"

    -- Format rumors
    local formatted = FormatRumorsForContext(rumors, playerName)

    if not formatted or #formatted == 0 then
        return ""
    end

    -- Build context string
    local context = "\n=== WHAT YOU'VE HEARD ABOUT THEM ===\n"
    context = context .. "Word travels fast on the streets. Here's what you know about this person:\n"

    for _, rumor in ipairs(formatted) do
        local heatIndicator = ""
        if rumor.heat >= 80 then
            heatIndicator = " (EVERYONE'S talking about this)"
        elseif rumor.heat >= 60 then
            heatIndicator = " (hot topic)"
        elseif rumor.heat >= 40 then
            heatIndicator = " (been hearing whispers)"
        end

        context = context .. string.format("- %s%s\n", rumor.text, heatIndicator)
    end

    context = context .. "\nYou can reference this knowledge naturally in conversation.\n"
    context = context .. "If their reputation is violent, be appropriately wary.\n"
    context = context .. "If they've done big jobs, treat them with more respect.\n"

    return context
end

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
exports('RecordPlayerAction', RecordPlayerAction)
exports('GetRumorsAboutPlayer', GetRumorsAboutPlayer)
exports('BuildRumorContext', BuildRumorContext)

-----------------------------------------------------------
-- EVENTS FOR OTHER SCRIPTS TO HOOK INTO
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:recordAction', function(actionType, details)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    RecordPlayerAction(Player.PlayerData.citizenid, actionType, details)
end)

-- Hook into common crime events (add more as needed)
AddEventHandler('qb-bankrobbery:server:success', function(src, bank)
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        RecordPlayerAction(Player.PlayerData.citizenid, 'bank_robbery', {
            location = bank,
            category = 'crime',
            witnesses = math.random(5, 20),
            isPublic = true
        })
    end
end)

AddEventHandler('qb-storerobbery:server:success', function(src)
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        RecordPlayerAction(Player.PlayerData.citizenid, 'store_robbery', {
            category = 'crime',
            witnesses = math.random(1, 5)
        })
    end
end)

print("^2[AI NPCs]^7 Rumor Mill system loaded")
