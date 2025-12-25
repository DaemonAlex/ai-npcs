--[[
    CO-OP QUEST SYSTEM
    Shared quests between multiple players
]]

local QBCore = exports['qb-core']:GetCoreObject()

-- Active co-op quests in memory
local activeCoopQuests = {}  -- { [quest_id] = { data } }

-----------------------------------------------------------
-- CREATE CO-OP QUEST
-----------------------------------------------------------
function CreateCoopQuest(leaderCitizenid, npcId, questId, questType, questData)
    questData = questData or {}

    local fullQuestId = string.format("%s_%s_%d", npcId, questId, os.time())

    MySQL.insert.await([[
        INSERT INTO ai_npc_coop_quests
        (quest_id, leader_citizenid, npc_id, quest_type, min_players, max_players, status, quest_data)
        VALUES (?, ?, ?, ?, ?, ?, 'forming', ?)
    ]], {
        fullQuestId,
        leaderCitizenid,
        npcId,
        questType,
        questData.minPlayers or 2,
        questData.maxPlayers or 4,
        json.encode(questData)
    })

    -- Add leader as first member
    MySQL.insert.await([[
        INSERT INTO ai_npc_coop_members (quest_id, citizenid, role)
        VALUES (?, ?, 'leader')
    ]], {fullQuestId, leaderCitizenid})

    -- Cache it
    activeCoopQuests[fullQuestId] = {
        id = fullQuestId,
        leader = leaderCitizenid,
        npcId = npcId,
        questType = questType,
        data = questData,
        members = { [leaderCitizenid] = { role = 'leader', contribution = 0 } },
        status = 'forming',
        createdAt = os.time()
    }

    if Config.Debug.enabled then
        print(("[AI NPCs] Co-op quest created: %s by %s"):format(fullQuestId, leaderCitizenid))
    end

    return fullQuestId
end

-----------------------------------------------------------
-- JOIN CO-OP QUEST
-----------------------------------------------------------
function JoinCoopQuest(questId, citizenid, role)
    local quest = activeCoopQuests[questId]
    if not quest then
        -- Try loading from DB
        quest = LoadCoopQuest(questId)
        if not quest then return false, "quest_not_found" end
    end

    if quest.status ~= 'forming' then
        return false, "quest_already_started"
    end

    -- Count current members
    local memberCount = 0
    for _ in pairs(quest.members) do memberCount = memberCount + 1 end

    if memberCount >= (quest.data.maxPlayers or 4) then
        return false, "quest_full"
    end

    if quest.members[citizenid] then
        return false, "already_joined"
    end

    role = role or 'member'

    MySQL.insert.await([[
        INSERT INTO ai_npc_coop_members (quest_id, citizenid, role)
        VALUES (?, ?, ?)
    ]], {questId, citizenid, role})

    quest.members[citizenid] = { role = role, contribution = 0 }

    -- Notify leader
    local Leader = QBCore.Functions.GetPlayerByCitizenId(quest.leader)
    if Leader then
        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        local playerName = Player and Player.PlayerData.charinfo.firstname or "Someone"
        TriggerClientEvent('ox_lib:notify', Leader.PlayerData.source, {
            title = 'Crew Update',
            description = playerName .. ' joined your crew',
            type = 'success'
        })
    end

    if Config.Debug.enabled then
        print(("[AI NPCs] %s joined co-op quest %s as %s"):format(citizenid, questId, role))
    end

    return true
end

-----------------------------------------------------------
-- LEAVE CO-OP QUEST
-----------------------------------------------------------
function LeaveCoopQuest(questId, citizenid)
    local quest = activeCoopQuests[questId]
    if not quest then return false, "quest_not_found" end

    if not quest.members[citizenid] then
        return false, "not_in_quest"
    end

    -- Can't leave if you're the leader and quest is active
    if quest.members[citizenid].role == 'leader' and quest.status == 'active' then
        return false, "leader_cannot_leave_active"
    end

    MySQL.update.await([[
        DELETE FROM ai_npc_coop_members WHERE quest_id = ? AND citizenid = ?
    ]], {questId, citizenid})

    quest.members[citizenid] = nil

    -- If leader left during forming, promote someone or cancel
    if quest.members[citizenid] and quest.members[citizenid].role == 'leader' then
        local newLeader = nil
        for cid, data in pairs(quest.members) do
            newLeader = cid
            break
        end

        if newLeader then
            quest.members[newLeader].role = 'leader'
            quest.leader = newLeader
            MySQL.update.await([[
                UPDATE ai_npc_coop_members SET role = 'leader' WHERE quest_id = ? AND citizenid = ?
            ]], {questId, newLeader})
            MySQL.update.await([[
                UPDATE ai_npc_coop_quests SET leader_citizenid = ? WHERE quest_id = ?
            ]], {newLeader, questId})
        else
            -- No one left, cancel quest
            CancelCoopQuest(questId, "all_left")
        end
    end

    return true
