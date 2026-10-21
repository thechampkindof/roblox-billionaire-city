--!strict
--[[ Token bucket behaviour, with an injected clock so it is deterministic. ]]

local Framework = require(script.Parent.Parent.Framework)
local RateLimiter = require(script.Parent.Parent.Parent.src.shared.Net.RateLimiter)

local CONFIG = {
	default = { capacity = 4, refillPerSecond = 1 },
	IncomeCollect = { capacity = 2, refillPerSecond = 0.5 },
}

local function clocked(now: { value: number })
	return function()
		return now.value
	end
end

Framework.test("allows a burst up to capacity, then rejects", function()
	local now = { value = 0 }
	local limiter = RateLimiter.new(CONFIG, clocked(now))
	for _ = 1, 4 do
		local allowed = limiter:Allow(1, "Unknown")
		Framework.isTrue(allowed)
	end
	local allowed, retry = limiter:Allow(1, "Unknown")
	Framework.isFalse(allowed)
	Framework.near(retry, 1, 1e-6, "retry after one second of refill")
end)

Framework.test("refills over time", function()
	local now = { value = 0 }
	local limiter = RateLimiter.new(CONFIG, clocked(now))
	for _ = 1, 4 do
		limiter:Allow(7, "Unknown")
	end
	now.value = 2
	local allowed = limiter:Allow(7, "Unknown")
	Framework.isTrue(allowed, "two tokens after two seconds")
end)

Framework.test("never exceeds capacity when idle", function()
	local now = { value = 0 }
	local limiter = RateLimiter.new(CONFIG, clocked(now))
	limiter:Allow(2, "Unknown")
	now.value = 10_000
	-- Bucket is capped at 4, so the 5th immediate request fails.
	limiter:Allow(2, "Unknown")
	limiter:Allow(2, "Unknown")
	limiter:Allow(2, "Unknown")
	Framework.isTrue(limiter:Allow(2, "Unknown"))
	Framework.isFalse(limiter:Allow(2, "Unknown"))
end)

Framework.test("intents have independent buckets", function()
	local now = { value = 0 }
	local limiter = RateLimiter.new(CONFIG, clocked(now))
	Framework.isTrue(limiter:Allow(3, "IncomeCollect"))
	Framework.isTrue(limiter:Allow(3, "IncomeCollect"))
	Framework.isFalse(limiter:Allow(3, "IncomeCollect"))
	Framework.isTrue(limiter:Allow(3, "Unknown"), "other intent untouched")
end)

Framework.test("players have independent buckets", function()
	local now = { value = 0 }
	local limiter = RateLimiter.new(CONFIG, clocked(now))
	for _ = 1, 4 do
		limiter:Allow(10, "Unknown")
	end
	Framework.isFalse(limiter:Allow(10, "Unknown"))
	Framework.isTrue(limiter:Allow(11, "Unknown"))
end)

Framework.test("Reset clears only that player", function()
	local now = { value = 0 }
	local limiter = RateLimiter.new(CONFIG, clocked(now))
	for _ = 1, 4 do
		limiter:Allow(20, "Unknown")
		limiter:Allow(21, "Unknown")
	end
	limiter:Reset(20)
	Framework.isTrue(limiter:Allow(20, "Unknown"))
	Framework.isFalse(limiter:Allow(21, "Unknown"))
end)

Framework.test("unknown intents fall back to the default bucket", function()
	local now = { value = 0 }
	local limiter = RateLimiter.new(CONFIG, clocked(now))
	for _ = 1, 4 do
		Framework.isTrue(limiter:Allow(30, "MadeUpIntent"))
	end
	Framework.isFalse(limiter:Allow(30, "MadeUpIntent"))
end)

Framework.test("no config means no limit", function()
	local now = { value = 0 }
	local limiter = RateLimiter.new({}, clocked(now))
	for _ = 1, 100 do
		Framework.isTrue(limiter:Allow(40, "Anything"))
	end
end)
