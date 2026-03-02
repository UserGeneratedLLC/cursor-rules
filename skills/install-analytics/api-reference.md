# Analytics API Reference

Server-only module at `ServerScriptService.UserGenerated.Analytics`.

```luau
local ServerScriptService = game:GetService("ServerScriptService")
local Analytics = require(ServerScriptService.UserGenerated.Analytics)
```

## Logging Events

```luau
Analytics:LogPlayerEvent(player, "EventName", {
    Attribute1 = value1,
    Attribute2 = value2,
})
```

Returns `true` if the session exists (event is queued); sampling happens asynchronously after return. Only include event-specific data -- state data is attached automatically via attribute providers. Attributes accept nested tables natively -- pass structured data directly instead of unpacking into flat keys.

```luau
Analytics:RegisterPlayerEventAttributeProvider(function(player, eventName)
    return { ["Shared.Health"] = humanoid.Health }
end)
```

Registers a callback that provides state attributes attached to every event for a player.

## Player Attributes

```luau
Analytics:GetPlayerAttribute(player, "AttributeName")   -- single value or nil
Analytics:SetPlayerAttribute(player, "AttributeName", value) -- returns boolean
Analytics:IncrementPlayerAttribute(player, "CounterName", amount) -- returns boolean
Analytics:GetPlayerAttributes(player)                    -- all attributes as table, or nil
Analytics:GetPlayerAttributeDeltas(player)               -- attribute deltas as table, or nil
```

`IncrementPlayerAttribute` persists across sessions and is automatically included in all future events. `SetPlayerAttribute` sets an attribute directly (returns `true` on success).

## Purchase Receipts

```luau
Analytics:LogPurchaseReceipt(receiptInfo, giftUserId?, tag?)
```

Logs a purchase receipt. `receiptInfo` is `MarketplaceServiceHelper.ReceiptInfo`. Optional `giftUserId` for gift purchases, optional `tag` string.

## New Player Detection

```luau
Analytics:IsNewPlayerAsync(player) -- yields, returns boolean
```

Yields until player save data is available. Returns `true` if the player's save is younger than the configured threshold.

## Gamepass Registration

```luau
Analytics:AddKnownGamePass(id)
```

Registers a gamepass ID for tracking in sessions.

## Session Access

```luau
local session = Analytics:Session(player) -- get or create, returns Session.Type?
```

Returns the existing session or creates one. Returns `nil` if the player has already had a session (prevents duplicates).

## Events

| Event | Fires when | Payload |
|-------|-----------|---------|
| `PurchaseReceiptLogged` | A purchase receipt is logged | `(ReceiptInfo, giftUserId?, tag?)` |
| `SessionCreated` | A new session is created | `(Session.Type)` |
| `SessionDestroying` | A session is being destroyed | `(Session.Type)` |

---

## Session API (`Session.Type`)

Sessions track per-player analytics state for a single visit.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `Player` | `Player` | The player this session belongs to |
| `CreatedAt` | `number` | Server timestamp when session was created |
| `SessionId` | `string` | Unique session identifier |
| `Destroying` | `Bindable.Event<>` | Fires when session is being destroyed |

### Methods

```luau
session:GetAttribute(key)           -- returns any?
session:SetAttribute(key, val)      -- sets attribute
session:IncrementAttribute(key, n)  -- increments numeric attribute
session:GetAttributes()             -- returns all attributes as table
session:GetAttributeDeltas()        -- returns {[string]: number} of changed numeric attributes
session:IsDestroyed()               -- returns boolean
session:Destroy(exitReason)         -- destroys session, returns boolean
session:GetExitReason()             -- returns string?
session:GetEndedAt()                -- returns number?
session:GetValidCFrameAsync(timeout) -- yields, returns CFrame?
session:HasSave(async?)             -- returns boolean
```

---

## Common Events

