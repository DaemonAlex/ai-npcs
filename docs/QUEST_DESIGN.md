# AI NPCs Quest Design Document

## Quest Types Reference
- `item_delivery` - Bring specific items to NPC
- `task` - Complete an action (go somewhere, do something)
- `payment` - Pay money/debt
- `kill` - Eliminate a target
- `frame` - Plant evidence on someone
- `escort` - Protect/transport someone
- `other` - Custom quest logic

---

## CRIMINAL UNDERGROUND

### Sketchy Mike (Street-Level Entry Point)
**Location:** Yellow Jack Inn | **Trust Category:** criminal

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Prove You're Cool" | item_delivery | Bring 5x `joint` or `weed_brick` | +10 trust, unlocks basic info |
| Stranger (5) | "Ears on the Street" | task | Visit 3 locations, report back | +5 trust, $500 |
| Acquaintance (15) | "Delivery Boy" | item_delivery | Deliver package to marked location | +10 trust, $1,000 |
| Acquaintance (25) | "Heat Check" | task | Lose cops while carrying product | +15 trust, referral to Charlie |
| Trusted (40) | "Problem Solver" | kill | Take out a snitch (ped target) | +20 trust, referral to Viktor |

**Integration:**
- Check `ox_inventory` for weed items
- Use `qb-phone` GPS for delivery locations
- Cop check via `qb-policejob` wanted level

---

### Charlie the Fence (Stolen Goods)
**Location:** Chamberlain Hills | **Trust Category:** criminal

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Show Me Something" | item_delivery | Bring stolen goods worth $5,000+ | +10 trust |
| Acquaintance (15) | "Shopping List" | item_delivery | Bring 3x `rolex`, 2x `goldchain` | +15 trust, $3,000 |
| Acquaintance (25) | "Hot Wheels" | task | Steal specific vehicle, deliver to lockup | +15 trust, $5,000 |
| Trusted (40) | "Art Appreciation" | task | Rob Vangelico or gallery, bring paintings | +20 trust, $15,000 |
| Trusted (50) | "The Big Fish" | payment | Pay $25,000 for introduction | Referral to The Architect |

**Integration:**
- `qb-inventory` item value checks
- Vehicle theft via `qb-vehicleshop` or custom
- Gallery heist integration

---

### The Architect (Heist Mastermind)
**Location:** Mirror Park (by appointment) | **Trust Category:** criminal

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Requires Referral | "Vetting Process" | item_delivery | Bring $50,000 cash + clean record check | Entry |
| Inner Circle (70) | "The Setup - Intel" | task | Photograph 3 bank locations | +10 trust, blueprints |
| Inner Circle (75) | "The Setup - Crew" | task | Recruit 3 players, report names | +10 trust, crew roles |
| Inner Circle (80) | "The Setup - Hardware" | item_delivery | Bring thermite, laptop, drills | +10 trust, timing info |
| Inner Circle (90) | "The Setup - Escape" | task | Scout getaway routes, place vehicles | +10 trust, full plan |
| Inner Circle (100) | "Green Light" | other | Execute heist within 48 hours | Access to casino prep |

**Integration:**
- `qb-bankrobbery` or equivalent
- Screenshot/photo mechanic
- Vehicle placement system

---

### Viktor (Arms Dealer)
**Location:** Docks warehouse | **Trust Category:** criminal

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Grease the Wheels" | payment | Pay $5,000 "introduction fee" | +10 trust |
| Stranger (10) | "Scrap Run" | item_delivery | Bring 10x `metalscrap`, 5x `steel` | +10 trust, discount |
| Acquaintance (20) | "Battery Operated" | item_delivery | Bring 5x `carbattery` | +10 trust, $2,000 |
| Acquaintance (30) | "Watch the Shipment" | escort | Protect delivery truck to location | +15 trust, free weapon |
| Trusted (45) | "Collect a Debt" | task | Beat up/threaten debtor, collect $10k | +15 trust, $3,000 |
| Trusted (55) | "Wet Work" | kill | Eliminate competing dealer | +20 trust, heavy weapons access |

**Integration:**
- `qb-inventory` crafting materials
- Escort mission via `qb-target` + ped spawning
- Combat integration

---

## DRUG EMPIRE

