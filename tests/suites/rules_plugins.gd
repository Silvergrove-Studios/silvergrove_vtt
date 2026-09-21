extends TestCase
## Phase 2: the plugin host. Manifests, loading, the hm.* API from the Lua
## side, hooks that pause on a prompt, actions, capability gates, failure
## isolation, the sandbox red team, and the sample plugin's own tests.
## Skipped where the runtime is not built in (phones).

const MANIFEST := {"id": "t.one", "version": "0.1.0", "api": 1, "name": "Test one",
	"capabilities": ["state", "prompts", "log", "actions", "effects", "resources", "dice"], "policy": {"status": "best"}}


func _kernel() -> RulesKernel:
	var st := EncounterState.new(Encounter.create("plugins"))
	st.encounter.doc.rng = {"seed": 99, "index": 0}
	return RulesKernel.new(st)


func _load(host: PluginHost, source: String, manifest: Dictionary = MANIFEST) -> String:
	return host.load_source(manifest, [["main.lua", source]])


func test_plugin_manifests() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var host := PluginHost.new(_kernel())
	check(_load(host, "", {"version": "1", "api": 1, "name": "x"}).contains("manifest"), "a manifest without an id is refused")
	check(_load(host, "", {"id": "1bad", "version": "1", "api": 1, "name": "x"}).contains("manifest"), "a bad id is refused")
	check(_load(host, "", {"id": "t.api", "version": "1", "api": 2, "name": "x"}).contains("manifest"), "a future api is refused")
	check(_load(host, "", {"id": "t.cap", "version": "1", "api": 1, "name": "x", "capabilities": ["network"]}).contains("manifest"), "an unknown capability is refused")
	check(_load(host, "", {"id": "t.dep", "version": "1", "api": 1, "name": "x", "depends": ["t.missing"]}).contains("depends"), "a missing dependency is refused")
	check(_load(host, "function x( end", {"id": "t.syntax", "version": "1", "api": 1, "name": "x"}) != "" and not host.plugins.has("t.syntax"), "a syntax error refuses the load and leaves nothing behind")
	check(_load(host, "", {"id": "t.ok", "version": "1", "api": 1, "name": "x"}) == "" and host.plugins.has("t.ok"), "a minimal plugin loads")
	check(_load(host, "", {"id": "t.ok", "version": "1", "api": 1, "name": "x"}).contains("already"), "not twice")
	host.unload("t.ok")
	check(not host.plugins.has("t.ok") and host.kernel.rulesets.is_empty(), "unload drops it from the kernel")
	var found := PluginHost.discover(["res://tests/plugins"])
	check(found.size() >= 2 and str(found[0].id) == "sample.focus" and str(found[1].id) == "sample.ordered", "discover() finds the sample plugins, sorted: %s" % [found.map(func(m): return m.id)])


