--!strict
--[[
	Generic objective evaluation.

	The first-15-minutes chain is data (`Config/Objectives`); this module contains the
	only place that knows how to measure a goal. Adding an objective later means adding
	a goal kind here plus a data row — never a special case in a service.
]]

export type Goal = any

export type ObjectiveContext = {
	cashCollected: number,
	upgradesPurchased: number,
	staffHired: number,
	parcelsOwned: number,
	managersHired: number,
	buildingLevel: (def: string) -> number,
}

export type Progress = {
	current: number,
	target: number,
	done: boolean,
	fraction: number,
}

local Objectives = {}

function Objectives.defaultContext(): ObjectiveContext
	return {
		cashCollected = 0,
		upgradesPurchased = 0,
		staffHired = 0,
		parcelsOwned = 0,
		managersHired = 0,
		buildingLevel = function()
			return 0
		end,
	}
end

--[[ Measures one goal against the context. Unknown goal kinds never complete. ]]
function Objectives.measure(goal: Goal, context: ObjectiveContext): Progress
	local current = 0
	local target = 1
	local kind = goal.kind
	local known = true
	if kind == "CollectCash" then
		current = context.cashCollected
		target = goal.amount
	elseif kind == "UpgradePurchase" then
		current = context.upgradesPurchased
		target = goal.count
	elseif kind == "HireStaff" then
		current = context.staffHired
		target = goal.count
	elseif kind == "OwnParcels" then
		current = context.parcelsOwned
		target = goal.count
	elseif kind == "HireManager" then
		current = context.managersHired
		target = goal.count
	elseif kind == "BuildingLevel" then
		current = context.buildingLevel(goal.def)
		target = goal.level
	else
		known = false
	end

	current = math.max(0, current)
	-- An unknown goal is never satisfiable; a known goal with a zero target is
	-- satisfied immediately (useful for onboarding hand-offs).
	target = if known then math.max(0, target) else 1
	local fraction = if target <= 0 then 1 else math.clamp(current / target, 0, 1)
	return {
		current = current,
		target = target,
		done = known and current >= target,
		fraction = if known then fraction else 0,
	}
end

return Objectives
