--!strict
--[[
	Feature flags. Monetization is deliberately off in this build: nothing purchasable
	with Robux exists yet, and nothing that is required for 100% completion may ever sit
	behind a flag that is on in production.
]]

local Flags = {}

export type FlagName =
	"Monetization"
	| "DebugTools"
	| "AmbientLife"
	| "CameraIntro"
	| "Telemetry"
	| "MockDataStore"

Flags.defaults = {
	Monetization = false, -- fair monetization: costs money, never required
	DebugTools = false, -- enabled only when Studio + an allow-listed tester
	AmbientLife = true,
	CameraIntro = true,
	Telemetry = true,
	MockDataStore = false, -- force the MockProvider (tests, offline Studio)
}

local overrides: { [string]: boolean } = {}

function Flags.get(name: FlagName): boolean
	local override = overrides[name]
	if override ~= nil then
		return override
	end
	return Flags.defaults[name]
end

function Flags.set(name: FlagName, value: boolean)
	overrides[name] = value
end

function Flags.reset()
	table.clear(overrides)
end

return Flags
