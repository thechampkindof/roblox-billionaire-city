--!strict
--[[
	Plot visuals on the client.

	The server owns all geometry (pads + building models). The client only:
	  * frames the camera on the player's plot once it is known,
	  * draws a highlight on whatever is selected,
	  * floats a small "collect" bubble over buildings holding uncollected income.

	No part is created here except the highlight and billboards, which are local-only.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core

local NumberFormat = require(Core.NumberFormat)
local StateController = require(script.Parent.StateController)
local CameraController = require(script.Parent.CameraController)

local PlotController = {}
PlotController.Name = "PlotController"

local selection: SelectionBox? = nil
local bubbles: { [string]: BillboardGui } = {}
local focusedPlot = false

--[[ The server owns the world: `Workspace.BillionaireCity/Plot_<userId>/<building>`. ]]
local function cityRoot(): Instance?
	return Workspace:FindFirstChild("BillionaireCity")
end

local function findModel(uid: string): Model?
	local root = cityRoot()
	if not root then
		return nil
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute("BuildingUid") == uid then
			return descendant
		end
	end
	return nil
end

function PlotController.FocusPlot()
	if focusedPlot then
		return
	end
	local plot = StateController.Get().plot
	if not plot or not plot.origin then
		return
	end
	focusedPlot = true
	CameraController.Focus(Vector3.new(plot.origin[1], plot.origin[2], plot.origin[3]))
end

function PlotController.HighlightBuilding(uid: string?)
	if selection then
		selection:Destroy()
		selection = nil
	end
	if not uid then
		return
	end
	local model = findModel(uid)
	local primary = model and model.PrimaryPart
	if not model or not primary then
		return
	end
	local box = Instance.new("SelectionBox")
	box.Name = "Selected"
	box.Adornee = model
	box.LineThickness = 0.06
	box.Color3 = Color3.fromRGB(96, 216, 132)
	box.SurfaceTransparency = 1
	box.Parent = model
	selection = box
end

--[[ A small floating label above buildings with uncollected income. ]]
local function updateBubbles(state: any)
	local seen: { [string]: boolean } = {}
	for uid, row in pairs(state.buildings or {}) do
		local pending = row.pending or 0
		if pending >= 1 and row.operational then
			seen[uid] = true
			local bubble = bubbles[uid]
			if not bubble then
				local model = findModel(uid)
				local part = model
					and (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart"))
				if not part then
					continue
				end
				local gui = Instance.new("BillboardGui")
				gui.Name = `Pending-{uid}`
				gui.Adornee = part
				gui.Size = UDim2.fromOffset(140, 34)
				gui.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
				gui.AlwaysOnTop = true
				gui.MaxDistance = 220
				local label = Instance.new("TextLabel")
				label.Name = "Amount"
				label.BackgroundColor3 = Color3.fromRGB(26, 29, 37)
				label.BackgroundTransparency = 0.15
				label.BorderSizePixel = 0
				label.Size = UDim2.fromScale(1, 1)
				label.Font = Enum.Font.GothamBold
				label.TextColor3 = Color3.fromRGB(248, 208, 96)
				label.TextScaled = true
				label.Text = `+{NumberFormat.money(pending)}`
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 10)
				corner.Parent = label
				label.Parent = gui
				gui.Parent = part
				bubble = gui
				bubbles[uid] = gui
			end
			local label = bubble:FindFirstChild("Amount")
			if label and label:IsA("TextLabel") then
				label.Text = `+{NumberFormat.money(pending)}`
			end
		end
	end
	for uid, bubble in pairs(bubbles) do
		if not seen[uid] then
			bubble:Destroy()
			bubbles[uid] = nil
		end
	end
end

function PlotController.Start()
	StateController.Changed:Connect(function()
		PlotController.FocusPlot()
		updateBubbles(StateController.Get())
	end)

	StateController.Ready:Connect(function()
		PlotController.FocusPlot()
	end)

	Players.LocalPlayer.CharacterAdded:Connect(function()
		focusedPlot = false
		task.delay(0.5, PlotController.FocusPlot)
	end)
end

function PlotController.Stop()
	if selection then
		selection:Destroy()
		selection = nil
	end
	for uid, bubble in pairs(bubbles) do
		bubble:Destroy()
		bubbles[uid] = nil
	end
end

return PlotController
