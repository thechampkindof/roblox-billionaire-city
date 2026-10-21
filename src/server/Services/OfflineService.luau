--!strict
--[[
	Offline income.

	Computed from saved timestamps only — never from "time since the client said it
	left". Elapsed time is clamped to the cap in `Balance` and scaled by the offline
	efficiency. A clock rollback (negative elapsed) earns nothing.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config
local Util = Shared.Util

local Signal = require(Core.Signal)
local Economy = require(Core.Economy)
local Content = require(Config.Init)
local Balance = Content.Balance
local BuildingMath = require(Util.BuildingMath)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local OfflineService = {}
OfflineService.Name = "OfflineService"
OfflineService.Dependencies = { "DataService", "EconomyService" }

OfflineService.Applied = Signal.new("OfflineIncomeApplied")

--[[ Called on ProfileLoaded. Returns the cash granted. ]]
function OfflineService.Apply(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end

	local now = os.time()
	local lastSaved = profile.Time.LastSaved
	if type(lastSaved) ~= "number" or lastSaved <= 0 then
		return 0
	end

	local elapsed = now - lastSaved
	if elapsed <= 0 then
		return 0
	end

	local total = 0
	for _, state in profile.Buildings do
		local def = Content.buildingById[state.def]
		if def and BuildingMath.isOperational(state) then
			local net = BuildingMath.income(def, state).netPerMin
			total += Economy.offlineEarnings(elapsed, net, Balance.Rates)
		end
		state.lastAccrual = now
	end

	if total <= 0 then
		return 0
	end

	local granted = EconomyService.Grant(player, { cash = total }, "offline_income")
	if not granted.ok then
		return 0
	end

	OfflineService.Applied:Fire(player, total, elapsed)
	return total
end

function OfflineService.Init(registry: any)
	DataService.ProfileLoaded:Connect(function(player: Player)
		task.defer(function()
			OfflineService.Apply(player)
		end)
	end)
end

function OfflineService.Start() end

return OfflineService
