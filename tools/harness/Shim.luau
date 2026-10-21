--!strict
--[[
	Minimal Roblox environment shim, used by `tools/server_sim.mjs` to execute the real
	server services headlessly.

	It implements only what the game code actually calls:
	  * `Instance.new` with parenting, children, attributes, `IsA`, `Clone`, `Destroy`
	  * `game:GetService` for Players / RunService / DataStoreService / Workspace /
	    ServerStorage / ReplicatedStorage, `game:BindToClose`, `game.JobId`
	  * RBXScriptSignals (`Connect`, `Fire`, `Wait`, `Once`)
	  * a deterministic scheduler for `task.spawn` / `defer` / `delay` / `wait`
	  * a virtual clock behind `os.time()` / `os.clock()`
	  * DataTypes used by world building (`Vector3`, `CFrame`, `Color3`, `UDim2`)
	  * an in-memory DataStore that honours `GetAsync` / `SetAsync` / `UpdateAsync`

	This is test scaffolding: it is deliberately permissive and never shipped in a place.
]]

local Shim = {}

-- Scheduler -------------------------------------------------------------------

local threads: { { co: thread, wake: number, name: string? } } = {}
-- Start at a realistic Unix timestamp so persisted timestamps look like production data.
local clock = 1_700_000_000

local function addThread(co: thread, wake: number)
	table.insert(threads, { co = co, wake = wake })
end

local function resumeThread(entry)
	if coroutine.status(entry.co) == "dead" then
		return false
	end
	local ok, wake = coroutine.resume(entry.co, clock)
	if not ok then
		error(`[shim] task errored: {tostring(wake)}`, 0)
	end
	if coroutine.status(entry.co) == "dead" then
		return false
	end
	entry.wake = if type(wake) == "number" then wake else clock
	return true
end

task = {
	spawn = function(fn: (...any) -> ...any, ...: any)
		local co = coroutine.create(fn)
		local ok, yielded = coroutine.resume(co, ...)
		if not ok then
			error(`[shim] task.spawn errored: {tostring(yielded)}`, 0)
		end
		if coroutine.status(co) ~= "dead" then
			table.insert(threads, {
				co = co,
				wake = if type(yielded) == "number" then yielded else clock,
			})
		end
		return co
	end,
	defer = function(fn: (...any) -> ...any, ...: any)
		local co = coroutine.create(fn)
		addThread(co, clock)
		return co
	end,
	delay = function(seconds: number, fn: (...any) -> ...any, ...: any)
		local co = coroutine.create(fn)
		addThread(co, clock + (seconds or 0))
		return co
	end,
	wait = function(seconds: number?)
		coroutine.yield(clock + (seconds or 0))
	end,
	cancel = function() end,
}

os = {
	time = function(): number
		return math.floor(clock)
	end,
	clock = function(): number
		return clock
	end,
	date = os.date,
	difftime = os.difftime,
}

--[[ Advances the virtual clock by `seconds`, running every due thread. ]]
function Shim.advance(seconds: number)
	local target = clock + seconds
	local guard = 0
	while clock < target do
		guard += 1
		if guard > 100_000 then
			error("[shim] scheduler made no progress (busy loop?)")
		end
		local nextWake: number? = nil
		for _, entry in ipairs(threads) do
			if
				coroutine.status(entry.co) ~= "dead" and (nextWake == nil or entry.wake < nextWake)
			then
				nextWake = entry.wake
			end
		end
		if nextWake == nil then
			clock = target
			break
		end
		local stamp = math.min(target, math.max(clock, nextWake))
		clock = stamp
		local index = #threads
		while index >= 1 do
			local entry = threads[index]
			if coroutine.status(entry.co) == "dead" then
				table.remove(threads, index)
			elseif entry.wake <= clock then
				if not resumeThread(entry) then
					table.remove(threads, index)
				end
			end
			index -= 1
		end
	end
	clock = target
end

function Shim.now(): number
	return clock
end

-- Data types -------------------------------------------------------------------

