---
name: fflag
description: Create and set up FastFlags (feature flags / remote config) in the codebase. Use when the user says /fflag, asks to add a fastflag, feature flag, fflag, replicated flag, private flag, or remote config value.
---

# FastFlag Setup

Create new FastFlags with correct placement, key naming, assertions, and consumption wiring.

## Workflow

### Step 1: Gather Requirements

Ask the user (use AskQuestion when available):

1. **What is the flag for?** (feature toggle, numeric tuning, config map, etc.)
2. **Does the client need it?** Determines Replicated vs Private.
3. **Default value?** What the flag returns before the DataStore loads or if no value is set.

If the user already provided this context (e.g., as part of a feature request), infer the answers and skip asking.

### Step 2: Determine Type and Placement

```
Does the client need this value?
├─ YES → FastFlags.Replicated
│   ├─ New system / multiple flags? → New file in Shared/Flags/<SystemName>Flags.luau
│   ├─ Fits an existing flags file? → Add to that file
│   └─ Tied to existing config module? → Add to that config module
│
└─ NO → FastFlags.Private (server-only)
    ├─ Used by one service/module? → Define inline in that module
    └─ Used by multiple server modules? → Define in the most related service, require from there
```

**Critical:** Each key can only be registered ONCE per runtime. Never define the same flag in two places. Shared modules under ReplicatedStorage are safe because `require` caches results.

### Step 3: Choose the Key Path

Keys use dot-separated hierarchy. Match existing patterns:

| Prefix | Use for | Examples |
|--------|---------|----------|
| `Game.<System>.<Flag>` | Gameplay features | `Game.LimitedShop.Enabled2`, `Game.Geyser.PadNerfedSpeed` |
| `Trading.<Flag>` | Trading system | `Trading.SendTradeRequestsDisabled` |
| `Event.<Event>.<Flag>` | Event-scoped config | `Event.FireAndIce.MutationWeight` |
| `Tower.<Flag>` | Tower system | `Tower.CooldownDuration`, `Tower.RitualEnabled` |
| `Announcements.<Feature>.<Flag>` | Announcement toggles | `Announcements.DivineObtain.Enabled` |
| `UserGenerated.<System>.<Flag>` | Platform/infra | `UserGenerated.Analytics.PlayerEventChances2` |

