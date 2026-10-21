--!strict
--[[
	Owner of building *instances*.

	Only this service creates, replaces or destroys building models. State lives in the
	profile; the model is a projection of that state (inside grid → world position is
	derived from the owning plot, never persisted).
]]

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Core = Shared.Core
local Config = Shared.Config

local Signal = require(Core.Signal)
local Unlock = require(Core.Unlock)
local Uid = require(Core.Uid)
local Content = require(Config.Init)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local BuildingFactory = require(script.Parent.BuildingFactory)

local BuildingService = {}
BuildingService.Name = "BuildingService"
BuildingService.Dependencies = { "DataService", "PlotService" }

BuildingService.BuildingAdded = Signal.new("BuildingAdded")
BuildingService.BuildingUpdated = Signal.new("BuildingUpdated")
BuildingService.BuildingRemoved = Signal.new("BuildingRemoved")

local models: { [Player]: { [string]: Model } } = {}

local function worldPosition(player: Player, parcelId: string): Vector3?
	local position = PlotService.ParcelPosition(player, parcelId)
	if position then
		return position
	end
	local plot = PlotService.Get(player)
	if plot then
		-- Fallback: parcel pad missing (should not happen) — centre of the plot.
		return plot.origin + Vector3.new(0, 1, 0)
	end
	return nil
end

--[[ Finds the building occupying a parcel, if any. ]]
function BuildingService.FindByParcel(profile: any, parcelId: string): (string?, any?)
	for uid, state in profile.Buildings do
		if state.parcel == parcelId then
			return uid, state
		end
	end
	return nil, nil
end

function BuildingService.GetState(player: Player, uid: string): any?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	return profile.Buildings[uid]
end

--[[ All building states for a player, as an array of `{ uid, state }`. ]]
function BuildingService.All(player: Player): { { uid: string, state: any } }
	local profile = DataService.Get(player)
	local list: { { uid: string, state: any } } = {}
	if not profile then
		return list
	end
	for uid, state in profile.Buildings do
		table.insert(list, { uid = uid, state = state })
	end
	return list
end

--[[
	Creates a building state row. Callers (ConstructionService) own pricing and
	construction timing; this function only creates the row and its model.
]]
function BuildingService.Create(player: Player, parcelId: string, def: any): (string?, any?)
	local profile = DataService.Get(player)
	if not profile then
		return nil, nil :: any
	end
	local uid = Uid.next(profile.Buildings)
	profile.Buildings[uid] = {
		def = def.id,
		parcel = parcelId,
		level = 1,
		phase = 0,
		upg = {},
		mastery = { xp = 0, lvl = 1, windowStart = os.time(), windowXp = 0 },
		staff = {},
		manager = nil,
		constructing = nil,
		pending = 0,
		lastAccrual = os.time(),
	}
	DataService.MarkDirty(player)
	BuildingService.Rebuild(player, uid)
	BuildingService.BuildingAdded:Fire(player, uid, profile.Buildings[uid])
	return uid, profile.Buildings[uid]
end

local function renderModel(player: Player, uid: string, state: any)
	local def = Content.buildingById[state.def]
	if not def then
		return
	end
	local position = worldPosition(player, state.parcel)
	if not position then
		return
	end

	local plot = PlotService.Get(player)
	if not plot then
		return
	end

	local model: Model
	if state.constructing then
		local phaseDef = def.phases[state.constructing.phase]
		local elapsed = math.max(0, os.time() - state.constructing.startedAt)
		local share = if state.constructing.seconds > 0
			then elapsed / state.constructing.seconds
			else 1
		local overall = ((state.constructing.phase - 1) + math.clamp(share, 0, 1)) / #def.phases
		model = BuildingFactory.Site(def, position, overall)
	elseif state.phase >= #def.phases then
		model = BuildingFactory.Build(
			def,
			position,
			state.level,
			"finished",
			state.mastery and state.mastery.lvl or 1
		)
	else
		model = BuildingFactory.Site(def, position, 1)
	end

	BuildingFactory.AttachPrompt(model, uid)
	model:SetAttribute("DefId", def.id)
	model:SetAttribute("ParcelId", state.parcel)
	model:SetAttribute("Level", state.level)
	model:SetAttribute("Phase", state.phase)
	model:SetAttribute("Constructing", state.constructing ~= nil)
	model.Parent = plot.folder

	local playerModels = models[player]
	if not playerModels then
		playerModels = {}
		models[player] = playerModels
	end
	local existing = playerModels[uid]
	if existing then
		existing:Destroy()
	end
	playerModels[uid] = model
end

--[[ Re-creates one building model from state. ]]
function BuildingService.Rebuild(player: Player, uid: string)
	local state = BuildingService.GetState(player, uid)
	if not state then
		return
	end
	renderModel(player, uid, state)
	BuildingService.BuildingUpdated:Fire(player, uid, state)
	PlotService.Refresh(player)
end

function BuildingService.RebuildAll(player: Player)
	local playerModels = models[player]
	if playerModels then
		for _, model in playerModels do
			model:Destroy()
		end
	end
	models[player] = {}
	for uid in (DataService.Get(player) or { Buildings = {} }).Buildings do
		BuildingService.Rebuild(player, uid)
	end
end

function BuildingService.ModelFor(player: Player, uid: string): Model?
	local playerModels = models[player]
	return if playerModels then playerModels[uid] else nil
end

--[[ Removes every instance owned by a player (called on leave). ]]
function BuildingService.Clear(player: Player)
	local playerModels = models[player]
	if playerModels then
		for _, model in playerModels do
			model:Destroy()
		end
	end
	models[player] = nil
end

--[[ Requirement context for blueprints, upgrades and land. ]]
function BuildingService.Context(player: Player): Unlock.Context
	local profile = DataService.Get(player)
	local context = Unlock.defaultContext()
	if not profile then
		return context
	end

	context.netWorth = require(script.Parent.EconomyService).NetWorth(profile)
	context.reputation = profile.Currency.Reputation
	context.prestigePoints = profile.Currency.PrestigePoints
	context.districtPct = function(districtId: string)
		local district = profile.Districts[districtId]
		return if district then district.devRating else 0
	end
	context.research = function(node: string)
		return profile.Research.done[node] == true
	end
	context.buildingLevel = function(defId: string)
		local highest = 0
		for _, state in profile.Buildings do
			if state.def == defId then
				highest = math.max(highest, state.level)
			end
		end
		return highest
	end
	context.contractDone = function(id: string)
		return profile.Contracts.done[id] == true
	end
	context.legacy = function(id: string)
		return profile.Legacy[id] == true
	end
	return context
end

function BuildingService.Init(registry: any)
	PlotService.PlotAssigned:Connect(function(player: Player)
		BuildingService.RebuildAll(player)
	end)
	DataService.ProfileReleasing:Connect(function(player: Player)
		BuildingService.Clear(player)
	end)
end

function BuildingService.Start() end

return BuildingService
