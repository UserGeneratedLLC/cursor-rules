---
name: abtest
description: Implement AB test attributes in game code. Use when the user asks to add an AB test, make a value configurable via AB tests, add remote configurability, or wire up ABTests.GetAttribute / GetJobAttribute calls.
---

# Implementing AB Tests

This skill guides you through adding AB test attributes to the codebase. See the API Reference at the end for method signatures and events.

## 1. Decide: Player-Level vs Job-Level

| Scope | API | Assigned by | Use when |
|-------|-----|-------------|----------|
| **Player** | `GetAttribute` / `GetAttributeAsync` | Per-player (UserId) | Different players should see different values: tutorial thresholds, UI variants, per-player multipliers |
| **Job** | `GetJobAttribute` / `GetJobAttributeAsync` | Per-server (JobId) | All players on a server share the same value: event parameters, feature toggles, wave configs, spawn rates |

Job-level tests use a `JOBID-` prefix internally -- you don't need to add this yourself; backend handles it based on test config.

## 2. Name the Attribute Key

Use dot-separated hierarchical names: `{System}.{Feature}.{Parameter}`

### Naming rules

- PascalCase each segment
- Boolean toggles: end with `.Enabled` (e.g., `Eco.DiversityBonus.Enabled`)
- Numeric tunables: name the parameter directly (e.g., `Event.Money.StormDuration`)
- String variants: name the choice (e.g., `FTU.TutorialGroup`)

### Real examples from the codebase

```
-- Job-level (server-wide)
Event.Money.StormDuration          -- number (seconds)
Event.FireAndIce.MutationChance    -- number (0-1)
Wave.MinGapStudsMin                -- number
GenRate.ShowOverhead               -- boolean
AB.HideCarryStand                  -- boolean
LuckyBlock.NaturalSpawn.Enabled    -- boolean

-- Player-level (per-player)
FTU.SessionCountThreshold          -- number
Camera.ZoomMultiplier              -- number
Eco.DiversityBonus.Enabled         -- boolean
FriendRequest.Enabled              -- boolean
Steal.Common                       -- number (weight)
```

## 3. Sync vs Async

| Variant | Yields? | Use in |
|---------|---------|--------|
| `GetAttribute` / `GetJobAttribute` | No | Gameplay loops, event handlers, UI updates, anywhere yielding is unsafe |
| `GetAttributeAsync` / `GetJobAttributeAsync` | Yes | `playerAdded`, join flows, `init()` where you need the value before proceeding |

**Rule:** Default to sync. Only use async when you explicitly need to block until the value is available (e.g., deciding whether to teleport a player on join).

## 4. Implementation Workflow

### Step 1: Add the import

```luau
local ABTests = require(ReplicatedStorage.UserGenerated.ABTests)
```

Place it in the `-- Imports` section of the service/controller.

### Step 2: Replace hardcoded values

Find the hardcoded value and replace it with an ABTests call. **Always use the current hardcoded value as the default** so behavior is unchanged without backend config.

Before:
```luau
local STORM_DURATION = 30
```

After:
```luau
local stormDuration = ABTests.GetJobAttribute("Event.Money.StormDuration", 30)
```

### Step 3: Add reactive updates (client only, if needed)

If the value can change at runtime via live config updates, listen for changes. Which event depends on scope:

- **Player-level:** `ABTests.PlayerUpdated`
- **Job-level:** `ABTests.JobUpdated`

### Step 4: Add condition callbacks (if needed)

If the test needs custom targeting conditions (beyond what backend can do with built-in conditions), add a callback to `ABTestConditions.server.luau`. See section 6.

## 5. Code Templates

### Server service -- sync (most common)

For values read during gameplay. No yielding.

```luau
-- In a service function
local function processReward(player: Player)
    local multiplier = ABTests.GetJobAttribute("Reward.Multiplier", 1)
    giveReward(player, BASE_REWARD * multiplier)
end
```

### Server service -- async (join flow)

For values needed before a player-specific decision on join.

