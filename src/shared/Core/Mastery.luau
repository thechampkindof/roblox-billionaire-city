--!strict
--[[
	Mastery: per-property level 1..100 driven by XP with diminishing returns.

	`xpForLevel(L) = round(100 * L^1.6)` is the XP required to *leave* level L.
	XP gain is scaled by `1 / (1 + windowXp / softCap)` inside a rolling window so a
	cheap business left running cannot max the tree on its own.
]]

local Money = require(script.Parent.Money)

local Mastery = {}

Mastery.MAX_LEVEL = 100

export type State = {
	xp: number, -- total lifetime XP toward the current level + progress
	lvl: number,
	windowStart: number,
	windowXp: number,
}

function Mastery.newState(level: number?): State
	return {
		xp = 0,
		lvl = math.clamp(level or 1, 1, Mastery.MAX_LEVEL),
		windowStart = 0,
		windowXp = 0,
	}
end

--[[ XP required to advance from `level` to `level + 1`. ]]
function Mastery.xpForLevel(level: number): number
	if level >= Mastery.MAX_LEVEL or level < 1 then
		return 0
	end
	return math.max(1, Money.round(100 * (level ^ 1.6)))
end

--[[ XP required to advance from level 1 to `level`. ]]
function Mastery.totalXpForLevel(level: number): number
	local target = math.clamp(level, 1, Mastery.MAX_LEVEL)
	local total = 0
	for current = 1, target - 1 do
		total += Mastery.xpForLevel(current)
	end
	return total
end

--[[ Inverse of `totalXpForLevel`: the level reached with `xp` total XP. ]]
function Mastery.levelFromXp(xp: number): number
	local remaining = math.max(0, xp)
	for level = 1, Mastery.MAX_LEVEL - 1 do
		local needed = Mastery.xpForLevel(level)
		if remaining < needed then
			return level
		end
		remaining -= needed
	end
	return Mastery.MAX_LEVEL
end

--[[ XP progress inside the current level, as `{ current, needed, fraction }`. ]]
function Mastery.progress(xp: number): { current: number, needed: number, fraction: number }
	local level = Mastery.levelFromXp(xp)
	local spent = Mastery.totalXpForLevel(level)
	local needed = Mastery.xpForLevel(level)
	if needed <= 0 then
		return { current = 0, needed = 0, fraction = 1 }
	end
	local current = math.clamp(xp - spent, 0, needed)
	return { current = current, needed = needed, fraction = current / needed }
end

--[[ Applies the soft cap to raw XP and returns the actual gain. ]]
function Mastery.applySoftCap(rawXp: number, windowXp: number, softCap: number): number
	if rawXp <= 0 then
		return 0
	end
	if softCap <= 0 then
		return rawXp
	end
	local factor = 1 / (1 + math.max(0, windowXp) / softCap)
	return rawXp * factor
end

--[[
	Adds XP to a mastery state, returning a new state and the amount actually gained.

	`windowSeconds` resets the soft-cap window when it has elapsed; the caller passes
	`os.time()` for `now`.
]]
function Mastery.gain(
	state: State,
	rawXp: number,
	now: number,
	softCap: number,
	windowSeconds: number
): (State, number)
	local windowXp = state.windowXp
	local windowStart = state.windowStart
	if windowSeconds > 0 and (windowStart == 0 or (now - windowStart) >= windowSeconds) then
		windowStart = now
		windowXp = 0
	end

	local gained = Mastery.applySoftCap(rawXp, windowXp, softCap)
	if gained <= 0 then
		return table.clone(state), 0
	end

	local xp = state.xp + Money.round(gained)
	local level = Mastery.levelFromXp(xp)
	return {
		xp = xp,
		lvl = level,
		windowStart = windowStart,
		windowXp = windowXp + gained,
	},
		gained
end

--[[ Milestone bonuses: small, permanent, and data-driven by level thresholds. ]]
function Mastery.milestoneBonus(level: number, milestones: { [number]: number }): number
	local bonus = 0
	for threshold, value in milestones do
		if level >= threshold then
			bonus += value
		end
	end
	return bonus
end

return Mastery
