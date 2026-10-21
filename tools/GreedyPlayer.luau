--!strict
--[[
	Greedy player simulation engine (tooling only, never shipped to Roblox).

	Model from Appendix B5: a player who always buys the best payback available,
	plays ~1.5 h per day and collects offline income at each session start.
	Used by `economy_sim.luau` (balance) and `content_validate.luau` (reachability).
]]

local root = script.Parent.Parent :: any
local Core = root.src.shared.Core
local Config = root.src.shared.Config

local Economy = require(Core.Economy)
local Mastery = require(Core.Mastery)
local Money = require(Core.Money)
local Content = require(Config.Init)
local Parcels = require(Config.Parcels)

local Balance = Content.Balance
local rates = Economy.defaultRates()

export type BuildingState = {
	defId: string,
	parcelId: string,
	level: number,
	upgrades: { [string]: number },
	staff: { [string]: number },
	manager: boolean,
	operationalAt: number,
	masteryXp: number,
	masteryLevel: number,
	windowStart: number,
	windowXp: number,
}

export type SimState = {
	now: number, -- seconds of simulated time
	playSeconds: number,
	cash: number,
	lastSessionStart: number,
	buildings: { BuildingState },
	parcels: { string },
	ownedParcels: number,
	upgradesPurchased: number,
	upgradeLevelsBought: number,
	staffHired: number,
	managersHired: number,
	cashCollected: number,
	spentCash: number,
	lifetimeEarned: number,
	lifetimeOffline: number,
	netEarned: number,
	optionsSeen: { [string]: boolean },
	violations: { string },
	milestones: { { label: string, seconds: number } },
}

export type Option = {
	kind: string,
	label: string,
	id: string,
	cost: number,
	deltaNetPerMin: number,
	apply: (state: SimState) -> (),
	requires: string?, -- content id that must be "purchased" earlier (def or upgrade id)
}

local GreedyPlayer = {}

GreedyPlayer.SESSION_SECONDS = 90 * 60 -- 1.5 h per day
GreedyPlayer.OFFLINE_GAP_SECONDS = 24 * 3600
GreedyPlayer.MAX_HOURS = 200

local function newBuilding(defId: string, parcelId: string, at: number): BuildingState
	return {
		defId = defId,
		parcelId = parcelId,
		level = 1,
		upgrades = {},
		staff = {},
		manager = false,
		operationalAt = at,
		masteryXp = 0,
		masteryLevel = 1,
		windowStart = at,
		windowXp = 0,
	}
end

function GreedyPlayer.newState(): SimState
	local state: SimState = {
		now = 0,
		playSeconds = 0,
		cash = Balance.AutoloadDelaySeconds * 0 + 500,
		lastSessionStart = 0,
		buildings = {},
		parcels = { Content.starterParcelId },
		ownedParcels = 1,
		upgradesPurchased = 0,
		upgradeLevelsBought = 0,
		staffHired = 0,
		managersHired = 0,
		cashCollected = 0,
		spentCash = 0,
		lifetimeEarned = 0,
		lifetimeOffline = 0,
		netEarned = 0,
		optionsSeen = {},
		violations = {},
		milestones = {},
	}
	-- A new player owns the starter parcel with a finished Convenience Store.
	local def = Content.buildingById[Content.starterBuildingId]
	state.buildings[1] = newBuilding(def.id, Content.starterParcelId, 0)
	return state
end

function GreedyPlayer.isOperational(building: BuildingState, now: number): boolean
	return now >= building.operationalAt
end

function GreedyPlayer.modifiersFor(building: BuildingState): Economy.Modifiers
	local mods = Economy.defaultModifiers()
	local def = Content.buildingById[building.defId]
	for _, upgradeId in ipairs(Content.upgradeIdsFor(def.id)) do
		local level = building.upgrades[upgradeId] or 0
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
	for gradeId, count in building.staff do
		local grade = Content.staffById[gradeId]
		mods.staffWagesPerMin += grade.wagePerMin * count
		mods.revenueMult += Balance.Staff.revenuePerWorker * grade.efficiency * count
	end
	mods.revenueMult += Mastery.milestoneBonus(building.masteryLevel, Balance.Mastery.milestones)
	return mods
end

