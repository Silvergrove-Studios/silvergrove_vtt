extends TestCase
## Performance budgets (docs/plugin-api-plan.md, §5.1), asserted so a
## regression fails CI rather than a session: effect expiry over 500
## effects, a hook round-trip into Lua, a full Player projection, a
## checkpoint and a restore, a bulk op over a horde. Budgets are for a
## laptop; shared CI runners get three times as long, phones and
## emulators are skipped.


## The budget in ms as this machine should meet it.
func _budget(ms: float) -> float:
	if OS.has_environment("CI") or OS.has_environment("GITHUB_ACTIONS"):
		return ms * 3.0
	return ms


func _crowd(n: int) -> RulesKernel:
	var st := EncounterState.new(Encounter.create("Perf"))
	st.encounter.doc.rng = {"seed": 1, "index": 0}
	var k := RulesKernel.new(st)
	SampleRules.new().install(k)
	var m := _chapel()
	st.attach_map(m)
	var sc := Encounter.new_scene(m, "ground", "G", "ruined_chapel.hexmap")
	var events := [{"t": "scene.add", "scene": sc}, {"t": "player.add", "player": {"id": "pl_1", "name": "Ana", "color": "#4f9cf6"}}]
	var g := m.grid
	for i in n:
		events.append({"t": "actor.add", "actor": {"id": "a_%d" % i, "kind": "pc" if i % 4 == 0 else "npc", "name": "A%d" % i, "owner": "pl_1" if i % 4 == 0 else "",
			"ext": {"sample": {"level": 1 + i % 5, "stats": {"agi": i % 4, "str": i % 3, "wit": 0}}}}})
		events.append({"t": "token.add", "scene": sc.id, "token": Encounter.new_token("A%d" % i, g.cell_center(Vector2i(i % 12, i / 12)), {"id": "t_%d" % i, "actor": "a_%d" % i})})
		events.append(Resources.set_event("actor:a_%d" % i, "sample", "hp", Resources.pool(10, 10, "rest")))
	k.commit(events, "Crowd")
	return k


func test_effect_expiry_budget() -> void:
	if OS.has_feature("mobile"):
		skip("budgets are for desktops")
		return
	var k := _crowd(100)
	var st := k.state
	var events := []
	for i in 500:
		events.append({"t": "effect.apply", "effect": {"id": "e_%d" % i, "on": "actor:a_%d" % (i % 100), "plugin": "sample", "key": "k%d" % (i % 7), "label": "Fx",
			"duration": {"kind": "turn_end", "of": "t_%d" % (i % 100), "turns": 1} if i % 2 == 0 else {"kind": "rounds", "rounds": 1},
			"changes": [{"path": "defence", "mode": "add", "value": -1, "type": "status"}]}})
	k.commit(events, "Effects")
	check(st.encounter.effects.size() == 500, "500 effects on 100 actors")
	var t0 := Time.get_ticks_usec()
	var gone := Effects.expire(st, {"kind": "round"})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	say.call("  expiry over 500 effects computed in %.2f ms (%d end)" % [ms, gone.size()])
	check(gone.size() == 250 and ms < _budget(10.0), "expiry over 500 effects is computed within 10 ms (%.2f)" % ms)
	t0 = Time.get_ticks_usec()
	k.commit(gone, "Round end")
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	say.call("  …and applied with re-derivation in %.1f ms" % ms)
	check(st.encounter.effects.size() == 250 and ms < _budget(150.0), "applying 250 removals with re-derivation stays within budget (%.1f ms)" % ms)


func test_projection_budget() -> void:
	if OS.has_feature("mobile"):
		skip("budgets are for desktops")
		return
	var k := _crowd(60)
	for i in 30:
		k.commit([{"t": "log.add", "entry": {"id": "n_%d" % i, "kind": "note", "text": "note %d" % i, "audience": "all"}}], "Note")
	var t0 := Time.get_ticks_usec()
	var v := {}
	for i in 20:
		v = Views.project(k, null, "pl_1", Views.ROLE_PLAYER)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	say.call("  a Player projection of 60 actors: %.2f ms" % ms)
	check(v.actors.size() == 15 and ms < _budget(5.0), "a full Player projection (15 visible of 60) stays under 5 ms (%.2f)" % ms)


