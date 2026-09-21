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
