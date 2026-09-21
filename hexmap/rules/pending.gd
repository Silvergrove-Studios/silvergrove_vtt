class_name Pending
extends RefCounted
## What the Table is waiting on: prompts to Players and rolls gathering
## contributions. Both are records in the encounter (`pending.prompts`,
## `pending.rolls`) so a reconnecting client is shown them again; the
## continuations that resume a paused action or hook live here, in
## memory, on the Table.
##
## A prompt: { id, to: player id | "gm", form, default, deadline (s),
##             by (plugin), title, opened (seq), context }
## A roll:   { id, spec, ctx, label, by, open_to: [player ids] | "all",
##             contributions: [{by, name, expr}], deadline }
##
## Answers and contributions come from Players as intents (Phase 4) or
## from the GM; `answer()` validates who may answer. The default answers
## a prompt whose deadline passed (`tick`) or that the GM waves through.

signal opened(kind: String, record: Dictionary)
signal closed(kind: String, id: String, answer: Variant)

var kernel: RulesKernel
## prompt id -> Callable(answer) continuing whatever paused
var _continuations: Dictionary = {}
## prompt id -> seconds left (host time; decremented by tick)
var _deadlines: Dictionary = {}


func _init(p_kernel: RulesKernel) -> void:
	kernel = p_kernel


func prompts() -> Dictionary:
	return kernel.state.encounter.pending.prompts


func rolls() -> Dictionary:
	return kernel.state.encounter.pending.rolls


# --------------------------------------------------------------- prompts --

## Open a prompt from a request ({kind: "prompt", to, form, opts}) and keep
## the continuation to call with the answer. Returns the prompt id.
func open_prompt(request: Dictionary, by: String, continuation: Callable, context: Dictionary = {}) -> String:
	var opts: Dictionary = request.get("opts", {}) if request.get("opts") is Dictionary else {}
	var rec := {"id": JsonDoc.new_id("p"), "to": str(request.get("to", "gm")), "form": request.get("form", {}),
		"default": opts.get("default", {}), "deadline": float(opts.get("deadline", 30)), "by": by,
		"title": str(request.get("form", {}).get("title", "")) if request.get("form") is Dictionary else "",
		"opened": kernel.log.seq, "context": context}
	if rec.to == "":
		rec.to = "gm"
	var why := kernel.commit([{"t": "pending.open", "kind": "prompts", "record": rec}], "Prompt", {"by": by}, "owner:" + rec.to if rec.to != "gm" else "gm")
	if why != "":
		return ""
	_continuations[rec.id] = continuation
	_deadlines[rec.id] = rec.deadline
	opened.emit("prompts", rec)
	return rec.id


## Answer a prompt. `who` is a player id or "" for the GM (who may answer
## any prompt). "" or why not.
func answer(id: String, p_answer: Variant, who := "") -> String:
	var rec: Dictionary = prompts().get(id, {})
	if rec.is_empty():
		return "no prompt '%s'" % id
	if who != "" and str(rec.to) != who:
		return "this prompt is for %s" % str(rec.to)
	var why := kernel.commit([{"t": "pending.close", "kind": "prompts", "id": id}], "Answer", {"by": who if who != "" else "gm"})
	if why != "":
		return why
	var cont: Variant = _continuations.get(id)
	_continuations.erase(id)
	_deadlines.erase(id)
	closed.emit("prompts", id, p_answer)
	if cont is Callable and (cont as Callable).is_valid():
		(cont as Callable).call(p_answer)
	return ""


## Answer with the prompt's default (a deadline passed, or the GM waved it on).
func answer_default(id: String) -> String:
	var rec: Dictionary = prompts().get(id, {})
	if rec.is_empty():
		return "no prompt '%s'" % id
	return answer(id, JsonDoc.deep(rec.get("default", {})), "")


## Count down deadlines; answer with the default when one runs out.
func tick(seconds: float) -> void:
	for id in _deadlines.keys():
		_deadlines[id] = float(_deadlines[id]) - seconds
		if float(_deadlines[id]) <= 0.0:
			answer_default(str(id))


