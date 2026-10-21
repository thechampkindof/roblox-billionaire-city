--!strict
--[[
	Minimal, allocation-light signal implementation used by services and clients.

	Pure Luau: no Roblox APIs, so it is unit-testable headlessly.
	Deliberately small: connect / once / fire / disconnect. Handlers are called in
	connection order, errors in one handler are captured and reported through the
	`onError` hook instead of breaking the remaining handlers.
]]

type Handler = (...any) -> ()

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

type ConnectionImpl = {
	Connected: boolean,
	_handler: Handler,
	_signal: SignalImpl,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: Handler) -> Connection,
	Once: (self: Signal, handler: Handler) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
	Count: (self: Signal) -> number,
}

type SignalImpl = {
	_handlers: { ConnectionImpl },
	_onError: ((string) -> ())?,
	Connect: (self: Signal, handler: Handler) -> Connection,
	Once: (self: Signal, handler: Handler) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
	Count: (self: Signal) -> number,
	SetErrorHandler: (self: Signal, handler: ((string) -> ())?) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new(name: string?): Signal
	local self = setmetatable({}, Signal) :: any
	self._handlers = {}
	self._onError = nil
	self.Name = name or "Signal"
	return self :: any
end

local Connection = {}
Connection.__index = Connection

function Connection.Disconnect(self: Connection)
	local impl = self :: ConnectionImpl
	if not impl.Connected then
		return
	end
	impl.Connected = false

	local handlers = impl._signal._handlers
	for index, candidate in ipairs(handlers) do
		if candidate == impl then
			table.remove(handlers, index)
			break
		end
	end
end

function Signal.SetErrorHandler(self: Signal, handler: ((string) -> ())?)
	local signal = self :: any
	signal._onError = handler
end

function Signal.Connect(self: Signal, handler: Handler): Connection
	local signal = self :: SignalImpl
	local connection = setmetatable({
		Connected = true,
		_handler = handler,
		_signal = signal,
	}, Connection) :: any
	table.insert(signal._handlers, connection)
	return connection :: Connection
end

function Signal.Once(self: Signal, handler: Handler): Connection
	local signal = self :: SignalImpl
	local connection: Connection
	local wrapped: Handler = function(...)
		connection:Disconnect()
		handler(...)
	end
	connection = signal:Connect(wrapped)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	local signal = self :: SignalImpl
	-- Copy first: handlers may disconnect (or connect) during dispatch.
	local snapshot = table.clone(signal._handlers)
	for _, connection in ipairs(snapshot) do
		if connection.Connected then
			local ok, err = pcall(connection._handler, ...)
			if not ok then
				local onError = signal._onError
				if onError then
					onError(tostring(err))
				end
			end
		end
	end
end

function Signal.DisconnectAll(self: Signal)
	local signal = self :: SignalImpl
	for _, connection in ipairs(signal._handlers) do
		connection.Connected = false
	end
	table.clear(signal._handlers)
end

function Signal.Count(self: Signal): number
	return #(self :: SignalImpl)._handlers
end

return Signal
