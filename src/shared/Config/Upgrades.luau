--!strict
--[[
	Upgrade lines, generated from archetype templates.

	`Config/Archetypes` describes the tree shape; this module expands it for every
	building, giving ~200 lines for the Starter District alone without hand-editing a
	single one. Hand-tuned exceptions would live in `overrides` below, keyed by the
	generated id — there are none in Phase 1, and adding one is a data edit.
]]

local Types = require(script.Parent.Parent.Core.Types)
local Balance = require(script.Parent.Balance)
local Archetypes = require(script.Parent.Archetypes)
local Buildings = require(script.Parent.Buildings)

local Upgrades = {}

export type UpgradeDef = Types.UpgradeDef

local CATEGORY_ORDER: { Types.UpgradeCategory } = {
	"Construction",
	"Staffing",
	"Equipment",
	"Business",
	"Appearance",
	"Mastery",
}

type GeneratedLine = {
	category: Types.UpgradeCategory,
	def: Types.UpgradeDef,
}

local upgradeById: { [string]: Types.UpgradeDef } = {}
local idsByBuilding: { [string]: { string } } = {}

local function makeId(buildingId: string, category: string, slug: string): string
	return `{buildingId}:{category}:{slug}`
end

for _, building in ipairs(Buildings.list) do
	local template = Archetypes[building.archetype]
	if not template then
		error(`archetype "{building.archetype}" has no upgrade template (building {building.id})`)
	end

	local ids: { string } = {}
	for _, category in ipairs(CATEGORY_ORDER) do
		local lines = template[category]
		if not lines then
			continue
		end

		local categoryCostFactor = Balance.Upgrades.categoryCostFactor[category]
		local growth = Balance.Upgrades.categoryGrowth[category]
		local categoryCap = Balance.Upgrades.categoryMaxLevel[category]

		for _, line in ipairs(lines) do
			local id = makeId(building.id, category, line.slug)
			if upgradeById[id] then
				error(`duplicate upgrade id "{id}"`)
			end

			local requires: Types.Requirements = {}
			if line.tier >= 2 then
				table.insert(
					requires,
					{ kind = "NetWorth", min = Balance.Upgrades.tierTwoNetWorth }
				)
			end
			if line.tier >= 3 then
				table.insert(
					requires,
					{ kind = "NetWorth", min = Balance.Upgrades.tierThreeNetWorth }
				)
			end

			local tierFactor = 1 + 0.12 * math.max(0, line.tier - 1)
			local baseCost = math.max(
				1,
				math.floor(
					building.upgradeCostBase * categoryCostFactor * line.costFactor * tierFactor
						+ 0.5
				)
			)

			local def: Types.UpgradeDef = {
				id = id,
				category = category,
				name = line.name,
				description = line.description,
				maxLevel = math.min(line.maxLevel, categoryCap),
				baseCost = { cash = baseCost },
				growth = growth,
				effect = {
					stat = line.stat :: any,
					op = line.op :: any,
					perLevel = line.perLevel,
				},
				requires = requires,
				tier = line.tier,
				buildingId = building.id,
				generated = true,
				contentVersion = 1,
			}

			upgradeById[id] = def
			table.insert(ids, id)
		end
	end
	idsByBuilding[building.id] = ids
end

Upgrades.byId = upgradeById
Upgrades.idsByBuilding = idsByBuilding
Upgrades.categoryOrder = CATEGORY_ORDER

--[[ All upgrade definitions, in stable (building, category, slug) order. ]]
function Upgrades.all(): { Types.UpgradeDef }
	local list: { Types.UpgradeDef } = {}
	for _, building in ipairs(Buildings.list) do
		for _, id in ipairs(idsByBuilding[building.id] or {}) do
			table.insert(list, upgradeById[id])
		end
	end
	return list
end

return Upgrades
