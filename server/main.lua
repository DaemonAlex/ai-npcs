local QBCore = exports['qb-core']:GetCoreObject()

-- Data stores (cache - synced with database)
local activeConversations = {}
local playerTrustCache = {}   -- In-memory cache, synced with DB
local intelCooldowns = {}     -- { [identifier] = { [topic] = lastAccessTime } }
local audioCache = {}
local cacheSize = 0

-- State locking: Track which player is talking to which NPC
local npcLocks = {}  -- { [npcId] = playerId }

-- Batch trust saving: Queue changes and commit periodically
local trustUpdateQueue = {}  -- { { identifier, trustCategory, npcId, value }, ... }
local TRUST_SAVE_INTERVAL = 300000  -- 5 minutes

-----------------------------------------------------------
-- STARTUP
-----------------------------------------------------------
CreateThread(function()
    print("^2[AI NPCs]^7 Server initialized - Advanced conversation system loaded")
    print("^2[AI NPCs]^7 Trust system: " .. (Config.Trust.enabled and "ENABLED" or "DISABLED"))
    print("^2[AI NPCs]^7 Database persistence: ENABLED (batch mode)")
    print("^2[AI NPCs]^7 Player context: ENABLED")
end)

-----------------------------------------------------------
-- NPC STATE LOCKING
-----------------------------------------------------------
function LockNPCForPlayer(npcId, playerId)
    if npcLocks[npcId] and npcLocks[npcId] ~= playerId then
        return false  -- NPC is locked by another player
    end
    npcLocks[npcId] = playerId
    return true
end

function UnlockNPC(npcId, playerId)
    if npcLocks[npcId] == playerId then
        npcLocks[npcId] = nil
    end
end

function IsNPCLockedByOther(npcId, playerId)
    return npcLocks[npcId] and npcLocks[npcId] ~= playerId
end

function GetNPCLockOwner(npcId)
    return npcLocks[npcId]
end

-----------------------------------------------------------
-- RANGE VALIDATION HELPER
-----------------------------------------------------------
local INTERACTION_RANGE = 5.0  -- Max distance for interactions

function IsPlayerNearNPC(playerId, npcId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    -- Get NPC coordinates from config
    local npc = GetNPCById(npcId)
    if not npc then return false end

    -- Get player coordinates
    local playerPed = GetPlayerPed(playerId)
    if not playerPed or playerPed == 0 then return false end

    local playerCoords = GetEntityCoords(playerPed)
    local npcCoords = npc.homeLocation

    -- Calculate distance (use vector if available, else manual)
    local distance = #(vector3(playerCoords.x, playerCoords.y, playerCoords.z) -
                       vector3(npcCoords.x, npcCoords.y, npcCoords.z))

    return distance <= INTERACTION_RANGE
end

-- Extended range check for quest interactions (player might be further away for deliveries)
function IsPlayerInQuestRange(playerId, npcId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    local npc = GetNPCById(npcId)
    if not npc then return false end

    local playerPed = GetPlayerPed(playerId)
    if not playerPed or playerPed == 0 then return false end

    local playerCoords = GetEntityCoords(playerPed)
    local npcCoords = npc.homeLocation

    local distance = #(vector3(playerCoords.x, playerCoords.y, playerCoords.z) -
                       vector3(npcCoords.x, npcCoords.y, npcCoords.z))

    return distance <= 10.0  -- Slightly larger range for quest completion
end

-----------------------------------------------------------
-- DATABASE: TRUST SYSTEM
-----------------------------------------------------------

-- Get trust from database (with caching)
function GetPlayerTrust(identifier, trustCategory, npcId)
    -- Check cache first
    if playerTrustCache[identifier] and
       playerTrustCache[identifier][trustCategory] and
       playerTrustCache[identifier][trustCategory][npcId] then
        return playerTrustCache[identifier][trustCategory][npcId]
    end

    -- Query database
    local result = MySQL.scalar.await([[
        SELECT trust_value FROM ai_npc_trust
        WHERE citizenid = ? AND npc_id = ? AND trust_category = ?
    ]], {identifier, npcId, trustCategory})

    local trustValue = result or 0

    -- Update cache
    if not playerTrustCache[identifier] then playerTrustCache[identifier] = {} end
    if not playerTrustCache[identifier][trustCategory] then playerTrustCache[identifier][trustCategory] = {} end
    playerTrustCache[identifier][trustCategory][npcId] = trustValue

    return trustValue
