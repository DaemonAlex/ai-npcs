--[[
    NPC MOOD SYSTEM
    Dynamic mood based on weather, time, recent interactions, world events
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- In-memory mood states (refreshed periodically)
local npcMoods = {}  -- { [npcId] = { mood, factors, lastUpdate } }
local globalMoodModifiers = {}  -- Server-wide events affecting all NPCs

-- Mood levels and their effects
local MOODS = {
    furious = { openness = -50, patience = -30, price_modifier = 2.0, will_attack = true },
    angry = { openness = -30, patience = -20, price_modifier = 1.5, will_attack = false },
    irritated = { openness = -15, patience = -10, price_modifier = 1.2, will_attack = false },
    neutral = { openness = 0, patience = 0, price_modifier = 1.0, will_attack = false },
    relaxed = { openness = 10, patience = 10, price_modifier = 0.9, will_attack = false },
    happy = { openness = 20, patience = 15, price_modifier = 0.8, will_attack = false },
    generous = { openness = 30, patience = 20, price_modifier = 0.6, will_attack = false },
}

-- NPC personality affects base mood
local npcPersonalities = {
    -- Paranoid types start lower
    paranoid = { baseMood = -20, weatherSensitivity = 1.5, timeSensitivity = 1.0 },
    nervous = { baseMood = -10, weatherSensitivity = 1.2, timeSensitivity = 0.8 },

    -- Stable types
    professional = { baseMood = 0, weatherSensitivity = 0.5, timeSensitivity = 0.5 },
    friendly = { baseMood = 10, weatherSensitivity = 0.3, timeSensitivity = 0.3 },

    -- Variable types
    volatile = { baseMood = 0, weatherSensitivity = 2.0, timeSensitivity = 1.5 },
    drunk = { baseMood = math.random(-20, 20), weatherSensitivity = 0.2, timeSensitivity = 2.0 },
}

-----------------------------------------------------------
-- WEATHER MOOD EFFECTS
-----------------------------------------------------------
local weatherMoodEffects = {
    CLEAR = 10,
    EXTRASUNNY = 15,
    CLOUDS = 0,
    OVERCAST = -5,
    RAIN = -15,
    THUNDER = -25,
    CLEARING = 5,
    NEUTRAL = 0,
    SNOW = -10,
    BLIZZARD = -30,
    SNOWLIGHT = -5,
    FOGGY = -10,
    SMOG = -15,
}

-----------------------------------------------------------
-- TIME MOOD EFFECTS
-----------------------------------------------------------
local function GetTimeMoodEffect(hour)
    -- Most people are irritable early morning and late night
    if hour >= 6 and hour < 10 then
        return -5  -- Morning grogginess
    elseif hour >= 10 and hour < 12 then
        return 5   -- Mid-morning
    elseif hour >= 12 and hour < 14 then
        return 0   -- Lunch time neutral
    elseif hour >= 14 and hour < 18 then
        return 5   -- Afternoon
    elseif hour >= 18 and hour < 21 then
        return 10  -- Evening (relaxed)
    elseif hour >= 21 and hour < 24 then
        return 0   -- Night
    else
        return -10 -- Late night (2-6am)
    end
end

-----------------------------------------------------------
-- CALCULATE NPC MOOD
-----------------------------------------------------------
function CalculateNPCMood(npcId, npcData)
    local factors = {}
    local moodScore = 0

    -- 1. Base personality
    local personality = npcData.personality and npcData.personality.type or "professional"
    local personConfig = npcPersonalities[personality] or npcPersonalities.professional
    moodScore = moodScore + personConfig.baseMood
    factors.personality = personConfig.baseMood

    -- 2. Weather effect (would need client to report this, or use a weather sync resource)
    -- For now, use a placeholder or hook into your weather system
    local weather = GetCurrentWeather() or "CLEAR"
    local weatherEffect = (weatherMoodEffects[weather] or 0) * personConfig.weatherSensitivity
    moodScore = moodScore + weatherEffect
    factors.weather = weatherEffect

    -- 3. Time of day
    local hour = GetGameTimer and math.floor((GetGameTimer() / 1000 / 60) % 24) or 12
    -- In a real implementation, get from client or world state
    local timeEffect = GetTimeMoodEffect(hour) * personConfig.timeSensitivity
    moodScore = moodScore + timeEffect
    factors.time = timeEffect

    -- 4. Recent interaction memory (check last few interactions)
    local recentBad = GetRecentNegativeInteractions(npcId)
    if recentBad > 0 then
        local badEffect = recentBad * -10
        moodScore = moodScore + badEffect
        factors.recentBad = badEffect
    end

    -- 5. Global events
    for eventName, modifier in pairs(globalMoodModifiers) do
        moodScore = moodScore + modifier
        factors[eventName] = modifier
    end

    -- 6. NPC-specific temporary modifiers (e.g., just got paid, friend died, etc.)
    if npcMoods[npcId] and npcMoods[npcId].tempModifier then
        moodScore = moodScore + npcMoods[npcId].tempModifier
        factors.temporary = npcMoods[npcId].tempModifier
    end

    -- Clamp score
    moodScore = math.max(-100, math.min(100, moodScore))

    -- Convert score to mood name
    local moodName = "neutral"
    if moodScore <= -40 then moodName = "furious"
    elseif moodScore <= -25 then moodName = "angry"
    elseif moodScore <= -10 then moodName = "irritated"
    elseif moodScore <= 10 then moodName = "neutral"
    elseif moodScore <= 25 then moodName = "relaxed"
    elseif moodScore <= 40 then moodName = "happy"
    else moodName = "generous"
    end

    return {
        mood = moodName,
        score = moodScore,
        factors = factors,
        effects = MOODS[moodName]
    }
end

-----------------------------------------------------------
-- GET CURRENT WEATHER (placeholder - hook into your weather system)
-----------------------------------------------------------
function GetCurrentWeather()
    -- TODO: Hook into qb-weathersync or similar
    -- For now, return random weather weighted toward nice
    local weathers = {"CLEAR", "CLEAR", "EXTRASUNNY", "CLOUDS", "OVERCAST", "RAIN"}
    return weathers[math.random(#weathers)]
end

-----------------------------------------------------------
-- CHECK RECENT NEGATIVE INTERACTIONS
-----------------------------------------------------------
function GetRecentNegativeInteractions(npcId)
    -- Check memories for recent negative interactions in last hour
    local result = MySQL.scalar.await([[
        SELECT COUNT(*) FROM ai_npc_memories
        WHERE npc_id = ? AND memory_type = 'negative'
        AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)
    ]], {npcId})

    return result or 0
end

-----------------------------------------------------------
-- GET NPC MOOD (with caching)
-----------------------------------------------------------
function GetNPCMood(npcId, npcData)
    -- Check cache (valid for 5 minutes)
    if npcMoods[npcId] and npcMoods[npcId].lastUpdate then
        if os.time() - npcMoods[npcId].lastUpdate < 300 then
            return npcMoods[npcId]
        end
    end

    -- Calculate fresh mood
    local mood = CalculateNPCMood(npcId, npcData or {})
    mood.lastUpdate = os.time()

    -- Cache it
    npcMoods[npcId] = mood

    return mood
end

-----------------------------------------------------------
-- SET TEMPORARY MOOD MODIFIER
-----------------------------------------------------------
function SetNPCTempMood(npcId, modifier, duration)
    if not npcMoods[npcId] then npcMoods[npcId] = {} end
    npcMoods[npcId].tempModifier = modifier
    npcMoods[npcId].lastUpdate = nil  -- Force recalculation

    -- Clear after duration
    if duration then
        SetTimeout(duration * 1000, function()
            if npcMoods[npcId] then
                npcMoods[npcId].tempModifier = nil
                npcMoods[npcId].lastUpdate = nil
            end
        end)
    end
end

-----------------------------------------------------------
-- GLOBAL MOOD EVENTS
-----------------------------------------------------------
function SetGlobalMoodEvent(eventName, modifier, duration)
    globalMoodModifiers[eventName] = modifier

    -- Clear all NPC caches to recalculate
    for npcId, _ in pairs(npcMoods) do
        npcMoods[npcId].lastUpdate = nil
    end

    if duration then
        SetTimeout(duration * 1000, function()
            globalMoodModifiers[eventName] = nil
            for npcId, _ in pairs(npcMoods) do
                npcMoods[npcId].lastUpdate = nil
            end
        end)
    end

    if Config.Debug.enabled then
        print(("[AI NPCs] Global mood event: %s (%+d) for %ds"):format(eventName, modifier, duration or 0))
    end
end

-----------------------------------------------------------
-- BUILD MOOD CONTEXT FOR AI PROMPT
-----------------------------------------------------------
function BuildMoodContext(npcId, npcData)
    local mood = GetNPCMood(npcId, npcData)

    local context = "\n=== YOUR CURRENT MOOD ===\n"
    context = context .. string.format("You are feeling %s (mood score: %d)\n", mood.mood:upper(), mood.score)

    -- Explain mood factors
    if mood.factors.weather and mood.factors.weather ~= 0 then
        if mood.factors.weather > 0 then
            context = context .. "The nice weather is putting you in a better mood.\n"
        else
            context = context .. "This weather is getting on your nerves.\n"
        end
    end

    if mood.factors.recentBad then
        context = context .. "You're still irritated from a recent bad interaction.\n"
    end

    -- Behavior instructions
    context = context .. "\nBEHAVIOR based on mood:\n"
    if mood.mood == "furious" or mood.mood == "angry" then
        context = context .. "- Be short-tempered and aggressive\n"
        context = context .. "- Raise prices or refuse to deal\n"
        context = context .. "- Quick to threaten or end conversation\n"
    elseif mood.mood == "irritated" then
        context = context .. "- Be curt and impatient\n"
        context = context .. "- Less willing to negotiate\n"
    elseif mood.mood == "relaxed" or mood.mood == "happy" then
        context = context .. "- Be more talkative and friendly\n"
        context = context .. "- More willing to share info\n"
        context = context .. "- Might offer small discounts\n"
    elseif mood.mood == "generous" then
        context = context .. "- Be very helpful and open\n"
        context = context .. "- Share information freely\n"
        context = context .. "- Offer good deals\n"
    end

    return context, mood.effects
end

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
exports('GetNPCMood', GetNPCMood)
exports('SetNPCTempMood', SetNPCTempMood)
exports('SetGlobalMoodEvent', SetGlobalMoodEvent)
exports('BuildMoodContext', BuildMoodContext)

-----------------------------------------------------------
-- EXAMPLE GLOBAL EVENTS
-----------------------------------------------------------
-- These would be triggered by other scripts

-- Police raid happening? Everyone's on edge
RegisterNetEvent('ai-npcs:server:globalEvent', function(eventType, duration)
    local events = {
        police_raid = -30,      -- Everyone paranoid
        gang_war = -20,         -- Tension in the air
        holiday = 20,           -- Festive mood
        major_heist = -15,      -- Heat on the streets
        cop_killed = -25,       -- Serious tension
        good_weather = 10,      -- Nice day
    }

    local modifier = events[eventType]
    if modifier then
        SetGlobalMoodEvent(eventType, modifier, duration or 3600)
    end
end)

print("^2[AI NPCs]^7 NPC Mood system loaded")
