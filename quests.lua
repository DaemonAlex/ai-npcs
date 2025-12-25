--[[
    QUEST DEFINITIONS
    All available quests for NPCs organized by category
]]

Config.Quests = {}

-----------------------------------------------------------
-- QUEST STRUCTURE TEMPLATE
-----------------------------------------------------------
--[[
    {
        id = "unique_quest_id",
        title = "Display Name",
        description = "What the NPC tells you",
        type = "delivery|kill|escort|retrieve|plant|dispose|frame|surveillance|intimidate",

        -- Requirements
        trustRequired = 0-100,
        referralRequired = nil or "npc_id",
        cooldown = 3600,  -- seconds between repeats
        oneTime = false,  -- true = can only complete once ever

        -- Conditions
        jobRequired = nil or {"police", "ems"},
        jobBlocked = nil or {"police"},  -- can't do if this job
        timeWindow = nil or {start = 20, end = 4},  -- night only
        weatherRequired = nil,  -- "RAIN", etc.

        -- Objectives
        objectives = {
            {type = "goto", coords = vector3(x,y,z), radius = 5.0},
            {type = "deliver", item = "item_name", amount = 1},
            {type = "kill", target = "npc_model", count = 1},
            {type = "wait", duration = 60},  -- seconds
        },

        -- Rewards
        reward = {
            money = 1000,
            trust = 10,
            item = nil or {name = "item", amount = 1},
            unlocks = nil or "next_quest_id",
            referral = nil or "new_npc_id"
        },

        -- Failure conditions
        failConditions = {
            timeout = 3600,
            playerDeath = true,
            policeNearby = false,
            witnessed = false
        },

        -- Co-op settings
        coop = nil or {
            minPlayers = 2,
            maxPlayers = 4,
            roles = {"driver", "muscle", "lookout"}
        }
    }
]]

-----------------------------------------------------------
-- STREET DEALER QUESTS (Trust: 0-40)
-----------------------------------------------------------
Config.Quests.street_dealer = {
    -- Tier 1: Building Trust (0-15)
    {
        id = "dealer_first_delivery",
        title = "First Run",
        description = "I got a package needs to get downtown. Nothing heavy, just a test run. You in?",
        type = "delivery",
        trustRequired = 0,
        objectives = {
            {type = "pickup", location = "dealer", item = "small_package"},
            {type = "deliver", location = "mirror_park", timeout = 600}
        },
        reward = {money = 500, trust = 5},
        failConditions = {timeout = 600, playerDeath = true}
    },
    {
        id = "dealer_corner_watch",
        title = "Watch the Corner",
        description = "I need eyes on the block for an hour. You see any badges, you text me. Simple.",
        type = "surveillance",
        trustRequired = 5,
        objectives = {
            {type = "stay_in_area", coords = vector3(-120.5, -1042.3, 27.3), radius = 50.0, duration = 600},
            {type = "report_police", count = 0}  -- Any police = report
        },
        reward = {money = 300, trust = 5},
        failConditions = {timeout = 900, playerDeath = true}
    },
    {
        id = "dealer_collect_debt",
        title = "Debt Collection",
        description = "Some fool owes me two bills. Go remind him what happens when you don't pay.",
        type = "intimidate",
        trustRequired = 10,
        objectives = {
            {type = "find_npc", model = "a_m_m_soucent_02", location = "forum_drive"},
            {type = "intimidate", target = "debtor", method = "threaten"}
        },
        reward = {money = 200, trust = 8, item = {name = "money_bag", amount = 1}},
        failConditions = {playerDeath = true, targetDeath = true}  -- Can't kill the debtor
    },

    -- Tier 2: Trusted Runner (15-30)
    {
        id = "dealer_bulk_delivery",
        title = "Bulk Run",
        description = "Got a bigger package. Multiple drops. Think you can handle it?",
        type = "delivery",
        trustRequired = 15,
        objectives = {
            {type = "pickup", location = "dealer", item = "medium_package"},
            {type = "deliver", location = "strawberry", timeout = 300},
            {type = "deliver", location = "davis", timeout = 300},
            {type = "deliver", location = "rancho", timeout = 300}
        },
        reward = {money = 1500, trust = 10},
        failConditions = {timeout = 1200, playerDeath = true, policeNearby = true}
    },
    {
        id = "dealer_stash_pickup",
        title = "Stash Run",
        description = "Need you to pick up from my stash. It's hidden good. Don't get followed.",
        type = "retrieve",
        trustRequired = 20,
        objectives = {
            {type = "goto", coords = vector3(-1086.2, -1595.4, 4.4), radius = 2.0},
            {type = "interact", action = "search_dumpster"},
            {type = "retrieve", item = "drug_stash"},
            {type = "return", location = "dealer", timeout = 600}
        },
        reward = {money = 800, trust = 10},
        failConditions = {timeout = 900, policeNearby = true}
    },
    {
        id = "dealer_supplier_meeting",
        title = "Meet the Man",
        description = "My supplier wants to meet you. Don't fuck this up.",
        type = "escort",
        trustRequired = 25,
        objectives = {
            {type = "goto", coords = vector3(-73.2, -1821.5, 26.9)},
            {type = "wait", duration = 30},
            {type = "talk_to", npc = "supplier_npc"}
        },
        reward = {trust = 15, referral = "mid_level_dealer"},
        failConditions = {playerDeath = true}
    },

    -- Tier 3: Inner Circle (30-40)
    {
        id = "dealer_snitch_problem",
        title = "Loose Lips",
        description = "Someone's talking to the cops. I know who. Make sure they can't talk no more.",
        type = "kill",
        trustRequired = 30,
        dark = true,
        objectives = {
            {type = "find_target", model = "a_m_y_stwhi_01", location = "vespucci_canals"},
            {type = "kill", target = "snitch", stealth_bonus = true}
        },
        reward = {money = 3000, trust = 20},
        failConditions = {witnessed = true}
    },
    {
        id = "dealer_territory_war",
        title = "Send a Message",
        description = "Ballas trying to move in on my corner. Time to remind them this is our turf.",
        type = "kill",
        trustRequired = 35,
        dark = true,
        coop = {minPlayers = 2, maxPlayers = 4},
        objectives = {
            {type = "goto", coords = vector3(102.5, -1942.7, 20.8)},
            {type = "kill", target = "ballas_dealer", count = 3},
            {type = "survive", duration = 120}  -- Hold position for 2 min
        },
        reward = {money = 5000, trust = 25},
        failConditions = {playerDeath = true}
    }
}

