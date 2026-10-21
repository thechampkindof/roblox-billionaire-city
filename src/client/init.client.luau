--!strict
--[[
	Client bootstrap.

	Boots the read-only state mirror first (so no server message is missed), then the
	camera, then input/UI. Every controller is a plain module with `Start()`; there is no
	shared mutable bootstrapping state beyond this file.
]]

local Players = game:GetService("Players")

local StateController = require(script.Controllers.StateController)
local CameraController = require(script.Controllers.CameraController)
local InputController = require(script.Controllers.InputController)
local PlotController = require(script.Controllers.PlotController)
local UIController = require(script.Controllers.UIController)
local AmbientController = require(script.Controllers.AmbientController)

StateController.Start()
CameraController.Start()
InputController.Start()
PlotController.Start()
UIController.Start()

AmbientController.Start()

local player = Players.LocalPlayer
print(`[BillionaireCity] client ready for {player.Name}`)