local Vector3 = {}
Vector3.__index = Vector3
function Vector3.new(x: number?, y: number?, z: number?): any
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end
Vector3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3.__mul = function(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	if type(a) == "number" then
		return Vector3.new(b.X * a, b.Y * a, b.Z * a)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3.__tostring = function(v)
	return string.format("(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
end

local Vector2 = {}
Vector2.__index = Vector2
function Vector2.new(x: number?, y: number?): any
	return setmetatable({ X = x or 0, Y = y or 0 }, Vector2)
end

local CFrame = {}
CFrame.__index = CFrame
function CFrame.new(x: any, y: number?, z: number?): any
	local position = if type(x) == "table" and x.X then x else Vector3.new(x, y, z)
	return setmetatable({ Position = position }, CFrame)
end
function CFrame.Angles(): any
	return CFrame.new(0, 0, 0)
end
function CFrame.lookAt(from: any, _to: any): any
	return CFrame.new(from)
end
function CFrame:Lerp(_other: any, _alpha: number?): any
	return CFrame.new(self.Position)
end
CFrame.__mul = function(a, b)
	return CFrame.new(a.Position + (b.Position or Vector3.new(0, 0, 0)))
end

local Color3 = {}
Color3.__index = Color3
function Color3.new(r: number?, g: number?, b: number?): any
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end
function Color3.fromRGB(r: number, g: number, b: number): any
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h: number, s: number, v: number): any
	return Color3.new(h, s, v)
end

local UDim = {}
UDim.__index = UDim
function UDim.new(scale: number?, offset: number?): any
	return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDim)
end

local UDim2 = {}
UDim2.__index = UDim2
function UDim2.new(x: number?, xo: number?, y: number?, yo: number?): any
	return setmetatable({ X = UDim.new(x, xo), Y = UDim.new(y, yo) }, UDim2)
end
function UDim2.fromScale(x: number?, y: number?): any
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x: number?, y: number?): any
	return UDim2.new(0, x, 0, y)
end

local Rect = {}
function Rect.new(x: number, y: number, w: number, h: number): any
	return { Min = Vector2.new(x, y), Max = Vector2.new(x + w, y + h) }
end

-- Enums -------------------------------------------------------------------------

-- Enum items are cached so `Enum.UserInputType.MouseButton1 == Enum.UserInputType.MouseButton1`
-- holds, exactly like Roblox (the input code compares them by identity).
local enumCache: { [string]: any } = {}
local Enum = setmetatable({}, {
	__index = function(_self, enumType: string)
		local items: { [string]: any } = {}
		return setmetatable({}, {
			__index = function(_e, name: string)
				local key = `{enumType}.{name}`
				local item = enumCache[key]
				if not item then
					item = { EnumType = enumType, Name = name }
					enumCache[key] = item
				end
				return item
			end,
		})
	end,
})

-- Signals -------------------------------------------------------------------------

local Connection = {}
Connection.__index = Connection
function Connection.Disconnect(self: any)
	self.Connected = false
end

local function newSignal(name: string?)
	local handlers: { any } = {}
	local signal: any = { Name = name or "Signal" }

	function signal:Connect(handler: (...any) -> ())
		local connection = setmetatable({ Connected = true, _handler = handler }, Connection)
		table.insert(handlers, connection)
		return connection
	end

	function signal:Once(handler: (...any) -> ())
		return signal:Connect(handler)
	end

	function signal:Wait()
		local ready = false
		local values: any = nil
		signal:Connect(function(...)
			values = { n = select("#", ...), ... }
			ready = true
		end)
		while not ready do
			task.wait(0)
		end
		return table.unpack(values, 1, values.n)
	end

	function signal:Fire(...)
		local snapshot = table.clone(handlers)
		local args = { n = select("#", ...), ... }
		for _, connection in ipairs(snapshot) do
			if connection.Connected then
				local ok, err = xpcall(function()
					connection._handler(table.unpack(args, 1, args.n))
				end, function(message: any)
					return `{tostring(message)}\n{tostring(debug and debug.traceback("", 2) or "")}`
				end)
				if not ok then
					error(`[shim] signal handler errored: {tostring(err)}`, 0)
				end
			end
		end
	end

	function signal:DisconnectAll()
		table.clear(handlers)
	end

	function signal:Count(): number
		return #handlers
	end

	return signal
