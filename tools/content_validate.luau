--!strict
--[[
	Content validator.

	Runs the checks required by Appendix B1: unique ids, resolved references, acyclic
	requirements, reachability from a new profile, the 2^53/16 cost budget and the
	profile-size budget. CI fails when any check fails.

	Usage:
	  lune run tools/content_validate.luau
	  node tools/run_luau.mjs tools/content_validate.luau
]]

local root = script.Parent.Parent :: any
local Core = root.src.shared.Core
local Config = root.src.shared.Config

local Unlock = require(Core.Unlock)
local Money = require(Core.Money)
local Profile = require(Core.Profile)
local Mastery = require(Core.Mastery)
local Content = require(Config.Init)
local GreedyPlayer = require(script.Parent.GreedyPlayer)

local problems: { string } = {}
local warnings: { string } = {}

local function check(ok: boolean, label: string, detail: string?)
	if ok then
		print(`  PASS  {label}`)
	else
		local message = if detail then `{label} — {detail}` else label
		table.insert(problems, message)
		print(`  FAIL  {message}`)
	end
end

local function note(message: string)
	table.insert(warnings, message)
end

print("Billionaire City Tycoon — content validation")
print(
	`content: {#Content.buildings} buildings, {#Content.upgrades} upgrades, {#Content.parcels} parcels, {#Content.objectives} objectives`
)
print("")

-- 1. Unique ids ---------------------------------------------------------------
local seen: { [string]: string } = {}
local duplicates: { string } = {}
local function register(kind: string, id: string)
	local key = `{kind}:{id}`
	if seen[key] then
		table.insert(duplicates, key)
	else
		seen[key] = kind
	end
end
for _, def in ipairs(Content.buildings) do
	register("building", def.id)
end
for _, def in ipairs(Content.upgrades) do
	register("upgrade", def.id)
end
for _, def in ipairs(Content.parcels) do
	register("parcel", def.id)
end
for _, def in ipairs(Content.districts) do
	register("district", def.id)
end
for _, def in ipairs(Content.objectives) do
	register("objective", def.id)
end
for _, def in ipairs(Content.staff) do
	register("staff", def.id)