-----------------------------------------------------------
-- CARTEL BOSS QUESTS (Trust: 0-100)
-----------------------------------------------------------
Config.Quests.cartel_boss = {
    -- Tier 1: Proving Ground (0-30)
    {
        id = "cartel_test_run",
        title = "Trial by Fire",
        description = "Everyone starts somewhere. Take this shipment to my people in Blaine County. Don't get pulled over.",
        type = "delivery",
        trustRequired = 0,
        referralRequired = "mid_level_dealer",  -- Need referral to even talk
        objectives = {
            {type = "pickup", location = "cartel_warehouse", item = "sealed_crate"},
            {type = "deliver", location = "sandy_shores", timeout = 1200},
            {type = "avoid_police", stars_max = 0}
        },
        reward = {money = 5000, trust = 15},
        failConditions = {timeout = 1200, policeWanted = true}
    },
    {
        id = "cartel_competitor_hit",
        title = "Business Negotiations",
        description = "A competitor has been... difficult. Remove him from the equation.",
        type = "kill",
        trustRequired = 20,
        dark = true,
        objectives = {
            {type = "find_target", location = "vinewood_hills", marker = true},
            {type = "kill", target = "competitor_boss"},
            {type = "dispose_vehicle", if_witness = true}
        },
        reward = {money = 15000, trust = 20},
        failConditions = {witnessed = true, timeout = 3600}
    },

    -- Tier 2: Trusted Operator (30-60)
    {
        id = "cartel_shipment_intercept",
        title = "Hijack",
        description = "Rival cartel has a shipment coming in tonight. Take their truck, bring it to me.",
        type = "hijack",
        trustRequired = 30,
        coop = {minPlayers = 2, maxPlayers = 4, roles = {"driver", "gunner"}},
        timeWindow = {start = 22, ['end'] = 4},
        objectives = {
            {type = "intercept", vehicle = "mule", route = "highway_1"},
            {type = "neutralize", targets = "guards", count = 4},
            {type = "steal", vehicle = "target_truck"},
            {type = "deliver", location = "cartel_warehouse"}
        },
        reward = {money = 30000, trust = 25},
        failConditions = {vehicleDestroyed = true, playerDeath = true}
    },
    {
        id = "cartel_witness_problem",
        title = "No Witnesses",
        description = "A witness to our last operation is in protective custody. They can't testify.",
        type = "kill",
        trustRequired = 45,
        dark = true,
        objectives = {
            {type = "scout", location = "motel_safehouse"},
            {type = "kill", target = "witness"},
            {type = "kill", target = "bodyguard", count = 2},
            {type = "escape", wanted_level = 0, timeout = 300}
        },
        reward = {money = 25000, trust = 30},
        failConditions = {timeout = 3600}
    },

    -- Tier 3: Inner Circle (60-80)
    {
        id = "cartel_meth_lab_setup",
        title = "New Kitchen",
        description = "We're expanding. I need you to oversee the setup of a new production facility.",
        type = "setup",
        trustRequired = 60,
        objectives = {
            {type = "meet", npc = "chemist", location = "yellow_jack"},
            {type = "escort", target = "chemist", destination = "lab_location"},
            {type = "deliver", items = {"chemical_a", "chemical_b", "equipment"}},
            {type = "wait", duration = 300, description = "Oversee setup"}
        },
        reward = {money = 40000, trust = 30, unlocks = "meth_lab_access"},
        failConditions = {chemistDeath = true}
    },
    {
        id = "cartel_fib_mole",
        title = "The Mole",
        description = "We have a friend in the FIB. He needs extraction. Make sure he doesn't fall into the wrong hands.",
        type = "escort",
        trustRequired = 70,
        objectives = {
            {type = "goto", location = "fib_parking"},
            {type = "signal", method = "flash_lights", count = 3},
            {type = "pickup", target = "agent_smith"},
            {type = "evade", if_pursued = true},
            {type = "deliver", target = "agent_smith", destination = "safe_house"}
        },
        reward = {money = 50000, trust = 35, referral = "corrupt_agent"},
        failConditions = {targetDeath = true, captured = true}
    },

    -- Tier 4: Blood In (80-100)
    {
        id = "cartel_family_job",
        title = "Family Business",
        description = "Someone betrayed the family. You know what needs to happen. Their whole crew.",
        type = "massacre",
        trustRequired = 80,
        dark = true,
        coop = {minPlayers = 3, maxPlayers = 6, roles = {"leader", "muscle", "driver"}},
        objectives = {
            {type = "assault", location = "traitor_compound"},
            {type = "kill", target = "traitor_guards", count = 8},
            {type = "find", target = "traitor_boss"},
            {type = "execute", target = "traitor_boss", method = "melee"},
            {type = "torch", location = "compound", item = "gasoline"}
        },
        reward = {money = 100000, trust = 50, title = "Sicario"},
        failConditions = {playerDeath = true}
    },
    {
        id = "cartel_cop_frame",
        title = "The Frame",
        description = "This detective has been a problem for too long. We're going to destroy his career.",
        type = "frame",
        trustRequired = 90,
        dark = true,
        objectives = {
            {type = "break_in", location = "detective_home"},
            {type = "plant", item = "cocaine_brick", location = "bedroom"},
            {type = "plant", item = "dirty_money", location = "garage"},
            {type = "plant", item = "burner_phone", location = "car"},
            {type = "escape", witnessed = false},
            {type = "call", contact = "anonymous_tip", target = "police_ia"}
        },
        reward = {money = 75000, trust = 40, intel = "dirty_cop_removed"},
        failConditions = {witnessed = true, caught = true}
    }
}

