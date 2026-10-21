--!strict
--[[
	Construction, phase progression and rushing.

	Timestamps (`startedAt`, `seconds`) drive everything, so progress survives a rejoin
	and offline time: a phase that finished while the player was away completes on the
	next tick. The whole build cost is paid up front; phases then advance themselves.
]]

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Core = Shared.Core
local Config = Shared.Config

local Result = require(Core.Result)
local Signal = require(Core.Signal)
local Unlock = require(Core.Unlock)
local Content = require(Config.Init)
local Balance = Content.Balance

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local BuildingService = require(script.Parent.BuildingService)

local ConstructionService = {}
ConstructionService.Name = "ConstructionService"
ConstructionService.Dependencies = { "DataService", "EconomyService", "BuildingService" }

ConstructionService.Started = Signal.new("ConstructionStarted")
ConstructionService.PhaseCompleted = Signal.new("ConstructionPhaseCompleted")
ConstructionService.Finished = Signal.new("ConstructionFinished")

local TICK_SECONDS = 2

--[[ Fraction (0..1) of the whole building that is complete, for UI progress bars. ]]
function ConstructionService.Progress(state: any): (number, number)
	local def = Content.buildingById[state.def]
	if not def then
		return 0, 0
	end
	if not state.constructing then
		return if state.phase >= #def.phases then 1 else 0, 0
	end
	local phaseDef = def.phases[state.constructing.phase]
	local now = os.time()
	local elapsed = math.max(0, now - state.constructing.startedAt)
	local remaining = math.max(0, state.constructing.seconds - elapsed)
	local share = if state.constructing.seconds > 0
		then math.clamp(elapsed / state.constructing.seconds, 0, 1)
		else 1
	local overall = ((state.constructing.phase - 1) + share) / #def.phases
	return overall, remaining
end

--[[ Advances one building's construction state until it is either done or mid-phase. ]]
local function advanceState(state: any): (boolean, boolean)
	local def = Content.buildingById[state.def]
	if not def or not state.constructing then
		return false, false
	end
	local now = os.time()
	local changed = false
	local finished = false

	while state.constructing do
		local phaseDef = def.phases[state.constructing.phase]
		if not phaseDef then
			state.constructing = nil
			break
		end
		local endsAt = state.constructing.startedAt + state.constructing.seconds
		if now < endsAt then
			break
		end
		state.phase = state.constructing.phase
		changed = true
		if state.phase >= #def.phases then
			state.constructing = nil
			finished = true
		else
			state.constructing = {
				phase = state.phase + 1,
				startedAt = endsAt,
				seconds = def.phases[state.phase + 1].seconds,
			}
		end
	end
	return changed, finished
end

--[[ Starts construction on an owned, empty parcel. ]]
function ConstructionService.Start(
	player: Player,
	parcelId: string,
	buildingId: string
): Result.Result<string>
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end
	local parcel = Content.parcelById[parcelId]
	if not parcel then
		return Result.err("INVALID_ID")
	end
	if not profile.Parcels[parcelId] then
		return Result.err("PARCEL_NOT_OWNED")
	end
	local existingUid = BuildingService.FindByParcel(profile, parcelId)
	if existingUid then
		return Result.err("PARCEL_OCCUPIED")
	end
	local def = Content.buildingById[buildingId]
	if not def then
		return Result.err("INVALID_ID")
	end
	if def.district ~= parcel.district then
		return Result.err("PARCEL_WRONG_DISTRICT")
	end
	if not Content.fitsSize(def.parcelSize, parcel.size) then
		return Result.err("PARCEL_TOO_SMALL")
	end
	if parcel.allowed then
		local allowed = false
		for _, id in ipairs(parcel.allowed) do
			if id == def.id then
				allowed = true
			end
		end
		if not allowed then
			return Result.err("LOCKED")
		end
	end

	local context = BuildingService.Context(player)
	local blueprint = Unlock.evaluate(def.blueprint, context)
	if not blueprint.ok then
		return Result.err("LOCKED", blueprint.unmet[1] and blueprint.unmet[1].description)
	end

	local totalCost = Content.totalBuildCost(def)
	local paid = EconomyService.SpendCash(player, totalCost, "construction_start")
	if not paid.ok then
		return paid.code == "INSUFFICIENT_FUNDS" and Result.err("INSUFFICIENT_FUNDS") or paid
	end

	local uid, state = BuildingService.Create(player, parcelId, def)
	if not uid or not state then
		-- Refund: state creation failed after payment.
		EconomyService.Grant(player, { cash = totalCost }, "construction_refund")
		return Result.err("NOT_FOUND")
	end

	state.constructing = {
		phase = 1,
		startedAt = os.time(),
		seconds = def.phases[1].seconds,
	}
	BuildingService.Rebuild(player, uid)
	DataService.SaveSoon(player)
	ConstructionService.Started:Fire(player, uid, def)
	return Result.ok(uid)
end

--[[ Completes every due phase for every loaded player. ]]
function ConstructionService.Tick()
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		local profile = DataService.Get(player)
		if not profile then
			continue
		end
		for uid, state in profile.Buildings do
			if not state.constructing then
				continue
			end
			local changed, finished = advanceState(state)
			if changed then
				BuildingService.Rebuild(player, uid)
				DataService.MarkDirty(player)
				if finished then
					ConstructionService.Finished:Fire(player, uid, state)
					DataService.SaveSoon(player)
				else
					ConstructionService.PhaseCompleted:Fire(player, uid, state.phase, state)
				end
			end
		end
	end
end

--[[ Pays a premium to finish the current phase immediately. ]]
function ConstructionService.Rush(player: Player, uid: string): Result.Result<boolean>
	local profile = DataService.Get(player)
	local state = profile and profile.Buildings[uid]
	if not profile or not state then
		return Result.err("NOT_FOUND")
	end
	if not state.constructing then
		return Result.err("NOT_CONSTRUCTING")
	end
	local _, remaining = ConstructionService.Progress(state)
	local cost = math.max(1, math.floor(remaining * Balance.Construction.rushCostPerSecond + 0.5))
	local paid = EconomyService.SpendCash(player, cost, "construction_rush")
	if not paid.ok then
		return paid
	end
	state.constructing.startedAt = os.time() - state.constructing.seconds
	ConstructionService.Tick()
	return Result.ok(true)
end

function ConstructionService.Init(registry: any)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(ConstructionService.Tick)
			if not ok then
				warn(`[ConstructionService] tick failed: {tostring(err)}`)
			end
		end
	end)
end

function ConstructionService.Start() end

return ConstructionService
