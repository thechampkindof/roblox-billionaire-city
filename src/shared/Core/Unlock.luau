--!strict
--[[
	Requirement evaluation.

	Content carries requirements as data (`Core/Types.Requirement`); this module turns a
	list of them into an answer plus human-readable gaps. It is used by land purchase,
	construction, upgrades, districts and the content validator (cycle detection).
]]

export type Requirement = any

export type Context = {
	netWorth: number,
	reputation: number,
	population: number,
	happiness: number,
	prestigePoints: number,
	districtPct: (district: string) -> number,
	research: (node: string) -> boolean,
	buildingLevel: (def: string) -> number,
	contractDone: (id: string) -> boolean,
	legacy: (id: string) -> boolean,
}

export type Unmet = {
	requirement: Requirement,
	-- 0..1 progress toward this single requirement, for objective UI.
	progress: number,
	description: string,
}

export type Evaluation = {
	ok: boolean,
	unmet: { Unmet },
	-- Mean progress across requirements, used for pinned-goal progress bars.
	progress: number,
}

local Unlock = {}

function Unlock.defaultContext(): Context
	return {
		netWorth = 0,
		reputation = 0,
		population = 0,
		happiness = 0,
		prestigePoints = 0,
		districtPct = function()
			return 0
		end,
		research = function()
			return false
		end,
		buildingLevel = function()
			return 0
		end,
		contractDone = function()
			return false
		end,
		legacy = function()
			return false
		end,
	}
end

local function ratio(current: number, target: number): number
	if target <= 0 then
		return 1
	end
	return math.clamp(current / target, 0, 1)
end

--[[ Evaluates a single requirement. ]]
function Unlock.evaluateOne(requirement: Requirement, context: Context): Unmet?
	local kind = requirement.kind
	if kind == "NetWorth" then
		local progress = ratio(context.netWorth, requirement.min)
		if progress >= 1 then
			return nil
		end
		return {
			requirement = requirement,
			progress = progress,
			description = `Net worth {requirement.min}`,
		}
	elseif kind == "Reputation" then
		local progress = ratio(context.reputation, requirement.min)
		if progress >= 1 then
			return nil
		end
		return {
			requirement = requirement,
			progress = progress,
			description = `Reputation {requirement.min}`,
		}
	elseif kind == "Population" then
		local progress = ratio(context.population, requirement.min)
		if progress >= 1 then
			return nil
		end
		return {
			requirement = requirement,
			progress = progress,
			description = `Population {requirement.min}`,
		}
	elseif kind == "Happiness" then
		local progress = ratio(context.happiness, requirement.min)
		if progress >= 1 then
			return nil
		end
		return {
			requirement = requirement,
			progress = progress,
			description = `Happiness {requirement.min}`,
		}
	elseif kind == "PrestigePoints" then
		local progress = ratio(context.prestigePoints, requirement.min)
		if progress >= 1 then
			return nil
		end
		return {
			requirement = requirement,
			progress = progress,
			description = `Prestige Points {requirement.min}`,
		}
	elseif kind == "DistrictPct" then
		local progress = ratio(context.districtPct(requirement.district), requirement.min)
		if progress >= 1 then
			return nil
		end
		return {
			requirement = requirement,
			progress = progress,
			description = `{requirement.district} district {requirement.min}% complete`,
		}
	elseif kind == "Research" then
		if context.research(requirement.node) then
			return nil
		end
		return {
			requirement = requirement,
			progress = 0,
			description = `Research {requirement.node}`,
		}
	elseif kind == "Building" then
		local level = context.buildingLevel(requirement.def)
		local target = requirement.level or 1
		local progress = ratio(level, target)
		if progress >= 1 then
			return nil
		end
		return {
			requirement = requirement,
			progress = progress,
			description = `{requirement.def} level {target}`,
		}
	elseif kind == "Contract" then
		if context.contractDone(requirement.id) then
			return nil
		end
		return { requirement = requirement, progress = 0, description = `Contract {requirement.id}` }
	elseif kind == "Legacy" then
		if context.legacy(requirement.id) then
			return nil
		end
		return { requirement = requirement, progress = 0, description = `Legacy {requirement.id}` }
	end

	-- Unknown requirement kinds are treated as unmet-but-not-fatal so a content
	-- mistake surfaces in the validator rather than crashing a player's session.
	return {
		requirement = requirement,
		progress = 0,
		description = `Unknown requirement "{tostring(kind)}"`,
	}
