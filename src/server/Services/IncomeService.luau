--!strict
--[[
	Server-side income accrual.

	Businesses accrue into `state.pending` from their saved `lastAccrual` timestamp, so
	a rejoin or a laggy frame can never lose or duplicate income. A manager collects
	automatically; otherwise the player presses Collect.

	The tick is O(owned buildings) every 2 seconds and never yields inside a transaction.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config
local Util = Shared.Util

local Result = require(Core.Result)
local Signal = require(Core.Signal)
local Money = require(Core.Money)
local Mastery = require(Core.Mastery)
local Content = require(Config.Init)
local Balance = Content.Balance
local BuildingMath = require(Util.BuildingMath)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local BuildingService = require(script.Parent.BuildingService)

local IncomeService = {}
IncomeService.Name = "IncomeService"
IncomeService.Dependencies = { "DataService", "EconomyService", "BuildingService" }

IncomeService.Collected = Signal.new("IncomeCollected")
IncomeService.Accrued = Signal.new("IncomeAccrued")

local TICK_SECONDS = 2

--[[ Fractional remainders so accrued income stays exact without storing floats. ]]
local remainders: { [number]: { [string]: number } } = {}

local function remainderFor(userId: number, uid: string): number
	local perPlayer = remainders[userId]
	if not perPlayer then
		perPlayer = {}
		remainders[userId] = perPlayer
	end
	return perPlayer[uid] or 0
end

local function setRemainder(userId: number, uid: string, value: number)
	local perPlayer = remainders[userId]
	if not perPlayer then
		perPlayer = {}
		remainders[userId] = perPlayer
	end
	perPlayer[uid] = value
end

--[[ Accrues one building's income up to `now`. Returns the cash added. ]]
function IncomeService.Accrue(player: Player, uid: string, state: any, now: number): number
	local def = Content.buildingById[state.def]
	if not def or not BuildingMath.isOperational(state) then
		return 0
	end
	local elapsed = math.max(0, now - (state.lastAccrual or now))
	if elapsed <= 0 then
		return 0
	end
	local net = BuildingMath.income(def, state).netPerMin
	local raw = (elapsed / 60) * net + remainderFor(player.UserId, uid)
	local whole = math.floor(raw)
	setRemainder(player.UserId, uid, raw - whole)
	state.lastAccrual = now
	if whole <= 0 then
		return 0
	end
	state.pending = math.min(Money.MAX_SAFE, state.pending + whole)
	return whole
end

--[[ Ticks every loaded player. Managers are collected automatically. ]]
function IncomeService.Tick()
	local now = os.time()
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = DataService.Get(player)
		if not profile then
			continue
		end
		local managerCash = 0
		for uid, state in profile.Buildings do
			local accrued = IncomeService.Accrue(player, uid, state, now)
			if accrued > 0 then
				IncomeService.Accrued:Fire(player, uid, accrued)
				if state.manager then
					managerCash += state.pending
					state.pending = 0
				end
			end
		end
		if managerCash > 0 then
			local granted = EconomyService.Grant(player, { cash = managerCash }, "manager_collect")
			if granted.ok then
				IncomeService.Collected:Fire(player, "manager", managerCash)
			else
				-- Put the money back if the transaction was rejected.
				for _, state in profile.Buildings do
					if state.manager then
						state.pending += managerCash
						break
					end
				end
			end
		end
	end
end

--[[ Collects pending income for one building, or all of them ("all"). ]]
function IncomeService.Collect(player: Player, target: string): Result.Result<number>
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end

	local total = 0
	local collected: { { uid: string, state: any, amount: number } } = {}

	if target == "all" then
		for uid, state in profile.Buildings do
			if state.pending > 0 then
				table.insert(collected, { uid = uid, state = state, amount = state.pending })
				total += state.pending
			end
		end
	else
		local state = profile.Buildings[target]
		if not state then
			return Result.err("NOT_FOUND")
		end
		if state.pending <= 0 then
			return Result.err("NOTHING_TO_COLLECT")
		end
		table.insert(collected, { uid = target, state = state, amount = state.pending })
		total = state.pending
	end

	if total <= 0 then
		return Result.err("NOTHING_TO_COLLECT")
	end

	local granted = EconomyService.Grant(player, { cash = total }, "income_collect")
	if not granted.ok then
		return granted
	end

	for _, entry in ipairs(collected) do
		entry.state.pending = 0
		local def = Content.buildingById[entry.state.def]
		if def then
			local xp = BuildingMath.masteryXpForCash(entry.amount, "collect")
			if Balance.Mastery.enabled and def.masteryEnabled then
				local softCap = Balance.Mastery.softCapPerHour
					* (Balance.Mastery.windowSeconds / 3600)
				local nextState, gained = Mastery.gain(
					entry.state.mastery,
					xp,
					os.time(),
					softCap,
					Balance.Mastery.windowSeconds
				)
				if gained > 0 then
					local levelChanged = nextState.lvl ~= entry.state.mastery.lvl
					entry.state.mastery = nextState
					if levelChanged then
						BuildingService.Rebuild(player, entry.uid)
					end
				end
			end
		end
	end

	DataService.MarkDirty(player)
	DataService.SaveSoon(player)
	IncomeService.Collected:Fire(player, target, total)
	return Result.ok(total)
end

--[[ Pending income across every building, used by UI and net-worth tools. ]]
function IncomeService.PendingTotal(profile: any): number
	local total = 0
	for _, state in profile.Buildings do
		total += state.pending
	end
	return total
end

function IncomeService.Init(registry: any)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(IncomeService.Tick)
			if not ok then
				warn(`[IncomeService] tick failed: {tostring(err)}`)
			end
		end
	end)
	DataService.ProfileReleasing:Connect(function(player: Player)
		remainders[player.UserId] = nil
	end)
end

function IncomeService.Start() end

return IncomeService
