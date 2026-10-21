# Performance

Targets (Appendix B7): 60 FPS on a mid-range phone with one player's city on screen,
server heartbeat comfortably under 10% of a 60 Hz frame, and joins that stay under a
second of server work before the first snapshot.

## What we measure

| Budget | Where | Status |
|---|---|---|
| Client frame | no per-frame allocation in UI; camera is one `CFrame:Lerp` per frame | by construction |
| Network | full snapshot on join, then patches at ≤ 4 Hz (`Balance.Network.patchHz`) | by construction |
| Remote payload | < 50 KB per message; a full snapshot for maxed content is ~30 KB of JSON | see budget below |
| Server work per tick | construction 2 s, income 1 s, snapshot 4 Hz, autosave 90 s | by construction |
| Instance count | one pad per owned parcel, one model per building, procedural art only | by construction |
| Ambient life | 10/22/40 client-only parts, no replication | `AmbientController` |
| Profile size | 28 KB worst case, 1 KB typical | `tools/size_budget.luau` |

## Techniques in place

- **StreamingEnabled** is set in `default.project.json`, so a client never loads another
  player's plot until it is close.
- **Snapshot coalescing**: services only mark a dirty *section*; `SnapshotService` sends
  one patch per player per 250 ms. A busy 10-purchase second becomes one message.
- **No per-frame server work.** Income accrues from `lastAccrual` timestamps in a 1 s
  loop; construction advances in a 2 s loop. Nothing loops per part, per player, per frame.
- **Pooled client ambience.** `AmbientController` creates its parts once and only writes
  `CFrame` in a heartbeat; every part is `Anchored`, `CanQuery = false`, `CanTouch = false`.
- **Billboards only when useful.** Income bubbles are created for buildings with pending
  cash and destroyed otherwise (`PlotController`).
- **Procedural art, no textures.** `BuildingFactory` builds from parts, with colour
  palettes per archetype and a `ServerStorage/Templates/<buildingId>/<phaseId>` override
  slot for hand-made stages. A building is rebuilt only when its state changes.
- **UI is built once and re-populated on patch.** Panel rows are recreated, but only when
  a panel is visible; HUD chips update strings in place.
- **Mobile quality scaling**: UI is scaled with a `UIScale` from the viewport width, so a
  small phone gets smaller panels rather than off-screen ones.
- **Mock provider in Studio** removes DataStore latency from the edit loop.

## Known costs and follow-ups

- Snapshot payload grows with the number of buildings. At 16 buildings it is ~14 KB;
  Phase 2's larger districts will need per-district chunks (`Balance.Network.snapshotChunkBytes`
  exists for that) — flagged in `ROADMAP.md`, not implemented.
- `SnapshotService.currencySection` recomputes completion and net worth per patch. It is
  cheap at this content volume (a few hundred table reads) but is the first thing to cache
  when districts 2–8 land.
- `PlotService` paints a pad per owned parcel. With 4×4 parcels that is 16 parts per plot;
  a fully built city at 8 districts is the number to measure in Phase 2.

## How to profile

1. Studio → **View → Performance → MicroProfiler**, play a session, look for spikes on
   parcel purchase and upgrade (model rebuild) rather than steady state.
2. **Network → Stats**: compare bytes/s during idle (should be near zero) and while
   collecting income (patches only).
3. **Script Performance**: `IncomeService`, `ConstructionService`, `SnapshotService`
   should each stay under ~0.5% at 12 plots.
4. Record numbers in this file when a phase lands; a budget without a measurement is a
   guess.
