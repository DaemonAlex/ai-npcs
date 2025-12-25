-----------------------------------------------------------
-- REQUEST QUEUE & RATE LIMITING
-----------------------------------------------------------
local requestQueue = {}
local isProcessingQueue = false
local lastRequestTime = 0
local requestsThisMinute = 0
local lastMinuteReset = GetGameTimer()
local pendingRequests = {}  -- Track pending requests per player

-- Rate limit config (adjust based on your API tier)
local RATE_LIMIT = {
    requestsPerMinute = 50,      -- Anthropic free tier is ~60/min
    minDelayMs = 200,            -- Minimum delay between requests
    maxConcurrent = 5,           -- Max concurrent requests
    requestTimeoutMs = 30000     -- 30 second timeout
}

local currentConcurrent = 0

function QueueAIRequest(playerId, conversation, playerMessage)
    -- Check if player already has a pending request
    if pendingRequests[playerId] then
        TriggerClientEvent('ai-npcs:client:receiveMessage', playerId,
            "*holds up a finger* Hold on, I'm still thinking...", conversation.npc.id)
        return
    end

    -- Add to queue
    table.insert(requestQueue, {
        playerId = playerId,
        conversation = conversation,
        playerMessage = playerMessage,
        queuedAt = GetGameTimer()
    })

    pendingRequests[playerId] = true

    -- Start processing if not already
    if not isProcessingQueue then
        ProcessRequestQueue()
    end
end

function ProcessRequestQueue()
    if #requestQueue == 0 then
        isProcessingQueue = false
        return
    end

    isProcessingQueue = true
    local currentTime = GetGameTimer()

    -- Reset rate limit counter every minute
    if currentTime - lastMinuteReset > 60000 then
        requestsThisMinute = 0
        lastMinuteReset = currentTime
    end

    -- Check rate limits
    if requestsThisMinute >= RATE_LIMIT.requestsPerMinute then
        -- Wait until next minute
        local waitTime = 60000 - (currentTime - lastMinuteReset) + 100
        if Config.Debug.enabled then
            print(("[AI NPCs] Rate limit reached, waiting %dms"):format(waitTime))
        end
        SetTimeout(waitTime, ProcessRequestQueue)
        return
    end

    -- Check concurrent limit
    if currentConcurrent >= RATE_LIMIT.maxConcurrent then
        SetTimeout(500, ProcessRequestQueue)
        return
    end

    -- Check minimum delay
    local timeSinceLastRequest = currentTime - lastRequestTime
    if timeSinceLastRequest < RATE_LIMIT.minDelayMs then
        SetTimeout(RATE_LIMIT.minDelayMs - timeSinceLastRequest, ProcessRequestQueue)
        return
    end

    -- Get next request
    local request = table.remove(requestQueue, 1)
    if not request then
        isProcessingQueue = false
        return
    end

    -- Check if request is too old (player might have left)
    if currentTime - request.queuedAt > 60000 then
        pendingRequests[request.playerId] = nil
        ProcessRequestQueue()
        return
    end

    -- Process the request
    lastRequestTime = currentTime
    requestsThisMinute = requestsThisMinute + 1
    currentConcurrent = currentConcurrent + 1

    GenerateAIResponseInternal(request.playerId, request.conversation, request.playerMessage, function()
        currentConcurrent = currentConcurrent - 1
        pendingRequests[request.playerId] = nil
        -- Process next request
        SetTimeout(RATE_LIMIT.minDelayMs, ProcessRequestQueue)
    end)
end

