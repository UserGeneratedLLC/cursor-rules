---
name: add-event
description: Add a new analytics event to the codebase. Use when the user asks to create an analytics event, add event tracking, log a player action, add a new LogPlayerEvent call, or instrument a feature with analytics.
---

# Add Event

Add a new `Analytics:LogPlayerEvent` call (and optionally a persistent counter) to a server-side module.

## Workflow

1. **Clarify** — Ask the user what action to track if not obvious. Determine:
   - What action triggers the event?
   - What data is unique to this occurrence?
   - Is there a running total that should be incremented?
2. **Locate** — Find the server-side code where the action succeeds
3. **Name** — Pick the event name (see Naming)
4. **Design attributes** — Decide what goes in the event table (see Attribute Design)
5. **Implement** — Add the analytics calls after the action succeeds
6. **Verify** — Confirm every value referenced actually exists at the call site

## Import

Add to the Imports section if not already present:

```luau
local Analytics = require(ServerScriptService.UserGenerated.Analytics)
```

## Naming

| Rule | Example |
|------|---------|
| Prefix player actions with `Player` | `PlayerBrainrotSold`, `PlayerGearPurchase`, `PlayerRebirth` |
| Use PascalCase | `PlayerSpawnMachineCraft` not `player_spawn_machine_craft` |
| Name describes the completed action | `PlayerTradeCompletedNEW` not `PlayerTradeStarted` |
| Non-player events skip the prefix | `CurrencyChanged`, `DivineObtained`, `WaveMachinePurchase` |
| Exploit/security events use descriptive names | `PlayerAntiCheat`, `ExploitAttempt:LuckyBlockSpoof` |

## Attribute Design

### What to include

Only data **unique to this specific event occurrence**. Ask: "Would this value be different each time this event fires?"

```luau
Analytics:LogPlayerEvent(player, "PlayerSpawnMachineCraft", {
    MachineType = cache.MachineType,
    Inputs = machineData,         -- deep table passed directly
    Output = result,              -- deep table passed directly
    OutputScale = result.scale,
    Cost = cost,
    AFKLuckBonus = afkLuckBonus,
    GotDoublePayout = gotDoublePayout,
})
```

### Deep tables are fine

Pass item data tables, input arrays, reward tables, etc. directly. Don't manually unpack every field — send the data structure as-is when it contains relevant context.

```luau
-- GOOD: Pass the item data directly
Analytics:LogPlayerEvent(player, "PlayerLimitedShopPurchase", {
    Item = data,
    CurrencySpent = price,
    StockAtPurchase = decreaseResult.newStock,
})

-- GOOD: Pass arrays of input data
Analytics:LogPlayerEvent(player, "PlayerSpawnMachineDivineInput", {
    DivineInputs = divineInputs,    -- array of {name, mutation, level}
    TotalInputs = #machineData,
    Output = result,
})

-- GOOD: Trade items as deep tables
Analytics:LogPlayerEvent(player, "PlayerTradeCompletedNEW", {
    Id = tradeGuid,
    OtherUser = player2.UserId,
    Given = givenPlayer1,           -- {[guid]: {Guid, Data, Rarity, SizeName}}
    Received = givenPlayer2,
    GivenTokens = player1Offer.tokens,
    ReceivedTokens = player2Offer.tokens,
})
```

### But don't send the world

Only include data relevant to understanding this event. Don't dump entire player profiles or large unrelated state.

```luau
-- BAD: Dumping entire profile
Analytics:LogPlayerEvent(player, "PlayerRebirth", {
    Profile = profile.Data,  -- way too much irrelevant data
})

-- GOOD: Just what matters for this rebirth
Analytics:LogPlayerEvent(player, "PlayerRebirth", {
    NewRebirthLevel = newLevel,
    Multiplier = multiplier,
    SpeedBeforeReset = speed,
})
```

### What NOT to include

The attribute provider automatically attaches all of these to every event — never duplicate them:

- Money, rebirth, speed, jump level, max carry
- Slot count, gear count, brainrot counts
- Galaxy/Magma coin balances
- VIP status, friend boost
- Active events, AFK luck
- Session counters (TotalBrainrotsCollected, TotalDeaths, etc.)
- Session metadata (job_id, place_id, user_id, abtests, etc.)

