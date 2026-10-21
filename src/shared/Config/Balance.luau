--!strict
--[[
	Every economy tunable in one place. Values marked `[ASSUMPTION]` in the GDD were not
	specified by the designer; they are implemented here so `tools/economy_sim.luau` can
	search for better ones without touching systems code.

	Change a number here, run `lune run tools/economy_sim.luau` (or `npm run sim`), and
	re-run the test suite. Nothing else should hard-code balance values.
]]

local Balance = {}

-- Session / lifecycle --------------------------------------------------------

Balance.AutoloadDelaySeconds = 5
Balance.AutosaveSeconds = 90 -- profile autosave cadence
Balance.SaveOnMilestoneSeconds = 5 -- debounce for milestone-triggered saves
Balance.OfflineCapHours = 4 -- [ASSUMPTION] GDD: "a few hours"
Balance.OfflineEfficiency = 0.5 -- [ASSUMPTION] GDD: "capped and computed from timestamp"
Balance.SessionLockWaitSeconds = 60
Balance.SaveRetries = 4
Balance.SaveRetryBackoffSeconds = 2

-- Economy math ---------------------------------------------------------------

Balance.Rates = {
	levelIncomeGrowth = 1.18,
	levelExpenseGrowth = 1.06,
	minNetFraction = 0.2, -- net profit is never below 20% of gross
	offlineCapHours = Balance.OfflineCapHours,
	offlineEfficiency = Balance.OfflineEfficiency,
	happinessMin = 0.9,
	happinessMax = 1.2,
}

-- Mastery --------------------------------------------------------------------

Balance.Mastery = {
	enabled = true,
	maxLevel = 100,
	xpPerCashCollected = 0.08, -- XP per $1 of income actually collected
	xpPerCashSpent = 0.02, -- XP per $1 spent on upgrades of the property
	softCapPerHour = 1500, -- XP where the diminishing-returns curve halves gains
	windowSeconds = 3600,
	milestones = {
		[5] = 0.02,
		[10] = 0.03,
		[25] = 0.05,
		[50] = 0.08,
		[75] = 0.1,
		[100] = 0.15,
	},
}

-- Upgrades -------------------------------------------------------------------

Balance.Upgrades = {
	-- Multiplies the building's `upgradeCostBase` for lines in each category.
	categoryCostFactor = {
		Construction = 2.2,
		Staffing = 1.9,
		Equipment = 1.5,
		Business = 1.3,
		Appearance = 0.8,
		Mastery = 3.0,
	},
	categoryGrowth = {
		Construction = 1.17,
		Staffing = 1.16,
		Equipment = 1.15,
		Business = 1.16,
		Appearance = 1.12,
		Mastery = 1.18,
	},
	categoryMaxLevel = {
		Construction = 12,
		Staffing = 15,
		Equipment = 20,
		Business = 20,
		Appearance = 10,
		Mastery = 10,
	},
	-- Net worth gate in front of the third tier of lines (keeps the early tree flat).
	tierTwoNetWorth = 5000,
	tierThreeNetWorth = 75000,
}

-- Staff ----------------------------------------------------------------------

Balance.Staff = {
	-- Wages are per minute and are part of operating expenses.
	Basic = { hireCost = 120, wagePerMin = 6, efficiency = 1.0 },
	Skilled = { hireCost = 900, wagePerMin = 26, efficiency = 1.6 },
	Expert = { hireCost = 6500, wagePerMin = 95, efficiency = 2.4 },
	Executive = { hireCost = 48000, wagePerMin = 420, efficiency = 3.6 },
	-- Every assigned worker adds this fraction of base revenue.
	revenuePerWorker = 0.04,
	maxPerSlot = 1,
}

-- Construction ---------------------------------------------------------------

Balance.Construction = {
	-- Construction lasts at most this long so a returning player is never blocked.
	maxSeconds = 15 * 60,
	-- Finishing an in-progress phase early costs this premium per remaining second.
	rushCostPerSecond = 4,
}

-- Land -----------------------------------------------------------------------

Balance.Land = {
	-- Land cost grows for each parcel already owned in the same district.
	costGrowthPerOwnedParcel = 1.35,
	-- Parcels unlock district development rating (0..100).
	devRatingPerParcel = 4,
}

-- Completion ----------------------------------------------------------------

Balance.CompletionWeights = {
	buildings = 20,
	upgrades = 20,
	mastery = 15,
	research = 10,
	collections = 15,
	achievements = 15,
	secrets = 5,
}

-- Networking / rate limiting ------------------------------------------------

Balance.RateLimit = {
	default = { capacity = 20, refillPerSecond = 4 },
	ParcelPurchase = { capacity = 6, refillPerSecond = 1 },
	ConstructStart = { capacity = 6, refillPerSecond = 1 },
	UpgradePurchase = { capacity = 20, refillPerSecond = 8 },
	StaffHire = { capacity = 8, refillPerSecond = 2 },
	ManagerHire = { capacity = 4, refillPerSecond = 0.5 },
	IncomeCollect = { capacity = 12, refillPerSecond = 4 },
	ObjectivePin = { capacity = 4, refillPerSecond = 0.5 },
	SettingsSet = { capacity = 4, refillPerSecond = 0.5 },
}

Balance.Network = {
	snapshotChunkBytes = 24_000, -- keep under the 50 KB remote payload budget
	patchHz = 4,
}

-- World ----------------------------------------------------------------------

Balance.World = {
	maxPlots = 12,
	plotSpacing = 420,
	districtTileStuds = 320,
	parcelStuds = 32,
	parcelGapStuds = 2,
	parcelThickness = 1,
	hubRadius = 90,
}

Balance.UI = {
	toastSeconds = 4,
	mobileScale = 0.92,
	panelWidth = 620,
	-- Ambient life budget: [ASSUMPTION] tuned for mid-range phones.
	ambientAgents = {
		low = 10,
		medium = 22,
		high = 40,
	},
}

return Balance
