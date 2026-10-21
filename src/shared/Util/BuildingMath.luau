--!strict
--[[
	One place that turns a profile's building data into income, prices and previews.

	Server services, the client's read-only mirror and the headless simulator all call
	these functions, so a price shown in the UI is by construction the price the server
	charges. Pure: no Roblox API, no state.
]]

local Core = script.Parent.Parent.Core
local Config = script.Parent.Parent.Config

local Economy = require(Core.Economy)
local Mastery = require(Core.Mastery)
local Types = require(Core.Types)
local Content = require(Config.Init)

local Balance = Content.Balance
local BuildingMath = {}

BuildingMath.rates = Balance.Rates

--[[ Upgrade-effect modifiers for one building instance. ]]
function BuildingMath.modifiers(
	defId: string,
	upgrades: { [string]: number },
	staff: { [string]: number }?,
	masteryLevel: number?
): Economy.Modifiers
	local mods = Economy.defaultModifiers()
	for _, upgradeId in ipairs(Content.upgradeIdsFor(defId)) do
		local level = upgrades[upgradeId] or 0
		if level > 0 then
			local upgrade = Content.upgradeById[upgradeId]
			mods = Economy.applyEffect(
				mods,
				upgrade.effect.stat,
				upgrade.effect.op,
				upgrade.effect.perLevel,
				level
			)
		end
	end
	if staff then
		for gradeId, count in staff do
			local grade = Content.staffById[gradeId]
			if grade and count > 0 then
				mods.staffWagesPerMin += grade.wagePerMin * count
				mods.revenueMult += Balance.Staff.revenuePerWorker * grade.efficiency * count
			end
		end
	end
	local mastery = masteryLevel or 1
	mods.revenueMult += Mastery.milestoneBonus(mastery, Balance.Mastery.milestones)
	return mods
end

--[[ Income breakdown for a building state (levels, phases and modifiers applied). ]]
function BuildingMath.income(def: Types.BuildingDef, state: Types.BuildingState): Economy.Income
	return Economy.income({
		baseRevenuePerMin = def.baseRevenuePerMin,
		baseExpensesPerMin = def.baseExpensesPerMin,
		capacity = def.capacity,
		level = state.level,
		phasesCompleted = state.phase,
		rates = Balance.Rates,
		modifiers = BuildingMath.modifiers(def.id, state.upg, state.staff, state.mastery.lvl),
	})
end

--[[ Net income of a fresh, fully built instance — the price anchor. ]]
function BuildingMath.baseIncome(def: Types.BuildingDef): number
	local probe: Types.BuildingState = {
		def = def.id,
		parcel = "",
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
	return math.max(1, BuildingMath.income(def, probe).netPerMin)
end

--[[ Dynamic price multiplier for upgrades, levels and hires on this building. ]]
function BuildingMath.priceScale(def: Types.BuildingDef, state: Types.BuildingState): number
	local current = BuildingMath.income(def, state).netPerMin
	return Economy.incomeScale(current, BuildingMath.baseIncome(def))
end

function BuildingMath.isOperational(state: Types.BuildingState): boolean
	local def = Content.buildingById[state.def]
	if not def then
		return false
	end
	return state.constructing == nil and state.phase >= #def.phases
end

--[[ Price of the next level of an upgrade line. ]]
function BuildingMath.upgradeCost(
	def: Types.BuildingDef,
	state: Types.BuildingState,
	upgradeId: string
): number
	local upgrade = Content.upgradeById[upgradeId]
	if not upgrade then
		return math.huge
	end
	local level = state.upg[upgradeId] or 0
	return Economy.scaledCost(
		upgrade.baseCost.cash or 0,
		upgrade.growth,
		level + 1,
		BuildingMath.priceScale(def, state)
	)
end

--[[ Price of the next building level. ]]
function BuildingMath.levelCost(def: Types.BuildingDef, state: Types.BuildingState): number
	if state.level >= def.maxLevel then
		return math.huge
	end
	return Economy.scaledCost(
		def.levelCostBase,
		def.levelGrowth,
		state.level + 1,
		BuildingMath.priceScale(def, state)
	)
end

--[[ Price of hiring one worker of `gradeId` for this building. ]]
function BuildingMath.staffCost(
	def: Types.BuildingDef,
	state: Types.BuildingState,
	gradeId: string
): number
	local grade = Content.staffById[gradeId]
	if not grade then
		return math.huge
	end
	return math.max(1, math.floor(grade.hireCost * BuildingMath.priceScale(def, state) + 0.5))
end

--[[
	Preview of the income change from buying one more level of `upgradeId`.
	Used by the UI ("net now -> net after") and by the simulator.
]]
function BuildingMath.previewUpgrade(
	def: Types.BuildingDef,
	state: Types.BuildingState,
	upgradeId: string
): Economy.Income
	local upgrade = Content.upgradeById[upgradeId]
	local copy: Types.BuildingState = table.clone(state)
	copy.upg = table.clone(state.upg)
	copy.staff = table.clone(state.staff)
	copy.upg[upgradeId] = (copy.upg[upgradeId] or 0) + 1
	return BuildingMath.income(def, copy)
end

--[[ Net worth contribution of a building: land is counted separately. ]]
function BuildingMath.investedValue(def: Types.BuildingDef, state: Types.BuildingState): number
	local total = Content.totalBuildCost(def)
	for upgradeId, level in state.upg do
		local upgrade = Content.upgradeById[upgradeId]
		if upgrade then
			total += Economy.totalCost(upgrade.baseCost.cash or 0, upgrade.growth, 1, level)
		end
	end
	for gradeId, count in state.staff do
		local grade = Content.staffById[gradeId]
		if grade then
			total += grade.hireCost * count
		end
	end
	if state.manager then
		total += def.managerCost
	end
	return total
end

--[[ Mastery XP earned from cash collected / spent on this building. ]]
function BuildingMath.masteryXpForCash(cash: number, kind: "collect" | "spend"): number
	local rate = if kind == "collect"
		then Balance.Mastery.xpPerCashCollected
		else Balance.Mastery.xpPerCashSpent
	return math.max(0, cash) * rate
end

return BuildingMath
