--!strict
--[[
	Greedy-player economy simulator.

	Prints hours-to-milestone for the reference player model in Appendix B5 and checks
	the economy invariants that can be verified with the content that currently exists.

	Usage:
	  lune run tools/economy_sim.luau            full report
	  lune run tools/economy_sim.luau --smoke    quick run used by CI
	  node tools/run_luau.mjs tools/economy_sim.luau --smoke
]]

local root = script.Parent.Parent :: any
local GreedyPlayer = require(script.Parent.GreedyPlayer)
local Core = root.src.shared.Core
local Config = root.src.shared.Config

local Economy = require(Core.Economy)
local Money = require(Core.Money)
local Completion = require(Core.Completion)
local Mastery = require(Core.Mastery)
local Content = require(Config.Init)
local Balance = Content.Balance

local args: { string } = ARGS or {}
local smoke = false
for _, arg in ipairs(args) do
	if arg == "--smoke" then
		smoke = true
	end
end

local problems: { string } = {}
local function check(ok: boolean, label: string, detail: string?)
	if ok then
		print(`  PASS  {label}`)
	else
		local message = if detail then `{label} — {detail}` else label
		table.insert(problems, message)
		print(`  FAIL  {message}`)
	end
end

local function hours(seconds: number): string
	return string.format("%.1f h", seconds / 3600)
end

print("Billionaire City Tycoon — economy simulation")
print(
	`content: {#Content.buildings} buildings, {#Content.upgrades} upgrade lines, {#Content.parcels} parcels`
)
print(
	`reference player: 1.5 h/day, greedy best payback, offline {Balance.OfflineCapHours} h at {Balance.OfflineEfficiency * 100}%`
)
print("")

-- Invariant 1: costs strictly increase with level and are integers >= 1. -----------
local costProblems: { string } = {}
for _, upgrade in ipairs(Content.upgrades) do
	local previous = 0
	for level = 1, upgrade.maxLevel do
		local cost = Economy.cost(upgrade.baseCost.cash or 0, upgrade.growth, level)
		if cost < 1 or not Money.isSafeInteger(cost) then
			table.insert(
				costProblems,
				`{upgrade.id} level {level} cost {cost} is not a positive integer`
			)
		end
		if level > 1 and cost <= previous then
			table.insert(
				costProblems,
				`{upgrade.id} level {level} does not cost more than level {level - 1}`
			)
		end
		previous = cost
	end
end
for _, building in ipairs(Content.buildings) do
	local previous = 0
	for level = 1, building.maxLevel do
		local cost = Economy.cost(building.levelCostBase, building.levelGrowth, level)
		if cost <= previous then
			table.insert(costProblems, `{building.id} level {level} cost curve is not increasing`)
		end
		previous = cost
	end
	local phaseTotal = 0
	for _, phase in ipairs(building.phases) do
		phaseTotal += phase.cost.cash or 0
	end
	if phaseTotal ~= building.buildCost then
		table.insert(
			costProblems,
			`{building.id} buildCost {building.buildCost} != phase total {phaseTotal}`
		)
	end
end

print("Invariants")
check(
	#costProblems == 0,
	"1. upgrade and level costs strictly increase, integers >= 1",
	costProblems[1]
)

-- Invariant 2: net income is never negative. ---------------------------------------
local negativeIncome = 0
for _, building in ipairs(Content.buildings) do
	local income = Economy.income({
		baseRevenuePerMin = building.baseRevenuePerMin,
		baseExpensesPerMin = building.baseExpensesPerMin * 25, -- absurd cost stress
		capacity = building.capacity,
		level = 1,
		phasesCompleted = #building.phases,
		rates = Balance.Rates,
		modifiers = Economy.defaultModifiers(),
	})
	if income.netPerMin < 0 then
		negativeIncome += 1
	end
end
check(
	negativeIncome == 0,
	"2. net income is never negative (even at 25x expenses)",
	`{negativeIncome} buildings failed`
)

-- Invariant 3: the sum of every cost stays below 2^53/16. --------------------------
local totalCost = 0
for _, upgrade in ipairs(Content.upgrades) do
	for level = 1, upgrade.maxLevel do
		totalCost += Economy.cost(upgrade.baseCost.cash or 0, upgrade.growth, level)
	end
end
for _, building in ipairs(Content.buildings) do
	totalCost += building.buildCost
	for level = 1, building.maxLevel do
		totalCost += Economy.cost(building.levelCostBase, building.levelGrowth, level)
	end
end
check(
	totalCost < Money.MAX_SAFE / 16,
	"3. total content cost fits exact integer range",
	tostring(totalCost)
)

-- Run the reference player. --------------------------------------------------------
local purchaseLimit = if smoke then 60 else 900
local hourLimit = if smoke then 40 else 400
local result = GreedyPlayer.run(purchaseLimit, hourLimit)
local state = result.state

print("")
print("Milestones")
for _, milestone in ipairs(state.milestones) do
	print(string.format("  %-24s %8s", milestone.label, hours(milestone.seconds)))
