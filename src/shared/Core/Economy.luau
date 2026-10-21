--!strict
--[[
	Pure economy math: cost curves, revenue, expenses, payback and offline income.

	Every number here is derived from content data passed in by the caller; the module
	holds no game-specific constants. `Config/Balance` supplies `Rates`, which keeps the
	GDD's tunables in exactly one place.

	Invariants implemented here (Appendix B5):
	  1. `cost()` is strictly increasing in level and returns integers >= 1.
	  2. `netPerMin()` is never negative (floor of 20% of gross by default).
	  6. `offlineEarnings()` never exceeds cap * net/min * efficiency.
]]

local Money = require(script.Parent.Money)

local Economy = {}

export type Rates = {
	levelIncomeGrowth: number, -- income multiplier per building level
	levelExpenseGrowth: number, -- expense multiplier per building level
	minNetFraction: number, -- net profit floor as a fraction of gross
	offlineCapHours: number,
	offlineEfficiency: number,
	happinessMin: number,
	happinessMax: number,
}

export type Modifiers = {
	revenueMult: number, -- upgrades, marketing, ...
	expenseMult: number,
	capacityBonus: number, -- additive customers per minute
	staffWagesPerMin: number, -- additive operating cost
	happinessMult: number,
	cityMult: number,
	eventMult: number,
	masteryXpMult: number,
}

--[[ Rates matching the documented defaults in Appendix B5. ]]
function Economy.defaultRates(): Rates
	return {
		levelIncomeGrowth = 1.18,
		levelExpenseGrowth = 1.06,
		minNetFraction = 0.2,
		offlineCapHours = 4,
		offlineEfficiency = 0.5,
		happinessMin = 0.9,
		happinessMax = 1.2,
	}
end

function Economy.defaultModifiers(): Modifiers
	return {
		revenueMult = 1,
		expenseMult = 1,
		capacityBonus = 0,
		staffWagesPerMin = 0,
		happinessMult = 1,
		cityMult = 1,
		eventMult = 1,
		masteryXpMult = 1,
	}
end

