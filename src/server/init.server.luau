--!strict
--[[
	Server bootstrap.

	Services are registered here in one place and started in explicit dependency order
	(`Services/Registry` sorts them and fails loudly on a cycle). Adding a service means
	adding one line — no service reaches into another's internals.
]]

local Registry = require(script.Services.Registry)

local services = {
	require(script.Services.DataService),
	require(script.Services.EconomyService),
	require(script.Services.PlotService),
	require(script.Services.BuildingService),
	require(script.Services.ParcelService),
	require(script.Services.ConstructionService),
	require(script.Services.IncomeService),
	require(script.Services.OfflineService),
	require(script.Services.StaffService),
	require(script.Services.UpgradeService),
	require(script.Services.ObjectiveService),
	require(script.Services.SnapshotService),
	require(script.Services.NetService),
	require(script.Services.DebugService),
}

local registry = Registry.new()
for _, service in ipairs(services) do
	registry:Add(service)
end

local ok, err = pcall(function()
	registry:Start()
end)

if not ok then
	warn(`[BillionaireCity] fatal startup error: {tostring(err)}`)
	error(err, 0)
end

print(`[BillionaireCity] server ready — services: {table.concat(registry:Order(), ", ")}`)
