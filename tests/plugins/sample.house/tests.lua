local hm = hexmap

hm.test("the house rules classify rolls, not the base ruleset", function(t)
	local id = t.actor({ id = "a_1", kind = "pc", name = "One", ext = { ["sample.ordered"] = { level = 1, stats = { agi = 1, str = 0, wit = 0 } } } })
	local r = t.roll_with_faces({ main = { 19 } }, "1d20", { actor = id, kind = "attack", dc = 10 })
	t.eq(r.result.outcome, "critical", "19 is a critical under the house rules")
	t.eq(r.result.house, true, "…classified here")
	r = t.roll_with_faces({ main = { 1 } }, "1d20", { actor = id, kind = "attack", dc = 1 })
	t.eq(r.result.outcome, "fumble", "a natural 1 fumbles")
	r = t.roll_with_faces({ main = { 12 } }, "1d20", { actor = id, kind = "attack", dc = 10, dark = true })
	t.eq(r.result.total, 10, "12 + str 0 - 2 for the dark: both before_roll handlers ran")
end)
