# Adaptation Guide

Installing analytics requires adapting three UGApp files (Profiles, Setup, ABTestConditions) to the game's saving system. The saving module is Step 1 because it determines everything downstream.

## Step 1: Investigate the Saving Module

Find the game's data/saving module and read it. Identify which category it falls into, then note these details for later steps:

- **Data template** -- what fields exist (directly maps to `BuildGeneralAttributesAsync` attributes)
- **Profile type** -- what Profiles.luau will export
- **Profiles table** -- how to look up a loaded profile
- **Events** -- do `OnAdded`/`OnReleasing` (or equivalents) already exist?
- **Purchase receipts** -- where are they stored? (needed for ABTestConditions)
- **Session metadata** -- `FirstSessionTime`, `SessionLoadCount` or equivalents (needed for Reconciler)

### Category A: ProfileStore (MAD Studio fork)

Most common. Look for `ProfileStore.New(...)`, `StartSessionAsync`, `profile.OnSessionEnd`.

| Field | Location |
|-------|----------|
| Data | `profile.Data` |
| Session count | `profile.SessionLoadCount` |
| First session | `profile.FirstSessionTime` |
| Release callback | `profile.OnSessionEnd:Connect(fn)` |
| Profile type | `ProfileStore.Profile<Data>` |

### Category B: ProfileService (Madwork)

Older library. Look for `ProfileService.GetProfileStore(...)`, `LoadProfileAsync`, `ListenToRelease`.

