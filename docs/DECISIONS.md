# Decisions

Every choice made where the brief was silent, ambiguous or self-conflicting. Newest
first. Each entry: what we chose, why, and what would change our mind.

## D-017 · The client harness fakes the Roblox UI surface

**Chose:** `tools/harness/Shim.luau` also provides lazily-created instance events
(`Activated`, `CharacterAdded`), default GUI properties (`AbsoluteSize`, `Text`), a cached
`Enum` (so identity comparisons hold), `TweenService`, `TweenInfo`, `RaycastParams` and a
camera with a settable raycast result. `client_sim.mjs` boots the real client bundle and
taps parcels, buildings and every panel tab.
**Why:** the first client boot found that `Kit.scrollList` never parented its ScrollingFrame
(the entire panel content area would have been invisible in game) and that closing a panel
recursed through the UI controller's callback. Neither is visible to a compiler.
**Would change:** keep it; extend the shim as new UI surfaces appear (drag, pinch, sounds).

## D-016 · A headless server harness, not just static checks

**Chose:** `tools/harness/Shim.luau` + `tools/server_sim.mjs` boot the real services
against a minimal Roblox environment (instances, signals, `task` scheduler, virtual
`os.time()`, in-memory DataStore) and play the Phase 1 loop through the real intents.
**Why:** the static checks could not see that `ConstructionService.Start` was shadowed by
the lifecycle `Start()`, that `Bootstrap` was never called, or that `normalise()` erased
`LastSaved`. The harness found all three (plus four more) in its first runs. It is 47
assertions and under a second of CI time.
**Would change:** delete it once Studio playtests are routine in CI (Roblox's own Open
Cloud Luau execution could replace it), but keep the shim for regression testing.

## D-015 · `script` is bound per chunk in the headless runtime

**Chose:** `tools/luau_runtime.mjs` loads each module as `local script = ...; <source>`.
**Why:** the earlier global-`script` emulation broke any `require(script.Parent.X)` that ran
later (intent handlers), which is how every `NetService` handler loads its service. Real
Roblox binds `script` lexically, so the runtime now does too.
**Would change:** nothing; this matches Studio semantics.

## D-014 · Verification without Studio