func test_plugin_api_from_lua() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var k := _kernel()
	var host := PluginHost.new(k)
	var failures := []
	host.plugin_failed.connect(func(id: String, where: String, msg: String) -> void: failures.append([id, where, msg]))
	var why := _load(host, """
		local hm = hexmap
		hm.schema.define("actor", { type = "object", required = { "agi" }, properties = { agi = { type = "integer" } }, additionalProperties = false })
		hm.derive(function(view)
			local d = view.ext[hm.id] or { agi = 0 }
			return { defence = hm.num({ { label = "base", type = "base", value = 10 }, { label = "agi", type = "ability", value = d.agi } }),
				tokens = #view.tokens, kind = view.kind, empty = {}, list = { 1, 2 } }
		end)
		hm.on("before_roll", function(p)
			table.insert(p.spec.parts, { label = "lucky", type = "status", value = 1 })
			if p.ctx.kind == "attack" then table.insert(p.spec.parts, { label = "attack", type = "status", value = 3 }) end
			return p
		end)
		hm.on("after_roll", function(p) p.result.outcome = p.result.total >= 10 and "hit" or "miss" return p end)
		hm.on("ask", function(p)
			local answer = hm.prompt("pl_1", { question = "really?" })
			p.answer = answer
			return p
		end)
		hm.on("ask", function(p) p.second = true return p end)
		hm.actions.register("poke", { label = "Poke", cost = { actions = 1 }, run = function(ctx)
			local a = hm.actor(ctx.actor)
			local ev = hm.effects.apply({ on = "actor:" .. ctx.actor, key = "poked", value = 1, stack = "highest",
				changes = { { path = "defence", mode = "add", value = -1, type = "status" } } })
			hm.commit(ev, "Poked")
			local ans = hm.prompt(a.owner, { question = "ouch?" })
			hm.commit(hm.state.set("encounter", "", { last = ans.word }), "Remember")
			hm.log("poked " .. a.name, "all")
			return { was = hm.value(hm.derived(ctx.actor).defence), now = hm.value(hm.derived(ctx.actor).defence), word = ans.word,
				res = hm.resources.get("actor:" .. ctx.actor, "hp"), none = hm.resources.get("actor:" .. ctx.actor, "nope") }
		end })
		hm.actions.register("setup", { run = function(ctx)
			hm.commit(hm.resources.set("actor:" .. ctx.actor, "hp", hm.resources.pool(4, 9, "rest")), "hp")
			hm.commit(hm.resources.spend("actor:" .. ctx.actor, "hp", 3), "spend")
			return hm.resources.get("actor:" .. ctx.actor, "hp").current
		end })
	""")
	check(why == "", "the plugin loads: " + why)
	var p := host.plugin("t.one")
	check(p.hooks == ["before_roll", "after_roll", "ask"] and p.actions.has("poke") and p.actions.poke.label == "Poke" and not p.actions.poke.has("run"), "registrations reached the host: %s %s" % [p.hooks, p.actions.keys()])
	check(p.schemas.has("actor") and k.validators.size() == 1, "the actor schema became a validator")
	# schema enforcement
	check(k.commit([{"t": "actor.add", "actor": {"id": "a_bad", "ext": {"t.one": {"agi": "x"}}}}], "bad").contains("agi"), "bad data is refused by the plugin's schema")
	check(k.commit([{"t": "actor.add", "actor": {"id": "a_1", "name": "One", "owner": "pl_1", "kind": "pc", "ext": {"t.one": {"agi": 2}}}}], "good") == "", "good data goes in")
	check(k.commit([{"t": "actor.set", "id": "a_1", "changes": {"ext/t.one/extra": 1}}], "extra").contains("extra"), "a change that breaks the schema is refused")
	# derive from Lua
	var d: Dictionary = k.state.encounter.actor("a_1").derived["t.one"]
	check(d.defence.total == 12 and d.defence.parts[1].label == "agi" and d.tokens == 0 and d.kind == "pc", "derive ran in Lua with the view: %s" % [d])
	check(d.list == [1, 2] and (d.empty is Array or d.empty is Dictionary), "lists and empty tables come through")
	# rolls through Lua hooks
	var r := k.roll("1d20", {"actor": "a_1", "kind": "attack"}, "Attack")
	check(not r.is_empty() and r.result.parts.size() == 2 and r.result.modifier == 3.0, "before_roll added parts, totalled under the policy (best status): %s" % [r.result.parts])
	check(r.result.outcome in ["hit", "miss"], "after_roll classified: " + str(r.result.outcome))
	# a hook that prompts pauses the bus and resumes
	var run := k.hooks.run("ask", {"n": 1})
	check(run.status == HookBus.HookRun.PENDING and run.request.kind == "prompt" and run.request.to == "pl_1" and run.request.form.question == "really?", "a Lua prompt pauses the hook run: %s" % [run.request])
	check(not run.payload.has("second"), "later handlers have not run yet")
	run.resume({"yes": true})
	check(run.status == HookBus.HookRun.DONE and run.payload.answer.yes == true and run.payload.second == true, "resume continues the Lua handler and the rest of the chain: %s" % [run.payload])
	# an action with a prompt in the middle
	var pc := host.dispatch("t.one", "poke", {"actor": "a_1"})
	check(pc.status == PluginHost.PluginCall.PENDING and pc.request.form.question == "ouch?" and pc.request.to == "pl_1", "the action paused on its prompt: %s %s" % [pc.status, pc.error])
	check(k.state.encounter.effects.size() == 1 and k.state.encounter.actor("a_1").derived["t.one"].defence.total == 11, "what it committed before the prompt is in")
	pc.resume({"word": "yes"})
	check(pc.status == PluginHost.PluginCall.OK and pc.value.word == "yes" and pc.value.now == 11, "the action finished with the answer: %s %s" % [pc.value, pc.error])
	check(k.state.encounter.doc.state.ext["t.one"].last == "yes" and k.state.encounter.log.size() == 2 and k.state.encounter.log[1].kind == "note", "state and a note were committed")
	check(pc.value.get("none") == null, "a missing resource is nil")
	var setup := host.dispatch("t.one", "setup", {"actor": "a_1"})
	check(setup.status == PluginHost.PluginCall.OK and setup.value == 1.0, "resources from Lua: pool set and spent: %s %s" % [setup.value, setup.error])
	check(host.dispatch("t.one", "missing", {}).status == PluginHost.PluginCall.ERROR, "an unknown action is an error")
	check(failures.is_empty(), "no plugin failures along the way: %s" % [failures])
	# the log names the plugin
	var by := []
	for e in k.log.entries:
		by.append(str(e.reason.get("by", "")))
	check(by.has("t.one"), "entries the plugin caused say so")


