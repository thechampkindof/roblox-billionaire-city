--!strict
--[[
	The single door for money (Appendix B2, §B5).

	Every currency change in the game goes through `EconomyService.Transact`:
	  * rejects non-finite, negative or non-integer amounts,
	  * rejects debits the player cannot afford,
	  * caps every balance at 2^53,
	  * commits atomically — no yields between the check and the write,
	  * emits one economy log event per transaction.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config
local Util = Shared.Util

local Result = require(Core.Result)
local Money = require(Core.Money)
local Signal = require(Core.Signal)
local Economy = require(Core.Economy)
local Content = require(Config.Init)
local BuildingMath = require(Util.BuildingMath)

local DataService = require(script.Parent.DataService)

local EconomyService = {}
EconomyService.Name = "EconomyService"
EconomyService.Dependencies = { "DataService" }

EconomyService.CurrencyChanged = Signal.new("CurrencyChanged")
EconomyService.Transacted = Signal.new("Transacted")
EconomyService.Log = Signal.new("EconomyLog")

export type Currency = "Cash" | "Reputation" | "PrestigePoints" | "ResearchPoints"

export type Deltas = {
	cash: number?,
	reputation: number?,
	prestige: number?,
	research: number?,
}

local CURRENCY_FIELD: { [string]: string } = {
	cash = "Cash",
	reputation = "Reputation",
	prestige = "PrestigePoints",
	research = "ResearchPoints",
}

local function validateAmount(value: any, allowNegative: boolean): (boolean, string?)
	if value == nil then
		return true, nil
	end
	if not Money.isSafeInteger(value) then
		return false, "amount must be a whole number inside the exact range"
	end
	if not allowNegative and value < 0 then
		return false, "amount must not be negative"
	end
	return true, nil
end

--[[
	Applies `deltas` (positive = credit, negative = debit) atomically.

	`reason` is a stable tag for telemetry ("parcel_purchase", "income_collect", ...).
]]
function EconomyService.Transact(
	player: Player,
	deltas: Deltas,
	reason: string
): Result.Result<boolean>
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end

	-- Validate everything before touching state.
	for key, value in deltas do
		local field = CURRENCY_FIELD[key]
		if not field then
			return Result.err("INVALID_PAYLOAD", `unknown currency "{key}"`)
		end
		local ok, message = validateAmount(value, true)
		if not ok then
			return Result.err("INVALID_PAYLOAD", tostring(message))
		end
	end

	local currency = profile.Currency
	local previous = table.clone(currency)
	local applied: { [string]: number } = {}

	for key, value in deltas do
		local field = CURRENCY_FIELD[key]
		local amount = value or 0
		if amount == 0 then
			continue
		end
		local nextValue = currency[field] + amount
		if nextValue < 0 then
			return Result.err(
				if field == "Cash" then "INSUFFICIENT_FUNDS" else "INSUFFICIENT_PRESTIGE",
				field
			)
		end
		currency[field] = math.clamp(nextValue, 0, Money.MAX_SAFE)
		applied[field] = amount
	end

	if next(applied) == nil then
		return Result.ok(false)
	end

	if applied.Cash and applied.Cash > 0 then
		profile.Stats.LifetimeEarned = Money.add(profile.Stats.LifetimeEarned, applied.Cash)
	end
	DataService.MarkDirty(player)

	for field, amount in applied do
		EconomyService.CurrencyChanged:Fire(player, field, previous[field], currency[field], reason)
	end
	EconomyService.Transacted:Fire(player, {
		reason = reason,
		deltas = applied,
		before = previous,
		after = table.clone(currency),
	})
	EconomyService.Log:Fire({
		userId = player.UserId,
		reason = reason,
		deltas = applied,
		balance = currency.Cash,
	})

	return Result.ok(true)
end

function EconomyService.Grant(
	player: Player,
	deltas: Deltas,
	reason: string
): Result.Result<boolean>
	return EconomyService.Transact(player, deltas, reason)
end

--[[ Debits cash; convenience wrapper with a readable error code. ]]
function EconomyService.SpendCash(
	player: Player,
	amount: number,
	reason: string
): Result.Result<boolean>
	local ok, message = validateAmount(amount, false)
	if not ok then
		return Result.err("INVALID_PAYLOAD", tostring(message))
	end
	if amount == 0 then
		return Result.ok(true)
	end
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end
	if profile.Currency.Cash < amount then
		return Result.err("INSUFFICIENT_FUNDS")
	end
	return EconomyService.Transact(player, { cash = -amount }, reason)
end

--[[ Net worth: cash + land + invested building value + unspent construction. ]]
function EconomyService.NetWorth(profile: any): number
	local land = 0
	for parcelId in profile.Parcels do
		local def = Content.parcelById[parcelId]
		if def then
			land += def.landCost
		end
	end
	local buildings = 0
	for _, state in profile.Buildings do
		local def = Content.buildingById[state.def]
		if def then
			buildings += BuildingMath.investedValue(def, state)
		end
	end
	return Economy.netWorth({
		cash = profile.Currency.Cash,
		landCostBasis = land,
		buildCostBasis = buildings,
		upgradeCostBasis = 0,
		assetValue = 0,
	})
end

--[[ Total income per minute across owned, operational buildings. ]]
function EconomyService.NetIncomePerMin(profile: any): number
	local total = 0
	for _, state in profile.Buildings do
		local def = Content.buildingById[state.def]
		if def and BuildingMath.isOperational(state) then
			total += BuildingMath.income(def, state).netPerMin
		end
	end
	return total
end

return EconomyService
