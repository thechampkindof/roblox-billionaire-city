--!strict
local Framework = require(script.Parent.Parent.Framework)
local Unlock = require(script.Parent.Parent.Parent.src.shared.Core.Unlock)

local function context(overrides: any?)
	local base = Unlock.defaultContext()
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

Framework.test("empty requirement lists always pass", function()
	local result = Unlock.evaluate({}, context())
	Framework.isTrue(result.ok)
	Framework.equal(result.progress, 1)
	Framework.isTrue(Unlock.evaluate(nil, context()).ok, "nil requirements pass")
end)

Framework.test("numeric gates compare against the context", function()
	local ctx = context({ netWorth = 30_000, reputation = 100 })
	local pass = Unlock.evaluate({ { kind = "NetWorth", min = 25_000 } }, ctx)
	Framework.isTrue(pass.ok)
	local fail = Unlock.evaluate({ { kind = "NetWorth", min = 50_000 } }, ctx)
	Framework.isFalse(fail.ok)
	Framework.equal(#fail.unmet, 1)
	Framework.near(fail.unmet[1].progress, 0.6, 1e-6)
end)

Framework.test("all requirements must pass and progress averages", function()
	local ctx = context({ netWorth = 10, reputation = 10 })
	local result =
		Unlock.evaluate({ { kind = "NetWorth", min = 10 }, { kind = "Reputation", min = 20 } }, ctx)
	Framework.isFalse(result.ok)
	Framework.equal(#result.unmet, 1)
	Framework.near(result.progress, 0.75, 1e-6)
end)

Framework.test("callbacks resolve district, research, building, contract and legacy", function()
	local ctx = Unlock.defaultContext()
	ctx.districtPct = function(district: string)
		return if district == "Starter" then 40 else 0
	end
	ctx.research = function(node: string)
		return node == "industrial_technology_1"
	end
	ctx.buildingLevel = function(id: string)
		return if id == "convenience_store" then 3 else 0
	end
	ctx.contractDone = function(id: string)
		return id == "first_delivery"
	end
	ctx.legacy = function(id: string)
		return id == "billionaire"
	end

	Framework.isTrue(Unlock.evaluate({
		{ kind = "DistrictPct", district = "Starter", min = 40 },
		{ kind = "Research", node = "industrial_technology_1" },
		{ kind = "Building", def = "convenience_store", level = 3 },
		{ kind = "Contract", id = "first_delivery" },
		{ kind = "Legacy", id = "billionaire" },
	}, ctx).ok)

	local missing = Unlock.evaluate({
		{ kind = "DistrictPct", district = "Shopping", min = 10 },
		{ kind = "Research", node = "nope" },
		{ kind = "Building", def = "convenience_store", level = 9 },
	}, ctx)
	Framework.equal(#missing.unmet, 3)
end)

Framework.test("unknown requirement kinds fail closed", function()
	local result = Unlock.evaluate({ { kind = "Telekinesis" } }, context())
	Framework.isFalse(result.ok)
	Framework.isTrue(string.find(result.unmet[1].description, "Unknown requirement") ~= nil)
end)

Framework.test("reference validation catches unknown ids and self references", function()
	local resolver = {
		building = function(id: string)
			return id == "convenience_store"
		end,
		research = function()
			return false
		end,
		contract = function()
			return false
		end,
		legacy = function()
			return false
		end,
		district = function(id: string)
			return id == "Starter"
		end,
	}
	local problems = Unlock.validateRefs({
		{ kind = "Building", def = "convenience_store" },
		{ kind = "Building", def = "convenience_store" },
		{ kind = "DistrictPct", district = "Nope", min = 10 },
		{ kind = "Research", node = "missing" },
		{ kind = "Warp", min = 1 },
	}, resolver, "convenience_store")
	-- two self references + unknown district + unknown research + unknown kind
	Framework.equal(#problems, 5)
end)

Framework.test("cycle detection finds and clears dependency loops", function()
	Framework.equal(Unlock.findCycle({ a = { "b" }, b = { "a" } }) ~= nil, true)
	Framework.equal(Unlock.findCycle({ a = { "b" }, b = {} }), nil)
	local message = Unlock.findCycle({ a = { "b" }, b = { "c" }, c = { "a" } }) or ""
	Framework.isTrue(string.find(message, "->") ~= nil, "cycle path reported")
	Framework.equal(
		#string.split(message, " -> "),
		4,
		"cycle path visits three nodes and closes the loop"
	)
end)
