extends TestCase
## The red-team pass over the plugin sandbox (docs/plugin-api-plan.md,
## §5.1): a hostile plugin, loaded through the PluginHost like any other,
## tries to get out, to break the host, to break another plugin or to
## hang the table. Each attempt must be contained with a readable error
## and the kernel must keep working afterwards. rules_lua.gd covers the
## bare VM (missing libraries, budgets, read-only globals); this covers
## the plugin API on top of it.


func _host() -> Array:
	var st := EncounterState.new(Encounter.create("Sandbox"))
	st.encounter.doc.rng = {"seed": 11, "index": 0}
	var k := RulesKernel.new(st)
	var host := PluginHost.new(k)
	host.instruction_budget = 300_000
	host.memory_budget = 32 * 1024 * 1024
	return [k, host]


func _load(host: PluginHost, id: String, src: String, caps: Array = ["state", "prompts", "log", "actions", "effects", "resources", "dice"]) -> String:
	return host.load_source({"id": id, "version": "1", "api": 1, "name": id, "capabilities": caps}, [["main.lua", src]])


func test_escape_attempts_are_contained() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var parts := _host()
	var k: RulesKernel = parts[0]
	var host: PluginHost = parts[1]
	var failures := []
	host.plugin_failed.connect(func(id: String, where: String, msg: String) -> void: failures.append("%s/%s: %s" % [id, where, msg]))
	# the host table is gone from the globals; the library is a local
	check(_load(host, "t.probe", """
		local hm = hexmap
		hm.actions.register("probe", { run = function()
			return { host = tostring(__host), rawhost = tostring(rawget(_G, "__host")), io = tostring(io), os = tostring(os),
				debug = tostring(debug), load = tostring(load), dump = tostring(string.dump), require = tostring(require),
				collect = tostring(collectgarbage), genv = tostring(getfenv) }
		end })
	""") == "", "the probe loads")
	var pc := host.dispatch("t.probe", "probe")
	check(pc.status == PluginHost.PluginCall.OK, "probe ran: " + pc.error)
	for key in ["host", "rawhost", "io", "os", "debug", "load", "dump", "require", "genv"]:
		check(str(pc.value.get(key)) == "nil", "%s is not reachable" % key)
	# tampering with the library or the standard libraries after seal
	check(_load(host, "t.tamper", """
		local hm = hexmap
		hm.actions.register("strlib", { run = function() string.rep = function() return "owned" end return "changed" end })
		hm.actions.register("strmeta", { run = function() getmetatable("").__index.rep = function() return "owned" end return "changed" end })
		hm.actions.register("global", { run = function() hexmap = nil return "changed" end })
		hm.actions.register("newglobal", { run = function() rawset(_G, "leak", 1) return "changed" end })
		hm.actions.register("mathlib", { run = function() math.random = nil return "changed" end })
		hm.actions.register("ok", { run = function() return string.rep("a", 3) end })
	""") == "", "the tamperer loads")
	for a in ["strlib", "strmeta", "global", "newglobal", "mathlib"]:
		var r := host.dispatch("t.tamper", a)
		check(r.status == PluginHost.PluginCall.ERROR and r.error != "", "%s: refused with an error (%s)" % [a, r.error])
	check(host.dispatch("t.tamper", "ok").value == "aaa", "and the library still works")
	# a plugin cannot reach into another: separate VMs, separate globals
	check(_load(host, "t.other", """
		local hm = hexmap
		hm.actions.register("peek", { run = function() return { other = tostring(rawget(_G, "secret")) } end })
	""") == "" and _load(host, "t.secretive", """
		local hm = hexmap
		secret = 42
		hm.actions.register("have", { run = function() return secret end })
	""") == "", "two more load")
	check(host.dispatch("t.other", "peek").value.other == "nil" and int(host.dispatch("t.secretive", "have").value) == 42, "one plugin's globals are not another's")
	# capabilities: what the manifest did not grant is refused at the host
	check(_load(host, "t.nocap", """
		local hm = hexmap
		hm.actions.register("note", { run = function() hm.log("hi") end })
		hm.actions.register("state", { run = function() hm.commit(hm.state.set("encounter", "", { x = 1 }), "x") end })
		hm.actions.register("ask", { run = function() return hm.prompt("pl_1", { title = "?" }) end })
		hm.actions.register("bulk", { run = function() return hm.bulk.run({}, { kind = "remove" }) end })
		hm.actions.register("cp", { run = function() return hm.checkpoint.mark("x") end })
	""", ["actions"]) == "", "a plugin with only 'actions' loads")
	for a in ["note", "state", "ask", "bulk", "cp"]:
		var r := host.dispatch("t.nocap", a)
		check(r.status == PluginHost.PluginCall.ERROR and r.error.contains("capability"), "%s without the capability: %s" % [a, r.error])
	check(k.state.encounter.log.is_empty() and k.state.encounter.doc.state.ext.is_empty() and k.state.encounter.checkpoints.is_empty(), "nothing got through")
	check(failures.size() >= 5, "every refusal was reported to the table: %d" % failures.size())


