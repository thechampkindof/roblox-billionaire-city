--!strict
--[[
	Tiny test framework. Deliberately dependency-free so it runs anywhere Luau runs
	(headless Luau, Lune, or the Node WASM runner in `tools/run_tests.mjs`).

	Usage in a spec module:
		local Framework = require(script.Parent.Parent.Framework)
		Framework.test("description", function()
			Framework.equal(2 + 2, 4)
		end)
]]

local Framework = {}

type TestCase = {
	name: string,
	run: () -> (),
}

local cases: { TestCase } = {}

function Framework.test(name: string, run: () -> ())
	table.insert(cases, { name = name, run = run })
end

local function fail(message: string, level: number): never
	error(message, (level or 1) + 1)
end

function Framework.equal(actual: any, expected: any, label: string?): ()
	if actual ~= expected then
		fail(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

function Framework.notEqual(actual: any, unexpected: any, label: string?): ()
	if actual == unexpected then
		fail(`{label or "value"}: did not expect {tostring(unexpected)}`, 2)
	end
end

function Framework.near(actual: number, expected: number, tolerance: number?, label: string?): ()
	local epsilon = tolerance or 1e-6
	if math.abs(actual - expected) > epsilon then
		fail(`{label or "value"}: expected {expected} +/- {epsilon}, got {actual}`, 2)
	end
end

function Framework.isTrue(value: any, label: string?): ()
	if not value then
		fail(`{label or "condition"}: expected truthy, got {tostring(value)}`, 2)
	end
end

function Framework.isFalse(value: any, label: string?): ()
	if value then
		fail(`{label or "condition"}: expected falsy, got {tostring(value)}`, 2)
	end
end

function Framework.greaterThan(actual: number, threshold: number, label: string?): ()
	if not (actual > threshold) then
		fail(`{label or "value"}: expected > {threshold}, got {actual}`, 2)
	end
end

--[[ Asserts `fn` throws. When `expectedFragment` is given, the message must contain it. ]]
function Framework.throws(fn: () -> (), expectedFragment: string?): string
	local ok, message = pcall(fn)
	if ok then
		fail("expected function to error, but it succeeded", 2)
	end
	local text = tostring(message)
	if expectedFragment and not string.find(text, expectedFragment, 1, true) then
		fail(`expected error containing "{expectedFragment}", got "{text}"`, 2)
	end
	return text
end

export type Summary = {
	passed: number,
	failed: number,
	failures: { string },
}

export type Runner = {
	run: (verbose: boolean?) -> Summary,
	count: () -> number,
	reset: () -> (),
}

--[[ Runs every registered test. Returns a summary; never throws on test failure. ]]
function Framework.run(verbose: boolean?): Summary
	local summary: Summary = { passed = 0, failed = 0, failures = {} }
	local showOutput = verbose ~= false
	for _, case in ipairs(cases) do
		local ok, err = pcall(case.run)
		if ok then
			summary.passed += 1
			if showOutput then
				print(`  ok   {case.name}`)
			end
		else
			summary.failed += 1
			table.insert(summary.failures, `{case.name}: {tostring(err)}`)
			if showOutput then
				print(`  FAIL {case.name}\n       {tostring(err)}`)
			end
		end
	end
	return summary
end

function Framework.count(): number
	return #cases
end

function Framework.reset()
	table.clear(cases)
end

return Framework
