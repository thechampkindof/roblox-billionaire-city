--!strict
--[[
	Parcel grid for the Starter District.

	One plot per player holds eight district zones on a fixed grid. Phase 1 defines the
	Starter zone (4x4 parcels) and reserves the district origins for later phases.
	`landCost` is a base price; `ParcelService` applies the owned-parcel multiplier from
	`Balance.Land`. Unbuilt parcels are markers only — no models exist until a building
	does (Appendix B7).
]]

local Types = require(script.Parent.Parent.Core.Types)
local Balance = require(script.Parent.Balance)

local Parcels = {}

export type ParcelDef = Types.ParcelDef

local function parcel(
	id: string,
	row: number,
	column: number,
	size: Types.ParcelSize,
	landCost: number,
	starter: boolean,
	requires: Types.Requirements?
): Types.ParcelDef
	return {
		id = id,
		district = "Starter",
		row = row,
		column = column,
		size = size,
		landCost = landCost,
		requires = requires or {},
		allowed = nil,
		starter = starter,
		contentVersion = 1,
	}
end

-- Row-major 4x4 grid. The starter parcel is free and pre-owned; every other parcel
-- is bought with cash, and later rows carry a small net-worth gate.
local layout: { { size: Types.ParcelSize, cost: number, minNetWorth: number? } } = {
	{ size = "S", cost = 0, minNetWorth = nil }, -- starter_01
	{ size = "S", cost = 300 },
	{ size = "S", cost = 300 },
	{ size = "M", cost = 460 },
	{ size = "S", cost = 420 },
	{ size = "S", cost = 420 },
	{ size = "M", cost = 620 },
	{ size = "M", cost = 620, minNetWorth = 1500 },
	{ size = "S", cost = 560 },
	{ size = "M", cost = 820 },
	{ size = "M", cost = 820, minNetWorth = 2500 },
	{ size = "M", cost = 820, minNetWorth = 2500 },
	{ size = "S", cost = 900, minNetWorth = 5000 },
	{ size = "M", cost = 1300, minNetWorth = 5000 },
	{ size = "M", cost = 1300, minNetWorth = 8000 },
	{ size = "M", cost = 1800, minNetWorth = 12000 },
}

Parcels.list = {}
for index, entry in ipairs(layout) do
	local row = math.floor((index - 1) / 4) + 1
	local column = ((index - 1) % 4) + 1
	local id = string.format("starter_%02d", index)
	local requires: Types.Requirements = {}
	if entry.minNetWorth then
		table.insert(requires, { kind = "NetWorth", min = entry.minNetWorth })
	end
	Parcels.list[index] = parcel(id, row, column, entry.size, entry.cost, index == 1, requires)
end

Parcels.byId = {}
for _, def in ipairs(Parcels.list) do
	Parcels.byId[def.id] = def
end

Parcels.STARTER_PARCEL = "starter_01"
Parcels.STARTER_BUILDING = "convenience_store"

--[[ Final land price for a parcel given how many parcels the player already owns. ]]
function Parcels.priceFor(def: Types.ParcelDef, ownedCount: number): number
	if def.landCost <= 0 then
		return 0
	end
	local extra = math.max(0, ownedCount - 1)
	local multiplier = Balance.Land.costGrowthPerOwnedParcel ^ extra
	return math.max(1, math.floor(def.landCost * multiplier + 0.5))
end

return Parcels
