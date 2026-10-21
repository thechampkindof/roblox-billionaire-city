--!strict
--[[
	`Result<T>` is the single return shape for every server intent and every
	failable core operation: `{ ok, code, message?, data? }`.

	Codes are stable strings so the client can localise them via `Config/Strings`.
]]

export type Result<T> = {
	ok: boolean,
	code: string,
	message: string?,
	data: T?,
}

local Result = {}

export type ResultType<T> = Result<T>

function Result.ok<T>(data: T?, code: string?): Result<T>
	return {
		ok = true,
		code = code or "OK",
		data = data,
	}
end

function Result.err<T>(code: string, message: string?): Result<T>
	return {
		ok = false,
		code = code,
		message = message,
	}
end

function Result.isOk(result: Result<any>): boolean
	return result.ok == true
end

function Result.isErr(result: Result<any>): boolean
	return result.ok ~= true
end

--[[ Returns the payload of a successful result, or `fallback` when it failed. ]]
function Result.unwrap<T>(result: Result<T>, fallback: T?): T?
	if result.ok then
		return result.data
	end
	return fallback
end

--[[ Returns the payload or throws; only for programmer errors in server code. ]]
function Result.expect<T>(result: Result<T>): T
	if not result.ok then
		error(`expected ok result, got "{result.code}"`, 2)
	end
	return result.data :: T
end

function Result.map<T, U>(result: Result<T>, transform: (T) -> U): Result<U>
	if not result.ok then
		return { ok = false, code = result.code, message = result.message }
	end
	return Result.ok(transform(result.data :: T))
end

return Result
