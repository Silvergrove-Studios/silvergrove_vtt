-- The plugin's own tests: run with `./run.sh plugintest tests/plugins/sample.ordered`
-- and by the app's self-test. Each runs on a fresh scratch encounter.
local hm = hexmap

local function hero(t, agi, str, armour)
	return t.actor({ id = "a_hero", kind = "pc", name = "Hero", owner = "pl_1",
		ext = { [hm.id] = { level = 2, stats = { agi = agi or 3, str = str or 1, wit = 0 }, armour = armour or 0 } } })
end

hm.test("derive: defence is 10 + agility + armour, typed", function(t)
	local id = hero(t, 3, 1, 2)
	local d = hm.derived(id)
	t.eq(d.defence.total, 15, "defence")
	t.eq(#d.defence.parts, 3, "three parts")
	t.eq(d.defence.parts[2].label, "agility", "the agility part is named")
	t.eq(d.hp_max, 6 + 2 * 4 + 1, "hp_max")
	t.eq(d.label, "Level 2", "a label")
end)

hm.test("schema: bad actor data is refused", function(t)
	local ok = pcall(function()
		t.actor({ id = "a_bad", ext = { [hm.id] = { level = 0, stats = { agi = 1, str = 1, wit = 1 } } } })
	end)
	t.ok(not ok, "level 0 is refused by the schema")
end)

hm.test("conditions change the numbers and stack as declared", function(t)
	local id = hero(t)
	t.dispatch("condition", { key = "shaken", target = "actor:" .. id, value = 1 })
	t.eq(hm.derived(id).defence.total, 11, "shaken lowers the defence")
	t.dispatch("condition", { key = "shaken", target = "actor:" .. id, value = 1 })
	t.eq(#hm.effects.on("actor:" .. id, "shaken"), 1, "highest: no second shaken")
	t.dispatch("condition", { key = "prone", target = "actor:" .. id })
	-- both penalties are "status": under this ruleset's policy the worst one counts, not the sum
	t.eq(hm.derived(id).defence.total, 11, "prone and shaken are both status: only the worst counts")
	t.eq(#hm.derived(id).defence.parts, 5, "but both show in the breakdown")
	t.eq(hm.derived(id).speed, 3, "prone halves speed")
end)

hm.test("rolls go through the hooks", function(t)
	local id = hero(t, 3, 2)
	local r = t.roll_with_faces({ main = { 15 } }, "1d20", { actor = id, kind = "attack", dc = 16 })
	t.eq(r.result.total, 17, "15 + strength 2")
	t.eq(r.result.outcome, "success", "at or above the difficulty")
	t.dispatch("condition", { key = "shaken", target = "actor:" .. id })
	r = t.roll_with_faces({ main = { 15 } }, "1d20", { actor = id, kind = "attack", dc = 16 })
	t.eq(r.result.total, 15, "shaken: -2")
	t.eq(r.result.outcome, "failure", "and now a miss")
	r = t.roll_with_faces({ main = { 20 } }, "1d20", { actor = id, kind = "attack", dc = 30 })
	t.eq(r.result.outcome, "critical", "a natural 20 is a critical whatever the difficulty")
end)

hm.test("strike: a hit spends the target's hit points, armour asks first", function(t)
	local a = hero(t, 3, 2)
	local b = t.actor({ id = "a_gob", kind = "npc", name = "Goblin", owner = "pl_2",
		ext = { [hm.id] = { level = 1, stats = { agi = 0, str = 0, wit = 0 }, armour = 1 } } })
	t.dispatch("setup", { actor = a })
	t.dispatch("setup", { actor = b })
	t.eq(hm.resources.get("actor:" .. b, "hp").current, 10, "goblin starts at 10")
	-- the dice stream is seeded (7); whatever it gives, the bookkeeping must hold
	local out = t.dispatch("strike", { actor = a, target = b }, { { spend = true } })
	local hp = hm.resources.get("actor:" .. b, "hp").current
	if out.outcome == "failure" then
		t.eq(hp, 10, "a miss leaves it whole")
	else
		t.eq(hp, math.max(0, 10 - out.damage), "a hit took the damage")
		t.eq(hm.resources.get("actor:" .. b, "armour").marked, 1, "the armour slot was spent")
	end
end)

hm.test("rest refills and logs", function(t)
	local a = hero(t)
	t.dispatch("setup", { actor = a })
	t.commit(hm.resources.spend("actor:" .. a, "hp", 5), "hurt")
	t.eq(hm.resources.get("actor:" .. a, "hp").current, 10, "hurt")
	local out = t.dispatch("rest", {})
	t.eq(hm.resources.get("actor:" .. a, "hp").current, 15, "rested")
	t.ok(out.refilled >= 1, "something refilled")
end)

hm.test("state: the ruleset keeps encounter-scoped data", function(t)
	t.commit(hm.state.set("encounter", "", { doom = 3 }), "doom")
	t.eq(hm.state.get("encounter").doom, 3, "read back")
end)
