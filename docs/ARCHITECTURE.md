# Billionaire City Tycoon — Architecture (binding)

> Reproduced verbatim from the design brief (Appendix B). Additions that clarify implementation
> without changing a binding decision are recorded in [`DECISIONS.md`](./DECISIONS.md).

# Appendix B · Engineering Blueprint

## B0 · Glossary

- **Plot:** a player's whole city area. **Parcel:** one purchasable land cell. **District:** one of eight themed zones inside a plot.
- **BuildingDef:** static config. **Building:** a player's instance (uid) on a parcel.
- **Archetype:** a building family sharing an upgrade-tree template. **Line:** one multi-level upgrade series. **Level:** operating improvement. **Phase:** a construction stage. **Mastery:** long-term 1–100 progression per property.
- **Net worth:** cash + invested cost basis (land, buildings, upgrades, vehicles) + current value of investments.

## B1 · Repository layout

```
repo/
├─ AGENTS.md                    short: commands, layout, constraints, done-when
├─ README.md                    beginner setup: tools, rojo serve, Studio connect, rojo build, publish
├─ default.project.json         Rojo mapping (StreamingEnabled set here)
├─ rokit.toml  stylua.toml  selene.toml  .luaurc  .gitignore
├─ docs/  GDD  ARCHITECTURE  DATA_SCHEMA  BALANCING  PERF  DECISIONS  ROADMAP  QA_CHECKLIST  PLANS (.md)
├─ src/
│  ├─ shared/   → ReplicatedStorage.Shared
│  │  ├─ Core/    pure Luau, no Roblox APIs: Signal, Maid, Result, Money, NumberFormat,
│  │  │           Economy, Mastery, Unlock, Completion, Migrations, Types
│  │  ├─ Config/  data only: Balance, Flags, Districts, Parcels, Archetypes, Buildings, Upgrades,
│  │  │           Research, Vehicles, Houses, Furniture, Contracts, Achievements, Legacy,
│  │  │           Events, Objectives, Strings
│  │  ├─ Net/     remote definitions, validators, limiter
│  │  └─ Util/
│  ├─ server/   → ServerScriptService.Server
│  │  ├─ init.server.luau      bootstrap: services in explicit dependency order
│  │  └─ Services/             Data, Plot, Parcel, Building (+Factory), Construction, Economy,
│  │                           Income, Offline, Staff, Mastery, Upgrade, District, Objective, Debug
│  │                           (later: Research, Contract, Event, Achievement, Legacy, Completion,
│  │                            CityStats, Customer, Traffic, Vehicle, House, Social, Leaderboard,
│  │                            Monetization, Telemetry)
│  ├─ client/   → StarterPlayerScripts.Client
│  │  ├─ init.client.luau
│  │  ├─ Controllers/  State (read-only mirror), Input, Camera, UI, Notify, Ambient, Tutorial
│  │  └─ UI/           Kit (components), Screens (HUD, BuildingPanel, Map, CityMenu, Completion…)
│  └─ assets/   → ServerStorage.Templates (art slots; procedural fallback in BuildingFactory)
├─ tests/       headless unit tests for Core and Config
├─ tools/       content_validate.luau, economy_sim.luau, size_budget.luau
└─ .github/workflows/ci.yml   stylua --check, selene, tests, content_validate, economy_sim --smoke
```

## B2 · Ownership rules

- Only `DataService` touches DataStores. Only `EconomyService` changes currencies. Only `BuildingService` creates or destroys building instances. Only `ConstructionService` advances phases. Clients never write state.
- Services call each other through public APIs and announce changes with Signals, never shared mutable tables. Dependency order is explicit in `init.server.luau`; a cycle fails CI.

## B3 · Profile schema (version 1)

```lua
Profile = {
  Version = 1,
  Currency = { Cash, Reputation, PrestigePoints, ResearchPoints },
  Stats    = { LifetimeEarned, PlaySeconds, NetWorthPeak },
  Time     = { FirstJoin, LastSaved, LastSeen },            -- os.time() seconds
  Parcels  = { [parcelId] = true },
  Buildings = { [uid] = { def, parcel, level, phase, upg = { [lineId] = level },
                          mastery = { xp, lvl }, staff = {...}, manager = grade or nil,
                          constructing = { phase, startedAt, seconds } or nil } },  -- phase = last completed; constructing = in flight
  Districts = { [districtId] = { unlocked, devRating } },
  Research = { done, active }, Contracts = { active, done, seed },
  Objectives = { chain, pinned }, Collections = { Vehicles, Houses, Furniture, Cosmetics },
  Achievements = {}, Legacy = {}, Settings = {}, Purchases = { [receiptId] = true },
}
```