```luau
function MyService.playerAdded(player: Player)
    local threshold = ABTests.GetAttributeAsync(player, "FTU.SpeedThreshold", 200)
    if player.Data.CurrentSpeed >= threshold then
        return
    end
    -- player qualifies for FTU flow
end
```

### Client controller -- player-level with reactive updates

```luau
local ABTests = require(ReplicatedStorage.UserGenerated.ABTests)
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local MyController = {}

local function applySettings()
    local enabled = ABTests.GetAttribute(LocalPlayer, "Feature.Enabled", false)
    if type(enabled) ~= "boolean" then
        enabled = false
    end
    -- apply the value
end

function MyController.init()
    -- Apply once loaded
    if ABTests.IsLoaded() then
        applySettings()
    else
        task.spawn(function()
            ABTests.Loaded:Wait()
            applySettings()
        end)
    end

    -- React to live updates
    ABTests.PlayerUpdated:Connect(function(updatedPlayer)
        if updatedPlayer == LocalPlayer then
            applySettings()
        end
    end)
end

return MyController
```

### Client controller -- job-level with reactive updates

```luau
local ABTests = require(ReplicatedStorage.UserGenerated.ABTests)

local MyController = {}

local function applySettings()
    local showFeature = ABTests.GetJobAttribute("AB.ShowFeature", true)
    if type(showFeature) ~= "boolean" then
        showFeature = true
    end
    -- apply the value
end

function MyController.init()
    if ABTests.IsLoaded() then
        applySettings()
    else
        task.spawn(function()
            ABTests.Loaded:Wait()
            applySettings()
        end)
    end

    ABTests.JobUpdated:Connect(applySettings)
end

return MyController
```

### Client controller -- async in init (blocking)

When the controller cannot proceed without the value. Use sparingly -- this yields init.

```luau
function MyController.init()
    local enabled = ABTests.GetJobAttributeAsync("FTU.HideTower", true)
    if not enabled then
        return
    end
    -- setup tower UI
end
```

### Event module -- job-level tunables

Events typically read many job-level attributes for all their parameters:

```luau
local function run(duration: number, _context: any?)
    local messageDelay = ABTests.GetJobAttribute("Event.MyEvent.MessageDelay", 3)
    local messageText = ABTests.GetJobAttribute(
        "Event.MyEvent.Message",
        "My Event has started!"
    )
    local spawnRate = ABTests.GetJobAttribute("Event.MyEvent.SpawnRate", 0.5)
    local maxItems = ABTests.GetJobAttribute("Event.MyEvent.MaxItemCap", 100)

    task.delay(messageDelay, function()
        Popup.GlobalMessage(messageText)
    end)

    -- use spawnRate, maxItems in event logic...

    return function()
        -- cleanup
    end
end
```

## 6. Adding Condition Callbacks

Condition callbacks let the backend target tests to specific server/player states. Add them to `src/ServerScriptService/UGApp/ABTestConditions.server.luau`.

### Structure

The file exports a module table of callbacks. All callbacks are auto-registered at the bottom via a loop:

```luau
for name, func in pairs(module) do
    if type(name) == "string" and type(func) == "function" then
        ServerABTests.RegisterConditionCallback(name, func)
    end
end
```

### Template for a new callback

```luau
--[[
    Description of what this condition checks.
    @param player Required/Optional
    @param arg1 Description
    @return true if condition is met
]]
function module.MyConditionName(
    player: Player?,
    arg1: number,
    arg2: number?
): boolean
    assert(player)
    Asserts.Player(player)
    Asserts.IntegerNonNegative(arg1)
    if arg2 ~= nil then
        Asserts.IntegerNonNegative(arg2)
    end
    -- logic here
    return result
end
```

### Existing callbacks (for reference)

| Callback | Purpose |
|----------|---------|
| `TestRecentPurchases` | Purchase count in last N days within [min, max] |
| `TestRobuxSpend` | Total Robux spent in last N days within [min, max] |
| `TestSessionCount` | Lifetime session count within [min, max] |
| `TestPlaceId` | `game.PlaceId` in allowed list |
| `IsPrivateServer` | `game.PrivateServerId ~= ""` |
| `IsPrivateServerOwner` | Private server + player is owner |
| `TestServerSize` | Player count within [min, max] |
| `TestPlaceVersion` | `game.PlaceVersion` meets minimum per-place |
| `IsFTUServer` | `TPService.isFTU()` |

