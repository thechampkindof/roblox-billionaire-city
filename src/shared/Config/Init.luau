--!strict
--[[
	Content aggregator: one require for every definition plus read-only indexes.

	Systems depend on this module, never on individual data files, so adding content is a
	data edit. Everything here is static and immutable at runtime.
]]

local Types = require(script.Parent.Parent.Core.Types)
local Balance = require(script.Parent.Balance)
local Flags = require(script.Parent.Flags)
local Archetypes = require(script.Parent.Archetypes)
local Buildings = require(script.Parent.Buildings)
local Upgrades = require(script.Parent.Upgrades)
local Parcels = require(script.Parent.Parcels)
local Districts = require(script.Parent.Districts)
local Staff = require(script.Parent.Staff)
local Objectives = require(script.Parent.Objectives)
local Strings = require(script.Parent.Strings)
local Economy = require(script.Parent.Parent.Core.Economy)

local Content = {}

Content.Balance = Balance
Content.Flags = Flags
Content.Archetypes = Archetypes

Content.buildings = Buildings.list
Content.upgrades = Upgrades.all()
Content.parcels = Parcels.list
Content.districts = Districts.list
Content.staff = Staff.all()
Content.objectives = Objectives.list
Content.strings = Strings

local buildingById: { [string]: Types.BuildingDef } = {}
for _, def in ipairs(Content.buildings) do
	buildingById[def.id] = def
end
Content.buildingById = buildingById

Content.upgradeById = Upgrades.byId
Content.parcelById = Parcels.byId
Content.districtById = Districts.byId

local staffById: { [string]: Types.StaffGradeDef } = {}
for _, def in ipairs(Content.staff) do
	staffById[def.id] = def
end
Content.staffById = staffById

local objectiveById: { [string]: Types.ObjectiveDef } = {}
for _, def in ipairs(Content.objectives) do
	objectiveById[def.id] = def
end
Content.objectiveById = objectiveById

Content.starterParcelId = Parcels.STARTER_PARCEL
Content.starterBuildingId = Parcels.STARTER_BUILDING
Content.starterDistrictId = Districts.STARTER

--[[ Upgrade ids generated for a building, in generation order. ]]
function Content.upgradeIdsFor(buildingId: string): { string }
	return Upgrades.idsByBuilding[buildingId] or {}
end

--[[ Upgrade definitions for a building grouped by category. ]]
function Content.upgradesByCategory(buildingId: string): { [string]: { Types.UpgradeDef } }
	local grouped: { [string]: { Types.UpgradeDef } } = {}
	for _, category in ipairs(Upgrades.categoryOrder) do
		grouped[category] = {}
	end
	for _, id in ipairs(Content.upgradeIdsFor(buildingId)) do
		local def = Content.upgradeById[id]
		if def then
			table.insert(grouped[def.category], def)
		end
	end
	return grouped
end

--[[ Parcels belonging to a district, in data order. ]]
function Content.parcelsFor(districtId: string): { Types.ParcelDef }
	local list: { Types.ParcelDef } = {}
	for _, def in ipairs(Content.parcels) do
		if def.district == districtId then
			table.insert(list, def)
		end
	end
	return list
end

--[[ Buildings allowed on a parcel, filtered by size and district. ]]
function Content.buildingsForParcel(parcel: Types.ParcelDef): { Types.BuildingDef }
	local list: { Types.BuildingDef } = {}
	for _, def in ipairs(Content.buildings) do
		if def.district ~= parcel.district then
			continue
		end
		if not Content.fitsSize(def.parcelSize, parcel.size) then
			continue
		end
		if parcel.allowed then
			local allowed = false
			for _, id in ipairs(parcel.allowed) do
				if id == def.id then
					allowed = true
					break
				end
			end
			if not allowed then
				continue
			end
		end
		table.insert(list, def)
	end
	return list
end

local SIZE_ORDER = { S = 1, M = 2, L = 3, XL = 4 }

--[[ A building fits when its footprint is no larger than the parcel. ]]
function Content.fitsSize(buildingSize: string, parcelSize: string): boolean
	local building = SIZE_ORDER[buildingSize]
	local parcel = SIZE_ORDER[parcelSize]
	if not building or not parcel then
		return false
	end
	return building <= parcel
end

--[[ Cost of the next level of an upgrade line. ]]
function Content.upgradeCost(upgradeId: string, currentLevel: number): number
	local def = Content.upgradeById[upgradeId]
	if not def then
		return math.huge
	end
	local base = def.baseCost.cash or 0
	return Economy.cost(base, def.growth, currentLevel + 1)
end

--[[ The cheapest cash price for a building (first phase). ]]
function Content.firstPhaseCost(def: Types.BuildingDef): number
	local firstPhase = def.phases[1]
	if not firstPhase then
		return 0
	end
	return firstPhase.cost.cash or 0
end

--[[ Total cash needed to finish every phase of a building. ]]
function Content.totalBuildCost(def: Types.BuildingDef): number
	local total = 0
	for _, phaseDef in ipairs(def.phases) do
		total += phaseDef.cost.cash or 0
	end
	return total
end

return Content
