--!strict
--[[
	Archetype upgrade templates.

	An archetype is a *family* of properties sharing an upgrade tree shape (six
	categories). `Config/Upgrades` expands these templates into concrete `UpgradeDef`s
	per building and applies hand-tuned overrides. Hand-editing 500+ lines is not
	feasible, so the templates are the default and overrides are the exception.

	Template fields:
	  slug         stable id fragment, used to build the upgrade id
	  name         player-facing name
	  description  one line shown in the Building Panel
	  stat/op/perLevel  effect applied per level (see Core/Types.Effect)
	  maxLevel     cap for this line (further capped by category caps)
	  costFactor   multiplier on the category cost (rarer/stronger lines cost more)
	  tier         1..3; tier 2+ lines carry a net-worth gate from `Balance.Upgrades`
]]

local Archetypes = {}

export type Line = {
	slug: string,
	name: string,
	description: string,
	stat: string,
	op: string,
	perLevel: number,
	maxLevel: number,
	costFactor: number,
	tier: number,
}

export type Template = { [string]: { Line } }

local function line(
	slug: string,
	name: string,
	description: string,
	stat: string,
	op: string,
	perLevel: number,
	maxLevel: number,
	costFactor: number,
	tier: number
): Line
	return {
		slug = slug,
		name = name,
		description = description,
		stat = stat,
		op = op,
		perLevel = perLevel,
		maxLevel = maxLevel,
		costFactor = costFactor,
		tier = tier,
	}
end

local Construction = "Construction"
local Staffing = "Staffing"
local Equipment = "Equipment"
local Business = "Business"
local Appearance = "Appearance"
local MasteryCat = "Mastery"

Archetypes.Retail = {
	[Construction] = {
		line(
			"storefront",
			"Storefront",
			"Wider entrance and a cleaner shopfront draw more shoppers.",
			"revenue",
			"add",
			0.05,
			8,
			1.0,
			1
		),
		line(
			"floor_space",
			"Floor Space",
			"More aisles means more customers served at once.",
			"capacity",
			"add",
			6,
			10,
			1.1,
			1
		),
		line(
			"stockroom",
			"Stockroom",
			"Bulk storage lowers restock costs.",
			"expense",
			"add",
			-0.03,
			8,
			1.2,
			2
		),
	},
	[Staffing] = {
		line(
			"cashiers",
			"Cashiers",
			"Extra checkout staff move the queue faster.",
			"revenue",
			"add",
			0.04,
			10,
			1.0,
			1
		),
		line(
			"shift_leads",
			"Shift Leads",
			"Good supervision trims waste.",
			"expense",
			"add",
			-0.03,
			8,
			1.15,
			2
		),
		line(
			"training",
			"Staff Training",
			"Trained teams learn the business faster.",
			"masteryXp",
			"add",
			0.06,
			6,
			0.9,
			2
		),
	},
	[Equipment] = {
		line(
			"registers",
			"Registers",
			"Faster scanning serves more shoppers.",
			"capacity",
			"add",
			5,
			12,
			1.0,
			1
		),
		line(
			"shelving",
			"Shelving",
			"Better displays sell more per visit.",
			"revenue",
			"add",
			0.06,
			12,
			1.05,
			1
		),
		line(
			"freezer",
			"Cold Storage",
			"Fewer spoiled goods, more stock on hand.",
			"capacity",
			"add",
			4,
			10,
			1.1,
			2
		),
		line(
			"self_checkout",
			"Self Checkout",
			"Cut labour per transaction.",
			"revenue",
			"add",
			0.07,
			8,
			1.35,
			3
		),
	},
	[Business] = {
		line(
			"marketing",
			"Local Marketing",
			"Flyers and radio spots bring new faces in.",
			"revenue",
			"add",
			0.08,
			12,
			1.0,
			1
		),
		line(
			"product_quality",
			"Product Quality",
			"Better goods justify a higher basket total.",
			"revenue",
			"add",
			0.06,
			12,
			1.15,
			1
		),
		line(
			"pricing",
			"Pricing Strategy",
			"Smarter margins keep more of each sale.",
			"expense",
			"add",
			-0.04,
			10,
			1.1,
			2
		),
		line(
			"loyalty",
			"Loyalty Program",
			"Regulars spend more, more often.",
			"revenue",
			"add",
			0.05,
			10,
			1.3,
			3
		),
	},
	[Appearance] = {
		line(
			"signage",
			"Signage",
			"A sign people can actually see.",
			"revenue",
			"add",
			0.02,
			6,
			1.0,
			1
		),
		line(
			"lighting",
			"Lighting",
			"Bright windows invite evening shoppers.",
			"revenue",
			"add",
			0.02,
			6,
			1.0,
			1
		),
		line(
			"facade",
			"Facade",
			"A landmark facade for the neighbourhood.",
			"revenue",
			"add",
			0.03,
			5,
			1.4,
			2
		),
	},
	[MasteryCat] = {
		line(
			"legacy_brand",
			"Legacy Brand",
			"A name the whole city trusts.",
			"revenue",
			"add",
			0.03,
			5,
			1.2,
			2
		),
		line(
			"collection",
			"Signature Collection",
			"Curated goods only regulars can buy.",
			"masteryXp",
			"add",
			0.08,
			5,
			1.1,
			1
		),
	},
}

