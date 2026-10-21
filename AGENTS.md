# AGENTS.md

Short orientation for anyone (human or agent) changing this repository.

## Commands

```bash
node tools/run_tests.mjs                       # unit tests (headless Luau)
node tools/syntax_check.mjs                    # every .luau file compiles
node tools/wiring_check.mjs                    # requires, Content paths, intents, exports
node tools/run_luau.mjs tools/content_validate.luau
node tools/run_luau.mjs tools/economy_sim.luau --smoke
node tools/run_luau.mjs tools/size_budget.luau
stylua --check . && selene src                 # with Rokit tools installed
rojo build -o build/BillionaireCityTycoon.rbxl
```

Run the first six before every commit. If a check cannot run in your environment, say so
in the PR instead of assuming it passed.

## Layout

- `src/shared/Core` — pure Luau. **No Roblox APIs** (no `Instance`, `Vector3`, `task`,
  `game`). Everything here is unit-tested headlessly.
- `src/shared/Config` — content as data. Systems must never name a building, upgrade or
  parcel; they read `Content`.
- `src/shared/Util/BuildingMath.luau` — the only place prices, income and previews are
  computed. Server, client and simulator all call it.
- `src/shared/Net` — intent schema (`Remotes.INTENTS`), `Validators`, `RateLimiter`.
- `src/server/Services` — one responsibility each, wired in `Services/Registry` and
  listed in `src/server/init.server.luau`.
- `src/client` — controllers + UI, all built in code.
- `docs/` — GDD and ARCHITECTURE are the brief verbatim; `DECISIONS.md` records every
  choice we made where the brief was silent.

## Non-negotiables

1. **Server authority.** Clients send intents and render snapshots. No client-side money.
2. **Money only through `EconomyService.Transact`.** Rejects non-finite, negative and
   non-integer amounts, caps at 2^53, emits a log line.
3. **Persistence is sacred.** Versioned profiles, session lock, autosave, `BindToClose`,
   retry with backoff. `os.time()` for persistence; `workspace:GetServerTimeNow()`
   client-side.
4. **Content is data.** Adding a building/upgrade/parcel/objective is a Config edit; if a
   system needs a new field, extend `Core/Types` and the content validator first.
5. **`--!strict` everywhere.** No `loadstring`, no `InvokeClient`, no `wait`/`spawn`/
   `delay` (use `task`), `Random.new(seed)` for anything reproducible, `Parent` assigned
   last, `Maid` for anything connected.
6. **Art is procedural** via `BuildingFactory`, with optional overrides at
   `ServerStorage/Templates/<buildingId>/<phaseId>`.
7. **Mobile first.** 44 px touch targets, one-handed camera, no hover-only affordances.
8. **Fictional brands only.** No real company names, logos or trademarks.
9. **No speculative stubs** for Phases 2–8. Extension points are fine; half-features are
   not. UI copies for unbuilt features says so out loud (`Strings.stub`).

## Testing rules

- Pure logic → `tests/Core`, `tests/Net`, `tests/Util`. Content changes also need
  `content_validate` and `economy_sim` to pass.
- A test that cannot fail is not a test; assert on real content values.
- Economics changes must keep the Appendix B5 invariants in `economy_sim` green.

## Definition of done

`stylua --check`, `selene`, unit tests, `content_validate`, `economy_sim --smoke`,
`syntax_check`, and `wiring_check` pass. `rojo build` produces a `.rbxl`. The relevant
`docs/QA_CHECKLIST.md` smoke test has been walked by a human in Studio, or the PR says
NOT RUN and why. `docs/ROADMAP.md` checkboxes and `docs/PLANS.md` are updated in the same
commit as the code.