### Smokey (Weed Connect)
**Location:** Grove Street | **Trust Category:** criminal

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Roll One Up" | item_delivery | Bring 20x `weed_white-widow` | +10 trust |
| Acquaintance (15) | "Garden Duty" | task | Tend grow op for 10 minutes | +10 trust, seeds |
| Acquaintance (25) | "Distribution" | task | Sell 50 bags, return with cash | +15 trust, $2,000 |
| Trusted (40) | "Supplier Run" | item_delivery | Pick up 100x seeds from contact | +15 trust, bulk pricing |
| Trusted (50) | "Hostile Takeover" | kill | Clear rival grow op, take product | +20 trust, territory |

**Integration:**
- `qb-weed` or `ps-weed` growing system
- Drug selling mechanics
- Territory system

---

### Rico (Cocaine Kingpin)
**Location:** Vinewood Hills mansion | **Trust Category:** criminal

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Requires Referral | "Taste Test" | item_delivery | Bring 10x `coke_brick` | Entry + $5,000 |
| Acquaintance (25) | "Kitchen Duty" | task | Process 20 bricks at safe house | +10 trust, $3,000 |
| Trusted (40) | "Club Circuit" | task | Sell at 5 nightclubs in one night | +15 trust, $10,000 |
| Trusted (55) | "Cartel Favor" | escort | Escort VIP from airport | +15 trust |
| Inner Circle (70) | "Snitch Hunt" | kill | Find and eliminate DEA informant | +20 trust, supplier access |
| Inner Circle (85) | "The Shipment" | task | Coordinate dock pickup, avoid cops | +20 trust, distribution rights |

**Integration:**
- `qb-drugs` cocaine processing
- Nightclub selling zones
- VIP escort mechanics

---

### Walter (Meth Manufacturer)
**Location:** Sandy Shores trailer | **Trust Category:** criminal

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Chemistry 101" | item_delivery | Bring pseudoephedrine, acetone, lithium | +15 trust |
| Acquaintance (20) | "Cook Session" | task | Complete meth cook (minigame) | +10 trust, product |
| Acquaintance (35) | "Supply Chain" | task | Steal precursors from pharmacy | +15 trust, $5,000 |
| Trusted (50) | "Lab Expansion" | payment | Invest $50,000 in new equipment | +15 trust, faster cooks |
| Trusted (65) | "Competition" | kill | Destroy rival lab, kill cook | +20 trust, monopoly |

**Integration:**
- `qb-methlab` or equivalent
- Robbery mechanics
- Explosion/destruction

---

## GANG TERRITORIES

### El Guapo (Vagos Lieutenant)
**Location:** Jamestown Street | **Trust Category:** gang

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Yellow Pride" | task | Wear Vagos colors for 1 hour | +5 trust |
| Stranger (10) | "Tag Up" | task | Spray 5 Vagos tags in rival territory | +10 trust |
| Acquaintance (25) | "Corner Work" | task | Sell product on Vagos corner | +10 trust, $1,500 |
| Acquaintance (35) | "Ballas Problem" | kill | Kill 3 Ballas members | +15 trust |
| Trusted (50) | "Weapon Stash" | escort | Escort weapons to safe house | +15 trust |
| Trusted (60) | "Blood In" | kill | Execute captured rival | +20 trust, full member |
| Inner Circle (80) | "War Council" | other | Plan territory takeover | +20 trust, lieutenant status |

**Integration:**
- Clothing check for gang colors
- Spray paint mechanic
- Gang territory system
- PvP or AI gang combat

---

### Purple K (Ballas OG)
**Location:** Davis | **Trust Category:** gang

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Purple Reign" | task | Wear Ballas colors, walk through Grove | +10 trust |
| Stranger (15) | "Drive-by" | kill | Kill 2 Families from vehicle | +15 trust |
| Acquaintance (30) | "Corner Takeover" | task | Clear Families corner, hold 10 min | +15 trust |
| Trusted (45) | "Crack Distribution" | task | Move 50 units in Ballas territory | +15 trust, $3,000 |
| Trusted (60) | "Badge Problem" | frame | Plant drugs in cop's car | +20 trust |
| Inner Circle (75) | "Grove Street Massacre" | kill | Kill Big Smoke Jr. | +25 trust, war starts |

**Integration:**
- Gang turf control
- Frame job mechanics (evidence planting)
- Boss elimination

---

### Big Smoke Jr. (Families Leader)
**Location:** Grove Street | **Trust Category:** gang

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Green Machine" | task | Wear Families green, patrol Grove | +10 trust |
| Stranger (15) | "Community Service" | task | Do 3 good deeds in Grove (help peds) | +10 trust |
| Acquaintance (25) | "Ballas Recon" | task | Photograph Ballas operations | +10 trust |
| Acquaintance (40) | "Dealer Cleanup" | kill | Kill 3 non-Families drug dealers in Grove | +15 trust |
| Trusted (55) | "Supply Line" | escort | Escort supply truck into Grove | +15 trust |
| Trusted (70) | "Political Cover" | task | Meet with councilman, deliver "donation" | +15 trust |
| Inner Circle (85) | "The Offensive" | kill | Lead attack on Ballas territory | +20 trust, Grove expansion |