Archetypes.Food = {
	[Construction] = {
		line(
			"dining_room",
			"Dining Room",
			"More seats, more covers per service.",
			"capacity",
			"add",
			5,
			10,
			1.0,
			1
		),
		line(
			"kitchen",
			"Kitchen",
			"A bigger line keeps orders moving.",
			"revenue",
			"add",
			0.05,
			10,
			1.15,
			1
		),
		line(
			"ventilation",
			"Ventilation",
			"A comfortable room keeps tables turning.",
			"expense",
			"add",
			-0.03,
			8,
			1.2,
			2
		),
	},
	[Staffing] = {
		line(
			"line_cooks",
			"Line Cooks",
			"More hands at the pass.",
			"revenue",
			"add",
			0.045,
			10,
			1.0,
			1
		),
		line(
			"waiters",
			"Floor Staff",
			"Faster service and happier tables.",
			"capacity",
			"add",
			4,
			10,
			1.05,
			1
		),
		line(
			"head_chef",
			"Head Chef",
			"Consistency cuts waste and complaints.",
			"expense",
			"add",
			-0.035,
			8,
			1.25,
			2
		),
	},
	[Equipment] = {
		line(
			"ovens",
			"Commercial Ovens",
			"Cook faster without burning anything.",
			"capacity",
			"add",
			5,
			12,
			1.0,
			1
		),
		line(
			"pos",
			"Tablet Ordering",
			"Orders reach the kitchen instantly.",
			"revenue",
			"add",
			0.05,
			10,
			1.1,
			2
		),
		line(
			"fridge",
			"Walk-in Fridge",
			"Buy in bulk, waste less.",
			"expense",
			"add",
			-0.04,
			8,
			1.15,
			2
		),
	},
	[Business] = {
		line(
			"menu",
			"Menu Design",
			"Signature dishes sell themselves.",
			"revenue",
			"add",
			0.06,
			12,
			1.0,
			1
		),
		line(
			"reviews",
			"Review Campaign",
			"Good press fills the room.",
			"revenue",
			"add",
			0.07,
			10,
			1.15,
			2
		),
		line(
			"suppliers",
			"Supplier Deals",
			"Cheaper ingredients at the same quality.",
			"expense",
			"add",
			-0.04,
			10,
			1.05,
			1
		),
		line(
			"delivery",
			"Delivery Partners",
			"Sell beyond the dining room.",
			"revenue",
			"add",
			0.05,
			10,
			1.3,
			3
		),
	},
	[Appearance] = {
		line(
			"neon",
			"Neon Sign",
			"Impossible to miss at night.",
			"revenue",
			"add",
			0.02,
			6,
			1.0,
			1
		),
		line(
			"terrace",
			"Terrace",
			"Outdoor seating doubles the floor.",
			"revenue",
			"add",
			0.03,
			5,
			1.3,
			2
		),
	},
	[MasteryCat] = {
		line(
			"house_special",
			"House Special",
			"The dish people cross town for.",
			"revenue",
			"add",
			0.035,
			5,
			1.2,
			2
		),
		line(
			"kitchen_legacy",
			"Kitchen Legacy",
			"Techniques passed down the line.",
			"masteryXp",
			"add",
			0.08,
			5,
			1.1,
			1
		),
	},
}

