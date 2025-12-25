-- AI NPCs Database Schema
-- Run this SQL to set up the required tables

-- Trust/Reputation tracking per player per NPC
CREATE TABLE IF NOT EXISTS `ai_npc_trust` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `npc_id` VARCHAR(50) NOT NULL,
    `trust_category` VARCHAR(50) NOT NULL,
    `trust_value` INT DEFAULT 0,
    `total_payments` INT DEFAULT 0,
    `conversation_count` INT DEFAULT 0,
    `last_interaction` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_player_npc` (`citizenid`, `npc_id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_npc_id` (`npc_id`),
    INDEX `idx_trust_category` (`trust_category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Quest/Task progress tracking
CREATE TABLE IF NOT EXISTS `ai_npc_quests` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `npc_id` VARCHAR(50) NOT NULL,
    `quest_id` VARCHAR(100) NOT NULL,
    `quest_type` ENUM('item_delivery', 'task', 'payment', 'kill', 'frame', 'escort', 'other') NOT NULL,
    `status` ENUM('offered', 'accepted', 'in_progress', 'completed', 'failed') DEFAULT 'offered',
    `quest_data` JSON DEFAULT NULL,
    `reward_claimed` BOOLEAN DEFAULT FALSE,
    `offered_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `completed_at` TIMESTAMP NULL,
    UNIQUE KEY `unique_player_quest` (`citizenid`, `npc_id`, `quest_id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Intel cooldowns (prevent farming)
CREATE TABLE IF NOT EXISTS `ai_npc_intel_cooldowns` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `topic` VARCHAR(100) NOT NULL,
    `tier` VARCHAR(50) NOT NULL,
    `accessed_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `unique_player_topic` (`citizenid`, `topic`),
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Referral tracking (who introduced who)
CREATE TABLE IF NOT EXISTS `ai_npc_referrals` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `from_npc_id` VARCHAR(50) NOT NULL,
    `to_npc_id` VARCHAR(50) NOT NULL,
    `referral_type` VARCHAR(50) DEFAULT 'standard',
    `used` BOOLEAN DEFAULT FALSE,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_to_npc` (`to_npc_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Debts/Promises tracking (for "pay me later" quests)
CREATE TABLE IF NOT EXISTS `ai_npc_debts` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `npc_id` VARCHAR(50) NOT NULL,
    `debt_type` ENUM('money', 'favor', 'item', 'percentage') NOT NULL,
    `amount` INT DEFAULT 0,
    `description` VARCHAR(255) DEFAULT NULL,
    `status` ENUM('pending', 'paid', 'defaulted') DEFAULT 'pending',
    `due_by` TIMESTAMP NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `paid_at` TIMESTAMP NULL,
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- NPC relationship notes (NPCs remember things about players)
CREATE TABLE IF NOT EXISTS `ai_npc_memories` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(50) NOT NULL,
    `npc_id` VARCHAR(50) NOT NULL,
    `memory_type` ENUM('positive', 'negative', 'neutral', 'warning') NOT NULL,
    `memory_text` TEXT NOT NULL,
    `importance` INT DEFAULT 5,
    `expires_at` TIMESTAMP NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX `idx_citizenid_npc` (`citizenid`, `npc_id`),
    INDEX `idx_importance` (`importance`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
