--!strict
--[[
	Remote definitions, shared by server and client.

	Client -> server: a single `Intent` RemoteEvent carrying (intentName, payload).
	Server -> client: `StateSnapshot`, `StatePatch`, `Toast`, `Notice`.

	Every intent has a declarative payload schema validated by `Net/Validators` on the
	server before any service sees it; unknown intents are dropped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.FOLDER_NAME = "BillionaireNet"
Remotes.SERVER_EVENTS = { "StateSnapshot", "StatePatch", "Toast", "Notice" }
Remotes.CLIENT_EVENT = "Intent"

export type FieldType = "string" | "number" | "boolean"

export type IntentSchema = {
	fields: { [string]: FieldType },
	maxStringLength: number?,
}

--[[ Intent name -> payload schema. Add a row here when adding an intent. ]]
local INTENTS: { [string]: IntentSchema } = {
	ParcelPurchase = { fields = { parcelId = "string" } },
	ConstructStart = { fields = { parcelId = "string", buildingId = "string" } },
	ConstructionRush = { fields = { buildingUid = "string" } },
	UpgradePurchase = { fields = { buildingUid = "string", upgradeId = "string" } },
	LevelPurchase = { fields = { buildingUid = "string" } },
	StaffHire = { fields = { buildingUid = "string", grade = "string" } },
	ManagerHire = { fields = { buildingUid = "string" } },
	IncomeCollect = { fields = { buildingUid = "string" } },
	ObjectivePin = { fields = { objectiveId = "string" } },
	SettingsSet = { fields = { key = "string", value = "string" } },
	DebugAction = { fields = { action = "string" } },
}
Remotes.INTENTS = INTENTS

export type IntentName = string

local cache: { [string]: RemoteEvent } = {}

local function folder(): Instance
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(Remotes.FOLDER_NAME)
		if existing then
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = Remotes.FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	else
		return ReplicatedStorage:WaitForChild(Remotes.FOLDER_NAME, 30)
			or error("net folder missing")
	end
end

--[[ Gets (and on the server, creates) a RemoteEvent by name. ]]
function Remotes.get(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	local parent = folder()
	local event: RemoteEvent
	if RunService:IsServer() then
		local existing = parent:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			event = existing
		else
			event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = parent
		end
	else
		event = parent:WaitForChild(name, 30) :: RemoteEvent
	end
	cache[name] = event
	return event
end

--[[ Server-only: creates every remote up front so clients never wait on first use. ]]
function Remotes.createAll()
	if not RunService:IsServer() then
		return
	end
	for _, name in ipairs(Remotes.SERVER_EVENTS) do
		Remotes.get(name)
	end
	Remotes.get(Remotes.CLIENT_EVENT)
end

function Remotes.intent(): RemoteEvent
	return Remotes.get(Remotes.CLIENT_EVENT)
end

function Remotes.snapshot(): RemoteEvent
	return Remotes.get("StateSnapshot")
end

function Remotes.patch(): RemoteEvent
	return Remotes.get("StatePatch")
end

function Remotes.toast(): RemoteEvent
	return Remotes.get("Toast")
end

function Remotes.notice(): RemoteEvent
	return Remotes.get("Notice")
end

return Remotes