end

-- Add trust (cached locally, batch saved to DB)
function AddPlayerTrust(identifier, trustCategory, npcId, amount)
    local current = GetPlayerTrust(identifier, trustCategory, npcId)
    local newValue = math.min(100, current + amount)

    -- Update cache immediately
    if not playerTrustCache[identifier] then playerTrustCache[identifier] = {} end
    if not playerTrustCache[identifier][trustCategory] then playerTrustCache[identifier][trustCategory] = {} end
    playerTrustCache[identifier][trustCategory][npcId] = newValue

    -- Queue for batch save (overwrites previous queued value for same key)
    local queueKey = identifier .. "_" .. trustCategory .. "_" .. npcId
    trustUpdateQueue[queueKey] = {
        identifier = identifier,
        trustCategory = trustCategory,
        npcId = npcId,
        value = newValue
    }

    if Config.Debug.enabled then
        print(("[AI NPCs] Trust queued: %s -> %s (+%d) = %d"):format(
            identifier, npcId, amount, newValue
        ))
    end
end

-- Force immediate save (called on player disconnect, conversation end, etc.)
function FlushTrustForPlayer(identifier)
    local savedCount = 0
    for queueKey, data in pairs(trustUpdateQueue) do
        if data.identifier == identifier then
            MySQL.insert([[
                INSERT INTO ai_npc_trust (citizenid, npc_id, trust_category, trust_value, conversation_count)
                VALUES (?, ?, ?, ?, 1)
                ON DUPLICATE KEY UPDATE
                    trust_value = ?,
                    conversation_count = conversation_count + 1,
                    last_interaction = CURRENT_TIMESTAMP
            ]], {data.identifier, data.npcId, data.trustCategory, data.value, data.value})
            trustUpdateQueue[queueKey] = nil
            savedCount = savedCount + 1
        end
    end
    if savedCount > 0 and Config.Debug.enabled then
        print(("[AI NPCs] Flushed %d trust updates for %s"):format(savedCount, identifier))
    end
end

-- Batch save all pending trust updates
function FlushAllTrustUpdates()
    local count = 0
    for queueKey, data in pairs(trustUpdateQueue) do
        MySQL.insert([[
            INSERT INTO ai_npc_trust (citizenid, npc_id, trust_category, trust_value, conversation_count)
            VALUES (?, ?, ?, ?, 1)
            ON DUPLICATE KEY UPDATE
                trust_value = ?,
                conversation_count = conversation_count + 1,
                last_interaction = CURRENT_TIMESTAMP
        ]], {data.identifier, data.npcId, data.trustCategory, data.value, data.value})
        count = count + 1
    end
    trustUpdateQueue = {}
    if count > 0 then
        print(("[AI NPCs] Batch saved %d trust updates"):format(count))
    end
end

-- Periodic batch save thread
CreateThread(function()
    while true do
        Wait(TRUST_SAVE_INTERVAL)
        FlushAllTrustUpdates()
    end
end)

-- Save on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print("[AI NPCs] Saving all pending trust updates...")
        FlushAllTrustUpdates()
    end
end)

-- Set trust directly (for admin/quest rewards)
function SetPlayerTrust(identifier, trustCategory, npcId, value)
    value = math.max(0, math.min(100, value))

    -- Update cache
    if not playerTrustCache[identifier] then playerTrustCache[identifier] = {} end
    if not playerTrustCache[identifier][trustCategory] then playerTrustCache[identifier][trustCategory] = {} end
    playerTrustCache[identifier][trustCategory][npcId] = value

    -- Upsert to database
    MySQL.insert.await([[
        INSERT INTO ai_npc_trust (citizenid, npc_id, trust_category, trust_value)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE trust_value = ?, last_interaction = CURRENT_TIMESTAMP
    ]], {identifier, npcId, trustCategory, value, value})
