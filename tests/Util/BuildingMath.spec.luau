--!strict
--[[
	Pricing and income math used by the server, the UI and the simulator.

	These tests deliberately go through *content* rather than made-up numbers, so a data
	edit that breaks the shape of an upgrade line fails here first.
]]

local Framework = require(script.Parent.Parent.Framework)
local Content = require(script.Parent.Parent.Parent.src.shared.Config.Init)
local Types = require(script.Parent.Parent.Parent.src.shared.Core.Types)
local BuildingMath = require(script.Parent.Parent.Parent.src.shared.Util.BuildingMath)

local def: Types.BuildingDef = Content.buildingById["convenience_store"]

local function state(overrides: { [string]: any }?): Types.BuildingState
	local base: Types.BuildingState = {
		def = def.id,
		parcel = "starter_01",
		level = 1,
		phase = #def.phases,
		upg = {},
		mastery = { xp = 0, lvl = 1, windowStart = 0, windowXp = 0 },
		staff = {},
		manager = nil,
		constructing = nil,
		pending = 0,
		lastAccrual = 0,
	}
	for key, value in overrides or {} do
		(base :: any)[key] = value
	end
	return base
end

Framework.test("the starter building exists and has phases", function()
	Framework.isTrue(def ~= nil)
	Framework.isTrue(#def.phases >= 1)
	Framework.isTrue(def.baseRevenuePerMin > 0)
	Framework.isTrue(def.baseExpensesPerMin > 0)
end)

Framework.test("a fresh building is operational", function()
	Framework.isTrue(BuildingMath.isOperational(state()))
	local midBuild = state({ phase = 1, constructing = { phase = 2, startedAt = 0, seconds = 10 } })
	Framework.isFalse(BuildingMath.isOperational(midBuild))
end)

Framework.test("income splits into gross, expenses and net", function()
	local income = BuildingMath.income(def, state())
	Framework.isTrue(income.grossPerMin > 0)
	Framework.isTrue(income.expensesPerMin > 0)
	Framework.near(income.netPerMin, income.grossPerMin - income.expensesPerMin, 1e-6)
	Framework.isTrue(
		income.netPerMin >= income.grossPerMin * Content.Balance.Rates.minNetFraction - 1e-6
	)
end)

Framework.test("a level raises income and costs more", function()
	local lvl1 = BuildingMath.income(def, state())
	local lvl5 = BuildingMath.income(def, state({ level = 5 }))
	Framework.isTrue(lvl5.netPerMin > lvl1.netPerMin)
	Framework.isTrue(BuildingMath.levelCost(def, state({ level = 1 })) > 0)
end)

Framework.test("level cost grows with level", function()
	local first = BuildingMath.levelCost(def, state({ level = 1 }))
	local second = BuildingMath.levelCost(def, state({ level = 2 }))
	Framework.isTrue(second > first)
end)

Framework.test("max level has no price", function()
	Framework.equal(BuildingMath.levelCost(def, state({ level = def.maxLevel })), math.huge)
end)

Framework.test("every generated upgrade line is priced and purchasable", function()
	local ids = Content.upgradeIdsFor(def.id)
	Framework.isTrue(#ids > 0, "generated upgrade lines")
	local grouped = Content.upgradesByCategory(def.id)
	local categories = 0
	for _, lines in grouped do
		if #lines > 0 then
			categories += 1
		end
	end
	Framework.equal(categories, 6, "all six categories have lines")

	for _, id in ipairs(ids) do
		local upgrade = Content.upgradeById[id]
		Framework.isTrue(upgrade ~= nil, id)
		Framework.equal(upgrade.buildingId, def.id, "line belongs to building")
		Framework.isTrue(upgrade.maxLevel > 0, "line has levels")
		Framework.isTrue(BuildingMath.upgradeCost(def, state(), id) > 0, "line has a price")
	end
end)

Framework.test("an upgrade changes income in the expected direction", function()
	local id = Content.upgradeIdsFor(def.id)[1]
	local upgrade = Content.upgradeById[id]
	local before = BuildingMath.income(def, state()).netPerMin
	local after = BuildingMath.previewUpgrade(def, state(), id).netPerMin
	if upgrade.effect.stat == "expense" then
		Framework.isTrue(after > before, "cheaper expenses raise net")
	elseif upgrade.effect.stat == "revenue" or upgrade.effect.stat == "capacity" then
		Framework.isTrue(after > before, "more revenue/capacity raises net")
	elseif upgrade.effect.stat == "staffSlots" then
		Framework.near(after, before, 1e-6, "slots alone do not change income")
	elseif upgrade.effect.stat == "masteryXp" then
		Framework.near(after, before, 1e-6, "mastery XP alone does not change income")
	end
end)

Framework.test("upgrade prices rise with level and with income", function()
	local id = Content.upgradeIdsFor(def.id)[1]
	local cheap = BuildingMath.upgradeCost(def, state(), id)
	local levelled = state({ upg = { [id] = 3 } })
	local expensive = BuildingMath.upgradeCost(def, levelled, id)
	Framework.isTrue(expensive > cheap)
end)

Framework.test("staff add revenue and wages", function()
	local base = BuildingMath.income(def, state())
	local staffed = BuildingMath.income(def, state({ staff = { Basic = 1 } }))
	Framework.isTrue(staffed.grossPerMin > base.grossPerMin, "revenue bonus")
	Framework.isTrue(staffed.expensesPerMin > base.expensesPerMin, "wages are an expense")
end)

Framework.test("mastery milestones raise revenue", function()
	local level1 = BuildingMath.income(def, state()).grossPerMin
	local level5 = BuildingMath.income(
		def,
		state({ mastery = { xp = 0, lvl = 5, windowStart = 0, windowXp = 0 } })
	).grossPerMin
	Framework.isTrue(level5 > level1)
end)

Framework.test("hiring costs scale with the building's income", function()
	local small = BuildingMath.staffCost(def, state(), "Basic")
	local big = BuildingMath.staffCost(def, state({ level = 6 }), "Basic")
	Framework.isTrue(big >= small)
	Framework.isTrue(small > 0)
	Framework.equal(BuildingMath.staffCost(def, state(), "Nonexistent"), math.huge)
end)

Framework.test("invested value never decreases and covers build cost", function()
	local fresh = BuildingMath.investedValue(def, state())
	Framework.isTrue(fresh >= Content.totalBuildCost(def))
	local upgraded =
		BuildingMath.investedValue(def, state({ upg = { [Content.upgradeIdsFor(def.id)[1]] = 2 } }))
	Framework.isTrue(upgraded > fresh)
end)

Framework.test("mastery XP scales with cash and kind", function()
	Framework.equal(BuildingMath.masteryXpForCash(-10, "collect"), 0)
	Framework.isTrue(BuildingMath.masteryXpForCash(100, "collect") > 0)
	Framework.isTrue(BuildingMath.masteryXpForCash(100, "spend") > 0)
end)

Framework.test("prices stay exact integers inside 2^53", function()
	for _, building in ipairs(Content.buildings) do
		local probe = state({ def = building.id, phase = #building.phases })
		for _, id in ipairs(Content.upgradeIdsFor(building.id)) do
			local cost = BuildingMath.upgradeCost(building, probe, id)
			Framework.isTrue(cost == math.floor(cost), "integer cost")
			Framework.isTrue(cost < 2 ^ 53, "cost inside exact range")
		end
	end
end)