**Integration:**
- Territory defense
- Diplomacy/bribery
- Large-scale gang warfare

---

### Chains (Lost MC Sergeant)
**Location:** East Vinewood Clubhouse | **Trust Category:** gang

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Ride or Die" | task | Complete motorcycle ride (follow Chains) | +10 trust |
| Stranger (15) | "Prospect Work" | task | Clean clubhouse, tend bar for event | +10 trust |
| Acquaintance (25) | "Parts Run" | item_delivery | Bring 10x motorcycle parts | +10 trust |
| Acquaintance (40) | "Gun Running" | escort | Escort gun shipment on bikes | +15 trust |
| Trusted (55) | "Meth Money" | item_delivery | Deliver meth to 3 buyers | +15 trust, $5,000 |
| Trusted (70) | "Rat in the Club" | kill | Find and execute club informant | +20 trust |
| Inner Circle (85) | "Colors" | other | Full patch ceremony (RP event) | Full member, cuts |

**Integration:**
- Motorcycle mechanics
- Club events system
- MC hierarchy

---

## LEGITIMATE NPCs (Gray Area)

### Margaret Chen (Career Counselor)
**Location:** City Hall | **Trust Category:** professional

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Community Hours" | task | Complete 30 min community service job | +10 trust |
| Acquaintance (20) | "Reference Check" | task | Work 3 different legal jobs | +10 trust, job referrals |
| Trusted (40) | "Off the Books" | task | "Help" with paperwork (deliver package) | +15 trust, hints about connections |
| Trusted (55) | "Old Friends" | other | She asks about crime, you share intel | Referral to Attorney Goldstein |

**What she knows (unlocked via trust):**
- Which businesses are fronts
- Who's "connected" in city government
- Attorney Goldstein's "special services"

---

### Attorney Goldstein (Criminal Defense)
**Location:** Downtown Office | **Trust Category:** professional

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Retainer" | payment | Pay $10,000 retainer | +10 trust, legal services |
| Acquaintance (25) | "Witness Problem" | task | "Convince" witness to not testify | +15 trust |
| Trusted (45) | "Evidence Handling" | item_delivery | Retrieve "misplaced" evidence from lockup | +15 trust |
| Trusted (60) | "Judicial Discretion" | payment | Pay $50,000 to "expedite" case | +20 trust, charges reduced |
| Inner Circle (75) | "The Network" | other | Access to corrupt officials | Referrals to judges, cops |

**Integration:**
- Court case system
- Evidence mechanics
- Bribery/corruption

---

### Dr. Hartman (Pillbox Hospital)
**Location:** Pillbox Hospital | **Trust Category:** professional

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Blood Drive" | task | Donate blood (RP + item) | +5 trust |
| Acquaintance (15) | "Supplies Run" | item_delivery | Bring medical supplies from pharmacy | +10 trust |
| Trusted (35) | "No Questions" | payment | Pay $5,000 for off-books treatment | +15 trust, no police report |
| Trusted (50) | "Prescription Pad" | payment | Pay $10,000 for prescription access | +15 trust, pill supply |
| Inner Circle (70) | "The Quiet Room" | other | Access to morgue, death certificates | Clean up services |

**Integration:**
- Hospital system
- Medical items
- "Cleanup" for bodies

---

### Old Pete (Mechanic/Racer)
**Location:** Burton Auto Shop | **Trust Category:** service

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Grease Monkey" | item_delivery | Bring 5x `metalscrap`, 3x `rubber` | +10 trust |
| Acquaintance (20) | "Test Drive" | task | Win street race with his car | +15 trust, tuning discount |
| Trusted (40) | "VIN Swap" | item_delivery | Bring stolen car for VIN swap | +15 trust, clean title |
| Trusted (55) | "Import Business" | task | Pick up imported car from docks | +15 trust, import contact |
| Inner Circle (70) | "Racing Underground" | other | Access to high-stakes races | Referral to race fixers |

**Integration:**
- `qb-mechanicjob` or equivalent
- Racing system
- VIN scratching/cleaning

---

