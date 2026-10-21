--!strict
--[[
	Maid: tracks cleanup tasks (functions, connections, instances) and runs them in
	reverse order. Pure Luau: instances are detected structurally (`Destroy`) so the
	module never references the Roblox API directly.
]]

export type Cleanup =
	(() -> ())
	| { Destroy: (self: any) -> () }
	| { Disconnect: (self: any) -> () }

export type Maid = {
	Add: (self: Maid, item: any) -> any,
	DoCleaning: (self: Maid) -> (),
	Destroy: (self: Maid) -> (),
	Count: (self: Maid) -> number,
}

type MaidImpl = {
	_tasks: { any },
	_cleaned: boolean,
	Add: (self: Maid, item: any) -> any,
	DoCleaning: (self: Maid) -> (),
	Destroy: (self: Maid) -> (),
	Count: (self: Maid) -> number,
}

local Maid = {}
Maid.__index = Maid

function Maid.new(): Maid
	local self = setmetatable({
		_tasks = {},
		_cleaned = false,
	}, Maid) :: any
	return self :: any
end

local function destroyTask(task: any)
	if type(task) == "function" then
		task()
	elseif type(task) == "table" then
		if type(task.Destroy) == "function" then
			task:Destroy()
		elseif type(task.Disconnect) == "function" then
			task:Disconnect()
		end
	end
end

function Maid.Add(self: Maid, item: any): any
	local maid = self :: MaidImpl
	if maid._cleaned then
		-- Adding to a cleaned maid immediately cleans the item; this keeps `Add`
		-- safe in teardown races without erroring.
		destroyTask(item)
		return item
	end
	table.insert(maid._tasks, item)
	return item
end

function Maid.DoCleaning(self: Maid)
	local maid = self :: MaidImpl
	for index = #maid._tasks, 1, -1 do
		local task = maid._tasks[index]
		maid._tasks[index] = nil
		destroyTask(task)
	end
end

function Maid.Destroy(self: Maid)
	local maid = self :: MaidImpl
	maid:DoCleaning()
	maid._cleaned = true
end

function Maid.Count(self: Maid): number
	return #(self :: MaidImpl)._tasks
end

return Maid