--[[ Applies one upgrade line's effect at `level` to a modifier table (returns a copy). ]]
function Economy.applyEffect(
	modifiers: Modifiers,
	stat: string,
	op: string,
	perLevel: number,
	level: number
): Modifiers
	local nextMods: Modifiers = table.clone(modifiers)
	if level <= 0 then
		return nextMods
	end
	local total = perLevel * level
	if op == "ad" or op == "add" then
		if stat == "revenue" then
			nextMods.revenueMult += total
		elseif stat == "expense" then
			nextMods.expenseMult += total
		elseif stat == "capacity" then
			nextMods.capacityBonus += total
		elseif stat == "staffSlots" then
			-- staffing capacity is consumed by StaffService, not economy math
		elseif stat == "masteryXp" then
			nextMods.masteryXpMult += total
		end
	else
		local factor = 1 + total
		if stat == "revenue" then
			nextMods.revenueMult *= factor
		elseif stat == "expense" then
			nextMods.expenseMult *= factor
		elseif stat == "capacity" then
			nextMods.capacityBonus *= factor
		elseif stat == "masteryXp" then
			nextMods.masteryXpMult *= factor
		end
	end
	return nextMods
end

--[[
	Cost of buying level `level` of a line whose first level costs `baseCost`
	and which grows by `growth` per level. Always an integer >= 1.
]]
function Economy.cost(baseCost: number, growth: number, level: number): number
	if level < 1 then
		return math.max(1, Money.round(baseCost))
	end
	local raw = baseCost * (growth ^ (level - 1))
	if raw ~= raw or raw > Money.MAX_SAFE then
		return Money.MAX_SAFE
	end
	return math.max(1, Money.round(raw))
end

--[[ Sum of costs for levels `fromLevel` .. `toLevel` (inclusive), saturating. ]]
function Economy.totalCost(
	baseCost: number,
	growth: number,
	fromLevel: number,
	toLevel: number
): number
	local sum = 0
	for level = fromLevel, toLevel do
		sum += Economy.cost(baseCost, growth, level)
		if sum >= Money.MAX_SAFE then
			return Money.MAX_SAFE
		end
	end
	return sum
end

--[[
	Income scale factor for dynamic pricing.

	Percentage upgrades mean an upgrade's value grows with the building's income. If the
	price stayed absolute, a mature business would be upgraded for pocket change and the
	early game would snowball (the failure mode Appendix B5's payback bands exist to
	prevent). Prices therefore scale linearly with the building's current income, which
	keeps every purchase's payback inside its tier band at every stage of the game.

	The scale is clamped so a building recovering from a temporary modifier can never be
	punished with a runaway price, and so it never discounts below the content price.
]]
function Economy.incomeScale(currentNetPerMin: number, baseNetPerMin: number): number
	if currentNetPerMin ~= currentNetPerMin or baseNetPerMin <= 0 then
		return 1
	end
	return math.clamp(currentNetPerMin / baseNetPerMin, 1, 1e6)
end

--[[ Content price adjusted by an income scale. Always a positive integer. ]]
function Economy.scaledCost(baseCost: number, growth: number, level: number, scale: number): number
	local base = Economy.cost(baseCost, growth, level)
	local factor = if Money.isFinite(scale) then math.clamp(scale, 1, 1e6) else 1
	local scaled = base * factor
	if scaled ~= scaled or scaled > Money.MAX_SAFE then
		return Money.MAX_SAFE
	end
	return math.max(1, Money.round(scaled))
end

export type IncomeArgs = {
	baseRevenuePerMin: number,
	baseExpensesPerMin: number,
	capacity: number,
	level: number,
	phasesCompleted: number,
	rates: Rates,
	modifiers: Modifiers,
}

export type Income = {
	grossPerMin: number,
	expensesPerMin: number,
	netPerMin: number,
	customersPerMin: number,
	avgSpend: number,
}

--[[
	Full income breakdown for one building.

	`revenue = min(traffic, capacity) * avgSpend`, expressed per minute. Capacity
	upgrades raise the customer ceiling; revenue upgrades raise the average spend.
]]
function Economy.income(args: IncomeArgs): Income
	local rates = args.rates
	local mods = args.modifiers
	local levelIndex = math.max(1, args.level or 1)
	local levelMult = rates.levelIncomeGrowth ^ (levelIndex - 1)
	local expenseMult = rates.levelExpenseGrowth ^ (levelIndex - 1)

	local baseCustomers = math.max(args.capacity, 1)
	local avgSpend = args.baseRevenuePerMin / baseCustomers
	local customers = baseCustomers * levelMult + mods.capacityBonus
	local phaseMult = 1 + 0.15 * math.max(0, args.phasesCompleted or 0)
	local gross = customers
		* avgSpend
		* mods.revenueMult
		* phaseMult
		* mods.happinessMult
		* mods.cityMult
		* mods.eventMult

	local expenses = (args.baseExpensesPerMin * expenseMult * mods.expenseMult)
		+ mods.staffWagesPerMin
	local floorNet = gross * rates.minNetFraction
	local net = math.max(gross - expenses, floorNet)
	net = math.max(net, 0)
	gross = math.max(gross, 0)
	expenses = math.max(expenses, 0)

	return {
		grossPerMin = gross,
		expensesPerMin = expenses,
		netPerMin = net,
		customersPerMin = customers,
		avgSpend = avgSpend,
	}
end

export type Payback = {
	minutes: number,
	-- true when the upgrade cannot repay itself because it does not raise net income
	infinite: boolean,
}

--[[ Payback time in minutes for `cost` raising net income by `deltaNetPerMin`. ]]
function Economy.payback(cost: number, deltaNetPerMin: number): Payback
	if deltaNetPerMin <= 0 or cost <= 0 then
		return { minutes = math.huge, infinite = true }
	end
	return { minutes = cost / deltaNetPerMin, infinite = false }
end

--[[
	Offline earnings for a building.

	`elapsedSeconds` is `now - lastSaved`; it is clamped to the cap *and* to the
	elapsed real time, so a clock rollback can never mint money.
]]
function Economy.offlineEarnings(elapsedSeconds: number, netPerMin: number, rates: Rates): number
	if elapsedSeconds ~= elapsedSeconds or elapsedSeconds <= 0 or netPerMin <= 0 then
		return 0
	end
	local capped = math.min(elapsedSeconds, rates.offlineCapHours * 3600)
	local earned = (capped / 60) * netPerMin * rates.offlineEfficiency
	return math.max(0, Money.round(earned))
end

--[[ Happiness multiplier derived from a 0..100 happiness score, clamped to [0.9, 1.2]. ]]
function Economy.happinessMultiplier(happiness: number, rates: Rates): number
	local score = math.clamp(happiness, 0, 100) / 100
	return math.clamp(
		rates.happinessMin + (rates.happinessMax - rates.happinessMin) * score,
		rates.happinessMin,
		rates.happinessMax
	)
end

--[[ Net worth = cash + invested cost basis (land, builds, upgrades) + asset value. ]]
function Economy.netWorth(args: {
	cash: number,
	landCostBasis: number,
	buildCostBasis: number,
	upgradeCostBasis: number,
	assetValue: number,
}): number
	local total = args.cash
		+ args.landCostBasis
		+ args.buildCostBasis
		+ args.upgradeCostBasis
		+ args.assetValue
	return math.clamp(total, 0, Money.MAX_SAFE)
end

--[[
	Total income per minute for a set of active buildings (construction still earns
	nothing until the first phase completes). Used by HUD, completion and the sim.
]]
function Economy.totalNetPerMin(values: { number }): number
	local total = 0
	for _, value in ipairs(values) do
		total += value
	end
	return total
end

return Economy