end

function GetTrustLevel(trustValue)
    for _, level in ipairs(Config.Trust.levels) do
        if trustValue >= level.minTrust and trustValue <= level.maxTrust then
            return level.name
        end
    end
    return "Stranger"
end

-----------------------------------------------------------
-- DATABASE: QUEST SYSTEM
-----------------------------------------------------------

-- Offer a quest to a player
function OfferQuest(identifier, npcId, questId, questType, questData)
    MySQL.insert.await([[
        INSERT INTO ai_npc_quests (citizenid, npc_id, quest_id, quest_type, status, quest_data)
        VALUES (?, ?, ?, ?, 'offered', ?)
        ON DUPLICATE KEY UPDATE status = 'offered', quest_data = ?, offered_at = CURRENT_TIMESTAMP
    ]], {identifier, npcId, questId, questType, json.encode(questData), json.encode(questData)})
end

-- Accept a quest
function AcceptQuest(identifier, npcId, questId)
    MySQL.update.await([[
        UPDATE ai_npc_quests SET status = 'accepted'
        WHERE citizenid = ? AND npc_id = ? AND quest_id = ?
    ]], {identifier, npcId, questId})
end

-- Complete a quest
function CompleteQuest(identifier, npcId, questId, trustReward)
    MySQL.update.await([[
        UPDATE ai_npc_quests SET status = 'completed', completed_at = CURRENT_TIMESTAMP
        WHERE citizenid = ? AND npc_id = ? AND quest_id = ?
    ]], {identifier, npcId, questId})

    -- Award trust if specified
    if trustReward and trustReward > 0 then
        local npc = GetNPCById(npcId)
        if npc then
            AddPlayerTrust(identifier, npc.trustCategory, npcId, trustReward)
        end
    end
end

-- Get player's quest status with an NPC
function GetQuestStatus(identifier, npcId, questId)
    local result = MySQL.scalar.await([[
        SELECT status FROM ai_npc_quests
        WHERE citizenid = ? AND npc_id = ? AND quest_id = ?
    ]], {identifier, npcId, questId})
    return result
end

-- Get all active quests for a player
function GetPlayerActiveQuests(identifier)
    local results = MySQL.query.await([[
        SELECT * FROM ai_npc_quests
        WHERE citizenid = ? AND status IN ('offered', 'accepted', 'in_progress')
    ]], {identifier})
    return results or {}
end

-----------------------------------------------------------
-- DATABASE: REFERRAL SYSTEM
-----------------------------------------------------------

-- Create a referral (NPC A vouches for player to NPC B)
function CreateReferral(identifier, fromNpcId, toNpcId, referralType)
    MySQL.insert.await([[
        INSERT INTO ai_npc_referrals (citizenid, from_npc_id, to_npc_id, referral_type)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE referral_type = ?, created_at = CURRENT_TIMESTAMP
    ]], {identifier, fromNpcId, toNpcId, referralType or 'standard', referralType or 'standard'})
end

-- Check if player has a referral to an NPC
function HasReferral(identifier, toNpcId)
    local result = MySQL.scalar.await([[
        SELECT COUNT(*) FROM ai_npc_referrals
        WHERE citizenid = ? AND to_npc_id = ? AND used = FALSE
    ]], {identifier, toNpcId})
    return (result or 0) > 0
end

-- Get who referred the player
function GetReferrer(identifier, toNpcId)
    local result = MySQL.scalar.await([[
        SELECT from_npc_id FROM ai_npc_referrals
        WHERE citizenid = ? AND to_npc_id = ? AND used = FALSE
        ORDER BY created_at DESC LIMIT 1
    ]], {identifier, toNpcId})
    return result
end

-- Mark referral as used
function UseReferral(identifier, toNpcId)
    MySQL.update.await([[
        UPDATE ai_npc_referrals SET used = TRUE
        WHERE citizenid = ? AND to_npc_id = ? AND used = FALSE
    ]], {identifier, toNpcId})
