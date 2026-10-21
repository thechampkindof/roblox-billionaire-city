--!strict
local Framework = require(script.Parent.Parent.Framework)
local Maid = require(script.Parent.Parent.Parent.src.shared.Core.Maid)

Framework.test("Maid cleans tasks in reverse order", function()
	local maid = Maid.new()
	local order: { string } = {}
	maid:Add(function()
		table.insert(order, "first")
	end)
	maid:Add(function()
		table.insert(order, "second")
	end)
	maid:DoCleaning()
	Framework.equal(table.concat(order, ","), "second,first")
	Framework.equal(maid:Count(), 0)
end)

Framework.test("Maid destroys table tasks via Destroy or Disconnect", function()
	local maid = Maid.new()
	local destroyed = false
	local disconnected = false
	maid:Add({
		Destroy = function()
			destroyed = true
		end,
	})
	maid:Add({
		Disconnect = function()
			disconnected = true
		end,
	})
	maid:Destroy()
	Framework.isTrue(destroyed, "Destroy called")
	Framework.isTrue(disconnected, "Disconnect called")
end)

Framework.test("Maid is idempotent and safe after cleanup", function()
	local maid = Maid.new()
	local calls = 0
	maid:Add(function()
		calls += 1
	end)
	maid:Destroy()
	maid:Destroy()
	local late = 0
	maid:Add(function()
		late += 1
	end)
	Framework.equal(calls, 1)
	Framework.equal(late, 1, "tasks added after Destroy run immediately")
end)