end

Shim.newSignal = newSignal

-- Instances -----------------------------------------------------------------------

local SUPER = {
	Instance = {},
	Folder = { "Instance" },
	Model = { "Instance" },
	Part = { "Instance" },
	RemoteEvent = { "Instance" },
	Player = { "Instance" },
	BillboardGui = { "Instance" },
	SurfaceGui = { "Instance" },
	TextLabel = { "Instance" },
	UICorner = { "Instance" },
	UIScale = { "Instance" },
	SelectionBox = { "Instance" },
	ScreenGui = { "Instance", "LayerCollector" },
	DataStore = { "Instance" },
	Script = { "Instance" },
	Camera = { "Instance" },
	PlayerGui = { "Instance" },

	Frame = { "Instance" },
	TextButton = { "Instance" },
	ImageLabel = { "Instance" },
}

local Methods = {}
local InstanceMT = {}
local localPlayer: any = nil

local function newInstance(className: string): any
	local self = setmetatable({
		ClassName = className,
		Name = className,
		_parent = nil,
		_children = {},
		_attributes = {},
	}, InstanceMT)
	if className == "RemoteEvent" then
		rawset(self, "OnServerEvent", newSignal("OnServerEvent"))
		rawset(self, "OnClientEvent", newSignal("OnClientEvent"))
	end
	return self
end

local function addChild(parent: any, child: any)
	for _, existing in ipairs(rawget(parent, "_children")) do
		if existing == child then
			return
		end
	end
	table.insert(rawget(parent, "_children"), child)
end

local function removeChild(parent: any, child: any)
	local children = rawget(parent, "_children")
	for index = #children, 1, -1 do
		if children[index] == child then
			table.remove(children, index)
		end
	end
end

local function getParent(self: any)
	return rawget(self, "_parent")
end

local function setParent(self: any, value: any)
	local old = rawget(self, "_parent")
	if old then
		removeChild(old, self)
	end
	rawset(self, "_parent", value)
	if value then
		addChild(value, self)
	end
end

-- Properties the UI reads before anyone sets them.
local DEFAULTS: { [string]: () -> any } = {
	AbsoluteSize = function()
		return Vector2.new(1280, 720)
	end,
	AbsoluteContentSize = function()
		return Vector2.new(0, 0)
	end,
	AbsolutePosition = function()
		return Vector2.new(0, 0)
	end,
	Text = function()
		return ""
	end,
	Visible = function()
		return true
	end,
	Transparency = function()
		return 0
	end,
	BackgroundTransparency = function()
		return 1
	end,
	ZIndex = function()
		return 1
	end,
	LayoutOrder = function()
		return 0
	end,
}

-- Instance events the UI connects to. Created lazily so any instance can have them.
local SIGNAL_PROPERTIES: { [string]: boolean } = {
	Activated = true,
	MouseButton1Click = true,
	MouseEnter = true,
	MouseLeave = true,
	Changed = true,
	ChildAdded = true,
	ChildRemoved = true,
	CharacterAdded = true,
	CharacterRemoving = true,
}

InstanceMT.__index = function(self: any, key: string)
	local method = Methods[key]
	if method then
		return method
	end
	local value = rawget(self, key)
	if value ~= nil then
		return value
	end
	if key == "Parent" then
		return getParent(self)
	end
	if SIGNAL_PROPERTIES[key] then
		local signal = newSignal(`${rawget(self, "Name")}.{key}`)
		rawset(self, key, signal)
		return signal
	end
	local fallback = DEFAULTS[key]
	if fallback then
		return fallback()
	end
	return nil
end

InstanceMT.__newindex = function(self: any, key: string, value: any)
	if key == "Parent" then
		setParent(self, value)
		return
	end
	rawset(self, key, value)
end

function Methods.IsA(self: any, className: string): boolean
	local chain = SUPER[rawget(self, "ClassName")] or {}
	if rawget(self, "ClassName") == className then
		return true
	end
	for _, parentName in ipairs(chain) do
		if parentName == className then
			return true
		end
	end
	return false