-----------------------------------------------------------
-- GANG LEADER QUESTS (Vagos Example)
-----------------------------------------------------------
Config.Quests.vagos_leader = {
    {
        id = "vagos_initiation",
        title = "Colors",
        description = "You wanna roll with Vagos? Prove you got heart. Handle this fool talking shit about us.",
        type = "beat_down",
        trustRequired = 0,
        objectives = {
            {type = "find", target = "trash_talker", location = "davis"},
            {type = "beat", target = "trash_talker", weapon = "fists"},
            {type = "take", item = "wallet"}
        },
        reward = {trust = 15, item = {name = "vagos_bandana", amount = 1}},
        factionTrust = {vagos = 10, ballas = -5}
    },
    {
        id = "vagos_drug_run",
        title = "Yellow Brick Road",
        description = "Product needs moving through Families territory. Don't get caught slipping.",
        type = "delivery",
        trustRequired = 20,
        objectives = {
            {type = "pickup", location = "vagos_hq", item = "drug_package"},
            {type = "deliver", location = "mirror_park", through_territory = "families"}
        },
        reward = {money = 3000, trust = 15},
        factionTrust = {vagos = 10, families = -15}
    },
    {
        id = "vagos_ballas_hit",
        title = "Purple Rain",
        description = "Ballas killed one of ours. Time for payback. Three of theirs for one of ours.",
        type = "kill",
        trustRequired = 40,
        dark = true,
        coop = {minPlayers = 2, maxPlayers = 4},
        objectives = {
            {type = "drive_by", location = "grove_street"},
            {type = "kill", target = "ballas_member", count = 3}
        },
        reward = {money = 5000, trust = 25},
        factionTrust = {vagos = 20, ballas = -50}
    },
    {
        id = "vagos_turf_war",
        title = "The Block",
        description = "We're taking Grove Street. Tonight. Full assault.",
        type = "territory_war",
        trustRequired = 70,
        dark = true,
        coop = {minPlayers = 4, maxPlayers = 8},
        timeWindow = {start = 22, ['end'] = 4},
        objectives = {
            {type = "assault", location = "grove_street"},
            {type = "kill", target = "ballas_defenders", count = 10},
            {type = "hold", location = "grove_street", duration = 600},
            {type = "plant", item = "vagos_flag", location = "center"}
        },
        reward = {money = 25000, trust = 40, territory = "grove_street"},
        factionTrust = {vagos = 50, ballas = -100, families = -30}
    }
}

