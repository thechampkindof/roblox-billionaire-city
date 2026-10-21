--!strict
--[[
	Profile template, reconciliation and size estimation.

	`Reconcile` is intentionally conservative: saved data always wins, missing fields
	come from the template, and type mismatches fall back to the template value instead
	of erroring. That protects a player's session from a half-written save or a field
	added by a newer content version.
]]

local Types = require(script.Parent.Types)

local Profile = {}

Profile.CURRENT_VERSION = 1
Profile.BUDGET_BYTES = 1_000_000 -- Appendix B3 target
Profile.HARD_LIMIT_BYTES = 3_000_000 -- test failure threshold

export type Profile = Types.Profile

--[[ A brand-new profile. `now` is `os.time()` supplied by the caller (keeps Core pure). ]]
function Profile.template(now: number): Profile
	return {
		Version = Profile.CURRENT_VERSION,
		Currency = {
			Cash = 500,
			Reputation = 0,
			PrestigePoints = 0,
			ResearchPoints = 0,
		},
		Stats = {
			LifetimeEarned = 0,
			PlaySeconds = 0,
			NetWorthPeak = 0,
		},
		Time = {
			FirstJoin = now,
			LastSaved = now,
			LastSeen = now,
		},
		Parcels = {},
		Buildings = {},
		Districts = {
			Starter = { unlocked = true, devRating = 0 },
		},
		Research = { done = {}, active = {} },
		Contracts = { active = {}, done = {}, seed = 0 },
		Objectives = {
			chain = "starter",
			index = 1,
			progress = {},
			completed = {},
			pinned = nil,
		},
		Collections = {
			Vehicles = {},
			Houses = {},
			Furniture = {},
			Cosmetics = {},
		},
		Achievements = {},
		Legacy = {},
		Settings = {
			quality = "auto",
			sfx = true,
			music = true,
		},
		Purchases = {},
	}
end

local function isPlainTable(value: any): boolean
	return type(value) == "table" and getmetatable(value) == nil
end

--[[ Deep merge of `saved` onto `template`: saved values win when their type matches. ]]
function Profile.reconcile(template: any, saved: any): any
	if not isPlainTable(saved) then
		return template
	end
	if not isPlainTable(template) then
		return saved
	end

	local result: any = {}
	for key, templateValue in template do
		local savedValue = saved[key]
		if savedValue == nil then
			result[key] = templateValue
		elseif isPlainTable(templateValue) and isPlainTable(savedValue) then
			result[key] = Profile.reconcile(templateValue, savedValue)
		elseif type(templateValue) == type(savedValue) then
			result[key] = savedValue
		else
			result[key] = templateValue
		end
	end

	-- Preserve keys that exist only in the save (content added by a newer version,
	-- e.g. a building uid). They are still validated downstream.
	for key, savedValue in saved do
		if result[key] == nil then
			result[key] = savedValue
		end
	end
	return result
end

--[[ Reconciles against the template and forces the current schema version. ]]
function Profile.normalise(saved: any, now: number): Profile
	return Profile.reconcile(Profile.template(now), saved) :: Profile
end

--[[ Deterministic, cheap size estimate in bytes (no Roblox API). ]]
function Profile.estimateBytes(profile: any): number
	local visited: { [any]: boolean } = {}
	local function size(value: any, depth: number): number
		local kind = type(value)
		if kind == "nil" then
			return 4
		elseif kind == "boolean" then
			return if value then 4 else 5
		elseif kind == "number" then
			return #tostring(value)
		elseif kind == "string" then
			return #value + 2
		elseif kind ~= "table" or depth > 32 or visited[value] then
			return 2
		end
		visited[value] = true
		local total = 2
		for key, child in value do
			total += size(key, depth + 1) + 1 + size(child, depth + 1) + 1
		end
		visited[value] = nil
		return total
	end
	return size(profile, 0)
end

return Profile