## Prompts without a continuation (a Table restarted with them open):
## close them with their defaults.
func close_orphans() -> void:
	for id in prompts().keys():
		if not _continuations.has(id):
			answer_default(str(id))


## Drive a PluginCall or HookRun through its prompts: while it is pending,
## open a prompt whose answer resumes it. `done` is called with the final
## call once it finishes or fails.
func drive(call: Variant, by: String, done: Callable = Callable()) -> void:
	var pending := false
	var request := {}
	if call is PluginHost.PluginCall:
		pending = call.status == PluginHost.PluginCall.PENDING
		request = call.request
	elif call is HookBus.HookRun:
		pending = call.status == HookBus.HookRun.PENDING
		request = call.request
	if not pending:
		if done.is_valid():
			done.call(call)
		return
	if str(request.get("kind", "")) != "prompt":
		# not a prompt: nothing else can wait yet — give it nothing
		call.resume(null)
		drive(call, by, done)
		return
	var me: WeakRef = weakref(self)
	open_prompt(request, by, func(p_answer: Variant) -> void:
		var pd: Pending = me.get_ref()
		if pd == null:
			return
		call.resume(p_answer)
		pd.drive(call, by, done), {"action": call.action if call is PluginHost.PluginCall else ""})


# ----------------------------------------------------------------- rolls --

## Open a roll that gathers contributions before it resolves.
func open_roll(spec: Variant, ctx: Dictionary, by: String, label := "Roll", open_to: Variant = "all", deadline := 30.0) -> String:
	var s: Dictionary = {"expr": spec} if spec is String else JsonDoc.deep(spec)
	var rec := {"id": JsonDoc.new_id("q"), "spec": s, "ctx": ctx, "label": label, "by": by, "open_to": open_to,
		"contributions": [], "deadline": deadline, "opened": kernel.log.seq}
	var why := kernel.commit([{"t": "pending.open", "kind": "rolls", "record": rec}], "Open roll", {"by": by})
	if why != "":
		return ""
	opened.emit("rolls", rec)
	return rec.id


## Add a named dice group to an open roll (a help die, a joined action).
func contribute(id: String, who: String, p_name: String, expr: String) -> String:
	var rec: Dictionary = rolls().get(id, {})
	if rec.is_empty():
		return "no open roll '%s'" % id
	var open_to: Variant = rec.get("open_to", "all")
	if open_to is Array and who != "" and not (open_to as Array).has(who):
		return "this roll is not open to %s" % who
	var parsed := Dice.parse(expr)
	if parsed.has("error"):
		return parsed.error
	for c in rec.get("contributions", []):
		if str(c.get("name", "")) == p_name:
			return "a '%s' contribution exists" % p_name
	var list: Array = (rec.get("contributions", []) as Array).duplicate()
	list.append({"by": who, "name": p_name, "expr": expr})
	return kernel.commit([{"t": "pending.set", "kind": "rolls", "id": id, "changes": {"contributions": list}}], "Contribute", {"by": who})


## Resolve an open roll through the kernel (hooks, stream, log) with its
## contributions as named groups. The log entry, or {} (see last_veto).
func resolve(id: String) -> Dictionary:
	var rec: Dictionary = rolls().get(id, {})
	if rec.is_empty():
		kernel.last_veto = "no open roll '%s'" % id
		return {}
	var spec: Dictionary = JsonDoc.deep(rec.spec)
	if not spec.has("named"):
		spec.named = {}
	for c in rec.get("contributions", []):
		spec.named[str(c.name)] = str(c.expr)
	var ctx: Dictionary = JsonDoc.deep(rec.get("ctx", {}))
	ctx.contributions = JsonDoc.deep(rec.get("contributions", []))
	kernel.log.begin_group()
	var why := kernel.commit([{"t": "pending.close", "kind": "rolls", "id": id}], "Resolve", {"by": str(rec.get("by", ""))})
	var entry := {}
	if why == "":
		entry = kernel.roll(spec, ctx, str(rec.get("label", "Roll")), {"by": str(rec.get("by", ""))})
	kernel.log.end_group(str(rec.get("label", "Roll")))
	closed.emit("rolls", id, entry)
	return entry