**Chose:** add `tools/syntax_check.mjs` (compiles every `.luau` with Luau) and
`tools/wiring_check.mjs` (requires resolve, every `Content.*` / `Balance.*` path exists,
every service method called exists, intent schemas match handlers, flags exist).
**Why:** the brief's gate is `stylua` + `selene` + Lune + Rojo, and the build sandbox has
no glibc (Rojo's native binding will not load) and no Selene/Rokit download access. These
two checks catch the failure class that would otherwise only surface in Studio: typos,
stale field names, missing functions.
**Would change:** if CI (which does have Rokit) runs Luau's own analyzer, these remain
cheap, complementary lints rather than a replacement.

## D-013 · Starter state: a finished store, not an empty lot

**Chose:** a new profile owns the free `starter_01` parcel **and** a completed
Convenience Store. The first objective is "collect income"; construction is taught by the
second building.
**Why:** GDD A1 says the player starts with "one basic business"; the onboarding chain
(collect → upgrade → hire → second parcel → manager) needs income on minute one. It also
keeps construction optional on the first visit instead of a mandatory wait.
**Would change:** if playtests show construction needs to be taught earlier, add a
scripted first build in the objective chain and start the plot empty.

## D-012 · Whole build paid up front, phases advance by timestamp

**Chose:** `ConstructStart` charges `Content.totalBuildCost(def)` once, then each phase
completes from `startedAt + seconds`. No `ConstructionNext` intent exists; `Rush`
completes the current phase for cash.
**Why:** timestamps make progress survive rejoin and offline time for free, and a single
purchase is one atomic `transact`. Phases stay visible (and rushable) without a second
payment mechanic the brief never specified.
**Would change:** if phases should cost separately, `ConstructionService.Start` charges
per phase and `advanceState` asks the player to fund the next one.

## D-011 · No self-referential requirements

**Chose:** "manager needs building level 2" is a `BuildingDef.managerMinLevel` field, not
a `Building` requirement pointing at the same property.
**Why:** `content_validate` forbids self-references because they read as requirement
cycles. A numeric field is unambiguous, data-driven and cannot loop.
**Would change:** introduce an explicit `{ kind = "OwnBuildingLevel" }` requirement kind if
other systems ever need the same gate.

## D-010 · Income-relative pricing

**Chose:** every price (upgrade level, building level, hire) is multiplied by
`BuildingMath.priceScale = currentNet / baseNet` (clamped ≥ 1).
**Why:** one content table then serves a property from $100 to $1B without retuning 141
lines per district, and a fully built property's purchases cannot become trivial.
**Would change:** if paybacks drift outside the bands in `BALANCING.md`, taper the
exponent (`current/base` → `sqrt(current/base)`) in `Core/Economy.incomeScale`.

## D-009 · Consumed income lives in `pending`, not in `Cash`

**Chose:** `IncomeService` accrues into `BuildingState.pending` (integer) and only
`Collect` (or a manager, automatically) moves it into `Cash` through `transact`.
**Why:** the GDD's core loop is "collect income", and the UI must show what is waiting per
building. Manager automation then has a precise meaning rather than "income is always
already banked".
**Would change:** nothing foreseeable; this is the genre-standard model.

## D-008 · Fractional accrual in memory, integers in the profile

**Chose:** with no manager, accrual keeps a fractional remainder per player/uid in a
service-local table; the profile only ever stores whole cash.
**Why:** at 1–2 s ticks a $200/min store earns $3.33 per tick; rounding each tick would
either lose or mint money. Remainders are dropped on rejoin (bounded by one tick).
**Would change:** store remainders in the profile if precision on rejoin ever matters.

## D-007 · Managers and mastery have no services of their own

**Chose:** hiring a manager is `StaffService.HireManager`; mastery XP is awarded inline by
`IncomeService`/`UpgradeService`/`ObjectiveService` through `Core/Mastery`.
**Why:** both are small, pure pieces of logic with one caller each. Separate services would
be ceremony, and the brief allows extension points rather than speculative layers.
**Would change:** when managers gain behaviours (routes, autopilot, per-district policies),
move them to `ManagerService`.

## D-006 · Client reads `ReplicatedStorage.Shared` via `GetService`

**Chose:** `local Shared = game:GetService("ReplicatedStorage").Shared` in client modules.
**Why:** `script.Parent…` depth differs between `StarterPlayerScripts.Client` (a Script with
folder children) and server services, and a wrong chain fails at runtime, not at build
time. The path through `ReplicatedStorage` is stable under the Rojo mapping.
**Would change:** switch to `script.Parent` chains if the project ever moves Shared under
the client script tree.

## D-005 · UI is code, panels are modal sheets

**Chose:** `UI/Kit` builds every widget; `BuildingPanel`/`ParcelPanel` are centred sheets
with a dismiss scrim, opened by tapping the world.
**Why:** mobile-first, one-handed play; no hover, no nested menus. Tapping the world is the
navigation metaphor the GDD describes ("the city is the interface").
**Would change:** split panels into separate screens if a district needs a map/menu.

## D-004 · Procedural-only art for Phase 1, with an override slot

**Chose:** `BuildingFactory` generates every model from parts; it checks
`ServerStorage/Templates/<buildingId>/<phaseId>` first, but nothing is shipped there yet.
**Why:** the brief asks for a visible progression from empty lot → site → finished →
upgraded without waiting for art, and a 9-building slice does not justify asset authoring.
**Would change:** art team drops phase models into the slot; no code change needed.

## D-003 · Objective chain is data, five steps, generic goals

**Chose:** `Content/Objectives.luau` holds five steps (collect, upgrade, hire, second
parcel, manager) expressed as `ObjectiveGoal` variants evaluated by `Core/Objectives`.
**Why:** Appendix A16 wants the first fifteen minutes to teach the loop; keeping goals
generic means Phase 2 objectives need no code.
**Would change:** nothing; add objective kinds to `Core/Types` and `Core/Objectives.measure`.

## D-002 · Economy rescale before content authoring

**Chose:** prices and incomes were rescaled (`Economy.scaledCost`, `incomeScale`) before
the nine buildings were written, and the simulator was updated to stay the tuning tool.
**Why:** authoring 141 lines against un-scaled prices would have required rewriting them
once progression rates were known.
**Would change:** never reintroduce a second pricing path; `BuildingMath` is canonical.

## D-001 · Phase 1 scope is one district

**Chose:** only the Starter District exists in content. Districts 2–8 are declared in
`Districts.luau` with origins and unlock requirements but have no parcels or buildings.
**Why:** the brief scopes Phase 1 to a playable vertical slice and forbids speculative
stubs. Declaring the districts keeps the eight-district shape while making the missing
content explicit.
**Would change:** Phase 2 adds Shopping District parcels/buildings/objectives only.

---

## Open questions (need a human decision)

1. **Pacing:** the greedy reference player exhausts all 141 Starter upgrade lines within
   ~1.5 h. Keep that (breadth arrives with districts 2–8) or slow the tree down now?
2. **Starter state:** pre-built store (current) vs. teaching construction as step one.
3. **Offline:** 4 h at 50% is our `[ASSUMPTION]`; confirm before launch messaging is written.
4. **Manager gate:** level 2 is deliberately early (the chain needs it). Should managers
   later require a minimum *number* of buildings instead?
5. **Mastery visibility:** mastery is shown as a tab and XP bar only. Should milestone
   rewards also announce themselves in the HUD?
