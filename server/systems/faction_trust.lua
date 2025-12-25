--[[
    FACTION TRUST SYSTEM
    Group-level reputation that affects all NPCs in a faction
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- In-memory cache for faction trust
local factionTrustCache = {}  -- { [citizenid] = { [faction] = data } }

-- Define which NPCs belong to which factions
local npcFactions = {
    -- Gangs
    vagos = {"el_guapo", "vagos_dealer", "vagos_lieutenant"},
    ballas = {"purple_k", "ballas_og", "ballas_dealer"},
    families = {"big_smoke_jr", "families_og", "grove_dealer"},
    lost_mc = {"chains", "lost_prospect", "lost_dealer"},

    -- Criminal orgs
    cartel = {"rico", "cartel_soldier", "cartel_boss"},
    mafia = {"the_architect", "charlie_fence", "viktor"},
    triads = {"triad_boss", "triad_enforcer"},

    -- Legitimate
    legal = {"margaret_chen", "vanessa_sterling", "captain_marcus"},
    medical = {"dr_hartman", "nurse_jackie"},
    law = {"attorney_goldstein"},

    -- Underground network
    underground = {"sketchy_mike", "smokey", "walter", "crazy_earl", "jackie"},
}

-- Reverse lookup: NPC -> Faction
local npcToFaction = {}
for faction, npcs in pairs(npcFactions) do
    for _, npcId in ipairs(npcs) do
        npcToFaction[npcId] = faction
    end
end

-- Faction relationships (how factions view each other)
local factionRelations = {
    vagos = { ballas = "enemy", families = "rival", lost_mc = "neutral", cartel = "ally" },
    ballas = { vagos = "enemy", families = "enemy", lost_mc = "neutral", cartel = "neutral" },
    families = { vagos = "rival", ballas = "enemy", lost_mc = "neutral", underground = "friendly" },
    lost_mc = { vagos = "neutral", ballas = "neutral", families = "neutral", underground = "friendly" },
    cartel = { vagos = "ally", mafia = "rival", underground = "friendly" },
    mafia = { cartel = "rival", underground = "friendly", legal = "friendly" },
    underground = { families = "friendly", lost_mc = "friendly", mafia = "friendly", cartel = "friendly" },
}

-----------------------------------------------------------
-- GET FACTION FOR NPC
-----------------------------------------------------------
function GetNPCFaction(npcId)
    return npcToFaction[npcId]
end

-----------------------------------------------------------
-- GET FACTION TRUST
-----------------------------------------------------------
function GetFactionTrust(citizenid, faction)
    -- Check cache
    if factionTrustCache[citizenid] and factionTrustCache[citizenid][faction] then
        local cached = factionTrustCache[citizenid][faction]
        if os.time() - cached.time < 300 then  -- 5 min cache
            return cached.data
        end
    end

    local result = MySQL.single.await([[
        SELECT * FROM ai_npc_faction_trust
        WHERE citizenid = ? AND faction = ?
    ]], {citizenid, faction})

    local data = result or {
        trust_value = 0,
        reputation = "unknown",
        kills_for = 0,
        kills_against = 0,
        missions_completed = 0
    }

    -- Cache it
    if not factionTrustCache[citizenid] then factionTrustCache[citizenid] = {} end
    factionTrustCache[citizenid][faction] = { time = os.time(), data = data }

    return data
end

-----------------------------------------------------------
-- UPDATE FACTION TRUST
-----------------------------------------------------------
function AddFactionTrust(citizenid, faction, amount, reason)
    local current = GetFactionTrust(citizenid, faction)
    local newValue = math.max(-100, math.min(100, (current.trust_value or 0) + amount))

    -- Determine new reputation based on trust
    local reputation = "unknown"
    if newValue <= -50 then reputation = "enemy"
    elseif newValue <= -10 then reputation = "hostile"
    elseif newValue <= 10 then reputation = "neutral"
    elseif newValue <= 40 then reputation = "friendly"
    elseif newValue <= 70 then reputation = "ally"
    else reputation = "blood"
    end

    MySQL.insert([[
        INSERT INTO ai_npc_faction_trust (citizenid, faction, trust_value, reputation, missions_completed)
        VALUES (?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE
            trust_value = ?,
            reputation = ?,
            missions_completed = missions_completed + 1,
            last_interaction = CURRENT_TIMESTAMP
    ]], {citizenid, faction, newValue, reputation, newValue, reputation})

    -- Clear cache
    if factionTrustCache[citizenid] then
        factionTrustCache[citizenid][faction] = nil
    end

    -- Ripple effect: Affect allied/enemy factions
    if factionRelations[faction] then
        for otherFaction, relation in pairs(factionRelations[faction]) do
            local modifier = 0
            if relation == "ally" then modifier = 0.5
            elseif relation == "friendly" then modifier = 0.25
            elseif relation == "rival" then modifier = -0.25
            elseif relation == "enemy" then modifier = -0.5
            end

            if modifier ~= 0 then
                local rippleAmount = math.floor(amount * modifier)
                if rippleAmount ~= 0 then
                    -- Recursive but limited to direct relationships
                    MySQL.insert([[
                        INSERT INTO ai_npc_faction_trust (citizenid, faction, trust_value, reputation)
                        VALUES (?, ?, ?, 'neutral')
                        ON DUPLICATE KEY UPDATE
                            trust_value = trust_value + ?,
                            last_interaction = CURRENT_TIMESTAMP
                    ]], {citizenid, otherFaction, rippleAmount, rippleAmount})

                    if factionTrustCache[citizenid] then
                        factionTrustCache[citizenid][otherFaction] = nil
                    end
                end
            end
        end
    end

    if Config.Debug.enabled then
        print(("[AI NPCs] Faction trust: %s %s%d with %s -> %d (%s)"):format(
            citizenid, amount >= 0 and "+" or "", amount, faction, newValue, reputation
        ))
    end

    return newValue, reputation
end

-----------------------------------------------------------
-- RECORD FACTION KILLS
-----------------------------------------------------------
function RecordFactionKill(killerCitizenid, victimFaction, wasFor)
    local column = wasFor and "kills_for" or "kills_against"
    local trustChange = wasFor and 15 or -25

    MySQL.update([[
        UPDATE ai_npc_faction_trust
        SET ]] .. column .. [[ = ]] .. column .. [[ + 1
        WHERE citizenid = ? AND faction = ?
    ]], {killerCitizenid, victimFaction})

    AddFactionTrust(killerCitizenid, victimFaction, trustChange, wasFor and "kill_for" or "kill_against")
end

-----------------------------------------------------------
-- GET NPC'S VIEW OF PLAYER (considering faction)
-----------------------------------------------------------
function GetNPCFactionView(npcId, citizenid)
    local faction = GetNPCFaction(npcId)
    if not faction then return nil end

    local factionData = GetFactionTrust(citizenid, faction)

    -- Also check enemy factions
    local enemyRep = nil
    if factionRelations[faction] then
        for otherFaction, relation in pairs(factionRelations[faction]) do
            if relation == "enemy" then
                local otherData = GetFactionTrust(citizenid, otherFaction)
                if otherData.reputation == "ally" or otherData.reputation == "blood" then
                    enemyRep = { faction = otherFaction, rep = otherData.reputation }
                    break
                end
            end
        end
    end

    return {
        faction = faction,
        trust = factionData.trust_value,
        reputation = factionData.reputation,
        kills_for = factionData.kills_for,
        kills_against = factionData.kills_against,
        missions = factionData.missions_completed,
        enemyAffiliation = enemyRep  -- Player is allied with our enemy
    }
end

-----------------------------------------------------------
-- BUILD FACTION CONTEXT FOR AI PROMPT
-----------------------------------------------------------
function BuildFactionContext(npcId, citizenid, playerName)
    local view = GetNPCFactionView(npcId, citizenid)
    if not view then return "" end

    local context = string.format("\n=== FACTION STANDING ===\n")
    context = context .. string.format("Faction: %s\n", view.faction:upper())
    context = context .. string.format("Player reputation with your faction: %s (trust: %d)\n",
        view.reputation, view.trust)

    if view.kills_for > 0 then
        context = context .. string.format("✓ %s has killed %d enemies FOR your faction\n",
            playerName, view.kills_for)
    end

    if view.kills_against > 0 then
        context = context .. string.format("⚠ WARNING: %s has killed %d of YOUR faction members!\n",
            playerName, view.kills_against)
    end

    if view.enemyAffiliation then
        context = context .. string.format("⚠ ALERT: %s is a %s of the %s - YOUR ENEMIES!\n",
            playerName, view.enemyAffiliation.rep, view.enemyAffiliation.faction:upper())
    end

    -- Behavior instructions based on reputation
    if view.reputation == "enemy" then
        context = context .. "BEHAVIOR: Treat them with hostility. They are an enemy. Do not help them. Consider them a threat.\n"
    elseif view.reputation == "hostile" then
        context = context .. "BEHAVIOR: Be cold and unwelcoming. They have wronged your faction. Trust nothing they say.\n"
    elseif view.reputation == "neutral" or view.reputation == "unknown" then
        context = context .. "BEHAVIOR: Treat them cautiously. They haven't proven themselves to your faction yet.\n"
    elseif view.reputation == "friendly" then
        context = context .. "BEHAVIOR: Be welcoming. They're on good terms with your faction. Offer reasonable help.\n"
    elseif view.reputation == "ally" then
        context = context .. "BEHAVIOR: They are a trusted ally. Offer significant help and intel. Warn them of dangers.\n"
    elseif view.reputation == "blood" then
        context = context .. "BEHAVIOR: They are FAMILY. Die for them. Share everything. They have bled for you.\n"
    end

    return context
end

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
exports('GetNPCFaction', GetNPCFaction)
exports('GetFactionTrust', GetFactionTrust)
exports('AddFactionTrust', AddFactionTrust)
exports('RecordFactionKill', RecordFactionKill)
exports('GetNPCFactionView', GetNPCFactionView)
exports('BuildFactionContext', BuildFactionContext)

-----------------------------------------------------------
-- EVENTS
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:factionKill', function(victimFaction, wasOrdered)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        RecordFactionKill(Player.PlayerData.citizenid, victimFaction, wasOrdered)
    end
end)

print("^2[AI NPCs]^7 Faction Trust system loaded")
