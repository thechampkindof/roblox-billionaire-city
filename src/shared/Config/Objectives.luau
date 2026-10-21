--!strict
--[[
	The first-15-minutes objective chain.

	Every step is one data row conforming to `Types.ObjectiveGoal`. `ObjectiveService`
	measures them through `Core/Objectives`; there is no per-objective code anywhere.
]]

local Types = require(script.Parent.Parent.Core.Types)

local Objectives = {}

export type ObjectiveDef = Types.ObjectiveDef

Objectives.chainId = "starter"

Objectives.list = {
	{
		id = "starter_collect_income",
		index = 1,
		title = "First takings",
		description = "Collect income from your Convenience Store.",
		goal = { kind = "CollectCash", amount = 50 },
		rewardCash = 100,
		rewardXp = 40,
		contentVersion = 1,
	},
	{
		id = "starter_first_upgrade",
		index = 2,
		title = "Sharpen the shop",
		description = "Buy any upgrade for your Convenience Store.",
		goal = { kind = "UpgradePurchase", count = 1 },
		rewardCash = 150,
		rewardXp = 60,
		contentVersion = 1,
	},
	{
		id = "starter_hire_staff",
		index = 3,
		title = "Help wanted",
		description = "Hire your first worker.",
		goal = { kind = "HireStaff", count = 1 },
		rewardCash = 200,
		rewardXp = 80,
		contentVersion = 1,
	},
	{
		id = "starter_second_parcel",
		index = 4,
		title = "Room to grow",
		description = "Buy a second parcel of land.",
		goal = { kind = "OwnParcels", count = 2 },
		rewardCash = 250,
		rewardXp = 100,
		contentVersion = 1,
	},
	{
		id = "starter_manager",
		index = 5,
		title = "Time to delegate",
		description = "Hire a manager so the store collects for you.",
		goal = { kind = "HireManager", count = 1 },
		rewardCash = 400,
		rewardXp = 150,
		contentVersion = 1,
	},
}

Objectives.byId = {}
for _, def in ipairs(Objectives.list) do
	Objectives.byId[def.id] = def
end

function Objectives.first(): Types.ObjectiveDef
	return Objectives.list[1]
end

return Objectives
