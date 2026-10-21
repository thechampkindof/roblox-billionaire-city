--!strict
local Framework = require(script.Parent.Parent.Framework)
local Objectives = require(script.Parent.Parent.Parent.src.shared.Core.Objectives)

local function context(overrides: any?)
	local base = Objectives.defaultContext()
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

Framework.test("collect cash measures the first objective", function()
	local progress =
		Objectives.measure({ kind = "CollectCash", amount = 50 }, context({ cashCollected = 25 }))
	Framework.equal(progress.current, 25)
	Framework.equal(progress.target, 50)
	Framework.isFalse(progress.done)
	Framework.near(progress.fraction, 0.5)
end)

Framework.test("count goals track purchases, hires and parcels", function()
	Framework.isTrue(
		Objectives.measure(
			{ kind = "UpgradePurchase", count = 1 },
			context({ upgradesPurchased = 1 })
		).done
	)
	Framework.isTrue(
		Objectives.measure({ kind = "HireStaff", count = 2 }, context({ staffHired = 2 })).done
	)
	Framework.isFalse(
		Objectives.measure({ kind = "OwnParcels", count = 3 }, context({ parcelsOwned = 2 })).done
	)
	Framework.isTrue(
		Objectives.measure({ kind = "HireManager", count = 1 }, context({ managersHired = 1 })).done
	)
end)

Framework.test("building level goals use the building lookup", function()
	local ctx = context({
		buildingLevel = function(id: string)
			return if id == "convenience_store" then 4 else 0
		end,
	})
	Framework.isTrue(
		Objectives.measure({ kind = "BuildingLevel", def = "convenience_store", level = 3 }, ctx).done
	)
	Framework.isFalse(
		Objectives.measure({ kind = "BuildingLevel", def = "other", level = 3 }, ctx).done
	)
end)

Framework.test("unknown goals never complete and zero targets are safe", function()
	local progress = Objectives.measure({ kind = "LandOnTheMoon" }, context())
	Framework.isFalse(progress.done)
	Framework.equal(progress.target, 1)
	local zero = Objectives.measure({ kind = "CollectCash", amount = 0 }, context())
	Framework.isTrue(zero.done, "zero target is instantly complete")
end)
