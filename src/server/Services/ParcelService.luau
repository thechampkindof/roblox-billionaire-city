--!strict
--[[
	Land purchases.

	A parcel is bought with cash, once, and requires the gates in `Config/Parcels`
	(net worth today; districts, population and reputation later). Prices use the
	owned-parcel multiplier from Balance so land stays a real sink.
]]

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Core = Shared.Core
local Config = Shared.Config

local Result = require(Core.Result)
local Signal = require(Core.Signal)
local Unlock = require(Core.Unlock)
local Content = require(Config.Init)
local Parcels = require(Config.Parcels)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)
local BuildingService = require(script.Parent.BuildingService)

local ParcelService = {}
ParcelService.Name = "ParcelService"
ParcelService.Dependencies = { "DataService", "EconomyService", "PlotService", "BuildingService" }

ParcelService.Purchased = Signal.new("ParcelPurchased")

local function ownedCount(profile: any): number
	local count = 0
	for _ in profile.Parcels do
		count += 1
	end
	return count
end

--[[ Current price of a parcel for this player. ]]
function ParcelService.PriceFor(profile: any, parcelId: string): number
	local def = Content.parcelById[parcelId]
	if not def then
		return math.huge
	end
	return Parcels.priceFor(def, ownedCount(profile))
end

function ParcelService.Purchase(player: Player, parcelId: string): Result.Result<number>
	local profile = DataService.Get(player)
	if not profile then
		return Result.err("NOT_LOADED")
	end
	local def = Content.parcelById[parcelId]
	if not def then
		return Result.err("INVALID_ID")
	end
	if profile.Parcels[parcelId] then
		return Result.err("PARCEL_OWNED")
	end

	local district = profile.Districts[def.district]
	if not district or not district.unlocked then
		return Result.err("LOCKED")
	end

	local context = BuildingService.Context(player)
	local gate = Unlock.evaluate(def.requires, context)
	if not gate.ok then
		return Result.err("LOCKED", gate.unmet[1] and gate.unmet[1].description)
	end

	local price = ParcelService.PriceFor(profile, parcelId)
	local paid = EconomyService.SpendCash(player, price, "parcel_purchase")
	if not paid.ok then
		return paid
	end

	profile.Parcels[parcelId] = true
	-- Owning more land develops the district, which gates other districts later.
	local districtState = profile.Districts[def.district]
	if districtState then
		local owned = 0
		for _, parcel in ipairs(Content.parcelsFor(def.district)) do
			if profile.Parcels[parcel.id] then
				owned += 1
			end
		end
		districtState.devRating = math.min(100, owned * Content.Balance.Land.devRatingPerParcel)
	end

	PlotService.Refresh(player)
	DataService.SaveSoon(player)
	ParcelService.Purchased:Fire(player, parcelId, price)
	return Result.ok(price)
end

function ParcelService.Init(registry: any) end
function ParcelService.Start() end

return ParcelService
