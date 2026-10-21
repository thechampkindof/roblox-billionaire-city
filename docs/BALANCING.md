# Balancing

Every number lives in `src/shared/Config/Balance.luau`. Nothing else hard-codes a rate.
`tools/economy_sim.luau` plays the content greedily and prints the numbers below, so a
tuning change is measured, not guessed.

```bash
node tools/run_luau.mjs tools/economy_sim.luau          # full reference run
node tools/run_luau.mjs tools/economy_sim.luau --smoke  # CI sanity run
```

## Model

```
capacity        = def.capacity + Σ capacity upgrades + staff capacity
customers/min   = min(capacity, baseCustomers × demand)
gross/min       = customers/min × avgSpend × levelIncomeGrowth^(level-1) × revenueMult
expenses/min    = baseExpenses/min × levelExpenseGrowth^(level-1) × expenseMult + wages
net/min         = max(gross − expenses, gross × Balance.Rates.minNetFraction)
```

- `revenueMult` adds up: upgrade lines, staff (`revenuePerWorker × efficiency` per worker)
  and mastery milestone bonuses.
- **Net profit never goes negative** (Appendix B5 #2): the `minNetFraction` floor (20%)
  means a badly staffed business still earns something, which keeps the UI honest.
- **Dynamic pricing**: `BuildingMath.priceScale` multiplies every price (upgrade, level,
  hire) by `currentNet / baseNet`, clamped to ≥1. A property that earns 10× more costs
  roughly 10× more to improve. This is what keeps thousands of purchases meaningful
  without hand-tuning each line.

## Mastery

- `xpForLevel(L) = round(100 × L^1.6)`, capped at level 100.
- XP comes from cash collected (`xpPerCashCollected`) and cash spent on the property
  (`xpPerCashSpent`), scaled by a rolling one-hour soft cap: gains are divided by
  `1 + windowXp / softCapPerHour`, so farming one cheap kiosk cannot max the tree.
- Milestones at 5/10/25/50/75/100 grant permanent revenue bonuses (2%→15%).

## Measured baseline (reference player: 1.5 h/day, greedy best payback)

```
first upgrade               0.0 h
second parcel               0.0 h
net worth $5K               0.3 h
net worth $25K              0.7 h
all starter parcels         1.3 h
first manager               1.3 h
net worth $100K             1.4 h

after 1.5 h: net worth $113,848 · 29,919 cash/min · 16 buildings · 16/16 parcels · 900 purchases
payback: build ~9.2 min · level ~18.8 min · upgrade ~11.6 min (min 1.1, max 23.0)
completion snapshot: buildings 33%, upgrades 100%, mastery 4%
```

### Reading of these numbers (provisional)

- The greedy simulator is an **upper bound**: it always buys the best payback and never
  idles, so a human will be slower. Real pacing should be checked in playtests
  (`QA_CHECKLIST.md` Smoke-01 asks for the human timestamps).
- Upgrades are exhausted (100%) inside the reference session while buildings sit at 33%.
  Phase 1 ships one district with 141 lines; the intent is that Phases 2–8 make breadth,
  not price, the gate. If playtests feel upgrade-starved, raise
  `Balance.Upgrades.categoryGrowth` rather than adding new line kinds.
- Level purchases (18.8 min payback) are deliberately the slowest early lever: they are
  the "save up while you do something else" option, and they keep the buildings' visual
  growth meaningful.
- Build payback (~9 min) is intentionally worse than upgrades: land and construction are
  long-term investments, and the second parcel must not outshine the first store's
  upgrade tree.

## Bands we hold ourselves to

| Rule | Where it is enforced |
|---|---|
| Every price is a positive integer below 2^53/16 | `content_validate`, `size_budget` |
| Cost strictly increases with level | `economy_sim` invariant 1 |
| Net income never negative, even at 25× expenses | `economy_sim` invariant 2 |
| No purchase adds >25% to total income after 30 minutes | `economy_sim` invariant 4 |
| Offline < cap × net/min × efficiency | `economy_sim` invariant 6 + `Core/Economy` tests |
| Everything is reachable with legal purchases only | `economy_sim` invariant 7 |
| Completion weights 20/20/15/10/15/15/5 | `Core/Completion` tests |

## `[ASSUMPTION]` values (the brief did not specify these)

| Value | Current | Why |
|---|---|---|
| Offline cap | 4 h | "a few hours"; keeps a return visit worth it without trivialising play |
| Offline efficiency | 50% | Active play must beat idling |
| Mastery XP rates | 0.08/0.02 per $1, soft cap 1500 XP/h | Tuned so mastery is a 100-hour axis, not a session one |
| Rush cost | $4 per remaining second | Priced so rushing a 50 s phase costs less than a new upgrade |
| Ambient agents | 10 / 22 / 40 by device | Appendix B7 wants a living city without mobile stutter |
| Plot ring | radius 420, max 12 plots | Fits 12 players' pads around the hub without StreamingEnabled churn |

## Tuning workflow

1. Edit `Balance.luau` (or content prices) only.
2. `node tools/run_tests.mjs` — the content-driven specs catch shape breaks.
3. `node tools/run_luau.mjs tools/economy_sim.luau` — compare paybacks and the 1.5 h
   snapshot with the table above.
4. Record the change and the new numbers in this file, in the same commit.
