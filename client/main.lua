local QBCore = exports['qb-core']:GetCoreObject()

-- Local variables
local spawnedNPCs = {}
local activeConversation = nil
local conversationCooldown = false
local npcMovementThreads = {}

-----------------------------------------------------------
-- INITIALIZATION
-----------------------------------------------------------
CreateThread(function()
    while not QBCore do
        Wait(100)
    end

    SpawnNPCs()
    StartMovementSystem()
    print("[AI NPCs] Client initialized with movement system")
end)

-----------------------------------------------------------
-- NPC SPAWNING
-----------------------------------------------------------
function SpawnNPCs()
    for _, npcData in pairs(Config.NPCs) do
        CreateNPC(npcData)
    end
end

function CreateNPC(npcData)
    -- Check schedule availability
    if not IsNPCAvailable(npcData) then
        -- Schedule check later
        ScheduleNPCSpawn(npcData)
        return
    end

    -- Get spawn location based on schedule or home
    local spawnCoords = GetNPCCurrentLocation(npcData)
    if not spawnCoords then return end

    RequestModel(npcData.model)
    while not HasModelLoaded(npcData.model) do
        Wait(1)
    end

    local npc = CreatePed(4, npcData.model, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnCoords.w, false, true)

    -- Verify NPC was created successfully
    if not npc or npc == 0 or not DoesEntityExist(npc) then
        print(("[AI NPCs] ^1Failed to spawn NPC: %s (invalid entity)^7"):format(npcData.name))
        SetModelAsNoLongerNeeded(npcData.model)
        return
    end

    -- Configure NPC base properties
    SetEntityInvincible(npc, true)
    SetPedFleeAttributes(npc, 0, 0)
    SetPedDiesWhenInjured(npc, false)
    SetPedCanRagdollFromPlayerImpact(npc, false)
    SetEntityCanBeDamaged(npc, false)
    SetPedCanBeTargetted(npc, false)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedConfigFlag(npc, 32, false) -- Can't be dragged out of vehicles
    SetPedConfigFlag(npc, 281, true) -- No writhe

    -- Movement configuration based on pattern
    if npcData.movement and npcData.movement.pattern ~= "stationary" then
        FreezeEntityPosition(npc, false)
        SetPedCanPlayAmbientAnims(npc, true)
        SetPedKeepTask(npc, true)
    else
        FreezeEntityPosition(npc, true)
        SetPedCanPlayAmbientAnims(npc, true)
    end

    -- Store NPC data
    spawnedNPCs[npcData.id] = {
        entity = npc,
        data = npcData,
        currentWaypointIndex = 1,
        isMoving = false,
        lastMoveTime = GetGameTimer()
    }

    -- Add ox_target interaction
    AddNPCTarget(npc, npcData)

    -- Add blip if configured
    if npcData.blip then
        CreateNPCBlip(npcData, spawnCoords)
    end

    print(("[AI NPCs] Spawned NPC: %s at %.1f, %.1f, %.1f"):format(
        npcData.name, spawnCoords.x, spawnCoords.y, spawnCoords.z
    ))
end

function AddNPCTarget(npc, npcData)
    exports.ox_target:addLocalEntity(npc, {
        {
            name = "talk_to_" .. npcData.id,
            label = "Talk to " .. npcData.name,
            icon = "fas fa-comments",
            distance = Config.Interaction.distance,
            onSelect = function()
                StartConversation(npcData.id)
            end
        },
        {
            name = "pay_" .. npcData.id,
            label = "Offer Payment",
            icon = "fas fa-money-bill-wave",
            distance = Config.Interaction.distance,
            canInteract = function()
                return activeConversation and activeConversation.npcId == npcData.id
            end,
            onSelect = function()
                ShowPaymentMenu(npcData.id)
            end
        }
    })
end

