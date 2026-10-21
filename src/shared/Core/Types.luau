--!strict
--[[
	Shared type definitions for content (data) and runtime (profile) shapes.

	`Core/Types` is pure Luau: it never touches the Roblox API, so both the headless
	unit tests and the server can require it. Content modules under `Config` are
	*data*; they are typed against these definitions.
]]

export type DistrictId =
	"Starter"
	| "Shopping"
	| "Financial"
	| "Luxury"
	| "Entertainment"
	| "Industrial"
	| "Transportation"
	| "Billionaire"

export type UpgradeCategory =
	"Construction"
	| "Staffing"
	| "Equipment"
	| "Business"
	| "Appearance"
	| "Mastery"

export type Archetype =
	"Retail"
	| "Food"
	| "Service"
	| "Residential"
	| "Office"
	| "Finance"
	| "Hospitality"
	| "Venue"
	| "Industry"
	| "Logistics"
	| "Transit"
	| "Landmark"
	| "Civic"

export type ParcelSize = "S" | "M" | "L" | "XL"

-- Requirements --------------------------------------------------------------

export type Requirement =
	{ kind: "NetWorth", min: number }
	| { kind: "Reputation", min: number }
	| { kind: "Population", min: number }
	| { kind: "Happiness", min: number }
	| { kind: "PrestigePoints", min: number }
	| { kind: "DistrictPct", district: DistrictId, min: number }
	| { kind: "Research", node: string }
	| { kind: "Building", def: string, level: number? }
	| { kind: "Contract", id: string }
	| { kind: "Legacy", id: string }

export type Requirements = { Requirement }

-- Costs ---------------------------------------------------------------------

export type Cost = {
	cash: number?,
	prestige: number?,
	research: number?,
	materials: { [string]: number }?,
}

-- Content -------------------------------------------------------------------

export type EffectStat =
	"revenue" -- multiplicative on gross revenue
	| "expense" -- multiplicative on operating expenses
	| "capacity" -- additive customer capacity
	| "staffSlots" -- additive employee slots
	| "masteryXp" -- multiplicative on mastery XP gained

export type Effect = {
	stat: EffectStat,
	op: "add" | "mult",
	perLevel: number,
}

export type UpgradeDef = {
	id: string,
	category: UpgradeCategory,
	name: string,
	description: string,
	maxLevel: number,
	baseCost: Cost,
	growth: number,
	effect: Effect,
	requires: Requirements,
	tier: number,
	buildingId: string,
	generated: boolean,
	contentVersion: number,
}

export type PhaseDef = {
	id: string,
	name: string,
	cost: Cost,
	seconds: number,
	requires: Requirements,
	visual: string,
}

export type BuildingDef = {
	id: string,
	district: DistrictId,
	archetype: Archetype,
	name: string,
	description: string,
	parcelSize: ParcelSize,
	landCost: number,
	buildCost: number,
	buildSeconds: number,
	blueprint: Requirements,
	phases: { PhaseDef },
	baseRevenuePerMin: number,
	baseExpensesPerMin: number,
	capacity: number,
	staffSlots: number,
	upgradeLines: { string },
	-- Level curve for this property (prices come from `Util/BuildingMath`).
	maxLevel: number,
	levelCostBase: number,
	levelGrowth: number,
	-- Per-line upgrade price anchor; generated lines multiply it by their tier factor.
	upgradeCostBase: number,
	managerCost: number,
	managerMinLevel: number,
	managerRequires: Requirements,
	masteryEnabled: boolean,
	style: string,
	tier: number,
	requiredForCompletion: boolean,
	contentVersion: number,
}

export type ParcelDef = {
	id: string,
	district: DistrictId,
	-- Grid coordinates inside the district zone (1-based, row/column).
	row: number,
	column: number,
	size: ParcelSize,
	landCost: number,
	requires: Requirements,
	-- Restricts what may be built here. `nil` = any building of the district that fits the size.
	allowed: { string }?,
	starter: boolean,
	contentVersion: number,
}

export type DistrictDef = {
	id: DistrictId,
	index: number,
	name: string,
	blurb: string,
	unlock: Requirements,
	arrivalHoursMin: number,
	arrivalHoursMax: number,
	plotOrigin: { row: number, column: number },
	accentColor: { number },
	contentVersion: number,
}

export type StaffGradeDef = {
	id: string,
	name: string,
	hireCost: number,
	wagePerMin: number,
	efficiency: number,
	requires: Requirements,
	contentVersion: number,
}

export type ObjectiveDef = {
	id: string,
	index: number,
	title: string,
	description: string,
	-- Generic, data-driven success test evaluated by `Core/Objectives`.
	goal: ObjectiveGoal,
	rewardCash: number,
	rewardXp: number,
	contentVersion: number,
}

export type ObjectiveGoal =
	{ kind: "CollectCash", amount: number }
	| { kind: "UpgradePurchase", count: number }
	| { kind: "HireStaff", count: number }
	| { kind: "OwnParcels", count: number }
	| { kind: "HireManager", count: number }
	| { kind: "BuildingLevel", def: string, level: number }

-- Profile (runtime) ---------------------------------------------------------

export type BuildingUpgradeState = { [string]: number }

export type BuildingMastery = {
	xp: number,
	lvl: number,
	-- Timestamp + XP at the start of the current soft-cap window.
	windowStart: number,
	windowXp: number,
}

export type ConstructionState = {
	phase: number, -- the phase currently under construction
	startedAt: number,
	seconds: number,
}

export type BuildingState = {
	def: string,
	parcel: string,
	level: number,
	phase: number, -- last completed phase
	upg: BuildingUpgradeState,
	mastery: BuildingMastery,
	staff: { [string]: number },
	manager: string?,
	constructing: ConstructionState?,
	pending: number, -- uncollected income, in cash
	lastAccrual: number, -- os.time() of last income accrual
}

export type DistrictState = {
	unlocked: boolean,
	devRating: number,
}

export type CurrencyState = {
	Cash: number,
	Reputation: number,
	PrestigePoints: number,
	ResearchPoints: number,
}

export type StatsState = {
	LifetimeEarned: number,
	PlaySeconds: number,
	NetWorthPeak: number,
}

export type TimeState = {
	FirstJoin: number,
	LastSaved: number,
	LastSeen: number,
}

export type ObjectivesState = {
	chain: string,
	index: number,
	progress: { [string]: number },
	completed: { [string]: boolean },
	pinned: string?,
}

export type Profile = {
	Version: number,
	Currency: CurrencyState,
	Stats: StatsState,
	Time: TimeState,
	Parcels: { [string]: boolean },
	Buildings: { [string]: BuildingState },
	Districts: { [string]: DistrictState },
	Research: { done: { [string]: boolean }, active: { [string]: boolean } },
	Contracts: { active: { [string]: boolean }, done: { [string]: boolean }, seed: number },
	Objectives: ObjectivesState,
	Collections: {
		Vehicles: { [string]: boolean },
		Houses: { [string]: boolean },
		Furniture: { [string]: boolean },
		Cosmetics: { [string]: boolean },
	},
	Achievements: { [string]: boolean },
	Legacy: { [string]: boolean },
	Settings: { [string]: boolean | number | string },
	Purchases: { [string]: boolean },
}

-- Net -----------------------------------------------------------------------

export type Result<T> = {
	ok: boolean,
	code: string,
	message: string?,
	data: T?,
}

export type PlotSlot = {
	index: number,
	originX: number,
	originZ: number,
}

return {}
