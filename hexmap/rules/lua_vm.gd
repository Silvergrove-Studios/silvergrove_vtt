class_name LuaVm
extends RefCounted
## One sandboxed Luau VM: the runtime a plugin's code lives in. The kernel
## (PluginHost) creates one per plugin, exposes the host functions the
## manifest allows, loads the plugin's chunks, then seals the VM — after
## which globals and the standard libraries are read-only — and calls
## into it. Every call runs in its own Lua thread under an instruction
## and memory budget; a call may yield (the plugin's way of asking the
## host for something it must wait for, a prompt to a Player) and be
## resumed with the answer. See docs/lua-runtime.md.
##
## The runtime is a GDExtension present on desktop builds only. Nothing
## here names its classes as types, so this script parses on a phone; use
## available() before making one.

## Safepoints a single call may pass before it is cut off. A safepoint is
## a loop iteration, call or return, so this is a coarse instruction count.
var instruction_budget := 1_000_000
## Bytes the VM may hold before a call is cut off.
var memory_budget := 64 * 1024 * 1024
## The most recent load or call error, for logs.
var last_error := ""

var _state: Object
var _sealed := false


## Whether the runtime is loaded in this build.
static func available() -> bool:
	return ClassDB.class_exists("LuaState") and ClassDB.class_exists("Luau")


func _init() -> void:
	if not available():
		return
	_state = ClassDB.instantiate("LuaState")
	# base, coroutine, table, string, math, utf8 — no os, io, debug, buffer,
	# vector; `load`, `require` and friends are not in these either.
	var libs := 0
	for n in ["LIB_BASE", "LIB_COROUTINE", "LIB_TABLE", "LIB_STRING", "LIB_MATH", "LIB_UTF8"]:
		libs |= int(ClassDB.class_get_integer_constant("LuaState", n))
	_state.open_libs(libs)
	# Environment juggling has no place in plugin code; drop it before the
	# globals are frozen. Budgets need the VM's safepoint interrupts, which
	# are one switch for the whole VM: on for its lifetime, each call's
	# thread listens on its own.
	_state.do_string("getfenv = nil setfenv = nil", "prelude")
	_state.set_top(0)
	_state.set_interrupts(true)


func is_valid() -> bool:
	return _state != null


## Give the plugin a host function under a global name. Before seal().
func expose(p_name: String, fn: Callable) -> void:
	if _state == null or _sealed:
		return
	_state.push_callable(fn)
	_state.set_global(p_name)


## Give the plugin a plain value (data only) under a global name. Before seal().
func expose_value(p_name: String, value: Variant) -> void:
	if _state == null or _sealed:
		return
	_state.push_variant(value)
	_state.set_global(p_name)


## Run a chunk of plugin source at load time (it defines functions and
## tables). Returns "" or the error. Before seal().
func load_chunk(source: String, chunk_name: String) -> String:
	if _state == null:
		return "no runtime"
	if _sealed:
		return "the VM is sealed"
	var status: int = _state.do_string(source, chunk_name)
	if status != 0:
		last_error = _top_error()
		return last_error
	_state.set_top(0)
	return ""


## Freeze globals and the standard libraries. After this, calls only.
func seal() -> void:
	if _state == null or _sealed:
		return
	_state.sandbox()
	_sealed = true


## A global's current value, converted to plain data ({} / null when absent).
func global(p_name: String) -> Variant:
	if _state == null:
		return null
	_state.get_global(p_name)
	var v: Variant = _state.to_variant(-1) if _state.get_top() > 0 else null
	_state.set_top(0)
	return v


## Call a global function with plain-data arguments in a fresh thread.
## The returned Call says whether it finished, yielded, errored or ran
## out of budget; a yielded Call is resumed with resume().
func call_function(fn_name: String, args: Array = []) -> Call:
	var c := Call.new()
	c.vm = self
	if _state == null:
		c.status = Call.ERROR
		c.error = "no runtime"
		return c
	var th: Object = _state.new_thread()
	# Nothing in Lua refers to the new thread once it leaves the stack; a
	# registry reference keeps the collector off it until the call is done.
	c._ref = _state.ref(-1)
	_state.pop(1)
	if _sealed:
		th.sandbox_thread()
	th.get_global(fn_name)
	if th.is_nil(-1):
		th.set_top(0)
		c.status = Call.ERROR
		c.error = "no function '%s'" % fn_name
		c._release()
		return c
	c._thread = th
	c._arm()
	for a in args:
		th.push_variant(a)
	c._finish(th.resume(args.size()))
	return c


## Full garbage collection: after a call is cut off or fails, whatever it
## allocated must not count against the next one.
func collect() -> void:
	if _state != null:
		_state.gc(2, 0)   # LUA_GCCOLLECT


func _top_error() -> String:
	if _state.get_top() == 0:
		return "unknown error"
	var msg := str(_state.to_variant(-1))
	_state.set_top(0)
	return msg


## One invocation of a plugin function: its outcome and, while it is
## yielded, the way to continue it.
class Call:
	const OK := "ok"
	const YIELD := "yield"
	const ERROR := "error"
	const BUDGET := "budget"

	var vm: LuaVm
	var status := OK
	## The return value (OK) or the yielded value (YIELD), as plain data.
	var value: Variant = null
	var error := ""
	## Safepoints passed so far, across resumes.
	var steps := 0
	var _thread: Object
	var _cut := false
	var _ref := -1

	func _arm() -> void:
		_thread.interrupt.connect(_on_interrupt)

	func _on_interrupt(state: Object, _gc: int) -> void:
		steps += 1
		if _cut:
			return
		if steps > vm.instruction_budget or state.get_total_bytes(0) > vm.memory_budget:
			_cut = true
			# A safe stop at the next safepoint. Never raise a Lua error from
			# here: that unwinds through the engine's frames and crashes.
			_thread.call("break")

	func _finish(rc: int) -> void:
		var th := _thread
		if _cut:
			status = BUDGET
			error = "instruction budget exceeded" if steps > vm.instruction_budget else "memory budget exceeded"
			_release()
			vm.collect()
			return
		match rc:
			0:
				status = OK
				value = th.to_variant(-1) if th.get_top() > 0 else null
				th.set_top(0)
				_release()
			1:
				status = YIELD
				value = th.to_variant(-1) if th.get_top() > 0 else null
				th.set_top(0)
			_:
				status = ERROR
				error = str(th.to_variant(-1)) if th.get_top() > 0 else "error %d" % rc
				th.set_top(0)
				vm.last_error = error
				_release()

	## Continue a yielded call with an answer (plain data).
	func resume(answer: Variant = null) -> Call:
		if status != YIELD or _thread == null:
			return self
		_thread.push_variant(answer)
		_finish(_thread.resume(1))
		return self

	func _release() -> void:
		if _thread != null:
			if _thread.interrupt.is_connected(_on_interrupt):
				_thread.interrupt.disconnect(_on_interrupt)
			_thread = null
		if _ref >= 0 and vm != null and vm._state != null:
			vm._state.unref(_ref)
			_ref = -1