end

-----------------------------------------------------------
-- START CO-OP QUEST
-----------------------------------------------------------
function StartCoopQuest(questId, leaderCitizenid)
    local quest = activeCoopQuests[questId]
    if not quest then return false, "quest_not_found" end

    if quest.leader ~= leaderCitizenid then
        return false, "not_leader"
    end

    if quest.status ~= 'forming' then
        return false, "invalid_status"
    end

    -- Check minimum players
    local memberCount = 0
    for _ in pairs(quest.members) do memberCount = memberCount + 1 end

    if memberCount < (quest.data.minPlayers or 2) then
        return false, "not_enough_players"
    end

    quest.status = 'active'
    quest.startedAt = os.time()

    MySQL.update.await([[
        UPDATE ai_npc_coop_quests SET status = 'active', started_at = NOW() WHERE quest_id = ?
    ]], {questId})

    -- Notify all members
    for citizenid, _ in pairs(quest.members) do
        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        if Player then
            TriggerClientEvent('ox_lib:notify', Player.PlayerData.source, {
                title = 'Quest Started',
                description = 'Your crew quest has begun!',
                type = 'success'
            })
            TriggerClientEvent('ai-npcs:client:coopQuestStarted', Player.PlayerData.source, quest)
        end
    end

    if Config.Debug.enabled then
        print(("[AI NPCs] Co-op quest started: %s with %d members"):format(questId, memberCount))
    end

    return true
end

-----------------------------------------------------------
-- UPDATE MEMBER CONTRIBUTION
-----------------------------------------------------------
function UpdateCoopContribution(questId, citizenid, amount)
    local quest = activeCoopQuests[questId]
    if not quest then return false end

    if not quest.members[citizenid] then return false end

    quest.members[citizenid].contribution = (quest.members[citizenid].contribution or 0) + amount

    MySQL.update.await([[
        UPDATE ai_npc_coop_members SET contribution = contribution + ? WHERE quest_id = ? AND citizenid = ?
    ]], {amount, questId, citizenid})

    return true
end

