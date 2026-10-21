# Data schema

Two kinds of data live in this project, and they must never mix:

- **Content** (`src/shared/Config`) — static, immutable, authored as data. Ships inside the
  place file.
- **Profile** (`profile` table, owned by `DataService`) — per player, versioned, saved by
  the in-house provider.

## Profile (version 1)

Defined by `Core/Profile.template` and typed as `Core/Types.Profile`.

```lua
Profile = {
  Version = 1,
  Currency = { Cash, Reputation, PrestigePoints, ResearchPoints },   -- integers
  Stats    = { LifetimeEarned, PlaySeconds, NetWorthPeak },
  Time     = { FirstJoin, LastSaved, LastSeen },                     -- os.time()
  Parcels  = { [parcelId] = true },
  Buildings = { [uid] = BuildingState },
  Districts = { [districtId] = { unlocked, devRating } },
  Research  = { done = {...}, active = {...} },
  Contracts = { active = {...}, done = {...}, seed },
  Objectives = {
    chain = "starter",
    index = 1,
    progress = { [metric] = number },
    completed = { [objectiveId] = true },
    pinned = objectiveId?,
  },
  Collections = { Vehicles = {}, Houses = {}, Furniture = {}, Cosmetics = {} },
  Achievements = { [id] = true },
  Legacy = { [id] = true },
  Settings = { quality = "auto"? , sfx = bool?, music = bool? },
  Purchases = { [sku] = true },
}

BuildingState = {
  def = "convenience_store",   -- Content.buildingById key
  parcel = "starter_01",
  level = 1,                   -- 1..BuildingDef.maxLevel
  phase = 2,                   -- last completed construction phase
  upg = { ["convenience_store.business.marketing"] = 3 },
  mastery = { xp, lvl, windowStart, windowXp },
  staff = { Basic = 1 },
  manager = "Standard"?,
  constructing = { phase, startedAt, seconds }?,   -- os.time() based
  pending = 0,                 -- uncollected cash, integer
  lastAccrual = 0,             -- os.time()
}
```

### Rules

- **Integers only** for currency, prices, pending income and XP. `Core/Money` owns the
  rounding; `EconomyService` rejects anything else.
- **`Version` gates migrations.** `Core/Migrations` upgrades older profiles in order;
  `Core/Profile.reconcile` fills new fields with template defaults so old saves never
  crash on a missing key.
- **`constructing.startedAt` is wall-clock.** Progress is recomputed from timestamps, so
  rejoin/offline time is handled by arithmetic, not by a running timer.
- **Nothing references world instances.** uids are `b<n>` strings (`Core/Uid`), so a
  profile survives the server rebuilding every model.
- **Never store derived values** (income per minute, net worth, completion %). They are
  computed on read so a balance change applies to existing saves.

### Size budget

`tools/size_budget.luau` builds the largest profile the current content allows: **~28 KB**
(budget 1 MB, hard fail 3 MB). A typical first-session profile is **~1 KB**. The profile is
stored as a single DataStore value; no chunking is needed at this content volume.

## Content

| File | Provides |
|---|---|
| `Balance.luau` | every tunable: rates, mastery curve, upgrade pricing, staff, construction, land, rate limits, UI |
| `Flags.luau` | `DebugTools`, `MockDataStore`, `AmbientLife`, … (all off-by-default where they matter) |
| `Districts.luau` | eight districts; Starter is playable, the rest are reserved origins |
| `Parcels.luau` | 4×4 Starter grid, prices, sizes, net-worth gates |
| `Archetypes.luau` | upgrade-line templates per archetype and category (this is what "hundreds of upgrades" comes from) |
| `Buildings.luau` | nine Starter buildings, phases, income anchors |
| `Upgrades.luau` | **generated** from Archetypes × Buildings at require time; ids are deterministic |
| `Staff.luau` | Basic / Skilled / Expert / Executive grades |
| `Objectives.luau` | the first-15-minutes chain, expressed as generic goals |
| `Strings.luau` | error codes → player text, toast copy, "coming later" copy |

### Generated upgrade ids

`<buildingId>.<category>.<slug>` — e.g. `convenience_store.equipment.cashiers`.

Generation is pure and deterministic, so an id is a stable save key. Changing an id is a
save-key change: add a migration in `Core/Migrations`, never silently rename.

Every generated line carries: `category`, `name`, `description`, `maxLevel`, `baseCost`,
`growth`, `effect = { stat, op, perLevel }`, `tier`, `buildingId`. Prices are anchored to
`building.upgradeCostBase × Balance.Upgrades.categoryCostFactor[category]` and scaled at
runtime by `BuildingMath.priceScale` (income-relative), so no line can drift out of band
when the property grows.

### Invariants enforced in CI

`tools/content_validate.luau` checks: unique ids, all references resolve, no requirement
cycles, every building reachable from a new profile, all costs integers under 2^53/16,
and the profile size budget. `tools/wiring_check.mjs` additionally checks that every
`Content.<path>` used in code exists in the data.