-----------------------------------------------------------
-- FALLBACK DIALOGUE SYSTEM (uses Config.FallbackResponses)
-----------------------------------------------------------
function GetFallbackResponse(npc, reason)
    local category = "generic"

    -- Determine category based on NPC trust category
    if npc.trustCategory then
        if npc.trustCategory == "criminal" or npc.trustCategory == "gang" then
            category = "criminal"
        elseif npc.trustCategory == "professional" or npc.trustCategory == "legitimate" then
            category = "legitimate"
        elseif npc.trustCategory == "service" then
            category = "service"
        end
    end

    -- Use API error messages for actual failures
    if reason == "api_error" or reason == "timeout" then
        category = "api_error"
    end

    -- Get from config, fallback to generic if category missing
    local responses = Config.FallbackResponses and Config.FallbackResponses[category]
    if not responses or #responses == 0 then
        responses = Config.FallbackResponses and Config.FallbackResponses.generic
    end

    -- Ultimate fallback if config is missing entirely
    if not responses or #responses == 0 then
        return "*looks distracted* Sorry, what were you saying?"
    end

    return responses[math.random(#responses)]
end

-----------------------------------------------------------
-- AI Response Generation with Full Context
-----------------------------------------------------------
function GenerateAIResponse(playerId, conversation, playerMessage)
    -- Use the queue system instead of direct call
    QueueAIRequest(playerId, conversation, playerMessage)
end

function GenerateAIResponseInternal(playerId, conversation, playerMessage, onComplete)
    local npc = conversation.npc
    local playerContext = conversation.playerContext

    -- Build the enhanced system prompt with context
    local systemPrompt = BuildContextualSystemPrompt(npc, playerContext, conversation)

    -- Build conversation history for API
    local messages = {}

    -- Add conversation history
    for _, msg in ipairs(conversation.conversationHistory) do
        table.insert(messages, msg)
    end

    -- Prepare API request based on provider
    local requestData, headers

    if Config.AI.provider == "anthropic" then
        -- Anthropic Claude API format
        requestData = {
            model = Config.AI.model,
            messages = messages,
            max_tokens = Config.AI.maxTokens,
            temperature = Config.AI.temperature,
            system = systemPrompt
        }

        headers = {
            ["Content-Type"] = "application/json",
            ["x-api-key"] = Config.AI.apiKey,
            ["anthropic-version"] = "2023-06-01"
        }
    else
        -- OpenAI API format - prepend system message
        table.insert(messages, 1, {
            role = "system",
            content = systemPrompt
        })

        requestData = {
            model = Config.AI.model,
            messages = messages,
            max_tokens = Config.AI.maxTokens,
            temperature = Config.AI.temperature
        }

        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. Config.AI.apiKey
        }
    end

    -- Timeout tracking
    local requestId = GetGameTimer()
    local hasResponded = false
    local timeoutTriggered = false

    -- Set up timeout handler
    SetTimeout(RATE_LIMIT.requestTimeoutMs, function()
        if not hasResponded then
            timeoutTriggered = true
            print(("[AI NPCs] Request timeout for player %s"):format(playerId))
            local fallback = GetFallbackResponse(npc, "timeout")
            TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
            if onComplete then onComplete() end
        end
    end)

    -- Make API request
    PerformHttpRequest(Config.AI.apiUrl, function(statusCode, response, respHeaders)
        -- Ignore if timeout already triggered
        if timeoutTriggered then return end
        hasResponded = true

        if statusCode == 200 then
            local success, data = pcall(json.decode, response)
            local aiResponse = nil

            if success then
                if Config.AI.provider == "anthropic" and data.content and data.content[1] then
                    aiResponse = data.content[1].text
                elseif data.choices and data.choices[1] then
                    aiResponse = data.choices[1].message.content
                end
            end

            if aiResponse then
                -- Clean up response
                aiResponse = CleanAIResponse(aiResponse)

                -- Add AI response to conversation history
                table.insert(conversation.conversationHistory, {
                    role = "assistant",
                    content = aiResponse
                })

                -- Send response to client
                TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, aiResponse, npc.id)

                -- Generate TTS if enabled
                if Config.TTS.enabled and Config.TTS.apiKey ~= "YOUR_ELEVENLABS_KEY_HERE" then
                    GenerateTTS(playerId, aiResponse, npc.voice or Config.TTS.defaultVoice)
                end

                if Config.Debug.printResponses then
                    print(("[AI NPCs] %s says: %s"):format(npc.name, aiResponse:sub(1, 80) .. "..."))
                end
            else
                print("[AI NPCs] Failed to parse AI response")
                print("[AI NPCs] Raw response: " .. tostring(response))
                local fallback = GetFallbackResponse(npc, "parse_error")
                TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
            end
        elseif statusCode == 429 then
            -- Rate limited by API
            print("[AI NPCs] API rate limit hit (429)")
            local fallback = GetFallbackResponse(npc, "api_error")
            TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
        else
            print(("[AI NPCs] AI API request failed with status: %s"):format(statusCode))
            print("[AI NPCs] Response: " .. tostring(response))
            local fallback = GetFallbackResponse(npc, "api_error")
            TriggerClientEvent('ai-npcs:client:receiveMessage', playerId, fallback, npc.id)
        end

        if onComplete then onComplete() end
    end, 'POST', json.encode(requestData), headers)
end

