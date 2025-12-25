--[[
    PHONE NOTIFICATIONS SYSTEM
    Send messages to high-trust players when intel/opportunities arise
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Minimum trust required to receive notifications from NPCs
local MIN_TRUST_FOR_NOTIFICATIONS = 50

-- Check for pending notifications when player joins
local function CheckPendingNotifications(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Get unsent notifications
    local notifications = MySQL.query.await([[
        SELECT n.*, t.trust_value
        FROM ai_npc_notifications n
        LEFT JOIN ai_npc_trust t ON t.citizenid = n.citizenid AND t.npc_id = n.npc_id
        WHERE n.citizenid = ?
        AND n.is_sent = FALSE
        AND (n.expires_at IS NULL OR n.expires_at > NOW())
        AND n.send_after <= NOW()
        ORDER BY n.priority DESC, n.created_at ASC
        LIMIT 10
    ]], {citizenid})

    if not notifications or #notifications == 0 then return end

    -- Send each notification
    for _, notif in ipairs(notifications) do
        -- Verify trust still meets requirement
        if (notif.trust_value or 0) >= notif.trust_required then
            SendPhoneNotification(playerId, notif)

            -- Mark as sent
            MySQL.update([[
                UPDATE ai_npc_notifications SET is_sent = TRUE WHERE id = ?
            ]], {notif.id})
        else
            -- Trust dropped, delete notification
            MySQL.update([[
                DELETE FROM ai_npc_notifications WHERE id = ?
            ]], {notif.id})
        end
    end
end

-----------------------------------------------------------
-- SEND PHONE NOTIFICATION
-----------------------------------------------------------
function SendPhoneNotification(playerId, notification)
    -- Get NPC info for sender name
    local npcName = "Unknown Contact"
    for _, npc in pairs(Config.NPCs) do
        if npc.id == notification.npc_id then
            npcName = npc.name
            break
        end
    end

    -- Try different phone systems
    -- QBCore phone (qb-phone)
    if GetResourceState('qb-phone') == 'started' then
        TriggerClientEvent('qb-phone:client:CustomNotification', playerId,
            npcName,
            notification.message,
            'fas fa-user-secret',
            '#ff6b35',
            10000
        )
    end

    -- GKS Phone
    if GetResourceState('gksphone') == 'started' then
        TriggerClientEvent('gksphone:client:addNotification', playerId, {
            title = npcName,
            text = notification.message,
            icon = 'user-secret',
            color = '#ff6b35'
        })
    end

    -- NPWD / New Phone Who Dis
    if GetResourceState('npwd') == 'started' then
        exports.npwd:createNotification({
            notisId = 'ai-npc-' .. notification.id,
            appId = 'MESSAGES',
            title = npcName,
            content = notification.message,
        })
    end

    -- LB Phone
    if GetResourceState('lb-phone') == 'started' then
        TriggerClientEvent('lb-phone:notification', playerId, {
            app = 'Messages',
            title = npcName,
            content = notification.message,
            icon = 'user-secret'
        })
    end

    -- Fallback: ox_lib notification
    TriggerClientEvent('ox_lib:notify', playerId, {
        title = 'Message from ' .. npcName,
        description = notification.message:sub(1, 100),
        type = 'info',
        duration = 10000
    })

    if Config.Debug.enabled then
        print(("[AI NPCs] Sent notification to %s from %s: %s"):format(
            playerId, npcName, notification.title
        ))
    end
end

-----------------------------------------------------------
-- CREATE NOTIFICATION FOR PLAYER
-----------------------------------------------------------
function CreateNPCNotification(citizenid, npcId, notifType, title, message, options)
    options = options or {}

    -- Check if player has enough trust
    local trustResult = MySQL.scalar.await([[
        SELECT trust_value FROM ai_npc_trust
        WHERE citizenid = ? AND npc_id = ?
    ]], {citizenid, npcId})

    local trustRequired = options.trustRequired or MIN_TRUST_FOR_NOTIFICATIONS
    if (trustResult or 0) < trustRequired then
        return false, "insufficient_trust"
    end

    -- Calculate expiry
    local expiresAt = nil
    if options.expiresInHours then
        expiresAt = os.date("%Y-%m-%d %H:%M:%S", os.time() + (options.expiresInHours * 3600))
    end

    -- Calculate send time (can be delayed)
    local sendAfter = os.date("%Y-%m-%d %H:%M:%S")
    if options.delayMinutes then
        sendAfter = os.date("%Y-%m-%d %H:%M:%S", os.time() + (options.delayMinutes * 60))
    end

    MySQL.insert([[
        INSERT INTO ai_npc_notifications
        (citizenid, npc_id, notification_type, title, message, priority, trust_required, send_after, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        npcId,
        notifType,
        title,
        message,
        options.priority or 5,
        trustRequired,
        sendAfter,
        expiresAt
    })

    -- If player is online and no delay, send immediately
    if not options.delayMinutes then
        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        if Player then
            SetTimeout(2000, function()
                CheckPendingNotifications(Player.PlayerData.source)
            end)
        end
    end

    return true
end

-----------------------------------------------------------
-- NOTIFICATION TEMPLATES
-----------------------------------------------------------
function SendIntelNotification(citizenid, npcId, intelTitle)
    local npcName = "Contact"
    for _, npc in pairs(Config.NPCs) do
        if npc.id == npcId then
            npcName = npc.name
            break
        end
    end

    local messages = {
        "Got something for you. Stop by when you can.",
        "New info just came in. Think you'd be interested.",
        "Word on the street... come see me.",
        "Opportunity knocked. You listening?",
        "Need to talk. In person. Soon.",
    }

    CreateNPCNotification(citizenid, npcId, 'intel',
        'New Intel Available',
        messages[math.random(#messages)],
        { priority = 7, expiresInHours = 24 }
    )
end

function SendQuestNotification(citizenid, npcId, questTitle)
    CreateNPCNotification(citizenid, npcId, 'quest',
        'Job Opportunity',
        "Got a job you might be interested in. Come see me.",
        { priority = 6, expiresInHours = 48 }
    )
end

function SendDebtReminder(citizenid, npcId, amount)
    local messages = {
        string.format("You owe me $%d. Don't forget.", amount),
        string.format("Remember that $%d? I remember.", amount),
        string.format("Tick tock. $%d. You know where to find me.", amount),
    }

    CreateNPCNotification(citizenid, npcId, 'debt',
        'Payment Reminder',
        messages[math.random(#messages)],
        { priority = 8, expiresInHours = 72 }
    )
end

function SendWarningNotification(citizenid, npcId, warningText)
    CreateNPCNotification(citizenid, npcId, 'warning',
        'Warning',
        warningText,
        { priority = 9, expiresInHours = 12 }
    )
end

function SendOpportunityNotification(citizenid, npcId, opportunityText)
    CreateNPCNotification(citizenid, npcId, 'opportunity',
        'Limited Opportunity',
        opportunityText,
        { priority = 7, expiresInHours = 6 }
    )
end

-----------------------------------------------------------
-- EVENTS
-----------------------------------------------------------
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    SetTimeout(5000, function()  -- Delay to let phone load
        CheckPendingNotifications(Player.PlayerData.source)
    end)
end)

RegisterNetEvent('ai-npcs:server:checkNotifications', function()
    local src = source
    CheckPendingNotifications(src)
end)

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
exports('CreateNPCNotification', CreateNPCNotification)
exports('SendIntelNotification', SendIntelNotification)
exports('SendQuestNotification', SendQuestNotification)
exports('SendDebtReminder', SendDebtReminder)
exports('SendWarningNotification', SendWarningNotification)
exports('SendOpportunityNotification', SendOpportunityNotification)

-----------------------------------------------------------
-- PERIODIC DEBT REMINDERS
-----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(3600000)  -- Every hour

        -- Find overdue debts
        local overdueDebts = MySQL.query.await([[
            SELECT d.citizenid, d.npc_id, d.amount
            FROM ai_npc_debts d
            WHERE d.status = 'pending'
            AND d.due_by IS NOT NULL
            AND d.due_by < NOW()
        ]])

        if overdueDebts then
            for _, debt in ipairs(overdueDebts) do
                SendDebtReminder(debt.citizenid, debt.npc_id, debt.amount)
            end
        end
    end
end)

print("^2[AI NPCs]^7 Phone Notifications system loaded")
