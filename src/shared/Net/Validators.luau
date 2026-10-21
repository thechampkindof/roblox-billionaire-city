--!strict
--[[
	Payload validation for every client -> server intent. Pure and unit tested.

	Rules (Appendix B2/B6):
	  * the payload must be a table and contain only fields in the schema,
	  * values must match the declared type (no implicit coercion),
	  * strings must be non-empty and short (ids are ids, not essays),
	  * numbers must be finite and inside a sane range.
]]

local Money = require(script.Parent.Parent.Core.Money)

local Validators = {}

Validators.DEFAULT_MAX_STRING = 64

export type Schema = {
	fields: { [string]: string },
	maxStringLength: number?,
}

--[[ Returns `true` when valid, else `false` plus a reason. ]]
function Validators.validatePayload(schema: Schema, payload: any): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "payload must be a table"
	end

	local maxLength = schema.maxStringLength or Validators.DEFAULT_MAX_STRING
	for key, value in payload do
		if type(key) ~= "string" then
			return false, "payload keys must be strings"
		end
		local expected = schema.fields[key]
		if not expected then
			return false, `unexpected field "{key}"`
		end
		if expected == "string" then
			if type(value) ~= "string" then
				return false, `field "{key}" must be a string`
			end
			if #value == 0 or #value > maxLength then
				return false, `field "{key}" must be 1..{maxLength} characters`
			end
		elseif expected == "number" then
			if not Money.isFinite(value) then
				return false, `field "{key}" must be a finite number`
			end
			if math.abs(value) > Money.MAX_SAFE then
				return false, `field "{key}" is out of range`
			end
		elseif expected == "boolean" then
			if type(value) ~= "boolean" then
				return false, `field "{key}" must be a boolean`
			end
		else
			return false, `unknown field type "{expected}"`
		end
	end

	for key in schema.fields do
		if payload[key] == nil then
			return false, `missing field "{key}"`
		end
	end
	return true, nil
end

--[[ Ids must be short printable tokens; this rejects obvious injection attempts. ]]
function Validators.isValidId(value: any): boolean
	if type(value) ~= "string" or #value == 0 or #value > 96 then
		return false
	end
	return string.match(value, "^[%w_%-%.:]+$") ~= nil
end

--[[
	Coerces a settings value from the wire. Settings are a strict allow-list so a
	client can never write arbitrary profile keys.
]]
function Validators.coerceSetting(key: string, raw: string): (boolean, any)
	if key == "quality" then
		if raw == "low" or raw == "medium" or raw == "high" or raw == "auto" then
			return true, raw
		end
		return false, nil
	elseif key == "sfx" or key == "music" then
		if raw == "true" then
			return true, true
		elseif raw == "false" then
			return true, false
		end
		return false, nil
	end
	return false, nil
end

return Validators