Rules: short stable string IDs; deterministic structure; budget ≤ 1 MB per profile (test fails at 3 MB; the DataStore value limit is 4 MB, so verify the current limit); migrations are pure functions `vN → vN+1` in `Core/Migrations` with tests; missing fields are reconciled from a template.

## B4 · Content schema (sketch for `Core/Types.luau`)

```lua
--!strict
export type DistrictId = "Starter" | "Shopping" | "Financial" | "Luxury"
  | "Entertainment" | "Industrial" | "Transportation" | "Billionaire"
export type UpgradeCategory = "Construction" | "Staffing" | "Equipment" | "Business" | "Appearance" | "Mastery"
export type Archetype = "Retail" | "Food" | "Service" | "Residential" | "Office" | "Finance"
  | "Hospitality" | "Venue" | "Industry" | "Logistics" | "Transit" | "Landmark" | "Civic"

export type Requirement =
    { kind: "NetWorth", min: number } | { kind: "Reputation", min: number }
  | { kind: "Population", min: number } | { kind: "Happiness", min: number }
  | { kind: "PrestigePoints", min: number } | { kind: "DistrictPct", district: DistrictId, min: number }
  | { kind: "Research", node: string } | { kind: "Building", def: string, level: number? }
  | { kind: "Contract", id: string } | { kind: "Legacy", id: string }

export type Cost = { cash: number?, prestige: number?, research: number?, materials: { [string]: number }? }

export type UpgradeDef = {
  id: string, category: UpgradeCategory, name: string, maxLevel: number,
  baseCost: Cost, growth: number,                         -- cost(L) = baseCost * growth^(L-1)
  effect: { stat: string, op: "add" | "mult", perLevel: number },
  requires: { Requirement }, tier: number,
}
export type PhaseDef = { id: string, cost: Cost, seconds: number, requires: { Requirement }, visual: string }
export type BuildingDef = {
  id: string, district: DistrictId, archetype: Archetype, name: string,
  parcelSize: "S" | "M" | "L" | "XL", landCost: number, blueprint: { Requirement },
  phases: { PhaseDef }, baseRevenuePerMin: number, baseExpensesPerMin: number,
  capacity: number, staffSlots: number, upgradeLines: { string },  -- generated from Archetypes + overrides
  mastery: string, style: string, contentVersion: number, requiredForCompletion: boolean,
}
```

**Content budget `[ASSUMPTION]` (launch targets):** 8 districts · 66 building types (many with multiple instances) · 500+ upgrade lines (template-generated) · mastery 1–100 per eligible property · ~80 research nodes (~16 per branch) · 60+ vehicles (~8 per category) · 20+ houses, 150+ furniture items, 12+ interior themes · 60+ contract templates · 150+ achievements · 7 Legacy milestones · 5 event types plus anniversary. Every definition carries `contentVersion` so future updates add content without shrinking anyone's completion %.

## B5 · Economy rules

Tunables live in `Config/Balance.luau`. Defaults are `[ASSUMPTION]`, to be tuned with `tools/economy_sim.luau`.

```
cost(L)       = round(baseCost * growth^(L-1)),   growth in [1.12, 1.35] (cheaper tiers lower)
gross/min     = baseRevenue * levelMult * demandMult * staffMult * upgradeMult * cityMult * eventMult
revenue       = min(traffic, capacity) * avgSpend
net/min       = max(gross - (wages + supplies + utilities + maintenance), 0.2 * gross)   -- never negative
happinessMult in [0.9, 1.2]  -- low happiness never zeroes income
offline       = min(now - lastSaved, capHours*3600) * netPerSec(at last save) * efficiency   -- default 4 h, 50%
masteryXP     = level L needs round(100 * L^1.6); gain scaled by 1 / (1 + xpThisHour / softCap)
completion %  = sum(weight_i * progress_i): Buildings & construction 20, Upgrades 20, Mastery 15,
                Research 10, Collections 15, Achievements 15, Secrets 5
```

Starting payback targets per upgrade (minutes; tune with the simulator):

| Tier | Low-level upgrade | High-level upgrade |
|---|---|---|
| Starter | 0.5–2 | 5–15 |
| Shopping | 2–5 | 15–40 |
| Financial | 5–10 | 30–75 |
| Luxury | 8–15 | 45–90 |
| Entertainment | 10–20 | 60–120 |
| Industrial | 10–20 | 60–120 |
| Transportation | 15–30 | 75–150 |
| Billionaire | 20–40 | 90–180 |

Reference player model for the simulator `[ASSUMPTION]`: plays about 1.5 h per day at ~50% activity, buys the best payback-per-cost option available, collects offline income at each session start.

**Invariants (enforced by tests and the simulator)**