func test_bad_data_across_the_bridge() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var parts := _host()
	var k: RulesKernel = parts[0]
	var host: PluginHost = parts[1]
	check(_load(host, "t.data", """
		local hm = hexmap
		hm.schema.define("actor", { type = "object" })
		hm.derive(function(view)
			local mode = (view.ext[hm.id] or {}).mode or "fine"
			if mode == "cycle" then local t = { a = 1 } t.self = t return t end
			if mode == "deep" then local t = {} local c = t for i = 1, 100 do c.n = {} c = c.n end return t end
			if mode == "fn" then return { f = function() end } end
			if mode == "number" then return 42 end
			if mode == "boom" then error("derive explodes") end
			if mode == "spin" then while true do end end
			if mode == "yield" then coroutine.yield({ kind = "prompt" }) end
			return { fine = true, level = (view.ext[hm.id] or {}).level or 0 }
		end)
		hm.on("before_roll", function(p)
			if p.ctx.mode == "cycle" then p.self = p end
			if p.ctx.mode == "fn" then p.spec.parts = function() end end
			if p.ctx.mode == "boom" then error("hook explodes") end
			if p.ctx.mode == "number" then return 7 end
			return p
		end)
		hm.actions.register("big", { run = function() return { s = string.rep("x", 200000) } end })
		hm.actions.register("badevent", { run = function() hm.commit({ t = "actor.set", id = "nobody", changes = {} }, "x") end })
		hm.actions.register("badevents", { run = function() hm.commit({ { t = "log.add", entry = { id = "n_ok", kind = "note", text = "first" } }, { t = "nonsense" } }, "x") end })
		hm.actions.register("keytable", { run = function() return { [{}] = 1 } end })
		hm.actions.register("nilkey", { run = function() return { a = nil, b = 2 } end })
	""") == "", "the plugin loads")
	var failed := []
	k.ruleset_failed.connect(func(id: String, msg: String) -> void: failed.append(msg))
	host.plugin_failed.connect(func(_id: String, where: String, msg: String) -> void: failed.append(where + ": " + msg))
	var add := func(mode: String) -> String:
		return k.commit([{"t": "actor.add", "actor": {"id": "a_" + mode, "ext": {"t.data": {"mode": mode, "level": 3}}}}], mode)
	check(add.call("fine") == "" and k.state.encounter.actor("a_fine").derived["t.data"].fine == true, "a sane derive lands")
	for mode in ["cycle", "deep", "fn", "number", "boom", "spin", "yield"]:
		failed.clear()
		var why: String = add.call(mode)
		var d: Dictionary = k.state.encounter.actor("a_" + mode).derived.get("t.data", {})
		check(why == "" and not d.has("self") and not failed.is_empty(), "derive '%s' is contained: the actor is added, the block is empty or safe, the failure reported (%s)" % [mode, failed])
	check(k.state.encounter.actor("a_fine").derived["t.data"].fine == true, "other actors still derive")
	# hooks that misbehave: the roll goes on, the failure is reported
	for mode in ["cycle", "fn", "boom", "number"]:
		failed.clear()
		var r := k.roll("1d20", {"actor": "a_fine", "mode": mode}, "Roll")
		check(not r.is_empty() and r.result.total >= 1, "a roll survives a '%s' hook: %s" % [mode, k.last_veto])
	# actions: big values cross, bad events are refused whole, odd tables are sanitised
	var pc := host.dispatch("t.data", "big")
	check(pc.status == PluginHost.PluginCall.OK and str(pc.value.s).length() == 200000, "a large string crosses")
	pc = host.dispatch("t.data", "badevent")
	check(pc.status == PluginHost.PluginCall.ERROR and pc.error.contains("nobody"), "a bad event is a readable error: " + pc.error)
	pc = host.dispatch("t.data", "badevents")
	check(pc.status == PluginHost.PluginCall.ERROR and k.state.encounter.log.filter(func(x: Dictionary) -> bool: return x.get("id", "") == "n_ok").is_empty(), "a bad batch applies nothing: " + pc.error)
	pc = host.dispatch("t.data", "keytable")
	check(pc.status == PluginHost.PluginCall.ERROR and pc.error.contains("key"), "a table key cannot cross: " + pc.error)
	pc = host.dispatch("t.data", "nilkey")
	check(pc.status == PluginHost.PluginCall.OK and pc.value.b == 2, "nil values simply vanish")
	# the kernel and the document are intact after all of it
	check(k.commit([{"t": "actor.set", "id": "a_fine", "changes": {"ext/t.data/level": 5}}], "Level") == "" and k.state.encounter.actor("a_fine").derived["t.data"].level == 5, "the kernel works on")