end

function Methods.GetChildren(self: any): { any }
	local copy = {}
	for _, child in ipairs(rawget(self, "_children")) do
		table.insert(copy, child)
	end
	return copy
end

function Methods.GetDescendants(self: any): { any }
	local list: { any } = {}
	for _, child in ipairs(rawget(self, "_children")) do
		table.insert(list, child)
		for _, descendant in ipairs(Methods.GetDescendants(child)) do
			table.insert(list, descendant)
		end
	end
	return list
end

function Methods.FindFirstChild(self: any, name: string): any
	for _, child in ipairs(rawget(self, "_children")) do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function Methods.FindFirstChildOfClass(self: any, className: string): any
	for _, child in ipairs(rawget(self, "_children")) do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

function Methods.WaitForChild(self: any, name: string): any
	local existing = Methods.FindFirstChild(self, name)
	if existing then
		return existing
	end
	for _ = 1, 100 do
		task.wait(0.1)
		existing = Methods.FindFirstChild(self, name)
		if existing then
			return existing
		end
	end
	return nil
end

function Methods.Destroy(self: any)
	setParent(self, nil)
	for _, child in ipairs(Methods.GetChildren(self)) do
		Methods.Destroy(child)
	end
	rawset(self, "_children", {})
end

function Methods.Clone(self: any): any
	local copy = newInstance(rawget(self, "ClassName"))
	rawset(copy, "Name", self.Name)
	for key, value in pairs(self) do
		if
			key ~= "_children"
			and key ~= "_parent"
			and key ~= "_attributes"
			and key ~= "ClassName"
		then
			rawset(copy, key, value)
		end
	end
	for _, child in ipairs(rawget(self, "_children")) do
		local childCopy = Methods.Clone(child)
		setParent(childCopy, copy)
	end
	return copy
end

function Methods.SetAttribute(self: any, name: string, value: any)
	rawget(self, "_attributes")[name] = value
end

function Methods.GetAttribute(self: any, name: string): any
	return rawget(self, "_attributes")[name]
end

function Methods.PivotTo(self: any, cframe: any)
	rawset(self, "Pivot", cframe)
end

function Methods.GetPivot(self: any): any
	return rawget(self, "Pivot") or CFrame.new(0, 0, 0)
end

function Methods.Kick(self: any, message: string?)
	rawset(self, "Kicked", message or true)
end

function Methods.FireClient(self: any, player: any, ...: any)
	local sink = rawget(self, "_clientSink")
	if sink then
		sink(player, rawget(self, "Name"), ...)
	end
	local event = rawget(self, "OnClientEvent")
	if event then
		event:Fire(...)
	end
end

function Methods.FireServer(self: any, ...: any)
	-- Roblox prepends the sending player; the harness lets a caller pass one explicitly.
	local args = { n = select("#", ...), ... }
	local first = args[1]
	local sender = if first ~= nil
			and type(first) == "table"
			and rawget(first, "ClassName") == "Player"
		then first
		else localPlayer
	local forwarded =
		table.pack(sender, table.unpack(args, if sender == first then 2 else 1, args.n))
	local event = rawget(self, "OnServerEvent")
	if event then
		event:Fire(table.unpack(forwarded, 1, forwarded.n))
	end
end

function Methods.FireAllClients(self: any, ...: any)
	local sink = rawget(self, "_clientSink")
	if sink then
		sink(nil, rawget(self, "Name"), ...)
	end
end

function Methods.GetPropertyChangedSignal(self: any, _property: string)
	local signals = rawget(self, "_propertySignals")
	if not signals then
		signals = {}
		rawset(self, "_propertySignals", signals)
	end
	local signal = signals[_property]
	if not signal then
		signal = newSignal(`Changed:{_property}`)
		signals[_property] = signal
	end
	return signal
end

function Methods.FindFirstChildWhichIsA(self: any, className: string): any
	for _, descendant in ipairs(Methods.GetDescendants(self)) do
		if Methods.IsA(descendant, className) then
			return descendant
		end
	end
	return nil
end

