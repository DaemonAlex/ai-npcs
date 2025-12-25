--[[
    INTERROGATION SYSTEM
    Allows cops to interrogate criminal NPCs for intel
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Interrogation cooldowns per NPC
local interrogationCooldowns = {}  -- { [npcId] = lastTime }
local COOLDOWN_DURATION = 1800000  -- 30 minutes

-- Jobs allowed to interrogate
local ALLOWED_JOBS = {
    police = true,
    sheriff = true,
    fib = true,
    doj = true,
    bcso = true,
    sasp = true,
    lspd = true,
}

-- Grade bonuses for interrogation success
local GRADE_BONUSES = {
    [0] = -20,  -- Cadet: harder
    [1] = -10,  -- Officer: slightly harder
    [2] = 0,    -- Senior: baseline
    [3] = 10,   -- Sergeant: easier
    [4] = 20,   -- Lieutenant: much easier
    [5] = 30,   -- Captain+: very easy
}

-----------------------------------------------------------
-- CHECK IF PLAYER CAN INTERROGATE
-----------------------------------------------------------
function CanInterrogate(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false, "no_player" end

    local job = Player.PlayerData.job.name
    if not ALLOWED_JOBS[job] then
        return false, "not_authorized"
    end

    return true, Player.PlayerData.job.grade.level
end

-----------------------------------------------------------
-- GET NPC RESISTANCE LEVEL
-----------------------------------------------------------
function GetNPCResistance(npcId, npcData)
    local baseResistance = 50

    -- Check NPC's reaction to cops
    if npcData and npcData.contextReactions then
        local reaction = npcData.contextReactions.copReaction
        if reaction == "paranoid_shutdown" then
            baseResistance = 90
        elseif reaction == "hostile_dismissive" then
            baseResistance = 80
        elseif reaction == "extremely_suspicious" then
            baseResistance = 70
        elseif reaction == "professional_denial" then
            baseResistance = 60
        end
    end

    -- Check if NPC was recently interrogated (more resistant)
    if interrogationCooldowns[npcId] then
        local timeSince = GetGameTimer() - interrogationCooldowns[npcId]
        if timeSince < COOLDOWN_DURATION then
            baseResistance = baseResistance + 30  -- Much harder if recent
        end
    end

    -- Check NPC's trust category
    if npcData and npcData.trustCategory then
        if npcData.trustCategory == "gang" then
            baseResistance = baseResistance + 20  -- Gang members are tough
        elseif npcData.trustCategory == "criminal" then
            baseResistance = baseResistance + 10
        end
    end

    return math.min(100, baseResistance)
end

-----------------------------------------------------------
-- PERFORM INTERROGATION
-----------------------------------------------------------
function PerformInterrogation(playerId, npcId, method)
    -- Validate player can interrogate
    local canDo, gradeOrError = CanInterrogate(playerId)
    if not canDo then
        return { success = false, error = gradeOrError }
    end

    local grade = gradeOrError
    local Player = QBCore.Functions.GetPlayer(playerId)
    local citizenid = Player.PlayerData.citizenid

    -- Get NPC data
    local npcData = nil
    for _, npc in pairs(Config.NPCs) do
        if npc.id == npcId then
            npcData = npc
            break
        end
    end

    if not npcData then
        return { success = false, error = "npc_not_found" }
    end

    -- Calculate success chance
    local resistance = GetNPCResistance(npcId, npcData)
    local gradeBonus = GRADE_BONUSES[grade] or 0

    -- Method modifiers
    local methodModifiers = {
        friendly = { bonus = -10, riskLevel = 0 },      -- Harder but no risk
        standard = { bonus = 0, riskLevel = 0 },        -- Baseline
        aggressive = { bonus = 20, riskLevel = 1 },     -- Easier but risky
        torture = { bonus = 40, riskLevel = 3 },        -- Much easier, very risky
    }

    local methodMod = methodModifiers[method] or methodModifiers.standard
    local successChance = 100 - resistance + gradeBonus + methodMod.bonus

    -- Roll for success
    local roll = math.random(1, 100)
    local success = roll <= successChance
    local broken = roll <= (successChance - 30)  -- Fully broken if big success

    -- Determine what intel they give up
    local intelRevealed = {}
    if success then
        intelRevealed = GenerateInterrogationIntel(npcId, npcData, broken)
    end

    -- Record the interrogation
    MySQL.insert([[
        INSERT INTO ai_npc_interrogations
        (npc_id, interrogator_citizenid, interrogator_job, method, resistance_level, intel_revealed, success, npc_broken)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        npcId,
        citizenid,
        Player.PlayerData.job.name,
        method,
        resistance,
        json.encode(intelRevealed),
        success,
        broken
    })

    -- Set cooldown
    interrogationCooldowns[npcId] = GetGameTimer()

    -- Handle risk (aggressive/torture methods might have consequences)
    local consequences = nil
    if methodMod.riskLevel > 0 then
        consequences = HandleInterrogationRisk(playerId, npcId, npcData, method, methodMod.riskLevel)
    end

    -- Add memory to NPC
    if success then
        exports['ai-npcs']:AddNPCMemoryAboutPlayer(playerId, npcId, 'negative',
            'Was interrogated by police and gave up information', 8, 30)
    else
        exports['ai-npcs']:AddNPCMemoryAboutPlayer(playerId, npcId, 'negative',
            'Was interrogated by police but said nothing', 5, 14)
    end

    if Config.Debug.enabled then
        print(("[AI NPCs] Interrogation: %s interrogated %s (%s) - %s (roll: %d, needed: %d)"):format(
            citizenid, npcId, method, success and "SUCCESS" or "FAILED", roll, successChance
        ))
    end

    return {
        success = success,
        broken = broken,
        intel = intelRevealed,
        resistance = resistance,
        consequences = consequences
    }
end

-----------------------------------------------------------
-- GENERATE INTEL FROM INTERROGATION
-----------------------------------------------------------
function GenerateInterrogationIntel(npcId, npcData, broken)
    local intel = {}

    -- Get rumors this NPC might know about
    -- Criminal NPCs know about other criminals
    if npcData.trustCategory == "criminal" or npcData.trustCategory == "gang" then
        -- Get recent player actions in the underground
        local rumors = MySQL.query.await([[
            SELECT DISTINCT citizenid, action_type, action_details
            FROM ai_npc_rumors
            WHERE visibility IN ('underground', 'street')
            AND expires_at > NOW()
            AND heat_level > 30
            ORDER BY heat_level DESC
            LIMIT ?
        ]], {broken and 5 or 2})

        for _, rumor in ipairs(rumors or {}) do
            local details = json.decode(rumor.action_details or "{}")
            table.insert(intel, {
                type = "player_activity",
                action = rumor.action_type,
                location = details.location,
                citizenid = broken and rumor.citizenid or nil  -- Only reveal identity if broken
            })
        end
    end

    -- Gang NPCs might reveal gang info
    local faction = exports['ai-npcs']:GetNPCFaction(npcId)
    if faction then
        -- Reveal some faction operations
        table.insert(intel, {
            type = "faction_info",
            faction = faction,
            info = broken and "Revealed stash locations and key members" or "Hinted at ongoing operations"
        })
    end

    -- If fully broken, might reveal referral chain
    if broken and npcData.trustCategory == "criminal" then
        table.insert(intel, {
            type = "contacts",
            info = "Gave up names of criminal contacts"
        })
    end

    return intel
end

-----------------------------------------------------------
-- HANDLE INTERROGATION RISK
-----------------------------------------------------------
function HandleInterrogationRisk(playerId, npcId, npcData, method, riskLevel)
    local consequences = {}

    -- Random chance of consequences based on risk level
    local roll = math.random(1, 100)

    if method == "aggressive" then
        if roll <= 20 then  -- 20% chance
            table.insert(consequences, {
                type = "complaint",
                description = "NPC filed a complaint - IA might investigate"
            })
        end
    elseif method == "torture" then
        if roll <= 40 then  -- 40% chance of serious consequences
            table.insert(consequences, {
                type = "evidence_tainted",
                description = "Any evidence obtained may be inadmissible"
            })
        end
        if roll <= 15 then  -- 15% chance
            table.insert(consequences, {
                type = "media_attention",
                description = "Word got out - media is asking questions"
            })
            -- Trigger global event
            TriggerEvent('ai-npcs:server:globalEvent', 'police_brutality', 7200)
        end
        if roll <= 5 then  -- 5% chance
            table.insert(consequences, {
                type = "federal_investigation",
                description = "FIB has opened an investigation"
            })
        end
    end

    -- Gang retaliation for interrogating their members
    local faction = exports['ai-npcs']:GetNPCFaction(npcId)
    if faction and riskLevel >= 2 then
        local Player = QBCore.Functions.GetPlayer(playerId)
        if Player then
            exports['ai-npcs']:AddFactionTrust(Player.PlayerData.citizenid, faction, -20, "interrogated_member")
            table.insert(consequences, {
                type = "faction_anger",
                faction = faction,
                description = faction .. " won't forget this"
            })
        end
    end

    return consequences
end

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
exports('CanInterrogate', CanInterrogate)
exports('PerformInterrogation', PerformInterrogation)
exports('GetNPCResistance', GetNPCResistance)

-----------------------------------------------------------
-- EVENTS
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:interrogate', function(npcId, method)
    local src = source
    local result = PerformInterrogation(src, npcId, method)

    TriggerClientEvent('ai-npcs:client:interrogationResult', src, result)
end)

print("^2[AI NPCs]^7 Interrogation system loaded")
