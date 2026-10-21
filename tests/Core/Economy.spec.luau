--!strict
local Framework = require(script.Parent.Parent.Framework)
local Economy = require(script.Parent.Parent.Parent.src.shared.Core.Economy)
local Money = require(script.Parent.Parent.Parent.src.shared.Core.Money)

local rates = Economy.defaultRates()

Framework.test("cost curve is strictly increasing, integral and >= 1", function()
	local previous = 0
	for level = 1, 60 do
		local value = Economy.cost(10, 1.16, level)
		Framework.isTrue(Money.isSafeInteger(value), `cost at level {level} is a safe integer`)
		Framework.greaterThan(value, previous - 1, `cost at level {level} grows`)
		previous = value
	end
	Framework.equal(Economy.cost(0, 1.2, 1), 1, "zero base still costs 1")
	Framework.equal(Economy.cost(10, 1.2, 0), 10, "level < 1 uses base")
end)

Framework.test("totalCost sums the requested levels", function()
	local total = Economy.totalCost(100, 1.1, 1, 3)
	Framework.equal(total, 100 + 110 + 121)
	Framework.equal(Economy.totalCost(100, 1.1, 3, 2), 0)
end)

Framework.test("income never goes negative even with heavy expenses", function()
	local income = Economy.income({
		baseRevenuePerMin = 100,
		baseExpensesPerMin = 500,
		capacity = 10,
		level = 1,
		phasesCompleted = 2,
		rates = rates,
		modifiers = Economy.defaultModifiers(),
	})
	Framework.greaterThan(income.netPerMin, 0, "net income stays positive")
	Framework.near(
		income.netPerMin,
		income.grossPerMin * rates.minNetFraction,
		1e-6,
		"net floors at 20% of gross"
	)
end)

Framework.test("income grows with level, phases and modifiers", function()
	local base = Economy.income({
		baseRevenuePerMin = 300,
		baseExpensesPerMin = 90,
		capacity = 60,
		level = 1,
		phasesCompleted = 2,
		rates = rates,
		modifiers = Economy.defaultModifiers(),
	})
	local upgraded = Economy.defaultModifiers()
	upgraded.revenueMult = 1.5
	upgraded.capacityBonus = 20
	local better = Economy.income({
		baseRevenuePerMin = 300,
		baseExpensesPerMin = 90,
		capacity = 60,
		level = 2,
		phasesCompleted = 2,
		rates = rates,
		modifiers = upgraded,
	})
	Framework.greaterThan(better.netPerMin, base.netPerMin, "net income rises")
	Framework.greaterThan(better.grossPerMin, base.grossPerMin, "gross revenue rises")
	Framework.near(base.grossPerMin, 300 * (1 + 0.15 * 2), 1e-6, "phase bonus applies")
end)

Framework.test("capacity upgrades raise revenue at constant average spend", function()
	local mods = Economy.defaultModifiers()
	mods.capacityBonus = 60
	local boosted = Economy.income({
		baseRevenuePerMin = 300,
		baseExpensesPerMin = 90,
		capacity = 60,
		level = 1,
		phasesCompleted = 0,
		rates = rates,
		modifiers = mods,
	})
	Framework.near(boosted.avgSpend, 5, 1e-9)
	Framework.near(boosted.grossPerMin, 600, 1e-6, "double capacity doubles revenue")
end)

Framework.test("applyEffect accumulates additive and multiplicative effects", function()
	local mods = Economy.defaultModifiers()
	mods = Economy.applyEffect(mods, "revenue", "add", 0.06, 5)
	Framework.near(mods.revenueMult, 1.3, 1e-9)
	mods = Economy.applyEffect(mods, "revenue", "mult", 0.1, 2)
	Framework.near(mods.revenueMult, 1.56, 1e-9)
	mods = Economy.applyEffect(mods, "capacity", "add", 4, 3)
	Framework.near(mods.capacityBonus, 12)
	mods = Economy.applyEffect(mods, "expense", "add", -0.04, 2)
	Framework.near(mods.expenseMult, 0.92, 1e-9)
	local unchanged = Economy.applyEffect(mods, "revenue", "add", 0.5, 0)
	Framework.near(unchanged.revenueMult, mods.revenueMult)
end)

Framework.test("payback reports infinity for non-income upgrades", function()
	Framework.near(Economy.payback(100, 50).minutes, 2)
	Framework.isTrue(Economy.payback(100, 0).infinite, "no delta -> infinite payback")
	Framework.isTrue(Economy.payback(0, 10).infinite, "free upgrade -> no payback")
end)

Framework.test("offline earnings are capped by hours and efficiency", function()
	local perMinute = 120
	local earned = Economy.offlineEarnings(10 * 3600, perMinute, rates)
	local expected = rates.offlineCapHours * 60 * perMinute * rates.offlineEfficiency
	Framework.near(earned, expected, 1, "capped at 4h x 50%")
	Framework.equal(
		Economy.offlineEarnings(-100, perMinute, rates),
		0,
		"clock rollback earns nothing"
	)
	Framework.equal(Economy.offlineEarnings(3600, 0, rates), 0, "no income -> nothing")
	Framework.equal(Economy.offlineEarnings(0 / 0, perMinute, rates), 0, "NaN elapsed")
end)

Framework.test("happiness multiplier stays inside its band", function()
	Framework.near(Economy.happinessMultiplier(0, rates), rates.happinessMin)
	Framework.near(Economy.happinessMultiplier(100, rates), rates.happinessMax)
	Framework.near(Economy.happinessMultiplier(50, rates), 1.05, 1e-9)
	Framework.near(Economy.happinessMultiplier(500, rates), rates.happinessMax)
end)

Framework.test("net worth adds cost basis to cash and never goes negative", function()
	local worth = Economy.netWorth({
		cash = 500,
		landCostBasis = 300,
		buildCostBasis = 1300,
		upgradeCostBasis = 200,
		assetValue = 0,
	})
	Framework.equal(worth, 2300)
	Framework.equal(
		Economy.netWorth({
			cash = -500,
			landCostBasis = 0,
			buildCostBasis = 0,
			upgradeCostBasis = 0,
			assetValue = -100,
		}),
		0
	)
end)