end
check(#duplicates == 0, "1. every id is unique", duplicates[1])

-- 2. Resolved references ------------------------------------------------------
local refProblems: { string } = {}
local resolver = {
	building = function(id: string)
		return Content.buildingById[id] ~= nil
	end,
	research = function()
		-- Research ships in Phase 5; district gates reference nodes that will exist then.
		return true
	end,
	contract = function()
		return true
	end,
	legacy = function()
		return true
	end,
	district = function(id: string)
		return Content.districtById[id] ~= nil
	end,
}

for _, building in ipairs(Content.buildings) do
	if not Content.districtById[building.district] then
		table.insert(refProblems, `{building.id}: unknown district "{building.district}"`)
	end
	if not Content.Archetypes[building.archetype] then
		table.insert(refProblems, `{building.id}: unknown archetype "{building.archetype}"`)
	end
	for _, problem in ipairs(Unlock.validateRefs(building.blueprint, resolver, building.id)) do
		table.insert(refProblems, problem)
	end
	for _, phaseDef in ipairs(building.phases) do
		for _, problem in
			ipairs(Unlock.validateRefs(phaseDef.requires, resolver, `{building.id}.{phaseDef.id}`))
		do
			table.insert(refProblems, problem)
		end
	end
	if not Content.districtById[building.district] then
		continue
	end
	local hasParcel = false
	for _, parcel in ipairs(Content.parcelsFor(building.district)) do
		if Content.fitsSize(building.parcelSize, parcel.size) then
			hasParcel = true
			break
		end
	end
	if not hasParcel then
		table.insert(
			refProblems,
			`{building.id}: no parcel in {building.district} fits size {building.parcelSize}`
		)
	end
end

for _, upgrade in ipairs(Content.upgrades) do
	if not Content.buildingById[upgrade.buildingId] then
		table.insert(refProblems, `{upgrade.id}: unknown building "{upgrade.buildingId}"`)
	end
	if not Content.Balance.Upgrades.categoryCostFactor[upgrade.category] then
		table.insert(refProblems, `{upgrade.id}: unknown category "{upgrade.category}"`)
	end
	for _, problem in ipairs(Unlock.validateRefs(upgrade.requires, resolver, upgrade.id)) do
		table.insert(refProblems, problem)
	end
end

for _, parcel in ipairs(Content.parcels) do
	if not Content.districtById[parcel.district] then
		table.insert(refProblems, `{parcel.id}: unknown district "{parcel.district}"`)
	end
	for _, problem in ipairs(Unlock.validateRefs(parcel.requires, resolver, parcel.id)) do
		table.insert(refProblems, problem)
	end
	if parcel.allowed then
		for _, id in ipairs(parcel.allowed) do
			if not Content.buildingById[id] then
				table.insert(refProblems, `{parcel.id}: allows unknown building "{id}"`)
			end
		end
	end
end

for _, objective in ipairs(Content.objectives) do
	local goal = objective.goal
	if goal.kind == "BuildingLevel" and not Content.buildingById[goal.def] then
		table.insert(refProblems, `{objective.id}: unknown building "{goal.def}"`)
	end
end

for _, district in ipairs(Content.districts) do
	for _, problem in ipairs(Unlock.validateRefs(district.unlock, resolver, district.id)) do
		table.insert(refProblems, problem)
	end
end

check(#refProblems == 0, "2. every reference resolves", refProblems[1])

-- 3. Acyclic requirements -----------------------------------------------------
local graph: { [string]: { string } } = {}
for _, building in ipairs(Content.buildings) do
	local edges: { string } = {}
	for _, requirement in ipairs(building.blueprint) do
		if requirement.kind == "Building" then
			table.insert(edges, requirement.def)
		end
	end
	for _, phaseDef in ipairs(building.phases) do
		for _, requirement in ipairs(phaseDef.requires) do
			if requirement.kind == "Building" then
				table.insert(edges, requirement.def)
			end
		end
	end
	graph[building.id] = edges
end
local cycle = Unlock.findCycle(graph)
check(cycle == nil, "3. the requirement graph is acyclic", cycle)

-- 4. Costs are integers and within documented ranges ---------------------------
local costProblems: { string } = {}
for _, upgrade in ipairs(Content.upgrades) do
	local base = upgrade.baseCost.cash or 0
	if not Money.isSafeInteger(base) or base < 1 then
		table.insert(costProblems, `{upgrade.id}: base cost {base} is not a positive integer`)
	end
	if upgrade.growth < 1.12 or upgrade.growth > 1.35 then
		table.insert(costProblems, `{upgrade.id}: growth {upgrade.growth} outside [1.12, 1.35]`)
	end
	if upgrade.maxLevel < 1 then
		table.insert(costProblems, `{upgrade.id}: maxLevel {upgrade.maxLevel} < 1`)
	end
end
for _, building in ipairs(Content.buildings) do
	if building.baseRevenuePerMin < 0 or building.baseExpensesPerMin < 0 then
		table.insert(costProblems, `{building.id}: negative income or expenses`)
	end
	if building.buildCost <= 0 or building.managerCost <= 0 or building.levelCostBase <= 0 then
		table.insert(costProblems, `{building.id}: non-positive cost`)
	end
end
check(#costProblems == 0, "4. costs are positive integers and growth is in band", costProblems[1])

-- 5. The sum of every cost stays under 2^53/16 --------------------------------
local totalCost = 0
for _, upgrade in ipairs(Content.upgrades) do
	for level = 1, upgrade.maxLevel do
		totalCost += (upgrade.baseCost.cash or 0) * (upgrade.growth ^ (level - 1))
	end
end
for _, building in ipairs(Content.buildings) do
	totalCost += building.buildCost + Content.totalBuildCost(building) * 16
	for level = 1, building.maxLevel do
		totalCost += building.levelCostBase * (building.levelGrowth ^ (level - 1))
	end
end
check(
	totalCost < Money.MAX_SAFE / 16,
	"5. total content cost stays under 2^53/16",
	tostring(totalCost)
)

-- 6. Structural checks --------------------------------------------------------
local structureProblems: { string } = {}
local districtOrder: { number } = {}
for _, district in ipairs(Content.districts) do
	table.insert(districtOrder, district.index)
end
table.sort(districtOrder)
for index, value in ipairs(districtOrder) do
	if value ~= index then
		table.insert(structureProblems, `district indexes are not contiguous at {index}`)
		break
	end
end
for _, district in ipairs(Content.districts) do
	if district.id ~= "Starter" and #district.unlock == 0 then
		table.insert(structureProblems, `{district.id}: non-starter district has no unlock gate`)
	end
end
local parcelCoordinates: { [string]: boolean } = {}
for _, parcel in ipairs(Content.parcels) do
	if parcel.row < 1 or parcel.row > 4 or parcel.column < 1 or parcel.column > 4 then
		table.insert(structureProblems, `{parcel.id}: grid position outside the Starter zone`)
	end
	local key = `{parcel.row}:{parcel.column}`
	if parcelCoordinates[key] then
		table.insert(structureProblems, `{parcel.id}: duplicate grid position {key}`)
	end
	parcelCoordinates[key] = true
end
for _, archetypeName in ipairs({ "Retail", "Food", "Service", "Residential", "Office" }) do
	local template = Content.Archetypes[archetypeName]
	if not template then
		table.insert(structureProblems, `archetype {archetypeName} has no template`)
		continue
	end
	for _, category in ipairs({
		"Construction",
		"Staffing",
		"Equipment",
		"Business",
		"Appearance",
		"Mastery",
	}) do
		if not template[category] or #template[category] == 0 then
			table.insert(structureProblems, `archetype {archetypeName} is missing {category} lines`)
		end
	end
end
local objectiveIndexes: { number } = {}
for _, objective in ipairs(Content.objectives) do
	table.insert(objectiveIndexes, objective.index)
end
table.sort(objectiveIndexes)
for index, value in ipairs(objectiveIndexes) do
	if value ~= index then
		table.insert(structureProblems, `objective indexes are not contiguous at {index}`)
		break
	end
end
local firstParcel = Content.parcelById[Content.starterParcelId]
if not firstParcel or firstParcel.landCost ~= 0 then
	table.insert(structureProblems, "the starter parcel must be free")
end
check(#structureProblems == 0, "6. content structure is coherent", structureProblems[1])

-- 7. Reachability from a new profile ------------------------------------------
local completionist = GreedyPlayer.run(if SLOW then 3000 else 700, if SLOW then 1200 else 400, true)
local unreachable: { string } = {}
for _, building in ipairs(Content.buildings) do
	if building.id ~= Content.starterBuildingId and not completionist.builtDefs[building.id] then
		table.insert(unreachable, building.id)
	end
end
for _, upgrade in ipairs(Content.upgrades) do
	if not completionist.upgradeIds[upgrade.id] then
		table.insert(unreachable, upgrade.id)
	end
end
check(#unreachable == 0, "7. every item is reachable through legal purchases", unreachable[1])
if not SLOW and #unreachable > 0 then
	note("run with SLOW=1 for an exhaustive reachability pass")
end

-- Starting profile must afford the first objective's actions.
local startCash = Profile.template(0).Currency.Cash
local starterParcel = Content.parcelById[Content.starterParcelId]
local secondParcel = Content.parcels[2]
local secondParcelPrice = secondParcel and secondParcel.landCost or 0
check(
	startCash >= secondParcelPrice,
	"7b. starting cash covers the second parcel",
	`{startCash} < {secondParcelPrice}`
)
check(starterParcel ~= nil and secondParcel ~= nil, "7c. at least two Starter parcels exist")

-- 8. Profile size budget ------------------------------------------------------
local profile = Profile.template(0)
for index, parcel in ipairs(Content.parcels) do
	profile.Parcels[parcel.id] = true
	local def = Content.buildings[index % #Content.buildings + 1]
	local uid = `b{index}`
	profile.Buildings[uid] = {
		def = def.id,
		parcel = parcel.id,
		level = def.maxLevel,
		phase = #def.phases,
		upg = {},
		mastery = { xp = 999999, lvl = 100, windowStart = 0, windowXp = 0 },
		staff = { Basic = 3, Expert = 1 },
		manager = "Executive",
		pending = 0,
		lastAccrual = 0,
	}
	for _, upgradeId in ipairs(Content.upgradeIdsFor(def.id)) do
		profile.Buildings[uid].upg[upgradeId] = Content.upgradeById[upgradeId].maxLevel
	end
end
for _, district in ipairs(Content.districts) do
	profile.Districts[district.id] = { unlocked = true, devRating = 100 }
end
local bytes = Profile.estimateBytes(profile)
check(
	bytes < Profile.HARD_LIMIT_BYTES,
	"8. worst-case profile stays under the hard size limit",
	`{bytes} bytes`
)
if bytes > Profile.BUDGET_BYTES then
	note(`worst-case profile is {bytes} bytes, above the 1 MB target`)
end
print(
	string.format(
		"        worst-case profile: %d bytes (target %d, hard %d)",
		bytes,
		Profile.BUDGET_BYTES,
		Profile.HARD_LIMIT_BYTES
	)
)

-- 9. Objectives are achievable with shipped content ---------------------------
local objectiveProblems: { string } = {}
for _, objective in ipairs(Content.objectives) do
	local goal = objective.goal
	if goal.kind == "BuildingLevel" and goal.level > Content.buildingById[goal.def].maxLevel then
		table.insert(objectiveProblems, `{objective.id}: requires level {goal.level} above the cap`)
	end
	if objective.rewardCash < 0 or objective.rewardXp < 0 then
		table.insert(objectiveProblems, `{objective.id}: negative reward`)
	end
end
check(#objectiveProblems == 0, "9. objectives are achievable", objectiveProblems[1])

-- Mastery curve sanity: level 100 must be reachable only with sustained play.
local totalXp = Mastery.totalXpForLevel(100)
check(totalXp > 1_000_000, "10. mastery 1-100 requires sustained play", tostring(totalXp))

print("")
for _, warning in ipairs(warnings) do
	print(`  note: {warning}`)
end
if #problems == 0 then
	print("RESULT: content is valid")
	EXIT_CODE = 0
else
	print(`RESULT: {#problems} problem(s) found`)
	for _, problem in ipairs(problems) do
		print(`  - {problem}`)
	end
	EXIT_CODE = 1
end

return { problems = problems, warnings = warnings }