-----------------------------------------------------------
-- Build Context-Aware System Prompt (v2.5 Enhanced)
-----------------------------------------------------------
function BuildContextualSystemPrompt(npc, playerContext, conversation)
    local prompt = npc.systemPrompt .. "\n\n"

    local citizenid = playerContext.citizenid

    -- ===========================================
    -- V2.5: NPC MOOD CONTEXT
    -- ===========================================
    local moodContext, moodEffects = "", nil
    if exports['ai-npcs'].BuildMoodContext then
        moodContext, moodEffects = exports['ai-npcs']:BuildMoodContext(npc.id, npc)
        if moodContext and moodContext ~= "" then
            prompt = prompt .. moodContext .. "\n"
        end
    end

    -- ===========================================
    -- V2.5: FACTION TRUST CONTEXT
    -- ===========================================
    if exports['ai-npcs'].BuildFactionContext and citizenid then
        local factionContext = exports['ai-npcs']:BuildFactionContext(npc.id, citizenid, playerContext.name)
        if factionContext and factionContext ~= "" then
            prompt = prompt .. factionContext .. "\n"
        end
    end

    -- ===========================================
    -- V2.5: RUMOR MILL CONTEXT
    -- ===========================================
    if exports['ai-npcs'].BuildRumorContext and citizenid then
        local rumorContext = exports['ai-npcs']:BuildRumorContext(npc.id, citizenid, npc)
        if rumorContext and rumorContext ~= "" then
            prompt = prompt .. rumorContext .. "\n"
        end
    end

    -- ===========================================
    -- V2.5: INTEL CONTEXT (what you can offer)
    -- ===========================================
    if exports['ai-npcs'].BuildIntelContext and citizenid then
        local intelContext = exports['ai-npcs']:BuildIntelContext(npc.id, citizenid)
        if intelContext and intelContext ~= "" then
            prompt = prompt .. intelContext .. "\n"
        end
    end

    -- Add current context section
    prompt = prompt .. "=== CURRENT SITUATION ===\n"

    -- Player info
    prompt = prompt .. ("You are currently talking to: %s\n"):format(playerContext.name)
    prompt = prompt .. ("Their job: %s\n"):format(playerContext.jobLabel)

    -- Trust level affects how open you are
    prompt = prompt .. ("Your relationship with them: %s (Trust: %d/100)\n"):format(
        conversation.trustLevel, conversation.trustValue
    )

    -- Context-specific instructions
    if playerContext.isCop then
        prompt = prompt .. "\n⚠️ WARNING: This person is LAW ENFORCEMENT. "
        local reaction = npc.contextReactions.copReaction
        if reaction == "extremely_suspicious" then
            prompt = prompt .. "Be very evasive. Give vague or misleading answers. Try to end the conversation. Do NOT reveal criminal information.\n"
        elseif reaction == "hostile_dismissive" then
            prompt = prompt .. "Be hostile and dismissive. Refuse to engage. Make it clear you don't talk to cops.\n"
        elseif reaction == "paranoid_shutdown" then
            prompt = prompt .. "Completely shut down. Deny knowing anything about anything illegal. Be boring and unhelpful.\n"
        elseif reaction == "professional_denial" then
            prompt = prompt .. "Maintain your cover story perfectly. Be polite but reveal nothing illegal.\n"
        else
            prompt = prompt .. "Be careful about what you reveal.\n"
        end
    else
        -- Non-cop context modifiers
        if playerContext.hasDrugs then
            prompt = prompt .. "✓ They appear to be carrying drugs. This suggests they're in the game. You can be more open about drug-related topics.\n"
        end

        if playerContext.hasCrimeTools then
            prompt = prompt .. "✓ They have professional tools (lockpicks, thermite, etc). They seem like a serious operator.\n"
        end

        if playerContext.hasWeapons then
            prompt = prompt .. "✓ They're armed. Treat them with appropriate respect/caution.\n"
        end

        if playerContext.cash > 10000 then
            prompt = prompt .. ("✓ They're carrying $%d in cash. They might be willing to pay for information.\n"):format(playerContext.cash)
        elseif playerContext.cash < 500 then
            prompt = prompt .. "✗ They don't seem to have much money on them.\n"
        end

        if playerContext.gang and playerContext.gang ~= "" then
            prompt = prompt .. ("✓ They're affiliated with: %s\n"):format(playerContext.gang)
        end
    end

    -- Trust level behavior
    prompt = prompt .. "\n=== TRUST LEVEL BEHAVIOR ===\n"
    if conversation.trustLevel == "Stranger" then
        prompt = prompt .. "They are a STRANGER. Be cautious. Only share vague rumors or public knowledge. Encourage them to prove themselves or pay for information.\n"
    elseif conversation.trustLevel == "Acquaintance" then
        prompt = prompt .. "They are an ACQUAINTANCE. You've met before. Share basic information if they pay. Don't reveal sensitive details yet.\n"
    elseif conversation.trustLevel == "Trusted" then
        prompt = prompt .. "They are TRUSTED. You've built a relationship. Share detailed information for fair payment. Warn them about dangers.\n"
    elseif conversation.trustLevel == "Inner Circle" then
        prompt = prompt .. "They are INNER CIRCLE. They've proven themselves completely. Share sensitive information freely. Give them the real good stuff.\n"
    end

    -- Payment context
    if conversation.paymentMade > 0 then
        prompt = prompt .. ("\n💰 They have paid you $%d this conversation. Be appropriately grateful and informative.\n"):format(conversation.paymentMade)
    end

    -- Intel request context
    if conversation.requestedIntel then
        prompt = prompt .. ("\n📋 INTEL REQUEST: They're asking about '%s' (tier: %s). Provide appropriate information based on trust and payment.\n"):format(
            conversation.requestedIntel.topic, conversation.requestedIntel.tier
        )
    end

    -- Reminder about format
    prompt = prompt .. "\n=== RESPONSE GUIDELINES ===\n"
    prompt = prompt .. "- Stay in character at all times\n"
    prompt = prompt .. "- Keep responses under 100 words\n"
    prompt = prompt .. "- Use appropriate actions in *asterisks*\n"
    prompt = prompt .. "- If they haven't paid enough for information, hint at needing payment\n"
    prompt = prompt .. "- If they're a cop, stick to your cover story\n"
    prompt = prompt .. "- Reference their trust level naturally in how open you are\n"

    return prompt
