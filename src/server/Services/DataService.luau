--!strict
--[[
	Owns profiles. Only this service touches the ProfileProvider (and therefore only this
	service touches DataStores).

	Responsibilities (Appendix B2, B5):
	  * load with session lock, migrate, reconcile against the template
	  * autosave, save on milestone, save + release on leave, save on BindToClose
	  * retry with exponential backoff; never silently drop a failed save
	  * announce lifecycle through signals, never shared mutable tables
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config

local Signal = require(Core.Signal)
local Result = require(Core.Result)
local Maid = require(Core.Maid)
local Profile = require(Core.Profile)
local Migrations = require(Core.Migrations)

local Balance = require(Config.Balance)
local Flags = require(Config.Flags)

local InHouseProvider = require(script.Parent.Parent.Data.InHouseProvider)
local Bootstrap = require(script.Parent.Parent.Data.Bootstrap)
local MockProvider = require(script.Parent.Parent.Data.MockProvider)

local DataService = {}
DataService.Name = "DataService"
DataService.Dependencies = {}

DataService.ProfileLoaded = Signal.new("ProfileLoaded")
DataService.ProfileReleasing = Signal.new("ProfileReleasing")
DataService.ProfileSaved = Signal.new("ProfileSaved")

export type Session = {
	userId: number,
	data: Profile.Profile,
	sessionKey: string,
	provider: any,
	loaded: boolean,
	saving: boolean,
	lastSaveAt: number,
	dirty: boolean,
	playSeconds: number,
	sessionStart: number,
}

local sessions: { [number]: Session } = {}
local players: { [number]: Player } = {}
local maids: { [number]: Maid.Maid } = {}
local autosaveThread: thread? = nil
local provider: any = nil

local function log(message: string)
	print(`[DataService] {message}`)
end

--[[ Chooses a provider: in-house with a probe, otherwise MockProvider. ]]
local function resolveProvider(): any
	if Flags.get("MockDataStore") then
		log("using MockProvider (flag)")
		return MockProvider.new()
	end
	if RunService:IsStudio() then
		local candidate = InHouseProvider.new()
		if candidate:Probe(0) then
			log("using InHouseProvider (Studio with API access)")
			return candidate
		end
		log("Studio without DataStore access — using MockProvider (progress will not persist)")
		return MockProvider.new()
	end
	local candidate = InHouseProvider.new()
	if candidate:IsReady() then
		return candidate
	end
	log("DataStoreService unavailable — using MockProvider")
	return MockProvider.new()
end

--[[
	Migrate + reconcile a saved profile, then apply the bootstrap invariants (starter
	parcel, starter building, district rows).

	`LastSaved` is deliberately left as stored: `OfflineService` measures elapsed time
	from it, so overwriting it here would silently disable offline income.
]]
local function normalise(data: any, now: number): Profile.Profile
	local profile = Profile.normalise(data, now)
	profile.Time.LastSeen = now
	profile.Version = Profile.CURRENT_VERSION
	Bootstrap.apply(profile, now)
	return profile
end

local function loadWithRetries(userId: number)
	local attempt = 0
	while attempt < 3 do
		attempt += 1
		local result = provider:LoadAsync(userId)
		if result.ok then
			return result
		end
		if result.code == "PROFILE_BUSY" then
			return result
		end
		log(`load attempt {attempt} failed for {userId}: {result.code}`)
		task.wait(0.5 * attempt)
	end
	return Result.err("LOAD_FAILED", "profile could not be loaded")
end

function DataService.Init(registry: any)
	provider = resolveProvider()
	DataService.Provider = provider

	Players.PlayerAdded:Connect(function(player)
		DataService.LoadPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		DataService.ReleasePlayer(player)
	end)
end

function DataService.Start()
	autosaveThread = task.spawn(function()
		while true do
			task.wait(Balance.AutosaveSeconds)
			for userId, session in sessions do
				if session.dirty then
					DataService.SaveSession(userId, "autosave")
				end
			end
		end
	end)

	game:BindToClose(function()
		for userId in sessions do
			DataService.SaveSession(userId, "shutdown")
		end
		-- Give DataStore writes a moment to land before the server dies.
		task.wait(2)
	end)
end

function DataService.LoadPlayer(player: Player): boolean
	if sessions[player.UserId] then
		return true
	end

	local result = loadWithRetries(player.UserId)
	if not result.ok then
		player:Kick(Config.Strings.errors.PROFILE_BUSY)
		return false
	end

	local payload = result.data
	local migrated: any = Result.ok(payload.data)
	if payload.data ~= nil then
		migrated = Migrations.migrate(payload.data, os.time())
	end
	if not migrated.ok then
		warn(
			`[DataService] migration failed for {player.UserId}: {migrated.code} {tostring(
				migrated.message
			)}`
		)
		player:Kick(Config.Strings.errors.SAVE_FAILED)
		return false
	end

	local now = os.time()
	local session: Session = {
		userId = player.UserId,
		data = normalise(migrated.data, now),
		sessionKey = payload.sessionKey,
		provider = provider,
		loaded = true,
		saving = false,
		lastSaveAt = now,
		dirty = false,
		playSeconds = 0,
		sessionStart = now,
	}
	sessions[player.UserId] = session
	players[player.UserId] = player

	local maid = Maid.new()
	maids[player.UserId] = maid
	maid:Add(function()
		sessions[player.UserId] = nil
		players[player.UserId] = nil
		maids[player.UserId] = nil
	end)

	DataService.ProfileLoaded:Fire(player, session.data)
	return true
end

function DataService.Get(player: Player): Profile.Profile?
	local session = sessions[player.UserId]
	return if session and session.loaded then session.data else nil
end

function DataService.GetSession(player: Player): Session?
	return sessions[player.UserId]
end

function DataService.IsLoaded(player: Player): boolean
	local session = sessions[player.UserId]
	return session ~= nil and session.loaded
end

--[[ Marks the profile for the next autosave; cheap to call from hot paths. ]]
function DataService.MarkDirty(player: Player)
	local session = sessions[player.UserId]
	if session then
		session.dirty = true
	end
end

--[[
	Saves now with retries and exponential backoff. Returns success.
	Never throws: a failed save must not take the server down.
]]
function DataService.SaveSession(userId: number, reason: string?): boolean
	local session = sessions[userId]
	if not session or not session.loaded then
		return false
	end
	if session.saving then
		return false
	end
	session.saving = true

	local now = os.time()
	session.data.Time.LastSaved = now
	session.data.Stats.PlaySeconds += math.max(0, now - session.lastSaveAt)
	session.lastSaveAt = now

	local attempts = 0
	local saved = false
	while attempts <= Balance.SaveRetries do
		attempts += 1
		local result = session.provider:SaveAsync(userId, session.data, session.sessionKey)
		if result.ok then
			saved = true
			break
		end
		if result.code == "SESSION_LOCKED" then
			warn(`[DataService] session lock lost for {userId}; not overwriting`)
			break
		end
		task.wait(Balance.SaveRetryBackoffSeconds * (2 ^ (attempts - 1)))
	end

	session.saving = false
	if saved then
		session.dirty = false
		DataService.ProfileSaved:Fire(userId, reason or "manual")
	else
		session.dirty = true
		warn(`[DataService] save failed for {userId} after {attempts} attempt(s)`)
	end
	return saved
end

--[[ Debounced "save soon" used by milestone actions. ]]
local saveSoonAt: { [number]: number } = {}
function DataService.SaveSoon(player: Player)
	local userId = player.UserId
	local now = os.clock()
	if saveSoonAt[userId] and (now - saveSoonAt[userId]) < Balance.SaveOnMilestoneSeconds then
		DataService.MarkDirty(player)
		return
	end
	saveSoonAt[userId] = now
	task.spawn(function()
		DataService.SaveSession(userId, "milestone")
	end)
end

function DataService.ReleasePlayer(player: Player)
	local userId = player.UserId
	local session = sessions[userId]
	if not session then
		return
	end
	DataService.ProfileReleasing:Fire(player, session.data)
	DataService.SaveSession(userId, "leave")
	session.loaded = false
	pcall(function()
		session.provider:ReleaseAsync(userId, session.sessionKey)
	end)
	local maid = maids[userId]
	if maid then
		maid:Destroy()
	end
end

--[[ Test/diagnostic helpers. ]]
function DataService.ProviderName(): string
	return if provider then provider.Name else "none"
end

function DataService.SetProviderForTests(newProvider: any)
	provider = newProvider
end

function DataService.SessionCount(): number
	local count = 0
	for _ in sessions do
		count += 1
	end
	return count
end

return DataService
