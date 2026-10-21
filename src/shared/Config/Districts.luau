--!strict
--[[
	Districts and their gates (GDD §A14). `arrivalHoursMin/Max` are targets for
	`tools/economy_sim.luau`; they are not enforced at runtime.
]]

local Types = require(script.Parent.Parent.Core.Types)

local Districts = {}

export type DistrictDef = Types.DistrictDef

Districts.list = {
	{
		id = "Starter",
		index = 1,
		name = "Starter District",
		blurb = "Where every empire begins: a corner store, a few parcels and a dream.",
		unlock = {},
		arrivalHoursMin = 0,
		arrivalHoursMax = 0,
		plotOrigin = { row = 0, column = 0 },
		accentColor = { 0.42, 0.78, 0.45 },
		contentVersion = 1,
	},
	{
		id = "Shopping",
		index = 2,
		name = "Shopping District",
		blurb = "Retail therapy at scale: boutiques, a mall and a cinema.",
		unlock = {
			{ kind = "NetWorth", min = 25_000 },
			{ kind = "DistrictPct", district = "Starter", min = 40 },
		},
		arrivalHoursMin = 2,
		arrivalHoursMax = 4,
		plotOrigin = { row = 0, column = 1 },
		accentColor = { 0.93, 0.6, 0.32 },
		contentVersion = 1,
	},
	{
		id = "Financial",
		index = 3,
		name = "Financial District",
		blurb = "Glass towers, leases and money that makes money.",
		unlock = {
			{ kind = "NetWorth", min = 1_000_000 },
			{ kind = "DistrictPct", district = "Shopping", min = 35 },
			{ kind = "Reputation", min = 250 },
		},
		arrivalHoursMin = 8,
		arrivalHoursMax = 14,
		plotOrigin = { row = 1, column = 0 },
		accentColor = { 0.35, 0.6, 0.9 },
		contentVersion = 1,
	},
	{
		id = "Luxury",
		index = 4,
		name = "Luxury District",
		blurb = "Mansions, waterfront estates and the garages that go with them.",
		unlock = {
			{ kind = "NetWorth", min = 25_000_000 },
			{ kind = "DistrictPct", district = "Financial", min = 30 },
			{ kind = "Population", min = 5000 },
		},
		arrivalHoursMin = 22,
		arrivalHoursMax = 32,
		plotOrigin = { row = 1, column = 1 },
		accentColor = { 0.85, 0.72, 0.35 },
		contentVersion = 1,
	},
	{
		id = "Entertainment",
		index = 5,
		name = "Entertainment District",
		blurb = "Stadiums, arenas and event nights that empty every other district.",
		unlock = {
			{ kind = "NetWorth", min = 250_000_000 },
			{ kind = "DistrictPct", district = "Shopping", min = 60 },
			{ kind = "DistrictPct", district = "Luxury", min = 25 },
			{ kind = "Happiness", min = 60 },
		},
		arrivalHoursMin = 40,
		arrivalHoursMax = 55,
		plotOrigin = { row = 2, column = 0 },
		accentColor = { 0.85, 0.4, 0.75 },
		contentVersion = 1,
	},
	{
		id = "Industrial",
		index = 6,
		name = "Industrial District",
		blurb = "Factories, warehouses and supply chains that feed the whole city.",
		unlock = {
			{ kind = "NetWorth", min = 2_500_000_000 },
			{ kind = "DistrictPct", district = "Financial", min = 50 },
			{ kind = "Research", node = "industrial_technology_1" },
			{ kind = "Population", min = 25_000 },
		},
		arrivalHoursMin = 60,
		arrivalHoursMax = 80,
		plotOrigin = { row = 2, column = 1 },
		accentColor = { 0.55, 0.55, 0.6 },
		contentVersion = 1,
	},
	{
		id = "Transportation",
		index = 7,
		name = "Transportation District",
		blurb = "Roads, rail and an airport that brings the world to your door.",
		unlock = {
			{ kind = "NetWorth", min = 25_000_000_000 },
			{ kind = "DistrictPct", district = "Industrial", min = 35 },
			{ kind = "DistrictPct", district = "Entertainment", min = 35 },
			{ kind = "Research", node = "transportation_2" },
		},
		arrivalHoursMin = 80,
		arrivalHoursMax = 105,
		plotOrigin = { row = 3, column = 0 },
		accentColor = { 0.4, 0.8, 0.85 },
		contentVersion = 1,
	},
	{
		id = "Billionaire",
		index = 8,
		name = "Billionaire District",
		blurb = "The signature tower, the grand plaza and the view from the top.",
		unlock = {
			{ kind = "NetWorth", min = 250_000_000_000 },
			{ kind = "PrestigePoints", min = 100 },
			{ kind = "Legacy", id = "billionaire" },
			{ kind = "Legacy", id = "corporate_executive" },
		},
		arrivalHoursMin = 105,
		arrivalHoursMax = 135,
		plotOrigin = { row = 3, column = 1 },
		accentColor = { 0.6, 0.5, 0.95 },
		contentVersion = 1,
	},
}

Districts.byId = {}
for _, def in ipairs(Districts.list) do
	Districts.byId[def.id] = def
end

Districts.STARTER = "Starter"

return Districts