### Vanessa Sterling (Real Estate)
**Location:** Downtown Office | **Trust Category:** professional

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Showing" | task | Attend 3 property showings | +5 trust |
| Acquaintance (20) | "Investment" | payment | Buy property ($50,000+) | +15 trust, insider info |
| Trusted (40) | "Shell Game" | payment | Pay $25,000 for anonymous LLC setup | +15 trust, money laundering |
| Trusted (55) | "Foreclosure Special" | task | "Convince" owner to sell (intimidate) | +15 trust, below-market property |
| Inner Circle (70) | "Real Money" | other | Access to property-based money laundering | Clean cash service |

**Integration:**
- Property system
- Money laundering mechanics
- Business ownership

---

## SERVICE NPCs

### Jackie (Bahama Mamas Bartender)
**Location:** Bahama Mamas (night) | **Trust Category:** service

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Regular" | task | Buy 10 drinks over time | +5 trust |
| Acquaintance (15) | "Party Supplies" | item_delivery | Bring party drugs for VIP room | +10 trust |
| Trusted (35) | "Backroom Access" | payment | Pay $5,000 for VIP room key | +15 trust, meeting spot |
| Trusted (50) | "Eyes and Ears" | other | Jackie reports who's meeting who | Intel on deals going down |

---

### Crazy Earl (Street Sage)
**Location:** Legion Square | **Trust Category:** service

| Trust Level | Quest | Type | Requirements | Reward |
|-------------|-------|------|--------------|--------|
| Stranger (0) | "Spare Change" | payment | Give $100 | +5 trust |
| Stranger (10) | "Liquid Courage" | item_delivery | Bring bottle of whiskey | +10 trust |
| Acquaintance (25) | "The Old Days" | task | Listen to his stories (RP) | +10 trust, historical intel |
| Trusted (40) | "Street Network" | other | Earl's homeless network watches the city | Intel on movements, stashes |

**Cheapest intel source but least reliable**

---

## IMPLEMENTATION NOTES

### Quest Trigger System
```lua
-- Example: Offering a quest when trust threshold met
RegisterNetEvent('ai-npcs:server:checkQuests', function(npcId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local trust = exports['ai-npcs']:GetPlayerTrustWithNPC(src, npcId)

    local availableQuests = GetAvailableQuests(npcId, trust)
    -- NPC AI mentions available quests in conversation
end)
```

### Item Verification
```lua
-- Check player has required items
function VerifyQuestItems(playerId, requiredItems)
    local Player = QBCore.Functions.GetPlayer(playerId)
    for item, count in pairs(requiredItems) do
        if not Player.Functions.GetItemByName(item) or
           Player.Functions.GetItemByName(item).amount < count then
            return false
        end
    end
    return true
end
```

### Kill Quest Targets
- Spawn temporary peds marked as targets
- Track kills via `onPlayerKill` or similar
- Clean up after quest complete/failed

### Territory Integration
- Hook into gang territory scripts
- Track spray paint locations
- Monitor area control timers

---

## QUEST CHAINS (Full Progression Examples)

### "The Bank Job" Chain
1. Sketchy Mike → Charlie the Fence → The Architect
2. Total trust needed: 150+ across 3 NPCs
3. Estimated completion: 10-15 hours of gameplay
4. Final reward: Access to Pacific Standard heist

### "Drug Empire" Chain
1. Smokey (weed) → Rico (coke) → Walter (meth)
2. Build supplier relationships
3. Total investment: $100,000+
4. Final reward: Multi-drug distribution network

### "Gang War" Chain
1. Choose a gang (Vagos/Ballas/Families/Lost)
2. Complete loyalty quests
3. Rise to lieutenant
4. Trigger territory war event
5. Outcome affects map control

---

## DARK QUESTS (Full GTA Style)

### Kill Quests
- **Snitch elimination** - Find and kill informant
- **Rival gang hits** - Drive-bys, executions
- **Witness intimidation** - Beat up or kill
- **Boss takedowns** - Major NPC eliminations

### Frame Jobs
- **Plant drugs on cop** - Get corrupt cop fired
- **Evidence manipulation** - Frame rival for crime
- **Insurance fraud** - Staged accidents

### Body Disposal
- **Desert burial** - Drive body to Sandy Shores
- **Acid bath** - Use Walter's lab
- **Ocean dump** - Boat required
- **Doctor's help** - Morgue disappearance

---

## NEXT STEPS

1. Create `quests.lua` config file with all quest definitions
2. Add quest tracking UI to NUI
3. Implement quest state machine (offered → accepted → in_progress → completed)
4. Create quest reward system
5. Add quest-specific NPC dialogue triggers
6. Integrate with existing job/crime scripts
