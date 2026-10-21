--!strict
--[[
	Tiny service container with explicit, acyclic dependency order.

	Every service module exports `Name` and `Dependencies` plus `Init(registry)` and
	`Start()`. `Registry.build` topologically sorts them and errors on a missing
	dependency or a cycle — a cycle fails at server start, not at 3am in production.
]]

local Registry = {}
Registry.__index = Registry

export type Service = {
	Name: string,
	Dependencies: { string }?,
	Init: ((registry: any) -> ())?,
	Start: ((registry: any) -> ())?,
}

function Registry.new()
	return setmetatable({
		_services = {},
		_order = {},
		_initialised = false,
	}, Registry)
end

function Registry:Add(service: Service)
	if self._services[service.Name] then
		error(`duplicate service "{service.Name}"`, 2)
	end
	self._services[service.Name] = service
end

--[[ Returns the services in dependency order, or errors with a readable message. ]]
function Registry:sort(): { Service }
	local ordered: { Service } = {}
	local state: { [string]: number } = {}
	local path: { string } = {}

	local function visit(name: string)
		local status = state[name]
		if status == 2 then
			return
		end
		if status == 1 then
			table.insert(path, name)
			error(`service dependency cycle: {table.concat(path, " -> ")}`, 0)
		end
		local service = self._services[name]
		if not service then
			error(`missing service "{name}" (required by {table.concat(path, " -> ")})`, 0)
		end
		state[name] = 1
		table.insert(path, name)
		for _, dependency in ipairs(service.Dependencies or {}) do
			visit(dependency)
		end
		table.remove(path)
		state[name] = 2
		table.insert(ordered, service)
	end

	local names: { string } = {}
	for name in self._services do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		visit(name)
	end
	return ordered
end

--[[ Runs Init then Start for every service, in dependency order. ]]
function Registry:Start()
	if self._initialised then
		return
	end
	self._initialised = true
	for _, service in ipairs(self:sort()) do
		table.insert(self._order, service.Name)
		if service.Init then
			service.Init(self)
		end
	end
	for _, service in ipairs(self:sort()) do
		if service.Start then
			service.Start(self)
		end
	end
end

function Registry:Get(name: string): any
	local service = self._services[name]
	if not service then
		error(`unknown service "{name}"`, 2)
	end
	return service
end

function Registry:Order(): { string }
	return table.clone(self._order)
end

return Registry
