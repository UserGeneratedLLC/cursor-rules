# Analytics Implementation Rules for Roblox

When implementing analytics tracking in this Roblox game, follow these guidelines.

## Table of Contents
1. Core Principles
2. Adding Player Events
3. Tracking Player Attributes
4. Verification Process (CRITICAL)
5. Common Mistakes to Avoid
6. Roblox/Luau Specific Knowledge
7. Final Verification (CRITICAL)

---

## 1. CORE PRINCIPLES

### MINIMAL Changes Only
DO NOT refactor existing code. Add analytics with absolute minimum changes. If you don't need to modify something, don't touch it.

BAD (refactoring their code):
```lua
local function setNight()
    handler.nightIndex += 1
    script:SetAttribute("NightNumber", handler.nightIndex)
    mapObject:toggleLights(false, 0.2)
end
```

GOOD (minimal change):
```lua
local function setNight()
    mapObject:toggleLights(false, 0.2)
    RUNTIME.TimeString.Value = "NIGHT"  -- Use what exists
end
```

### Use What Already Exists
Before creating new tracking, SEARCH the codebase to see if data is already tracked.

Example: Instead of creating `handler.nightIndex`, use existing `RUNTIME.DayInt` and `RUNTIME.TimeString`.

### Wrap in task.spawn Only When Necessary
Only use task.spawn() when there's real risk of errors. Don't wrap simple operations.

UNNECESSARY:
```lua
task.spawn(function()
    Analytics:IncrementPlayerAttribute(plr, "TotalDigEvents", 1)
end)
```

BETTER:
```lua
Analytics:IncrementPlayerAttribute(plr, "TotalDigEvents", 1)
```

NECESSARY (complex logic):
```lua
task.spawn(function()
    local itemInstance = RS_ASSETS.Instances.DigItems:FindFirstChild(itemObject.itemName)
    local itemRarity = itemInstance and itemInstance:GetAttribute("Rarity") or "Unknown"
    local pickupDepth = 0
    if plr.Character and plr.Character:GetAttribute("InDigZone") then
        local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
        if hrp and digZone.DIG_ZONE_FOLDER then
            local terrainBox = digZone.DIG_ZONE_FOLDER.TerrainBoundingBox
            local startPos = (terrainBox.CFrame * CFrame.new(0, terrainBox.Size.Y/2, 0)).Position
            local progressDirection = -terrainBox.CFrame.UpVector
            pickupDepth = math.max(0, utils.getDirectedDistance(startPos, hrp.Position, progressDirection))
        end
    end
    Analytics:LogPlayerEvent(plr, "PlayerItemPickup", {...})
end)
```

### Don't Add Obvious Comments
Analytics calls are self-documenting. Don't add `-- Analytics: EventName`.

---

## 2. ADDING PLAYER EVENTS

### Event Naming Convention
Prefix ALL player events with "Player":
- PlayerItemPickup
- PlayerItemSell
- PlayerItemBuy
- PlayerDeath
- PlayerEscaped
- PlayerFreeFoodReceived

### Basic Event Structure
```lua
Analytics:LogPlayerEvent(plr, "PlayerEventName", {
    AttributeName = value,
    AnotherAttribute = anotherValue,
})
```

### Example: PlayerItemBuy Event
Find where purchase happens (e.g., plrAttemptTrade):

```lua
function handler.plrAttemptTrade(plr : Player, npcModel : Model)
    local npcObject = NPCHandler.getNPCByModel("RegularPrisoner", npcModel)
    local cost = npcObject.sellItem:GetAttribute("Cost") or math.huge
    
    if plr.hiddenstats.ToiletPaper.Value >= cost then
        plr.hiddenstats.ToiletPaper.Value -= cost
        local toolType = npcObject.sellItem:GetAttribute("Tool_Type")
        purchaseTypeMap[toolType](plr, npcObject.sellItem.Name)
        
        -- Add AFTER successful purchase
        Analytics:LogPlayerEvent(plr, "PlayerItemBuy", {
            ItemName = npcObject.sellItem.Name,
            ItemType = toolType,
            Cost = cost,
        })
    end
end
```

### Incremental Counters
For auto-incrementing totals (persists across sessions):