Rules:
- No overlapping hierarchy (can't have both `Game.Saves` as a value AND `Game.Saves.Enabled` as nested)
- Use PascalCase for each segment
- Be specific -- `Game.Geyser.PassiveSpawnDelay` not `Game.SpawnDelay`

### Step 4: Select the Assertion

Pick from this table based on the value type:

| Value type | Assertion | Notes |
|------------|-----------|-------|
| On/off toggle | `Asserts.Boolean` | |
| Text / ID | `Asserts.String` | |
| Any positive number | `Asserts.FinitePositive` | Rates, multipliers, durations |
| Non-negative number | `Asserts.FiniteNonNegative` | Weights, chances (allows 0) |
| Percentage 0-1 | `Asserts.Range(0, 1)` | |
| Percentage 0-100 | `Asserts.Range(0, 100)` | |
| Positive integer | `Asserts.IntegerPositive` | Counts, levels, IDs |
| Non-negative integer | `Asserts.IntegerNonNegative` | |
| Integer in range | `Asserts.IntegerRange(a, b)` | |
| Enum-like string | `Asserts.Set({"a", "b", "c"})` | |
| Optional value | `Asserts.Optional(inner)` | Value or nil |
| String-keyed map | `Asserts.Map(Asserts.String, valueAssert)` | Config dictionaries |
| Array | `Asserts.Array(valueAssert)` | Lists |
| Structured object | `Asserts.Table({ key = assert })` | Complex configs |
| Multiple valid types | `Asserts.AnyOf(a, b, ...)` | |

For complex table values, define the assert as a local variable above the flag (see MysteryMerchantDynamicStockFlags for a full example).

### Step 5: Write the Flag

Use the appropriate template below.

---

## Templates

### Shared Replicated Flags File

Create at `src/ReplicatedStorage/Shared/Flags/<SystemName>Flags.luau`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FastFlags = require(ReplicatedStorage.UserGenerated.FastFlags)
local Asserts = require(ReplicatedStorage.UserGenerated.Lang.Asserts)

local FeatureEnabled = FastFlags.Replicated(
	"Game.System.FeatureEnabled",
	Asserts.Boolean,
	true
)

local TuningValue = FastFlags.Replicated(
	"Game.System.TuningValue",
	Asserts.FinitePositive,
	5.0
)

return table.freeze({
	FeatureEnabled = FeatureEnabled,
	TuningValue = TuningValue,
})
```

### Inline Private Flags (in a service)

Place under a `-- FFlags` or `-- Feature Flags` section comment, before Constants:

```luau
-- FFlags
local FeatureDisabled = FastFlags.Private("System.FeatureDisabled", Asserts.Boolean, false)
```

Requires at top of the service:

```luau
local FastFlags = require(ReplicatedStorage.UserGenerated.FastFlags)
local Asserts = require(ReplicatedStorage.UserGenerated.Lang.Asserts)
```

### Adding to an Existing Flags File

1. Add the local variable with `FastFlags.Replicated(...)` or `FastFlags.Private(...)`
2. Add it to the return table

---

## Consumption Patterns

### Get (non-yielding, use in gameplay)

```luau
if MyFlags.FeatureEnabled:Get() then
	-- feature is on
end

local rate = MyFlags.TuningValue:Get()
```

### GetAsync (yielding, use at startup)

```luau
local value = MyFlags.FeatureEnabled:GetAsync()
```

Only use when you MUST have the real DataStore value before continuing.

### Changed (react to live updates)

```luau
MyFlags.TuningValue.Changed:Connect(function(current, previous)
	updateSomething(current)
end)
```

### Loaded (wait for initial load)

```luau
if not FastFlags.IsLoaded() then
	FastFlags.Loaded:Wait()
end
```

Or per-flag:

```luau
MyFlags.FeatureEnabled.Loaded:Wait()
```

### Typical controller/service pattern

```luau
local MyFlags = require(ReplicatedStorage.Shared.Flags.MyFlags)

function MyService.init()
	-- Use :Get() in gameplay, react with .Changed
	if MyFlags.FeatureEnabled:Get() then
		setupFeature()
	end

	MyFlags.FeatureEnabled.Changed:Connect(function(current)
		if current then
			setupFeature()
		else
			teardownFeature()
		end
	end)
end
```

---

## Checklist

Before finishing, verify:

- [ ] Key path follows existing naming conventions (check Step 3)
- [ ] Assertion matches the value type (check Step 4)
- [ ] Default value passes the assertion
- [ ] Flag is only registered once per runtime (no duplicate definitions)
- [ ] Replicated flags are in a shared module under ReplicatedStorage
- [ ] Private flags used by multiple modules live in one place, required by others
- [ ] `FastFlags` and `Asserts` imports are present in the file
- [ ] Flag is added to the frozen return table (for shared flag files)
- [ ] Consumption code uses `:Get()` (not `:GetAsync()`) in gameplay paths

## API Reference

### Setup

Works on both client and server:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FastFlags = require(ReplicatedStorage.UserGenerated.FastFlags)
local Asserts = require(ReplicatedStorage.UserGenerated.Lang.Asserts)
```

Flags must be registered on the server first. The server sets up replication, then clients can access replicated flags.

### Creating Flags

| Constructor | Visibility | Description |
|-------------|------------|-------------|
| `FastFlags.Private(key, assertion, default)` | Server-only | Cannot be seen or accessed on the client |
| `FastFlags.Replicated(key, assertion, default)` | Client + Server | Replicates to all clients. Server must register first. |

Both return a `Value` object (see Value API below).

### Single Instantiation Rule

Each key can only be registered **once per runtime**. Calling `Private` or `Replicated` with the same key twice on the same side (client or server) throws `ConflictingKeys` -- a hard, unrecoverable error.

Client and server are separate runtimes, so a `Replicated` flag is registered once on the server and once on the client (expected). But within the same runtime, a key must appear exactly once.

**Placement guidance:**

- **Replicated flags:** Place in a shared module under `ReplicatedStorage`. Both sides require the same module; `require` caching ensures single registration.
- **Private flags (one module):** Define directly in that module.
- **Private flags (multiple modules):** Define in a single location (the most related service). Other modules require it from there. Avoid cyclic dependencies -- extract into a dedicated flags module if needed.

### System State

| API | Description |
|-----|-------------|
| `FastFlags.IsLoaded()` | Returns `true` if initial values have loaded from the DataStore |
| `FastFlags.Loaded` | Event. Fires when the system loads. Use `:Wait()` or `:Connect()`. |

### Validation

| API | Description |
|-----|-------------|
| `FastFlags.IsA(value)` | Returns `true` if the value is a `FastFlags.Value` |
| `FastFlags.Assert(value)` | Asserts the value is a `FastFlags.Value`, returns it or errors |

### Value API

Once you have a flag value from `Private` or `Replicated`:

| Method / Property | Yields? | Description |
|-------------------|---------|-------------|
| `value:Get()` | No | Returns current value, or default if not loaded yet |
| `value:GetAsync()` | Yes | Yields until loaded from DataStore, then returns |
| `value:IsLoaded()` | No | Returns `true` if this flag has loaded |
| `value.Changed` | -- | Event `(current, previous)`. Fires on live config changes. |
| `value.Loaded` | -- | Event. Fires once when load attempt completes (even if key doesn't exist in DataStore). |
| `value.Key` | -- | The key string used at registration |
| `value.DefaultValue` | -- | The default value provided at registration |

**When to use which:**

- `:Get()` -- gameplay loops, event handlers, UI updates, anywhere yielding is unsafe
- `:GetAsync()` -- server startup, join flows, anywhere you need the real stored value before proceeding

### Default Values

The default is used when:

- The flag hasn't loaded from the DataStore yet
- The stored value fails assertion validation (falls back to default, logs a warning)
- No value exists in the DataStore

Default values can be any storable Luau type: string, number, boolean, or table. Tables are deep-copied and frozen.

### Key Paths and JSON Structure

Keys use dot notation that maps to nested JSON in the backend:

```luau
FastFlags.Private("UserGenerated.Saves.AutoSavePeriod", Asserts.FinitePositive, 600)
```

Maps to:

```json
{
  "UserGenerated": {
    "Saves": {
      "AutoSavePeriod": 600
    }
  }
}
```

**Supported value types:**

| Type | Lua | JSON |
|------|-----|------|
| Boolean | `true`/`false` | `true`/`false` |
| Number | `123`, `1.5` | `123`, `1.5` |
| String | `"text"` | `"text"` |
| Null | `nil` | `null` |
| Array | `{1, 2, 3}` | `[1, 2, 3]` |
| Object | `{a=1, b=2}` | `{"a": 1, "b": 2}` |

**Key conflicts:** Keys with hierarchical overlap error. You cannot have both a value and nested object at the same path (e.g., `UserGenerated.Saves` as a value AND `UserGenerated.Saves.Enabled` as nested).

### Editing Flags

Edit flags at **https://fflag.ug.xyz/**

| Method | Delivery | Use when |
|--------|----------|----------|
| **Immediate Push** (MessagingService) | Broadcast to all running servers within seconds | Urgent changes |
| **Slow Push** (DataStore) | Servers poll every ~15 minutes | Non-urgent, or when MessagingService quota is a concern |

### Assertions

For the full Asserts API, read [.cursor/rules/asserts.mdc](.cursor/rules/asserts.mdc).
