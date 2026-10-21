--!strict
--[[
	Headless boot + interaction test for the client.

	Boots the server (so remotes and world geometry exist), installs a fake LocalPlayer,
	runs `src/client`, pushes a real snapshot across the wire, then simulates taps on the
	parcel and the building and switches every building-panel tab. This exercises the UI
	construction code that a Studio playtest would otherwise be the only test of.
]]

local Shim = require(script.Parent.Shim)

Shim.install()

local root = script.Parent.Parent.Parent
game:GetService("ReplicatedStorage").Shared = root.src.shared
require(root.src.server)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local Remotes = require(root.src.shared.Net.Remotes)

local ClientSim = {}

local results: { { label: string, ok: boolean, detail: string? } } = {}

local function check(label: string, ok: boolean, detail: string?): boolean
	table.insert(results, { label = label, ok = ok, detail = detail })
	local mark = if ok then "  PASS  " else "  FAIL  "
	print(`{mark}{label}{if detail then " — " .. detail else ""}`)
	return ok
end

local function descendantsWithText(instance: any, text: string): { any }
	local matches: { any } = {}
	for _, descendant in ipairs(instance:GetDescendants()) do
		local className = descendant.ClassName
		if (className == "TextButton" or className == "TextLabel") and descendant.Text == text then
			table.insert(matches, descendant)
		end
	end
	return matches
end

local function tap(instance: any)
	Shim.aimAt(instance)
	local input = {
		UserInputType = Enum.UserInputType.MouseButton1,
		Position = Vector2.new(400, 300),
	}
	UserInputService.InputBegan:Fire(input, false)
	Shim.advance(0.5)
end

function ClientSim.run()
	local ok, err = pcall(ClientSim.play)
	if not ok then
		check("the client simulation ran to completion", false, tostring(err))
	end
	return ClientSim.summary()
end

function ClientSim.play()
	-- A local player with a PlayerGui.
	local localPlayer = Shim.createPlayer(2001, "ClientHarness")
	local playerGui = Shim.installClient(localPlayer)

	-- Boot the client bundle exactly like StarterPlayerScripts does.
	require(root.src.client)
	Shim.advance(0.5)

	local screen = playerGui:FindFirstChild("BillionaireCityUI")
	check("the client builds its ScreenGui", screen ~= nil)
	if not screen then
		return
	end

	-- Join: the server sends a snapshot, the client mirrors it.
	Shim.join(localPlayer)
	Shim.advance(2)

	local StateController = require(root.src.client.Controllers.StateController)
	check("the client receives state", StateController.IsReady())
	local state = StateController.Get()
	check(
		"the snapshot carries currency",
		state.currency ~= nil and state.currency.cash > 0,
		`${state.currency and state.currency.cash}`
	)
	check("the snapshot carries the plot", state.plot ~= nil)
	check("the snapshot carries the building", next(state.buildings or {}) ~= nil)

	local hud = screen:FindFirstChild("HUD")
	check("the HUD exists", hud ~= nil)

	-- Tap the starter parcel: the parcel sheet should open.
	local city = Workspace:FindFirstChild("BillionaireCity")
	check("the server built the city folder", city ~= nil)

	local parcelPart: any = nil
	local buildingModel: any = nil
	if city then
		for _, descendant in ipairs(city:GetDescendants()) do
			local parcelId = descendant:GetAttribute("ParcelId")
			local buildingUid = descendant:GetAttribute("BuildingUid")
			if parcelId == "starter_01" and descendant.ClassName == "Part" and not parcelPart then
				parcelPart = descendant
			end
			if buildingUid and descendant.ClassName == "Model" and not buildingModel then
				buildingModel = descendant
			end
		end
	end
	check("the plot has parcel pads", parcelPart ~= nil)
	check("the plot has a building model", buildingModel ~= nil)

	if parcelPart then
		tap(parcelPart)
		local parcelPanel = screen:FindFirstChild("ParcelPanel")
		check(
			"tapping a parcel opens the parcel sheet",
			parcelPanel ~= nil and parcelPanel.Visible == true
		)
	end

	if buildingModel then
		tap(buildingModel)
		local buildingPanel = screen:FindFirstChild("BuildingPanel")
		check(
			"tapping a building opens the building panel",
			buildingPanel ~= nil and buildingPanel.Visible == true
		)
		check(
			"the building panel closes the parcel sheet",
			screen:FindFirstChild("ParcelPanel").Visible == false
		)

		-- Every tab renders without error; the tab buttons are the only way in.
		for _, tab in ipairs({
			"Overview",
			"Upgrades",
			"Staff",
			"Income",
			"Construction",
			"Mastery",
			"Customize",
		}) do
			local buttons = descendantsWithText(buildingPanel, tab)
			if #buttons == 0 then
				check(`the "{tab}" tab has a button`, false)
			else
				local fired = pcall(function()
					buttons[1].Activated:Fire()
				end)
				check(`the "{tab}" tab renders`, fired)
				Shim.advance(0.1)
			end
		end
		check(
			"the customization tab says the feature is coming later",
			#descendantsWithText(buildingPanel, "Coming in a later update.") > 0
		)
	end

	-- Collect-all from the HUD, through the real intent path.
	local collectButton: any = nil
	if hud then
		for _, descendant in ipairs(hud:GetDescendants()) do
			if descendant.ClassName == "TextButton" and string.find(descendant.Text, "Collect") then
				collectButton = descendant
			end
		end
	end
	check("the HUD has a collect button", collectButton ~= nil)
	if collectButton then
		Shim.advance(30)
		local before = StateController.Get().currency.cash
		collectButton.Activated:Fire()
		Shim.advance(2)
		check(
			"collecting from the HUD raises cash",
			StateController.Get().currency.cash > before,
			`${before} -> ${StateController.Get().currency.cash}`
		)
	end

	-- A toast from the server reaches the toast layer.
	Remotes.toast():FireClient(localPlayer, { text = "Harness toast", kind = "info" })
	Shim.advance(0.2)
	local toastCount = 0
	for _, descendant in ipairs(screen:GetDescendants()) do
		if descendant.ClassName == "TextLabel" and descendant.Text == "Harness toast" then
			toastCount += 1
		end
	end
	check("server toasts render", toastCount == 1)
end

function ClientSim.summary(): { passed: number, failed: number }
	local passed = 0
	for _, result in ipairs(results) do
		if result.ok then
			passed += 1
		end
	end
	return { passed = passed, failed = #results - passed }
end

return ClientSim