function CreateNPCBlip(npcData, coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, npcData.blip.sprite)
    SetBlipColour(blip, npcData.blip.color)
    SetBlipScale(blip, npcData.blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(npcData.blip.label or npcData.name)
    EndTextCommandSetBlipName(blip)

    spawnedNPCs[npcData.id].blip = blip
end

-----------------------------------------------------------
-- SCHEDULE & AVAILABILITY
-----------------------------------------------------------
function IsNPCAvailable(npcData)
    if not npcData.schedule then return true end

    local currentHour = GetClockHours()

    for _, schedule in ipairs(npcData.schedule) do
        local startHour = schedule.time[1]
        local endHour = schedule.time[2]

        local isInTimeRange
        if startHour < endHour then
            isInTimeRange = currentHour >= startHour and currentHour < endHour
        else
            -- Handles overnight schedules (e.g., 20-4)
            isInTimeRange = currentHour >= startHour or currentHour < endHour
        end

        if isInTimeRange then
            return schedule.active ~= false
        end
    end

    return true
end

function GetNPCCurrentLocation(npcData)
    -- Check schedule-based locations first
    if npcData.movement and npcData.movement.pattern == "schedule" then
        local currentHour = GetClockHours()

        for _, locData in ipairs(npcData.movement.locations) do
            local startHour = locData.time[1]
            local endHour = locData.time[2]

            local isInTimeRange
            if startHour < endHour then
                isInTimeRange = currentHour >= startHour and currentHour < endHour
            else
                isInTimeRange = currentHour >= startHour or currentHour < endHour
            end

            if isInTimeRange then
                return locData.coords
            end
        end
    end

    return npcData.homeLocation
end

function ScheduleNPCSpawn(npcData)
    CreateThread(function()
        while true do
            Wait(60000) -- Check every minute
            if IsNPCAvailable(npcData) and not spawnedNPCs[npcData.id] then
                CreateNPC(npcData)
                break
            end
        end
    end)
end

-----------------------------------------------------------
-- MOVEMENT SYSTEM (with dynamic sleep for optimization)
-----------------------------------------------------------
function StartMovementSystem()
    CreateThread(function()
        while true do
            local playerCoords = GetEntityCoords(PlayerPedId())
            local nearestDistance = 999999.0
            local sleepTime = 5000  -- Default: check every 5 seconds

            for npcId, npcInfo in pairs(spawnedNPCs) do
                local npcData = npcInfo.data
                local entity = npcInfo.entity

                if not DoesEntityExist(entity) then
                    goto continue
                end

                -- Calculate distance for dynamic sleep
                local npcCoords = GetEntityCoords(entity)
                local distance = #(playerCoords - npcCoords)
                if distance < nearestDistance then
                    nearestDistance = distance
                end

                -- Check if NPC should still be available
                if not IsNPCAvailable(npcData) then
                    DespawnNPC(npcId)
                    goto continue
                end

                -- Handle movement patterns (only if player is within range)
                if npcData.movement and distance < 100.0 then
                    HandleNPCMovement(npcId, npcInfo)
                end

                ::continue::
            end

            -- Dynamic sleep based on nearest NPC distance
            -- Optimized thresholds: responsive when close, efficient when far
            -- Note: 0ms is avoided to prevent frame stutter/client freezes
            if nearestDistance < 5.0 then
                sleepTime = 100    -- Very close (<5m): 100ms - near-instant response
            elseif nearestDistance < 15.0 then
                sleepTime = 500    -- Close: 0.5s updates
            elseif nearestDistance < 30.0 then
                sleepTime = 1000   -- Medium-close: 1s updates
            else
                sleepTime = 2000   -- Far (>30m): 2s updates - matches >50m spec
            end

            Wait(sleepTime)
        end
    end)
end

function HandleNPCMovement(npcId, npcInfo)
    local npcData = npcInfo.data
    local entity = npcInfo.entity
    local pattern = npcData.movement.pattern
    local currentTime = GetGameTimer()

    -- Don't move if in conversation (either via global check or local flag)
    if npcInfo.inConversation then
        return
    end
    if activeConversation and activeConversation.npcId == npcId then
        return
    end

    if pattern == "wander" then
        HandleWanderMovement(npcId, npcInfo, currentTime)
    elseif pattern == "patrol" then
        HandlePatrolMovement(npcId, npcInfo, currentTime)
    elseif pattern == "schedule" then
        HandleScheduleMovement(npcId, npcInfo, currentTime)
    end
end

function HandleWanderMovement(npcId, npcInfo, currentTime)
    local entity = npcInfo.entity
    local npcData = npcInfo.data
    local wanderConfig = Config.Movement.patterns.wander

    -- Check if enough time has passed since last move
    local timeSinceMove = currentTime - npcInfo.lastMoveTime
    local waitTime = math.random(wanderConfig.minWait, wanderConfig.maxWait)

    if timeSinceMove < waitTime then return end
    if npcInfo.isMoving then return end

    -- Generate random point within wander radius
    local homeCoords = npcData.homeLocation
    local angle = math.random() * 2 * math.pi
    local distance = math.random() * wanderConfig.radius

    local targetX = homeCoords.x + (math.cos(angle) * distance)
    local targetY = homeCoords.y + (math.sin(angle) * distance)

    -- Get ground Z coordinate
    local found, groundZ = GetGroundZFor_3dCoord(targetX, targetY, homeCoords.z + 10.0, false)
    if not found then groundZ = homeCoords.z end

    -- Make NPC walk to location
    npcInfo.isMoving = true
    TaskGoToCoordAnyMeans(entity, targetX, targetY, groundZ, 1.0, 0, false, 786603, 0.0)

    -- Reset when reached
    CreateThread(function()
        while npcInfo.isMoving do
            Wait(1000)
            local currentCoords = GetEntityCoords(entity)
            local dist = #(currentCoords - vector3(targetX, targetY, groundZ))
            if dist < 2.0 or not IsPedWalking(entity) then
                npcInfo.isMoving = false
                npcInfo.lastMoveTime = GetGameTimer()
            end
        end
    end)
end

function HandlePatrolMovement(npcId, npcInfo, currentTime)
    local entity = npcInfo.entity
    local npcData = npcInfo.data
    local locations = npcData.movement.locations

    if not locations or #locations == 0 then return end
    if npcInfo.isMoving then return end

    -- Get current waypoint
    local waypointIndex = npcInfo.currentWaypointIndex
    local waypoint = locations[waypointIndex]

    -- Check if at waypoint and waited long enough
    local currentCoords = GetEntityCoords(entity)
    local waypointCoords = waypoint.coords
    local dist = #(currentCoords - vector3(waypointCoords.x, waypointCoords.y, waypointCoords.z))

    if dist < 2.0 then
        -- At waypoint, check wait time
        local timeSinceMove = currentTime - npcInfo.lastMoveTime
        local waitTime = waypoint.waitTime or Config.Movement.patterns.patrol.waitAtPoints

        if timeSinceMove < waitTime then return end

        -- Move to next waypoint
        npcInfo.currentWaypointIndex = (waypointIndex % #locations) + 1
    end

    -- Move to current waypoint
    local targetWaypoint = locations[npcInfo.currentWaypointIndex].coords
    npcInfo.isMoving = true

    TaskGoToCoordAnyMeans(entity, targetWaypoint.x, targetWaypoint.y, targetWaypoint.z, 1.0, 0, false, 786603, 0.0)

    -- Reset when reached
    CreateThread(function()
        while npcInfo.isMoving do
            Wait(1000)
            local coords = GetEntityCoords(entity)
            local d = #(coords - vector3(targetWaypoint.x, targetWaypoint.y, targetWaypoint.z))
            if d < 2.0 then
                npcInfo.isMoving = false
                npcInfo.lastMoveTime = GetGameTimer()
                SetEntityHeading(entity, targetWaypoint.w or GetEntityHeading(entity))
            end
        end
    end)
end

function HandleScheduleMovement(npcId, npcInfo, currentTime)
    local entity = npcInfo.entity
    local npcData = npcInfo.data

    -- Get where NPC should be right now
    local targetLocation = GetNPCCurrentLocation(npcData)
    if not targetLocation then
        DespawnNPC(npcId)
        return
    end

    -- Check if already at target
    local currentCoords = GetEntityCoords(entity)
    local dist = #(currentCoords - vector3(targetLocation.x, targetLocation.y, targetLocation.z))

    if dist < 5.0 then return end
    if npcInfo.isMoving then return end

    -- Teleport if too far (different zone), otherwise walk
    if dist > 100.0 then
        -- Too far, teleport
        SetEntityCoords(entity, targetLocation.x, targetLocation.y, targetLocation.z)
        SetEntityHeading(entity, targetLocation.w)
        npcInfo.lastMoveTime = GetGameTimer()

        -- Update blip if exists
        if npcInfo.blip then
            SetBlipCoords(npcInfo.blip, targetLocation.x, targetLocation.y, targetLocation.z)
        end
    else
        -- Walk there
        npcInfo.isMoving = true
        TaskGoToCoordAnyMeans(entity, targetLocation.x, targetLocation.y, targetLocation.z, 1.0, 0, false, 786603, 0.0)

        CreateThread(function()
            while npcInfo.isMoving do
                Wait(1000)
                local coords = GetEntityCoords(entity)
                local d = #(coords - vector3(targetLocation.x, targetLocation.y, targetLocation.z))
                if d < 2.0 then
                    npcInfo.isMoving = false
                    npcInfo.lastMoveTime = GetGameTimer()
                    SetEntityHeading(entity, targetLocation.w)
                end
            end
        end)
    end
end

function DespawnNPC(npcId)
    local npcInfo = spawnedNPCs[npcId]
    if not npcInfo then return end

    if npcInfo.blip then
        RemoveBlip(npcInfo.blip)
    end

    if DoesEntityExist(npcInfo.entity) then
        exports.ox_target:removeLocalEntity(npcInfo.entity)
        DeleteEntity(npcInfo.entity)
    end

    spawnedNPCs[npcId] = nil
    ScheduleNPCSpawn(npcInfo.data)

    print(("[AI NPCs] Despawned NPC: %s (schedule)"):format(npcInfo.data.name))
end

-----------------------------------------------------------
-- CONVERSATION SYSTEM
-----------------------------------------------------------
function StartConversation(npcId)
    if activeConversation then
        exports['ox_lib']:notify({
            title = 'Conversation',
            description = 'You are already talking to someone',
            type = 'error'
        })
        return
    end

    if conversationCooldown then
        exports['ox_lib']:notify({
            title = 'Conversation',
            description = 'Wait a moment before starting another conversation',
            type = 'error'
        })
        return
    end

    local npcInfo = spawnedNPCs[npcId]
    if not npcInfo then return end

    -- Stop NPC movement during conversation
    if DoesEntityExist(npcInfo.entity) then
        ClearPedTasksImmediately(npcInfo.entity)
        npcInfo.isMoving = false
        npcInfo.inConversation = true

        -- Face the player
        local playerCoords = GetEntityCoords(PlayerPedId())
        local npcCoords = GetEntityCoords(npcInfo.entity)
        local heading = GetHeadingFromVector_2d(playerCoords.x - npcCoords.x, playerCoords.y - npcCoords.y)
        SetEntityHeading(npcInfo.entity, heading)

        -- Freeze NPC in place during conversation
        FreezeEntityPosition(npcInfo.entity, true)

        -- Play idle talking animation
        RequestAnimDict("mp_facial")
        local timeout = 0
        while not HasAnimDictLoaded("mp_facial") and timeout < 1000 do
            Wait(10)
            timeout = timeout + 10
        end
        if HasAnimDictLoaded("mp_facial") then
            TaskPlayAnim(npcInfo.entity, "mp_facial", "mic_chatter", 3.0, -3.0, -1, 49, 0, false, false, false)
        end
    end

    activeConversation = {
        npcId = npcId,
        npc = npcInfo.data,
        paymentMade = 0
    }

    -- Start conversation on server
    TriggerServerEvent('ai-npcs:server:startConversation', npcId)

    -- Open conversation UI
    OpenConversationUI(npcInfo.data)

    print(("[AI NPCs] Started conversation with %s"):format(npcInfo.data.name))
end

function OpenConversationUI(npcData)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openConversation",
        npcName = npcData.name,
        npcRole = npcData.role
    })
