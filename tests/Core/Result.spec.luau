--!strict
local Framework = require(script.Parent.Parent.Framework)
local Result = require(script.Parent.Parent.Parent.src.shared.Core.Result)

Framework.test("Result ok carries data and the OK code", function()
	local result = Result.ok({ id = 7 })
	Framework.isTrue(Result.isOk(result))
	Framework.isFalse(Result.isErr(result))
	Framework.equal(result.code, "OK")
	Framework.equal(Result.unwrap(result, nil).id, 7)
end)

Framework.test("Result err carries a stable code and message", function()
	local result = Result.err("INSUFFICIENT_FUNDS", "Not enough cash.")
	Framework.isFalse(Result.isOk(result))
	Framework.equal(result.code, "INSUFFICIENT_FUNDS")
	Framework.equal(result.message, "Not enough cash.")
end)

Framework.test("Result map transforms only successes", function()
	local doubled = Result.map(Result.ok(21), function(value)
		return value * 2
	end)
	Framework.equal(doubled.data, 42)

	local failed = Result.map(Result.err("NOPE"), function(value)
		return value * 2
	end)
	Framework.equal(failed.code, "NOPE")
	Framework.equal(failed.data, nil)
end)

Framework.test("Result expect throws on failure", function()
	Framework.throws(function()
		Result.expect(Result.err("BAD"))
	end, "BAD")
end)
