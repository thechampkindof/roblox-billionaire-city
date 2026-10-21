--!strict
--[[
	City Completion %.

	Appendix B5 fixes the weights: Buildings 20, Upgrades 20, Mastery 15, Research 10,
	Collections 15, Achievements 15, Secrets 5. Content that does not exist yet (research,
	collections, achievements in Phase 1) reports 0 progress, so completion never
	pretends to be higher than it is.
]]

local Completion = {}

export type Weights = { [string]: number }

Completion.DEFAULT_WEIGHTS = {
	buildings = 20,
	upgrades = 20,
	mastery = 15,
	research = 10,
	collections = 15,
	achievements = 15,
	secrets = 5,
}

export type Parts = { [string]: number }

--[[ Clamps every part to 0..1 and returns weighted 0..100 with the weights normalised. ]]
function Completion.percent(parts: Parts, weights: Weights?): number
	local resolved = weights or Completion.DEFAULT_WEIGHTS
	local totalWeight = 0
	local score = 0
	for key, weight in resolved do
		totalWeight += weight
		local value = parts[key] or 0
		if type(value) ~= "number" or value ~= value then
			value = 0
		end
		score += weight * math.clamp(value, 0, 1)
	end
	if totalWeight <= 0 then
		return 0
	end
	return (score / totalWeight) * 100
end

--[[
	Progress for a set of items: `sum(done) / count`. Items can carry weights
	(`{ { done = true, weight = 3 } }`) so megaprojects count more than kiosks.
]]
export type Item = { done: boolean, weight: number? }

function Completion.ratio(items: { Item }): number
	if #items == 0 then
		return 0
	end
	local totalWeight = 0
	local doneWeight = 0
	for _, item in ipairs(items) do
		local weight = item.weight or 1
		totalWeight += weight
		if item.done then
			doneWeight += weight
		end
	end
	if totalWeight <= 0 then
		return 0
	end
	return doneWeight / totalWeight
end

--[[ Average of per-building upgrade-line completion fractions. ]]
function Completion.average(values: { number }): number
	if #values == 0 then
		return 0
	end
	local total = 0
	for _, value in ipairs(values) do
		total += math.clamp(value, 0, 1)
	end
	return total / #values
end

return Completion