Archetypes.Service = {
	[Construction] = {
		line(
			"bays",
			"Service Bays",
			"Handle more customers at once.",
			"capacity",
			"add",
			4,
			10,
			1.0,
			1
		),
		line(
			"waiting_area",
			"Waiting Area",
			"Comfortable queues keep customers.",
			"revenue",
			"add",
			0.05,
			10,
			1.05,
			1
		),
		line(
			"utility_run",
			"Utility Run",
			"Bulk utilities cut monthly bills.",
			"expense",
			"add",
			-0.03,
			8,
			1.2,
			2
		),
	},
	[Staffing] = {
		line(
			"attendants",
			"Attendants",
			"Someone always available to help.",
			"revenue",
			"add",
			0.04,
			10,
			1.0,
			1
		),
		line(
			"supervisor",
			"Supervisor",
			"Fewer mistakes, less wasted stock.",
			"expense",
			"add",
			-0.03,
			8,
			1.15,
			2
		),
	},
	[Equipment] = {
		line("tools", "Pro Tools", "Faster jobs per bay.", "capacity", "add", 5, 12, 1.0, 1),
		line(
			"diagnostics",
			"Diagnostics Kit",
			"Up-sell the right service first time.",
			"revenue",
			"add",
			0.06,
			10,
			1.15,
			2
		),
		line(
			"automation",
			"Automation",
			"Machines do the slow part.",
			"expense",
			"add",
			-0.045,
			8,
			1.35,
			3
		),
	},
	[Business] = {
		line(
			"local_ads",
			"Local Ads",
			"Be the first name people think of.",
			"revenue",
			"add",
			0.07,
			12,
			1.0,
			1
		),
		line(
			"memberships",
			"Memberships",
			"Predictable recurring revenue.",
			"revenue",
			"add",
			0.05,
			10,
			1.2,
			2
		),
		line(
			"contracts",
			"Fleet Contracts",
			"Steady work from local businesses.",
			"revenue",
			"add",
			0.06,
			10,
			1.35,
			3
		),
	},
	[Appearance] = {
		line("paint", "Fresh Paint", "Clean and trustworthy.", "revenue", "add", 0.02, 6, 1.0, 1),
		line(
			"canopy",
			"Canopy",
			"Shade for customers and cars.",
			"revenue",
			"add",
			0.025,
			5,
			1.2,
			2
		),
	},
	[MasteryCat] = {
		line(
			"local_legend",
			"Local Legend",
			"The neighbourhood institution.",
			"revenue",
			"add",
			0.03,
			5,
			1.2,
			2
		),
		line(
			"apprentice_program",
			"Apprentice Program",
			"Your craft spreads.",
			"masteryXp",
			"add",
			0.08,
			5,
			1.1,
			1
		),
	},
}

