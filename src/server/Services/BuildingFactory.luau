--!strict
--[[
	Procedural building art.

	No meshes are authored for this project, so every building is assembled from parts
	by style definition. Art slots exist at `ServerStorage/Templates/<buildingId>/<stage>`
	(`stage` = "site", "shell" or "finished"); if a model is present there it replaces the
	placeholder entirely, so real art can land later without touching code.

	Budgets: <= 40 BaseParts per standard building (Appendix B7).
]]

local ServerStorage = game:GetService("ServerStorage")

local Shared = script.Parent.Parent.Parent.ReplicatedStorage.Shared
local Config = Shared.Config
local Types = Shared.Core.Types
local Content = require(Config.Init)

local BuildingFactory = {}

export type Style = {
	wall: Color3,
	trim: Color3,
	roof: Color3,
	sign: Color3,
	floors: number,
	footprint: Vector2,
	height: number,
}

local PALETTES: { [string]: { wall: Color3, trim: Color3, roof: Color3, sign: Color3 } } = {
	retail_small = {
		wall = Color3.fromRGB(236, 226, 200),
		trim = Color3.fromRGB(196, 84, 66),
		roof = Color3.fromRGB(84, 92, 104),
		sign = Color3.fromRGB(250, 205, 90),
	},
	retail_mid = {
		wall = Color3.fromRGB(224, 232, 236),
		trim = Color3.fromRGB(64, 132, 176),
		roof = Color3.fromRGB(72, 80, 92),
		sign = Color3.fromRGB(120, 215, 240),
	},
	food_small = {
		wall = Color3.fromRGB(240, 216, 196),
		trim = Color3.fromRGB(176, 62, 52),
		roof = Color3.fromRGB(92, 60, 48),
		sign = Color3.fromRGB(255, 170, 90),
	},
	service_fuel = {
		wall = Color3.fromRGB(226, 230, 232),
		trim = Color3.fromRGB(38, 120, 92),
		roof = Color3.fromRGB(60, 66, 74),
		sign = Color3.fromRGB(120, 240, 160),
	},
	service_wash = {
		wall = Color3.fromRGB(208, 228, 240),
		trim = Color3.fromRGB(46, 110, 170),
		roof = Color3.fromRGB(70, 80, 96),
		sign = Color3.fromRGB(140, 210, 255),
	},
	service_lot = {
		wall = Color3.fromRGB(190, 192, 196),
		trim = Color3.fromRGB(120, 124, 130),
		roof = Color3.fromRGB(150, 152, 158),
		sign = Color3.fromRGB(230, 230, 235),
	},
	residential_small = {
		wall = Color3.fromRGB(238, 232, 220),
		trim = Color3.fromRGB(150, 118, 92),
		roof = Color3.fromRGB(122, 74, 62),
		sign = Color3.fromRGB(255, 214, 150),
	},
	residential_mid = {
		wall = Color3.fromRGB(230, 226, 214),
		trim = Color3.fromRGB(120, 110, 100),
		roof = Color3.fromRGB(96, 88, 84),
		sign = Color3.fromRGB(255, 200, 140),
	},
	office_small = {
		wall = Color3.fromRGB(198, 214, 232),
		trim = Color3.fromRGB(70, 96, 130),
		roof = Color3.fromRGB(60, 70, 86),
		sign = Color3.fromRGB(150, 220, 255),
	},
}

local DEFAULT_PALETTE = {
	wall = Color3.fromRGB(220, 220, 224),
	trim = Color3.fromRGB(110, 110, 118),
	roof = Color3.fromRGB(80, 84, 92),
	sign = Color3.fromRGB(240, 220, 160),
}

local function paletteFor(style: string)
	return PALETTES[style] or DEFAULT_PALETTE
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = material or Enum.Material.SmoothPlastic
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function addSign(
	parent: Instance,
	cframe: CFrame,
	width: number,
	height: number,
	color: Color3,
	text: string
)
	local board = part(
		parent,
		"Sign",
		Vector3.new(width, height, 0.4),
		cframe,
		color,
		Enum.Material.SmoothPlastic
	)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, 120)
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(28, 30, 36)
	label.Text = text
	label.Parent = gui
end

--[[ Looks for a hand-authored replacement in ServerStorage/Templates. ]]
local function artSlot(buildingId: string, stage: string): Model?
	local templates = ServerStorage:FindFirstChild("Templates")
	if not templates then
		return nil
	end
	local buildingFolder = templates:FindFirstChild(buildingId)
	if not buildingFolder then
		return nil
	end
	local model = buildingFolder:FindFirstChild(stage)
	if model and model:IsA("Model") then
		return model:Clone()
	end
	return nil
end

local function finish(model: Model, def: Types.BuildingDef, stage: string, position: Vector3): Model
	model.Name = `{def.id}_{stage}`
	model:PivotTo(CFrame.new(position))
	model:SetAttribute("BuildingDef", def.id)
	model:SetAttribute("Stage", stage)
	return model
end

