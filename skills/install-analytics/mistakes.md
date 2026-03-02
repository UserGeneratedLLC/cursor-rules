# Common Mistakes

## Requiring from non-server code

Analytics is server-only. Requiring it from ReplicatedStorage shared modules or client code will error.

```luau
-- WRONG: shared module in ReplicatedStorage could be required by client
-- ReplicatedStorage/Shared/SomeModule.luau
local Analytics = require(ServerScriptService.UserGenerated.Analytics)

-- CORRECT: only require from ServerScriptService or ServerStorage modules
-- ServerScriptService/Server/Services/SomeService.luau
local ServerScriptService = game:GetService("ServerScriptService")
local Analytics = require(ServerScriptService.UserGenerated.Analytics)
```

## Requiring server scripts instead of ModuleScripts

Only ModuleScripts (`.luau`, `init.luau`) can be required. Server scripts (`.server.luau`) and client scripts (`.client.luau`) cannot.

```luau
-- WRONG: .server.luau cannot be required
local GameHandler = require(ServerScriptService.ServerMain.init) -- init.server.luau = ERROR

-- CORRECT: require the ModuleScript
local GameHandler = require(ServerScriptService.ServerMain.GameHandler) -- init.luau = OK
```

## Creating new tracking instead of using existing state

Always search the codebase first. If data is already tracked somewhere, use it.

```luau
-- WRONG: creating redundant state
local nightIndex = 0
local function setNight()
    nightIndex += 1
end

-- CORRECT: use what the game already tracks
results["Shared.TimeString"] = GetValue(runtime:FindFirstChild("TimeString"), "")
```

## Putting state data in events instead of attribute providers

If data would be useful context for any event, it's state and belongs in the attribute provider.

```luau
-- WRONG: health is state, not event-specific
Analytics:LogPlayerEvent(player, "PlayerTookDamage", {
    DamageAmount = damage,
    HealthAfter = humanoid.Health,
    DamageSource = source,
})

-- CORRECT: health goes in BuildGeneralAttributesAsync, event only has event-specific data
-- In attribute provider:
results["Shared.Health"] = humanoid.Health

-- In event:
Analytics:LogPlayerEvent(player, "PlayerTookDamage", {
    DamageAmount = damage,
    DamageSource = source,
})
```

## Ignoring lobby vs game server

Game-specific state (round duration, wave number, etc.) may not exist on the lobby server. Always guard.

```luau
-- WRONG: errors on lobby server where RoundStartTime doesn't exist
results["Shared.RoundDuration"] = os.clock() - GameHandler.RoundStartTime

-- CORRECT: check existence first
if GameHandler.RoundStartTime then
    results["Shared.RoundDuration"] = math.round(os.clock() - GameHandler.RoundStartTime)
end
```

## Over-using task.spawn

Only use `task.spawn` when multiple steps could error. Simple analytics calls don't need it.

```luau
-- WRONG: unnecessary wrapper
task.spawn(function()
    Analytics:IncrementPlayerAttribute(player, "TotalDigEvents", 1)
end)

-- CORRECT: call directly
Analytics:IncrementPlayerAttribute(player, "TotalDigEvents", 1)
```

`task.spawn` IS appropriate when you need to compute multiple values that could fail:

```luau
-- CORRECT: complex logic that could error at multiple points
task.spawn(function()
    local itemInstance = Assets.DigItems:FindFirstChild(itemObject.itemName)
    local itemRarity = itemInstance and itemInstance:GetAttribute("Rarity") or "Unknown"
    local pickupDepth = 0
    if player.Character and player.Character:GetAttribute("InDigZone") then
        local hrp = player.Character:FindFirstChild("HumanoidRootPart")
        if hrp and digZone.DIG_ZONE_FOLDER then
            local terrainBox = digZone.DIG_ZONE_FOLDER.TerrainBoundingBox
            local startPos = (terrainBox.CFrame * CFrame.new(0, terrainBox.Size.Y / 2, 0)).Position
            local progressDirection = -terrainBox.CFrame.UpVector
            pickupDepth = math.max(0, utils.getDirectedDistance(startPos, hrp.Position, progressDirection))
        end
    end
    Analytics:LogPlayerEvent(player, "PlayerItemPickup", {
        ItemName = itemObject.itemName,
        ItemRarity = itemRarity,
        PickupDepth = pickupDepth,
    })
end)
```

## Tracking unique players incorrectly

Use a set keyed by UserId, not a count of current players.

```luau
-- WRONG: counts current players, not unique players who joined
handler.PlayersStarted = #game.Players:GetPlayers()

-- CORRECT: track unique players via set
local UniquePlayerIds: {[number]: true} = {}
local UniquePlayerCount = 0

function handler.playerAdded(player: Player)
    if not UniquePlayerIds[player.UserId] then
        UniquePlayerIds[player.UserId] = true
        UniquePlayerCount += 1
        handler.PlayersStarted = UniquePlayerCount
    end
end
```

## Unpacking structured data into flat event keys

Events accept nested tables natively. Pass item data, trade payloads, reward structs directly.

```luau
-- WRONG: manually unpacking into flat keys
Analytics:LogPlayerEvent(player, "PlayerItemPickup", {
    ItemName = itemData.Name,
    ItemRarity = itemData.Rarity,
    ItemLevel = itemData.Level,
})

-- CORRECT: pass the struct directly
Analytics:LogPlayerEvent(player, "PlayerItemPickup", {
    Item = itemData,
})
```

This also applies to trade events, reward structs, inventory snapshots, etc. The analytics backend handles nested tables.

## Using unverified attributes

Every attribute you reference must be verified by searching the codebase first. If you can't find where it's set, don't use it.

Verification steps:
1. Search for the attribute name across `src/`
2. Confirm it's set/updated somewhere (look for `SetAttribute`, `.Value =`, or assignment)
3. Confirm the type (ValueBase needs `.Value`, Instance Attribute needs `:GetAttribute()`)
4. Confirm availability (lobby server vs game server)
