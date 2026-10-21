--!strict
--[[
	City camera.

	A fixed, mobile-friendly three-quarter view centred on the player's plot. Zoom
	buttons (not pinch, not hover) keep it usable one-handed. The camera is scriptable,
	so the player character never controls it — the city is the interface.
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core

local Maid = require(Core.Maid)
local StateController = require(script.Parent.StateController)

local CameraController = {}
CameraController.Name = "CameraController"

local ZOOM_LEVELS =
	{ Vector3.new(70, 85, 70), Vector3.new(100, 120, 100), Vector3.new(140, 165, 140) }
local zoomIndex = 1
local maid = Maid.new()
local target: Vector3 = Vector3.new(0, 0, 0)

local function camera(): Camera
	return Workspace.CurrentCamera
end

--[[ Applies the current zoom/target immediately (used by buttons for snappy feedback). ]]
local function apply()
	local current = camera()
	if not current then
		return
	end
	current.CameraType = Enum.CameraType.Scriptable
	local offset = ZOOM_LEVELS[zoomIndex]
	current.CFrame = CFrame.lookAt(target + offset, target)
end

--[[ Per-frame smoothing toward the current target; cheap because it is one CFrame lerp. ]]
local function update()
	local current = camera()
	if not current then
		return
	end
	current.CameraType = Enum.CameraType.Scriptable
	local offset = ZOOM_LEVELS[zoomIndex]
	local goal = CFrame.lookAt(target + offset, target)
	current.CFrame = current.CFrame:Lerp(goal, 0.18)
end

function CameraController.ZoomIn()
	zoomIndex = math.max(1, zoomIndex - 1)
	apply()
end

function CameraController.ZoomOut()
	zoomIndex = math.min(#ZOOM_LEVELS, zoomIndex + 1)
	apply()
end

function CameraController.Focus(position: Vector3)
	target = position
	apply()
end

function CameraController.Start()
	local plot = StateController.Get().plot
	if plot and plot.origin then
		target = Vector3.new(plot.origin[1], plot.origin[2], plot.origin[3])
	end

	local player = Players.LocalPlayer
	local character: Model? = player.Character
	if character then
		character.Parent = nil
		character:Destroy()
	end
	maid:Add(player.CharacterAdded:Connect(function(newCharacter)
		-- The city view is camera-only; remove the character so it never blocks taps.
		task.defer(function()
			if newCharacter.Parent then
				newCharacter:Destroy()
			end
		end)
	end))

	apply()
	maid:Add(RunService.RenderStepped:Connect(update))
	maid:Add(function()
		local current = camera()
		if current then
			current.CameraType = Enum.CameraType.Custom
		end
	end)
end

function CameraController.Update()
	update()
end

function CameraController.Target(): Vector3
	return target
end

return CameraController
