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

hm.test("the base ruleset's own after_damage hook reaches the house rules", function(t)
	local a = t.actor({ id = "a_a", kind = "pc", name = "A", ext = { ["sample.ordered"] = { level = 1, stats = { agi = 1, str = 3, wit = 0 } } } })
	local b = t.actor({ id = "a_b", kind = "npc", name = "B", ext = { ["sample.ordered"] = { level = 1, stats = { agi = 0, str = 0, wit = 0 } } } })
	t.commit({ t = "resource.set", ref = "actor:a_b", plugin = "sample.ordered", name = "hp", record = { kind = "pool", current = 20, max = 20, recharge = "rest" } }, "HP")
	-- the strike is sample.ordered's action; the test kernel carries the
	-- dependency, so dispatch it there. The dice are seeded, not chosen:
	-- strike until a hard hit lands, checking the hook's answer each time.
	local hard, hits = 0, 0
	for i = 1, 16 do
		t.commit({ t = "resource.set", ref = "actor:a_b", plugin = "sample.ordered", name = "hp", record = { kind = "pool", current = 20, max = 20, recharge = "rest" } }, "HP")
		local r = t.dispatch_of("sample.ordered", "strike", { actor = "a_a", target = "a_b" })
		if r.damage > 0 then hits = hits + 1 end
		if r.damage >= 6 then
			hard = hard + 1
			t.eq(r.after, "hard hit", "the house hook saw a hit of " .. r.damage)
		else
			t.eq(r.after, nil, "no note for " .. r.damage)
		end
	end
	t.ok(hits > 0 and hard > 0, "some strikes hit (" .. hits .. "), some hard (" .. hard .. ")")
	local notes = 0
	-- the hook's events were committed by the base action: a note per hard hit
	local a_view = hm.actor("a_b")
	t.ok(a_view ~= nil, "target still there")
end)