--[[ Net income of the same building with no upgrades and no staff (the price anchor). ]]
function GreedyPlayer.baseIncomeFor(defId: string): number
	local def = Content.buildingById[defId]
	local income = Economy.income({
		baseRevenuePerMin = def.baseRevenuePerMin,
		baseExpensesPerMin = def.baseExpensesPerMin,
		capacity = def.capacity,
		level = 1,
		phasesCompleted = #def.phases,
		rates = rates,
		modifiers = Economy.defaultModifiers(),
	})
	return math.max(income.netPerMin, 1)
end

--[[ Price multiplier applied to every upgrade, level and hire on a building. ]]
function GreedyPlayer.priceScaleFor(building: BuildingState): number
	return Economy.incomeScale(
		GreedyPlayer.incomeFor(building),
		GreedyPlayer.baseIncomeFor(building.defId)
	)
end

function GreedyPlayer.incomeFor(building: BuildingState): number
	local def = Content.buildingById[building.defId]
	if not def then
		return 0
	end
	local income = Economy.income({
		baseRevenuePerMin = def.baseRevenuePerMin,
		baseExpensesPerMin = def.baseExpensesPerMin,
		capacity = def.capacity,
		level = building.level,
		phasesCompleted = #def.phases,
		rates = rates,
		modifiers = GreedyPlayer.modifiersFor(building),
	})
	return income.netPerMin
end

function GreedyPlayer.netPerMin(state: SimState): number
	local total = 0
	for _, building in ipairs(state.buildings) do
		if GreedyPlayer.isOperational(building, state.now) then
			total += GreedyPlayer.incomeFor(building)
		end
	end
	return total
end

function GreedyPlayer.landCostBasis(state: SimState): number
	local total = 0
	for _, parcelId in ipairs(state.parcels) do
		local def = Content.parcelById[parcelId]
		if def then
			total += def.landCost
		end
	end
	return total
end

function GreedyPlayer.netWorth(state: SimState): number
	local buildBasis = 0
	local upgradeBasis = 0
	for _, building in ipairs(state.buildings) do
		local def = Content.buildingById[building.defId]
		buildBasis += Content.totalBuildCost(def)
		for upgradeId, level in building.upgrades do
			local upgrade = Content.upgradeById[upgradeId]
			for index = 1, level do
				upgradeBasis += Economy.cost(upgrade.baseCost.cash or 0, upgrade.growth, index)
			end
		end
	end
	return Economy.netWorth({
		cash = state.cash,
		landCostBasis = GreedyPlayer.landCostBasis(state),
		buildCostBasis = buildBasis,
		upgradeCostBasis = upgradeBasis,
		assetValue = 0,
	})
end

local function emptyParcels(state: SimState): { string }
	local used: { [string]: boolean } = {}
	for _, building in ipairs(state.buildings) do
		used[building.parcelId] = true
	end
	local free: { string } = {}
	for _, parcelId in ipairs(state.parcels) do
		if not used[parcelId] then
			table.insert(free, parcelId)
		end
	end
	return free
end

local function nextParcel(state: SimState): any
	local owned: { [string]: boolean } = {}
	for _, id in ipairs(state.parcels) do
		owned[id] = true
	end
	for _, def in ipairs(Content.parcels) do
		if not owned[def.id] then
			return def
		end
	end
	return nil
end

