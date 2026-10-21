--!strict
--[[
	Profile size budget (Appendix B3).

	DataStores cap a value at ~4 MB and serialising gets expensive long before that, so the
	budget is 1 MB with a 3 MB hard fail. This tool builds the *largest* profile the current
	content can produce (every building, every upgrade line maxed, every parcel, every
	collection entry) and reports where the bytes go.

	Usage:
	  node tools/run_luau.mjs tools/size_budget.luau
	  lune run tools/size_budget.luau
]]

local root = script.Parent.Parent :: any
local Core = root.src.shared.Core
local Config = root.src.shared.Config

local Profile = require(Core.Profile)
local Mastery = require(Core.Mastery)
local Uid = require(Core.Uid)
local Content = require(Config.Init)

local problems: { string } = {}

local function fail(message: string)
	table.insert(problems, message)
	print(`  FAIL  {message}`)
end

local function pass(label: string, detail: string?)
	print(`  PASS  {label}{if detail then " — " .. detail else ""}`)
end

print("Billionaire City Tycoon — profile size budget")
print("")

-- 1. Worst case: all content unlocked, maxed and completed ---------------------

local now = 1_700_000_000
local profile = Profile.template(now)

profile.Currency.Cash = 2 ^ 50
profile.Currency.Reputation = 1e6
profile.Currency.PrestigePoints = 1e6
profile.Currency.ResearchPoints = 1e6
profile.Stats.LifetimeEarned = 2 ^ 50
profile.Stats.PlaySeconds = 10_000_000
profile.Stats.NetWorthPeak = 2 ^ 50

for _, district in ipairs(Content.districts) do
	profile.Districts[district.id] = { unlocked = true, devRating = 100 }
end

for _, parcel in ipairs(Content.parcels) do
	profile.Parcels[parcel.id] = true
end

-- One building per parcel, cycling through everything that fits.
local index = 0
for _, parcel in ipairs(Content.parcels) do
	local candidates = Content.buildingsForParcel(parcel)
	local def = candidates[(index % math.max(1, #candidates)) + 1]
	index += 1
	if def then
		local uid = Uid.next(profile.Buildings)
		local upgrades: { [string]: number } = {}
		for _, upgradeId in ipairs(Content.upgradeIdsFor(def.id)) do
			local upgrade = Content.upgradeById[upgradeId]
			upgrades[upgradeId] = upgrade and upgrade.maxLevel or 0
		end
		local staff: { [string]: number } = {}
		for _, grade in ipairs(Content.staff) do
			staff[grade.id] = 1
		end
		profile.Buildings[uid] = {
			def = def.id,
			parcel = parcel.id,
			level = def.maxLevel,
			phase = #def.phases,
			upg = upgrades,
			mastery = {
				xp = Mastery.totalXpForLevel(Mastery.MAX_LEVEL),
				lvl = Mastery.MAX_LEVEL,
				windowStart = now,
				windowXp = 0,
			},
			staff = staff,
			manager = "Standard",
			constructing = nil,
			pending = 0,
			lastAccrual = now,
		}
	end
end

for _, objective in ipairs(Content.objectives) do
	profile.Objectives.completed[objective.id] = true
end
profile.Objectives.index = #Content.objectives + 1
for key = 1, 64 do
	profile.Objectives.progress[`metric_{key}`] = key * 1000
end

for key = 1, 64 do
	profile.Achievements[`achievement_{key}`] = true
	profile.Legacy[`legacy_{key}`] = true
	profile.Purchases[`purchase_{key}`] = true
	profile.Research.done[`node_{key}`] = true
	profile.Contracts.done[`contract_{key}`] = true
	profile.Collections.Vehicles[`vehicle_{key}`] = true
	profile.Collections.Houses[`house_{key}`] = true
	profile.Collections.Furniture[`furniture_{key}`] = true
	profile.Collections.Cosmetics[`cosmetic_{key}`] = true
end

local bytes = Profile.estimateBytes(profile)
print(
	string.format(
		"  buildings: %d   upgrade lines: %d   parcels: %d",
		#Content.buildings,
		#Content.upgrades,
		#Content.parcels
	)
)
print(string.format("  worst-case profile: %d bytes", bytes))
print("")

-- 2. Section breakdown ---------------------------------------------------------

local sections: { [string]: number } = {}
for key, value in profile do
	sections[key] = Profile.estimateBytes(value)
end

local order: { { name: string, bytes: number } } = {}
for name, size in sections do
	table.insert(order, { name = name, bytes = size })
end
table.sort(order, function(a, b)
	return a.bytes > b.bytes
end)

print("  largest sections:")
for index = 1, math.min(6, #order) do
	local entry = order[index]
	print(string.format("    %-14s %8d bytes", entry.name, entry.bytes))
end
print("")

-- 3. Budget assertions ---------------------------------------------------------

local budget = Profile.BUDGET_BYTES
local hard = Profile.HARD_LIMIT_BYTES

if bytes <= 250_000 then
	pass("comfortably inside the DataStore budget", string.format("%d / %d bytes", bytes, budget))
elseif bytes <= budget then
	pass("inside the DataStore budget", string.format("%d / %d bytes", bytes, budget))
else
	fail(string.format("worst case is %d bytes, budget is %d", bytes, budget))
end

if bytes > hard then
	fail(string.format("worst case exceeds the hard limit (%d > %d)", bytes, hard))
end

-- A typical profile must be far smaller than the worst case.
local typical = Profile.template(now)
typical.Parcels[Content.starterParcelId] = true
for _, parcel in ipairs(Content.parcels) do
	if parcel.starter then
		typical.Parcels[parcel.id] = true
	end
end
local starterDef = Content.buildingById[Content.starterBuildingId]
if starterDef then
	typical.Buildings["b1"] = {
		def = starterDef.id,
		parcel = Content.starterParcelId,
		level = 3,
		phase = #starterDef.phases,
		upg = { [Content.upgradeIdsFor(starterDef.id)[1]] = 2 },
		mastery = { xp = 500, lvl = 2, windowStart = now, windowXp = 0 },
		staff = { Basic = 1 },
		manager = nil,
		constructing = nil,
		pending = 0,
		lastAccrual = now,
	}
end
local typicalBytes = Profile.estimateBytes(typical)
print(string.format("  typical first-session profile: %d bytes", typicalBytes))
if typicalBytes > 20_000 then
	fail(string.format("typical profile is %d bytes, expected under 20 KB", typicalBytes))
else
	pass("typical profile is small", string.format("%d bytes", typicalBytes))
end

-- 4. Cost headroom (2^53 / 16 rule) -------------------------------------------

local Money = require(Core.Money)
local maxCost = 0
for _, upgrade in ipairs(Content.upgrades) do
	local base = upgrade.baseCost.cash or 0
	for level = 1, upgrade.maxLevel do
		-- Sum of the geometric line, the worst case a single purchase can ever cost.
		local cost = base * (upgrade.growth ^ level)
		if cost > maxCost then
			maxCost = cost
		end
	end
end
local limit = Money.MAX_SAFE / 16
if maxCost <= limit then
	pass("largest single purchase leaves headroom", string.format("%.0f of %.0f", maxCost, limit))
else
	fail(string.format("largest purchase %0.f exceeds the 2^53/16 budget %.0f", maxCost, limit))
end

print("")
if #problems > 0 then
	print(`RESULT: {#problems} problem(s)`)
	for _, problem in ipairs(problems) do
		print(`  - {problem}`)
	end
	EXIT_CODE = 1
else
	print("RESULT: profile size budget is healthy")
end