func test_checkpoint_and_bulk_budgets() -> void:
	if OS.has_feature("mobile"):
		skip("budgets are for desktops")
		return
	var k := _crowd(100)
	var st := k.state
	var t0 := Time.get_ticks_usec()
	var cp := k.checkpoint("Perf")
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	say.call("  a checkpoint of 100 actors: %.1f ms" % ms)
	check(cp != "" and ms < _budget(30.0), "marking a checkpoint stays under 30 ms (%.1f)" % ms)
	var refs := []
	for i in 100:
		refs.append("token:t_%d" % i)
	t0 = Time.get_ticks_usec()
	var r := Bulk.run(k, refs, {"kind": "resource", "plugin": "sample", "name": "hp", "delta": -3})
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	say.call("  bulk damage to 100 tokens: %.1f ms" % ms)
	check(r.ok and ms < _budget(120.0), "a bulk op over 100 targets stays under 120 ms (%.1f)" % ms)
	t0 = Time.get_ticks_usec()
	check(k.restore_checkpoint(cp) == "", "restore")
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	say.call("  restore with full re-derivation: %.1f ms" % ms)
	check(Resources.get_record(st, "actor:a_0", "sample", "hp").current == 10 and ms < _budget(150.0), "a restore of 100 actors stays under 150 ms (%.1f)" % ms)