-----------------------------------------------------------
-- PAWN SHOP OWNER QUESTS
-----------------------------------------------------------
Config.Quests.pawn_shop = {
    {
        id = "pawn_collect_item",
        title = "Repo Job",
        description = "Guy took a loan, pawned his watch, now he wants it back without paying. Get my money.",
        type = "collect",
        trustRequired = 0,
        objectives = {
            {type = "find", target = "deadbeat", location = "del_perro"},
            {type = "collect", amount = 500, method = "intimidate_or_pay"}
        },
        reward = {money = 100, trust = 5}
    },
    {
        id = "pawn_stolen_goods",
        title = "Hot Merchandise",
        description = "I got a line on some... liberated electronics. Pick 'em up for me.",
        type = "retrieve",
        trustRequired = 15,
        objectives = {
            {type = "goto", location = "warehouse_east"},
            {type = "retrieve", item = "electronics_box"},
            {type = "return", location = "pawn_shop"}
        },
        reward = {money = 800, trust = 10},
        failConditions = {policeNearby = true}
    },
    {
        id = "pawn_gun_trace",
        title = "Clean Pieces",
        description = "Got some heat that needs serial numbers... adjusted. Know a guy.",
        type = "delivery",
        trustRequired = 30,
        objectives = {
            {type = "pickup", item = "unmarked_guns", location = "pawn_shop"},
            {type = "deliver", location = "mirror_park_garage"},
            {type = "wait", duration = 120},
            {type = "return", item = "clean_guns", location = "pawn_shop"}
        },
        reward = {money = 2000, trust = 15, referral = "gun_runner"}
    },
    {
        id = "pawn_insurance_job",
        title = "Insurance Claim",
        description = "I need a robbery. Staged. My inventory's insured. Make it look good.",
        type = "robbery",
        trustRequired = 50,
        dark = true,
        objectives = {
            {type = "wait_until", time = 2},  -- 2 AM
            {type = "break_in", location = "pawn_shop_back"},
            {type = "steal", items = "marked_items"},
            {type = "rough_up", target = "pawn_owner", damage = 10},
            {type = "deliver", items = "marked_items", location = "storage_unit"}
        },
        reward = {money = 10000, trust = 25},
        failConditions = {witnessed_real = true}
    }
}

