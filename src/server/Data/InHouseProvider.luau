--!strict
--[[
	In-house ProfileProvider.

	Design notes (Appendix B5):
	  * one DataStore key per player: `Player_<userId>`, value `{ Version, Data, Lock }`
	  * every read and write is an `UpdateAsync` so lock acquisition is atomic
	  * writes are rejected when another session owns a fresh lock
	  * stale locks (crashed server) are taken over after `SessionLock.DEFAULT_STALE_SECONDS`
	  * retries live in `DataService`; this provider returns failures immediately

	This is intentionally a small, auditable implementation. Before public launch,
	swap it for ProfileStore (MadStudio) — see docs/ARCHITECTURE.md and DECISIONS.md.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Core = Shared.Core
local Result = require(Core.Result)
local SessionLock = require(Core.SessionLock)

local InHouseProvider = {}
InHouseProvider.__index = InHouseProvider

local STORE_NAME = "BillionaireCityTycoon_v1"

function InHouseProvider.new(options: { storeName: string? }?): any
	local storeName = (if options and options.storeName then options.storeName else STORE_NAME)
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(storeName)
	end)
	return setmetatable({
		Name = "InHouseProvider",
		_store = if ok then store else nil,
		_ready = ok,
	}, InHouseProvider)
end

--[[ True when the DataStore is usable (published place + API access enabled). ]]
function InHouseProvider:IsReady(): boolean
	return self._ready == true
end

--[[ Probes the store with a cheap read; used to detect Studio without API access. ]]
function InHouseProvider:Probe(userId: number): boolean
	if not self._ready then
		return false
	end
	local ok = pcall(function()
		return self._store:GetAsync(`probe_{userId}`)
	end)
	return ok
end

function InHouseProvider:LoadAsync(userId: number)
	if not self._ready then
		return Result.err("DATASTORE_UNAVAILABLE", "DataStore is not available in this environment")
	end

	local key = `Player_{userId}`
	local now = os.time()
	local sessionKey = `{game.JobId}-{userId}-{now}-{math.random(100000, 999999)}`
	local acquired = false
	local payload: any = nil

	local ok, err = pcall(function()
		self._store:UpdateAsync(key, function(current: any)
			local record = current
			local lock = if record and type(record) == "table" then record.Lock else nil
			local canAcquire = SessionLock.canAcquire(lock, now, SessionLock.DEFAULT_STALE_SECONDS)
			if not canAcquire and record and record.Lock and record.Lock.key ~= sessionKey then
				-- Do not modify: another live session owns this profile.
				return nil
			end
			acquired = true
			payload = if record and type(record) == "table" then record.Data else nil
			return {
				Version = 1,
				Data = payload,
				Lock = SessionLock.create(sessionKey, now),
			}
		end)
	end)

	if not ok then
		return Result.err("DATASTORE_LOAD_FAILED", tostring(err))
	end
	if not acquired then
		return Result.err("PROFILE_BUSY", "profile is open in another server")
	end

	return Result.ok({
		data = payload,
		sessionKey = sessionKey,
		fresh = payload == nil,
	})
end

function InHouseProvider:SaveAsync(userId: number, data: any, sessionKey: string)
	if not self._ready then
		return Result.err("DATASTORE_UNAVAILABLE", "DataStore is not available")
	end

	local key = `Player_{userId}`
	local now = os.time()
	local written = false
	local lockLost = false

	local ok, err = pcall(function()
		self._store:UpdateAsync(key, function(current: any)
			local record = current
			local lock = if record and type(record) == "table" then record.Lock else nil
			local valid = SessionLock.validateWrite(lock, sessionKey)
			if not valid then
				lockLost = true
				return nil
			end
			written = true
			return {
				Version = 1,
				Data = data,
				Lock = SessionLock.touch(lock, sessionKey, now)
					or SessionLock.create(sessionKey, now),
			}
		end)
	end)

	if lockLost then
		return Result.err("SESSION_LOCKED", "session lock lost; refusing to overwrite")
	end
	if not ok then
		return Result.err("DATASTORE_SAVE_FAILED", tostring(err))
	end
	if not written then
		return Result.err("DATASTORE_SAVE_FAILED", "write was skipped")
	end
	return Result.ok(true)
end

function InHouseProvider:ReleaseAsync(userId: number, sessionKey: string)
	if not self._ready then
		return
	end
	local key = `Player_{userId}`
	pcall(function()
		self._store:UpdateAsync(key, function(current: any)
			local record = current
			if
				record
				and type(record) == "table"
				and record.Lock
				and record.Lock.key == sessionKey
			then
				return {
					Version = 1,
					Data = record.Data,
					Lock = nil,
				}
			end
			return nil
		end)
	end)
end

--[[ Diagnostic used by the bootstrap: "Studio" | "Live" | "Mock". ]]
function InHouseProvider:Environment(): string
	if not RunService:IsStudio() then
		return "Live"
	end
	return if self._ready then "Studio" else "Mock"
end

return InHouseProvider