func test_lua_hook_round_trip_budget() -> void:
	if OS.has_feature("mobile"):
		skip("budgets are for desktops")
		return
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := EncounterState.new(Encounter.create("Hooks"))
	st.encounter.doc.rng = {"seed": 2, "index": 0}
	var k := RulesKernel.new(st)
	var host := PluginHost.new(k)
	check(host.load_dir("res://tests/plugins/sample.ordered") == "", "the plugin loads")
	k.commit([{"t": "actor.add", "actor": {"id": "a_1", "kind": "pc", "name": "One", "ext": {"sample.ordered": {"level": 1, "stats": {"agi": 1, "str": 1, "wit": 0}}}}}], "Actor")
	var samples := []
	for i in 200:
		var t0 := Time.get_ticks_usec()
		k.hooks.run_sync("before_roll", {"spec": {"expr": "1d20", "parts": []}, "ctx": {"actor": "a_1", "kind": "attack"}})
		samples.append((Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	var median: float = samples[samples.size() / 2]
	say.call("  a hook round-trip into Lua: median %.3f ms, worst %.3f ms" % [median, samples[samples.size() - 1]])
	check(median < _budget(0.5), "a hook round-trip into Lua stays under 0.5 ms median (%.3f)" % median)


func test_phase_7b_budgets() -> void:
	if OS.has_feature("mobile"):
		skip("budgets are for desktops")
		return
	# a template on a square map, and picking a target among a crowd
	var st := EncounterState.new(Encounter.create("Perf sq"))
	var k := RulesKernel.new(st)
	SampleRules.new().install(k)
	var m := HexMap.load_file(example("cellar.hexmap"))
	st.attach_map(m)
	var sc := Encounter.new_scene(m, "ground", "C", "cellar.hexmap")
	var events := [{"t": "scene.add", "scene": sc}]
	for i in 60:
		events.append({"t": "token.add", "scene": sc.id, "token": Encounter.new_token("T%d" % i, m.grid.cell_center(Vector2i(2 + i % 10, 2 + i / 10)), {"id": "t_%d" % i})})
	k.commit(events, "Crowd")
	var t0 := Time.get_ticks_usec()
	var circle := k.map.template(sc.id, {"shape": "circle", "at": "token:t_25", "radius": 4, "blocked_by_walls": true})
	var cone := k.map.template(sc.id, {"shape": "cone", "at": "token:t_25", "direction": 45, "length": 8, "angle": 90})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(circle.cells.size() > 10 and cone.cells.size() > 5 and ms < _budget(8.0), "two wall-clipped templates on a square map stay under 8 ms (%.2f)" % ms)
	t0 = Time.get_ticks_usec()
	for i in 200:
		MapQuery.pick_target(st, sc.id, {"kind": "token"}, m.grid.cell_center(Vector2i(2 + i % 10, 2 + (i / 10) % 6)), false)
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	check(ms < _budget(20.0), "200 target picks among 60 tokens stay under 20 ms (%.2f)" % ms)
	# a client's compendium page over 1,000 entries, and a picker over them
	var c := Compendium.new()
	var up := c.user_pack("big", "Big", "p")
	for i in 1000:
		c.put("spells", {"id": "s%d" % i, "name": "Spell %d" % i, "level": i % 10, "school": ["fire", "ice", "air"][i % 3], "text": "words " + str(i)}, "big")
	t0 = Time.get_ticks_usec()
	var page := c.query_for("spells", {"filter": {"level": {"min": 2, "max": 4}, "school": "fire"}, "text": "spell", "sort": "name", "per_page": 25}, false)
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	check(page.total == 100 and page.entries.size() == 25 and ms < _budget(15.0), "a player's page of a 1,000-entry collection stays under 15 ms (%.2f)" % ms)
	var r := ViewRenderer.new()
	r.comp_source = func(collection: String, req: Dictionary, on_reply: Callable) -> void:
		on_reply.call({"collection": collection, "page": c.query_for(collection, req.get("query", {}), false)})
	root.add_child(r)
	t0 = Time.get_ticks_usec()
	r.render({"type": "picker", "collection": "spells", "per_page": 50, "on_pick": {}}, {})
	ms = (Time.get_ticks_usec() - t0) / 1000.0
	check(ms < _budget(25.0), "a picker's first page over 1,000 entries renders under 25 ms (%.2f)" % ms)
	r.queue_free()
	await tree.process_frame


## Sight for a party of four: by day each sees the whole map in its line of
## sight (every wall on it counts), in the dark its darkvision and the lit
## places in its line of sight — the host works it out for every screen at
## every move.
func test_sight_budget() -> void:
	if OS.has_feature("mobile"):
		skip("budgets are for desktops")
		return
	var m := _chapel()
	var st := EncounterState.new(Encounter.create("Sight"))
	st.attach_map(m)
	var sc := Encounter.new_scene(m, "ground", "G", "ruined_chapel.hexmap")
	st.apply({"t": "scene.add", "scene": sc})
	var g := m.grid
	var eyes := []
	for at in [Vector2i(3, 7), Vector2i(8, 7), Vector2i(12, 2), Vector2i(18, 13)]:
		var tk := Encounter.new_token("E", g.cell_center(g.offset_to_axial(at.x, at.y)), {"owner": "pl_1", "vision": {"radius": 6, "dark_radius": 60, "units": "ft"}, "light": {"bright": 2, "dim": 4}})
		st.apply({"t": "token.add", "scene": sc.id, "token": tk})
		eyes.append(tk)
	for light in ["daylight", "dark"]:
		st.apply({"t": "scene.set", "id": sc.id, "changes": {"light": light}})
		var v := {}
		var t0 := Time.get_ticks_usec()
		for i in 5:
			v = Vision.of(st, sc.id, eyes)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / 5.0
		say.call("  what four tokens see, %s: %d cells, %d polygons, %.1f ms" % [light, (v.cells as Array).size(), (v.polygons as Array).size(), ms])
		check(not (v.cells as Array).is_empty() and ms < _budget(25.0), "four tokens' sight %s stays under 25 ms (%.1f)" % [light, ms])