end

function EndConversation(reason)
    if not activeConversation then return end

    -- Restore NPC to normal state
    local npcInfo = spawnedNPCs[activeConversation.npcId]
    if npcInfo and DoesEntityExist(npcInfo.entity) then
        -- Clear animation
        ClearPedTasks(npcInfo.entity)
        npcInfo.inConversation = false

        -- Unfreeze if NPC has movement pattern
        if npcInfo.data.movement and npcInfo.data.movement.pattern ~= "stationary" then
            FreezeEntityPosition(npcInfo.entity, false)
            npcInfo.lastMoveTime = GetGameTimer()  -- Reset move timer
        end
    end

    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "closeConversation"
    })

    if reason then
        exports['ox_lib']:notify({
            title = 'Conversation Ended',
            description = reason,
            type = 'info'
        })
    end

    TriggerServerEvent('ai-npcs:server:endConversation')
    activeConversation = nil

    -- Set cooldown
    conversationCooldown = true
    SetTimeout(Config.Interaction.cooldown, function()
        conversationCooldown = false
    end)

    print("[AI NPCs] Conversation ended")
end

-----------------------------------------------------------
-- PAYMENT SYSTEM
-----------------------------------------------------------
function ShowPaymentMenu(npcId)
    if not activeConversation or activeConversation.npcId ~= npcId then return end

    local input = exports['ox_lib']:inputDialog('Offer Payment', {
        {
            type = 'number',
            label = 'Amount ($)',
            description = 'How much cash to offer?',
            icon = 'dollar-sign',
            required = true,
            min = 100,
            max = 100000
        }
    })

    if input and input[1] then
        local amount = tonumber(input[1])
        if amount and amount > 0 then
            TriggerServerEvent('ai-npcs:server:sendMessage',
                "*hands over $" .. amount .. "*",
                amount
            )
            activeConversation.paymentMade = (activeConversation.paymentMade or 0) + amount
        end
    end
