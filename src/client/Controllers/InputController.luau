--!strict
--[[
	World input: tap/click a parcel or a building.

	Uses one raycast from the camera through the screen point, so touch, mouse and
	gamepad-as-mouse all behave identically. GUI clicks are ignored (GameProcessedEvent).
]]

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage").Shared
local Core = Shared.Core

local Signal = require(Core.Signal)

local InputController = {}
InputController.Name = "InputController"

InputController.ParcelTapped = Signal.new("ParcelTapped")
InputController.BuildingTapped = Signal.new("BuildingTapped")

local MAX_DISTANCE = 2000

local function raycast(screenPosition: Vector2): RaycastResult?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local city = Workspace:FindFirstChild("BillionaireCity")
	if not city then
		return nil
	end
	params.FilterDescendantsInstances = { city }
	return Workspace:Raycast(ray.Origin, ray.Direction * MAX_DISTANCE, params)
end

local function handle(screenPosition: Vector2)
	local result = raycast(screenPosition)
	local hit = result and result.Instance or nil
	if not hit then
		return
	end

	local buildingUid = hit:GetAttribute("BuildingUid")
	if buildingUid then
		InputController.BuildingTapped:Fire(tostring(buildingUid))
		return
	end

	-- Walk up a couple of parents: models carry the attribute on every part, but
	-- decoration parts added later might not.
	local current = hit
	for _ = 1, 3 do
		if not current then
			break
		end
		local uid = current:GetAttribute("BuildingUid")
		if uid then
			InputController.BuildingTapped:Fire(tostring(uid))
			return
		end
		current = current.Parent
	end

	local parcelId = hit:GetAttribute("ParcelId")
	if parcelId then
		InputController.ParcelTapped:Fire(tostring(parcelId))
	end
end

function InputController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			handle(input.Position)
		end
	end)
end

return InputController