-----------------------------------------------------------
-- MECHANIC (CHOP SHOP) QUESTS
-----------------------------------------------------------
Config.Quests.chop_shop = {
    {
        id = "chop_first_boost",
        title = "Easy Ride",
        description = "Need a basic sedan. Nothing fancy. Just... don't get caught.",
        type = "vehicle_theft",
        trustRequired = 0,
        objectives = {
            {type = "steal", vehicle_class = "sedan", any = true},
            {type = "deliver", location = "chop_shop"}
        },
        reward = {money = 1000, trust = 5}
    },
    {
        id = "chop_sports_car",
        title = "Speed Demon",
        description = "Client wants something fast. I'm talking sports car. Can you handle it?",
        type = "vehicle_theft",
        trustRequired = 15,
        objectives = {
            {type = "steal", vehicle_class = "sports", any = true},
            {type = "deliver", location = "chop_shop", condition = 80}  -- 80% condition min
        },
        reward = {money = 3000, trust = 10}
    },
    {
        id = "chop_specific_order",
        title = "Special Order",
        description = "Need a specific ride. White Zentorno. Client's paying top dollar.",
        type = "vehicle_theft",
        trustRequired = 30,
        objectives = {
            {type = "find", vehicle = "zentorno", color = "white"},
            {type = "steal", vehicle = "target"},
            {type = "deliver", location = "chop_shop", condition = 90}
        },
        reward = {money = 8000, trust = 15}
    },
    {
        id = "chop_exotic_heist",
        title = "Car Show",
        description = "Exotic car show at the casino. Security's tight but so are the margins.",
        type = "heist",
        trustRequired = 50,
        coop = {minPlayers = 2, maxPlayers = 4, roles = {"driver", "thief", "blocker"}},
        objectives = {
            {type = "scout", location = "casino_parking"},
            {type = "disable", target = "security_cameras"},
            {type = "steal", vehicles = {"entity", "t20", "adder"}, count = 3},
            {type = "deliver", location = "chop_shop"}
        },
        reward = {money = 25000, trust = 25}
    },
    {
        id = "chop_truck_heist",
        title = "Transport",
        description = "Truck full of luxury cars. Highway 1. Tonight. Interested?",
        type = "hijack",
        trustRequired = 70,
        coop = {minPlayers = 3, maxPlayers = 6},
        timeWindow = {start = 1, ['end'] = 5},
        objectives = {
            {type = "intercept", vehicle = "car_carrier", route = "highway_1"},
            {type = "neutralize", targets = "escorts", count = 2},
            {type = "steal", vehicle = "car_carrier"},
            {type = "deliver", location = "hidden_warehouse"}
        },
        reward = {money = 50000, trust = 35}
    }
}

-----------------------------------------------------------
-- ARMS DEALER QUESTS
-----------------------------------------------------------
Config.Quests.arms_dealer = {
    {
        id = "arms_small_delivery",
        title = "Hardware Run",
        description = "Small package. Handguns. Nothing major. Don't draw attention.",
        type = "delivery",
        trustRequired = 0,
        referralRequired = "pawn_shop",
        objectives = {
            {type = "pickup", location = "arms_dealer", item = "pistol_case"},
            {type = "deliver", location = "client_alley", timeout = 600}
        },
        reward = {money = 1500, trust = 10}
    },
    {
        id = "arms_rifle_run",
        title = "Long Guns",
        description = "Client needs rifles. Multiple drops. Keep them separated.",
        type = "delivery",
        trustRequired = 25,
        objectives = {
            {type = "pickup", item = "rifle_cases", count = 3},
            {type = "deliver", location = "drop_1", item_count = 1},
            {type = "deliver", location = "drop_2", item_count = 1},
            {type = "deliver", location = "drop_3", item_count = 1}
        },
        reward = {money = 5000, trust = 15}
    },
    {
        id = "arms_mil_surplus",
        title = "Surplus",
        description = "Military shipment went 'missing'. It's at the docks. Get it before anyone else does.",
        type = "retrieve",
        trustRequired = 50,
        coop = {minPlayers = 2, maxPlayers = 4},
        objectives = {
            {type = "infiltrate", location = "dock_warehouse"},
            {type = "neutralize", targets = "guards", count = 4, stealth_bonus = true},
            {type = "retrieve", item = "military_crate"},
            {type = "extract", vehicle = "van", location = "arms_warehouse"}
        },
        reward = {money = 20000, trust = 25}
    },
    {
        id = "arms_competitor_raid",
        title = "Hostile Takeover",
        description = "Another dealer's been undercutting me. Time to shut him down. Permanently.",
        type = "raid",
        trustRequired = 75,
        dark = true,
        coop = {minPlayers = 3, maxPlayers = 6},
        objectives = {
            {type = "assault", location = "competitor_warehouse"},
            {type = "kill", target = "competitor_guards", count = 6},
            {type = "kill", target = "competitor_dealer"},
            {type = "loot", items = "weapons_cache"},
            {type = "torch", location = "warehouse"}
        },
        reward = {money = 40000, trust = 35}
    }
}