end

-----------------------------------------------------------
-- Clean AI Response
-----------------------------------------------------------
function CleanAIResponse(response)
    -- Remove any markdown formatting that might slip through
    response = response:gsub("```", "")
    response = response:gsub("##", "")
    response = response:gsub("**", "")

    -- Trim whitespace
    response = response:match("^%s*(.-)%s*$")

    -- Limit length if too long
    if #response > 500 then
        response = response:sub(1, 497) .. "..."
    end

    return response
end

-----------------------------------------------------------
-- Text-to-Speech Generation (with proper caching)
-----------------------------------------------------------
local audioCache = {}
local cacheSize = 0

-- Create a deterministic cache key from text + voice
local function GetTTSCacheKey(text, voiceId)
    -- Normalize text (lowercase, trim, remove excess whitespace)
    local normalized = text:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    -- Create hash from text + voice
    return GetHashKey(normalized .. "_" .. (voiceId or "default"))
end

function GenerateTTS(playerId, text, voiceId)
    if not Config.TTS.enabled then return end
    if not Config.TTS.apiKey or Config.TTS.apiKey == "YOUR_ELEVENLABS_KEY_HERE" then
        return
    end

    local voice = voiceId or Config.TTS.defaultVoice
    local cacheKey = GetTTSCacheKey(text, voice)

    -- Check cache first - if we have this exact phrase already, just play it
    if Config.TTS.cacheAudio and audioCache[cacheKey] then
        local cachedFile = audioCache[cacheKey]
        TriggerClientEvent('ai-npcs:client:playAudio', playerId, cachedFile)
        if Config.Debug.enabled then
            print(("[AI NPCs] TTS cache hit: %s"):format(cachedFile))
        end
        return
    end

    local requestData = {
        text = text,
        model_id = "eleven_monolingual_v1",
        voice_settings = {
            stability = 0.5,
            similarity_boost = 0.75
        }
    }

    local headers = {
        ["Content-Type"] = "application/json",
        ["xi-api-key"] = Config.TTS.apiKey
    }

    local url = Config.TTS.apiUrl .. voice

    PerformHttpRequest(url, function(statusCode, response, respHeaders)
        if statusCode == 200 then
            local fileName = ("audio_%s.ogg"):format(cacheKey)
            local savePath = "audio/" .. fileName

            -- Save audio file
            local saved = SaveResourceFile(GetCurrentResourceName(), savePath, response, #response)

            if saved then
                -- Cache reference
                if Config.TTS.cacheAudio then
                    audioCache[cacheKey] = fileName
                    cacheSize = cacheSize + 1

                    -- Clean cache if too large
                    if cacheSize > Config.TTS.maxCacheSize then
                        CleanAudioCache()
                    end
                end

                -- Send to client
                TriggerClientEvent('ai-npcs:client:playAudio', playerId, fileName)

                if Config.Debug.enabled then
                    print(("[AI NPCs] Generated TTS audio: %s (cached)"):format(fileName))
                end
            end
        else
            if Config.Debug.enabled then
                print(("[AI NPCs] TTS request failed with status: %s"):format(statusCode))
            end
        end
    end, 'POST', json.encode(requestData), headers)
end

-----------------------------------------------------------
-- Audio Cache Management
-----------------------------------------------------------
function CleanAudioCache()
    local count = 0
    for audioId, fileName in pairs(audioCache) do
        if count >= 10 then break end

        audioCache[audioId] = nil
        cacheSize = cacheSize - 1
        count = count + 1
    end

    if Config.Debug.enabled then
        print(("[AI NPCs] Cleaned %d cached audio files"):format(count))
    end
end