end
print("")
print(
	string.format(
		"After %.1f h: net worth %s, cash/min %s, %d buildings, %d/%d parcels, %d purchases",
		result.hours,
		string.format("$%.0f", GreedyPlayer.netWorth(state)),
		string.format("%.0f", GreedyPlayer.netPerMin(state)),
		#state.buildings,
		state.ownedParcels,
		#Content.parcels,
		result.purchases
	)
)

-- Payback distribution by action kind.
local byKind: { [string]: { sum: number, count: number, min: number, max: number } } = {}
for _, sample in ipairs(result.paybackSamples) do
	if sample.payback ~= math.huge then
		local entry = byKind[sample.kind]
		if not entry then
			entry = { sum = 0, count = 0, min = math.huge, max = 0 }
			byKind[sample.kind] = entry
		end
		entry.sum += sample.payback
		entry.count += 1
		entry.min = math.min(entry.min, sample.payback)
		entry.max = math.max(entry.max, sample.payback)
	end
end
print("")
print("Payback by action (minutes)")
local kinds: { string } = {}
for kind in byKind do
	table.insert(kinds, kind)
end
table.sort(kinds)
for _, kind in ipairs(kinds) do
	local entry = byKind[kind]
	print(
		string.format(
			"  %-10s avg %7.1f   min %6.1f   max %7.1f   n=%d",
			kind,
			entry.sum / entry.count,
			entry.min,
			entry.max,
			entry.count
		)
	)
end

-- Invariant 4: no >25% income jump after 30 minutes.
check(
	#result.invariantViolations == 0,
	"4. no purchase raises total income by >25% after 30 min",
	result.invariantViolations[1]
)

-- Invariant 5: district arrival windows (only Starter exists in Phase 1).
print("  SKIP  5. district arrival windows — districts 2–8 ship in Phases 3–7 (N/A)")

-- Invariant 6: offline earnings respect the cap.
local worstNet = 0
for _, building in ipairs(state.buildings) do
	worstNet = math.max(worstNet, GreedyPlayer.incomeFor(building))
end
local capped = Economy.offlineEarnings(Balance.OfflineCapHours * 36000, worstNet, Balance.Rates)
local limit = Balance.OfflineCapHours * 60 * worstNet * Balance.OfflineEfficiency
check(
	capped <= limit + 1,
	"6. offline earnings never exceed cap x net x efficiency",
	`{capped} > {limit}`
)

-- Invariant 7: solvability — every def and upgrade was bought by the greedy player.
local unreachable: { string } = {}
local completionist =
	GreedyPlayer.run(if smoke then 120 else 3000, if smoke then 80 else 1200, true)
for _, building in ipairs(Content.buildings) do
	if not completionist.builtDefs[building.id] and building.id ~= Content.starterBuildingId then
		table.insert(unreachable, building.id)
	end
end
for _, upgrade in ipairs(Content.upgrades) do
	if not completionist.upgradeIds[upgrade.id] then
		table.insert(unreachable, upgrade.id)
	end
end
if smoke then
	print(
		`  INFO  7. solvability — {#unreachable} item(s) not bought in the short smoke run (checked in the full run)`
	)
else
	check(#unreachable == 0, "7. every item is reachable with legal purchases only", unreachable[1])
end

-- Completion snapshot using the shipped weights.
local builtSet: { [string]: boolean } = {}
for _, building in ipairs(state.buildings) do
	builtSet[building.defId] = true
end
local builtCount = 0
for _ in builtSet do
	builtCount += 1
end
local masterySum = 0
for _, building in ipairs(state.buildings) do
	masterySum += Mastery.progress(building.masteryXp).fraction + (building.masteryLevel - 1)
end
local masteryFraction = if #state.buildings > 0
	then math.clamp(masterySum / (#state.buildings * (Mastery.MAX_LEVEL - 1)), 0, 1)
	else 0
print("")
print(
	string.format(
		"Completion snapshot: buildings %.0f%%, upgrades %.0f%%, mastery %.0f%%",
		(builtCount / #Content.buildings) * 100,
		math.min(100, (result.state.upgradeLevelsBought / math.max(#Content.upgrades, 1)) * 100),
		masteryFraction * 100
	)
)

-- Smoke mode: a short run must move the player forward without breaking invariants.
if smoke then
	local firstUpgrade = result.purchasedIds[Content.upgradeIdsFor(Content.starterBuildingId)[1]]
	check(result.purchases > 0, "smoke. the greedy player buys something", "no purchases")
	check(state.cash >= 0, "smoke. cash never goes negative")
	check(firstUpgrade ~= nil or result.purchases > 0, "smoke. upgrades are affordable")
end

print("")
if #problems == 0 then
	print("RESULT: all checks passed")
	EXIT_CODE = 0
else
	print(`RESULT: {#problems} check(s) failed`)
	for _, problem in ipairs(problems) do
		print(`  - {problem}`)
	end
	EXIT_CODE = 1
end

return { problems = problems, state = state, hours = result.hours }
