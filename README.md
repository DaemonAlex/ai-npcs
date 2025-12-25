# AI NPCs - Advanced Conversational AI for FiveM RP

A comprehensive AI-powered NPC conversation system for QBCore FiveM servers. NPCs respond dynamically based on player context, build trust relationships, provide intel for crime RP, and move around the map realistically.

## Features

### Core Systems

- **Dynamic AI Conversations**: NPCs respond intelligently using Claude AI or OpenAI GPT
- **Text-to-Speech Audio**: Optional ElevenLabs voice synthesis for immersive conversations
- **Player Context Awareness**: NPCs react differently based on your job, items, cash, and gang affiliation
- **Trust/Reputation System**: Build relationships with NPCs to unlock better intel
- **Intel/Clue System**: Pay for information about crimes, heists, drug operations, and more
- **NPC Movement**: NPCs wander, patrol, or follow schedules - they're not just standing still!
- **Modern UI**: Clean conversation interface with payment options
- **ox_target Integration**: Seamless interaction system

### Player Context Awareness

NPCs can detect and react to:
- **Your Job**: Cops get stonewalled or lied to, criminals get business talk
- **Items You Carry**: Drugs, weapons, crime tools, valuables all affect NPC behavior
- **Cash on Hand**: Rich players get more attention
- **Gang Affiliation**: Gang NPCs recognize their own
- **Criminal Record**: Some NPCs know your history

### Trust System

Build relationships over time:
- **Stranger** (0-10): Vague hints, rumors only
- **Acquaintance** (11-30): Basic info for cash
- **Trusted** (31-60): Detailed intel, warnings
- **Inner Circle** (61-100): The real good stuff, exclusive access

Trust is earned through:
- Repeated visits (+2 per visit)
- Successful conversations (+1)
- Payments (+5 per payment)
- Bringing requested items (+10)
- Referrals from other NPCs (+15)

### Intel Tiers & Pricing

| Tier | Trust Required | Price Range | Cooldown |
|------|---------------|-------------|----------|
| Rumors | 0 | Free | 5 min |
| Basic | 10-20 | $500-$2,000 | 10 min |
| Detailed | 30-50 | $2,000-$10,000 | 30 min |
| Sensitive | 60-70 | $10,000-$50,000 | 1 hour |
| Exclusive | 80+ | $50,000-$200,000 | 2 hours |

### NPC Movement Patterns

- **Stationary**: Classic standing NPC
- **Wander**: Moves randomly within a radius of home location
- **Patrol**: Follows defined waypoints with wait times
- **Schedule**: Different locations at different times of day

## Installation

1. **Dependencies**: Ensure you have:
   - qb-core
   - ox_lib
   - ox_target

2. **Copy Config**:
   ```bash
   cp config.example.lua config.lua
   ```

3. **Add API Keys**: Edit `config.lua`:
   ```lua
   Config.AI.apiKey = "your_anthropic_or_openai_key"
   Config.TTS.apiKey = "your_elevenlabs_key" -- Optional
   ```

4. **Add to server.cfg**:
   ```
   ensure ai-npcs
   ```

5. **Restart Server**

## Included NPCs

### Crime & Underground
| NPC | Location | Specialty |
|-----|----------|-----------|
| Sketchy Mike | Yellow Jack Inn | Street-level drug/crime intel |
| Charlie the Fence | Chamberlain Hills | Stolen goods, buyer contacts |
| The Architect | Mirror Park | Heist planning, bank security |
| Smokey | Grove Street | Weed connections |
| Rico | Vinewood | Cocaine supply chain |
| Walter | Sandy Shores | Meth production |
| Viktor | Docks | Weapons and ammunition |

### Gang Contacts
| NPC | Gang | Territory |
|-----|------|-----------|
| El Guapo | Vagos | Jamestown |
| Purple K | Ballas | Davis |
| Big Smoke Jr | Families | Grove Street |
| Chains | Lost MC | East Vinewood |

### Legitimate NPCs
| NPC | Role | Location |
|-----|------|----------|
| Margaret Chen | Career Counselor | City Hall |
| Old Pete | Mechanic Mentor | Burton |
| Dr. Hartman | Doctor | Pillbox Hospital |
| Vanessa Sterling | Real Estate | Downtown |
| Captain Marcus | Pilot | LSIA |
| Attorney Goldstein | Lawyer | Downtown |

### Service & Immersion
| NPC | Role | Location |
|-----|------|----------|
| Jackie | Bartender | Bahama Mamas (night) |
| Dexter | Casino Host | Diamond Casino (night) |
| Crazy Earl | Street Sage | Legion Square |

## Configuration

### Adding New NPCs

