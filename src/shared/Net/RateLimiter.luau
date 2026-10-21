--!strict
--[[
	Per-player token bucket rate limiting.

	Tokens refill continuously; a burst is allowed up to `capacity`, then requests are
	rejected with `RATE_LIMITED`. Pure math with an injected clock so it is testable.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Bucket = {
	capacity: number,
	refillPerSecond: number,
	tokens: number,
	updatedAt: number,
}

export type Limiter = {
	buckets: { [string]: Bucket },
	configs: { [string]: { capacity: number, refillPerSecond: number } },
	now: () -> number,
	Allow: (self: Limiter, userId: number, key: string) -> (boolean, number),
	Reset: (self: Limiter, userId: number) -> (),
	SetConfig: (self: Limiter, key: string, capacity: number, refillPerSecond: number) -> (),
}

--[[ `configs` maps intent name -> capacity/refill. `now` is injectable for tests. ]]
function RateLimiter.new(
	configs: { [string]: { capacity: number, refillPerSecond: number } },
	now: (() -> number)?
): Limiter
	return setmetatable({
		buckets = {},
		configs = configs,
		now = now or os.clock,
	}, RateLimiter) :: any
end

function RateLimiter:SetConfig(key: string, capacity: number, refillPerSecond: number)
	self.configs[key] = { capacity = capacity, refillPerSecond = refillPerSecond }
end

local function bucketKey(userId: number, key: string): string
	return `{userId}:{key}`
end

--[[ Returns `allowed, retryAfterSeconds`. ]]
function RateLimiter:Allow(userId: number, key: string): (boolean, number)
	local config = self.configs[key] or self.configs.default
	if not config then
		return true, 0
	end
	local clock = self.now()
	local id = bucketKey(userId, key)
	local bucket = self.buckets[id]
	if not bucket then
		bucket = {
			capacity = config.capacity,
			refillPerSecond = config.refillPerSecond,
			tokens = config.capacity,
			updatedAt = clock,
		}
		self.buckets[id] = bucket
	end

	local elapsed = math.max(0, clock - bucket.updatedAt)
	bucket.tokens = math.min(bucket.capacity, bucket.tokens + elapsed * bucket.refillPerSecond)
	bucket.updatedAt = clock

	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true, 0
	end

	local deficit = 1 - bucket.tokens
	local retry = if bucket.refillPerSecond > 0 then deficit / bucket.refillPerSecond else 1
	return false, retry
end

function RateLimiter:Reset(userId: number)
	local prefix = `{userId}:`
	for key in self.buckets do
		if string.sub(key, 1, #prefix) == prefix then
			self.buckets[key] = nil
		end
	end
end

return RateLimiter
