--!strict
--[[
	Tiny UI component kit, built in code (no external packages).

	Mobile-first rules baked in: 44 px minimum tap targets, scaled text, no hover-only
	affordances, scrollable panels. Everything is parented to a single ScreenGui owned
	by UIController, so tests and teardown stay simple.
]]

local Kit = {}

Kit.PALETTE = {
	background = Color3.fromRGB(16, 18, 24),
	surface = Color3.fromRGB(26, 29, 37),
	surfaceHigh = Color3.fromRGB(38, 42, 52),
	accent = Color3.fromRGB(96, 216, 132),
	accentDark = Color3.fromRGB(54, 140, 86),
	gold = Color3.fromRGB(248, 208, 96),
	danger = Color3.fromRGB(240, 96, 96),
	text = Color3.fromRGB(238, 240, 246),
	textDim = Color3.fromRGB(166, 172, 186),
	stroke = Color3.fromRGB(64, 70, 84),
}

export type Props = { [string]: any }

--[[ Creates an instance with properties applied, then parents it last. ]]
function Kit.create(className: string, props: Props?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	for key, value in props or {} do
		(instance :: any)[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

function Kit.corner(radius: number?): UICorner
	return Kit.create("UICorner", {
		CornerRadius = UDim.new(0, radius or 12),
	}) :: any
end

function Kit.stroke(color: Color3?, thickness: number?): UIStroke
	return Kit.create("UIStroke", {
		Color = color or Kit.PALETTE.stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: any
end

function Kit.padding(amount: number?): UIPadding
	local pad = UDim.new(0, amount or 10)
	return Kit.create("UIPadding", {
		PaddingTop = pad,
		PaddingBottom = pad,
		PaddingLeft = pad,
		PaddingRight = pad,
	}) :: any
end

--[[ Text label with sane defaults. ]]
function Kit.label(text: string, size: UDim2?, props: Props?): TextLabel
	local merged: Props = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = Kit.PALETTE.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = size or UDim2.new(1, 0, 0, 20),
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return Kit.create("TextLabel", merged) :: any
end

--[[ Rounded container. ]]
function Kit.card(props: Props?, strokeColor: Color3?): Frame
	local merged: Props = {
		BackgroundColor3 = Kit.PALETTE.surface,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 60),
	}
	for key, value in props or {} do
		merged[key] = value
	end
	local frame = Kit.create("Frame", merged)
	Kit.corner(12).Parent = frame
	Kit.stroke(strokeColor).Parent = frame
	return frame :: any
end

--[[
	Button with a press animation and a minimum 44 px height. Returns the button.
	`onClick` is called with the button; safe to call from touch, mouse or gamepad.
]]
function Kit.button(text: string, onClick: (TextButton) -> (), props: Props?): TextButton
	local merged: Props = {
		BackgroundColor3 = Kit.PALETTE.accentDark,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 160, 0, 44),
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = Kit.PALETTE.text,
		TextSize = 16,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	local button = Kit.create("TextButton", merged) :: TextButton
	Kit.corner(10).Parent = button
	Kit.stroke(Kit.PALETTE.accentDark).Parent = button
	button.Activated:Connect(function()
		onClick(button)
	end)
	return button
end

function Kit.progressBar(height: number?): (Frame, (fraction: number, color: Color3?) -> ())
	local track = Kit.create("Frame", {
		BackgroundColor3 = Color3.fromRGB(50, 54, 66),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height or 10),
	}) :: Frame
	Kit.corner(6).Parent = track
	local fill = Kit.create("Frame", {
		BackgroundColor3 = Kit.PALETTE.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}) :: Frame
	Kit.corner(6).Parent = fill
	fill.Parent = track

	local function setFraction(fraction: number, color: Color3?)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return track, setFraction
end

function Kit.scrim(parent: Instance): TextButton
	local scrim = Kit.create("TextButton", {
		BackgroundColor3 = Color3.fromRGB(6, 8, 12),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 20,
	}) :: TextButton
	scrim.Parent = parent
	return scrim
end

--[[ Vertical scroll list. Returns the scrolling frame and an inner content frame. ]]
function Kit.scrollList(parent: Instance, props: Props?): (ScrollingFrame, Frame)
	local merged: Props = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.new(1, 0, 1, 0),
	}
	for key, value in props or {} do
		merged[key] = value
	end
	local scroll = Kit.create("ScrollingFrame", merged) :: ScrollingFrame
	local content = Kit.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, 0),
	}) :: Frame
	local layout = Kit.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) :: UIListLayout
	layout.Parent = content
	content.Parent = scroll

	local function fit()
		content.Size = UDim2.new(1, -8, 0, layout.AbsoluteContentSize.Y)
		scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 24)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	return scroll, content
end

function Kit.clearChildren(parent: Instance)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiObject") or child:IsA("UILayout") then
			child:Destroy()
		end
	end
end

--[[ Horizontal chip used by the HUD stat row. ]]
function Kit.statChip(
	label: string,
	value: string,
	width: number?
): (Frame, (newValue: string) -> ())
	local frame = Kit.create("Frame", {
		BackgroundColor3 = Kit.PALETTE.surface,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, width or 130, 0, 52),
	}) :: Frame
	Kit.corner(10).Parent = frame
	Kit.stroke().Parent = frame

	local caption = Kit.label(label, UDim2.new(1, -16, 0, 16), {
		Position = UDim2.new(0, 8, 0, 6),
		TextColor3 = Kit.PALETTE.textDim,
		TextSize = 12,
	})
	caption.Parent = frame
	local valueLabel = Kit.label(value, UDim2.new(1, -16, 0, 24), {
		Position = UDim2.new(0, 8, 0, 22),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
	})
	valueLabel.Parent = frame

	return frame, function(newValue: string)
		valueLabel.Text = newValue
	end
end

return Kit
