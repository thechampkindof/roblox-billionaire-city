--!strict
--[[
	Studio-only debug tools.

	Hard gates, all of which must pass:
	  1. `RunService:IsStudio()` — never true on a live server,
	  2. `Flags.DebugTools` — false by default and never set in production,
	  3. the player's user id is in `DebugService.ALLOWLIST` — empty by default.

	With the allowlist empty these actions are impossible to trigger anywhere.
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config

local Result = require(Core.Result)
local Content = require(Config.Init)
local Flags = require(Config.Flags)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local BuildingService = require(script.Parent.BuildingService)

local DebugService = {}
DebugService.Name = "DebugService"
DebugService.Dependencies = { "DataService", "EconomyService", "BuildingService" }

-- Add Studio tester user ids here while testing. Empty = nobody.
DebugService.ALLOWLIST = {} :: { number }

function DebugService.isAllowed(player: Player): boolean
	if not RunService:IsStudio() then
		return false
	end
	if not Flags.get("DebugTools") then
		return false
	end
	for _, userId in ipairs(DebugService.ALLOWLIST) do
		if userId == player.UserId then
			return true
		end
	end
	return false
end

local ACTIONS: { [string]: (player: Player, profile: any) -> Result.Result<any> } = {
	grant_cash = function(player: Player, profile: any)
		EconomyService.Grant(player, { cash = 10_000 }, "debug_grant")
		return Result.ok(true)
	end,
	unlock_parcels = function(player: Player, profile: any)
		for _, parcel in ipairs(Content.parcels) do
			profile.Parcels[parcel.id] = true
		end
		local district = profile.Districts.Starter
		if district then
			district.devRating = 100
		end
		DataService.MarkDirty(player)
		return Result.ok(true)
	end,
	finish_construction = function(player: Player, profile: any)
		for uid, state in profile.Buildings do
			local def = Content.buildingById[state.def]
			if not def then
				continue
			end
			if state.constructing then
				state.constructing.startedAt = os.time() - state.constructing.seconds
			end
			state.phase = #def.phases
			state.constructing = nil
			BuildingService.Rebuild(player, uid)
		end
		DataService.MarkDirty(player)
		return Result.ok(true)
	end,
	max_upgrades = function(player: Player, profile: any)
		for uid, state in profile.Buildings do
			local def = Content.buildingById[state.def]
			if not def then
				continue
			end
			for _, upgradeId in ipairs(Content.upgradeIdsFor(def.id)) do
				state.upg[upgradeId] = Content.upgradeById[upgradeId].maxLevel
			end
			state.level = def.maxLevel
			BuildingService.Rebuild(player, uid)
		end
		DataService.MarkDirty(player)
		return Result.ok(true)
	end,
	clear_pending = function(player: Player, profile: any)
		for _, state in profile.Buildings do
			state.pending = 0
		end
		return Result.ok(true)
	end,
}

--[[ Entry point used by NetService's DebugAction intent. ]]
function DebugService.Run(player: Player, action: string): Result.Result<boolean>
	if not DebugService.isAllowed(player) then
		return Result.err("LOCKED", "debug tools are disabled")
	end
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end
	local handler = ACTIONS[action]
	if not handler then
		return Result.err("INVALID_ID", action)
	end
	return handler(player, profile)
end

function DebugService.Init(registry: any)
	if Flags.get("DebugTools") and #DebugService.ALLOWLIST > 0 then
		warn("[DebugService] debug tools are ENABLED for allow-listed players in Studio")
	end
end

function DebugService.Start() end

return DebugService
