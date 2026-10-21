--!strict
--[[ Payload validation and settings coercion (Appendix B2 rule 1-3). ]]

local Framework = require(script.Parent.Parent.Framework)
local Validators = require(script.Parent.Parent.Parent.src.shared.Net.Validators)

local SCHEMA: Validators.Schema = {
	fields = { parcelId = "string", amount = "number", flag = "boolean" },
	maxStringLength = 16,
}

local function valid(payload: any): (boolean, string?)
	return Validators.validatePayload(SCHEMA, payload)
end

Framework.test("accepts a well-formed payload", function()
	local ok, reason = valid({ parcelId = "starter_01", amount = 12, flag = true })
	Framework.isTrue(ok, reason)
end)

Framework.test("requires every declared field", function()
	local ok, reason = valid({ parcelId = "a" })
	Framework.isFalse(ok, "missing fields are rejected")
	Framework.isTrue(string.find(tostring(reason), "missing field") ~= nil, tostring(reason))
end)

Framework.test("rejects a non-table payload", function()
	local ok = valid("nope")
	Framework.isFalse(ok)
	Framework.equal(select(2, valid(nil)) ~= nil, true)
end)

Framework.test("rejects unknown fields", function()
	local ok, reason = valid({ parcelId = "a", evil = 1 })
	Framework.isFalse(ok)
	Framework.isTrue(string.find(tostring(reason), "unexpected field") ~= nil)
end)

Framework.test("rejects wrong value types", function()
	Framework.isFalse(valid({ amount = "12" }))
	Framework.isFalse(valid({ parcelId = 12 }))
	Framework.isFalse(valid({ flag = "true" }))
end)

local function withParcelId(value: string): any
	return { parcelId = value, amount = 1, flag = false }
end

Framework.test("rejects empty and oversized strings", function()
	local emptyOk = valid(withParcelId(""))
	Framework.isFalse(emptyOk, "empty string")
	local longOk = valid(withParcelId(string.rep("x", 17)))
	Framework.isFalse(longOk, "17 characters")
	local okOk = valid(withParcelId(string.rep("x", 16)))
	Framework.isTrue(okOk, "16 characters is allowed")
end)

Framework.test("rejects non-finite and out-of-range numbers", function()
	Framework.isFalse(valid({ amount = 0 / 0 }))
	Framework.isFalse(valid({ amount = math.huge }))
	Framework.isFalse(valid({ amount = 2 ^ 60 }))
end)

Framework.test("rejects non-string keys", function()
	Framework.isFalse(valid({ [1] = "x" }))
end)

Framework.test("ids reject whitespace and separators", function()
	Framework.isTrue(Validators.isValidId("b12"))
	Framework.isTrue(Validators.isValidId("starter_01"))
	Framework.isFalse(Validators.isValidId("drop table"))
	Framework.isFalse(Validators.isValidId(""))
	Framework.isFalse(Validators.isValidId(12))
end)

Framework.test("settings coercion is an allow-list", function()
	local ok, value = Validators.coerceSetting("quality", "low")
	Framework.isTrue(ok)
	Framework.equal(value, "low")

	Framework.isFalse(Validators.coerceSetting("quality", "ultra"))
	Framework.isFalse(Validators.coerceSetting("cash", "999"))
	local sfxOk, sfx = Validators.coerceSetting("sfx", "false")
	Framework.isTrue(sfxOk)
	Framework.equal(sfx, false)
end)
