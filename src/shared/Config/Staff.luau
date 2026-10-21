--!strict
--[[
	Staff grades (GDD §A7). Staff are abstract: hired counts per building, no simulated
	humanoids. Wages are part of operating expenses, efficiency multiplies their output.
]]

local Types = require(script.Parent.Parent.Core.Types)
local Balance = require(script.Parent.Balance)

local Staff = {}

export type StaffGradeDef = Types.StaffGradeDef

Staff.order = { "Basic", "Skilled", "Expert", "Executive" }

Staff.byId = {
	Basic = {
		id = "Basic",
		name = "Shop Assistant",
		hireCost = Balance.Staff.Basic.hireCost,
		wagePerMin = Balance.Staff.Basic.wagePerMin,
		efficiency = Balance.Staff.Basic.efficiency,
		requires = {},
		contentVersion = 1,
	},
	Skilled = {
		id = "Skilled",
		name = "Skilled Worker",
		hireCost = Balance.Staff.Skilled.hireCost,
		wagePerMin = Balance.Staff.Skilled.wagePerMin,
		efficiency = Balance.Staff.Skilled.efficiency,
		requires = { { kind = "NetWorth", min = 2500 } },
		contentVersion = 1,
	},
	Expert = {
		id = "Expert",
		name = "Expert",
		hireCost = Balance.Staff.Expert.hireCost,
		wagePerMin = Balance.Staff.Expert.wagePerMin,
		efficiency = Balance.Staff.Expert.efficiency,
		requires = { { kind = "NetWorth", min = 40_000 } },
		contentVersion = 1,
	},
	Executive = {
		id = "Executive",
		name = "Executive",
		hireCost = Balance.Staff.Executive.hireCost,
		wagePerMin = Balance.Staff.Executive.wagePerMin,
		efficiency = Balance.Staff.Executive.efficiency,
		requires = { { kind = "NetWorth", min = 500_000 } },
		contentVersion = 1,
	},
}

function Staff.all(): { StaffGradeDef }
	local list: { StaffGradeDef } = {}
	for _, id in ipairs(Staff.order) do
		table.insert(list, Staff.byId[id])
	end
	return list
end

return Staff
