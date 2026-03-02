---
name: install-analytics
description: Implement server-side analytics tracking using the Analytics module. Use when the user asks to add analytics, track player events, add event logging, implement telemetry, or instrument code with Analytics calls.
---

# Install Analytics

**PLAN MODE REQUIRED.** Always use plan mode when performing an analytics install. Before making any changes, investigate the game's saving system, present a full adaptation plan, and wait for user confirmation.

Analytics is **server-only**. Require from `ServerScriptService.UserGenerated.Analytics`.

## Workflow

1. **Investigate the saving module** -- Find the game's data module, read it, identify the saving system category (A-D). Note the data template fields, profile type, events, lookup pattern, purchase receipt location. The data template is the primary source for what goes into `BuildGeneralAttributesAsync`. This is the most time-consuming step. See [adaptation-guide.md](adaptation-guide.md).
2. **Plan the adaptation** -- Present a plan covering: saving module modifications, Profiles.luau hookup, Setup.server.luau structure (especially `BuildGeneralAttributesAsync` fields from the data template), ABTestConditions conditions, Reconciler approach. Wait for confirmation.
3. **Adapt Profiles.luau** -- Hook into the saving module per [adaptation-guide.md](adaptation-guide.md) Step 3.
4. **Adapt Setup.server.luau** -- Wire events, build attributes from data template, set up Reconciler per [adaptation-guide.md](adaptation-guide.md) Steps 4-6.
5. **Adapt ABTestConditions.server.luau** -- Wire monetization conditions based on what's available per [adaptation-guide.md](adaptation-guide.md) Step 5.
6. **Add game-specific analytics** -- `LogPlayerEvent` calls, counters, etc. per the principles and API below.
7. **Review** -- Check all changes against the checklist below.

## Principles

| Principle | Detail |
|-----------|--------|
| Minimal changes | Do NOT refactor existing code. Only add analytics calls. |
| Use what exists | Search the codebase before creating new tracking. Reuse existing ValueBase objects, attributes, and state. |
| Log after success | Place analytics calls after the action succeeds, not before. |
| No obvious comments | Analytics calls are self-documenting. Don't add `-- Analytics: EventName`. |
| task.spawn sparingly | Only wrap in `task.spawn` when complex multi-step logic could error. Never for simple `LogPlayerEvent` or `IncrementPlayerAttribute` calls. |
| Pass deep data directly | Events accept nested tables natively. Pass item data, trade payloads, reward structs directly -- do NOT unpack into flat keys. |

## API Quick Reference

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local Analytics = require(ServerScriptService.UserGenerated.Analytics)

-- Log event (returns true if session exists, sampling is async)
Analytics:LogPlayerEvent(player, "PlayerEventName", {
    ItemName = name,
    Cost = cost,
})

-- Persistent counter (survives sessions, auto-attached to future events)
Analytics:IncrementPlayerAttribute(player, "TotalItemsSold", 1)

-- Read / write attributes
Analytics:GetPlayerAttribute(player, "AttributeName")
Analytics:SetPlayerAttribute(player, "AttributeName", value)
Analytics:GetPlayerAttributes(player)
Analytics:GetPlayerAttributeDeltas(player)

-- Purchase receipt logging
Analytics:LogPurchaseReceipt(receiptInfo, giftUserId?, tag?)

-- New player check (yields)
Analytics:IsNewPlayerAsync(player)

-- Session access
local session = Analytics:Session(player) -- get or create, returns Session.Type?
```

For the full API, common events, and common counters, see [api-reference.md](api-reference.md).

## Event Naming

Prefix ALL player events with `Player`: `PlayerDeath`, `PlayerItemSold`, `PlayerGearPurchase`, `PlayerRebirth`, etc.

## Event Data

Events accept nested tables directly. Pass structured data as-is:

```luau
-- CORRECT: pass the item struct directly
Analytics:LogPlayerEvent(player, "PlayerItemPickup", {
    Item = itemData,
})

-- WRONG: unnecessary unpacking
Analytics:LogPlayerEvent(player, "PlayerItemPickup", {
    ItemName = itemData.Name,
    ItemRarity = itemData.Rarity,
    ItemLevel = itemData.Level,
})
```

This applies to item data, trade payloads, reward structs, inventory snapshots, etc.

## State vs Event-Specific Data

| Category | Where it goes | Examples |
|----------|---------------|----------|
| **State** (useful for ANY event) | Attribute provider | Health, currency, game progress, persistent counters |
| **Event-specific** (unique to THIS occurrence) | `LogPlayerEvent` data table | Item data struct, cost paid, damage dealt, actual amount healed |

**Rule:** If the data would be useful context for any event, it's state data and belongs in the attribute provider, not the event.

### Attribute Provider

State attributes go in `BuildGeneralAttributesAsync` or `RegisterPlayerEventAttributeProvider`.

`BuildGeneralAttributesAsync` signature: `(session: Session.Type, profile: Profiles.Profile?, sendInventory: boolean) -> {[string]: any}`

```luau
-- Safe ValueBase accessor
local function GetValue(instance: Instance?, defaultValue: any): any
    if instance and instance:IsA("ValueBase") then
        return (instance :: any).Value
    end
    return defaultValue
end

-- BuildGeneralAttributesAsync (state attached to ALL events)
results["Shared.Health"] = humanoid.Health
results["Shared.DayNumber"] = GetValue(runtime:FindFirstChild("DayInt"), 0)

-- RegisterPlayerEventAttributeProvider (session counters)
results["Shared.TotalItemsSold"] = session:GetAttribute("TotalItemsSold")
```

## Verification (CRITICAL)

Before using ANY attribute or value, search the codebase and confirm:

1. **Exists?** - Search for the name
2. **Set/updated?** - Find where it's assigned
3. **Correct type?** - ValueBase (access `.Value`) vs Instance Attribute (access `:GetAttribute()`)
4. **Always available?** - Present on lobby server AND game server, or only one?

### Require Safety

Analytics is server-only. Only require from server-side code:

| Location | Safe? |
|----------|-------|
| `ServerScriptService/` modules | Yes |
| `ServerStorage/` modules | Yes |
| `ReplicatedStorage/` shared modules | **NO** - client could require it |
| `.client.luau` / `StarterPlayer/` | **NO** |

### Lobby vs Game Server

Game-specific state may not exist on the lobby server. Always guard:

```luau
if GameHandler.RoundStartTime then
    results["Shared.RoundDuration"] = math.round(os.clock() - GameHandler.RoundStartTime)
end
```

## Implementation Checklist

**Before:**
- [ ] Search for existing tracking - don't duplicate
- [ ] Verify every attribute/value exists in codebase
- [ ] Check if lobby detection is needed
- [ ] Confirm require location is server-safe

**After:**
- [ ] Review all git changes - minimal additions only
- [ ] State data in provider, event data in `LogPlayerEvent`
- [ ] Deep data passed directly, not unpacked into flat keys
- [ ] Zero new linter errors

### Red Flags

Stop and reconsider if you see:
- More than 100 lines added for a single attribute
- Any refactoring of existing code
- New tracking modules or systems created
- `task.spawn` around simple calls
- Attributes that weren't verified by searching
- Structured data manually unpacked into flat event keys

For common mistakes and anti-patterns, see [mistakes.md](mistakes.md).
For saving system adaptation patterns, see [adaptation-guide.md](adaptation-guide.md).
