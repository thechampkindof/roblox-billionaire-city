--!strict
local Framework = require(script.Parent.Parent.Framework)
local Completion = require(script.Parent.Parent.Parent.src.shared.Core.Completion)

Framework.test("completion weights sum to 100", function()
	local total = 0
	for _, weight in Completion.DEFAULT_WEIGHTS do
		total += weight
	end
	Framework.equal(total, 100)
end)

Framework.test("empty parts report zero completion", function()
	Framework.equal(Completion.percent({}), 0)
end)

Framework.test("full progress reports 100%", function()
	local parts = {}
	for key in Completion.DEFAULT_WEIGHTS do
		parts[key] = 1
	end
	Framework.near(Completion.percent(parts), 100, 1e-9)
end)

Framework.test("weights drive the percentage", function()
	-- Buildings are worth 20 of 100.
	local result = Completion.percent({ buildings = 1 })
	Framework.near(result, 20, 1e-9)
	local half = Completion.percent({ buildings = 0.5, upgrades = 0.5 })
	Framework.near(half, 20, 1e-9)
end)

Framework.test("out-of-range and NaN parts are clamped", function()
	Framework.near(Completion.percent({ buildings = 5 }), 20, 1e-9)
	Framework.near(Completion.percent({ buildings = -5 }), 0, 1e-9)
	Framework.near(Completion.percent({ buildings = 0 / 0 }), 0, 1e-9)
end)

Framework.test("custom weights are normalised", function()
	Framework.near(Completion.percent({ a = 1 }, { a = 3, b = 1 }), 75, 1e-9)
end)

Framework.test("ratio supports weighted items", function()
	Framework.near(
		Completion.ratio({
			{ done = true, weight = 3 },
			{ done = false, weight = 1 },
		}),
		0.75,
		1e-9
	)
	Framework.equal(Completion.ratio({}), 0)
end)

Framework.test("average clamps values", function()
	Framework.near(Completion.average({ 0, 1, 2 }), 2 / 3, 1e-9)
	Framework.equal(Completion.average({}), 0)
end)
