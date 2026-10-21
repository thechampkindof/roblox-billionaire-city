# Billionaire City Tycoon

A Roblox tycoon about building one enormous city: hundreds of upgrades, persistent
progress and a plot that visibly grows while you play. This repository is the
**Phase 0 + Phase 1** slice: the foundation, the Convenience Store loop, parcels,
construction, staff, managers, mastery, objectives and offline income.

- Design: [`docs/GDD.md`](docs/GDD.md)
- Engineering rules: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- What is done / next: [`docs/ROADMAP.md`](docs/ROADMAP.md)
- How to test by hand: [`docs/QA_CHECKLIST.md`](docs/QA_CHECKLIST.md)

## What you need

| Tool | Version | Why |
|---|---|---|
| [Rokit](https://github.com/rojo-rbx/rokit) | any | installs the pinned tools |
| Roblox Studio | current | the game only runs there |
| Node.js 20+ | optional | runs the headless checks in this repo |

```bash
rokit install          # installs Rojo, StyLua, Selene, Lune from rokit.toml
```

## Run it in Studio

```bash
rojo serve             # keep this running
```

1. Open Roblox Studio.
2. New **Baseplate** place (the Rojo project supplies everything else).
3. In the Rojo plugin, **Connect** to `localhost:34872`, then **Sync in**.
4. Press **Play**.

You should get your own plot, a Convenience Store, a HUD in the top-left, an objective
card and a collect button. Tap a parcel to buy land, tap a building to manage it.

## Build a place file

```bash
rojo build -o build/BillionaireCityTycoon.rbxl
```

Open that file in Studio, or upload it through the normal publish flow. `build/` is
git-ignored.

## Headless checks (no Studio needed)

```bash
node tools/run_tests.mjs        # 108 unit tests: Core, Config, Net, Util
node tools/run_luau.mjs tools/content_validate.luau
node tools/run_luau.mjs tools/economy_sim.luau --smoke
node tools/run_luau.mjs tools/size_budget.luau
node tools/syntax_check.mjs     # every Luau file compiles
node tools/wiring_check.mjs     # requires, Content paths, intents, service methods
```

With the pinned tools installed you can also use the official toolchain:

```bash
stylua --check .
selene src
lune run tools/content_validate.luau
```

CI runs all of the above (see `.github/workflows/ci.yml`).

## Where things live

```
src/shared/Core     pure Luau (no Roblox API): money, signals, mastery, unlock, profile
src/shared/Config   content as data: balance, buildings, upgrades, parcels, objectives
src/shared/Net      remote definitions, payload validators, rate limiter
src/shared/Util     BuildingMath — the one place prices and income are computed
src/server          services (data, economy, plots, buildings, construction, income…)
src/client          controllers and UI, all built in code
tests/              headless specs
tools/              validators, simulator, size budget, syntax and wiring checks
```

## Playing with the debug tools

Debug actions exist only when **all** of these are true: the server is in Studio, the
`DebugTools` flag is on, and the player is on the allow-list in `DebugService.luau`.
Enable the flag in `src/shared/Config/Flags.luau` while developing; production builds
leave it off, so the code path is unreachable.

## Troubleshooting

- **Nothing spawns / UI is empty** — check the Output window for
  `[BillionaireCity] server ready` and `client ready`.
- **`Rojo: project not found`** — run `rojo serve` from the repository root.
- **Your profile will not load in Studio** — the in-house provider needs DataStores,
  which Studio only allows in published places. Set `MockDataStore = true` in
  `src/shared/Config/Flags.luau` (or just play in Studio, which falls back to the mock
  provider automatically) to keep a session profile in memory.