func test_plugin_isolation_and_gates() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var k := _kernel()
	var host := PluginHost.new(k)
	host.instruction_budget = 100_000
	var failures := []
	host.plugin_failed.connect(func(id: String, where: String, msg: String) -> void: failures.append([id, where, msg]))
	var ruleset_fails := []
	k.ruleset_failed.connect(func(id: String, msg: String) -> void: ruleset_fails.append([id, msg]))
	# a well-behaved plugin beside a broken one
	check(_load(host, """
		hexmap.derive(function(v) return { fine = 1 } end)
		hexmap.on("before_roll", function(p) p.fine = true return p end)
	""", {"id": "t.good", "version": "1", "api": 1, "name": "good"}) == "", "good loads")
	check(_load(host, """
		local hm = hexmap
		hm.derive(function(v) error("derive broke") end)
		hm.on("before_roll", function(p) error("hook broke") end)
		hm.actions.register("spin", { run = function() while true do end end })
		hm.actions.register("deep", { run = function() local function f() return f() + 1 end return f() end })
		hm.actions.register("probe", { run = function()
			return { io = tostring(io), os = tostring(os), debug = tostring(debug), load = tostring(load), require = tostring(require),
				host = tostring(__host), getfenv = tostring(getfenv), hexmap = type(hexmap) }
		end })
		hm.actions.register("escape", { run = function() hexmap.derive = nil return "changed" end })
		hm.actions.register("bad_commit", { run = function() hm.commit({ { t = "actor.set", id = "nobody", changes = {} } }, "x") end })
		hm.actions.register("yieldy", { run = function() return hm.prompt("pl", {}) end })
		hm.actions.register("state", { run = function() hm.commit(hm.state.set("encounter", "", { x = 1 }), "x") end })
		hm.actions.register("note", { run = function() hm.log("hi") end })
	""", {"id": "t.bad", "version": "1", "api": 1, "name": "bad", "capabilities": ["actions"]}) == "", "bad loads (its faults are at run time)")
	k.commit([{"t": "actor.add", "actor": {"id": "a_1"}}], "actor")
	var a := k.state.encounter.actor("a_1")
	check(a.derived["t.good"].fine == 1 and not a.derived.has("t.bad") or a.derived["t.bad"].is_empty(), "the good ruleset derived, the broken one did not take it down: %s" % [a.derived])
	check(ruleset_fails.size() >= 1 and ruleset_fails[0][0] == "t.bad" and ruleset_fails[0][1].contains("derive broke"), "the derive error was reported against the plugin")
	var r := k.roll("1d6", {}, "x")
	check(not r.is_empty() and failures.any(func(f: Array) -> bool: return f[0] == "t.bad" and str(f[1]).begins_with("hook")), "a hook error is skipped and reported; the roll still happens")
	var pc := host.dispatch("t.bad", "spin", {})
	check(pc.status == PluginHost.PluginCall.ERROR and pc.error.contains("budget"), "an endless action is cut off: " + pc.error)
	pc = host.dispatch("t.bad", "deep", {})
	check(pc.status == PluginHost.PluginCall.ERROR and pc.error.contains("stack"), "runaway recursion is an error: " + pc.error)
	pc = host.dispatch("t.bad", "probe", {})
	check(pc.status == PluginHost.PluginCall.OK, "probe ran: " + pc.error)
	for key in ["io", "os", "debug", "load", "require", "host", "getfenv"]:
		check(str(pc.value.get(key)) == "nil", "%s is not reachable" % key)
	check(pc.value.hexmap == "table", "the API is")
	pc = host.dispatch("t.bad", "escape", {})
	check(pc.status == PluginHost.PluginCall.ERROR, "the API table is read-only after seal")
	pc = host.dispatch("t.bad", "bad_commit", {})
	check(pc.status == PluginHost.PluginCall.ERROR and pc.error.contains("nobody"), "a refused commit is a Lua error with the reason: " + pc.error)
	pc = host.dispatch("t.bad", "yieldy", {})
	check(pc.status == PluginHost.PluginCall.ERROR and pc.error.contains("prompts"), "yielding without the prompts capability is an error")
	pc = host.dispatch("t.bad", "state", {})
	check(pc.status == PluginHost.PluginCall.ERROR and pc.error.contains("state"), "ext.set without the state capability is refused")
	pc = host.dispatch("t.bad", "note", {})
	check(pc.status == PluginHost.PluginCall.ERROR and pc.error.contains("log"), "hm.log without the log capability is refused")
	pc = host.dispatch("t.good", "nothing", {})
	check(pc.status == PluginHost.PluginCall.ERROR, "no such action")
	check(host.plugin("t.bad").errors.size() >= 5, "the plugin's error list grew: %d" % host.plugin("t.bad").errors.size())
	check(k.roll("1d6", {}, "y").result.has("total"), "the kernel is fine after all that")