-----------------------------------------------------------
-- FIXER QUESTS (High-Level Coordinator)
-----------------------------------------------------------
Config.Quests.fixer = {
    {
        id = "fixer_first_job",
        title = "Audition",
        description = "I don't know you. Let's fix that. Small job, clean execution.",
        type = "assassination",
        trustRequired = 0,
        referralRequired = "cartel_boss",
        objectives = {
            {type = "receive_target", method = "phone"},
            {type = "find", target = "mark", using = "photo"},
            {type = "kill", target = "mark", method = "any", clean = true},
            {type = "escape", wanted_level = 0}
        },
        reward = {money = 15000, trust = 15}
    },
    {
        id = "fixer_extraction",
        title = "The Asset",
        description = "VIP needs out of the country. Quietly. Multiple agencies looking for them.",
        type = "escort",
        trustRequired = 30,
        objectives = {
            {type = "meet", location = "safehouse_3"},
            {type = "escort", target = "vip", to = "airport_hangar"},
            {type = "evade", if_pursued = true},
            {type = "deliver", target = "vip", to = "private_jet"}
        },
        reward = {money = 25000, trust = 20}
    },
    {
        id = "fixer_evidence_destruction",
        title = "Paper Trail",
        description = "Evidence locker. LSPD. Specific case files need to disappear.",
        type = "heist",
        trustRequired = 60,
        coop = {minPlayers = 2, maxPlayers = 4},
        objectives = {
            {type = "acquire", item = "police_uniform", method = "any"},
            {type = "infiltrate", location = "mission_row_pd"},
            {type = "access", location = "evidence_room", method = "keycard"},
            {type = "find", item = "case_files_472"},
            {type = "destroy", item = "case_files_472", method = "burn"},
            {type = "exfiltrate", witnessed = false}
        },
        reward = {money = 50000, trust = 30}
    },
    {
        id = "fixer_judge_problem",
        title = "Judicial Override",
        description = "A judge is about to make an unfavorable ruling. Change his mind. Permanently.",
        type = "assassination",
        trustRequired = 85,
        dark = true,
        objectives = {
            {type = "scout", location = "judge_home"},
            {type = "wait_until", target = "alone"},
            {type = "infiltrate", location = "judge_home", method = "stealth"},
            {type = "kill", target = "judge", method = "staged_suicide"},
            {type = "plant", item = "suicide_note"},
            {type = "escape", witnessed = false}
        },
        reward = {money = 100000, trust = 40}
    },
    {
        id = "fixer_prison_break",
        title = "Inside Job",
        description = "Client's associate is in Bolingbroke. He needs to not be. Full extraction.",
        type = "heist",
        trustRequired = 95,
        dark = true,
        coop = {minPlayers = 4, maxPlayers = 8, roles = {"leader", "pilot", "demolition", "cover", "driver"}},
        objectives = {
            {type = "acquire", items = {"guard_uniforms", "explosives", "helicopter"}},
            {type = "infiltrate", location = "bolingbroke", team_role = "inside"},
            {type = "create_diversion", location = "east_block"},
            {type = "extract", target = "prisoner_x", method = "heli"},
            {type = "evade", duration = 300},
            {type = "deliver", target = "prisoner_x", location = "extraction_point"}
        },
        reward = {money = 250000, trust = 50}
    }
}

