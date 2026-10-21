--!strict
--[[
	Upgrade line purchases and building level purchases.

	Prices come from `Util/BuildingMath`, the same module the client uses for previews,
	so the number on the button is the number charged. Requirements are net-worth gates
	for now (tier 2/3 lines) and level caps from content.
]]

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Core = Shared.Core
local Config = Shared.Config
local Util = Shared.Util

local Result = require(Core.Result)
local Signal = require(Core.Signal)
local Unlock = require(Core.Unlock)
local Mastery = require(Core.Mastery)
local Content = require(Config.Init)
local Balance = Content.Balance
local BuildingMath = require(Util.BuildingMath)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local BuildingService = require(script.Parent.BuildingService)

local UpgradeService = {}
UpgradeService.Name = "UpgradeService"
UpgradeService.Dependencies = { "DataService", "EconomyService", "BuildingService" }

UpgradeService.Purchased = Signal.new("UpgradePurchased")
UpgradeService.LevelPurchased = Signal.new("LevelPurchased")

local function awardMastery(player: Player, uid: string, state: any, spent: number)
	local def = Content.buildingById[state.def]
	if not def or not def.masteryEnabled or not Balance.Mastery.enabled then
		return
	end
	local xp = BuildingMath.masteryXpForCash(spent, "spend")
	local softCap = Balance.Mastery.softCapPerHour * (Balance.Mastery.windowSeconds / 3600)
	local nextState, gained =
		Mastery.gain(state.mastery, xp, os.time(), softCap, Balance.Mastery.windowSeconds)
	if gained <= 0 then
		return
	end
	local levelChanged = nextState.lvl ~= state.mastery.lvl
	state.mastery = nextState
	if levelChanged then
		BuildingService.Rebuild(player, uid)
	end
end

--[[ Buys one level of an upgrade line. ]]
function UpgradeService.Purchase(
	player: Player,
	uid: string,
	upgradeId: string
): Result.Result<number>
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end
	local state = profile.Buildings[uid]
	if not state then
		return Result.err("NOT_FOUND")
	end
	local def = Content.buildingById[state.def]
	local upgrade = Content.upgradeById[upgradeId]
	if not def or not upgrade or upgrade.buildingId ~= def.id then
		return Result.err("INVALID_ID")
	end
	if not BuildingMath.isOperational(state) then
		return Result.err("CONSTRUCTION_PENDING")
	end
	local level = state.upg[upgradeId] or 0
	if level >= upgrade.maxLevel then
		return Result.err("MAX_LEVEL")
	end

	local context = BuildingService.Context(player)
	local gate = Unlock.evaluate(upgrade.requires, context)
	if not gate.ok then
		return Result.err("LOCKED", gate.unmet[1] and gate.unmet[1].description)
	end

	local cost = BuildingMath.upgradeCost(def, state, upgradeId)
	local paid = EconomyService.SpendCash(player, cost, "upgrade_purchase")
	if not paid.ok then
		return paid
	end

	state.upg[upgradeId] = level + 1
	awardMastery(player, uid, state, cost)
	BuildingService.Rebuild(player, uid)
	DataService.SaveSoon(player)
	UpgradeService.Purchased:Fire(player, uid, upgradeId, state.upg[upgradeId], cost)
	return Result.ok(state.upg[upgradeId])
end

--[[ Buys one operating level for the building itself. ]]
function UpgradeService.PurchaseLevel(player: Player, uid: string): Result.Result<number>
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end
	local state = profile.Buildings[uid]
	if not state then
		return Result.err("NOT_FOUND")
	end
	local def = Content.buildingById[state.def]
	if not def then
		return Result.err("INVALID_ID")
	end
	if not BuildingMath.isOperational(state) then
		return Result.err("CONSTRUCTION_PENDING")
	end
	if state.level >= def.maxLevel then
		return Result.err("MAX_LEVEL")
	end

	local cost = BuildingMath.levelCost(def, state)
	local paid = EconomyService.SpendCash(player, cost, "level_purchase")
	if not paid.ok then
		return paid
	end

	state.level += 1
	awardMastery(player, uid, state, cost)
	BuildingService.Rebuild(player, uid)
	DataService.SaveSoon(player)
	UpgradeService.LevelPurchased:Fire(player, uid, state.level, cost)
	return Result.ok(state.level)
end

--[[ Preview used by tests and tooling: cost + income delta of the next level. ]]
function UpgradeService.PreviewLevel(player: Player, uid: string): (number, number)
	local profile = DataService.Get(player)
	local state = profile and profile.Buildings[uid]
	if not profile or not state then
		return math.huge, 0
	end
	local def = Content.buildingById[state.def]
	if not def then
		return math.huge, 0
	end
	local before = BuildingMath.income(def, state).netPerMin
	local copy = table.clone(state)
	copy.level += 1
	local after = BuildingMath.income(def, copy).netPerMin
	return BuildingMath.levelCost(def, state), after - before
end

function UpgradeService.Init(registry: any) end
function UpgradeService.Start() end

return UpgradeService