| Event | Description |
|-------|-------------|
| `PlayerDeath` | Player died |
| `PlayerBrainrotCollected` | Picked up a brainrot |
| `PlayerBrainrotSold` | Sold a brainrot |
| `PlayerSellAll` | Sold all brainrots at once |
| `PlayerBrainrotUpgrade` | Upgraded a brainrot |
| `PlayerSpeedUpgrade` | Purchased speed upgrade |
| `PlayerCarryUpgrade` | Purchased carry upgrade |
| `PlayerGearPurchase` | Purchased gear |
| `PlayerSlotUnlocked` | Unlocked a new slot |
| `PlayerMoneyCollected` | Collected money from slot |
| `PlayerWheelSpinReward` | Received wheel reward |
| `PlayerLuckyBlockOpened` | Opened a lucky block |
| `PlayerTradeCompleted` | Completed a trade |
| `PlayerGiftCompleted` | Completed a gift |
| `PlayerRebirth` | Performed rebirth |
| `PlayerLimitedShopPurchase` | Purchased from limited shop |
| `PlayerSpawnMachineCraft` | Crafted via spawn machine |
| `PlayerTowerReward` | Received tower reward |
| `PlayerObbyComplete` | Completed an obby |
| `PlayerBaseSkinUnlocked` | Unlocked a base skin |
| `PlayerInviteSuccess` | Successfully invited a player |
| `PlayerAntiCheat` | Anti-cheat triggered |
| `PlayerATMPayout` | Received ATM payout |
| `PlayerMiniEventTriggered` | Mini event triggered |

## Common Counters

| Counter | Description |
|---------|-------------|
| `TotalDeaths` | Times player has died |
| `TotalBrainrotsCollected` | Brainrots picked up |
| `TotalBrainrotsSold` | Brainrots sold |
| `TotalMoneyCollected` | Total money earned |
| `TotalUpgrades` | Upgrades purchased |
| `TotalWheelSpins` | Wheel spins used |
| `TotalLuckyBlocksOpened` | Lucky blocks opened |
| `TotalCoinsCollected` | Special coins collected |
| `TotalLuckyBlocksCollected` | Lucky blocks collected |
| `TotalTowerBrainrotsSubmitted` | Brainrots submitted to tower |
| `TotalTowerCompletions` | Tower completions |
| `TotalTowerTrialCompletions` | Tower trial completions |

---

## Examples

### Basic Event

```luau
Analytics:LogPlayerEvent(player, "PlayerDeath", {
    Cause = "Tsunami",
})
```

### Event with Counter

```luau
Analytics:IncrementPlayerAttribute(player, "TotalBrainrotsSold", 1)
Analytics:LogPlayerEvent(player, "PlayerBrainrotSold", {
    BrainrotName = "Skibidi",
    Mutation = "Shiny",
    SellPrice = 1500,
})
```

### Purchase Event

```luau
Analytics:LogPlayerEvent(player, "PlayerGearPurchase", {
    GearName = "Speed Boots",
    GearType = "Speed",
    Cost = 5000,
})
```

### Upgrade Event

```luau
Analytics:IncrementPlayerAttribute(player, "TotalUpgrades", 1)
Analytics:LogPlayerEvent(player, "PlayerSpeedUpgrade", {
    NewSpeed = 25,
    SpeedGained = 5,
    Cost = 10000,
})
```

### Collection Event

```luau
Analytics:IncrementPlayerAttribute(player, "TotalMoneyCollected", amount)
Analytics:LogPlayerEvent(player, "PlayerMoneyCollected", {
    SlotName = "Slot3",
    Amount = amount,
})
```

### Trade Event (deep data)

```luau
Analytics:LogPlayerEvent(player, "PlayerTradeCompleted", {
    Id = tradeId,
    Party = 1,
    OtherUser = otherPlayer.UserId,
    Given = givenItemData,
    Received = receivedItemData,
})
```

### Item Pickup (deep data)

```luau
Analytics:LogPlayerEvent(player, "PlayerItemPickup", {
    Item = itemData, -- pass the whole struct, don't unpack
})
```
