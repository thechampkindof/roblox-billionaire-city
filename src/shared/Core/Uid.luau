--!strict
--[[
	Stable, short, collision-free building uids.

	Format: `b<n>` where `n` is one higher than the highest existing numeric suffix.
	Deterministic and short (important for the profile size budget), and it survives
	saves because the counter is derived from the profile itself.
]]

local Uid = {}

function Uid.next(existing: { [string]: any }): string
	local highest = 0
	for key in existing do
		if type(key) == "string" then
			local suffix = string.match(key, "^b(%d+)$")
			if suffix then
				highest = math.max(highest, tonumber(suffix) or 0)
			end
		end
	end
	return `b{highest + 1}`
end

function Uid.isValid(id: string): boolean
	return type(id) == "string" and string.match(id, "^b%d+$") ~= nil
end

return Uid
