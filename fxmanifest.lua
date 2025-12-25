fx_version 'cerulean'
game 'gta5'

name 'ai-npcs'
author 'DaemonAlex'
description 'AI-powered NPC conversation system with trust, quests, and intel'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/ai_handler.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'audio/*.ogg'
}

lua54 'yes'

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql',
    'qb-core'
}

-- Exports for other resources
exports {
    -- Trust
    'GetPlayerTrustWithNPC',
    'AddPlayerTrustWithNPC',
    'SetPlayerTrustWithNPC',

    -- Quests
    'OfferQuestToPlayer',
    'CompletePlayerQuest',
    'GetPlayerQuestStatus',

    -- Referrals
    'CreatePlayerReferral',
    'HasPlayerReferral',

    -- Debts
    'CreatePlayerDebt',
    'GetPlayerDebts',
    'PayPlayerDebt',

    -- Memories
    'AddNPCMemoryAboutPlayer',
    'GetNPCMemoriesAboutPlayer'
}