end

-----------------------------------------------------------
-- DATABASE: DEBT SYSTEM
-----------------------------------------------------------

-- Create a debt (player owes NPC)
function CreateDebt(identifier, npcId, debtType, amount, description)
    MySQL.insert.await([[
        INSERT INTO ai_npc_debts (citizenid, npc_id, debt_type, amount, description, status)
        VALUES (?, ?, ?, ?, ?, 'pending')
    ]], {identifier, npcId, debtType, amount, description})
end

-- Get player's debts to an NPC
function GetPlayerDebts(identifier, npcId)
    local results = MySQL.query.await([[
        SELECT * FROM ai_npc_debts
        WHERE citizenid = ? AND npc_id = ? AND status = 'pending'
    ]], {identifier, npcId})
    return results or {}
end

-- Pay off a debt
function PayDebt(identifier, debtId)
    MySQL.update.await([[
        UPDATE ai_npc_debts SET status = 'paid', paid_at = CURRENT_TIMESTAMP
        WHERE id = ? AND citizenid = ?
    ]], {debtId, identifier})
end

-- Check total debt to NPC
function GetTotalDebt(identifier, npcId)
    local result = MySQL.scalar.await([[
        SELECT COALESCE(SUM(amount), 0) FROM ai_npc_debts
        WHERE citizenid = ? AND npc_id = ? AND status = 'pending' AND debt_type = 'money'
    ]], {identifier, npcId})
    return result or 0
end

-----------------------------------------------------------
-- DATABASE: MEMORY SYSTEM (NPCs remember things)
-----------------------------------------------------------