```lua
-- Increment the counter
Analytics:IncrementPlayerAttribute(plr, "TotalItemsPickedUp", 1)

-- Log the event with event-specific data only
Analytics:LogPlayerEvent(plr, "PlayerItemPickup", {
    ItemName = itemName,
    ItemRarity = rarity,
})
```

The `TotalItemsPickedUp` value is automatically available in `session:GetAttribute("TotalItemsPickedUp")` from the attribute provider - no need to manually include it in events.

---

## 3. TRACKING PLAYER ATTRIBUTES

Player attributes are **state/contextual data** automatically attached to **every event**. This is separate from event-specific data.

### State vs Event-Specific Data

**State Data (goes in attribute provider):**
- Current player health, position, stats
- Character state (IsCrouching, InDigZone, IsSprinting)
- Game state (DayNumber, RoundDuration, TimeOfDay)
- Persistent totals (TotalItemsPickedUp, TotalDeaths)

**Event-Specific Data (goes in LogPlayerEvent):**
- Data unique to THIS event occurrence
- Item names, costs, amounts specific to the action
- Deltas/changes (ActualHealed, DamageDealt, DistanceTraveled)

**Example:** PlayerUsedHealingItem event
- State: `CurrentHealth` (attribute provider - useful for ALL events)
- Event-specific: `ItemName`, `HealAmount`, `ActualHealed` (LogPlayerEvent - only relevant to this event)

### Two Places to Add Attributes

#### A. BuildGeneralAttributesAsync
For state/contextual data available on ALL events (player stats, game state):

```lua
local function BuildGeneralAttributesAsync(
    session: Session.Type,
    profileData: Profiles.Data?,
    sendInventory: boolean
): {[string]: any}
    local player = session.Player
    local results = {}
    
    -- Player stats (STATE - useful for all events)
    local hiddenstats = player:FindFirstChild("hiddenstats")
    if hiddenstats then
        results["Shared.Energy"] = GetValue(hiddenstats:FindFirstChild("NormalizedEnergy"), 0)
        results["Shared.ToiletPaper"] = GetValue(hiddenstats:FindFirstChild("ToiletPaper"), 0)
    end
    
    -- Character state (useful for all events)
    if player.Character then
        results["Shared.InDigZone"] = player.Character:GetAttribute("InDigZone") or false
        
        -- Health is STATE - useful context for ANY event
        local humanoid = player.Character:FindFirstChild("Humanoid")
        if humanoid then
            results["Shared.Health"] = humanoid.Health
            results["Shared.MaxHealth"] = humanoid.MaxHealth
        end
    end
    
    return results
end
```

#### B. RegisterPlayerEventAttributeProvider
For session-specific or game-handler attributes:

```lua
Analytics:RegisterPlayerEventAttributeProvider(function(
    player,
    eventName
): {[string]: any}
    local session = Analytics:Session(player)
    if not session then return {} end
    
    local results = BuildGeneralAttributesAsync(session, profile and profile.Data, false)
    
    -- Session attributes (auto-tracked counters)
    results["Shared.TotalDigEvents"] = session:GetAttribute("TotalDigEvents")
    results["Shared.TotalItemsSold"] = session:GetAttribute("TotalItemsSold")
    
    return results
end)
```

### GetValue Helper Function
Always use helper for safe value access from Roblox instances:

```lua
local function GetValue(instance: Instance?, defaultValue: any): any
    if instance and instance:IsA("ValueBase") then
        return (instance :: any).Value
    end
    return defaultValue
end

-- Usage:
results["Shared.DayNumber"] = GetValue(runtime:FindFirstChild("DayInt"), 0)
```

---

## 4. VERIFICATION PROCESS (CRITICAL)

### MUST Verify Every Single Attribute

Before using ANY attribute, VERIFY it exists. Use grep:

```bash
grep -r "NormalizedEnergy" src/
grep -r "DayInt" src/
grep -r "SetAttribute.*IsCrouch" src/
```

### Verification Checklist
For EACH attribute:
1. ✅ Does it exist? (grep the codebase)
2. ✅ Is it set/updated? (find where assigned)
3. ✅ Is it the right type? (ValueBase or Attribute)
4. ✅ Is it always available? (lobby vs game server)

### Example Verification: IsCrawling