Archetypes.Residential = {
	[Construction] = {
		line(
			"units",
			"Extra Units",
			"More homes on the same land.",
			"capacity",
			"add",
			4,
			10,
			1.0,
			1
		),
		line(
			"balconies",
			"Balconies",
			"A view is worth more rent.",
			"revenue",
			"add",
			0.05,
			10,
			1.05,
			1
		),
		line(
			"insulation",
			"Insulation",
			"Lower heating and cooling bills.",
			"expense",
			"add",
			-0.03,
			8,
			1.2,
			2
		),
	},
	[Staffing] = {
		line(
			"caretaker",
			"Caretaker",
			"Small fixes before they become big ones.",
			"expense",
			"add",
			-0.03,
			8,
			1.0,
			1
		),
		line(
			"concierge",
			"Concierge",
			"Service that justifies the rent.",
			"revenue",
			"add",
			0.04,
			8,
			1.15,
			2
		),
	},
	[Equipment] = {
		line(
			"appliances",
			"Appliances",
			"Modern fittings attract tenants.",
			"revenue",
			"add",
			0.05,
			10,
			1.0,
			1
		),
		line(
			"smart_home",
			"Smart Home",
			"Lower running costs, higher appeal.",
			"expense",
			"add",
			-0.04,
			8,
			1.15,
			2
		),
	},
	[Business] = {
		line(
			"listings",
			"Listing Quality",
			"Photos that fill vacancies fast.",
			"revenue",
			"add",
			0.06,
			10,
			1.0,
			1
		),
		line(
			"referrals",
			"Resident Referrals",
			"Happy tenants bring friends.",
			"revenue",
			"add",
			0.05,
			10,
			1.2,
			2
		),
	},
	[Appearance] = {
		line("landscaping", "Landscaping", "Kerbside appeal.", "revenue", "add", 0.02, 6, 1.0, 1),
		line(
			"roof_garden",
			"Roof Garden",
			"A shared space tenants love.",
			"revenue",
			"add",
			0.03,
			5,
			1.35,
			2
		),
	},
	[MasteryCat] = {
		line(
			"landmark_home",
			"Landmark Home",
			"The address everyone knows.",
			"revenue",
			"add",
			0.03,
			5,
			1.2,
			2
		),
		line(
			"community",
			"Community Events",
			"Neighbours become a neighbourhood.",
			"masteryXp",
			"add",
			0.08,
			5,
			1.1,
			1
		),
	},
}

Archetypes.Office = {
	[Construction] = {
		line("floors", "Extra Floors", "More lettable space.", "capacity", "add", 5, 10, 1.0, 1),
		line(
			"lobby",
			"Lobby",
			"A first impression that closes leases.",
			"revenue",
			"add",
			0.05,
			10,
			1.1,
			1
		),
		line("hvac", "HVAC", "Comfortable tenants renew.", "expense", "add", -0.035, 8, 1.2, 2),
	},
	[Staffing] = {
		line(
			"reception",
			"Reception",
			"A human answers the phone.",
			"revenue",
			"add",
			0.04,
			10,
			1.0,
			1
		),
		line(
			"facilities",
			"Facilities Team",
			"Fewer emergency call-outs.",
			"expense",
			"add",
			-0.03,
			8,
			1.15,
			2
		),
	},
	[Equipment] = {
		line(
			"elevators",
			"Elevators",
			"Nobody waits on the ground floor.",
			"capacity",
			"add",
			5,
			12,
			1.05,
			1
		),
		line(
			"fiber",
			"Fiber Internet",
			"Tenants pay for speed.",
			"revenue",
			"add",
			0.06,
			10,
			1.15,
			2
		),
		line(
			"security",
			"Security System",
			"Lower insurance, higher trust.",
			"expense",
			"add",
			-0.04,
			8,
			1.2,
			2
		),
	},
	[Business] = {
		line("leasing", "Leasing Team", "Shorter vacancies.", "revenue", "add", 0.07, 12, 1.0, 1),
		line(
			"tenant_mix",
			"Tenant Mix",
			"Anchor tenants lift the whole building.",
			"revenue",
			"add",
			0.05,
			10,
			1.25,
			2
		),
		line(
			"corporate_rates",
			"Corporate Rates",
			"Long leases at better margins.",
			"revenue",
			"add",
			0.06,
			10,
			1.35,
			3
		),
	},
	[Appearance] = {
		line(
			"signage_tower",
			"Tower Sign",
			"Your name on the skyline.",
			"revenue",
			"add",
			0.02,
			6,
			1.0,
			1
		),
		line(
			"plaza",
			"Ground Plaza",
			"A place to meet before a meeting.",
			"revenue",
			"add",
			0.025,
			5,
			1.3,
			2
		),
	},
	[MasteryCat] = {
		line(
			"signature_tower",
			"Signature Tower",
			"An address that sells itself.",
			"revenue",
			"add",
			0.035,
			5,
			1.2,
			2
		),
		line(
			"exec_network",
			"Executive Network",
			"Deals follow the people.",
			"masteryXp",
			"add",
			0.08,
			5,
			1.1,
			1
		),
	},
}

return Archetypes