end

RegisterNetEvent('ai-npcs:client:showPaymentPrompt', function(suggestedPrice, topic, tier)
    if not activeConversation then return end

    local alert = exports['ox_lib']:alertDialog({
        header = 'Payment Required',
        content = ("This information costs around **$%s**\n\nPay for intel about: %s"):format(
            suggestedPrice, topic
        ),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Pay $' .. suggestedPrice,
            cancel = 'Not Now'
        }
    })

    if alert == 'confirm' then
        TriggerServerEvent('ai-npcs:server:sendMessage',
            "*pays $" .. suggestedPrice .. " for information*",
            suggestedPrice
        )
        activeConversation.paymentMade = (activeConversation.paymentMade or 0) + suggestedPrice

        -- Request the intel after payment
        Wait(500)
        TriggerServerEvent('ai-npcs:server:requestIntel', topic, tier)
    end
end)

-----------------------------------------------------------
-- NUI CALLBACKS
-----------------------------------------------------------
RegisterNUICallback('sendMessage', function(data, cb)
    if not activeConversation then
        cb('error')
        return
    end

    TriggerServerEvent('ai-npcs:server:sendMessage', data.message, data.payment or 0)
    cb('ok')
end)

RegisterNUICallback('endConversation', function(data, cb)
    EndConversation()
    cb('ok')
end)

