--!strict
local Framework = require(script.Parent.Parent.Framework)
local Signal = require(script.Parent.Parent.Parent.src.shared.Core.Signal)

Framework.test("Signal fires handlers in connection order", function()
	local signal = Signal.new("test")
	local seen: { string } = {}
	signal:Connect(function(value: string)
		table.insert(seen, `a:{value}`)
	end)
	signal:Connect(function(value: string)
		table.insert(seen, `b:{value}`)
	end)
	signal:Fire("x")
	Framework.equal(table.concat(seen, ","), "a:x,b:x")
	Framework.equal(signal:Count(), 2)
end)

Framework.test("Signal disconnect stops delivery", function()
	local signal = Signal.new("test")
	local calls = 0
	local connection = signal:Connect(function()
		calls += 1
	end)
	signal:Fire()
	connection:Disconnect()
	connection:Disconnect() -- idempotent
	signal:Fire()
	Framework.equal(calls, 1)
	Framework.equal(signal:Count(), 0)
end)

Framework.test("Signal once handlers fire exactly once", function()
	local signal = Signal.new("test")
	local calls = 0
	signal:Once(function()
		calls += 1
	end)
	signal:Fire()
	signal:Fire()
	Framework.equal(calls, 1)
end)

Framework.test("Signal handler errors do not break other handlers", function()
	local signal = Signal.new("test")
	local errors: { string } = {}
	signal:SetErrorHandler(function(message)
		table.insert(errors, message)
	end)
	local secondRan = false
	signal:Connect(function()
		error("boom")
	end)
	signal:Connect(function()
		secondRan = true
	end)
	signal:Fire()
	Framework.isTrue(secondRan, "second handler ran")
	Framework.equal(#errors, 1)
end)

Framework.test("Signal disconnect during dispatch is safe", function()
	local signal = Signal.new("test")
	local secondRan = false
	local first: any
	first = signal:Connect(function()
		first:Disconnect()
	end)
	signal:Connect(function()
		secondRan = true
	end)
	signal:Fire()
	Framework.isTrue(secondRan)
	Framework.equal(signal:Count(), 1)
end)
