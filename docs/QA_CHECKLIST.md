# QA checklist

Every smoke test is written to be followed by someone who has never seen the project.
Tick a box only when you observed the expected result. Timestamps next to each section are
the *target* for a first-time player and the tuning input for `BALANCING.md`.

## Smoke-01 · Studio playtest (Phase 1 vertical slice)

**Setup (5 min)**

1. `rokit install` (or install Rojo manually), then `rojo serve` in the repo root.
2. Roblox Studio → New Baseplate → Rojo plugin → Connect → **Sync in**.
3. Open **Output** and keep it visible.
4. Optionally set `DebugTools = true` in `src/shared/Config/Flags.luau` and add your user
   id to `DebugService.ALLOWLIST` — the walkthrough below uses no debug actions.
5. Press **Play** (F5). Give the server 3 s.

**A. Join and plot**

- [ ] Output shows `[BillionaireCity] server ready — services: …` (one line, ~14 names).
- [ ] Output shows `[BillionaireCity] client ready for <your name>`.
- [ ] The camera settles on a pad of 16 parcel tiles; a building sits on the first tile.
- [ ] HUD shows CASH `$500`, NET WORTH, PER MIN, CITY `0%`/small, plus an objective card.
- [ ] Toast: "Welcome to your city plot!".

**B. First income (target: 0–2 min)**

- [ ] After ~10 s the building shows a floating `+$…` bubble.
- [ ] Press **Collect** (bottom-left). Cash increases; bubble disappears; toast
      "Income collected."
- [ ] Objective 1 ticks over to "Buy your first upgrade" (or completes and advances).
- [ ] `/` Output shows no red errors from any `[BillionaireCity]` service.

**C. Building panel (target: 0–4 min)**

- [ ] Tap the building → panel opens with tabs Overview / Upgrades / Staff / Income /
      Construction / Mastery / Customize.
- [ ] Overview shows level, net/min, and an "Expand to level 2" button with a **cost and
      payback printed before purchase**.
- [ ] Upgrades: grow into groups by category; each row shows current level, effect and
      price. Buy the cheapest one.
- [ ] Cash drops by exactly the price shown; income/min in the HUD increases.
- [ ] Income tab: revenue, operating costs, net and average spend are all non-zero.
- [ ] Mastery tab: XP bar moves after collecting income.
- [ ] Customize tab: shows "Coming in a later update." and nothing interactive.
- [ ] Close the panel with the Close button, then reopen and close by tapping the scrim.

**D. Construction (target: 4–8 min)**

- [ ] Close the panel. Tap an empty parcel (not the building's tile) → parcel sheet opens.
- [ ] "Buy this parcel" shows a price; press it. Cash drops; the tile changes colour.
- [ ] Tap the new parcel again → "Build Convenience Store" (or another building) lists
      cost, net/min and build time.
- [ ] Press the build button. Cash drops by the full build cost; a construction site
      appears; toast "Construction started."
- [ ] Open the new building's Construction tab: progress bar advances within ~10 s, and a
      "Finish now" price is shown.
- [ ] Wait for the phases to finish (or press Finish now). The model changes between
      phases and the building starts earning only when fully built.
- [ ] HUD PER MIN rises once the new building is operational.

**E. Staff, manager, mastery (target: 8–15 min)**

- [ ] Staff tab: hire a Basic worker — cash drops, wages appear in the Income tab's
      operating costs, and net income changes accordingly.
- [ ] Manager button is disabled with a level hint until the building is level 2; at
      level 2 it can be hired.
- [ ] After hiring the manager, income collects without pressing Collect (watch cash climb
      on its own for 30 s).
- [ ] Mastery tab reaches a milestone (level 5) during the session; the milestone row
      describes the revenue bonus.
- [ ] Objective chain advances through hire → second parcel → manager with toasts.

**F. Persistence and offline (needs a published place or Studio with DataStores)**

- [ ] Note cash, building count, upgrade levels and mastery XP. Press **Stop**, then Play
      again in the same Studio session.
- [ ] Values match exactly (construction that finished while away is complete; a build
      still running is still running, with less time remaining).
- [ ] Wait ~2 real minutes offline, rejoin: a gold toast shows "Welcome back! Offline
      income: $…" and cash rose by no more than
      `min(elapsed, 4 h) × net/min × 0.5`.
- [ ] Close Studio with the game running (server saves on `BindToClose`); reopen: no lost
      purchases.

**G. Authority and abuse**

- [ ] In the client console (Studio → Play → Client → Command bar) run
      `game.ReplicatedStorage.BillionaireNet.Intent:FireServer("IncomeCollect", {buildingUid="all", extra=1})`
      — server replies with a toast "Something went wrong with that request." and cash does
      not change.
- [ ] Fire the same intent 30 times in a loop: after ~12 the server answers "Slow down for
      a second."
- [ ] Fire `("DebugAction", {action="grant_cash"})`: rejected with "debug tools are
      disabled" (allow-list empty by default).
- [ ] No `InvokeClient` exists anywhere: search the repo for `InvokeClient` → no matches.

**H. Mobile / layout**

- [ ] In Studio, set the viewport to `360 × 640` (Test → Device Emulation). The HUD chips
      fit on one row, the Collect button is reachable with a thumb, and both panels fit
      without clipping.
- [ ] Rotate to `640 × 360`: UI rescales, nothing is cut off, the camera still frames the plot.
- [ ] Every tappable control is at least ~44 px tall.

**I. Performance sanity**

- [ ] FPS stays at the Studio cap while collecting and buying upgrades.
- [ ] Network → Stats: idle traffic is near zero; buying/collecting produces small bursts,
      no continuous stream.
- [ ] MicroProfiler shows no repeat spikes from `IncomeService`/`ConstructionService`.

**J. Failure paths**

- [ ] Set `MockDataStore = true`, restart: the game plays normally on a memory provider and
      Output says the mock provider is in use.
- [ ] Stop the server twice quickly and rejoin: the session lock resolves within ~60 s and
      the profile still loads (toast may say "Your city is open in another server").

**Sign-off**

```
Tester:             ______________
Date:               ______________
Phase build:        ______________
Time to first upgrade:     ____ min   (target 0–2)
Time to second parcel:     ____ min   (target ~5)
Time to first manager:     ____ min   (target 10–15)
Notes / surprises:
```

## Regression list (run before every release)

```bash
node tools/run_tests.mjs
node tools/syntax_check.mjs
node tools/wiring_check.mjs
node tools/run_luau.mjs tools/content_validate.luau
node tools/run_luau.mjs tools/economy_sim.luau --smoke
node tools/run_luau.mjs tools/size_budget.luau
stylua --check . && selene src
rojo build -o build/BillionaireCityTycoon.rbxl
```

If any command cannot run in your environment, write **NOT RUN + reason** in the PR rather
than skipping silently.