-- Add a memory about a player
function AddNPCMemory(identifier, npcId, memoryType, memoryText, importance, expiresInDays)
    local expiresAt = nil
    if expiresInDays then
        expiresAt = os.date("%Y-%m-%d %H:%M:%S", os.time() + (expiresInDays * 86400))
    end

    MySQL.insert.await([[
        INSERT INTO ai_npc_memories (citizenid, npc_id, memory_type, memory_text, importance, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], {identifier, npcId, memoryType, memoryText, importance or 5, expiresAt})
end

-- Get NPC's memories about a player
function GetNPCMemories(identifier, npcId, limit)
    local results = MySQL.query.await([[
        SELECT * FROM ai_npc_memories
        WHERE citizenid = ? AND npc_id = ?
        AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP)
        ORDER BY importance DESC, created_at DESC
        LIMIT ?
    ]], {identifier, npcId, limit or 5})
    return results or {}
end

-----------------------------------------------------------
-- DATABASE: INTEL COOLDOWNS
-----------------------------------------------------------

-- Check if intel is on cooldown
function CanAccessIntel(identifier, topic, tier)
    local cooldown = Config.Intel.cooldowns[tier] or 600000
    local cooldownSeconds = cooldown / 1000

    local result = MySQL.scalar.await([[
        SELECT TIMESTAMPDIFF(SECOND, accessed_at, CURRENT_TIMESTAMP)
        FROM ai_npc_intel_cooldowns
        WHERE citizenid = ? AND topic = ?
    ]], {identifier, topic})

    if not result then return true end
    return result >= cooldownSeconds
end

-- Record intel access
function RecordIntelAccess(identifier, topic, tier)
    MySQL.insert.await([[
        INSERT INTO ai_npc_intel_cooldowns (citizenid, topic, tier, accessed_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE tier = ?, accessed_at = CURRENT_TIMESTAMP
    ]], {identifier, topic, tier, tier})
end

-----------------------------------------------------------
-- HELPER: Get NPC by ID
-----------------------------------------------------------
function GetNPCById(npcId)
    for _, npc in pairs(Config.NPCs) do
        if npc.id == npcId then
            return npc
        end
    end
    return nil
end

-----------------------------------------------------------
-- PLAYER CONTEXT
-----------------------------------------------------------
function GetPlayerContext(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return nil end

    local context = {
        name = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname,
        job = Player.PlayerData.job.name,
        jobLabel = Player.PlayerData.job.label,
        jobGrade = Player.PlayerData.job.grade.level,
        isCop = false,
        cash = Player.PlayerData.money.cash,
        hasDrugs = false,
        hasWeapons = false,
        hasCrimeTools = false,
        hasValuables = false,
        gang = Player.PlayerData.gang and Player.PlayerData.gang.name or nil,
        metadata = Player.PlayerData.metadata or {}
    }

    -- Check if cop
    for _, copJob in ipairs(Config.PlayerContext.suspiciousJobs) do
        if context.job == copJob then
            context.isCop = true
            break
        end
    end

    -- Check inventory for special items
    local items = Player.PlayerData.items
    if items then
        for _, item in pairs(items) do
            if item and item.name then
                -- Check drugs
                for _, drug in ipairs(Config.PlayerContext.specialItems.drugs) do
                    if item.name == drug then
                        context.hasDrugs = true
                        break
                    end
                end
                -- Check weapons
                for _, weapon in ipairs(Config.PlayerContext.specialItems.weapons) do
                    if item.name == weapon then
                        context.hasWeapons = true
                        break
                    end
                end
                -- Check crime tools
                for _, tool in ipairs(Config.PlayerContext.specialItems.crimeTools) do
                    if item.name == tool then
                        context.hasCrimeTools = true
                        break
                    end
                end
                -- Check valuables
                for _, valuable in ipairs(Config.PlayerContext.specialItems.valuables) do
                    if item.name == valuable then
                        context.hasValuables = true
                        break
                    end
                end
            end
        end
    end

    if Config.Debug.printPlayerContext then
        print(("[AI NPCs] Player context for %s:"):format(playerId))
        print(json.encode(context, { indent = true }))
    end

    return context
end

-----------------------------------------------------------
-- INTEL SYSTEM
-----------------------------------------------------------
function CanAccessIntel(identifier, topic, tier)
    if not intelCooldowns[identifier] then return true end
    if not intelCooldowns[identifier][topic] then return true end

    local cooldown = Config.Intel.cooldowns[tier] or 600000
    local lastAccess = intelCooldowns[identifier][topic]
    local now = GetGameTimer()

    return (now - lastAccess) >= cooldown
end

function RecordIntelAccess(identifier, topic)
    if not intelCooldowns[identifier] then
        intelCooldowns[identifier] = {}
    end
    intelCooldowns[identifier][topic] = GetGameTimer()
end

function GetIntelPrice(tier)
    local priceRange = Config.Intel.prices[tier]
    if not priceRange then return 0 end
    return math.random(priceRange.min, priceRange.max)
end

-----------------------------------------------------------
-- CONVERSATION MANAGEMENT
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:startConversation', function(npcId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Check if NPC is already in conversation with someone else
    if IsNPCLockedByOther(npcId, src) then
        local owner = GetNPCLockOwner(npcId)
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Busy',
            description = 'This person is already talking to someone else',
            type = 'error'
        })
        print(("[AI NPCs] Player %s tried to talk to %s but it's locked by %s"):format(src, npcId, owner))
        return
    end

    -- Lock the NPC for this player
    if not LockNPCForPlayer(npcId, src) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Busy',
            description = 'This person is occupied',
            type = 'error'
        })
        return
    end

    -- Find NPC config
    local npc = nil
    for _, npcData in pairs(Config.NPCs) do
        if npcData.id == npcId then
            npc = npcData
            break
        end
    end

    if not npc then
        UnlockNPC(npcId, src)  -- Release lock if NPC not found
        print(("[AI NPCs] NPC not found: %s"):format(npcId))
        return
    end

    -- Get player context and trust
    local identifier = Player.PlayerData.citizenid
    local playerContext = GetPlayerContext(src)
    local trustValue = GetPlayerTrust(identifier, npc.trustCategory, npcId)
    local trustLevel = GetTrustLevel(trustValue)

    -- Initialize conversation
    activeConversations[src] = {
        npcId = npcId,
        npc = npc,
        messageCount = 0,
        lastActivity = GetGameTimer(),
        conversationHistory = {},
        playerContext = playerContext,
        identifier = identifier,
        trustValue = trustValue,
        trustLevel = trustLevel,
        paymentMade = 0
    }

    -- Build contextual greeting
    local greeting = BuildContextualGreeting(npc, playerContext, trustLevel)

    -- Send greeting
    TriggerClientEvent('ai-npcs:client:receiveMessage', src, greeting, npc.id)

    -- Add trust for visiting
    if Config.Trust.enabled then
        AddPlayerTrust(identifier, npc.trustCategory, npcId, Config.Trust.earnRates.repeatVisit)
    end

    print(("[AI NPCs] Started conversation: Player %s (%s) with %s (Trust: %s/%d)"):format(
        src, trustLevel, npc.name, trustLevel, trustValue
    ))