func test_plugin_ordering_between_plugins() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var k := _kernel()
	var host := PluginHost.new(k)
	_load(host, "hexmap.on(\"x\", function(p) p.trail = (p.trail or \"\") .. \"A\" return p end)", {"id": "t.a", "version": "1", "api": 1, "name": "a"})
	_load(host, "hexmap.on(\"x\", function(p) p.trail = (p.trail or \"\") .. \"B\" return p end)", {"id": "t.b", "version": "1", "api": 1, "name": "b", "depends": ["t.a"]})
	check(k.hooks.run("x", {}).payload.trail == "AB", "plugins run in load order")
	host.unload("t.a")
	check(k.hooks.run("x", {}).payload.trail == "B", "unloading one leaves the other's handlers")


func test_sample_plugin_conformance() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var k := _kernel()
	var host := PluginHost.new(k)
	var why := host.load_dir("res://tests/plugins/sample.ordered")
	check(why == "", "sample.ordered loads: " + why)
	var p := host.plugin("sample.ordered")
	check(p != null and p.actions.has("strike") and p.actions.has("rest") and p.schemas.has("actor"), "it registered its actions and schema")
	var lines := []
	var r := host.run_tests("sample.ordered", func(l: String) -> void: lines.append(l))
	check(r.names.size() >= 7 and r.count >= 20 and r.fails == 0, "its own tests pass: %d checks, %d failed: %s" % [r.count, r.fails, r.failures])
	check(k.state.encounter.actors.is_empty(), "tests ran on scratch states, not the real one")
	# and it still works on the real kernel afterwards
	check(k.commit([{"t": "actor.add", "actor": {"id": "a_h", "owner": "pl_1", "ext": {"sample.ordered": {"level": 3, "stats": {"agi": 2, "str": 1, "wit": 0}, "armour": 1}}}}], "hero") == "", "an actor on the real kernel")
	check(k.state.encounter.actor("a_h").derived["sample.ordered"].defence.total == 13, "derived by the plugin")
	var pc := host.dispatch("sample.ordered", "setup", {"actor": "a_h"})
	check(pc.status == PluginHost.PluginCall.OK and Resources.get_record(k.state, "actor:a_h", "sample.ordered", "hp").max == 6 + 12 + 1, "setup made the pool: %s" % [pc.error])
	var t0 := Time.get_ticks_msec()
	for i in 200:
		k.commit([{"t": "actor.set", "id": "a_h", "changes": {"ext/sample.ordered/stats/agi": i % 5}}], "agi")
	var per := (Time.get_ticks_msec() - t0) / 200.0
	say.call("  a change + Lua derive: %.2f ms" % per)
	check(per < 5.0, "a change with a Lua derive stays cheap (%.2f ms)" % per)
