--!strict
--[[
	Toast stack: short, queue-limited, auto-dismissing messages in the bottom-centre of
	the screen. Errors are red, successes green, offline income is gold.
]]

local TweenService = game:GetService("TweenService")

local Kit = require(script.Parent.Kit)

local Toasts = {}

local MAX_VISIBLE = 3
local active: { TextLabel } = {}

--[[ Shows a toast inside `parent` (a ScreenGui or frame). ]]
function Toasts.show(parent: Instance, text: string, kind: string?)
	local color = Kit.PALETTE.text
	if kind == "error" then
		color = Kit.PALETTE.danger
	elseif kind == "success" then
		color = Kit.PALETTE.accent
	elseif kind == "reward" then
		color = Kit.PALETTE.gold
	end

	local label = Kit.label(text, UDim2.new(0, 320, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.PALETTE.surface,
		BackgroundTransparency = 0.05,
		Font = Enum.Font.GothamMedium,
		TextColor3 = color,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(0, 320, 0, 44),
	}) :: TextLabel
	label.ZIndex = 60
	label.Parent = parent
	Kit.corner(10).Parent = label
	Kit.padding(10).Parent = label
	Kit.stroke(Kit.PALETTE.stroke).Parent = label

	local listLayout = parent:FindFirstChild("__toastLayout")
	if not listLayout then
		local holder = Kit.create("Frame", {
			Name = "__toastLayout",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -120),
			Size = UDim2.new(0, 340, 0, 240),
			ZIndex = 60,
		}) :: Frame
		local layout = Kit.create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}) :: UIListLayout
		layout.Parent = holder
		holder.Parent = parent
		listLayout = holder
	end

	label.Parent = listLayout
	table.insert(active, label)
	if #active > MAX_VISIBLE then
		local oldest = table.remove(active, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	label.TextTransparency = 1
	TweenService:Create(label, TweenInfo.new(0.15), { TextTransparency = 0 }):Play()

	task.delay(4, function()
		if not label.Parent then
			return
		end
		local tween = TweenService:Create(
			label,
			TweenInfo.new(0.25),
			{ TextTransparency = 1, BackgroundTransparency = 1 }
		)
		tween:Play()
		tween.Completed:Once(function()
			label:Destroy()
		end)
	end)
end

return Toasts
