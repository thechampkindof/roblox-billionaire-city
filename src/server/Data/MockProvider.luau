--!strict
--[[
	In-memory ProfileProvider for Studio playtests without API access, for tests, and
	for local iteration. It implements the same session-lock semantics as the in-house
	provider, including optional artificial latency and failure injection.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Result = require(Core.Result)
local SessionLock = require(Core.SessionLock)

local MockProvider = {}
MockProvider.__index = MockProvider

function MockProvider.new(options: { latency: number? }?): any
	return setmetatable({
		Name = "MockProvider",
		_store = {},
		_locks = {},
		_saves = 0,
		_failNextSave = false,
		_failNextLoad = false,
		_latency = (if options and options.latency then options.latency else 0),
	}, MockProvider)
end

function MockProvider:_wait(self: any)
	if self._latency > 0 then
		task.wait(self._latency)
	end
end

function MockProvider:FailNextSave()
	self._failNextSave = true
end

function MockProvider:FailNextLoad()
	self._failNextLoad = true
end

function MockProvider:LoadAsync(userId: number)
	self:_wait()
	if self._failNextLoad then
		self._failNextLoad = false
		return Result.err("MOCK_LOAD_FAILED", "simulated load failure")
	end

	local now = os.time()
	local canAcquire =
		SessionLock.canAcquire(self._locks[userId], now, SessionLock.DEFAULT_STALE_SECONDS)
	if not canAcquire then
		return Result.err("PROFILE_BUSY", "another session holds this profile")
	end

	local sessionKey = `mock-{userId}-{now}`
	self._locks[userId] = SessionLock.create(sessionKey, now)
	local data = self._store[userId]
	return Result.ok({
		data = data,
		sessionKey = sessionKey,
		fresh = data == nil,
	})
end

function MockProvider:SaveAsync(userId: number, data: any, sessionKey: string)
	self:_wait()
	if self._failNextSave then
		self._failNextSave = false
		return Result.err("MOCK_SAVE_FAILED", "simulated save failure")
	end
	local valid = SessionLock.validateWrite(self._locks[userId], sessionKey)
	if not valid then
		return Result.err("SESSION_LOCKED", "session lock lost")
	end
	self._store[userId] = data
	self._locks[userId] = SessionLock.touch(self._locks[userId], sessionKey, os.time())
	self._saves += 1
	return Result.ok(true)
end

function MockProvider:ReleaseAsync(userId: number, sessionKey: string)
	if SessionLock.owns(self._locks[userId], sessionKey, os.time()) then
		self._locks[userId] = nil
	end
end

--[[ Test helpers. ]]
function MockProvider:HasProfile(userId: number): boolean
	return self._store[userId] ~= nil
end

function MockProvider:SaveCount(): number
	return self._saves
end

function MockProvider:ClearLock(userId: number)
	self._locks[userId] = nil
end

function MockProvider:SetLock(userId: number, lock: SessionLock.Lock)
	self._locks[userId] = lock
end

return MockProvider
