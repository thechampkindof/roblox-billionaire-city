--!strict
--[[
	Staff and managers.

	Staff slots come from the building definition. Every assigned worker adds a small
	revenue bonus and a wage that flows into operating expenses (see BuildingMath).
	A manager automates collection and requires a minimum building level.
]]

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Core = Shared.Core
local Config = Shared.Config
local Util = Shared.Util

local Result = require(Core.Result)
local Signal = require(Core.Signal)
local Unlock = require(Core.Unlock)
local Content = require(Config.Init)
local BuildingMath = require(Util.BuildingMath)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local BuildingService = require(script.Parent.BuildingService)

local StaffService = {}
StaffService.Name = "StaffService"
StaffService.Dependencies = { "DataService", "EconomyService", "BuildingService" }

StaffService.Hired = Signal.new("StaffHired")
StaffService.ManagerHired = Signal.new("ManagerHired")

local function usedSlots(state: any): number
	local total = 0
	for _, count in state.staff do
		total += count
	end
	return total
end

--[[ Hires one worker of `gradeId` for a building. ]]
function StaffService.Hire(player: Player, uid: string, gradeId: string): Result.Result<number>
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end
	local state = profile.Buildings[uid]
	if not state then
		return Result.err("NOT_FOUND")
	end
	local def = Content.buildingById[state.def]
	local grade = Content.staffById[gradeId]
	if not def or not grade then
		return Result.err("INVALID_ID")
	end
	if not BuildingMath.isOperational(state) then
		return Result.err("CONSTRUCTION_PENDING")
	end
	if usedSlots(state) >= def.staffSlots then
		return Result.err("STAFF_FULL")
	end

	local context = BuildingService.Context(player)
	local gate = Unlock.evaluate(grade.requires, context)
	if not gate.ok then
		return Result.err("LOCKED", gate.unmet[1] and gate.unmet[1].description)
	end

	local cost = BuildingMath.staffCost(def, state, gradeId)
	local paid = EconomyService.SpendCash(player, cost, "staff_hire")
	if not paid.ok then
		return paid
	end

	state.staff[gradeId] = (state.staff[gradeId] or 0) + 1
	BuildingService.Rebuild(player, uid)
	DataService.SaveSoon(player)
	StaffService.Hired:Fire(player, uid, gradeId, state.staff[gradeId])
	return Result.ok(state.staff[gradeId])
end

--[[ Hires the building's manager (one per building). ]]
function StaffService.HireManager(player: Player, uid: string): Result.Result<boolean>
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
	if state.manager then
		return Result.err("MANAGER_ALREADY_HIRED")
	end
	if not BuildingMath.isOperational(state) then
		return Result.err("CONSTRUCTION_PENDING")
	end
	if state.level < def.managerMinLevel then
		return Result.err("MANAGER_REQUIRED_LEVEL", `reach level {def.managerMinLevel} first`)
	end

	local paid = EconomyService.SpendCash(player, def.managerCost, "manager_hire")
	if not paid.ok then
		return paid
	end

	state.manager = "Standard"
	BuildingService.Rebuild(player, uid)
	DataService.SaveSoon(player)
	StaffService.ManagerHired:Fire(player, uid, def.managerCost)
	return Result.ok(true)
end

--[[ Total wages per minute for a building (exposed for the Income tab). ]]
function StaffService.WagesPerMin(state: any): number
	local total = 0
	for gradeId, count in state.staff do
		local grade = Content.staffById[gradeId]
		if grade then
			total += grade.wagePerMin * count
		end
	end
	return total
end

function StaffService.Init(registry: any) end
function StaffService.Start() end

return StaffService
