--!strict
--[[
	Player-facing strings. Keeping error codes here means the server can return stable
	codes and the client can localise them later without touching services.
]]

local Strings = {}

Strings.appName = "Billionaire City Tycoon"

Strings.errors = {
	UNKNOWN_INTENT = "That action is not available.",
	INVALID_PAYLOAD = "Something went wrong with that request.",
	RATE_LIMITED = "Slow down for a second.",
	NOT_LOADED = "Your city is still loading. Try again in a moment.",
	NOT_OWNER = "That building is not yours.",
	NOT_FOUND = "That no longer exists.",
	PARCEL_OWNED = "You already own that parcel.",
	PARCEL_NOT_OWNED = "Buy that parcel first.",
	PARCEL_OCCUPIED = "Something is already built there.",
	PARCEL_TOO_SMALL = "That building does not fit on this parcel.",
	PARCEL_WRONG_DISTRICT = "That building belongs in another district.",
	LOCKED = "You have not unlocked that yet.",
	INSUFFICIENT_FUNDS = "Not enough cash.",
	INSUFFICIENT_PRESTIGE = "Not enough Prestige Points.",
	MAX_LEVEL = "Already at the maximum level.",
	ALREADY_CONSTRUCTING = "That building is already under construction.",
	NOT_CONSTRUCTING = "Nothing is under construction there.",
	CONSTRUCTION_PENDING = "Finish construction first.",
	STAFF_FULL = "No free staff slots. Upgrade staffing first.",
	MANAGER_REQUIRED_LEVEL = "That building is not established enough for a manager.",
	MANAGER_ALREADY_HIRED = "This building already has a manager.",
	NOTHING_TO_COLLECT = "Nothing to collect yet.",
	INVALID_ID = "Unrecognised selection.",
	SAVE_FAILED = "Your progress could not be saved. We will retry.",
	PROFILE_BUSY = "Your city is open in another server. Try again shortly.",
}

Strings.toasts = {
	plotAssigned = "Welcome to your city plot!",
	parcelPurchased = "Parcel purchased.",
	constructionStarted = "Construction started.",
	constructionComplete = "Construction complete!",
	upgradePurchased = "Upgrade purchased.",
	staffHired = "Worker hired.",
	managerHired = "Manager hired — income now collects automatically.",
	incomeCollected = "Income collected.",
	offlineIncome = "Welcome back! Offline income: %s",
	objectiveComplete = "Objective complete: %s",
	levelUp = "Level up!",
	masteryUp = "Mastery level %d reached.",
}

Strings.tabs = {
	overview = "Overview",
	upgrades = "Upgrades",
	staff = "Staff",
	income = "Income & Expenses",
	construction = "Construction",
	mastery = "Mastery",
	customization = "Customization",
}

Strings.categories = {
	Construction = "Construction",
	Staffing = "Staffing",
	Equipment = "Equipment",
	Business = "Business",
	Appearance = "Appearance",
	Mastery = "Mastery",
}

Strings.stub = "Coming in a later update."

return Strings
