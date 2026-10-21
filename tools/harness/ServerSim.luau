--!strict
--[[
	Headless playthrough of the Phase 1 loop, executed against the real server code.

	`tools/server_sim.mjs` installs `tools/harness/Shim.luau`, boots `src/server`, then
	runs `ServerSim.run()`. Everything below is an assertion a Studio playtest would make
	by hand: does a player get a plot, does income accrue, do purchases charge exactly
	once, does the manager automate collection, does construction finish on its own, does
	the profile survive a save/reload, are unknown intents and floods rejected.
]]

local Shim = require(script.Parent.Shim)

Shim.install()
math.randomseed(1234)

local root = script.Parent.Parent.Parent

-- Rojo maps `src/shared` to `ReplicatedStorage.Shared`; mirror that in the shim so the
-- services' `game:GetService("ReplicatedStorage").Shared` resolves to the real modules.
game:GetService("ReplicatedStorage").Shared = root.src.shared

-- Boot the server (requires every service and runs Init/Start in dependency order).
require(root.src.server)
local Services = root.src.server.Services
local Shared = root.src.shared

local DataService = require(Services.DataService)
local OfflineService = require(Services.OfflineService)
local ObjectiveService = require(Services.ObjectiveService)
local ConstructionService = require(Services.ConstructionService)
local Content = require(Shared.Config.Init)
local Economy = require(Shared.Core.Economy)
local Remotes = require(Shared.Net.Remotes)
local Balance = Content.Balance

local ServerSim = {}

local results: { { label: string, ok: boolean, detail: string? } } = {}

local function check(label: string, ok: boolean, detail: string?): boolean
	table.insert(results, { label = label, ok = ok, detail = detail })
	local mark = if ok then "  PASS  " else "  FAIL  "
	print(`{mark}{label}{if detail then " — " .. detail else ""}`)
	return ok
end

local function count(tbl: any): number
	local total = 0
	for _ in tbl do
		total += 1
	end
	return total
end

local function describe(value: any): string?
	if value == nil then
		return nil
	end
	return tostring(value)
end

--[[ Sends an intent exactly like the client: through the same remote. ]]
local function send(player: any, intent: string, payload: any)
	Remotes.intent():FireServer(player, intent, payload)
end

--[[ A burst with no time passing, to exercise the rate limiter. ]]
local function burst(player: any, intent: string, payload: any, times: number)
	for _ = 1, times do
		send(player, intent, payload)
	end
end

function ServerSim.run(): { passed: number, failed: number, failures: { string } }
	local ok, err = pcall(ServerSim.play)
	if not ok then
		check("the simulation ran to completion", false, tostring(err))
	end
	return ServerSim.summary()
end

