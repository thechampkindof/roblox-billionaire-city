# Plans (living document)

Last updated: 2026-10-21 · Phase 0 + Phase 1 shipped.

## Where we are

Phase 0 (foundation) and Phase 1 (playable vertical slice) are implemented:

- one district, nine buildings, 141 generated upgrade lines, 16 parcels
- buy land → build (timestamped phases) → upgrade → hire → manage → mastery
- objectives, offline income, save/load, snapshots, toasts, HUD, building panel
- verification: 108 unit tests, content validator, economy simulator, size budget,
  syntax check, wiring check

## Next tasks (in order)

1. **Human playtest of Smoke-01.** The only Phase 1 item not verified end to end. It
   produces the timings that decide whether the upgrade tree is too fast (see
   `DECISIONS.md` open question 1).
2. **Close the gaps Smoke-01 finds.** Expect: model stage polish, panel copy, and a first
   pass on colour/shape differences between the nine buildings.
3. **Phase 2 kickoff — data first.**
   - `Config/Districts.luau`: turn the Shopping placeholder into a real unlock requirement.
   - `Config/Parcels.luau`: 4×4 Shopping grid.
   - `Config/Buildings.luau`: eight Shopping buildings using existing archetypes.
   - `Config/Objectives.luau`: the district unlock chain.
   - Run `content_validate`, `economy_sim`, `size_budget` before writing any code.
4. **District gating.** `Bootstrap` currently unlocks only Starter; add a
   `DistrictService` (or extend `ParcelService`) once the second district has content, with
   `Unlock.evaluate` on `DistrictDef.unlock` and a dev-rating contribution per owned parcel.
5. **Snapshot chunking.** Measure the Shopping snapshot first; only chunk if the payload
   approaches `Balance.Network.snapshotChunkBytes`.
6. **Retail demand model.** Customer types and product quality are the one genuinely new
   mechanic Phase 2 needs; prototype it in `Core/Economy` behind data, not in a service.

## Deliberately deferred

| Item | Why deferred |
|---|---|
| Separate MasteryService / ManagerService | one caller each; see `DECISIONS.md` D-007 |
| Vehicles, houses, furniture | Phase 4 content, needs collection UI first |
| Research, contracts, events | Phases 3–5; `Core/Types` already has the state shapes |
| Monetization | flag exists, nothing purchasable; must never gate completion |
| Telemetry | flag exists; no endpoint decided |
| Leaderboards / social | Phase 7, needs cross-server design |

## Risks

- **Nothing has run in Studio.** Both layers now run headlessly (47 server + 23 client
  assertions), but rendering, replication, input feel and mobile layout are still only
  designed, not observed. The first playtest is a bug hunt for layout and game feel.
- **The harnesses found eleven real defects** on first run: broken Shared require paths,
  missing bootstrap, wiped `LastSaved`, shadowed `ConstructionService.Start`, `Config.Flags`
  misuse, double `PivotTo`, an unfriendly rate-limit message, an unparented scroll frame,
  recursive panel close, an unstable `Enum` comparison in the input path and toast tweens
  without `TweenInfo`. Assume a similar density of cosmetic bugs remains.
- **Economy tuning** is provisional and measured only against a greedy bot.
- **Rojo build** is unverified in this environment (no glibc); CI is the authority.
- **Profile growth** in Phase 2 (supply chains, collections) is the next budget pressure.

## Definition of done for the next milestone (Phase 2)

- [ ] Shopping District content validated and reachable from a fresh profile
- [ ] Mall megaproject with ≥ 4 phases and visible stage changes
- [ ] Retail demand reflected in `BuildingMath` and shown in the Income tab
- [ ] `economy_sim` covers two districts and keeps Starter paybacks in band
- [ ] Smoke-02 written and executed in Studio