end)

function BuildContextualGreeting(npc, playerContext, trustLevel)
    local greeting = npc.personality.greeting

    -- Modify greeting based on context
    if playerContext.isCop then
        local reaction = npc.contextReactions.copReaction
        if reaction == "extremely_suspicious" then
            greeting = "*eyes you warily* ...Something I can help you with, officer?"
        elseif reaction == "hostile_dismissive" then
            greeting = "*turns away* I got nothing to say to you, pig."
        elseif reaction == "paranoid_shutdown" then
            greeting = "*becomes very still* I think you have the wrong person."
        elseif reaction == "professional_denial" then
            greeting = "Good day, officer. I'm just a simple antiques dealer. How may I help?"
        end
    elseif trustLevel == "Inner Circle" then
        greeting = "*nods with respect* Good to see you again, friend. What do you need?"
    elseif trustLevel == "Trusted" then
        greeting = "*relaxes slightly* Ah, you're back. What's on your mind?"
    end

    return greeting
end

RegisterNetEvent('ai-npcs:server:sendMessage', function(message, paymentOffer)
    local src = source
    local conversation = activeConversations[src]

    if not conversation then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Error',
            description = 'No active conversation',
            type = 'error'
        })
        return
    end

    -- Handle payment
    if paymentOffer and paymentOffer > 0 then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player and Player.PlayerData.money.cash >= paymentOffer then
            Player.Functions.RemoveMoney('cash', paymentOffer, 'npc-intel-payment')
            conversation.paymentMade = conversation.paymentMade + paymentOffer
            AddPlayerTrust(conversation.identifier, conversation.npc.trustCategory,
                conversation.npcId, Config.Trust.earnRates.payment)

            TriggerClientEvent('ox_lib:notify', src, {
                title = conversation.npc.name,
                description = ("Received $%d"):format(paymentOffer),
                type = 'success'
            })
        end
    end

    -- Update activity
    conversation.lastActivity = GetGameTimer()
    conversation.messageCount = conversation.messageCount + 1

    -- Check conversation limits
    if conversation.messageCount > Config.Interaction.maxConversationLength then
        local endMsg = "I've said enough. Come back another time..."
        TriggerClientEvent('ai-npcs:client:endConversation', src, endMsg)
        activeConversations[src] = nil
        return
    end

    -- Add to conversation history
    table.insert(conversation.conversationHistory, {
        role = "user",
        content = message
    })

    -- Generate AI response with full context
    GenerateAIResponse(src, conversation, message)
end)

RegisterNetEvent('ai-npcs:server:endConversation', function()
    local src = source
    local conversation = activeConversations[src]

    if conversation then
        -- Add trust for completing conversation
        if Config.Trust.enabled and conversation.messageCount >= 3 then
            AddPlayerTrust(conversation.identifier, conversation.npc.trustCategory,
                conversation.npcId, Config.Trust.earnRates.conversation)
        end

        -- Flush trust updates immediately for this player
        FlushTrustForPlayer(conversation.identifier)

        -- Unlock the NPC so others can talk
        UnlockNPC(conversation.npcId, src)
    end

    activeConversations[src] = nil
    print(("[AI NPCs] Ended conversation for player %s"):format(src))
end)