function Methods.GetPlayers(self: any): { any }
	local players: { any } = {}
	for _, child in ipairs(rawget(self, "_children")) do
		if child.ClassName == "Player" then
			table.insert(players, child)
		end
	end
	return players
end

-- DataStore ---------------------------------------------------------------------

local Store = {}
Store.__index = Store

function Store:GetAsync(key: string): any
	local value = (self._data :: any)[key]
	return value
end

function Store:SetAsync(key: string, value: any)
	(self._data :: any)[key] = value
	self.Writes += 1
end

function Store:UpdateAsync(key: string, transform: (any) -> any): any
	local current = (self._data :: any)[key]
	local updated = transform(current)
	if updated ~= nil then
		(self._data :: any)[key] = updated
	end
	self.Writes += 1
	return updated
end

function Store:RemoveAsync(key: string)
	(self._data :: any)[key] = nil
end

-- Services -----------------------------------------------------------------------

local services: { [string]: any } = {}
local clientMessages: { any } = {}
local observers: { (player: any, channel: string, payload: any) -> () } = {}

local function newService(className: string, name: string): any
	local service = newInstance(className)
	rawset(service, "Name", name)
	return service
end

local players = newService("Players", "Players")
rawset(players, "PlayerAdded", newSignal("PlayerAdded"))
rawset(players, "PlayerRemoving", newSignal("PlayerRemoving"))
services.Players = players

local runService = newService("RunService", "RunService")
rawset(runService, "IsStudio", function()
	return true
end)
rawset(runService, "IsServer", function()
	return true
end)
rawset(runService, "IsClient", function()
	return false
end)
rawset(runService, "Heartbeat", newSignal("Heartbeat"))
rawset(runService, "RenderStepped", newSignal("RenderStepped"))
services.RunService = runService

local dataStoreService = newService("DataStoreService", "DataStoreService")
local stores: { [string]: any } = {}
rawset(dataStoreService, "GetDataStore", function(_self: any, name: string)
	local store = stores[name]
	if not store then
		store = setmetatable({ _data = {}, Writes = 0, Name = name }, Store)
		stores[name] = store
	end
	return store
end)
services.DataStoreService = dataStoreService

local workspace = newService("Workspace", "Workspace")
services.Workspace = workspace

local serverStorage = newService("ServerStorage", "ServerStorage")
services.ServerStorage = serverStorage

local replicatedStorage = newService("ReplicatedStorage", "ReplicatedStorage")
services.ReplicatedStorage = replicatedStorage

local StarterGui = newService("StarterGui", "StarterGui")
services.StarterGui = StarterGui

local UserInputService = newService("UserInputService", "UserInputService")
rawset(UserInputService, "TouchEnabled", false)
rawset(UserInputService, "KeyboardEnabled", true)
rawset(UserInputService, "InputBegan", newSignal("InputBegan"))
services.UserInputService = UserInputService

local gameObject = {
	JobId = "harness-job",
	GetService = function(_self: any, name: string)
		local service = services[name]
		if not service then
			error(`[shim] service "{name}" is not implemented`, 2)
		end
		return service
	end,
	BindToClose = function(_self: any, handler: () -> ())
		Shim.closeHandler = handler
	end,
	Workspace = workspace,
}

local TweenInfoShim = {
	new = function(duration: number?, _style: any?, _direction: any?, repeatCount: number?)
		return { Time = duration or 0, RepeatCount = repeatCount or 0 }
	end,
}

local RandomShim = {
	new = function(_seed: number?)
		return {
			NextNumber = function(_self: any, min: number?, max: number?)
				return if max
					then (min or 0) + math.random() * (max - (min or 0))
					else math.random()
			end,
			NextInteger = function(_self: any, min: number, max: number)
				return math.random(min, max)
			end,
		}
	end,
}