--[[ Builds every legal option for the current state. ]]
function GreedyPlayer.options(state: SimState, preferUnseen: boolean?): { Option }
	local options: { Option } = {}
	local currentNet = GreedyPlayer.netPerMin(state)

	-- Upgrades on operational buildings.
	for index, building in ipairs(state.buildings) do
		local def = Content.buildingById[building.defId]
		if not GreedyPlayer.isOperational(building, state.now) then
			continue
		end
		for _, upgradeId in ipairs(Content.upgradeIdsFor(def.id)) do
			local upgrade = Content.upgradeById[upgradeId]
			local level = building.upgrades[upgradeId] or 0
			if level >= upgrade.maxLevel then
				continue
			end
			local scale = GreedyPlayer.priceScaleFor(building)
			local cost =
				Economy.scaledCost(upgrade.baseCost.cash or 0, upgrade.growth, level + 1, scale)
			local before = GreedyPlayer.incomeFor(building)
			local savedLevel = building.upgrades[upgradeId]
			building.upgrades[upgradeId] = level + 1
			local after = GreedyPlayer.incomeFor(building)
			building.upgrades[upgradeId] = savedLevel
			local delta = after - before
			-- Mastery-XP upgrades do not change income but are still legal purchases.
			if delta > 0 or upgrade.effect.stat == "masteryXp" then
				table.insert(options, {
					kind = "upgrade",
					label = `{def.name}: {upgrade.name} {level + 1}`,
					id = upgradeId,
					cost = cost,
					deltaNetPerMin = delta,
					requires = upgradeId,
					apply = function(target: SimState)
						local targetBuilding = target.buildings[index]
						targetBuilding.upgrades[upgradeId] = (
							targetBuilding.upgrades[upgradeId] or 0
						) + 1
						target.upgradesPurchased += 1
						target.upgradeLevelsBought += 1
						target.optionsSeen[upgradeId] = true
					end,
				})
			end
		end

		-- Building level.
		if building.level < def.maxLevel then
			local cost = Economy.scaledCost(
				def.levelCostBase,
				def.levelGrowth,
				building.level + 1,
				GreedyPlayer.priceScaleFor(building)
			)
			local before = GreedyPlayer.incomeFor(building)
			building.level += 1
			local after = GreedyPlayer.incomeFor(building)
			building.level -= 1
			if after - before > 0 then
				table.insert(options, {
					kind = "level",
					label = `{def.name}: level {building.level + 1}`,
					id = `{def.id}:level`,
					cost = cost,
					deltaNetPerMin = after - before,
					requires = `{def.id}:level`,
					apply = function(target: SimState)
						target.buildings[index].level += 1
						target.upgradesPurchased += 1
					end,
				})
			end
		end

		-- Staff.
		local slots = 0
		for _, count in building.staff do
			slots += count
		end
		local capacity = def.staffSlots
		if slots < capacity then
			for _, gradeId in ipairs({ "Basic", "Skilled", "Expert", "Executive" }) do
				local grade = Content.staffById[gradeId]
				if grade then
					local before = GreedyPlayer.incomeFor(building)
					building.staff[gradeId] = (building.staff[gradeId] or 0) + 1
					local after = GreedyPlayer.incomeFor(building)
					building.staff[gradeId] -= 1
					if (building.staff[gradeId] or 0) <= 0 then
						building.staff[gradeId] = nil
					end
					if after - before > 0 then
						table.insert(options, {
							kind = "staff",
							label = `{def.name}: hire {grade.name}`,
							id = `{def.id}:staff:{gradeId}`,
							cost = math.max(
								1,
								Money.round(grade.hireCost * GreedyPlayer.priceScaleFor(building))
							),
							deltaNetPerMin = after - before,
							requires = `{def.id}:staff:{gradeId}`,
							apply = function(target: SimState)
								local targetBuilding = target.buildings[index]
								targetBuilding.staff[gradeId] = (targetBuilding.staff[gradeId] or 0)
									+ 1
								target.staffHired += 1
							end,
						})
					end
				end
			end
		end

		-- Manager (no income effect in the simulator; it automates collection).
		if not building.manager and building.level >= def.managerMinLevel then
			table.insert(options, {
				kind = "manager",
				label = `{def.name}: hire manager`,
				id = `{def.id}:manager`,
				cost = def.managerCost,
				deltaNetPerMin = 0, -- automation, not income
				requires = `{def.id}:manager`,
				apply = function(target: SimState)
					target.buildings[index].manager = true
					target.managersHired += 1
				end,
			})
		end
	end

	-- Construction on empty owned parcels.
	for _, parcelId in ipairs(emptyParcels(state)) do
		local parcel = Content.parcelById[parcelId]
		for _, def in ipairs(Content.buildingsForParcel(parcel)) do
			local cost = Content.totalBuildCost(def)
			local probe = newBuilding(def.id, parcelId, state.now)
			local income = GreedyPlayer.incomeFor(probe)
			if income > 0 then
				table.insert(options, {
					kind = "build",
					label = `Build {def.name}`,
					id = `{def.id}:build:{parcelId}`,
					cost = cost,
					deltaNetPerMin = income,
					requires = `{def.id}:build`,
					apply = function(target: SimState)
						local building =
							newBuilding(def.id, parcelId, target.now + def.buildSeconds)
						table.insert(target.buildings, building)
						target.optionsSeen[def.id .. ":built"] = true
						target.optionsSeen[def.id] = true
					end,
				})
			end
		end
	end

	-- Next parcel.
	local parcel = nextParcel(state)
	if parcel then
		local price = Parcels.priceFor(parcel, state.ownedParcels)
		table.insert(options, {
			kind = "parcel",
			label = `Buy parcel {parcel.id}`,
			id = parcel.id,
			cost = price,
			deltaNetPerMin = 0, -- land unlocks options; no direct income
			requires = parcel.id,
			apply = function(target: SimState)
				table.insert(target.parcels, parcel.id)
				target.ownedParcels += 1
				target.optionsSeen[parcel.id] = true
			end,
		})
	end

	-- Rank by payback; land and automation (which unlock options) get a small bonus so
	-- the player does not stall forever without parcels or managers.
	local scored: { { option: Option, score: number } } = {}
	for _, option in ipairs(options) do
		local score
		if option.deltaNetPerMin > 0 then
			score = option.cost / option.deltaNetPerMin
		elseif option.kind == "parcel" then
			-- Land unlocks options, so it is valued like a ~6 minute payback.
			score = 6 + option.cost / math.max(currentNet, 1)
		elseif option.kind == "manager" then
			-- Automation removes clicking; the model values it at ~5 minutes.
			score = 5 + option.cost / math.max(currentNet, 1)
		else
			score = 20 + option.cost / math.max(currentNet, 1)
		end
		if preferUnseen and not state.optionsSeen[option.requires or option.id] then
			score *= 0.01
		end
		table.insert(scored, { option = option, score = score })
	end
	table.sort(scored, function(a, b)
		if a.score == b.score then
			return a.option.cost < b.option.cost
		end
		return a.score < b.score
	end)

	local ranked: { Option } = {}
	for _, entry in ipairs(scored) do
		table.insert(ranked, entry.option)
	end
	return ranked
