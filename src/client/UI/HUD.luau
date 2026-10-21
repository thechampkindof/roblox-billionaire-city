--!strict
--[[
	Heads-up display: cash, net worth, income per minute, completion, the objective
	card, a collect-all button and camera zoom controls.

	Deliberately short on chrome: four stats, one objective, two buttons. Everything else
	lives behind a tap on the world (parcel or building panel).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config

local NumberFormat = require(Core.NumberFormat)
local Content = require(Config.Init)
local Kit = require(script.Parent.Kit)

local HUD = {}

export type Hud = {
	frame: Frame,
	refresh: (state: any) -> (),
	setHandlers: (handlers: { onCollect: () -> (), onZoomIn: () -> (), onZoomOut: () -> () }) -> (),
}

function HUD.create(parent: Instance): Hud
	local root = Kit.create("Frame", {
		Name = "HUD",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}) :: Frame
	root.Parent = parent

	-- Top bar -----------------------------------------------------------------
	local top = Kit.create("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(1, -24, 0, 56),
	}) :: Frame
	local topLayout = Kit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) :: UIListLayout
	topLayout.Parent = top
	top.Parent = root

	local cashFrame, setCash = Kit.statChip("CASH", "$0", 132)
	cashFrame.Parent = top
	local worthFrame, setWorth = Kit.statChip("NET WORTH", "$0", 150)
	worthFrame.Parent = top
	local incomeFrame, setIncome = Kit.statChip("PER MIN", "$0", 132)
	incomeFrame.Parent = top
	local completionFrame, setCompletion = Kit.statChip("CITY", "0%", 110)
	completionFrame.Parent = top

	-- Objective card ----------------------------------------------------------
	local objective = Kit.card({
		Name = "Objective",
		Position = UDim2.new(0, 12, 0, 76),
		Size = UDim2.new(0, 330, 0, 96),
	}, Kit.PALETTE.stroke)
	objective.Parent = root

	local objectiveTitle = Kit.label("Objective", UDim2.new(1, -20, 0, 20), {
		Position = UDim2.new(0, 10, 0, 8),
		Font = Enum.Font.GothamBold,
		TextColor3 = Kit.PALETTE.gold,
		TextSize = 15,
	})
	objectiveTitle.Parent = objective

	local objectiveDesc = Kit.label("", UDim2.new(1, -20, 0, 34), {
		Position = UDim2.new(0, 10, 0, 28),
		TextColor3 = Kit.PALETTE.textDim,
		TextSize = 13,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	objectiveDesc.Parent = objective

	local barTrack, setBar = Kit.progressBar(8)
	barTrack.Position = UDim2.new(0, 10, 0, 64)
	barTrack.Size = UDim2.new(1, -20, 0, 8)
	barTrack.Parent = objective

	local objectiveProgress = Kit.label("", UDim2.new(1, -20, 0, 16), {
		Position = UDim2.new(0, 10, 0, 74),
		TextColor3 = Kit.PALETTE.textDim,
		TextSize = 12,
	})
	objectiveProgress.Parent = objective

	-- Bottom actions ----------------------------------------------------------
	local actions = Kit.create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -16),
		Size = UDim2.new(0, 320, 0, 52),
	}) :: Frame
	local actionLayout = Kit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) :: UIListLayout
	actionLayout.Parent = actions
	actions.Parent = root

	local collectButton = Kit.button("Collect", function() end, {
		Size = UDim2.new(0, 200, 0, 48),
		BackgroundColor3 = Kit.PALETTE.accentDark,
		TextSize = 17,
	})
	collectButton.Parent = actions

	local zoomHeld = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 108, 0, 48),
	}) :: Frame
	local zoomLayout = Kit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
	})
	zoomLayout.Parent = zoomHeld
	local zoomOut = Kit.button(
		"-",
		function() end,
		{ Size = UDim2.new(0, 50, 0, 48), BackgroundColor3 = Kit.PALETTE.surfaceHigh }
	)
	zoomOut.Parent = zoomHeld
	local zoomIn = Kit.button(
		"+",
		function() end,
		{ Size = UDim2.new(0, 50, 0, 48), BackgroundColor3 = Kit.PALETTE.surfaceHigh }
	)
	zoomIn.Parent = zoomHeld
	zoomHeld.Parent = actions

	-- Hint --------------------------------------------------------------------
	local hint = Kit.label(
		"Tap a parcel to buy or build · tap a building to manage it",
		UDim2.new(1, -24, 0, 18),
		{
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 12, 1, -72),
			TextColor3 = Kit.PALETTE.textDim,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
		}
	)
	hint.Parent = root

	local handlers = {
		onCollect = function() end,
		onZoomIn = function() end,
		onZoomOut = function() end,
	}

	collectButton.Activated:Connect(function()
		handlers.onCollect()
	end)
	zoomIn.Activated:Connect(function()
		handlers.onZoomIn()
	end)
	zoomOut.Activated:Connect(function()
		handlers.onZoomOut()
	end)

	local function refresh(state: any)
		local currency = state.currency
		if not currency then
			return
		end
		setCash(NumberFormat.money(currency.cash or 0))
		setWorth(NumberFormat.money(currency.netWorth or 0))
		setIncome(`{NumberFormat.money(currency.netPerMin or 0)}/m`)
		setCompletion(`{string.format("%.0f", currency.completion or 0)}%`)

		local pending = 0
		for _, building in state.buildings or {} do
			pending += building.pending or 0
		end
		if pending > 0 then
			collectButton.Text = `Collect {NumberFormat.money(pending)}`
			collectButton.BackgroundColor3 = Kit.PALETTE.accentDark
		else
			collectButton.Text = "Collect"
			collectButton.BackgroundColor3 = Kit.PALETTE.surfaceHigh
		end

		local objectiveState = state.objective
		if objectiveState then
			objectiveTitle.Text = objectiveState.title
			objectiveDesc.Text = objectiveState.description
			setBar(objectiveState.fraction or 0, Kit.PALETTE.gold)
			objectiveProgress.Text = string.format(
				"%s / %s   ·   reward %s",
				NumberFormat.full(objectiveState.current or 0),
				NumberFormat.full(objectiveState.target or 0),
				NumberFormat.money(objectiveState.rewardCash or 0)
			)
			objective.Visible = true
		else
			objective.Visible = true
			objectiveTitle.Text = "Starter District"
			objectiveDesc.Text = "Onboarding complete — grow your city, district by district."
			setBar(1, Kit.PALETTE.accent)
			objectiveProgress.Text = `Phases 2–8 arrive in later updates`
		end
	end

	return {
		frame = root,
		refresh = refresh,
		setHandlers = function(newHandlers)
			handlers = newHandlers
		end,
	}
end

return HUD