end

--[[ Evaluates a list of requirements (all must pass). ]]
function Unlock.evaluate(requirements: { Requirement }?, context: Context): Evaluation
	if not requirements or #requirements == 0 then
		return { ok = true, unmet = {}, progress = 1 }
	end
	local unmet: { Unmet } = {}
	local total = 0
	for _, requirement in ipairs(requirements) do
		local miss = Unlock.evaluateOne(requirement, context)
		if miss then
			table.insert(unmet, miss)
			total += miss.progress
		else
			total += 1
		end
	end
	return {
		ok = #unmet == 0,
		unmet = unmet,
		progress = total / #requirements,
	}
end

--[[
	Static check used by `tools/content_validate`: requirements may only reference
	content that exists, and `Building` requirements may not point at themselves.
]]
export type RefResolver = {
	building: (id: string) -> boolean,
	research: (id: string) -> boolean,
	contract: (id: string) -> boolean,
	legacy: (id: string) -> boolean,
	district: (id: string) -> boolean,
}

function Unlock.validateRefs(
	requirements: { Requirement }?,
	resolver: RefResolver,
	owner: string
): { string }
	local problems: { string } = {}
	if not requirements then
		return problems
	end
	for _, requirement in ipairs(requirements) do
		local kind = requirement.kind
		if kind == "DistrictPct" then
			if not resolver.district(requirement.district) then
				table.insert(
					problems,
					`{owner}: unknown district "{tostring(requirement.district)}"`
				)
			end
		elseif kind == "Building" then
			if not resolver.building(requirement.def) then
				table.insert(problems, `{owner}: unknown building "{tostring(requirement.def)}"`)
			elseif requirement.def == owner then
				table.insert(problems, `{owner}: building requirement points at itself`)
			end
		elseif kind == "Research" then
			if not resolver.research(requirement.node) then
				table.insert(
					problems,
					`{owner}: unknown research node "{tostring(requirement.node)}"`
				)
			end
		elseif kind == "Contract" then
			if not resolver.contract(requirement.id) then
				table.insert(problems, `{owner}: unknown contract "{tostring(requirement.id)}"`)
			end
		elseif kind == "Legacy" then
			if not resolver.legacy(requirement.id) then
				table.insert(
					problems,
					`{owner}: unknown legacy milestone "{tostring(requirement.id)}"`
				)
			end
		elseif
			kind ~= "NetWorth"
			and kind ~= "Reputation"
			and kind ~= "Population"
			and kind ~= "Happiness"
			and kind ~= "PrestigePoints"
		then
			table.insert(problems, `{owner}: unknown requirement kind "{tostring(kind)}"`)
		end
	end
	return problems
end

--[[ Depth-first cycle detection over `{ id -> { requirement ids } }`. ]]
function Unlock.findCycle(graph: { [string]: { string } }): string?
	local state: { [string]: number } = {}
	local function visit(node: string, path: { string }): string?
		state[node] = 1
		table.insert(path, node)
		for _, dependency in ipairs(graph[node] or {}) do
			if state[dependency] == 1 then
				table.insert(path, dependency)
				return table.concat(path, " -> ")
			elseif state[dependency] == nil then
				local cycle = visit(dependency, path)
				if cycle then
					return cycle
				end
			end
		end
		table.remove(path)
		state[node] = 2
		return nil
	end

	for node in graph do
		if state[node] == nil then
			local cycle = visit(node, {}) :: string?
			if cycle then
				return cycle
			end
		end
	end
	return nil
end

return Unlock