-- Also unlock on player disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local conversation = activeConversations[src]

    if conversation then
        FlushTrustForPlayer(conversation.identifier)
        UnlockNPC(conversation.npcId, src)
        activeConversations[src] = nil
        print(("[AI NPCs] Player %s disconnected, cleaning up conversation"):format(src))
    end

    -- Also clean up any stale locks from this player
    for npcId, lockOwner in pairs(npcLocks) do
        if lockOwner == src then
            npcLocks[npcId] = nil
        end
    end
end)

-----------------------------------------------------------
-- INTEL REQUEST HANDLING
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:requestIntel', function(topic, tier)
    local src = source
    local conversation = activeConversations[src]

    if not conversation then return end

    local npc = conversation.npc
    local identifier = conversation.identifier

    -- Check trust requirement
    local trustRequired = Config.Intel.trustRequirements[tier] or 0
    if conversation.trustValue < trustRequired then
        TriggerClientEvent('ai-npcs:client:receiveMessage', src,
            "*shakes head* I don't know you well enough to talk about that...", npc.id)
        return
    end

    -- Check cooldown
    if not CanAccessIntel(identifier, topic, tier) then
        TriggerClientEvent('ai-npcs:client:receiveMessage', src,
            "I already told you what I know about that. Come back later.", npc.id)
        return
    end

    -- Get price
    local price = GetIntelPrice(tier)

    -- Check if player paid enough
    if tier ~= "rumors" and conversation.paymentMade < price then
        TriggerClientEvent('ai-npcs:client:receiveMessage', src,
            ("*rubs fingers together* That kind of information costs money... About $%d."):format(price), npc.id)
        TriggerClientEvent('ai-npcs:client:showPaymentPrompt', src, price, topic, tier)
        return
    end

    -- Record access
    RecordIntelAccess(identifier, topic)

    -- Add to conversation for AI to reference
    conversation.requestedIntel = { topic = topic, tier = tier }
end)

-----------------------------------------------------------
-- CONVERSATION CLEANUP
-----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(60000)
        local currentTime = GetGameTimer()

        for playerId, conversation in pairs(activeConversations) do
            if currentTime - conversation.lastActivity > Config.Interaction.idleTimeout then
                TriggerClientEvent('ai-npcs:client:endConversation', playerId,
                    "Looks like you've got other things on your mind... We'll talk later.")
                activeConversations[playerId] = nil
                print(("[AI NPCs] Auto-ended idle conversation for player %s"):format(playerId))
            end
        end
    end
end)

-----------------------------------------------------------
-- TRUST DECAY (Optional - runs daily)
-----------------------------------------------------------
if Config.Trust.enabled then
    CreateThread(function()
        while true do
            Wait(Config.Trust.decayCheckInterval)

            for identifier, categories in pairs(playerTrust) do
                for category, npcs in pairs(categories) do
                    for npcId, trust in pairs(npcs) do
                        -- Decay trust over time
                        local newTrust = math.max(0, trust - Config.Trust.decayRate)
                        playerTrust[identifier][category][npcId] = newTrust
                    end
                end
            end

            print("[AI NPCs] Applied trust decay")
            SaveTrustData()
        end
    end)
end

-----------------------------------------------------------
-- AUDIO CACHE
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:getAudio', function(text, voiceId)
    local src = source
    local audioId = GetHashKey(text .. voiceId)

    if audioCache[audioId] then
        TriggerClientEvent('ai-npcs:client:playAudio', src, audioCache[audioId])
    else
        GenerateTTS(src, text, voiceId, audioId)
    end
end)

