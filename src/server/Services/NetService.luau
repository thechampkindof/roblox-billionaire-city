--!strict
--[[
	Intent gateway.

	Every client -> server message passes through here:
	  1. unknown intent names are dropped,
	  2. payloads are schema-validated,
	  3. per-player token buckets reject floods,
	  4. ids are checked against Config,
	  5. the handler returns a Result; failures become a toast with a stable code.

	No `InvokeClient` anywhere. No client-computed money.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config
local Net = Shared.Net

local Result = require(Core.Result)
local Validators = require(Net.Validators)
local RateLimiter = require(Net.RateLimiter)
local Remotes = require(Net.Remotes)
local Content = require(Config.Init)
local Balance = Content.Balance

local DataService = require(script.Parent.DataService)

local NetService = {}
NetService.Name = "NetService"
NetService.Dependencies = { "DataService" }

NetService.Rejected = require(Core.Signal).new("IntentRejected")

type Handler = (player: Player, payload: any) -> Result.Result<any>

local handlers: { [string]: Handler } = {}
local limiter = RateLimiter.new(Balance.RateLimit)

--[[ Services register their intent handlers during Init. ]]
function NetService.Register(intent: string, handler: Handler)
	if not Remotes.INTENTS[intent] then
		error(`intent "{intent}" has no schema; add it to Net/Remotes`, 2)
	end
	handlers[intent] = handler
end

local function toast(player: Player, text: string, kind: string)
	Remotes.toast():FireClient(player, { text = text, kind = kind })
end

local function reject(player: Player, code: string, message: string?)
	NetService.Rejected:Fire(player, code, message)
	local text = if message and #message > 0
		then message
		else (Content.strings.errors[code] or Content.strings.errors.UNKNOWN_INTENT)
	toast(player, text, "error")
end

local function dispatch(player: Player, intent: string, payload: any)
	local schema = Remotes.INTENTS[intent]
	if not schema then
		reject(player, "UNKNOWN_INTENT")
		return
	end
	local valid, reason = Validators.validatePayload(schema, payload)
	if not valid then
		reject(player, "INVALID_PAYLOAD", reason)
		return
	end
	local allowed, retryAfter = limiter:Allow(player.UserId, intent)
	if not allowed then
		-- The player gets the friendly string; the retry time is diagnostic only.
		NetService.Rejected:Fire(player, "RATE_LIMITED", retryAfter)
		toast(player, Content.strings.errors.RATE_LIMITED, "error")
		return
	end
	if not DataService.IsLoaded(player) then
		reject(player, "NOT_LOADED")
		return
	end

	local handler = handlers[intent]
	if not handler then
		reject(player, "UNKNOWN_INTENT")
		return
	end

	local ok, result = xpcall(function()
		return handler(player, payload)
	end, function(message: any)
		return `{tostring(message)}\n{debug.traceback("", 2)}`
	end)
	if not ok then
		warn(`[NetService] {intent} handler errored: {tostring(result)}`)
		reject(player, "INVALID_PAYLOAD")
		return
	end
	if result and not result.ok then
		reject(player, result.code, result.message)
	end
end

function NetService.Init(registry: any)
	Remotes.createAll()
	Remotes.intent().OnServerEvent:Connect(function(player: Player, intent: any, payload: any)
		if type(intent) ~= "string" then
			return
		end
		dispatch(player, intent, payload)
	end)

	local function registerAll()
		NetService.Register("ParcelPurchase", function(player: Player, payload: any)
			return require(script.Parent.ParcelService).Purchase(player, payload.parcelId)
		end)
		NetService.Register("ConstructStart", function(player: Player, payload: any)
			local result = require(script.Parent.ConstructionService).StartConstruction(
				player,
				payload.parcelId,
				payload.buildingId
			)
			return Result.map(result, function(uid)
				return uid
			end)
		end)
		NetService.Register("ConstructionRush", function(player: Player, payload: any)
			return require(script.Parent.ConstructionService).Rush(player, payload.buildingUid)
		end)
		NetService.Register("UpgradePurchase", function(player: Player, payload: any)
			return require(script.Parent.UpgradeService).Purchase(
				player,
				payload.buildingUid,
				payload.upgradeId
			)
		end)
		NetService.Register("LevelPurchase", function(player: Player, payload: any)
			return require(script.Parent.UpgradeService).PurchaseLevel(player, payload.buildingUid)
		end)
		NetService.Register("StaffHire", function(player: Player, payload: any)
			return require(script.Parent.StaffService).Hire(
				player,
				payload.buildingUid,
				payload.grade
			)
		end)
		NetService.Register("ManagerHire", function(player: Player, payload: any)
			return require(script.Parent.StaffService).HireManager(player, payload.buildingUid)
		end)
		NetService.Register("IncomeCollect", function(player: Player, payload: any)
			return require(script.Parent.IncomeService).Collect(player, payload.buildingUid)
		end)
		NetService.Register("ObjectivePin", function(player: Player, payload: any)
			return require(script.Parent.ObjectiveService).Pin(player, payload.objectiveId)
		end)
		NetService.Register("SettingsSet", function(player: Player, payload: any)
			local valid, value = Validators.coerceSetting(payload.key, payload.value)
			if not valid then
				return Result.err("INVALID_PAYLOAD", tostring(payload.key))
			end
			local profile = DataService.Get(player)
			if not profile then
				return Result.err("NOT_LOADED")
			end
			profile.Settings[payload.key] = value
			DataService.MarkDirty(player)
			return Result.ok(true)
		end)
		NetService.Register("DebugAction", function(player: Player, payload: any)
			return require(script.Parent.DebugService).Run(player, payload.action)
		end)
	end
	registerAll()
end

function NetService.Start() end

return NetService