```lua
{
    id = "unique_id",
    name = "Display Name",
    model = "ped_model_name",
    blip = { sprite = 280, color = 1, scale = 0.6, label = "Blip Name" }, -- Optional
    homeLocation = vector4(x, y, z, heading),
    movement = {
        pattern = "wander", -- stationary, wander, patrol, schedule
        locations = {} -- For patrol/schedule patterns
    },
    schedule = { -- Optional availability times
        { time = {20, 4}, active = true },  -- Active 8 PM to 4 AM
        { time = {4, 20}, active = false }  -- Not available daytime
    },
    role = "street_informant",
    voice = Config.Voices.male_street, -- ElevenLabs voice ID
    trustCategory = "criminal", -- Trust tracked per category

    personality = {
        type = "Character Type",
        traits = "Personality description",
        knowledge = "What they know about",
        greeting = "What they say when you approach"
    },

    contextReactions = {
        copReaction = "extremely_suspicious",
        hasDrugs = "more_open",
        hasMoney = "greedy",
        hasCrimeTools = "respectful"
    },

    intel = {
        {
            tier = "rumors",
            topics = {"topic1", "topic2"},
            trustRequired = 0,
            price = 0
        }
    },

    systemPrompt = [[Your AI system prompt here...]]
}
```

### Context Reactions

Available reaction types for NPCs:
- `extremely_suspicious` - Very evasive, gives false info
- `hostile_dismissive` - Refuses to engage, threatens
- `paranoid_shutdown` - Complete shutdown, denies everything
- `professional_denial` - Maintains cover story perfectly
- `pretends_not_to_notice` - Ignores what they see
- `interested` / `very_interested` - Opens up more
- `business_minded` - Talks money and deals
- `neutral` - No special reaction

## Integration with Other Resources

### Exports

```lua
-- Get player's trust with an NPC
local trust = exports['ai-npcs']:GetPlayerTrustWithNPC(playerId, npcId)

-- Add trust between player and NPC
exports['ai-npcs']:AddPlayerTrustWithNPC(playerId, npcId, amount)
```

### Events

```lua
-- Client: Receive NPC message
RegisterNetEvent('ai-npcs:client:receiveMessage', function(message, npcId)
    -- Handle message
end)

-- Client: Show payment prompt
RegisterNetEvent('ai-npcs:client:showPaymentPrompt', function(price, topic, tier)
    -- Handle payment UI
end)

-- Server: End conversation
TriggerServerEvent('ai-npcs:server:endConversation')
```

## API Setup

### Anthropic Claude (Recommended)
1. Visit https://console.anthropic.com/
2. Create API key
3. Set `Config.AI.provider = "anthropic"`
4. Add key to `Config.AI.apiKey`

### OpenAI GPT
1. Visit https://platform.openai.com/api-keys
2. Create API key
3. Set `Config.AI.provider = "openai"`
4. Set `Config.AI.apiUrl = "https://api.openai.com/v1/chat/completions"`
5. Add key to `Config.AI.apiKey`

### ElevenLabs TTS (Optional)
1. Visit https://elevenlabs.io/
2. Create account and get API key
3. Set `Config.TTS.enabled = true`
4. Add key to `Config.TTS.apiKey`

## Usage

1. **Find an NPC**: Look for NPCs at configured locations
2. **Start Conversation**: Use ox_target to "Talk to [Name]"
3. **Chat**: Type messages to interact
4. **Offer Payment**: Use "Offer Payment" option for intel
5. **Build Trust**: Return regularly to build relationships
6. **Get Intel**: Once trusted, ask about specific topics

## Cost Optimization

### AI API Costs
- Claude Haiku: ~$0.00025/1k input, ~$0.00125/1k output
- GPT-4: ~$0.03/1k tokens (more expensive)

### Reducing Costs
- Use Claude Haiku (default) - fast and cheap
- Limit max tokens (default 200)
- Set reasonable conversation limits
- Enable audio caching for TTS

## Troubleshooting

### NPCs Not Responding
- Check API key validity
- Verify internet connectivity
- Check server console for HTTP errors

### NPCs Not Moving
- Ensure `Config.Movement.enabled = true`
- Check movement pattern is not "stationary"
- Verify patrol waypoints are valid coordinates

### Trust Not Saving
- Trust is in-memory by default
- Implement MySQL save in `SaveTrustData()` for persistence

### Schedule NPCs Not Appearing
- Check in-game time matches schedule
- Verify schedule time ranges are correct

## Version History

- **v2.0.0** - Major overhaul
  - Added trust/reputation system
  - Added intel/clue pricing system
  - Added player context awareness (job, items, money, gang)
  - Added NPC movement patterns (wander, patrol, schedule)
  - Added 20+ diverse NPCs across the map
  - Added cop detection and appropriate NPC reactions
  - Added payment UI integration with ox_lib
  - Claude API support alongside OpenAI

- **v1.0.0** - Initial release
  - Basic AI conversation system
  - OpenAI GPT integration
  - ElevenLabs TTS support

## Credits

Original concept by DaemonAlex. Enhanced for DPSRP with comprehensive RP features.