1. Search: `grep -r "IsCrouch" src/`
2. Results: `MechanicController.isCrouched` (client-side only)
3. Search: `grep -r "SetAttribute.*[Cc]rouch" src/`
4. NO RESULTS - attribute NOT synced to server
5. DECISION: Cannot track IsCrawling - client-side only

### Example Verification: DayNumber

1. Search: `grep -r "DayInt" src/`
2. Results: `RUNTIME.DayInt.Value = dayIndex`
3. VERIFIED - value exists and is updated
4. DECISION: Use `GetValue(runtime:FindFirstChild("DayInt"), 0)`

---

## 5. COMMON MISTAKES TO AVOID

### Mistake #1: Trying to Require Server Scripts
CANNOT require .server.luau scripts - only ModuleScripts.

BAD:
```lua
local GameHandler = require(ServerScriptService.ServerMain.init)  -- .server.luau = ERROR
```

GOOD:
```lua
-- In GameHandler ModuleScript (init.luau)
handler.RoundStartTime = tick()
handler.PlayersStarted = 0

-- In Setup.server.luau
local GameHandler = require(ServerScriptService.ServerMain.GameHandler)
local roundDuration = tick() - GameHandler.RoundStartTime
```

### Mistake #2: Creating New Tracking vs Using Existing

BAD:
```lua
local nightIndex = 0
function setNight()
    nightIndex += 1
end
```

GOOD:
```lua
-- They already have RUNTIME.TimeString = "DAY" or "NIGHT"
local runtime = ReplicatedStorage:FindFirstChild("Runtime")
if runtime then
    results["Shared.TimeString"] = GetValue(runtime:FindFirstChild("TimeString"), "")
end
```

### Mistake #3: Not Checking Lobby vs Game Server

BAD:
```lua
results["Shared.RoundDuration"] = tick() - GameHandler.RoundStartTime  -- Errors in lobby
```

GOOD:
```lua
local isLobbyServer = game.PlaceId == 92122513197996

if not isLobbyServer then
    if GameHandler.RoundStartTime then
        results["Shared.RoundDuration"] = math.round(tick() - GameHandler.RoundStartTime)
    end
end
```

### Mistake #4: Tracking Unique Players Wrong

BAD (counts current players, not unique):
```lua
handler.playersStarted = #game.Players:GetPlayers()
```

GOOD (tracks UNIQUE players who joined):
```lua
local uniquePlayers = {}

function handler.playerAdded(plr : Player)
    if not uniquePlayers[plr.UserId] then
        uniquePlayers[plr.UserId] = true
        local playersStarted = 0
        for _ in pairs(uniquePlayers) do
            playersStarted += 1
        end
        handler.PlayersStarted = playersStarted
    end
end
```

### Mistake #5: Putting State Data in Events Instead of Attributes

BAD (health is state - useful for ALL events):
```lua
Analytics:LogPlayerEvent(plr, "PlayerTookDamage", {
    DamageAmount = damage,
    HealthAfter = humanoid.Health,  -- WRONG - this is state
    DamageSource = source,
})
```

GOOD (health in attribute provider, only event-specific data in event):
```lua
-- In BuildGeneralAttributesAsync:
results["Shared.Health"] = humanoid.Health  -- Available for ALL events

-- In event:
Analytics:LogPlayerEvent(plr, "PlayerTookDamage", {
    DamageAmount = damage,
    DamageSource = source,
})
```

**Rule:** If the data would be useful context for ANY event, it's state data and belongs in the attribute provider.

### Mistake #6: Over-using task.spawn

BAD:
```lua
task.spawn(function()
    Analytics:IncrementPlayerAttribute(plr, "TotalDigEvents", 1)
end)
```

GOOD:
```lua
Analytics:IncrementPlayerAttribute(plr, "TotalDigEvents", 1)
```

Only use task.spawn for complex operations that could error.

---

## 6. ROBLOX/LUAU SPECIFIC KNOWLEDGE

### Single-Threaded Execution
Roblox runs Luau on SINGLE CPU core. No multi-core execution.

### Server Scripts vs ModuleScripts
- .server.luau = Server script (CANNOT be required)
- .client.luau = Client script (CANNOT be required)  
- .luau or init.luau = ModuleScript (CAN be required)