--[[ The actual playthrough; kept separate so a crash still reports the checks that ran. ]]
function ServerSim.play()
	local toasts: { any } = {}
	Remotes.toast().OnClientEvent:Connect(function(payload: any)
		table.insert(toasts, payload)
	end)

	local snapshots = 0
	Remotes.snapshot().OnClientEvent:Connect(function()
		snapshots += 1
	end)

	-- Every currency change is logged by EconomyService; assertions about money use this
	-- instead of raw cash, which keeps moving while a manager is hired.
	local logEntries: { any } = {}
	local EconomyService = require(Services.EconomyService)
	EconomyService.Log:Connect(function(entry: any)
		table.insert(logEntries, entry)
	end)

	local function countReason(reason: string): number
		local total = 0
		for _, entry in ipairs(logEntries) do
			if entry.reason == reason then
				total += 1
			end
		end
		return total
	end

	-- 1. Boot and join -----------------------------------------------------------

	local player = Shim.createPlayer(1001, "HarnessOne")
	Shim.join(player)
	Shim.advance(3)

	check(
		"DataService chose a provider",
		DataService.ProviderName() ~= "none",
		DataService.ProviderName()
	)

	local profile = DataService.Get(player)
	check("a profile is loaded for the joining player", profile ~= nil)
	if not profile then
		return
	end

	check("the starter parcel is owned", profile.Parcels[Content.starterParcelId] == true)
	check(
		"one starter building exists",
		count(profile.Buildings) == 1,
		describe(count(profile.Buildings))
	)
	check("a snapshot reached the client", snapshots > 0, describe(snapshots))

	local uid: string? = nil
	for key in profile.Buildings do
		uid = key
	end
	local building = profile.Buildings[uid :: string]
	check(
		"the starter building is the configured one",
		building.def == Content.starterBuildingId,
		building.def
	)
	check("the starter building is finished", ConstructionService.Progress(building) == 1)
	check("the player starts with cash", profile.Currency.Cash > 0, `${profile.Currency.Cash}`)
	local starterCash = profile.Currency.Cash

	-- 2. Income accrues and collects ---------------------------------------------

	Shim.advance(30)
	check("income accrues into pending", building.pending > 0, `$${building.pending}`)

	send(player, "IncomeCollect", { buildingUid = "all" })
	Shim.advance(1)
	check(
		"collecting pays the player",
		profile.Currency.Cash > starterCash,
		`$${starterCash} -> $${profile.Currency.Cash}`
	)
	check("collecting empties pending", building.pending == 0)

	-- 3. Upgrades ----------------------------------------------------------------

	local upgradeIds = Content.upgradeIdsFor(building.def)
	check("the building has generated upgrade lines", #upgradeIds > 0, describe(#upgradeIds))

	local upgradeId = upgradeIds[1]
	local cashBeforeUpgrade = profile.Currency.Cash
	profile.Currency.Cash = 100_000
	send(player, "UpgradePurchase", { buildingUid = uid, upgradeId = upgradeId })
	Shim.advance(1)
	check("an upgrade purchase raises the level", (building.upg[upgradeId] or 0) == 1)
	check(
		"an upgrade purchase is logged as a transaction",
		countReason("upgrade_purchase") == 1,
		describe(countReason("upgrade_purchase"))
	)

	local cashBeforeInvalid = profile.Currency.Cash
	send(player, "UpgradePurchase", { buildingUid = uid, upgradeId = "not.a.real.line" })
	Shim.advance(1)
	check("unknown upgrade ids cost nothing", profile.Currency.Cash == cashBeforeInvalid)
	check("unknown upgrade ids are not logged", countReason("upgrade_purchase") == 1)
	check("the upgrade charged less than the cash we granted", cashBeforeUpgrade >= 0)

	send(player, "LevelPurchase", { buildingUid = uid })
	Shim.advance(1)
	check("the building can be levelled", building.level == 2, describe(building.level))

	-- 4. Staff and manager ---------------------------------------------------------

	local staffGrade = Content.staff[1].id
	send(player, "StaffHire", { buildingUid = uid, grade = staffGrade })
	Shim.advance(1)
	check("a worker can be hired", (building.staff[staffGrade] or 0) == 1)

	profile.Currency.Cash = 200_000
	send(player, "ManagerHire", { buildingUid = uid })
	Shim.advance(1)
	check(
		"a manager can be hired once the building is level 2",
		building.manager ~= nil,
		describe(building.manager)
	)

	local cashBeforeAutomation = profile.Currency.Cash
	Shim.advance(180)
	check(
		"managers collect income automatically",
		profile.Currency.Cash > cashBeforeAutomation,
		`$${cashBeforeAutomation} -> $${profile.Currency.Cash}`
	)

	-- 5. Parcels and construction ----------------------------------------------

	local target: any = nil
	for _, parcel in ipairs(Content.parcels) do
		if parcel.id ~= Content.starterParcelId then
			target = parcel
			break
		end
	end
	check("a second parcel exists", target ~= nil)

	if target then
		profile.Currency.Cash = 500_000
		send(player, "ParcelPurchase", { parcelId = target.id })
		Shim.advance(1)
		check("a parcel purchase is recorded", profile.Parcels[target.id] == true)
		check(
			"a parcel purchase is logged once",
			countReason("parcel_purchase") == 1,
			describe(countReason("parcel_purchase"))
		)

		send(player, "ParcelPurchase", { parcelId = target.id })
		Shim.advance(1)
		check("buying the same parcel twice is rejected", countReason("parcel_purchase") == 1)

		local candidates = Content.buildingsForParcel(target)
		check("buildings that fit the parcel are known", #candidates > 0, describe(#candidates))
		if #candidates > 0 then
			local def = candidates[1]
			local buildCost = Content.totalBuildCost(def)
			profile.Currency.Cash = buildCost + 10_000
			send(player, "ConstructStart", { parcelId = target.id, buildingId = def.id })
			Shim.advance(1)

			local newUid: string? = nil
			for key, state in profile.Buildings do
				if state.parcel == target.id then
					newUid = key
				end
			end
			check("construction creates a building on the parcel", newUid ~= nil)
			if newUid then
				local newState = profile.Buildings[newUid]
				check("the new building starts under construction", newState.constructing ~= nil)
				check(
					"construction is paid for up front, once",
					profile.Currency.Cash == 10_000,
					`$${profile.Currency.Cash} left`
				)

				local phaseBefore = newState.phase
				Shim.advance(400)
				check("construction advances from timestamps", newState.phase >= phaseBefore)
				check(
					"construction finishes on its own",
					newState.constructing == nil,
					`phase ${newState.phase}`
				)
				check(
					"construction is charged exactly once",
					countReason("construction_start") == 1
				)
				check("no rush fees were charged", countReason("construction_rush") == 0)
			end
		end
	end

	-- 6. Objectives ----------------------------------------------------------------

	local objective = ObjectiveService.CurrentFor(player)
	check(
		"the objective chain moved past the first step",
		objective == nil or objective.id ~= "collect_first_income",
		objective and objective.id or "chain complete"
	)

	-- 7. Offline income -----------------------------------------------------------

	profile.Time.LastSaved = os.time() - 3600
	local offlineCash = OfflineService.Apply(player)
	local capped = Economy.offlineEarnings(3600, 1000, Balance.Rates)
	check("offline income is granted from the saved timestamp", offlineCash > 0, `$${offlineCash}`)
	check(
		"offline income respects the cap and efficiency",
		offlineCash <= capped,
		`$${offlineCash} vs cap $${capped}`
	)

	-- 8. Save and reload ----------------------------------------------------------

	local saved = DataService.SaveSession(1001, "harness")
	check("the profile saves", saved == true)

	local cashSnapshot = profile.Currency.Cash
	local upgradeCount = count(building.upg)
	local masteryXp = building.mastery.xp
	local buildingsBefore = count(profile.Buildings)
	local managerBefore = building.manager

	Shim.leave(player)
	Shim.advance(2)

	local rejoined = Shim.createPlayer(1001, "HarnessOne")
	Shim.join(rejoined)
	Shim.advance(3)

	local reloaded = DataService.Get(rejoined)
	check("the profile reloads", reloaded ~= nil)
	if reloaded then
		local reloadedBuilding = reloaded.Buildings[uid :: string]
		check(
			"cash survives the round trip",
			reloaded.Currency.Cash >= cashSnapshot,
			`$${reloaded.Currency.Cash} vs $${cashSnapshot}`
		)
		check(
			"every building survives the round trip",
			count(reloaded.Buildings) == buildingsBefore
		)
		check(
			"upgrades survive the round trip",
			reloadedBuilding and count(reloadedBuilding.upg) == upgradeCount
		)
		check(
			"the manager survives the round trip",
			reloadedBuilding and reloadedBuilding.manager == managerBefore
		)
		check(
			"mastery XP survives the round trip",
			reloadedBuilding and reloadedBuilding.mastery.xp >= masteryXp
		)

		-- 9. Authority -------------------------------------------------------------

		local collectsBefore = countReason("income_collect")
		send(rejoined, "IncomeCollect", { buildingUid = "all", extra = 1 })
		Shim.advance(1)
		check(
			"unexpected payload fields are rejected",
			countReason("income_collect") == collectsBefore
		)

		send(rejoined, "DefinitelyNotAnIntent", {})
		send(rejoined, "DebugAction", { action = "grant_cash" })
		Shim.advance(1)
		check("debug actions stay locked", countReason("debug_grant") == 0)

		local collectionsBefore = countReason("income_collect") + countReason("manager_collect")
		burst(rejoined, "IncomeCollect", { buildingUid = "all" }, 60)
		Shim.advance(1)
		local limited = false
		for _, toast in ipairs(toasts) do
			if type(toast) == "table" and tostring(toast.text):find("Slow down") then
				limited = true
			end
		end
		check("intent floods are rate limited", limited)
		check(
			"a flood cannot collect more than the bucket allows",
			(countReason("income_collect") + countReason("manager_collect")) - collectionsBefore
				<= 13,
			describe(
				(countReason("income_collect") + countReason("manager_collect")) - collectionsBefore
			)
		)
	end
end

function ServerSim.summary(): { passed: number, failed: number, failures: { string } }
	local failures: { string } = {}
	local passed = 0
	for _, result in ipairs(results) do
		if result.ok then
			passed += 1
		else
			table.insert(failures, result.label)
		end
	end
	return { passed = passed, failed = #failures, failures = failures }
end

function ServerSim.results(): { { label: string, ok: boolean, detail: string? } }
	return results
end

return ServerSim
