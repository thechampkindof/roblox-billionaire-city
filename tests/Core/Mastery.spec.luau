--!strict
local Framework = require(script.Parent.Parent.Framework)
local Mastery = require(script.Parent.Parent.Parent.src.shared.Core.Mastery)

Framework.test("mastery XP curve increases with level", function()
	local previous = 0
	for level = 1, 99 do
		local needed = Mastery.xpForLevel(level)
		Framework.greaterThan(needed, previous, `xp for level {level}`)
		previous = needed
	end
	Framework.equal(Mastery.xpForLevel(100), 0, "level 100 is terminal")
end)

Framework.test("levelFromXp inverts totalXpForLevel", function()
	for level = 1, 20 do
		local xp = Mastery.totalXpForLevel(level)
		Framework.equal(Mastery.levelFromXp(xp), level, `round trip at level {level}`)
		if level > 1 then
			Framework.equal(Mastery.levelFromXp(xp - 1), level - 1, `one XP short at level {level}`)
		end
	end
	Framework.equal(Mastery.levelFromXp(1e12), 100, "huge XP caps at 100")
	Framework.equal(Mastery.levelFromXp(-5), 1, "negative XP floors at 1")
end)

Framework.test("progress reports the fraction inside the current level", function()
	local progress = Mastery.progress(0)
	Framework.equal(progress.current, 0)
	Framework.equal(progress.needed, Mastery.xpForLevel(1))
	Framework.near(progress.fraction, 0)
end)

Framework.test("soft cap halves gains at the cap and shrinks further beyond", function()
	Framework.near(Mastery.applySoftCap(100, 0, 1000), 100)
	Framework.near(Mastery.applySoftCap(100, 1000, 1000), 50)
	Framework.near(Mastery.applySoftCap(100, 3000, 1000), 25)
	Framework.equal(Mastery.applySoftCap(0, 500, 1000), 0)
	Framework.equal(Mastery.applySoftCap(-10, 500, 1000), 0)
end)

Framework.test("gain advances levels and resets the soft-cap window", function()
	local state = Mastery.newState(1)
	state, _ = Mastery.gain(state, Mastery.xpForLevel(1), 1000, 10_000, 3600)
	Framework.equal(state.lvl, 2)
	Framework.equal(state.windowStart, 1000)

	local capped, gained = Mastery.gain(state, 2000, 1100, 2000, 3600)
	Framework.greaterThan(gained, 0)
	Framework.near(gained, 2000 / (1 + state.windowXp / 2000), 1e-6, "soft cap applied")

	local reset, _ = Mastery.gain(capped, 100, 5000, 2000, 3600)
	Framework.equal(reset.windowStart, 5000, "window rolled over")
	Framework.near(reset.windowXp, 100, 1e-6, "window XP reset")
end)

Framework.test("mastery milestones add their bonuses once reached", function()
	local milestones = { [5] = 0.02, [10] = 0.03, [25] = 0.05 }
	Framework.near(Mastery.milestoneBonus(1, milestones), 0)
	Framework.near(Mastery.milestoneBonus(5, milestones), 0.02)
	Framework.near(Mastery.milestoneBonus(12, milestones), 0.05)
	Framework.near(Mastery.milestoneBonus(100, milestones), 0.1)
end)