### CRITICAL: ServerScriptService Require Safety
NEVER require ServerScriptService modules from:
- Client scripts (.client.luau or in StarterPlayer)
- Shared scripts in ReplicatedStorage (could be used by client)

BAD:
```lua
-- In ReplicatedStorage/Modules/SomeSharedModule.luau
local Analytics = require(game.ServerScriptService.UserGenerated.Analytics)  -- ERROR if client uses this
```

GOOD:
```lua
-- ONLY require ServerScriptService from server-side code:
-- ✅ ServerScriptService scripts
-- ✅ ServerStorage scripts
-- ❌ NOT from ReplicatedStorage (unless server-only)
-- ❌ NOT from StarterPlayer scripts
-- ❌ NOT from .client.luau scripts
```

When adding Analytics:
- Check file location first
- If in ServerScriptService/ or ServerStorage/ → Safe to require ServerScriptService
- If in ReplicatedStorage/ → Check if server-only or shared
- If in StarterPlayer/ → NEVER require ServerScriptService

### Instance Hierarchy
Check each level when accessing nested children:

```lua
local serverMain = ServerScriptService:FindFirstChild("ServerMain")
if serverMain then
    local gameHandler = serverMain:FindFirstChild("GameHandler")
    if gameHandler then
        local value = gameHandler:GetAttribute("SomeAttribute")
    end
end
```

### ValueBase Types
Common Roblox value containers (old way):
- IntValue - integers
- NumberValue - floats
- StringValue - strings
- BoolValue - booleans

Access via .Value:
```lua
local dayInt = runtime:FindFirstChild("DayInt")  -- Returns IntValue instance
local dayNumber = dayInt.Value  -- Returns actual number
```

### Attributes vs Values

Attributes (new way):
```lua
instance:SetAttribute("MyNumber", 5)
local value = instance:GetAttribute("MyNumber")
```

ValueBase objects (old way):
```lua
local intValue = Instance.new("IntValue")
intValue.Name = "MyNumber"
intValue.Value = 5
intValue.Parent = someInstance
```

Many older games use ValueBase objects.

### Multi-Place Detection
```lua
local LOBBY_PLACE_ID = 92122513197996
local isLobbyServer = game.PlaceId == LOBBY_PLACE_ID
```

---

## COMPLETE WORKFLOW EXAMPLE

Adding "PlayerUsedHealingItem" event:

### Step 1: Find Location
```bash
grep -r "Heal" src/
grep -r "UseFood" src/
```

Found in ToolHandler.luau:
```lua
function ToolHandler.useFood(plr: Player, tool: Tool)
    local healAmount = tool:GetAttribute("HealAmount") or 20
    local humanoid = plr.Character:FindFirstChild("Humanoid")
    if humanoid then
        humanoid.Health = math.min(humanoid.Health + healAmount, humanoid.MaxHealth)
    end
end
```

### Step 2: Verify Data Points
```bash
grep -r "HealAmount" src/          # ✅ Exists
grep -r "humanoid.Health" src/     # ✅ Exists
```

- ✅ plr - Player object
- ✅ tool.Name - Tool name
- ✅ healAmount - From GetAttribute
- ✅ humanoid.Health - Current health

### Step 3: Add Analytics Module
```lua
local Analytics = require(game.ServerScriptService.UserGenerated.Analytics)
```

### Step 4: Implement
```lua
function ToolHandler.useFood(plr: Player, tool: Tool)
    local healAmount = tool:GetAttribute("HealAmount") or 20
    local humanoid = plr.Character:FindFirstChild("Humanoid")
    if humanoid then
        local healthBefore = humanoid.Health
        humanoid.Health = math.min(humanoid.Health + healAmount, humanoid.MaxHealth)
        local actualHealed = humanoid.Health - healthBefore
        
        -- Event-specific data only. Health is in attribute provider.
        Analytics:LogPlayerEvent(plr, "PlayerUsedHealingItem", {
            ItemName = tool.Name,
            HealAmount = healAmount,
            ActualHealed = actualHealed,
        })
    end
end
```

### Step 5: Test
- Event fires when expected
- All attributes have valid values
- Works in lobby and game servers

---

## IMPLEMENTATION CHECKLIST

