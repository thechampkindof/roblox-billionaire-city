--!strict
--[[
	Parcel sheet: buy land, or pick which building to construct on land you own.

	Shows every legal building that fits the parcel, with cost, build time and expected
	net income, so the player can compare before spending (GDD §A20).
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config
local Util = Shared.Util

local NumberFormat = require(Core.NumberFormat)
local Content = require(Config.Init)
local Balance = Content.Balance
local BuildingMath = require(Util.BuildingMath)
local Kit = require(script.Parent.Kit)
local StateController = require(script.Parent.Parent.Controllers.StateController)

local ParcelPanel = {}

export type Panel = {
	open: (parcelId: string) -> (),
	close: () -> (),
	refresh: (state: any) -> (),
	isOpen: () -> boolean,
	parcelId: () -> string?,
}

export type Callbacks = {
	openBuilding: ((uid: string) -> ())?,
	onConstructed: (() -> ())?,
}

function ParcelPanel.create(gui: ScreenGui, callbacks: Callbacks?): Panel
	local hooks = callbacks or {}
	local scrim = Kit.scrim(gui)
	local frame = Kit.card({
		Name = "ParcelPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 500, 0, 430),
		Visible = false,
		ZIndex = 30,
	}, Kit.PALETTE.gold)
	frame.Parent = gui

	local scale = Kit.create("UIScale", { Scale = 1 })
	scale.Parent = frame

	local title = Kit.label("Parcel", UDim2.new(1, -120, 0, 26), {
		Position = UDim2.new(0, 16, 0, 12),
		Font = Enum.Font.GothamBold,
		TextSize = 19,
	})
	title.Parent = frame

	local subtitle = Kit.label("", UDim2.new(1, -140, 0, 20), {
		Position = UDim2.new(0, 16, 0, 40),
		TextColor3 = Kit.PALETTE.textDim,
		TextSize = 13,
	})
	subtitle.Parent = frame

	local closeButton = Kit.button("Close", function() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 92, 0, 40),
		BackgroundColor3 = Kit.PALETTE.surfaceHigh,
	})
	closeButton.Parent = frame

	local body = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 72),
		Size = UDim2.new(1, -24, 1, -84),
	}) :: Frame
	body.Parent = frame

	local scroll, list = Kit.scrollList(body)
	local currentParcel: string? = nil

	local function addRow(
		nameText: string,
		detail: string,
		actionText: string?,
		action: (() -> ())?,
		affordable: boolean
	)
		local row = Kit.card({ Size = UDim2.new(1, 0, 0, 68) })
		local name = Kit.label(nameText, UDim2.new(1, -170, 0, 20), {
			Position = UDim2.new(0, 10, 0, 8),
			Font = Enum.Font.GothamBold,
			TextSize = 15,
		})
		name.Parent = row
		local detailLabel = Kit.label(detail, UDim2.new(1, -170, 0, 32), {
			Position = UDim2.new(0, 10, 0, 28),
			TextColor3 = Kit.PALETTE.textDim,
			TextSize = 12,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		detailLabel.Parent = row
		if actionText and action then
			local button = Kit.button(actionText, action, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.new(0, 145, 0, 42),
				TextSize = 13,
				BackgroundColor3 = if affordable
					then Kit.PALETTE.accentDark
					else Kit.PALETTE.surfaceHigh,
			})
			button.Parent = row
		end
		row.Parent = list
	end

	function ParcelPanel.render()
		Kit.clearChildren(list)
		local parcelId = currentParcel
		if not parcelId then
			return
		end
		local state = StateController.Get()
		local parcel = Content.parcelById[parcelId]
		if not parcel then
			return
		end
		local owned = state.parcels and state.parcels.owned and state.parcels.owned[parcelId]
		local cash = state.currency and state.currency.cash or 0

		title.Text = `Parcel {parcel.id}`
		subtitle.Text = `{parcel.district} District · size {parcel.size}`

		if not owned then
			local price = state.parcels and state.parcels.prices and state.parcels.prices[parcelId]
				or parcel.landCost
			local requirements = ""
			for _, requirement in ipairs(parcel.requires) do
				if requirement.kind == "NetWorth" then
					requirements = ` · requires net worth {NumberFormat.money(requirement.min)}`
				end
			end
			addRow(
				"Buy this parcel",
				`{NumberFormat.money(price)} · land is yours forever{requirements}`,
				NumberFormat.money(price),
				function()
					StateController.Send("ParcelPurchase", { parcelId = parcelId })
				end,
				cash >= price
			)
			addRow(
				"Why buy land?",
				"Every parcel holds one building. More parcels means more income lines and district development."
			)
			return
		end

		if state.parcels and state.parcels.owned then
			for uid, row in StateController.Buildings() do
				if row.parcel == parcelId then
					addRow(
						`{row.name} — already built`,
						`Level {row.level} · {NumberFormat.money(
							row.income and row.income.net or 0
						)}/min`,
						"Manage",
						function()
							if hooks.openBuilding then
								hooks.openBuilding(uid)
							end
						end,
						true
					)
					return
				end
			end
		end

		local candidates = Content.buildingsForParcel(parcel)
		if #candidates == 0 then
			addRow(
				"Nothing fits here",
				"This parcel is reserved for larger projects in a later phase."
			)
			return
		end

		for _, def in ipairs(candidates) do
			local cost = Content.totalBuildCost(def)
			local probe = {
				def = def.id,
				parcel = parcelId,
				level = 1,
				phase = #def.phases,
				upg = {},
				mastery = { xp = 0, lvl = 1, windowStart = 0, windowXp = 0 },
				staff = {},
				manager = nil,
				constructing = nil,
				pending = 0,
				lastAccrual = 0,
			}
			local net = BuildingMath.income(def, probe).netPerMin
			addRow(
				`Build {def.name}`,
				string.format(
					"%s · %s net/min · %s build time",
					NumberFormat.money(cost),
					NumberFormat.money(net),
					NumberFormat.duration(def.buildSeconds)
				),
				NumberFormat.money(cost),
				function()
					StateController.Send(
						"ConstructStart",
						{ parcelId = parcelId, buildingId = def.id }
					)
					if hooks.onConstructed then
						hooks.onConstructed()
					end
				end,
				cash >= cost
			)
		end
	end

	local panel: any = {
		frame = frame,
		open = function(parcelId: string)
			currentParcel = parcelId
			frame.Visible = true
			scrim.Visible = true
			ParcelPanel.render()
		end,
		close = function()
			currentParcel = nil
			frame.Visible = false
			scrim.Visible = false
		end,
		refresh = function()
			if frame.Visible then
				ParcelPanel.render()
			end
		end,
		isOpen = function()
			return frame.Visible == true
		end,
		parcelId = function()
			return currentParcel
		end,
	}

	closeButton.Activated:Connect(panel.close)
	scrim.Activated:Connect(panel.close)

	local viewport = gui.AbsoluteSize
	scale.Scale = math.clamp(math.min(viewport.X / 560, viewport.Y / 520), 0.55, 1)

	return panel
end

return ParcelPanel
