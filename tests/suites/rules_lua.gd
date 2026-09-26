extends TestCase
## The plugin runtime (LuaVm): sandbox, budgets, yields, the data bridge.
## Skipped where the runtime is not built in (phones).


func _vm() -> LuaVm:
	var vm := LuaVm.new()
	vm.instruction_budget = 200_000
	vm.memory_budget = 32 * 1024 * 1024
	return vm


func test_lua_vm_sandbox() -> void:
	if not LuaVm.available():
		skip("no Lua runtime in this build")
		return
	var vm := _vm()
	check(vm.is_valid(), "a VM can be made")
	check(vm.load_chunk("""
		function probe()
			return { io = tostring(io), os = tostring(os), debug = tostring(debug),
				require = tostring(require), load = tostring(load), loadstring = tostring(loadstring),
				dofile = tostring(dofile), dump = tostring(string.dump), getfenv = tostring(getfenv),
				setfenv = tostring(setfenv), print = tostring(print) ~= "nil" }
		end
		function poke() string.byte = nil return "changed" end
		function newglobal() leaked = 1 return leaked end
	""", "probe") == "", "chunks load: " + vm.last_error)
	vm.seal()
	var r := vm.call_function("probe")
	check(r.status == LuaVm.Call.OK, "probe ran: " + r.error)
	for k in ["io", "os", "debug", "require", "load", "loadstring", "dofile", "dump", "getfenv", "setfenv"]:
		check(str(r.value.get(k)) == "nil", "%s is absent" % k)
	check(r.value.get("print") == true, "print exists (routed to the log later)")
	r = vm.call_function("poke")
	check(r.status == LuaVm.Call.ERROR, "the standard library is read-only after seal: " + r.status)
	r = vm.call_function("newglobal")
	check(r.status == LuaVm.Call.ERROR, "globals are read-only after seal: " + r.status)
	check(vm.load_chunk("x = 1", "late") != "", "no chunks load after seal")
	r = vm.call_function("missing")
	check(r.status == LuaVm.Call.ERROR and r.error.contains("missing"), "calling a missing function is an error, not a crash")


func test_lua_vm_budgets() -> void:
	if not LuaVm.available():
		skip("no Lua runtime in this build")
		return
	var vm := _vm()
	vm.load_chunk("""
		function spin() local i = 0 while true do i = i + 1 end end
		function bomb() local t = {} for i = 1, 1e9 do t[i] = string.rep('x', 1000000) .. i end end
		function deep(n) return deep(n + 1) + 1 end
		function fine() local s = 0 for i = 1, 1000 do s = s + i end return s end
	""", "budgets")
	vm.seal()
	var t0 := Time.get_ticks_msec()
	var r := vm.call_function("spin")
	check(r.status == LuaVm.Call.BUDGET, "an endless loop is cut off: " + r.status)
	check(Time.get_ticks_msec() - t0 < 2000, "…promptly (%d ms)" % (Time.get_ticks_msec() - t0))
	r = vm.call_function("bomb")
	check(r.status == LuaVm.Call.BUDGET and r.error.contains("memory"), "an allocation bomb is cut off: %s %s" % [r.status, r.error])
	r = vm.call_function("deep", [0])
	check(r.status == LuaVm.Call.ERROR and r.error.contains("stack overflow"), "runaway recursion is an error: " + r.error)
	r = vm.call_function("fine")
	check(r.status == LuaVm.Call.OK and int(r.value) == 500500, "the VM still works after being cut off")


func test_lua_vm_yield_and_resume() -> void:
	if not LuaVm.available():
		skip("no Lua runtime in this build")
		return
	var vm := _vm()
	vm.expose("host_roll", func(expr: String) -> int: return 17 if expr == "1d20" else 0)
	vm.load_chunk("""
		local function prompt(form) return coroutine.yield({ kind = "prompt", form = form }) end
		function act(ctx)
			local roll = host_roll("1d20")
			local ans = prompt({ question = "spend armour?", roll = roll })
			local again = prompt({ question = "sure?" })
			return { damage = (ans.yes and roll - 2 or roll), sure = again, actor = ctx.actor, tags = ctx.tags }
		end
	""", "prompt")
	vm.seal()
	var c := vm.call_function("act", [{"actor": "hero", "tags": ["a", "b"]}])
	check(c.status == LuaVm.Call.YIELD, "the call yields at the prompt: " + c.status + c.error)
	check(c.value is Dictionary and c.value.get("kind") == "prompt", "with the request as data")
	check(c.value.form.roll == 17, "host functions ran before the yield")
	c.resume({"yes": true})
	check(c.status == LuaVm.Call.YIELD and c.value.form.question == "sure?", "a second prompt")
	c.resume("yes")
	check(c.status == LuaVm.Call.OK, "then it finishes: " + c.error)
	check(c.value.damage == 15 and c.value.sure == "yes" and c.value.actor == "hero", "with the answers applied: %s" % [c.value])
	check(c.value.tags is Array and c.value.tags == ["a", "b"], "arrays survive the round trip as arrays")
	# Two calls in flight at once: independent threads.
	var a := vm.call_function("act", [{"actor": "A"}])
	var b := vm.call_function("act", [{"actor": "B"}])
	b.resume({"yes": false})
	b.resume("b")
	a.resume({"yes": true})
	a.resume("a")
	check(a.value.actor == "A" and b.value.actor == "B" and a.value.damage == 15 and b.value.damage == 17, "in-flight calls do not share state")


func test_lua_vm_bridge() -> void:
	if not LuaVm.available():
		skip("no Lua runtime in this build")
		return
	var vm := _vm()
	vm.expose_value("config", {"max": 12, "names": ["x", "y"]})
	vm.load_chunk("""
		function derive(actor)
			return { defence = 10 + actor.stats.agi, parts = { { label = "agility", value = actor.stats.agi } },
				max = config.max, second = config.names[2], deep = actor }
		end
	""", "bridge")
	vm.seal()
	var actor := {"stats": {"agi": 3, "str": 1}, "level": 2, "nested": {"a": [1, {"b": 2.5}]}}
	var r := vm.call_function("derive", [actor])
	check(r.status == LuaVm.Call.OK, "derive ran: " + r.error)
	check(int(r.value.defence) == 13, "computed from nested data")
	check(r.value.parts is Array and r.value.parts[0].label == "agility", "arrays of tables come back as arrays of dictionaries")
	check(int(r.value.max) == 12 and r.value.second == "y", "exposed values are readable")
	check(r.value.deep.nested.a[1].b == 2.5, "deep data round-trips")
	var t0 := Time.get_ticks_msec()
	for i in 2000:
		vm.call_function("derive", [actor])
	var per := (Time.get_ticks_msec() - t0) / 2000.0
	check(per < 0.5, "a call with nested data in and out costs under 0.5 ms (%.3f ms)" % per)
	say.call("  derive round trip: %.3f ms" % per)


func test_plain_error_for_people() -> void:
	check(PluginHost.plain_error('[string "srd5e/combat.lua"]:103: Thok is behind total cover') == "Thok is behind total cover", "the chunk and line go")
	check(PluginHost.plain_error('[string "hexmap"]:464: [string "srd5e/character.lua"]:435: choose your Primal Order') == "choose your Primal Order", "nested ones too")
	check(PluginHost.plain_error("no plugin 'x'") == "no plugin 'x'", "a plain one is kept")
