--!strict
--[[
	Read-only client mirror of server state.

	The server sends a snapshot on join and coalesced patches afterwards; this module
	stores the latest merged view and fires `Changed(section)` so UI can rebind. It never
	computes money, income or progression for display decisions that matter — values come
	from the server. Local math (via BuildingMath) is used only for previews, and the
	server re-validates every intent.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Net = Shared.Net

local Signal = require(Core.Signal)
local Remotes = require(Net.Remotes)

local StateController = {}
StateController.Name = "StateController"

StateController.Changed = Signal.new("StateChanged")
StateController.Ready = Signal.new("StateReady")

export type State = {
	version: number?,
	currency: any?,
	buildings: { [string]: any }?,
	parcels: any?,
	plot: any?,
	objective: any?,
	settings: { [string]: any }?,
	offlineCapHours: number?,
	offlineEfficiency: number?,
}

local state: State = {}
local loaded = false

local function merge(section: string, value: any)
	local target = state :: any
	target[section] = value
end

function StateController.Get(): State
	return state
end

function StateController.IsReady(): boolean
	return loaded
end

function StateController.Building(uid: string): any?
	return state.buildings and state.buildings[uid]
end

function StateController.Buildings(): { [string]: any }
	return state.buildings or {}
end

--[[ Sends an intent. The server validates everything; failures arrive as a toast. ]]
function StateController.Send(intent: string, payload: any)
	Remotes.intent():FireServer(intent, payload)
end

local function applySnapshot(snapshot: any)
	for key, value in snapshot do
		merge(key, value)
	end
	loaded = true
	StateController.Ready:Fire(state)
	StateController.Changed:Fire("all")
end

local function applyPatch(patch: any)
	for key, value in patch do
		merge(key, value)
	end
	StateController.Changed:Fire("patch")
end

function StateController.Start()
	local snapshotEvent = Remotes.snapshot()
	snapshotEvent.OnClientEvent:Connect(function(snapshot: any)
		if type(snapshot) == "table" then
			applySnapshot(snapshot)
		end
	end)

	local patchEvent = Remotes.patch()
	patchEvent.OnClientEvent:Connect(function(patch: any)
		if type(patch) == "table" then
			applyPatch(patch)
		end
	end)
end

--[[
	Converts a snapshot building row into the shape `Util/BuildingMath` expects, so the
	client can run the same price/income preview code as the server.
]]
function StateController.AsProfileBuilding(row: any): any
	return {
		def = row.def,
		parcel = row.parcel,
		level = row.level,
		phase = row.phase,
		upg = row.upg or {},
		mastery = {
			xp = row.mastery and row.mastery.xp or 0,
			lvl = row.mastery and row.mastery.lvl or 1,
			windowStart = 0,
			windowXp = 0,
		},
		staff = row.staff or {},
		manager = row.manager,
		constructing = row.constructing,
		pending = row.pending or 0,
		lastAccrual = 0,
	}
end

return StateController
