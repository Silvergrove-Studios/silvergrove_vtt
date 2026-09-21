class_name HookBus
extends RefCounted
## "Ask, don't tell": the host calls the plugins at every moment a rule
## could apply, with a payload the handlers may modify, veto or extend.
## Handlers run in a fixed order (by their owner's order, then by
## registration), each seeing the payload as the previous one left it.
##
## A handler is a Callable taking the payload Dictionary and returning:
##   - a Dictionary: the payload to continue with;
##   - null: keep the payload as it is;
##   - a HookBus.Wait: pause the run until something outside answers
##     (a prompt to a Player); the run resumes with the answer.
## A handler vetoes by setting payload.veto to a reason; the run stops and
## reports it. A handler that throws (a plugin error) is skipped and the
## error is recorded on the run; the Table logs it and carries on.
##
## Runs are objects (HookRun) so a paused one can be resumed later.

## A handler raised an error: (hook, owner, message).
signal handler_failed(hook: String, owner: String, message: String)

## hook name -> [ {owner, order, fn} ] sorted by (order, registration)
var _handlers: Dictionary = {}
var _serial := 0


## Register `fn` for `hook` on behalf of `owner` (a plugin id). Lower
## `order` runs first; plugins get their order from the campaign's list.
func on(hook: String, fn: Callable, owner := "", order := 0) -> void:
	if not _handlers.has(hook):
		_handlers[hook] = []
	_serial += 1
	_handlers[hook].append({"owner": owner, "order": order, "serial": _serial, "fn": fn})
	_handlers[hook].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.order < b.order if a.order != b.order else a.serial < b.serial)


## Drop every handler an owner registered.
func off(owner: String) -> void:
	for hook in _handlers:
		var kept := []
		for h in _handlers[hook]:
			if h.owner != owner:
				kept.append(h)
		_handlers[hook] = kept


func has(hook: String) -> bool:
	return not handlers(hook).is_empty()


## The handlers that would run: an owner's handler for a hook that
## another owner overrides is left out (plugin layering, G10).
func handlers(hook: String) -> Array:
	var all: Array = _handlers.get(hook, [])
	if _overrides.is_empty():
		return all
	var out := []
	for h in all:
		if not is_overridden(str(h.owner), hook):
			out.append(h)
	return out


## by -> {owner: [hooks]}: `by` replaces `owner`'s handlers for those
## hooks (or all of them, with "*"). Lifted with `unoverride(by)`.
var _overrides: Dictionary = {}


func override(by: String, owner: String, hooks: Array) -> void:
	if not _overrides.has(by):
		_overrides[by] = {}
	_overrides[by][owner] = hooks.duplicate()


func unoverride(by: String) -> void:
	_overrides.erase(by)


func is_overridden(owner: String, hook: String) -> bool:
	for by in _overrides:
		var per: Dictionary = _overrides[by]
		if per.has(owner):
			var list: Array = per[owner]
			if list.has(hook) or list.has("*"):
				return true
	return false


## Who overrides what: [{by, owner, hooks}].
func overrides() -> Array:
	var out := []
	for by in _overrides:
		for owner in _overrides[by]:
			out.append({"by": str(by), "owner": str(owner), "hooks": _overrides[by][owner].duplicate()})
	return out


## Run a hook to completion or to its first pause. The payload is copied
## first; the run's `payload` is what handlers produced.
func run(hook: String, payload: Dictionary) -> HookRun:
	var r := HookRun.new()
	r.bus = self
	r.hook = hook
	r.payload = JsonDoc.deep(payload)
	r.chain = handlers(hook).duplicate()
	r._step()
	return r


## The final payload of a run that must not pause (host-internal hooks).
## A paused run is treated as vetoed.
func run_sync(hook: String, payload: Dictionary) -> Dictionary:
	var r := run(hook, payload)
	if r.status == HookRun.PENDING:
		r.payload.veto = "hook '%s' paused where it may not" % hook
		r.status = HookRun.VETOED
	return r.payload


## What a handler returns to pause the run: what it wants, and how to
## continue once it has it. `resume` receives (payload, answer) and
## returns like a handler.
class Wait:
	var request: Dictionary
	var resume: Callable

	static func make(p_request: Dictionary, p_resume: Callable) -> Wait:
		var w := Wait.new()
		w.request = p_request
		w.resume = p_resume
		return w


class HookRun:
	const DONE := "done"
	const PENDING := "pending"
	const VETOED := "vetoed"

	var bus: HookBus
	var hook := ""
	var status := DONE
	var payload: Dictionary = {}
	## While PENDING: what the paused handler asked for.
	var request: Dictionary = {}
	## Handler errors met along the way: [{owner, message}].
	var errors: Array = []
	var chain: Array = []
	var index := 0
	var _wait: Wait

	## Continue a PENDING run with the answer to its request.
	func resume(answer: Variant) -> HookRun:
		if status != PENDING or _wait == null:
			return self
		var w := _wait
		_wait = null
		request = {}
		status = DONE
		var result: Variant = _call(w.resume, [payload, answer], chain[index - 1] if index > 0 and index - 1 < chain.size() else {})
		if not _absorb(result):
			return self
		_step()
		return self

	func _step() -> void:
		while index < chain.size():
			if payload.has("veto") and payload.veto != null and str(payload.veto) != "":
				status = VETOED
				return
			var h: Dictionary = chain[index]
			index += 1
			var result: Variant = _call(h.fn, [payload], h)
			if not _absorb(result):
				return
		if payload.has("veto") and payload.veto != null and str(payload.veto) != "":
			status = VETOED

	## Take a handler's result into the run. False when the run paused or
	## was vetoed and stepping must stop.
	func _absorb(result: Variant) -> bool:
		if result is Wait:
			_wait = result
			request = (result as Wait).request
			status = PENDING
			return false
		if result is Dictionary:
			payload = result
		if payload.has("veto") and payload.veto != null and str(payload.veto) != "":
			status = VETOED
			return false
		return true

	func _call(fn: Callable, args: Array, h: Dictionary) -> Variant:
		if not fn.is_valid():
			errors.append({"owner": str(h.get("owner", "")), "message": "handler is not callable"})
			bus.handler_failed.emit(hook, str(h.get("owner", "")), "handler is not callable")
			return null
		# A GDScript handler's own errors surface as engine errors; plugin
		# (Lua) handlers report through their Call and hand back {error}.
		var result: Variant = fn.callv(args)
		if result is Dictionary and result.has("__error"):
			var msg := str(result.__error)
			errors.append({"owner": str(h.get("owner", "")), "message": msg})
			bus.handler_failed.emit(hook, str(h.get("owner", "")), msg)
			return null
		return result