func test_runaway_plugins_do_not_take_the_table_down() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var parts := _host()
	var k: RulesKernel = parts[0]
	var host: PluginHost = parts[1]
	check(_load(host, "t.runaway", """
		local hm = hexmap
		hm.actions.register("spin", { run = function() while true do end end })
		hm.actions.register("alloc", { run = function() local t = {} for i = 1, 1e8 do t[i] = string.rep("y", 4096) end end })
		hm.actions.register("recurse", { run = function() local function f(n) return f(n + 1) + 1 end return f(0) end })
		hm.actions.register("commitstorm", { run = function()
			for i = 1, 100000 do hm.commit({ t = "log.add", entry = { id = "s_" .. i, kind = "note", text = "storm" } }, "storm") end
		end })
		hm.actions.register("rollstorm", { run = function() for i = 1, 100000 do hm.dice.roll("1d20", {}, "storm") end end })
		hm.actions.register("fine", { run = function() return "still here" end })
	""") == "", "loads")
	for a in ["spin", "alloc", "recurse"]:
		var t0 := Time.get_ticks_msec()
		var pc := host.dispatch("t.runaway", a)
		var ms := Time.get_ticks_msec() - t0
		check(pc.status == PluginHost.PluginCall.ERROR and ms < 5000, "%s is cut off in %d ms: %s" % [a, ms, pc.error])
	host.call_ms_budget = 500
	var t0 := Time.get_ticks_msec()
	var pc := host.dispatch("t.runaway", "commitstorm")
	var ms := Time.get_ticks_msec() - t0
	say.call("  a commit storm ran %d notes in %d ms before the time budget cut it" % [k.state.encounter.log.size(), ms])
	check(pc.status == PluginHost.PluginCall.ERROR and (pc.error.contains("time") or pc.error.contains("budget")) and ms < 1500, "a commit storm is cut off by a budget (%d ms): %s" % [ms, pc.error])
	check(k.log.can_undo() and k.state.encounter.log.size() > 0, "what it committed before the cut is in the log, undoable")
	var n := k.state.encounter.log.size()
	t0 = Time.get_ticks_msec()
	pc = host.dispatch("t.runaway", "rollstorm")
	ms = Time.get_ticks_msec() - t0
	say.call("  a roll storm ran %d rolls in %d ms" % [k.state.encounter.log.size() - n, ms])
	check(pc.status == PluginHost.PluginCall.ERROR and (pc.error.contains("time") or pc.error.contains("budget")) and ms < 1500 and k.state.encounter.log.size() > n, "a roll storm is cut off too (%d ms, %d rolls): %s" % [ms, k.state.encounter.log.size() - n, pc.error])
	check(host.dispatch("t.runaway", "fine").value == "still here", "the plugin still answers afterwards")
	check(k.commit([{"t": "clock.set", "changes": {"minute": 1}}], "tick") == "", "and so does the kernel")