### Common attribute patterns

| Pattern | Example |
|---------|---------|
| Item identification | `BrainrotName`, `Mutation`, `Level`, `Scale`, `Guid` |
| Cost/economy | `Cost`, `CurrencySpent`, `OldBalance`, `NewBalance`, `Delta` |
| Source tracking | `Source = "SpawnMachine"`, `Source = "TradingBooth"` |
| Other player | `OtherUser = otherPlayer.UserId` |
| Reward details | `RewardType`, `RewardName`, item data table |
| Boolean flags | `GotDoublePayout`, `IsFirstPlace`, `IsForced` |
| Size data | `OutputScale`, `SizeName` (derived from scale) |

## Counters

Pair a counter with the event when there's a meaningful running total. Increment **before** logging the event so the counter is current in the event's attribute snapshot.

```luau
Analytics:IncrementPlayerAttribute(player, "TotalLuckyBlocksOpened", 1)
Analytics:LogPlayerEvent(player, "PlayerLuckyBlockOpened", {
    BlockType = blockType,
    RewardType = rewardType,
    Reward = rewardData,
})
```

### Existing counters

Check these before creating new ones — reuse if one already fits:

| Counter | Description |
|---------|-------------|
| `TotalDeaths` | Times player has died |
| `TotalBrainrotsCollected` | Brainrots picked up |
| `TotalBrainrotsSold` | Brainrots sold |
| `TotalMoneyCollected` | Total money earned |
| `TotalUpgrades` | Upgrades purchased |
| `TotalWheelSpins` | Wheel spins used |
| `TotalLuckyBlocksOpened` | Lucky blocks opened |
| `TotalLuckyBlocksCollected` | Lucky blocks collected |
| `TotalCoinsCollected` | Special coins collected |
| `TotalTowerBrainrotsSubmitted` | Brainrots submitted to tower |
| `TotalTowerCompletions` | Tower completions |
| `TotalTowerTrialCompletions` | Tower trial completions |

New counter names should follow `Total<Thing><Action>` format (e.g., `TotalGearsEquipped`).

## Conditional Logging

Some events should only fire under specific conditions. Common patterns:

```luau
-- Filter out cycling sources (plot pickup/swap/return)
local cyclingSources = {
    PlotPickup = true,
    SpawnMachineReturn = true,
    PlotSwap = true,
}
if not cyclingSources[source] then
    Analytics:LogPlayerEvent(player, "DivineObtained", {
        BrainrotName = item.name,
        Source = source or "Unknown",
    })
end

-- Only log notable occurrences
if spawnLevel > 50 or source ~= "NaturalSpawn" then
    Analytics:LogPlayerEvent(player, "PlayerHighLevelPickup", { ... })
end

-- Anti-exploit honeypot
Analytics:LogPlayerEvent(player, "ExploitAttempt:LuckyBlockSpoof", {
    AttemptedBlockType = blockType,
})
```

## CurrencyChanged Pattern

When a feature adds/removes a currency, use the `CurrencyChanged` event:

```luau
Analytics:LogPlayerEvent(player, "CurrencyChanged", {
    CurrencyId = "TradeTokens",
    OldBalance = oldBalance,
    NewBalance = newBalance,
    Delta = amount,
    Source = "TradingBooth",
})
```

## Placement Rules

- Log **after** the action succeeds, never before
- Place at the same indentation level as surrounding code
- No `-- Analytics` comment needed — the call is self-documenting
- Don't wrap in `task.spawn` unless the analytics block does complex multi-step logic that could error
- If logging for both parties (trades, gifts), log for each player separately

## Checklist

Before submitting:

- [ ] Event name follows naming convention
- [ ] Attributes contain only event-specific data (no state data)
- [ ] Deep tables passed directly where appropriate (not aggressively unpacked)
- [ ] Every referenced value exists and is accessible at the call site
- [ ] Counter reuses existing one if applicable, or follows `Total<Thing><Action>` format
- [ ] Call is placed after the action succeeds
- [ ] Analytics require is in the Imports section
- [ ] No unnecessary `task.spawn` wrapping
- [ ] No duplicate tracking — searched for existing events first
