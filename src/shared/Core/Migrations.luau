--!strict
--[[
	Versioned profile migrations.

	Each step is a *pure* function `vN -> vN+1` registered under its source version.
	Migrations never touch the network, never read the clock (the caller supplies `now`)
	and are unit-tested by replaying representative old saves.
]]

local Result = require(script.Parent.Result)
local Profile = require(script.Parent.Profile)

local Migrations = {}

export type Migration = (profile: any, now: number) -> any

Migrations.CURRENT_VERSION = Profile.CURRENT_VERSION

--[[ Source version -> upgrade function. Add `[1] = function(...)` when schema v2 ships. ]]
local steps: { [number]: Migration } = {}

function Migrations.register(fromVersion: number, migrate: Migration)
	steps[fromVersion] = migrate
end

function Migrations.clearRegistered()
	table.clear(steps)
end

function Migrations.registeredVersions(): { number }
	local versions: { number } = {}
	for version in steps do
		table.insert(versions, version)
	end
	table.sort(versions)
	return versions
end

--[[
	Brings `saved` up to `Migrations.CURRENT_VERSION`.

	Rejects saves from the future (they would lose data on the next write) and saves
	whose version has no migration path.
]]
function Migrations.migrate(saved: any, now: number): Result.Result<any>
	return Migrations.runChain(saved, Migrations.CURRENT_VERSION, now)
end

--[[ Runs the migration chain up to `targetVersion`. Exposed so tests can exercise
	steps before the schema version is bumped for real. ]]
function Migrations.runChain(saved: any, targetVersion: number, now: number): Result.Result<any>
	if type(saved) ~= "table" then
		return Result.err("MIGRATION_BAD_SAVE", "profile is not a table")
	end

	local version = saved.Version
	if type(version) ~= "number" or version ~= math.floor(version) or version < 1 then
		return Result.err("MIGRATION_BAD_VERSION", `invalid profile version {tostring(version)}`)
	end
	if version > targetVersion then
		return Result.err("MIGRATION_FUTURE", `profile version {version} is newer than this server`)
	end

	local current = saved
	while version < targetVersion do
		local step = steps[version]
		if not step then
			return Result.err("MIGRATION_MISSING", `no migration from version {version}`)
		end
		local ok, migrated = pcall(step, current, now)
		if not ok then
			return Result.err("MIGRATION_FAILED", tostring(migrated))
		end
		current = migrated
		version += 1
		current.Version = version
	end

	return Result.ok(Profile.reconcile(Profile.template(now), current))
end

return Migrations
