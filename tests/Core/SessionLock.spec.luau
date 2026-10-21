--!strict
--[[ Uid and SessionLock: the small pure pieces persistence depends on. ]]

local Framework = require(script.Parent.Parent.Framework)
local Uid = require(script.Parent.Parent.Parent.src.shared.Core.Uid)
local SessionLock = require(script.Parent.Parent.Parent.src.shared.Core.SessionLock)

Framework.test("uids start at b1 and count up", function()
	Framework.equal(Uid.next({}), "b1")
	Framework.equal(Uid.next({ b1 = true }), "b2")
	Framework.equal(Uid.next({ b1 = true, b7 = true }), "b8")
end)

Framework.test("uid generation ignores non-conforming keys", function()
	Framework.equal(Uid.next({ zombie = true, b3 = true, ["b4x"] = true }), "b4")
end)

Framework.test("uid validation", function()
	Framework.isTrue(Uid.isValid("b1"))
	Framework.isTrue(Uid.isValid("b1234"))
	Framework.isFalse(Uid.isValid("b"))
	Framework.isFalse(Uid.isValid("1"))
	Framework.isFalse(Uid.isValid(""))
end)

Framework.test("a fresh lock is free", function()
	local canAcquire = SessionLock.canAcquire(nil, 100)
	Framework.isTrue(canAcquire)
	Framework.isFalse(SessionLock.isHeld(nil, 100))
end)

Framework.test("a fresh lock blocks another session with a countdown", function()
	local lock = { key = "session-a", at = 100 }
	local canAcquire, wait = SessionLock.canAcquire(lock, 110, 60)
	Framework.isFalse(canAcquire)
	Framework.near(wait, 50, 1e-6)
	Framework.isTrue(SessionLock.owns(lock, "session-a", 110, 60))
	Framework.isFalse(SessionLock.owns(lock, "session-b", 110, 60))
end)

Framework.test("a stale lock can be taken over", function()
	local lock = { key = "session-a", at = 0 }
	Framework.isTrue(SessionLock.canAcquire(lock, 61, 60))
	Framework.isFalse(SessionLock.isHeld(lock, 61, 60))
end)

Framework.test("malformed locks are treated as free", function()
	Framework.isFalse(SessionLock.isHeld({ key = "", at = 0 }, 1))
	Framework.isFalse(SessionLock.isHeld({ key = "x", at = 0 / 0 }, 1))
	local canAcquire = SessionLock.canAcquire({ at = 0 } :: any, 1)
	Framework.isTrue(canAcquire)
end)

Framework.test("writes are only valid for the lock owner", function()
	local lock = { key = "session-a", at = 0 }
	Framework.isTrue(SessionLock.validateWrite(nil, "anything"))
	local ownOk = SessionLock.validateWrite(lock, "session-a")
	Framework.isTrue(ownOk)
	local foreignOk, reason = SessionLock.validateWrite(lock, "session-b")
	Framework.isFalse(foreignOk)
	Framework.isTrue(reason ~= nil)
end)
