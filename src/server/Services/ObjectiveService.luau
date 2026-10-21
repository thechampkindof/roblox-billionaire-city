--!strict
--[[
	Objective chain driver.

	Progress counters live in `profile.Objectives.progress`; the current objective is
	measured by `Core/Objectives` against those counters plus live profile queries.
	Completing one grants its reward, advances the index and fires a toast — every
	objective goes through this single path, so adding content is a data edit.
]]

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Core = Shared.Core
local Config = Shared.Config

local Signal = require(Core.Signal)
local Result = require(Core.Result)
local ObjectivesCore = require(Core.Objectives)
local Content = require(Config.Init)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local IncomeService = require(script.Parent.IncomeService)
local ParcelService = require(script.Parent.ParcelService)
local StaffService = require(script.Parent.StaffService)
local UpgradeService = require(script.Parent.UpgradeService)
local ConstructionService = require(script.Parent.ConstructionService)

local ObjectiveService = {}
ObjectiveService.Name = "ObjectiveService"
ObjectiveService.Dependencies = {
	"DataService",
	"EconomyService",
	"IncomeService",
	"ParcelService",
	"StaffService",
	"UpgradeService",
	"ConstructionService",
}

ObjectiveService.Completed = Signal.new("ObjectiveCompleted")
ObjectiveService.Advanced = Signal.new("ObjectiveAdvanced")

local function progressTable(profile: any): { [string]: number }
	local progress = profile.Objectives.progress
	if not progress then
		progress = {}
		profile.Objectives.progress = progress
	end
	return progress
end

local function currentObjective(profile: any): any?
	local index = profile.Objectives.index or 1
	for _, def in ipairs(Content.objectives) do
		if def.index == index and profile.Objectives.completed[def.id] ~= true then
			return def
		end
	end
	return nil
end

--[[ Builds the measurement context for a player. ]]
function ObjectiveService.Context(player: Player): ObjectivesCore.ObjectiveContext
	local profile = DataService.Get(player)
	local context = ObjectivesCore.defaultContext()
	if not profile then
		return context
	end
	local progress = progressTable(profile)
	context.cashCollected = progress.cashCollected or 0
	context.upgradesPurchased = progress.upgradesPurchased or 0
	context.staffHired = progress.staffHired or 0
	context.managersHired = progress.managersHired or 0

	local parcels = 0
	for _ in profile.Parcels do
		parcels += 1
	end
	context.parcelsOwned = parcels
	context.buildingLevel = function(defId: string)
		local highest = 0
		for _, state in profile.Buildings do
			if state.def == defId then
				highest = math.max(highest, state.level)
			end
		end
		return highest
	end
	return context
end

--[[ Re-measures the active objective and completes it when satisfied. ]]
function ObjectiveService.Evaluate(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local objective = currentObjective(profile)
	if not objective then
		return
	end
	local progress = ObjectivesCore.measure(objective.goal, ObjectiveService.Context(player))
	if not progress.done then
		return
	end

	profile.Objectives.completed[objective.id] = true
	profile.Objectives.index = (profile.Objectives.index or 1) + 1
	local rewards: EconomyService.Deltas = {}
	if objective.rewardCash > 0 then
		rewards.cash = objective.rewardCash
	end
	if rewards.cash then
		EconomyService.Grant(player, rewards, `objective_reward:{objective.id}`)
	end
	-- Objective XP is mastery XP for the player's first building.
	if objective.rewardXp > 0 then
		for _, state in profile.Buildings do
			if state.mastery then
				state.mastery.xp += objective.rewardXp
			end
			break
		end
	end

	DataService.SaveSoon(player)
	ObjectiveService.Completed:Fire(player, objective)
	local nextObjective = currentObjective(profile)
	if nextObjective then
		ObjectiveService.Advanced:Fire(player, nextObjective)
	end
end

local function bump(player: Player, key: string, amount: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local progress = progressTable(profile)
	progress[key] = (progress[key] or 0) + amount
	ObjectiveService.Evaluate(player)
end

function ObjectiveService.Init(registry: any)
	DataService.ProfileLoaded:Connect(function(player: Player)
		local profile = DataService.Get(player)
		if not profile then
			return
		end
		if not profile.Objectives.progress then
			profile.Objectives.progress = {}
		end
		task.defer(function()
			ObjectiveService.Evaluate(player)
		end)
	end)

	IncomeService.Collected:Connect(function(player: Player, _target: string, amount: number)
		bump(player, "cashCollected", amount)
	end)
	UpgradeService.Purchased:Connect(function(player: Player)
		bump(player, "upgradesPurchased", 1)
	end)
	UpgradeService.LevelPurchased:Connect(function(player: Player)
		bump(player, "upgradesPurchased", 1)
	end)
	StaffService.Hired:Connect(function(player: Player)
		bump(player, "staffHired", 1)
	end)
	StaffService.ManagerHired:Connect(function(player: Player)
		bump(player, "managersHired", 1)
	end)
	ParcelService.Purchased:Connect(function(player: Player)
		ObjectiveService.Evaluate(player)
	end)
	ConstructionService.Finished:Connect(function(player: Player)
		ObjectiveService.Evaluate(player)
	end)
end

function ObjectiveService.Start() end

--[[ Snapshot payload for the HUD objective card. ]]
function ObjectiveService.CurrentFor(player: Player): any?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local objective = currentObjective(profile)
	if not objective then
		return nil
	end
	local progress = ObjectivesCore.measure(objective.goal, ObjectiveService.Context(player))
	return {
		id = objective.id,
		title = objective.title,
		description = objective.description,
		current = progress.current,
		target = progress.target,
		fraction = progress.fraction,
		done = progress.done,
		rewardCash = objective.rewardCash,
	}
end

--[[ Handles the `ObjectivePin` intent. ]]
function ObjectiveService.Pin(player: Player, objectiveId: string): Result.Result<boolean>
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end
	if objectiveId == "" or objectiveId == "none" then
		profile.Objectives.pinned = nil
		return Result.ok(true)
	end
	if not Content.objectiveById[objectiveId] then
		return Result.err("INVALID_ID")
	end
	profile.Objectives.pinned = objectiveId
	DataService.MarkDirty(player)
	return Result.ok(true)
end

return ObjectiveService