-----------------------------------------------------------
-- EXPORTS FOR OTHER RESOURCES
-----------------------------------------------------------
exports('GetPlayerTrustWithNPC', function(playerId, npcId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return 0 end

    local identifier = Player.PlayerData.citizenid
    for _, npc in pairs(Config.NPCs) do
        if npc.id == npcId then
            return GetPlayerTrust(identifier, npc.trustCategory, npcId)
        end
    end
    return 0
end)

exports('AddPlayerTrustWithNPC', function(playerId, npcId, amount)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    local identifier = Player.PlayerData.citizenid
    for _, npc in pairs(Config.NPCs) do
        if npc.id == npcId then
            AddPlayerTrust(identifier, npc.trustCategory, npcId, amount)
            return true
        end
    end
    return false
end)

exports('SetPlayerTrustWithNPC', function(playerId, npcId, value)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    local identifier = Player.PlayerData.citizenid
    for _, npc in pairs(Config.NPCs) do
        if npc.id == npcId then
            SetPlayerTrust(identifier, npc.trustCategory, npcId, value)
            return true
        end
    end
    return false
end)

-- Quest exports (with range validation for security)
exports('OfferQuestToPlayer', function(playerId, npcId, questId, questType, questData, skipRangeCheck)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    -- Range validation (can be bypassed by server scripts with skipRangeCheck)
    if not skipRangeCheck and not IsPlayerNearNPC(playerId, npcId) then
        if Config.Debug.enabled then
            print(("[AI NPCs] OfferQuest blocked: Player %s not near NPC %s"):format(playerId, npcId))
        end
        return false, "not_in_range"
    end

    local identifier = Player.PlayerData.citizenid
    OfferQuest(identifier, npcId, questId, questType, questData)
    return true
end)

exports('CompletePlayerQuest', function(playerId, npcId, questId, trustReward, skipRangeCheck)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    -- Range validation for quest completion (slightly larger range)
    if not skipRangeCheck and not IsPlayerInQuestRange(playerId, npcId) then
        if Config.Debug.enabled then
            print(("[AI NPCs] CompleteQuest blocked: Player %s not near NPC %s"):format(playerId, npcId))
        end
        return false, "not_in_range"
    end

    local identifier = Player.PlayerData.citizenid
    CompleteQuest(identifier, npcId, questId, trustReward)
    return true
end)

exports('GetPlayerQuestStatus', function(playerId, npcId, questId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return nil end

    local identifier = Player.PlayerData.citizenid
    return GetQuestStatus(identifier, npcId, questId)
end)

-- Referral exports (with range validation)
exports('CreatePlayerReferral', function(playerId, fromNpcId, toNpcId, referralType, skipRangeCheck)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    -- Must be near the NPC giving the referral
    if not skipRangeCheck and not IsPlayerNearNPC(playerId, fromNpcId) then
        if Config.Debug.enabled then
            print(("[AI NPCs] CreateReferral blocked: Player %s not near NPC %s"):format(playerId, fromNpcId))
        end
        return false, "not_in_range"
    end

    local identifier = Player.PlayerData.citizenid
    CreateReferral(identifier, fromNpcId, toNpcId, referralType)
    return true
end)

exports('HasPlayerReferral', function(playerId, toNpcId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    local identifier = Player.PlayerData.citizenid
    return HasReferral(identifier, toNpcId)
end)

-- Debt exports
exports('CreatePlayerDebt', function(playerId, npcId, debtType, amount, description)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    local identifier = Player.PlayerData.citizenid
    CreateDebt(identifier, npcId, debtType, amount, description)
    return true
end)

exports('GetPlayerDebts', function(playerId, npcId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return {} end

    local identifier = Player.PlayerData.citizenid
    return GetPlayerDebts(identifier, npcId)
end)

exports('PayPlayerDebt', function(playerId, debtId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    local identifier = Player.PlayerData.citizenid
    PayDebt(identifier, debtId)
    return true
end)

-- Memory exports
exports('AddNPCMemoryAboutPlayer', function(playerId, npcId, memoryType, memoryText, importance, expiresInDays)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end

    local identifier = Player.PlayerData.citizenid
    AddNPCMemory(identifier, npcId, memoryType, memoryText, importance, expiresInDays)
    return true
end)

exports('GetNPCMemoriesAboutPlayer', function(playerId, npcId, limit)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return {} end

    local identifier = Player.PlayerData.citizenid
    return GetNPCMemories(identifier, npcId, limit)
end)
