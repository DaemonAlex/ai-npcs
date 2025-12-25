-- AI NPCs v2.5 Database Upgrade
-- Run this AFTER install.sql if upgrading from v2.0

-- =========================================================
-- FACTION TRUST (Group Dynamics)
-- =========================================================
-- Tracks trust with entire factions, not just individual NPCs
CREATE TABLE IF NOT EXISTS `ai_npc_faction_trust` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `faction` VARCHAR(50) NOT NULL,  -- 'vagos', 'ballas', 'families', 'lost_mc', 'cartel', 'mafia', etc.
    `trust_value` INT DEFAULT 0,
    `reputation` ENUM('unknown', 'enemy', 'neutral', 'friendly', 'ally', 'blood') DEFAULT 'unknown',
    `kills_for` INT DEFAULT 0,       -- Members killed FOR this faction
    `kills_against` INT DEFAULT 0,   -- Members killed OF this faction
    `missions_completed` INT DEFAULT 0,
    `last_interaction` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_player_faction` (`citizenid`, `faction`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_faction` (`faction`),
    INDEX `idx_reputation` (`reputation`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- RUMOR MILL (Dynamic World Knowledge)
-- =========================================================
-- Tracks notable player actions that NPCs can gossip about
CREATE TABLE IF NOT EXISTS `ai_npc_rumors` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,           -- Who did it
    `action_type` VARCHAR(50) NOT NULL,         -- 'bank_robbery', 'murder', 'drug_sale', 'arrest', etc.
    `action_details` JSON DEFAULT NULL,         -- { location: "Pacific Standard", amount: 500000, etc. }
    `visibility` ENUM('underground', 'street', 'citywide', 'legendary') DEFAULT 'street',
    `heat_level` INT DEFAULT 50,                -- 0-100, decays over time
    `witnesses` INT DEFAULT 0,                  -- How many saw it
    `is_public` BOOLEAN DEFAULT FALSE,          -- Was it on the news?
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `expires_at` TIMESTAMP NULL,                -- When rumor fades
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_action_type` (`action_type`),
    INDEX `idx_visibility` (`visibility`),
    INDEX `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- TIME-SENSITIVE INTEL
-- =========================================================
-- Intel that expires or changes over time
CREATE TABLE IF NOT EXISTS `ai_npc_intel` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `npc_id` VARCHAR(50) NOT NULL,              -- Which NPC knows this
    `intel_type` VARCHAR(50) NOT NULL,          -- 'bank_job', 'stash_location', etc.
    `category` VARCHAR(50) NOT NULL,            -- 'heist', 'drugs', 'info', etc.
    `title` VARCHAR(255) NOT NULL,
    `details` JSON DEFAULT NULL,                -- Specific intel details
    `value` INT DEFAULT 0,                      -- Price in dollars
    `trust_required` INT DEFAULT 0,
    `expires_at` TIMESTAMP NULL,                -- Intel expires after this
    `max_buyers` INT DEFAULT 1,                 -- Limited availability
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_npc_id` (`npc_id`),
    INDEX `idx_intel_type` (`intel_type`),
    INDEX `idx_category` (`category`),
    INDEX `idx_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Track who bought what intel
CREATE TABLE IF NOT EXISTS `ai_npc_intel_purchases` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `intel_id` INT NOT NULL,                    -- References ai_npc_intel.id
    `citizenid` VARCHAR(50) NOT NULL,
    `price_paid` INT DEFAULT 0,
    `purchased_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_purchase` (`citizenid`, `intel_id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_intel_id` (`intel_id`),
    FOREIGN KEY (`intel_id`) REFERENCES `ai_npc_intel`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- PHONE NOTIFICATIONS (Offline Messaging)
-- =========================================================
-- Queue messages to send when player comes online
CREATE TABLE IF NOT EXISTS `ai_npc_notifications` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `npc_id` VARCHAR(50) NOT NULL,
    `notification_type` ENUM('intel', 'quest', 'debt', 'warning', 'opportunity') NOT NULL,
    `title` VARCHAR(100) NOT NULL,
    `message` TEXT NOT NULL,
    `priority` INT DEFAULT 5,                   -- 1-10, higher = more urgent
    `trust_required` INT DEFAULT 50,            -- Minimum trust to receive
    `is_sent` BOOLEAN DEFAULT FALSE,
    `is_read` BOOLEAN DEFAULT FALSE,
    `send_after` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `expires_at` TIMESTAMP NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_is_sent` (`is_sent`),
    INDEX `idx_priority` (`priority`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- CO-OP QUESTS (Group Missions)
-- =========================================================
-- Track shared quests between players
CREATE TABLE IF NOT EXISTS `ai_npc_coop_quests` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `quest_id` VARCHAR(100) NOT NULL,
    `leader_citizenid` VARCHAR(50) NOT NULL,
    `npc_id` VARCHAR(50) NOT NULL,
    `quest_type` VARCHAR(50) NOT NULL,
    `min_players` INT DEFAULT 2,
    `max_players` INT DEFAULT 4,
    `status` ENUM('forming', 'active', 'completed', 'failed', 'abandoned') DEFAULT 'forming',
    `quest_data` JSON DEFAULT NULL,
    `started_at` TIMESTAMP NULL,
    `completed_at` TIMESTAMP NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_coop_quest` (`quest_id`),
    INDEX `idx_leader` (`leader_citizenid`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Members of co-op quests
CREATE TABLE IF NOT EXISTS `ai_npc_coop_members` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `quest_id` VARCHAR(100) NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `role` VARCHAR(50) DEFAULT 'member',        -- 'leader', 'member', 'muscle', 'driver', 'hacker', etc.
    `contribution` INT DEFAULT 0,               -- Track individual contribution
    `joined_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_member` (`quest_id`, `citizenid`),
    INDEX `idx_citizenid` (`citizenid`),
    FOREIGN KEY (`quest_id`) REFERENCES `ai_npc_coop_quests`(`quest_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- NPC RELATIONSHIPS (NPC-to-NPC Communication)
-- =========================================================
-- Define relationships between NPCs
CREATE TABLE IF NOT EXISTS `ai_npc_relationships` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `npc_id` VARCHAR(50) NOT NULL,
    `related_npc_id` VARCHAR(50) NOT NULL,
    `relationship` ENUM('ally', 'friend', 'neutral', 'rival', 'enemy') NOT NULL,
    `shares_intel` BOOLEAN DEFAULT FALSE,       -- Do they share player info?
    `shares_trust` BOOLEAN DEFAULT FALSE,       -- Does trust affect both?
    `trust_modifier` FLOAT DEFAULT 1.0,         -- Multiplier for shared trust
    UNIQUE KEY `unique_relationship` (`npc_id`, `related_npc_id`),
    INDEX `idx_npc_id` (`npc_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- PLAYER ACTIONS LOG (For Rumor Mill)
-- =========================================================
-- Detailed log of player criminal activity
CREATE TABLE IF NOT EXISTS `ai_npc_player_actions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `action_category` VARCHAR(50) NOT NULL,     -- 'crime', 'business', 'social', 'gang'
    `action_type` VARCHAR(100) NOT NULL,        -- 'bank_robbery', 'drug_sale', 'assault', etc.
    `target_type` VARCHAR(50) DEFAULT NULL,     -- 'npc', 'player', 'business', 'vehicle'
    `target_id` VARCHAR(100) DEFAULT NULL,      -- ID of target
    `location` VARCHAR(100) DEFAULT NULL,       -- Zone/area name
    `coords` VARCHAR(100) DEFAULT NULL,         -- x,y,z coordinates
    `value` INT DEFAULT 0,                      -- Money/item value involved
    `severity` INT DEFAULT 5,                   -- 1-10 scale
    `witnesses` INT DEFAULT 0,
    `reported_to_police` BOOLEAN DEFAULT FALSE,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_action_type` (`action_type`),
    INDEX `idx_created_at` (`created_at`),
    INDEX `idx_severity` (`severity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- INTERROGATION SYSTEM
-- =========================================================
-- Track interrogation attempts and NPC resistance
CREATE TABLE IF NOT EXISTS `ai_npc_interrogations` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `npc_id` VARCHAR(50) NOT NULL,
    `interrogator_citizenid` VARCHAR(50) NOT NULL,
    `interrogator_job` VARCHAR(50) NOT NULL,    -- 'police', 'fib', etc.
    `method` ENUM('friendly', 'standard', 'aggressive', 'torture') DEFAULT 'standard',
    `resistance_level` INT DEFAULT 50,          -- 0-100, how hard NPC resists
    `intel_revealed` JSON DEFAULT NULL,         -- What they gave up
    `success` BOOLEAN DEFAULT FALSE,
    `npc_broken` BOOLEAN DEFAULT FALSE,         -- Did they fully break?
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_npc_id` (`npc_id`),
    INDEX `idx_interrogator` (`interrogator_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =========================================================
-- CLEANUP JOBS (Scheduled maintenance)
-- =========================================================

-- Event to clean expired data daily
DELIMITER //
CREATE EVENT IF NOT EXISTS `cleanup_expired_ai_npc_data`
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    -- Clean expired rumors
    DELETE FROM `ai_npc_rumors` WHERE `expires_at` IS NOT NULL AND `expires_at` < NOW();
    -- Clean expired intel
    DELETE FROM `ai_npc_intel` WHERE `expires_at` IS NOT NULL AND `expires_at` < NOW();
    -- Clean expired notifications
    DELETE FROM `ai_npc_notifications` WHERE `expires_at` IS NOT NULL AND `expires_at` < NOW();
    -- Decay rumor heat levels
    UPDATE `ai_npc_rumors` SET `heat_level` = GREATEST(0, `heat_level` - 10) WHERE `heat_level` > 0;
    -- Clean old player action logs (keep 30 days)
    DELETE FROM `ai_npc_player_actions` WHERE `created_at` < DATE_SUB(NOW(), INTERVAL 30 DAY);
END //
DELIMITER ;