### Key rules

- Type signature: `(player: Player?, ...any) -> boolean`
- Always `assert(player)` if the condition requires a player
- Validate all arguments with `Asserts` at the top
- For range checks: `min` inclusive, `max` inclusive and optional
- Player conditions can access profile data via `Profiles.GetAsync(player, true)`
- Server conditions (no player needed) still receive `player: Player?` parameter

## 7. Best Practices

1. **Default = current behavior.** The default value in `GetAttribute`/`GetJobAttribute` must match the current hardcoded value. This ensures no behavior change without backend config.

2. **Validate returned types.** Backend can send unexpected types. Guard booleans and numbers:
   ```luau
   local val = ABTests.GetJobAttribute("Key", true)
   if type(val) ~= "boolean" then val = true end
   ```

3. **Don't yield in hot paths.** Use sync `GetAttribute`/`GetJobAttribute` in gameplay loops, event handlers, and render callbacks. These return the default if not loaded yet.

4. **Comment the ABTest attributes.** At the top of the file or above the function, document what attributes are read and their types/defaults:
   ```luau
   -- ABTest Attributes:
   -- - Camera.ZoomMultiplier: number (default 1.3)
   ```

5. **Backend handles test configuration.** You implement the attribute reads. Backend configures groups, percentages, conditions, and scheduling. Once your code is merged, backend sets up the test.

6. **One attribute per tunable.** Don't pack multiple values into a single table attribute when they could be independent. `Event.Money.SpawnRate` and `Event.Money.MaxCap` are better than `Event.Money.Config = {spawnRate=0.5, maxCap=100}`.

## 8. API Reference

### Setup

Works on both client and server:

```luau
local ABTests = require(ReplicatedStorage.UserGenerated.ABTests)
```

### Player Attributes

| Method | Yields? | Description |
|--------|---------|-------------|
| `ABTests.GetAttribute(player, key, default)` | No | Returns current value or default if not loaded yet |
| `ABTests.GetAttributeAsync(player, key, default)` | Yes | Yields until attribute is loaded, then returns value or default |

Client can only read `LocalPlayer`'s attributes. Other players always return default.

### Job Attributes

Job attributes use the first player in the server (or `LocalPlayer` on client). All players on a server share the same value.

| Method | Yields? | Description |
|--------|---------|-------------|
| `ABTests.GetJobAttribute(key, default)` | No | Returns current value or default if not loaded yet |
| `ABTests.GetJobAttributeAsync(key, default)` | Yes | Yields until attribute is loaded, then returns value or default |

### System State

| API | Description |
|-----|-------------|
| `ABTests.IsLoaded()` | Returns `true` if the system has loaded initial values |

### Events

| Event | Fires when | Payload |
|-------|-----------|---------|
| `ABTests.Loaded` | System loads initial values | *(none)* |
| `ABTests.PlayerUpdated` | A player's attributes change at runtime | `(player: Player)` |
| `ABTests.JobUpdated` | Job-level attributes change at runtime | *(none)* |

### Default Values

Default values can be any Luau type:

| Type | Example |
|------|---------|
| String | `ABTests.GetAttribute(player, "Variant", "Control")` |
| Number | `ABTests.GetAttribute(player, "DamageMultiplier", 1.5)` |
| Boolean | `ABTests.GetAttribute(player, "NewFeature", false)` |
| Table | `ABTests.GetAttribute(player, "ShopPrices", { sword = 100, shield = 50 })` |

### Notes

- **Async vs sync:** Async methods yield until loaded. Use async for join flows, sync for gameplay loops and event handlers.
- **Client limitation:** Client can only read `LocalPlayer`'s attributes. Other players always return default.
- **How it works:** You implement the attribute reads in your code. Backend handles all test configuration (groups, percentages, player/server scoping, scheduling). Once your code is merged, backend configures the test.
