# Roadmap

Phase 0 and Phase 1 are **complete**. Phases 2–8 are planned, with acceptance criteria, and
nothing from them is stubbed in code.

Legend: `[x]` done and verified · `[~]` done but only verified outside Studio (see notes) ·
`[ ]` not started

## Phase 0 — Foundation (complete)

- [x] Rojo project (`default.project.json`, StreamingEnabled), `rokit.toml`, `stylua.toml`,
      `selene.toml`, `.luaurc`, `.gitignore`, CI workflow
- [x] Docs set: GDD, ARCHITECTURE, DATA_SCHEMA, BALANCING, PERF, DECISIONS, ROADMAP,
      QA_CHECKLIST, PLANS, README, AGENTS
- [x] `src/shared/Core`: Signal, Maid, Result, Money, NumberFormat, Economy, Mastery,
      Unlock, Completion, Migrations, Profile, SessionLock, Uid, Types
- [x] Core unit tests (Signal, Maid, Result, Money, NumberFormat, Economy, Mastery, Unlock,
      Completion, Profile, Objectives, SessionLock/Uid)
- [x] Net layer: one `Intent` remote with a declarative schema, validators, token-bucket
      limiter, typed result codes
- [x] Data layer: `DataService`, `ProfileProvider` interface, in-house DataStore provider,
      `MockProvider`, retries with backoff, session lock, autosave, `BindToClose`
- [x] Content pipeline: `Core/Types`, archetype-generated upgrade lines, `content_validate`,
      `economy_sim`, `size_budget`
- [x] Studio-only debug tools behind three gates (Studio + flag + allow-list)
- [x] Extra verification for sandboxes without Rokit: `syntax_check.mjs`, `wiring_check.mjs`

## Phase 1 — Playable vertical slice (complete)

- [x] Per-player plot assignment, teardown on leave, plot ring around a shared hub
- [x] 4×4 Starter parcel grid, parcel purchase with net-worth gates, pad colouring
- [x] Timestamp-based construction with progress, automatic phase advance, optional rush
- [x] Convenience Store playable: 141 generated upgrade lines across all six categories,
      income tick, revenue/expenses/net shown before purchase, manual collect
- [x] First manager: automates collection; first mastery milestone grants a revenue bonus
- [x] HUD: cash, net worth, income/min, city completion, objective card, toasts, collect-all
- [x] Building Panel tabs: Overview, Upgrades, Staff, Income & Expenses, Construction,
      Mastery work; Customization is a real layout with an explicit "coming later" note
- [x] Offline income on return, capped at 4 h and 50% (from saved timestamps only)
- [x] First-fifteen-minutes objective chain on the generic objective system
- [x] City visibly evolves: empty lot → construction site → finished phases → upgraded
      building (procedural `BuildingFactory` stages)
- [x] Save/load round trip preserves buildings, upgrades, staff, mastery, construction and
      pending income (`DataService` normalise + `Core/Profile.reconcile`)
- [~] In-Studio playtest: `docs/QA_CHECKLIST.md` **Smoke-01** is written but has not been
      executed by a human (no Studio in the build environment)
- [~] `rojo build -o build/BillionaireCityTycoon.rbxl`: NOT RUN here — the sandbox lacks a
      glibc loader for Rojo's native binding. `default.project.json` is in place; CI runs it.

## Phase 2 — Shopping District

Acceptance criteria:
- [ ] 4×4 Shopping parcels, land prices gated by Starter development rating
- [ ] ≥ 8 Shopping buildings (clothing, electronics, supermarket, café, cinema, furniture,
      boutiques, department store) with archetype-generated lines
- [ ] Retail demand model (customer types, product quality) driving `gross/min`
- [ ] Mall megaproject: 4+ construction phases, each changing the model and unlocking floors
- [ ] District unlock objective chain (data only, no new objective code)
- [ ] Snapshot chunking per district (`Balance.Network.snapshotChunkBytes`)
- [ ] `economy_sim` covers two districts; payback bands unchanged for Starter
- [ ] Smoke-02 in the QA checklist

## Phase 3 — Financial District

Acceptance criteria:
- [ ] Office tenants, lease quality, floors (level axis with per-floor visuals)
- [ ] Bank with fictional investments: explicit risk text, no real-money parallels
- [ ] Corporate HQ: company-wide upgrades with a visible effect on all owned businesses
- [ ] Prestige Points granted for first HQ completion (never required for 100%)
- [ ] One signature skyscraper concept with ≥ 5 phases

## Phase 4 — Luxury District

Acceptance criteria:
- [ ] Personal homes with interiors, furniture collections, garages
- [ ] Property value + quality rating displayed; amenity upgrades
- [ ] Collection UI with completion tracking feeding `Core/Completion`
- [ ] Vehicles as cosmetics/collection only (no driving physics)

## Phase 5 — Entertainment District

Acceptance criteria:
- [ ] Event scheduling per venue (seeded `Random.new`), optional participation
- [ ] Temporary traffic multipliers, never required for progress
- [ ] Stadium/arena/theme park capacity upgrades with visible crowds
- [ ] Server-wide event announcements (no cross-server state)

## Phase 6 — Industrial District

Acceptance criteria:
- [ ] Supply chain graph (factory → warehouse → distribution) with fallback sourcing
- [ ] Manual → automated line upgrades; a broken chain reduces profit but never halts it
- [ ] Recipes as data, validated for cycles
- [ ] Warehouse stock persisted without exceeding the profile budget

## Phase 7 — Transportation & City Completion

Acceptance criteria:
- [ ] Roads/transit tiers raising district demand
- [ ] Parking garages, bus depot, subway, train, airport (late-game megaproject)
- [ ] Completion screen using the fixed weights (20/20/15/10/15/15/5)
- [ ] Leaderboards (opt-in) with no gameplay advantage

## Phase 8 — Billionaire District & long tail

Acceptance criteria:
- [ ] Landmark megaprojects with 6+ phases and PP costs
- [ ] Mastery level 100 rewards per property (cosmetic + city-wide bonus)
- [ ] Legacy milestones that never wipe progress
- [ ] Final completion goal: every building maxed, every district at 100% development
