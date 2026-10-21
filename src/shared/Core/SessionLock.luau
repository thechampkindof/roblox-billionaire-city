--!strict
--[[
	Session-lock logic, kept pure so it can be tested without DataStores.

	A lock is `{ key: string, at: number }` stored beside the profile. Only the server
	holding `key` may write. A lock older than `staleSeconds` is considered abandoned
	(the previous server crashed) and may be taken over.

	`ProfileProvider` implementations call these functions; nothing else may.
]]

local SessionLock = {}

export type Lock = {
	key: string,
	at: number,
}

SessionLock.DEFAULT_STALE_SECONDS = 60

--[[ True when a lock exists and is still fresh. ]]
function SessionLock.isHeld(lock: Lock?, now: number, staleSeconds: number?): boolean
	if not lock or type(lock.key) ~= "string" or lock.key == "" then
		return false
	end
	local stale = staleSeconds or SessionLock.DEFAULT_STALE_SECONDS
	if type(lock.at) ~= "number" or lock.at ~= lock.at then
		return false
	end
	return (now - lock.at) < stale
end

--[[ True when `sessionKey` currently owns a fresh lock. ]]
function SessionLock.owns(
	lock: Lock?,
	sessionKey: string,
	now: number,
	staleSeconds: number?
): boolean
	if not SessionLock.isHeld(lock, now, staleSeconds) then
		return false
	end
	return (lock :: Lock).key == sessionKey
end

--[[
	Decides whether a load may proceed.

	Returns `true` when the profile is unlocked or the existing lock is stale, and
	`false` plus the remaining wait time when another live session owns it.
]]
function SessionLock.canAcquire(lock: Lock?, now: number, staleSeconds: number?): (boolean, number)
	if not SessionLock.isHeld(lock, now, staleSeconds) then
		return true, 0
	end
	local stale = staleSeconds or SessionLock.DEFAULT_STALE_SECONDS
	local at = (lock :: Lock).at
	return false, math.max(0, stale - (now - at))
end

--[[ Validates a write attempt. Stale-but-someone-else locks still block writes. ]]
function SessionLock.validateWrite(lock: Lock?, sessionKey: string): (boolean, string?)
	if not lock or not lock.key then
		return true, nil
	end
	if lock.key ~= sessionKey then
		return false, "SESSION_LOCKED"
	end
	return true, nil
end

--[[ A new lock for `sessionKey` at `now`. ]]
function SessionLock.create(sessionKey: string, now: number): Lock
	return { key = sessionKey, at = now }
end

--[[ Refreshes the timestamp when `sessionKey` owns the lock; returns the new lock. ]]
function SessionLock.touch(lock: Lock?, sessionKey: string, now: number): Lock?
	if lock and lock.key == sessionKey then
		return { key = sessionKey, at = now }
	end
	return nil
end

return SessionLock