-----------------------------------------------------------
-- BODY DISPOSAL SPECIALIST
-----------------------------------------------------------
Config.Quests.cleaner = {
    {
        id = "cleaner_first_job",
        title = "The Mess",
        description = "Someone left a problem that needs cleaning. Car, body, all of it.",
        type = "dispose",
        trustRequired = 0,
        referralRequired = "fixer",
        dark = true,
        objectives = {
            {type = "goto", location = "crime_scene"},
            {type = "load", target = "body", into = "trunk"},
            {type = "clean", location = "crime_scene", item = "bleach"},
            {type = "deliver", target = "body", location = "pig_farm"},
            {type = "deliver", target = "vehicle", location = "crusher"}
        },
        reward = {money = 10000, trust = 15}
    },
    {
        id = "cleaner_mass_cleanup",
        title = "Party's Over",
        description = "Gang shootout. Multiple packages. Time sensitive before the badges show.",
        type = "dispose",
        trustRequired = 40,
        dark = true,
        coop = {minPlayers = 2, maxPlayers = 4},
        timeWindow = {start = 0, ['end'] = 6},
        objectives = {
            {type = "goto", location = "shootout_scene"},
            {type = "load", targets = "bodies", count = 5},
            {type = "clean", location = "scene", items = {"bleach", "acid"}},
            {type = "dispose", targets = "bodies", location = "acid_pit"},
            {type = "dispose", targets = "weapons", location = "ocean"}
        },
        reward = {money = 35000, trust = 30}
    },
    {
        id = "cleaner_high_profile",
        title = "Celebrity Status",
        description = "Famous client. Very famous. The kind where this never happened. Ever.",
        type = "dispose",
        trustRequired = 70,
        dark = true,
        objectives = {
            {type = "goto", location = "vinewood_mansion"},
            {type = "assess", scene = true},
            {type = "clean", location = "bedroom", thoroughness = "forensic"},
            {type = "dispose", target = "body", location = "crematorium"},
            {type = "dispose", target = "evidence", method = "incinerate"},
            {type = "stage", scene = "burglary_gone_wrong"}
        },
        reward = {money = 75000, trust = 40, item = {name = "blackmail_material", amount = 1}}
    }
}

-----------------------------------------------------------
-- LEGITIMATE BUSINESS QUESTS (Front Operations)
-----------------------------------------------------------
Config.Quests.restaurant_owner = {
    {
        id = "restaurant_delivery",
        title = "Special Delivery",
        description = "Got a catering order. Delivery van's out back. Nothing special in the boxes. Just food.",
        type = "delivery",
        trustRequired = 20,  -- Need some trust first
        objectives = {
            {type = "pickup", vehicle = "delivery_van"},
            {type = "deliver", location = "warehouse_front", timeout = 900}
        },
        reward = {money = 2000, trust = 10}
    },
    {
        id = "restaurant_protection_money",
        title = "Insurance Collection",
        description = "Some local businesses owe their monthly... insurance payments. Collect for me.",
        type = "collect",
        trustRequired = 40,
        objectives = {
            {type = "collect", from = "store_1", amount = 500},
            {type = "collect", from = "store_2", amount = 500},
            {type = "collect", from = "store_3", amount = 500},
            {type = "return", location = "restaurant"}
        },
        reward = {money = 300, trust = 15}
    }
}

-----------------------------------------------------------
-- HELPER FUNCTION TO GET QUEST BY ID
-----------------------------------------------------------
function GetQuestById(questId)
    for npcType, quests in pairs(Config.Quests) do
        for _, quest in ipairs(quests) do
            if quest.id == questId then
                return quest, npcType
            end
        end
    end
    return nil
end

-----------------------------------------------------------
-- GET AVAILABLE QUESTS FOR PLAYER WITH NPC
-----------------------------------------------------------
function GetAvailableQuests(npcType, playerTrust, playerReferrals, playerCompletedQuests)
    local available = {}
    local quests = Config.Quests[npcType] or {}

    for _, quest in ipairs(quests) do
        local canOffer = true

        -- Check trust requirement
        if quest.trustRequired and playerTrust < quest.trustRequired then
            canOffer = false
        end

        -- Check referral requirement
        if quest.referralRequired and not playerReferrals[quest.referralRequired] then
            canOffer = false
        end

        -- Check if one-time and already completed
        if quest.oneTime and playerCompletedQuests[quest.id] then
            canOffer = false
        end

        if canOffer then
            table.insert(available, quest)
        end
    end

    return available
end

print("^2[AI NPCs]^7 Quest definitions loaded (" .. #Config.Quests.street_dealer + #Config.Quests.cartel_boss .. "+ quests)")