| Field | Location |
|-------|----------|
| Data | `profile.Data` |
| Session count | `profile.MetaData.SessionLoadCount` |
| First session | `profile.MetaData.ProfileCreateTime` |
| Release callback | `profile:ListenToRelease(fn)` |
| Profile type | `{ Data: Data, MetaData: {...} }` (or game's own type alias) |

### Category C: Custom DataStore (no library)

Raw `DataStoreService:GetDataStore()`. Look for `GetAsync`/`SetAsync`, manual save loops.

| Field | Location |
|-------|----------|
| Data | Varies -- may be a table, player attributes, or leaderstats |
| Session count | May not exist. Use `Saves:GetSaveAsync` as fallback |
| First session | May not exist. Omit from Reconciler if unavailable |
| Release callback | Usually `Players.PlayerRemoving` |
| Profile type | Jerry-rig as `{ Data: Data }` |

If data lives in attributes/leaderstats rather than a table, build the profile on demand (see break-a-lucky-block pattern).

### Category D: Custom Event System

No profile concept. Look for event buses (TEvent, BindableEvents, custom signal systems).

| Field | Location |
|-------|----------|
| Data | Raw table from the data API |
| Session count | Use `Saves:GetSaveAsync` |
| Release callback | Wire to existing "data saving" event |
| Profile type | Define manually in Profiles.luau |

Wire UGApp Profiles to the existing event system rather than modifying the data layer directly.

---

## Step 2: Modify the Saving Module

Add what's missing so Profiles.luau can hook in. Skip items that already exist.

### What to add

1. **Bindable events** (`OnAdded`, `OnReleasing`) if the module doesn't already expose them
2. **Type exports** (`export type Data`, `export type Profile`) if not already exported
3. **Profiles table export** if the lookup isn't publicly accessible

If the saving module is a `.server.luau` (cannot be required), convert it:
- Rename to `init.luau` (ModuleScript)
- Create a child `.server.luau` that requires the parent and calls an `init()` or `start()` function
- Move the imperative startup code into that function

### Event Timing (CRITICAL)

**OnAdded must fire AFTER all of these, in order:**

1. DataStore load completes
2. `Reconcile()` runs (fills missing template keys)
3. Data migrations run (version upgrades, schema changes)
4. Data corrections run (fixing negative values, removing banned items, legacy conversions)
5. Profile is SET in the profiles table (`Profiles[player] = profile`)
6. Replication/attribute setup finishes (Replica creation, `DataLoaded` attribute, leaderstats)
7. **THEN fire `OnAdded(player, profile)`**

The profile MUST be accessible via the normal lookup when OnAdded fires. Listeners (Setup.server.luau) will immediately call `Profiles.GetAsync(player, true)` and expect to get the profile back.

**OnReleasing must fire BEFORE all of these, in order:**

1. **Fire `OnReleasing(player, profile)`** -- profile is still in the table
2. Listeners run (Setup captures final session stats, inventory snapshot)
3. Replica/replicator cleanup
4. Profile is REMOVED from the table (`Profiles[player] = nil`)
5. Player is kicked (if applicable)
6. DataStore save executes

The profile MUST still be in the table when OnReleasing fires. Listeners need to read the profile data one last time.

### ProfileStore hookup

```luau
local Bindable = require(ReplicatedStorage.UserGenerated.Concurrency.Bindable)

-- Add to module exports
local OnAdded: Bindable.Event<Player, Profile> = Bindable.new()
local OnReleasing: Bindable.Event<Player, Profile> = Bindable.new()

-- In the player load function, AFTER reconcile + corrections + table insert:
Profiles[player] = profile
OnAdded:Fire(player, profile)

-- In the OnSessionEnd handler, BEFORE table removal:
profile.OnSessionEnd:Connect(function()
    if Profiles[player] then
        OnReleasing:Fire(player, profile)
    end
    Profiles[player] = nil
end)
```

### ProfileService hookup

```luau
-- In the player load function, AFTER reconcile + corrections + table insert:
Profiles[player] = profile
OnAdded:Fire(player, profile)

-- In the ListenToRelease handler, BEFORE table removal:
profile:ListenToRelease(function()
    if Profiles[player] then
        OnReleasing:Fire(player, profile)
    end
    Profiles[player] = nil
end)
```

### Custom DataStore hookup

```luau
-- After data loads and corrections run:
cache[player] = data
OnAdded:Fire(player, { Data = data })

-- In PlayerRemoving, BEFORE save and cache clear:
local profile = { Data = cache[player] }
OnReleasing:Fire(player, profile)
save(player)
cache[player] = nil
```

### Event bus hookup (Category D)

Don't modify the data layer. Wire in Profiles.luau directly:

```luau
-- In Profiles.luau
local DataAdded: Bindable.Event<Player, Template> = Bindable.new()
local DataReleasing: Bindable.Event<Player, Template> = Bindable.new()

TEvent.OnBindable("PlayerDataReady", function(player)
    DataAdded:Fire(player, assert(DataStoreAPI.GetPlayerAllData(player)::any))
end, {priority = math.huge}) -- fire last, after all corrections

TEvent.OnBindable("PlayerDataSaving", function(player)
    DataReleasing:Fire(player, assert(DataStoreAPI.GetPlayerAllData(player)::any))
end)
```

---

## Step 3: Profiles.luau

Stable skeleton -- only the marked sections change per game.

```luau
--!strict

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ADAPT: require the game's data module
local DataService = require(--[[ game's data module path ]])

-- ADAPT: export types from the data module
export type Data = DataService.Data
export type Profile = DataService.Profile

-- ADAPT: reference the correct event names
local Added = DataService.OnAdded
local Releasing = DataService.OnReleasing

local function GetAsync(
    player: Player,
    async: boolean
): Profile?
    assert(typeof(player) == "Instance" and player:IsA("Player"))
    assert(type(async) == "boolean")
    -- ADAPT: use the correct lookup
    local cached = DataService.Profiles[player]
    if cached then
        return cached
    end
    if not async then
        return nil
    end
    if player.Parent ~= Players then
        return nil
    end
    local thr = coroutine.running()
    local ancestryChanged = player.AncestryChanged:Connect(function(parent)
        if parent ~= Players then
            task.spawn(thr, nil)
        end
    end)
    local conn = Added:Connect(function(
        profilePlayer,
        profile
    )
        if profilePlayer == player then
            task.spawn(thr, profile)
        end
    end)
    local result = coroutine.yield()
    ancestryChanged:Disconnect()
    conn:Disconnect()
    return result
end

return table.freeze({
    Added = Added,
    Releasing = Releasing,
    GetAsync = GetAsync,
})
```

### Common lookup variations

| Pattern | Example |
|---------|---------|
| Direct table | `DataService.Profiles[player]` |
| Keyed by UserId | `DataService.TrueProfiles[player.UserId]` |
| Wrapper object | `DataService.Profiles[player].Profile` |
| Method call | `DataService:GetProfile(player)` or `DataService.GetProfile(player)` |
| Build on demand | `DataHandler.buildProfile(player)` |
| Raw data API | `DataStoreAPI.GetPlayerAllData(player)` |

If events need Bindable wrappers (module fires with different signatures or names):

```luau
local Bindable = require(ReplicatedStorage.UserGenerated.Concurrency.Bindable)

local Added: Bindable.Event<Player, Profile> = Bindable.new()
local Releasing: Bindable.Event<Player, Profile> = Bindable.new()

DataService.OnProfileAdded:Connect(function(player, profile)
    Added:Fire(player, profile)
end)
DataService.OnProfileReleasing:Connect(function(player, profile)
    Releasing:Fire(player, profile)
end)
```

---

## Step 4: Setup.server.luau

The skeleton is stable across all games. Only `BuildGeneralAttributesAsync` changes (populated from the data template discovered in Step 1).

### Stable skeleton

```luau
--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Analytics = require(ServerScriptService.UserGenerated.Analytics)
local Profiles = require(ServerScriptService.UGApp.Profiles)
local Saves = require(ServerScriptService.UserGenerated.Storage.Saves)
local PlayerKit = require(ServerScriptService.UserGenerated.Analytics.PlayerKit)
local Session = require(ServerScriptService.UserGenerated.Analytics.Session)

-- GAME-SPECIFIC: BuildGeneralAttributesAsync (see below)

Analytics:RegisterPlayerEventAttributeProvider(function(player, eventName)
    local session = Analytics:Session(player)
    if not session then return {} end
    local profile = Profiles.GetAsync(player, true)
    local results = BuildGeneralAttributesAsync(session, profile, false)
    -- Add session counters
    results["UG.RobuxSpent"] = session:GetAttribute("UG.RobuxSpent")
    results["UG.RobuxTransactions"] = session:GetAttribute("UG.RobuxTransactions")
    results["UG.CompleteTracking"] = session:GetAttribute("UG.CompleteTracking")
    return results
end)

-- GAME-SPECIFIC: Reconciler (see below)

local function UpdateSessionStats(session, profile, async)
    local attributes = BuildGeneralAttributesAsync(session, profile, true)
    for key, val in pairs(attributes) do
        local success, reason: any = pcall(session.SetAttribute, session, key, val)
        if not success then
            warn(`UpdateSessionStats: {reason}, {key}, {val}`)
        end
    end
end

Profiles.Added:Connect(function(player, profile)
    local session = Analytics:Session(player)
    if session then
        UpdateSessionStats(session, profile, true)
    end
end)

Profiles.Releasing:Connect(function(player, profile)
    local session = Analytics:Session(player)
    if session then
        UpdateSessionStats(session, profile, true)
    end
end)

PlayerKit.CollectingAttributes:Connect(function(session, sessionState, async)
    local profile = Profiles.GetAsync(session.Player, true)
    UpdateSessionStats(session, profile, async)
end)
```

### BuildGeneralAttributesAsync

Map data template fields from Step 1 to `Shared.*` attribute keys. The data template is the primary source of what to track.

```luau
local function BuildGeneralAttributesAsync(
    session: Session.Type,
    profile: Profiles.Profile?,
    sendInventory: boolean
): {[string]: any}
    local player = session.Player
    local profileData: Profiles.Data? = profile and profile.Data
    local results = {}
    results["Shared.ServerSize"] = #Players:GetPlayers()

    if profileData then
        -- Map data template fields to analytics attributes
        -- e.g. results["Shared.Money"] = profileData.Money
        -- e.g. results["Shared.Level"] = profileData.Level
    end

    return results
end
```

### Reconciler

Adapts based on saving system category:

**ProfileStore:**
```luau
Saves.Reconcile:Connect(function(save)
    local saveData = save.Profile.Data
    local profile = Profiles.GetAsync(save.Player, true)
    if profile then
        saveData.CreatedAt = profile.FirstSessionTime
        saveData.Sessions = math.max(0, profile.SessionLoadCount - 1)
        if saveData.Sessions <= 0 then
            saveData.Attributes["UG.CompleteTracking"] = true
        end
    end
end)
```

**ProfileService:**
```luau
Saves.Reconcile:Connect(function(save)
    local saveData = save.Profile.Data
    local profile = Profiles.GetAsync(save.Player, true)
    if profile then
        saveData.CreatedAt = profile.MetaData.ProfileCreateTime
        saveData.Sessions = math.max(0, profile.MetaData.SessionLoadCount - 1)
        if saveData.Sessions <= 0 then
            saveData.Attributes["UG.CompleteTracking"] = true
        end
    end
end)
```

**Custom DataStore:**
```luau
Saves.Reconcile:Connect(function(save)
    local saveData = save.Profile.Data
    -- FirstSessionTime/SessionLoadCount may not be available
    -- Use what the game provides, or omit
end)
```

---

## Step 5: ABTestConditions.server.luau

Universal conditions that work everywhere:

- `TestSessionCount` -- use `Saves:GetSaveAsync` (works with all categories)
- `TestPlaceId` -- `table.find(placeIds, game.PlaceId)`
- `IsPrivateServer` -- `game.PrivateServerId ~= ""`
- `IsPrivateServerOwner` -- `game.PrivateServerOwnerId == player.UserId`
- `TestServerSize` -- `#Players:GetPlayers()`
- `TestPlaceVersion` -- `game.PlaceVersion >= required`

Monetization conditions vary by what's available:

| Condition | ProfileStore | ProfileService | Custom | Fallback |
|-----------|-------------|----------------|--------|----------|
| `TestRecentPurchases` | `profile.Data.PurchaseReceipts` | `profile.Data.PurchaseHistory` | Game-specific | Omit |
| `TestRobuxSpend` | `profile.Data.PurchaseReceipts` | `profile.Data.PurchaseHistory` | Game-specific | `Analytics:GetPlayerAttribute("UG.RobuxSpent")` |

If the game has no purchase receipt storage, use the Analytics attribute fallback (knockout pattern):

```luau
function module.TestRobuxSpend(player, days, min, max)
    local spent = Analytics:GetPlayerAttribute(player, "UG.RobuxSpent") or 0
    if spent < min then return false end
    if max and spent > max then return false end
    return true
end
```

---

## Known Bugs in Existing Installs

Watch for these copy-paste errors:

1. **dusty-trip** `Profiles.luau` line 23: `OnReleasing` handler fires `Added:Fire(...)` instead of `Releasing:Fire(...)`.
2. **knockout2** `Profiles.luau` line 3: `game:GetService("UGApp")` instead of `game:GetService("Players")`.