--[[
	Installs the Roblox globals.

	The WASM host makes `_G` itself read-only, and plain `Name = value` assignments would
	write to a *local* of the same name inside this module, so the environment table from
	`getfenv(0)` is written directly instead.
]]
function Shim.install()
	local env: any = getfenv(0)
	env.game = gameObject
	env.Instance = { new = newInstance }
	env.Enum = Enum
	env.Vector2 = Vector2
	env.Vector3 = Vector3
	env.CFrame = CFrame
	env.Color3 = Color3
	env.UDim = UDim
	env.UDim2 = UDim2
	env.Rect = Rect
	env.Random = RandomShim
	env.TweenInfo = TweenInfoShim
	env.RaycastParams = {
		new = function()
			return { FilterType = nil, FilterDescendantsInstances = {} }
		end,
	}
end

-- Harness-facing helpers -------------------------------------------------------

--[[ Installs the client-only services and gives `player` a PlayerGui. ]]
function Shim.installClient(player: any)
	local tweenService = services.TweenService
	if not tweenService then
		tweenService = newService("TweenService", "TweenService")
		rawset(tweenService, "Create", function(_self: any, _instance: any, _info: any, _props: any)
			local tween = { Completed = newSignal("Completed") }
			function tween:Play()
				tween.Playing = true
			end
			function tween:Cancel() end
			function tween:Pause() end
			return tween
		end)
		services.TweenService = tweenService
	end

	local camera = rawget(workspace, "CurrentCamera")
	if not camera then
		camera = newInstance("Camera")
		rawset(camera, "Name", "Camera")
		rawset(camera, "CFrame", CFrame.new(0, 60, 60))
		rawset(camera, "CameraType", Enum.CameraType.Scriptable)
		rawset(camera, "ViewportPointToRay", function(_self: any, _x: number, _y: number)
			return { Origin = Vector3.new(0, 60, 60), Direction = Vector3.new(0, -1, 0) }
		end)
		rawset(workspace, "CurrentCamera", camera)
	end

	local raycastResult: any = nil
	rawset(workspace, "Raycast", function(_self: any, _origin: any, _direction: any, _params: any)
		return raycastResult
	end)
	rawset(workspace, "_setRaycast", function(_self: any, result: any)
		raycastResult = result
	end)

	rawset(players, "LocalPlayer", player)
	localPlayer = player
	local playerGui = newInstance("PlayerGui")
	rawset(playerGui, "Name", "PlayerGui")
	setParent(playerGui, player)
	return playerGui
end

--[[ Points the next client raycast at `instance` (used to simulate a tap). ]]
function Shim.aimAt(instance: any)
	local setter = rawget(workspace, "_setRaycast")
	if setter then
		setter(
			workspace,
			{ Instance = instance, Position = Vector3.new(0, 1, 0), Normal = Vector3.new(0, 1, 0) }
		)
	end
end

function Shim.createPlayer(userId: number, name: string): any
	local player = newInstance("Player")
	rawset(player, "Name", name)
	rawset(player, "UserId", userId)
	rawset(player, "DisplayName", name)
	rawset(player, "CharacterAdded", newSignal("CharacterAdded"))
	setParent(player, players)
	return player
end

function Shim.join(player: any)
	setParent(player, players)
	players.PlayerAdded:Fire(player)
	Shim.advance(1)
end

function Shim.leave(player: any)
	players.PlayerRemoving:Fire(player)
	setParent(player, nil)
end

function Shim.onClientMessage(callback: (player: any, channel: string, payload: any) -> ())
	table.insert(observers, callback)
end

function Shim.setRemoteSink(remote: any)
	rawset(remote, "_clientSink", function(player: any, channel: string, payload: any)
		table.insert(clientMessages, { player = player, channel = channel, payload = payload })
		for _, observer in ipairs(observers) do
			observer(player, channel, payload)
		end
	end)
end

--[[ Records what the server sends to each client. ]]
function Shim.attachSinkToFolder()
	local folder = Methods.FindFirstChild(replicatedStorage, "BillionaireNet")
	if not folder then
		return 0
	end
	local count = 0
	for _, child in ipairs(Methods.GetChildren(folder)) do
		if child.ClassName == "RemoteEvent" then
			Shim.setRemoteSink(child)
			count += 1
		end
	end
	return count
end

function Shim.clientMessages()
	return clientMessages
end

function Shim.stores()
	return stores
end

function Shim.shutdown()
	if Shim.closeHandler then
		Shim.closeHandler()
	end
end

return Shim
