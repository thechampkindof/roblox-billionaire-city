--!strict
--[[
	Cosmetic ambient life: pedestrians and traffic around the hub.

	Client-side only, pooled, seeded and capped by device quality (Appendix B2 #8, B7).
	Nothing here affects the economy, and nothing is replicated.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core
local Config = Shared.Config

local Maid = require(Core.Maid)
local Content = require(Config.Init)
local Balance = Content.Balance

local AmbientController = {}
AmbientController.Name = "AmbientController"

local maid = Maid.new()
local agents: { BasePart } = {}
local phase: { [BasePart]: number } = {}
local rng = Random.new(20261021)
local running = false

local function qualityBudget(): number
	local input = UserInputService
	if input.TouchEnabled and not input.KeyboardEnabled then
		return Balance.UI.ambientAgents.low
	end
	if input.GamepadEnabled then
		return Balance.UI.ambientAgents.medium
	end
	return Balance.UI.ambientAgents.medium
end

local function createAgent(index: number): BasePart
	local isVehicle = index % 3 == 0
	local part = Instance.new("Part")
	part.Name = if isVehicle then `AmbientCar{index}` else `AmbientPed{index}`
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	if isVehicle then
		part.Size = Vector3.new(4, 2, 7)
		part.Color = Color3.fromHSV(rng:NextNumber(0, 1), 0.35, 0.85)
	else
		part.Size = Vector3.new(2, 4, 1)
		part.Color = Color3.fromHSV(rng:NextNumber(0, 1), 0.25, 0.65)
	end
	return part
end

function AmbientController.Start()
	if not Config.Flags.get("AmbientLife") then
		return
	end
	local budget = qualityBudget()
	local folder = Workspace:FindFirstChild("AmbientLife")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "AmbientLife"
		folder.Parent = Workspace
	end

	for index = 1, budget do
		local agent = createAgent(index)
		agent.Parent = folder
		table.insert(agents, agent)
		phase[agent] = rng:NextNumber(0, math.pi * 2)
	end

	running = true
	maid:Add(RunService.Heartbeat:Connect(function(deltaTime: number)
		if not running then
			return
		end
		for index, agent in ipairs(agents) do
			phase[agent] = (phase[agent] + deltaTime * (if index % 3 == 0 then 0.35 else 0.18))
				% (math.pi * 2)
			local angle = phase[agent]
			local radius = Balance.World.hubRadius - 18 + (index % 5) * 5
			local position = Vector3.new(
				math.cos(angle) * radius,
				if index % 3 == 0 then 1.6 else 2.4,
				math.sin(angle) * radius
			)
			agent.CFrame = CFrame.lookAt(
				position,
				position + Vector3.new(-math.sin(angle), 0, math.cos(angle))
			)
		end
	end))
end

function AmbientController.Stop()
	running = false
	maid:Destroy()
end

return AmbientController
