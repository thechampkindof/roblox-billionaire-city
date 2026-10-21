--!strict
--[[
	Plot assignment and teardown.

	One plot per player, arranged around a shared hub. A plot owns:
	  * its base platform and road strip,
	  * one marker part per Starter parcel (no models for empty land),
	  * a folder that is destroyed when the player leaves.

	Ownership rule: this service owns plot geometry. Buildings are created by
	`BuildingService`, which listens to `PlotAssigned`; parcels are painted by
	`ParcelService` through `PlotService.Refresh`.
]]

local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config

local Signal = require(Core.Signal)
local Maid = require(Core.Maid)
local Content = require(Config.Init)
local Balance = Content.Balance
local Parcels = require(Config.Parcels)

local DataService = require(script.Parent.DataService)

local PlotService = {}
PlotService.Name = "PlotService"
PlotService.Dependencies = { "DataService" }

PlotService.PlotAssigned = Signal.new("PlotAssigned")
PlotService.PlotReleased = Signal.new("PlotReleased")

export type Plot = {
	player: Player,
	slot: number,
	origin: Vector3,
	folder: Folder,
	pads: { [string]: BasePart },
	maid: Maid.Maid,
}

local plots: { [Player]: Plot } = {}
local claimedSlots: { [number]: boolean } = {}
local hub: Model? = nil
local worldRoot: Folder? = nil

local PAD_SIZE = Balance.World.parcelStuds
local PITCH = Balance.World.parcelStuds + Balance.World.parcelGapStuds + 6

local function slotOrigin(slot: number): Vector3
	local count = Balance.World.maxPlots
	local angle = ((slot - 1) / count) * math.pi * 2
	return Vector3.new(
		math.cos(angle) * Balance.World.plotSpacing,
		0,
		math.sin(angle) * Balance.World.plotSpacing
	)
end

local function firstFreeSlot(): number
	for slot = 1, Balance.World.maxPlots do
		if not claimedSlots[slot] then
			return slot
		end
	end
	return -1
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = size
	part.Position = position
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[ Builds the shared plaza once per server. ]]
local function buildHub(): Model
	local existing = Workspace:FindFirstChild("BillionaireHub")
	if existing and existing:IsA("Model") then
		return existing
	end
	local model = Instance.new("Model")
	model.Name = "BillionaireHub"

	local plaza = makePart(
		model,
		"Plaza",
		Vector3.new(120, 1, 120),
		Vector3.new(0, 0, 0),
		Color3.fromRGB(210, 208, 200)
	)
	plaza.Material = Enum.Material.Concrete

	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2
		local bench = makePart(
			model,
			`Bench{index}`,
			Vector3.new(10, 2, 4),
			Vector3.new(math.cos(angle) * 34, 1.5, math.sin(angle) * 34),
			Color3.fromRGB(120, 90, 60)
		)
		bench.Material = Enum.Material.Wood
	end

	local statue = makePart(
		model,
		"Monument",
		Vector3.new(10, 24, 10),
		Vector3.new(0, 12, 0),
		Color3.fromRGB(240, 205, 90)
	)
	statue.Material = Enum.Material.Metal

	local whole = makePart(
		model,
		"Sign",
		Vector3.new(46, 8, 1),
		Vector3.new(0, 6, -40),
		Color3.fromRGB(40, 44, 52)
	)
	whole.Material = Enum.Material.Metal
	local label = Instance.new("SurfaceGui")
	label.Face = Enum.NormalId.Front
	label.Parent = whole
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextScaled = true
	text.Text = "BILLIONAIRE CITY"
	text.Parent = label

	model.Parent = Workspace
	return model
end

local function paintPads(plot: Plot, profile: any)
	for parcelId, pad in plot.pads do
		local def = Content.parcelById[parcelId]
		local owned = profile.Parcels[parcelId] == true
		local occupied = false
		for _, state in profile.Buildings do
			if state.parcel == parcelId then
				occupied = true
				break
			end
		end

		if occupied then
			pad.Color = Color3.fromRGB(70, 74, 82)
		elseif owned then
			pad.Color = Color3.fromRGB(94, 148, 96)
		else
			pad.Color = Color3.fromRGB(130, 132, 138)
		end
		pad.Transparency = if occupied then 0.35 else 0.15
		pad:SetAttribute("Owned", owned)
		pad:SetAttribute("Occupied", occupied)
		pad:SetAttribute("Price", if def then Parcels.priceFor(def, plotCount(profile)) else 0)

		local billboard = pad:FindFirstChildOfClass("BillboardGui")
		if billboard then
			local label = billboard:FindFirstChildOfClass("TextLabel")
			if label then
				if occupied then
					label.Text = ""
				elseif owned then
					label.Text = "Build here"
					label.TextColor3 = Color3.fromRGB(190, 255, 200)
				else
					local def2 = Content.parcelById[parcelId]
					local price = if def2 then Parcels.priceFor(def2, plotCount(profile)) else 0
					label.Text = `Buy  ${price}`
					label.TextColor3 = Color3.fromRGB(255, 240, 210)
				end
			end
		end
	end
