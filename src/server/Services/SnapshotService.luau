--!strict
--[[
	Server -> client state mirror.

	One snapshot on join, then coalesced patches of only the sections that changed,
	sent at most 4 times per second (Appendix B6). The client store is read-only: it can
	display state but never write it.
]]

local Players = game:GetService("Players")

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Core = Shared.Core
local Config = Shared.Config
local Util = Shared.Util
local Net = Shared.Net

local Signal = require(Core.Signal)
local Completion = require(Core.Completion)
local Mastery = require(Core.Mastery)
local Content = require(Config.Init)
local Balance = Content.Balance
local BuildingMath = require(Util.BuildingMath)
local Remotes = require(Net.Remotes)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local BuildingService = require(script.Parent.BuildingService)
local ConstructionService = require(script.Parent.ConstructionService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local StaffService = require(script.Parent.StaffService)
local ParcelService = require(script.Parent.ParcelService)

local SnapshotService = {}
SnapshotService.Name = "SnapshotService"
SnapshotService.Dependencies = {
	"DataService",
	"EconomyService",
	"PlotService",
	"BuildingService",
	"ConstructionService",
	"ObjectiveService",
	"StaffService",
	"ParcelService",
}

SnapshotService.Sent = Signal.new("SnapshotSent")

local dirty: { [Player]: { [string]: boolean } } = {}
local lastSent: { [Player]: number } = {}
local PATCH_INTERVAL = 1 / Balance.Network.patchHz

local function markAll(player: Player)
	local sections: { [string]: boolean } = {}
	for _, name in ipairs({ "currency", "buildings", "parcels", "objective", "plot" }) do
		sections[name] = true
	end
	dirty[player] = sections
end

function SnapshotService.MarkDirty(player: Player, section: string?)
	local sections = dirty[player]
	if not sections then
		markAll(player)
		return
	end
	if section then
		sections[section] = true
	else
		markAll(player)
	end
end

local function currencySection(player: Player, profile: any)
	local netWorth = EconomyService.NetWorth(profile)
	profile.Stats.NetWorthPeak = math.max(profile.Stats.NetWorthPeak or 0, netWorth)
	local completionParts = {
		buildings = 0,
		upgrades = 0,
		mastery = 0,
		research = 0,
		collections = 0,
		achievements = 0,
		secrets = 0,
	}
	local built = 0
	local upgradeLevels = 0
	local maxUpgradeLevels = 0
	local masteryTotal = 0
	for _, state in profile.Buildings do
		local def = Content.buildingById[state.def]
		if def then
			built += 1
			masteryTotal += (state.mastery.lvl - 1) / (Mastery.MAX_LEVEL - 1)
			for _, upgradeId in ipairs(Content.upgradeIdsFor(def.id)) do
				local upgrade = Content.upgradeById[upgradeId]
				upgradeLevels += state.upg[upgradeId] or 0
				maxUpgradeLevels += upgrade.maxLevel
			end
		end
	end
	completionParts.buildings = if #Content.buildings > 0 then built / #Content.buildings else 0
	completionParts.upgrades = if maxUpgradeLevels > 0 then upgradeLevels / maxUpgradeLevels else 0
	completionParts.mastery = if built > 0 then masteryTotal / built else 0

	return {
		cash = profile.Currency.Cash,
		reputation = profile.Currency.Reputation,
		prestige = profile.Currency.PrestigePoints,
		research = profile.Currency.ResearchPoints,
		netWorth = netWorth,
		netPerMin = EconomyService.NetIncomePerMin(profile),
		lifetimeEarned = profile.Stats.LifetimeEarned,
		completion = Completion.percent(completionParts, Balance.CompletionWeights),
		serverTime = os.time(),
	}
end

local function buildingsSection(player: Player, profile: any)
	local list: { [string]: any } = {}
	for uid, state in profile.Buildings do
		local def = Content.buildingById[state.def]
		if not def then
			continue
		end
		local income = BuildingMath.income(def, state)
		local progress, remaining = ConstructionService.Progress(state)
		local upgradeLevels: { [string]: number } = {}
		for upgradeId, level in state.upg do
			upgradeLevels[upgradeId] = level
		end
		list[uid] = {
			uid = uid,
			def = def.id,
			name = def.name,
			archetype = def.archetype,
			parcel = state.parcel,
			level = state.level,
			maxLevel = def.maxLevel,
			phase = state.phase,
			phases = #def.phases,
			upg = upgradeLevels,
			mastery = {
				xp = state.mastery.xp,
				lvl = state.mastery.lvl,
				progress = Mastery.progress(state.mastery.xp).fraction,
			},
			staff = table.clone(state.staff),
			staffSlots = def.staffSlots,
			wagesPerMin = StaffService.WagesPerMin(state),
			manager = state.manager,
			pending = state.pending,
			constructing = if state.constructing
				then { phase = state.constructing.phase, progress = progress, remaining = remaining }
				else nil,
			operational = BuildingMath.isOperational(state),
			income = {
				gross = income.grossPerMin,
				expenses = income.expensesPerMin,
				net = income.netPerMin,
				customers = income.customersPerMin,
				avgSpend = income.avgSpend,
			},
		}
	end
	return list
end

local function parcelsSection(player: Player, profile: any)
	local prices: { [string]: number } = {}
	local owned: { [string]: boolean } = {}
	for _, parcel in ipairs(Content.parcels) do
		owned[parcel.id] = profile.Parcels[parcel.id] == true
		prices[parcel.id] = ParcelService.PriceFor(profile, parcel.id)
	end
	return { owned = owned, prices = prices }
end

local function plotSection(player: Player)
	local plot = PlotService.Get(player)
	if not plot then
		return nil
	end
	return {
		slot = plot.slot,
		origin = { plot.origin.X, plot.origin.Y, plot.origin.Z },
	}
end

function SnapshotService.BuildSnapshot(player: Player): any?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	return {
		version = 1,
		currency = currencySection(player, profile),
		buildings = buildingsSection(player, profile),
		parcels = parcelsSection(player, profile),
		plot = plotSection(player),
		objective = ObjectiveService.CurrentFor(player),
		settings = table.clone(profile.Settings),
		offlineCapHours = Balance.OfflineCapHours,
		offlineEfficiency = Balance.OfflineEfficiency,
	}
end

local function sendPatch(player: Player)
	local sections = dirty[player]
	if not sections then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local patch: any = {}
	local hasAny = false
	for section in sections do
		if section == "currency" then
			patch.currency = currencySection(player, profile)
		elseif section == "buildings" then
			patch.buildings = buildingsSection(player, profile)
			patch.plot = plotSection(player)
		elseif section == "parcels" then
			patch.parcels = parcelsSection(player, profile)
		elseif section == "objective" then
			patch.objective = ObjectiveService.CurrentFor(player)
		elseif section == "plot" then
			patch.plot = plotSection(player)
		end
		hasAny = true
	end
	dirty[player] = nil
	if hasAny then
		Remotes.patch():FireClient(player, patch)
		SnapshotService.Sent:Fire(player, patch)
	end
end

function SnapshotService.SendFull(player: Player)
	local snapshot = SnapshotService.BuildSnapshot(player)
	if snapshot then
		Remotes.snapshot():FireClient(player, snapshot)
		SnapshotService.Sent:Fire(player, snapshot)
	end
end

function SnapshotService.Toast(player: Player, text: string, kind: string?)
	Remotes.toast():FireClient(player, { text = text, kind = kind or "info" })
end

function SnapshotService.Notice(player: Player, payload: any)
	Remotes.notice():FireClient(player, payload)
end

function SnapshotService.Init(registry: any)
	DataService.ProfileLoaded:Connect(function(player: Player)
		task.defer(function()
			SnapshotService.SendFull(player)
			SnapshotService.Toast(player, Content.strings.toasts.plotAssigned, "success")
		end)
	end)
	DataService.ProfileReleasing:Connect(function(player: Player)
		dirty[player] = nil
		lastSent[player] = nil
	end)

	-- Everything that changes what the client displays marks the relevant section.
	EconomyService.CurrencyChanged:Connect(function(player: Player)
		SnapshotService.MarkDirty(player, "currency")
	end)
	BuildingService.BuildingAdded:Connect(function(player: Player)
		SnapshotService.MarkDirty(player)
	end)
	BuildingService.BuildingUpdated:Connect(function(player: Player)
		SnapshotService.MarkDirty(player, "buildings")
	end)
	ParcelService.Purchased:Connect(function(player: Player)
		SnapshotService.MarkDirty(player)
	end)
	ObjectiveService.Completed:Connect(function(player: Player)
		SnapshotService.MarkDirty(player, "objective")
	end)
	ObjectiveService.Advanced:Connect(function(player: Player)
		SnapshotService.MarkDirty(player, "objective")
	end)
	ConstructionService.Started:Connect(function(player: Player)
		SnapshotService.MarkDirty(player, "buildings")
	end)
	ConstructionService.PhaseCompleted:Connect(function(player: Player)
		SnapshotService.MarkDirty(player, "buildings")
	end)
	ConstructionService.Finished:Connect(function(player: Player)
		SnapshotService.MarkDirty(player, "buildings")
	end)
end

function SnapshotService.Start()
	task.spawn(function()
		while true do
			task.wait(PATCH_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				if dirty[player] then
					local ok, err = pcall(sendPatch, player)
					if not ok then
						warn(`[SnapshotService] patch failed: {tostring(err)}`)
					end
				end
			end
		end
	end)
end

return SnapshotService