Before implementing analytics:
- [ ] Search for existing tracking - don't duplicate
- [ ] VERIFY EVERY attribute exists (grep each one)
- [ ] Check lobby vs game server detection needed
- [ ] Use minimal changes - don't refactor
- [ ] Only wrap in task.spawn if complex logic could error
- [ ] Don't add obvious comments
- [ ] Put STATE data (health, position, stats) in attribute provider, NOT events
- [ ] Put EVENT-SPECIFIC data (item name, cost, amount) in LogPlayerEvent
- [ ] Use Analytics:IncrementPlayerAttribute for persistent counters
- [ ] Use session:GetAttribute for session-only data

After implementing analytics:
- [ ] Review ALL git changes (staged + unstaged)
- [ ] Verify each change meets doc specifications
- [ ] Run final verification checklist (see FINAL VERIFICATION section)
- [ ] Ensure zero new linter errors

---

## QUICK REFERENCE

### Add Player Event
```lua
-- After successful action:
Analytics:LogPlayerEvent(plr, "PlayerEventName", {
    Attribute1 = value1,
    Attribute2 = value2,
})
```

### Increment Counter
```lua
Analytics:IncrementPlayerAttribute(plr, "CounterName", amount)
```

### Add Attribute to BuildGeneralAttributesAsync
```lua
-- In Setup.server.luau
local function BuildGeneralAttributesAsync(...): {[string]: any}
    local results = {}
    
    -- Use GetValue helper
    local hiddenstats = player:FindFirstChild("hiddenstats")
    if hiddenstats then
        results["Shared.Energy"] = GetValue(hiddenstats:FindFirstChild("NormalizedEnergy"), 0)
    end
    
    return results
end
```

### Add Session Attribute
```lua
-- In RegisterPlayerEventAttributeProvider
results["Shared.TotalDigEvents"] = session:GetAttribute("TotalDigEvents")
```

### Verify Attribute Exists
```bash
grep -r "AttributeName" src/
grep -r "SetAttribute.*AttributeName" src/
grep -r "\.Value = " src/  # For ValueBase objects
```

### Detect Lobby Server
```lua
local isLobbyServer = game.PlaceId == 92122513197996
if not isLobbyServer then
    -- Game-specific tracking
end
```

---

## FINAL VERIFICATION (CRITICAL)

Before submitting any analytics implementation, perform a complete audit of ALL changes:

### Review Git Changes
Examine ALL staged and unstaged changes in git to verify every modification meets the specifications in this document.

```bash
# Review all changes
git diff
git diff --staged

# Or review in IDE's source control view
```

### Verification Checklist
For EVERY file that was modified:

1. ✅ **Minimal Changes**: No refactoring, only analytics additions
2. ✅ **Used What Exists**: No new tracking systems created
3. ✅ **All Attributes Verified**: Every attribute was grepped and confirmed to exist
4. ✅ **No task.spawn Abuse**: Only used where complex logic could error
5. ✅ **No Comments**: No obvious analytics comments added
6. ✅ **State vs Session**: Attributes correctly categorized
7. ✅ **Lobby Detection**: Game-specific tracking checks isLobbyServer
8. ✅ **Type Safety**: Proper type checks (IsA, type guards)
9. ✅ **No Linter Errors**: Zero new linter errors introduced

### Audit Questions
Ask yourself for each change:
- Why was this line changed?
- Does it follow the MINIMAL changes principle?
- Is there a simpler way?
- Did I verify the attribute exists?
- Will this work in lobby AND game servers?

### Red Flags
Stop and reconsider if you see:
- ❌ More than 100 lines added for a single state attribute
- ❌ Any refactoring of existing game code
- ❌ New tracking systems (handlers, modules, etc)
- ❌ task.spawn wrapped around simple operations
- ❌ Comments explaining analytics code
- ❌ Attributes that weren't verified with grep
- ❌ Linter errors in modified files

**If unsure, audit the staged changes against this document section by section.**

---

## WHEN IN DOUBT

1. Grep the codebase to verify existence
2. Check if it's set (search SetAttribute or .Value =)
3. Ask developer which values matter
4. Better to track LESS than track INVALID data

Full details: docs/analytics-implementation-guide.md