1. Costs strictly increase with level; all costs are integers ≥ 1.
2. Net income is never negative.
3. The sum of every cost in the game stays under 2^53 / 16 so integer math stays exact.
4. After the first 30 minutes, no single upgrade raises total income per minute by more than 25% (unless flagged as a milestone reward), and every purchase's payback falls inside its tier band.
5. District arrival times in the simulator fall inside the windows in §A14, and the reference player reaches 100% City Completion in 100–200 h.
6. Offline earnings never exceed cap × net income × efficiency.
7. Solvable: every item is reachable from a new profile through legal purchases only.

## B6 · Network protocol

- **Client → server intents** (each returns `Result {ok, code, data?}`): `ParcelPurchase`, `ConstructStart`, `UpgradePurchase`, `StaffHire/Assign`, `ManagerHire`, `IncomeCollect(buildingUid | "all")`, `ObjectivePin`, `SettingsSet`; later phases add research, contracts, vehicles, furniture.
- **Server → client:** one `StateSnapshot` on join, then coalesced `StatePatch` diffs (≤ 4 Hz), plus `Toast`, `EventBanner`, `LeaderboardData`. The client store is a read-only mirror; UI binds to selectors.
- Every remote: schema-validated, rate-limited per player (token bucket), IDs checked against Config, numbers checked for finiteness and range. Never `InvokeClient`.

## B7 · World and performance

- **Layout `[ASSUMPTION]`:** a shared Hub (plaza, leaderboards, transit stop) with `PlotSlots = MaxPlayers` (default 12) plots arranged around it. Each plot holds the eight district zones on a fixed grid (district tile ≈ 320×320 studs, parcel unit ≈ 32 studs), unlocked progressively. Unbuilt parcels are markers, not models: instances exist only for what the player has built.
- **Visiting:** in-server visiting = teleport to a friend's plot with owner-controlled permissions. Cross-server visiting is a later stretch goal.
- **Initial budgets (validate in Studio, record in `docs/PERF.md`):** server Heartbeat cost under 5 ms average at 12 players (income tick is O(dirty buildings), cached, staggered); remote traffic under 5 KB/s per player average; ≤ 400 BaseParts per standard building, ≤ 3,000 per landmark, ≤ 40,000 per fully built plot; 60 FPS on a mid-range phone at default quality; client memory under 1 GB.
- **Determinism:** the city-event schedule is a pure function of UTC time slot + seed, so every server agrees without MessagingService.
- **Leaderboards:** OrderedDataStore, updated at most once per player per 60–120 s and only when the value changed.

## B8 · Verification ladder

1. Headless unit tests on `Core` and `Config`. 2. `content_validate` and `economy_sim`. 3. StyLua and Selene. 4. `rojo build`. 5. Studio playtest through MCP if connected, otherwise the human `QA_CHECKLIST.md`. 6. Structured logs plus a thin `Telemetry` module (wrap Roblox AnalyticsService economy and funnel events where the API exists).

## B9 · Roadmap (original five stages: Foundation → Expansion → Systems → Content → Polish)

| Phase | Scope | Stage |
|---|---|---|
| **0** | Engineering foundation, tooling, docs, Core, data layer, validators, simulator | Foundation |
| **1** | Playable vertical slice: plots, parcels, construction, Convenience Store, HUD, save/load, offline income | Foundation |
| **2** | Full Starter District, employees, managers, mastery, complete Building Panel, city management menu, objective tracker, district-gate framework | Expansion |
| **3** | Shopping and Financial districts, mall megaproject, investments, Corporate HQ company-wide upgrades | Expansion |
| **4** | City simulation: demand model, population, happiness, roads, utilities, parks, client ambient NPCs and traffic | Systems |
| **5** | Meta systems: contracts, research, events, dailies/weeklies, achievements, completion menu, Legacy, social, leaderboards | Systems |
| **6** | Collections: vehicles and garages, houses and interiors, rare collectibles, hidden building | Systems |
| **7** | Remaining districts: Luxury, Entertainment, Industrial, Transportation, Billionaire (one task each) | Content |
| **8** | Balance, performance, mobile UX, tutorial polish, anti-exploit review, monetization review, release checklist | Polish |

## B10 · Risk register

| Risk | Mitigation |
|---|---|
| Scope explosion | Content as data, archetype templates, strict phases with acceptance criteria |
| Economy runaway or dead ends | Simulator, invariants in CI, payback bands, solvability check |
| Player data loss | Session locking, versioned migrations, autosave, BindToClose, size budget test |
| Exploits and duplication | Server authority, single money door, atomic transactions, rate limits, idempotent receipts |
| Mobile performance | StreamingEnabled, client-side ambient NPCs, part budgets, pooled objects |
| No art pipeline | Procedural buildings with art-slot overrides |
| Roblox policy | No paid randomness, in-game-currency-only investments, fictional IP |