--[[ Construction site: dirt, fence posts and a progress-lit shell. ]]
function BuildingFactory.Site(def: Types.BuildingDef, position: Vector3, progress: number): Model
	local override = artSlot(def.id, if progress >= 1 then "finished" else "site")
	if override and progress < 1 then
		return finish(override, def, "site", position)
	end

	local palette = paletteFor(def.style)
	local model = Instance.new("Model")
	local fraction = math.clamp(progress, 0, 1)

	local ground = part(
		model,
		"Ground",
		Vector3.new(30, 0.4, 30),
		CFrame.new(position + Vector3.new(0, 0.2, 0)),
		Color3.fromRGB(150, 124, 92),
		Enum.Material.Ground
	)
	ground.Name = "Dirt"

	for index = 1, 4 do
		local angle = (index / 4) * math.pi * 2
		part(
			model,
			`Fence{index}`,
			Vector3.new(0.6, 4, 12),
			CFrame.new(position + Vector3.new(math.cos(angle) * 14, 2, math.sin(angle) * 14))
				* CFrame.Angles(0, angle, 0),
			Color3.fromRGB(214, 160, 60),
			Enum.Material.Metal
		)
	end

	if fraction > 0.02 then
		local height = math.max(1.5, 12 * fraction)
		part(
			model,
			"Structure",
			Vector3.new(20, height, 20),
			CFrame.new(position + Vector3.new(0, height / 2, 0)),
			palette.wall,
			Enum.Material.Concrete
		)
	end

	if fraction > 0.55 then
		part(
			model,
			"Crane",
			Vector3.new(1.2, 18, 1.2),
			CFrame.new(position + Vector3.new(10, 9, -10)),
			Color3.fromRGB(240, 190, 60),
			Enum.Material.Metal
		)
	end

	model:PivotTo(CFrame.new(position))
	return finish(model, def, "site", position)
end

--[[ Finished (or shell) building. Level adds floors, appearance adds trim, mastery adds gold. ]]
function BuildingFactory.Build(
	def: Types.BuildingDef,
	position: Vector3,
	level: number,
	stage: string,
	masteryLevel: number?
): Model
	local override = artSlot(def.id, if stage == "finished" then "finished" else "shell")
	if override then
		return finish(override, def, stage, position)
	end

	local palette = paletteFor(def.style)
	local model = Instance.new("Model")
	local floors = math.clamp(1 + math.floor((level - 1) / 3), 1, 5)
	local height = 6 + (floors - 1) * 5
	local footprint = if def.parcelSize == "S" then 18 elseif def.parcelSize == "M" then 24 else 28

	local base = part(
		model,
		"Base",
		Vector3.new(footprint + 2, 0.6, footprint + 2),
		CFrame.new(position + Vector3.new(0, 0.3, 0)),
		palette.trim,
		Enum.Material.Concrete
	)
	base.Name = "Plinth"

	part(
		model,
		"Body",
		Vector3.new(footprint, height, footprint),
		CFrame.new(position + Vector3.new(0, height / 2 + 0.6, 0)),
		if stage == "shell" then Color3.fromRGB(168, 168, 172) else palette.wall,
		if stage == "shell" then Enum.Material.Concrete else Enum.Material.SmoothPlastic
	)

	if stage ~= "shell" then
		part(
			model,
			"Roof",
			Vector3.new(footprint + 2, 1, footprint + 2),
			CFrame.new(position + Vector3.new(0, height + 1.1, 0)),
			palette.roof,
			Enum.Material.Slate
		)

		local doorHeight = math.min(5, height * 0.6)
		part(
			model,
			"Door",
			Vector3.new(5, doorHeight, 0.4),
			CFrame.new(position + Vector3.new(0, doorHeight / 2 + 0.6, -footprint / 2 - 0.2)),
			Color3.fromRGB(58, 62, 70),
			Enum.Material.Glass
		)

		local windowCount = math.min(floors * 2, 8)
		for index = 1, windowCount do
			local row = math.floor((index - 1) / 2)
			local side = if index % 2 == 0 then 1 else -1
			part(
				model,
				`Window{index}`,
				Vector3.new(3, 2.4, 0.3),
				CFrame.new(
					position
						+ Vector3.new(side * footprint * 0.28, 3 + row * 4.2, -footprint / 2 - 0.2)
				),
				Color3.fromRGB(150, 205, 235),
				Enum.Material.Glass
			)
		end

		addSign(
			model,
			CFrame.new(position + Vector3.new(0, height + 3.2, -footprint / 2 - 0.1)),
			math.min(footprint, 20),
			4,
			palette.sign,
			def.name
		)
	end

	-- Visible progression: a second wing at level 6+, gold trim at mastery 50+.
	if level >= 6 and stage ~= "shell" then
		part(
			model,
			"Wing",
			Vector3.new(footprint * 0.5, height * 0.7, footprint * 0.6),
			CFrame.new(position + Vector3.new(footprint * 0.8, height * 0.35 + 0.6, 0)),
			palette.wall
		)
	end
	if (masteryLevel or 0) >= 50 and stage ~= "shell" then
		part(
			model,
			"MasteryTrim",
			Vector3.new(footprint + 3, 0.6, footprint + 3),
			CFrame.new(position + Vector3.new(0, 0.9, 0)),
			Color3.fromRGB(248, 212, 96),
			Enum.Material.Metal
		)
	end

	model:PivotTo(CFrame.new(position))
	return finish(model, def, stage, position)
end

--[[ Adds the collector prompt above a building (client also uses attributes). ]]
function BuildingFactory.AttachPrompt(model: Model, uid: string)
	model:SetAttribute("BuildingUid", uid)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("BuildingUid", uid)
		end
	end
end

return BuildingFactory
