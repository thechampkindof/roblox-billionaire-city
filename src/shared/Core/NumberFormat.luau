--!strict
--[[
	Number formatting for money and statistics.

	Suffix ladder follows the genre convention used by idle/tycoon games and the
	brief (K, M, B, T, Qa, Qi...). Values stay exact integers everywhere in simulation;
	formatting is presentation-only and never feeds back into economy math.
]]

local NumberFormat = {}

-- Short-scale suffixes. Index 1 = 10^3 (thousand).
local SUFFIXES = {
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"UDc",
	"DDc",
	"TDc",
	"QaDc",
	"QiDc",
	"SxDc",
	"SpDc",
	"OcDc",
	"NoDc",
	"Vg",
}

export type Options = {
	-- Significant digits shown below the unit threshold.
	decimals: number?,
	-- Always show at least one decimal ("1.0K") instead of "1K".
	alwaysDecimal: boolean?,
	-- Prefix, e.g. "$".
	prefix: string?,
}

local function roundTo(value: number, decimals: number): number
	local factor = 10 ^ decimals
	return math.floor(value * factor + 0.5) / factor
end

--[[ `short(1500)` -> `1.5K`; `short(999)` -> `999`; `short(0)` -> `0`. ]]
function NumberFormat.short(value: number, options: Options?): string
	local opts = options or {}
	local prefix = opts.prefix or ""
	local decimals = opts.decimals or 1
	local alwaysDecimal = opts.alwaysDecimal or false

	if value ~= value then
		return prefix .. "0"
	end
	local negative = value < 0
	local magnitude = math.abs(value)
	local sign = if negative then "-" else ""

	if magnitude < 1000 then
		local text = if magnitude == math.floor(magnitude)
			then tostring(math.floor(magnitude))
			else string.format("%.1f", magnitude)
		return sign .. prefix .. text
	end

	local tier = math.floor(math.log(magnitude, 1000))
	tier = math.clamp(tier, 1, #SUFFIXES)
	local scaled = magnitude / (1000 ^ tier)
	-- Rounding can push 999.95 -> 1000; promote a tier instead of printing "1000K".
	if scaled >= 999.95 and tier < #SUFFIXES then
		tier += 1
		scaled = magnitude / (1000 ^ tier)
	end

	local text = string.format("%." .. tostring(decimals) .. "f", roundTo(scaled, decimals))
	-- Trim trailing ".0" unless the caller wants it kept.
	if not alwaysDecimal and string.sub(text, -2) == ".0" then
		text = string.sub(text, 1, -3)
	end
	-- Drop redundant trailing zeros ("1.50" -> "1.5", "1.00" -> "1").
	text = string.gsub(text, "%.?0+$", "")
	if text == "" then
		text = "1"
	end
	return sign .. prefix .. text .. SUFFIXES[tier]
end

--[[ Exact grouped format: `1234567` -> `1,234,567`. ]]
function NumberFormat.full(value: number, prefix: string?): string
	local text = tostring(math.floor(math.abs(value) + 0.5))
	local digits = #text
	local groups: { string } = {}
	local index = digits
	while index > 0 do
		local start = math.max(1, index - 2)
		table.insert(groups, 1, string.sub(text, start, index))
		index = start - 1
	end
	local formatted = table.concat(groups, ",")
	return (prefix or "") .. (if value < 0 then "-" else "") .. formatted
end

--[[ Money is the most common case: `money(1234)` -> `$1.2K`. ]]
function NumberFormat.money(value: number, options: Options?): string
	local opts = options or {}
	return NumberFormat.short(value, {
		decimals = opts.decimals,
		alwaysDecimal = opts.alwaysDecimal,
		prefix = opts.prefix or "$",
	})
end

--[[ Percentage with a fixed precision: `percent(0.127)` -> `12.7%`. ]]
function NumberFormat.percent(fraction: number, decimals: number?): string
	return string.format("%." .. tostring(decimals or 1) .. "f%%", fraction * 100)
end

--[[ Duration for UI: `formatDuration(3725)` -> `1h 2m`. ]]
function NumberFormat.duration(seconds: number): string
	if seconds <= 0 then
		return "0s"
	end
	local total = math.floor(seconds)
	local days = math.floor(total / 86400)
	local hours = math.floor((total % 86400) / 3600)
	local minutes = math.floor((total % 3600) / 60)
	local secs = total % 60
	if days > 0 then
		return `{days}d {hours}h`
	elseif hours > 0 then
		return `{hours}h {minutes}m`
	elseif minutes > 0 then
		return `{minutes}m {secs}s`
	end
	return `{secs}s`
end

return NumberFormat
