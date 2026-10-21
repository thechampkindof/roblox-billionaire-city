--!strict
--[[
	Money / integer safety.

	Rules enforced here and depended on by `EconomyService`:
	  * every currency amount is a whole number (no cents in the profile),
	  * never negative unless the caller explicitly allows it,
	  * never NaN/inf,
	  * never above `Money.MAX_SAFE` (2^53) so float-backed Lua numbers stay exact.
]]

local Money = {}

Money.MAX_SAFE = 2 ^ 53
Money.MIN_SAFE = -(2 ^ 53)

function Money.isFinite(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	return value == value and value ~= math.huge and value ~= -math.huge
end

--[[ True when `value` is a finite integer inside the exact-number range. ]]
function Money.isSafeInteger(value: any): boolean
	if not Money.isFinite(value) then
		return false
	end
	if value ~= math.floor(value) then
		return false
	end
	return value <= Money.MAX_SAFE and value >= Money.MIN_SAFE
end

--[[ Rounds to the nearest whole number and saturates at the safe range. ]]
function Money.round(value: number): number
	if not Money.isFinite(value) then
		return 0
	end
	local rounded = if value >= 0 then math.floor(value + 0.5) else math.ceil(value - 0.5)
	return math.clamp(rounded, Money.MIN_SAFE, Money.MAX_SAFE)
end

--[[ Saturating clamp used after any arithmetic on balances. ]]
function Money.clamp(value: number): number
	if not Money.isFinite(value) then
		return 0
	end
	return math.clamp(value, 0, Money.MAX_SAFE)
end

--[[ Returns nil when the amount is not spendable, otherwise the exact integer. ]]
function Money.toAmount(value: any): number?
	if not Money.isSafeInteger(value) or value < 0 then
		return nil
	end
	return value
end

--[[ Safe addition with saturation. ]]
function Money.add(a: number, b: number): number
	return math.clamp(a + b, Money.MIN_SAFE, Money.MAX_SAFE)
end

--[[ Safe subtraction with saturation at zero. ]]
function Money.sub(a: number, b: number): number
	return Money.clamp(a - b)
end

--[[ True when `cost` is affordable with `balance`. ]]
function Money.canAfford(balance: number, cost: number): boolean
	return Money.toAmount(cost) ~= nil and balance >= cost
end

--[[ Compares two integer amounts with a tolerance, for tests and assert helpers. ]]
function Money.equals(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 0)
end

return Money