end

local function recordMilestone(state: SimState, label: string)
	for _, milestone in ipairs(state.milestones) do
		if milestone.label == label then
			return
		end
	end
	table.insert(state.milestones, { label = label, seconds = state.now })
end

local function checkMilestones(state: SimState)
	local worth = GreedyPlayer.netWorth(state)
	local thresholds = {
		{ 5_000, "net worth $5K" },
		{ 25_000, "net worth $25K" },
		{ 100_000, "net worth $100K" },
		{ 1_000_000, "net worth $1M" },
		{ 25_000_000, "net worth $25M" },
	}
	for _, threshold in ipairs(thresholds) do
		if worth >= threshold[1] then
			recordMilestone(state, threshold[2])
		end
	end
	if state.upgradesPurchased >= 1 then
		recordMilestone(state, "first upgrade")
	end
	if state.staffHired >= 1 then
		recordMilestone(state, "first worker")
	end
	if state.managersHired >= 1 then
		recordMilestone(state, "first manager")
	end
	if state.ownedParcels >= 2 then
		recordMilestone(state, "second parcel")
	end
	if state.ownedParcels >= #Content.parcels then
		recordMilestone(state, "all starter parcels")
	end
end

--[[ Advances time, accruing income and applying mastery XP. ]]
local function advance(state: SimState, seconds: number)
	if seconds <= 0 then
		return
	end
	local net = GreedyPlayer.netPerMin(state)
	local earned = net * (seconds / 60)
	state.cash += earned
	state.netEarned += earned
	state.lifetimeEarned += earned
	state.cashCollected += earned
	state.now += seconds
	state.playSeconds += seconds

	-- Mastery XP from collected income, with the same soft cap as the live game.
	for _, building in ipairs(state.buildings) do
		if GreedyPlayer.isOperational(building, state.now) then
			local share = GreedyPlayer.incomeFor(building) / math.max(net, 1)
			local raw = earned * share * Balance.Mastery.xpPerCashCollected
			local softCap = Balance.Mastery.softCapPerHour * (Balance.Mastery.windowSeconds / 3600)
			local state2 = Mastery.gain({
				xp = building.masteryXp,
				lvl = building.masteryLevel,
				windowStart = building.windowStart,
				windowXp = building.windowXp,
			}, raw, state.now, softCap, Balance.Mastery.windowSeconds)
			building.masteryXp = state2.xp
			building.masteryLevel = state2.lvl
			building.windowStart = state2.windowStart
			building.windowXp = state2.windowXp
		end
	end
