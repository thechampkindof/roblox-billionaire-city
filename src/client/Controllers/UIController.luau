--!strict
--[[
	UI orchestrator.

	Owns the ScreenGui, the HUD, both panels, toasts and the routing between world taps
	and panels. Rebuilds only what the server says changed: the whole panel refreshes on
	patch (cheap — at most 4 times a second) and the HUD on every state change.

	Mobile-first: everything is measured against the viewport and scaled with a UIScale,
	so a phone in portrait still gets 44 px touch targets.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config

local Signal = require(Core.Signal)
local Content = require(Config.Init)
local Balance = Content.Balance
local StateController = require(script.Parent.StateController)
local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local PlotController = require(script.Parent.PlotController)
local Kit = require(script.Parent.Parent.UI.Kit)
local Toasts = require(script.Parent.Parent.UI.Toasts)
local HUD = require(script.Parent.Parent.UI.HUD)
local BuildingPanel = require(script.Parent.Parent.UI.BuildingPanel)
local ParcelPanel = require(script.Parent.Parent.UI.ParcelPanel)
local Remotes = require(Shared.Net.Remotes)

local UIController = {}
UIController.Name = "UIController"

UIController.Toast = Signal.new("UIControllerToast")

local gui: ScreenGui? = nil
local toastLayer: Frame? = nil
local hud: any = nil
local buildingPanel: any = nil
local parcelPanel: any = nil
local ready = false

local function togglePanels(openBuilding: any?, openParcel: any?)
	if openBuilding then
		if parcelPanel then
			parcelPanel.close()
		end
		buildingPanel.open(openBuilding)
		PlotController.HighlightBuilding(openBuilding)
	elseif openParcel then
		if buildingPanel then
			buildingPanel.close()
		end
		PlotController.HighlightBuilding(nil)
		parcelPanel.open(openParcel)
	else
		if buildingPanel then
			buildingPanel.close()
		end
		if parcelPanel then
			parcelPanel.close()
		end
		PlotController.HighlightBuilding(nil)
	end
end

local function refresh()
	local state = StateController.Get()
	if hud then
		hud.refresh(state)
	end
	if buildingPanel then
		buildingPanel.refresh(state)
	end
	if parcelPanel then
		parcelPanel.refresh(state)
	end
end

local function showToast(text: string, kind: string?)
	if toastLayer then
		Toasts.show(toastLayer, text, kind)
	end
end

function UIController.ToastPlayer(text: string, kind: string?)
	showToast(text, kind)
end

function UIController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "BillionaireCityUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 10
	screen.Parent = playerGui
	gui = screen

	toastLayer = Kit.create("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 55,
	}) :: Frame
	toastLayer.Parent = screen

	hud = HUD.create(screen)
	buildingPanel = BuildingPanel.create(screen, screen)
	parcelPanel = ParcelPanel.create(screen, {
		openBuilding = function(uid: string)
			togglePanels(uid, nil)
		end,
		onConstructed = function()
			showToast(Content.strings.toasts.constructionStarted, "info")
		end,
	})

	-- Called when the player dismisses the building panel: clear the selection and the
	-- neighbouring sheet, without re-entering `close()` through `togglePanels`.
	buildingPanel.setOnClose(function()
		if parcelPanel then
			parcelPanel.close()
		end
		PlotController.HighlightBuilding(nil)
	end)

	hud.setHandlers({
		onCollect = function()
			StateController.Send("IncomeCollect", { buildingUid = "all" })
		end,
		onZoomIn = function()
			CameraController.ZoomIn()
		end,
		onZoomOut = function()
			CameraController.ZoomOut()
		end,
	})

	InputController.BuildingTapped:Connect(function(uid: string)
		if buildingPanel.isOpen() and buildingPanel.uid() == uid then
			return
		end
		togglePanels(uid, nil)
	end)

	InputController.ParcelTapped:Connect(function(parcelId: string)
		if buildingPanel.isOpen() or parcelPanel.isOpen() then
			return
		end
		togglePanels(nil, parcelId)
	end)

	StateController.Changed:Connect(function()
		if ready then
			refresh()
		end
	end)

	StateController.Ready:Connect(function()
		ready = true
		refresh()
	end)

	Remotes.toast().OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" then
			showToast(tostring(payload.text or ""), payload.kind)
		end
	end)

	Remotes.notice().OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "offlineIncome" then
			showToast(
				string.format(Content.strings.toasts.offlineIncome, tostring(payload.text or "")),
				"reward"
			)
		elseif payload.text then
			showToast(tostring(payload.text), payload.kind)
		end
	end)

	-- Keep the GUI honest across orientation changes and small screens.
	local function rescale()
		local viewport = screen.AbsoluteSize
		local scale = 1
		if viewport.X < 720 then
			scale = math.clamp(viewport.X / 720, 0.72, 1) * Balance.UI.mobileScale
		end
		for _, target in ipairs({ hud.frame, buildingPanel.frame, parcelPanel.frame }) do
			local existing = target:FindFirstChildOfClass("UIScale")
			if not existing then
				existing = Instance.new("UIScale")
				existing.Parent = target
			end
			existing.Scale = scale
		end
	end

	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()

	-- Escape / a back gesture closes panels.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if
			input.KeyCode == Enum.KeyCode.Escape
			and (buildingPanel.isOpen() or parcelPanel.isOpen())
		then
			togglePanels(nil, nil)
		end
	end)
end

return UIController
