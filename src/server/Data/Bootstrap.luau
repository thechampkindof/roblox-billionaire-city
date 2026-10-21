--!strict
--[[
	Profile bootstrap: the invariants every loaded profile must satisfy.

	Runs once per load, before any service sees the profile:
	  * the starter parcel is owned,
	  * a finished Convenience Store sits on it (the vertical slice's starting point),
	  * every district has a state row,
	  * mastery/staff/upgrade tables exist on every building.

	Only *state* is created here; world instances belong to BuildingService.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config

local Types = require(Core.Types)
local Mastery = require(Core.Mastery)
local Uid = require(Core.Uid)
local Content = require(Config.Init)

local Bootstrap = {}

local function newBuilding(def: Types.BuildingDef, parcelId: string): Types.BuildingState
	return {
		def = def.id,
		parcel = parcelId,
		level = 1,
		phase = #def.phases,
		upg = {},
		mastery = Mastery.newState(1),
		staff = {},
		manager = nil,
		constructing = nil,
		pending = 0,
		lastAccrual = os.time(),
	}
end

--[[ Mutates `profile` in place so every expected field exists. ]]
function Bootstrap.apply(profile: Types.Profile, now: number): boolean
	local changed = false

	if profile.Parcels[Content.starterParcelId] == nil then
		profile.Parcels[Content.starterParcelId] = true
		changed = true
	end

	for _, district in ipairs(Content.districts) do
		if not profile.Districts[district.id] then
			profile.Districts[district.id] = {
				unlocked = district.id == Content.starterDistrictId,
				devRating = 0,
			}
			changed = true
		end
	end

	local starterDef = Content.buildingById[Content.starterBuildingId]
	local hasStarter = false
	for _, state in profile.Buildings do
		if state.parcel == Content.starterParcelId then
			hasStarter = true
		end
		-- Repair rows written by older content versions.
		if not state.upg then
			state.upg = {}
			changed = true
		end
		if not state.staff then
			state.staff = {}
			changed = true
		end
		if not state.mastery then
			state.mastery = Mastery.newState(1)
			changed = true
		end
		if not state.lastAccrual or state.lastAccrual <= 0 then
			state.lastAccrual = now
			changed = true
		end
	end

	if not hasStarter and starterDef then
		local uid = Uid.next(profile.Buildings)
		profile.Buildings[uid] = newBuilding(starterDef, Content.starterParcelId)
		changed = true
	end

	if profile.Time.LastSaved <= 0 then
		profile.Time.LastSaved = now
		changed = true
	end

	return changed
end

return Bootstrap