RegisterNUICallback('closeUI', function(data, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('offerPayment', function(data, cb)
    if activeConversation then
        ShowPaymentMenu(activeConversation.npcId)
    end
    cb('ok')
end)

-----------------------------------------------------------
-- SERVER EVENTS
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:client:receiveMessage', function(message, npcId)
    if not activeConversation or activeConversation.npcId ~= npcId then return end

    SendNUIMessage({
        action = "receiveMessage",
        message = message,
        npcName = activeConversation.npc.name
    })

    -- Show subtitle if enabled
    if Config.Interaction.showSubtitles then
        exports['ox_lib']:notify({
            title = activeConversation.npc.name,
            description = message:sub(1, 100) .. (message:len() > 100 and "..." or ""),
            type = 'info',
            duration = 5000
        })
    end
end)

RegisterNetEvent('ai-npcs:client:playAudio', function(audioFile)
    if not activeConversation then return end

    local npcInfo = spawnedNPCs[activeConversation.npcId]
    if npcInfo and npcInfo.entity and DoesEntityExist(npcInfo.entity) then
        local npcCoords = GetEntityCoords(npcInfo.entity)

        -- Play sound at NPC location
        PlaySoundFromCoord(-1, "SELECT", npcCoords.x, npcCoords.y, npcCoords.z,
            "HUD_FRONTEND_DEFAULT_SOUNDSET", false, 15.0, false)

        print(("[AI NPCs] Playing TTS audio: %s"):format(audioFile))
    end
end)

RegisterNetEvent('ai-npcs:client:endConversation', function(reason)
    EndConversation(reason)
end)

-----------------------------------------------------------
-- CLEANUP
-----------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    -- Remove all NPCs
    for npcId, npcInfo in pairs(spawnedNPCs) do
        if npcInfo.blip then
            RemoveBlip(npcInfo.blip)
        end
        if DoesEntityExist(npcInfo.entity) then
            exports.ox_target:removeLocalEntity(npcInfo.entity)
            DeleteEntity(npcInfo.entity)
        end
    end

    -- Close any active conversation
    if activeConversation then
        EndConversation()
    end

    print("[AI NPCs] Cleaned up NPCs")
end)

-----------------------------------------------------------
-- HELPER FUNCTIONS
-----------------------------------------------------------
function GetHeadingFromVector_2d(dx, dy)
    local heading = math.deg(math.atan(dy, dx))
    if heading < 0 then
        heading = heading + 360
    end
    return (450.0 - heading) % 360.0
end
