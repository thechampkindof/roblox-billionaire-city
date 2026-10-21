--!strict
--[[
	Building Panel: the main management surface.

	Tabs and status:
	  Overview        live summary + level-up purchase
	  Upgrades        every generated line, grouped by the six categories
	  Staff           worker slots, grades and the manager (functional — the onboarding
	                  chain requires hiring)
	  Income & Expenses  revenue, wages, supplies, net, payback of the next purchase
	  Construction    phase progress + rush (read/act)
	  Mastery         level, XP bar, next milestone
	  Customization   stubbed with the real layout

	Every row shows cost, effect and current level *before* purchase, per GDD §A20.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config
local Util = Shared.Util

local NumberFormat = require(Core.NumberFormat)
local Mastery = require(Core.Mastery)
local Content = require(Config.Init)
local Balance = Content.Balance
local BuildingMath = require(Util.BuildingMath)
local Kit = require(script.Parent.Kit)
local StateController = require(script.Parent.Parent.Controllers.StateController)

local BuildingPanel = {}

export type Panel = {
	frame: Frame,
	open: (uid: string) -> (),
	close: () -> (),
	refresh: (state: any) -> (),
	isOpen: () -> boolean,
	uid: () -> string?,
}

local TABS = {
	{ id = "overview", label = "Overview" },
	{ id = "upgrades", label = "Upgrades" },
	{ id = "staff", label = "Staff" },
	{ id = "income", label = "Income" },
	{ id = "construction", label = "Construction" },
	{ id = "mastery", label = "Mastery" },
	{ id = "custom", label = "Customize" },
}

function BuildingPanel.create(
	parent: Instance,
	gui: ScreenGui,
	onNotify: (text: string, kind: string) -> ()
): Panel
	local scrim = Kit.scrim(gui)
	local frame = Kit.card({
		Name = "BuildingPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, Balance.UI.panelWidth, 0, 470),
		BackgroundTransparency = 0.02,
		Visible = false,
		ZIndex = 30,
	}, Kit.PALETTE.accentDark)
	frame.Parent = parent

	local scale = Kit.create("UIScale", { Scale = 1 })
	scale.Parent = frame

	local title = Kit.label("Building", UDim2.new(1, -140, 0, 26), {
		Position = UDim2.new(0, 16, 0, 12),
		Font = Enum.Font.GothamBold,
		TextSize = 20,
	})
	title.Parent = frame

	local subtitle = Kit.label("", UDim2.new(1, -140, 0, 18), {
		Position = UDim2.new(0, 16, 0, 38),
		TextColor3 = Kit.PALETTE.textDim,
		TextSize = 13,
	})
	subtitle.Parent = frame

	local closeButton = Kit.button("Close", function() end, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 96, 0, 40),
		BackgroundColor3 = Kit.PALETTE.surfaceHigh,
	})
	closeButton.Parent = frame

	local tabBar = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 62),
		Size = UDim2.new(1, -24, 0, 42),
	}) :: Frame
	local tabScroll = Kit.create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Size = UDim2.new(1, 0, 1, 0),
	}) :: ScrollingFrame
	tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	local tabLayout = Kit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) :: UIListLayout
	tabLayout.Parent = tabScroll
	tabScroll.Parent = tabBar
	tabBar.Parent = frame

	local content = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 110),
		Size = UDim2.new(1, -24, 1, -122),
	}) :: Frame
	content.Parent = frame
	local scroll, list = Kit.scrollList(content)

	local currentUid: string? = nil
	local currentTab = "overview"
	local tabButtons: { [string]: TextButton } = {}

	local function setTab(tabId: string)
		currentTab = tabId
		for id, button in tabButtons do
			button.BackgroundColor3 = if id == tabId
				then Kit.PALETTE.accentDark
				else Kit.PALETTE.surfaceHigh
		end
		BuildingPanel.render()
	end

	for index, tab in ipairs(TABS) do
		local button = Kit.button(tab.label, function()
			setTab(tab.id)
		end, {
			Size = UDim2.new(0, 104, 0, 38),
			LayoutOrder = index,
			BackgroundColor3 = Kit.PALETTE.surfaceHigh,
			TextSize = 14,
		})
		button.Parent = tabScroll
		tabButtons[tab.id] = button
	end

	local function addRow(
		titleText: string,
		subtitleText: string,
		actionText: string?,
		action: (() -> ())?,
		accent: Color3?
	): (Frame, TextButton?, TextLabel)
		local row = Kit.card({ Size = UDim2.new(1, 0, 0, 64) }, accent)
		local name = Kit.label(titleText, UDim2.new(1, -180, 0, 20), {
			Position = UDim2.new(0, 10, 0, 8),
			Font = Enum.Font.GothamBold,
			TextSize = 15,
		})
		name.Parent = row
		local detail = Kit.label(subtitleText, UDim2.new(1, -180, 0, 28), {
			Position = UDim2.new(0, 10, 0, 28),
			TextColor3 = Kit.PALETTE.textDim,
			TextSize = 12,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		detail.Parent = row

		local button: TextButton? = nil
		if actionText and action then
			button = Kit.button(actionText, action, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.new(0, 150, 0, 40),
				TextSize = 13,
			})
			button.Parent = row
		end
		row.Parent = list
		return row, button, detail
	end

	local function send(intent: string, payload: any)
		StateController.Send(intent, payload)
	end

	local function renderOverview(row: any)
		local profile = StateController.AsProfileBuilding(row)
		local def = Content.buildingById[row.def]
		if not def then
			return
		end
		local income = BuildingMath.income(def, profile)
		addRow(
			`Level {row.level} / {row.maxLevel}`,
			`{NumberFormat.money(income.netPerMin)}/min net · {row.operational and "Operating" or "Under construction"}`
		)

		if row.level < row.maxLevel then
			local state = StateController.Get()
			local cash = state.currency and state.currency.cash or 0
			local cost = BuildingMath.levelCost(def, profile)
			local copy = table.clone(profile)
			copy.level += 1
			local after = BuildingMath.income(def, copy).netPerMin
			local delta = after - income.netPerMin
			local payback = if delta > 0 then cost / delta else math.huge
			local _, button = addRow(
				`Expand to level {row.level + 1}`,
				string.format(
					"+%s/min · payback %s · cost %s",
					NumberFormat.money(delta),
					if payback == math.huge then "—" else NumberFormat.duration(payback * 60),
					NumberFormat.money(cost)
				),
				NumberFormat.money(cost),
				function()
					send("LevelPurchase", { buildingUid = row.uid })
				end,
				Kit.PALETTE.accent
			)
			if button then
				button.BackgroundColor3 = if cash >= cost
					then Kit.PALETTE.accentDark
					else Kit.PALETTE.surfaceHigh
			end
		end

		if row.operational then
			addRow(
				"Uncollected income",
				`{NumberFormat.money(row.pending)} waiting`,
				if row.pending > 0 then "Collect" else nil,
				if row.pending > 0
					then function()
						send("IncomeCollect", { buildingUid = row.uid })
					end
					else nil,
				Kit.PALETTE.gold
			)
		end

		addRow(
			"Managers",
			if row.manager
				then `Managed by {row.manager} — income collects automatically`
				else "No manager yet",
			nil,
			nil
		)
	end

	local function renderUpgrades(row: any)
		local profile = StateController.AsProfileBuilding(row)
		local def = Content.buildingById[row.def]
		local cash = StateController.Get().currency and StateController.Get().currency.cash or 0
		if not def then
			return
		end
		local grouped = Content.upgradesByCategory(row.def)
		for _, category in ipairs({
			"Construction",
			"Staffing",
			"Equipment",
			"Business",
			"Appearance",
			"Mastery",
		}) do
			local heading = Kit.label(
				Content.strings.categories[category] or category,
				UDim2.new(1, 0, 0, 24),
				{
					Font = Enum.Font.GothamBold,
					TextColor3 = Kit.PALETTE.gold,
					TextSize = 14,
				}
			)
			heading.Parent = list

			for _, upgrade in ipairs(grouped[category] or {}) do
				local level = row.upg[upgrade.id] or 0
				local cost = BuildingMath.upgradeCost(def, profile, upgrade.id)
				local effectText = if upgrade.effect.stat == "revenue"
					then `+{string.format("%.0f", upgrade.effect.perLevel * 100)}% revenue per level`
					elseif upgrade.effect.stat == "expense" then `{string.format(
						"%.0f",
						upgrade.effect.perLevel * 100
					)}% expenses per level`
					elseif upgrade.effect.stat == "capacity" then `+{string.format(
						"%.0f",
						upgrade.effect.perLevel
					)} customers/min per level`
					elseif upgrade.effect.stat == "masteryXp" then `+{string.format(
						"%.0f",
						upgrade.effect.perLevel * 100
					)}% mastery XP per level`
					else `+{string.format("%.1f", upgrade.effect.perLevel)} {upgrade.effect.stat} per level`

				local maxed = level >= upgrade.maxLevel
				local detail = `{upgrade.description}  ·  {effectText}`
				local _, button = addRow(
					`{upgrade.name}  ({level}/{upgrade.maxLevel})`,
					detail,
					if maxed then "Maxed" else NumberFormat.money(cost),
					if maxed
						then nil
						else function()
							send(
								"UpgradePurchase",
								{ buildingUid = row.uid, upgradeId = upgrade.id }
							)
						end,
					nil
				)
				if button and not maxed then
					button.BackgroundColor3 = if cash >= cost
						then Kit.PALETTE.accentDark
						else Kit.PALETTE.surfaceHigh
				end
			end
		end
	end

	local function renderStaff(row: any)
		local profile = StateController.AsProfileBuilding(row)
		local def = Content.buildingById[row.def]
		if not def then
			return
		end
		local used = 0
		for _, count in row.staff do
			used += count
		end
		local cash = StateController.Get().currency and StateController.Get().currency.cash or 0

		addRow(
			`Slots {used} / {def.staffSlots}`,
			`Wages {NumberFormat.money(row.wagesPerMin)}/min are part of operating costs`
		)

		for _, gradeId in ipairs({ "Basic", "Skilled", "Expert", "Executive" }) do
			local grade = Content.staffById[gradeId]
			if grade then
				local cost = BuildingMath.staffCost(def, profile, gradeId)
				local count = row.staff[gradeId] or 0
				local _, button = addRow(
					`{grade.name}  x{count}`,
					string.format(
						"wage %s/min · +%.0f%% revenue each%s",
						NumberFormat.money(grade.wagePerMin),
						Balance.Staff.revenuePerWorker * grade.efficiency * 100,
						if used >= def.staffSlots then " · no free slots" else ""
					),
					NumberFormat.money(cost),
					function()
						send("StaffHire", { buildingUid = row.uid, grade = gradeId })
					end,
					nil
				)
				if button then
					button.BackgroundColor3 = if cash >= cost and used < def.staffSlots
						then Kit.PALETTE.accentDark
						else Kit.PALETTE.surfaceHigh
				end
			end
		end

		local managerText = if row.manager then "Hired" else NumberFormat.money(def.managerCost)
		local _, managerButton = addRow(
			"Manager",
			if row.manager
				then "Collects income automatically, even while you are offline."
				else `Automates collection · requires level {def.managerMinLevel}`,
			managerText,
			if row.manager
				then nil
				else function()
					send("ManagerHire", { buildingUid = row.uid })
				end,
			Kit.PALETTE.gold
		)
		if managerButton and not row.manager then
			local affordable = cash >= def.managerCost and row.level >= def.managerMinLevel
			managerButton.BackgroundColor3 = if affordable
				then Kit.PALETTE.accentDark
				else Kit.PALETTE.surfaceHigh
		end
	end

	local function renderIncome(row: any)
		local income = row.income
		addRow(
			"Revenue",
			`${NumberFormat.money(income.gross)} / min from {string.format("%.0f", income.customers)} customers`
		)
		addRow(
			"Operating costs",
			`${NumberFormat.money(income.expenses)} / min (supplies, utilities, wages)`
		)
		addRow(
			"Net profit",
			`${NumberFormat.money(income.net)} / min · never below {string.format(
				"%.0f",
				Balance.Rates.minNetFraction * 100
			)}% of revenue`
		)
		addRow("Average spend", `{NumberFormat.money(income.avgSpend)} per customer`)
		addRow("Pending cash", `${NumberFormat.money(row.pending)} waiting to be collected`)
	end

	local function renderConstruction(row: any)
		local def = Content.buildingById[row.def]
		if row.constructing then
			local progress = row.constructing.progress or 0
			local track, setFraction = Kit.progressBar(12)
			addRow(
				`Phase {row.constructing.phase} of {row.phases}`,
				`{string.format("%.0f", progress * 100)}% complete · {NumberFormat.duration(
					row.constructing.remaining
				)} remaining`
			)
			track.Parent = list
			setFraction(progress, Kit.PALETTE.accent)
			local rushCost = math.max(
				1,
				math.floor(
					(row.constructing.remaining or 0) * Balance.Construction.rushCostPerSecond + 0.5
				)
			)
			addRow(
				"Finish now",
				`Pay a premium to complete the current phase immediately`,
				NumberFormat.money(rushCost),
				function()
					send("ConstructionRush", { buildingUid = row.uid })
				end,
				Kit.PALETTE.gold
			)
		else
			addRow(
				"Construction complete",
				if def then `All {#def.phases} phases finished` else "Finished"
			)
			addRow(
				"Expansion",
				Content.strings.stub .. " (Construction phases arrive with Phase 2 content)"
			)
		end
	end

	local function renderMastery(row: any)
		local def = Content.buildingById[row.def]
		local mastery = row.mastery or { xp = 0, lvl = 1, progress = 0 }
		local track, setFraction = Kit.progressBar(12)
		addRow(
			`Mastery level {mastery.lvl} / {Mastery.MAX_LEVEL}`,
			`{NumberFormat.full(mastery.xp)} XP earned`
		)
		track.Parent = list
		setFraction(mastery.progress or 0, Kit.PALETTE.gold)

		local nextMilestone: number? = nil
		for threshold in Balance.Mastery.milestones do
			if
				(tonumber(threshold) or 0) > mastery.lvl
				and (nextMilestone == nil or threshold < nextMilestone)
			then
				nextMilestone = tonumber(threshold)
			end
		end
		if nextMilestone then
			local bonus = Balance.Mastery.milestones[nextMilestone]
			addRow(
				`Next milestone: level {nextMilestone}`,
				`Permanent +{string.format("%.0f", (bonus or 0) * 100)}% revenue at level {nextMilestone}`
			)
		else
			addRow("Mastered", "Every milestone reached for this property.")
		end
		if def then
			addRow(
				"How mastery grows",
				"Earn XP by collecting income and buying upgrades. Gains soften if you farm one cheap property all day."
			)
		end
	end

	local function renderCustom(row: any)
		addRow("Appearance themes", Content.strings.stub)
		addRow("Signage & lighting", Content.strings.stub)
		addRow("Furniture collections", Content.strings.stub)
	end

	function BuildingPanel.render()
		Kit.clearChildren(list)
		local uid = currentUid
		local row = uid and StateController.Building(uid)
		if not row then
			BuildingPanel.close()
			return
		end
		local def = Content.buildingById[row.def]
		title.Text = def and def.name or row.def
		subtitle.Text = string.format(
			"%s · %s · level %d",
			if def then def.archetype else "Building",
			if row.operational then "Operating" else "Construction",
			row.level
		)

		if currentTab == "overview" then
			renderOverview(row)
		elseif currentTab == "upgrades" then
			renderUpgrades(row)
		elseif currentTab == "staff" then
			renderStaff(row)
		elseif currentTab == "income" then
			renderIncome(row)
		elseif currentTab == "construction" then
			renderConstruction(row)
		elseif currentTab == "mastery" then
			renderMastery(row)
		else
			renderCustom(row)
		end
	end

	local onClose: (() -> ())? = nil

	local panel: any = {
		frame = frame,
		open = function(uid: string)
			currentUid = uid
			scrim.Visible = true
			frame.Visible = true
			setTab(currentTab)
		end,
		close = function()
			currentUid = nil
			scrim.Visible = false
			frame.Visible = false
			if onClose then
				onClose()
			end
		end,
		refresh = function(state: any)
			if frame.Visible and currentUid then
				BuildingPanel.render()
			end
		end,
		isOpen = function()
			return frame.Visible == true
		end,
		uid = function()
			return currentUid
		end,
		setOnClose = function(callback: () -> ())
			onClose = callback
		end,
	}

	closeButton.Activated:Connect(function()
		panel.close()
	end)
	scrim.Activated:Connect(function()
		panel.close()
	end)

	-- Fit on small screens.
	local viewport = gui.AbsoluteSize
	scale.Scale = math.clamp(math.min(viewport.X / 680, viewport.Y / 560), 0.55, 1)

	return panel
end

return BuildingPanel