end

--[[ Offline income for the gap between sessions (capped, 50% efficiency). ]]
local function applyOffline(state: SimState)
	local gap = GreedyPlayer.OFFLINE_GAP_SECONDS - GreedyPlayer.SESSION_SECONDS
	local net = GreedyPlayer.netPerMin(state)
	local earned = Economy.offlineEarnings(gap, net, rates)
	state.cash += earned
	state.lifetimeEarned += earned
	state.lifetimeOffline += earned
	state.now += gap
	state.lastSessionStart = state.now
end

export type RunResult = {
	state: SimState,
	purchases: number,
	hours: number,
	invariantViolations: { string },
	purchasedIds: { [string]: boolean },
	builtDefs: { [string]: boolean },
	upgradeIds: { [string]: boolean },
	paybackSamples: { { kind: string, payback: number, deltaShare: number, seconds: number } },
}

--[[ Runs the greedy player until `maxPurchases` or the time budget is exhausted. ]]
function GreedyPlayer.run(
	maxPurchases: number?,
	maxHours: number?,
	preferUnseen: boolean?
): RunResult
	local state = GreedyPlayer.newState()
	local purchaseLimit = maxPurchases or 400
	local hourLimit = maxHours or GreedyPlayer.MAX_HOURS
	local purchases = 0
	local purchased: { [string]: boolean } = {}
	local builtDefs: { [string]: boolean } = {}
	local upgradeIds: { [string]: boolean } = {}
	local samples: { { kind: string, payback: number, deltaShare: number, seconds: number } } = {}

	checkMilestones(state)

	while purchases < purchaseLimit and state.now < hourLimit * 3600 do
		local options = GreedyPlayer.options(state, preferUnseen)
		if #options == 0 then
			break
		end

		-- Take the best option we can afford (or wait for the best one).
		local best = options[1]
		local wait =
			math.max(0, (best.cost - state.cash) / math.max(GreedyPlayer.netPerMin(state), 1) * 60)
		if state.now + wait >= hourLimit * 3600 then
			advance(state, hourLimit * 3600 - state.now)
			break
		end
		advance(state, wait)
		state.cash = math.max(0, state.cash - best.cost)
		state.spentCash += best.cost

		local payback = if best.deltaNetPerMin > 0
			then best.cost / best.deltaNetPerMin
			else math.huge
		local totalNet = GreedyPlayer.netPerMin(state)
		local deltaShare = if totalNet > 0 then best.deltaNetPerMin / totalNet else 1
		table.insert(
			samples,
			{ kind = best.kind, payback = payback, deltaShare = deltaShare, seconds = state.now }
		)

		best.apply(state)
		purchased[best.id] = true
		if best.kind == "build" then
			builtDefs[best.requires:gsub(":build$", "")] = true
		elseif best.kind == "upgrade" then
			upgradeIds[best.id] = true
		end
		state.optionsSeen[best.id] = true
		if best.requires then
			state.optionsSeen[best.requires] = true
		end
		purchases += 1
		checkMilestones(state)

		-- Session bookkeeping: after 1.5 h of play, treat the next 22.5 h as offline.
		if
			state.playSeconds
			>= (GreedyPlayer.SESSION_SECONDS * math.max(1, math.floor(purchases / 40) + 1))
		then
			applyOffline(state)
			checkMilestones(state)
		end
	end

	-- Final invariants that need the completed run.
	local violations: { string } = {}
	for _, sample in ipairs(samples) do
		-- Appendix B5 invariant 4: after 30 minutes, no single purchase may raise total
		-- income per minute by more than 25%.
		if sample.seconds > 30 * 60 and sample.deltaShare > 0.25 then
			table.insert(
				violations,
				string.format(
					"%s at %.1f min raises total income by %.0f%% (limit 25%%)",
					sample.kind,
					sample.seconds / 60,
					sample.deltaShare * 100
				)
			)
		end
	end

	return {
		state = state,
		purchases = purchases,
		hours = state.now / 3600,
		invariantViolations = violations,
		purchasedIds = purchased,
		builtDefs = builtDefs,
		upgradeIds = upgradeIds,
		paybackSamples = samples,
	}
end

return GreedyPlayer