end

function plotCount(profile: any): number
	local count = 0
	for _ in profile.Parcels do
		count += 1
	end
	return count
end

PlotService.ParcelCount = plotCount

local function assign(player: Player)
	local slot = firstFreeSlot()
	if slot < 0 then
		player:Kick("All city plots are taken. Please rejoin.")
		return
	end
	claimedSlots[slot] = true

	local origin = slotOrigin(slot)
	local maid = Maid.new()
	local folder = Instance.new("Folder")
	folder.Name = `Plot_{player.UserId}`

	local platform = makePart(
		folder,
		"Platform",
		Vector3.new(4 * PITCH + 16, 1, 4 * PITCH + 16),
		origin + Vector3.new(0, -0.5, 0),
		Color3.fromRGB(74, 86, 92)
	)
	platform.Material = Enum.Material.Concrete
	platform:SetAttribute("IsPlotPlatform", true)

	local pads: { [string]: BasePart } = {}
	for _, parcelDef in ipairs(Parcels.list) do
		local x = origin.X + (parcelDef.column - 2.5) * PITCH
		local z = origin.Z + (parcelDef.row - 2.5) * PITCH
		local pad = makePart(
			folder,
			parcelDef.id,
			Vector3.new(PAD_SIZE, 1, PAD_SIZE),
			Vector3.new(x, 0.5, z),
			Color3.fromRGB(130, 132, 138)
		)
		pad.Material = Enum.Material.Grass
		pad:SetAttribute("ParcelId", parcelDef.id)
		pad:SetAttribute("District", parcelDef.district)

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.AlwaysOnTop = false
		billboard.Size = UDim2.fromOffset(220, 56)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
		billboard.MaxDistance = 400
		billboard.Parent = pad

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.35
		label.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
		label.TextColor3 = Color3.fromRGB(235, 238, 244)
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.Text = ""
		label.Parent = billboard

		pads[parcelDef.id] = pad
		maid:Add(pad)
	end

	maid:Add(folder)
	folder.Parent = worldRoot or Workspace

	local plot: Plot = {
		player = player,
		slot = slot,
		origin = origin,
		folder = folder,
		pads = pads,
		maid = maid,
	}
	plots[player] = plot

	local profile = DataService.Get(player)
	if profile then
		paintPads(plot, profile)
	end

	PlotService.PlotAssigned:Fire(player, plot)
end

local function release(player: Player)
	local plot = plots[player]
	if not plot then
		return
	end
	claimedSlots[plot.slot] = false
	plots[player] = nil
	PlotService.PlotReleased:Fire(player, plot)
	plot.maid:Destroy()
end

function PlotService.Init(registry: any)
	worldRoot = Workspace:FindFirstChild("BillionaireCity") :: Folder?
	if not worldRoot then
		local folder = Instance.new("Folder")
		folder.Name = "BillionaireCity"
		folder.Parent = Workspace
		worldRoot = folder
	end

	DataService.ProfileLoaded:Connect(function(player: Player)
		assign(player)
	end)
	DataService.ProfileReleasing:Connect(function(player: Player)
		release(player)
	end)
end

function PlotService.Start()
	hub = buildHub()
	hub.Name = "BillionaireHub"
end

function PlotService.Get(player: Player): Plot?
	return plots[player]
end

--[[ Repaints one player's parcels from their profile. ]]
function PlotService.Refresh(player: Player)
	local plot = plots[player]
	local profile = DataService.Get(player)
	if plot and profile then
		paintPads(plot, profile)
	end
end

--[[ World position of a parcel's centre. ]]
function PlotService.ParcelPosition(player: Player, parcelId: string): Vector3?
	local plot = plots[player]
	if not plot then
		return nil
	end
	local pad = plot.pads[parcelId]
	if not pad then
		return nil
	end
	return pad.Position + Vector3.new(0, 0.5, 0)
end

--[[ Slot origin, used by the client camera. ]]
function PlotService.OriginOf(player: Player): Vector3?
	local plot = plots[player]
	return if plot then plot.origin else nil
end

return PlotService