-----------------------------------------------------------
-- COMPLETE CO-OP QUEST
-----------------------------------------------------------
function CompleteCoopQuest(questId, success)
    local quest = activeCoopQuests[questId]
    if not quest then return false, "quest_not_found" end

    local status = success and 'completed' or 'failed'
    quest.status = status

    MySQL.update.await([[
        UPDATE ai_npc_coop_quests SET status = ?, completed_at = NOW() WHERE quest_id = ?
    ]], {status, questId})

    -- Calculate rewards based on contribution
    local totalContribution = 0
    for _, data in pairs(quest.members) do
        totalContribution = totalContribution + (data.contribution or 0)
    end

    local baseReward = quest.data.reward or {}
    local baseTrust = baseReward.trust or 20
    local baseMoney = baseReward.money or 10000

    -- Distribute rewards
    for citizenid, data in pairs(quest.members) do
        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)

        if success then
            -- Calculate share based on contribution
            local share = totalContribution > 0 and (data.contribution / totalContribution) or (1 / #quest.members)
            share = math.max(0.1, share)  -- Minimum 10% share

            local trustReward = math.floor(baseTrust * share * (data.role == 'leader' and 1.2 or 1.0))
            local moneyReward = math.floor(baseMoney * share)

            -- Award trust
            if quest.npcId then
                exports['ai-npcs']:AddPlayerTrustWithNPC(
                    Player and Player.PlayerData.source or 0,
                    quest.npcId,
                    trustReward
                )
            end

            -- Award money
            if Player and moneyReward > 0 then
                Player.Functions.AddMoney('cash', moneyReward, 'coop-quest-reward')
            end

            -- Notify
            if Player then
                TriggerClientEvent('ox_lib:notify', Player.PlayerData.source, {
                    title = 'Quest Complete!',
                    description = string.format('Earned $%d and %d trust', moneyReward, trustReward),
                    type = 'success'
                })
            end
        else
            -- Failed - notify only
            if Player then
                TriggerClientEvent('ox_lib:notify', Player.PlayerData.source, {
                    title = 'Quest Failed',
                    description = 'The job went sideways...',
                    type = 'error'
                })
            end
        end
    end

    -- Clean up
    activeCoopQuests[questId] = nil

    if Config.Debug.enabled then
        print(("[AI NPCs] Co-op quest %s: %s"):format(status, questId))
    end

    return true
end

-----------------------------------------------------------
-- CANCEL CO-OP QUEST
-----------------------------------------------------------
function CancelCoopQuest(questId, reason)
    local quest = activeCoopQuests[questId]

    MySQL.update.await([[
        UPDATE ai_npc_coop_quests SET status = 'abandoned' WHERE quest_id = ?
    ]], {questId})

    if quest then
        for citizenid, _ in pairs(quest.members) do
            local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
            if Player then
                TriggerClientEvent('ox_lib:notify', Player.PlayerData.source, {
                    title = 'Quest Cancelled',
                    description = reason or 'The job has been called off',
                    type = 'error'
                })
            end
        end
        activeCoopQuests[questId] = nil
    end

    return true
end

-----------------------------------------------------------
-- GET PLAYER'S ACTIVE CO-OP QUESTS
-----------------------------------------------------------
function GetPlayerCoopQuests(citizenid)
    local quests = MySQL.query.await([[
        SELECT q.*, m.role, m.contribution
        FROM ai_npc_coop_quests q
        JOIN ai_npc_coop_members m ON m.quest_id = q.quest_id
        WHERE m.citizenid = ? AND q.status IN ('forming', 'active')
    ]], {citizenid})

    return quests or {}
end

-----------------------------------------------------------
-- LOAD CO-OP QUEST FROM DB
-----------------------------------------------------------
function LoadCoopQuest(questId)
    local quest = MySQL.single.await([[
        SELECT * FROM ai_npc_coop_quests WHERE quest_id = ?
    ]], {questId})

    if not quest then return nil end

    local members = MySQL.query.await([[
        SELECT * FROM ai_npc_coop_members WHERE quest_id = ?
    ]], {questId})

    local memberMap = {}
    for _, m in ipairs(members or {}) do
        memberMap[m.citizenid] = { role = m.role, contribution = m.contribution }
    end

    local loaded = {
        id = quest.quest_id,
        leader = quest.leader_citizenid,
        npcId = quest.npc_id,
        questType = quest.quest_type,
        data = json.decode(quest.quest_data or "{}"),
        members = memberMap,
        status = quest.status
    }

    activeCoopQuests[questId] = loaded
    return loaded
end

-----------------------------------------------------------
-- INVITE PLAYER TO CO-OP
-----------------------------------------------------------
function InviteToCoopQuest(questId, inviterCitizenid, targetPlayerId)
    local quest = activeCoopQuests[questId]
    if not quest then return false, "quest_not_found" end

    if quest.status ~= 'forming' then
        return false, "quest_already_started"
    end

    local Target = QBCore.Functions.GetPlayer(targetPlayerId)
    if not Target then return false, "player_not_found" end

    local Inviter = QBCore.Functions.GetPlayerByCitizenId(inviterCitizenid)
    local inviterName = Inviter and Inviter.PlayerData.charinfo.firstname or "Someone"

    -- Send invite to target
    TriggerClientEvent('ai-npcs:client:coopQuestInvite', targetPlayerId, {
        questId = questId,
        inviter = inviterName,
        questType = quest.questType,
        npcId = quest.npcId
    })

    return true
end

-----------------------------------------------------------
-- EXPORTS
-----------------------------------------------------------
exports('CreateCoopQuest', CreateCoopQuest)
exports('JoinCoopQuest', JoinCoopQuest)
exports('LeaveCoopQuest', LeaveCoopQuest)
exports('StartCoopQuest', StartCoopQuest)
exports('UpdateCoopContribution', UpdateCoopContribution)
exports('CompleteCoopQuest', CompleteCoopQuest)
exports('CancelCoopQuest', CancelCoopQuest)
exports('GetPlayerCoopQuests', GetPlayerCoopQuests)
exports('InviteToCoopQuest', InviteToCoopQuest)

-----------------------------------------------------------
-- EVENTS
-----------------------------------------------------------
RegisterNetEvent('ai-npcs:server:acceptCoopInvite', function(questId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local success, err = JoinCoopQuest(questId, Player.PlayerData.citizenid)
    if success then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Joined Crew',
            description = 'You joined the job',
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Error',
            description = err or 'Could not join',
            type = 'error'
        })
    end
end)

RegisterNetEvent('ai-npcs:server:declineCoopInvite', function(questId)
    -- Just ignore, maybe notify inviter
end)

-----------------------------------------------------------
-- CLEANUP STALE QUESTS
-----------------------------------------------------------
CreateThread(function()
    while true do
        Wait(300000)  -- Every 5 minutes

        -- Cancel forming quests older than 30 minutes
        MySQL.update([[
            UPDATE ai_npc_coop_quests
            SET status = 'abandoned'
            WHERE status = 'forming'
            AND created_at < DATE_SUB(NOW(), INTERVAL 30 MINUTE)
        ]])

        -- Cancel active quests older than 4 hours (assumed failed/abandoned)
        MySQL.update([[
            UPDATE ai_npc_coop_quests
            SET status = 'abandoned'
            WHERE status = 'active'
            AND started_at < DATE_SUB(NOW(), INTERVAL 4 HOUR)
        ]])
    end
end)

print("^2[AI NPCs]^7 Co-op Quest system loaded")
