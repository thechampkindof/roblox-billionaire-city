--!strict
local Framework = require(script.Parent.Parent.Framework)
local Profile = require(script.Parent.Parent.Parent.src.shared.Core.Profile)
local Migrations = require(script.Parent.Parent.Parent.src.shared.Core.Migrations)

Framework.test("a new profile starts with $500 and one starter district", function()
	local profile = Profile.template(1000)
	Framework.equal(profile.Version, Profile.CURRENT_VERSION)
	Framework.equal(profile.Currency.Cash, 500)
	Framework.equal(profile.Time.FirstJoin, 1000)
	Framework.isTrue(profile.Districts.Starter.unlocked)
	Framework.equal(next(profile.Buildings), nil, "no buildings yet")
	Framework.equal(profile.Research.seed, nil, "research shape matches the schema")
end)

Framework.test("reconcile fills missing fields and keeps saved values", function()
	local saved = {
		Version = 1,
		Currency = { Cash = 1234 },
		Settings = { quality = "low" },
		Buildings = {
			abc = { def = "convenience_store", parcel = "starter_01", level = 4 },
		},
	}
	local profile = Profile.normalise(saved, 5000)
	Framework.equal(profile.Currency.Cash, 1234)
	Framework.equal(profile.Currency.Reputation, 0, "missing currency filled from template")
	Framework.equal(profile.Settings.quality, "low")
	Framework.equal(profile.Settings.sfx, true, "missing setting filled")
	Framework.equal(profile.Buildings.abc.level, 4, "extra keys preserved")
	Framework.equal(profile.Time.LastSaved, 5000)
end)

Framework.test("reconcile replaces type mismatches with template values", function()
	local saved = { Currency = { Cash = "lots" }, Objectives = { index = "three" } }
	local profile = Profile.normalise(saved, 0)
	Framework.equal(profile.Currency.Cash, 500)
	Framework.equal(profile.Objectives.index, 1)
end)

Framework.test("reconcile survives corrupt saves", function()
	local profile = Profile.normalise("not a table", 42)
	Framework.equal(profile.Currency.Cash, 500)
	local kept = Profile.reconcile({ a = 1, b = 2 }, { a = 5 })
	Framework.equal(kept.a, 5)
	Framework.equal(kept.b, 2)
end)

Framework.test("profile size estimate stays inside the 1 MB budget", function()
	local profile = Profile.template(1700000000)
	for index = 1, 120 do
		profile.Buildings[`uid_{index}`] = {
			def = "convenience_store",
			parcel = `starter_{index}`,
			level = 12,
			phase = 2,
			upg = { ["convenience_store:Business:marketing"] = 20 },
			mastery = { xp = 250000, lvl = 42, windowStart = 1700000000, windowXp = 10 },
			staff = { Basic = 3 },
			pending = 123456,
			lastAccrual = 1700000000,
		}
	end
	local bytes = Profile.estimateBytes(profile)
	Framework.isTrue(bytes > 0)
	Framework.isTrue(bytes < Profile.BUDGET_BYTES, `estimate {bytes} under budget`)
end)

Framework.test("migrations reject future and unknown versions", function()
	Migrations.clearRegistered()
	local future = Migrations.migrate({ Version = Migrations.CURRENT_VERSION + 1 }, 0)
	Framework.equal(future.code, "MIGRATION_FUTURE")

	local bad = Migrations.migrate({ Version = "one" }, 0)
	Framework.equal(bad.code, "MIGRATION_BAD_VERSION")

	local notTable = Migrations.migrate(42, 0)
	Framework.equal(notTable.code, "MIGRATION_BAD_SAVE")
end)

Framework.test("migrations run registered steps in order", function()
	Migrations.clearRegistered()
	Migrations.register(1, function(profile: any)
		Framework.equal(profile.Version, 1)
		profile.Currency.Cash = 900
		return profile
	end)
	local result = Migrations.runChain({ Version = 1, Currency = { Cash = 0 } }, 2, 1234)
	Framework.isTrue(result.ok, result.message)
	Framework.equal(result.data.Currency.Cash, 900, "step applied")
	Framework.equal(result.data.Version, 2, "chain reports the target version")
	Migrations.clearRegistered()
end)

Framework.test("current-version saves pass straight through", function()
	Migrations.clearRegistered()
	local result =
		Migrations.migrate({ Version = Migrations.CURRENT_VERSION, Currency = { Cash = 77 } }, 5)
	Framework.isTrue(result.ok)
	Framework.equal(result.data.Currency.Cash, 77)
	Framework.equal(result.data.Stats.LifetimeEarned, 0, "missing fields filled")
end)
