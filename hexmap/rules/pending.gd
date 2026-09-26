class_name Pending
extends RefCounted
## What the Table is waiting on: prompts to Players and rolls gathering
## contributions. Both are records in the encounter (`pending.prompts`,
## `pending.rolls`) so a reconnecting client is shown them again; the
## continuations that resume a paused action or hook live here, in
## memory, on the Table.
##
## A prompt: { id, to: player id | "gm", form, default, deadline (s; 0 or
##             less: none), by (plugin), title, opened (seq), context, actor }
##   `actor` (opts.actor) names the character a prompt is about, for the
##   screens to say ("for Ada Vex"); a form's `choices` ([{id, label,
##   intent?}]) draw as a button each (docs/plugin-authoring.md).
##   A prompt opened without anything waiting on it (`hm.prompt_open`)
##   carries `context.hook = true`: its answer fires the `prompt_answered`
##   hook instead of resuming a continuation. A group of prompts opened
##   together (`hm.prompt_all`) share `context.group`; the continuation
##   runs once with every answer when the last of them is in.
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
## prompt ids answered by their deadline, so the hook can say so
var _timed_out: Dictionary = {}


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
	if str(opts.get("actor", "")) != "":
		rec.actor = str(opts.actor)
	if rec.to == "":
		rec.to = "gm"
	var why := kernel.commit([{"t": "pending.open", "kind": "prompts", "record": rec}], "Prompt", {"by": by}, "owner:" + rec.to if rec.to != "gm" else "gm")
	if why != "":
		return ""
	_continuations[rec.id] = continuation
	# a deadline of 0 waits for the answer however long it takes (a
	# player's roll is theirs to make: nothing rolls it for them)
	if float(rec.deadline) > 0.0:
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
	var timed_out := _timed_out.has(id)
	_continuations.erase(id)
	_deadlines.erase(id)
	_timed_out.erase(id)
	closed.emit("prompts", id, p_answer)
	if cont is Callable and (cont as Callable).is_valid():
		(cont as Callable).call(p_answer)
	elif bool(rec.get("context", {}).get("hook", false)):
		# nothing waits: the plugins are told
		var ctx: Dictionary = rec.get("context", {}) if rec.get("context") is Dictionary else {}
		kernel.fire("prompt_answered", {"prompt": JsonDoc.deep(rec), "answer": p_answer, "by": who, "timed_out": timed_out,
			"plugin": str(rec.get("by", "")), "context": ctx.get("context", {})}, "Answered")
	return ""


## Open a prompt nothing waits on: its answer (or its default at the
## deadline) fires `prompt_answered` to the plugins. Returns the id.
func open_prompt_unattended(request: Dictionary, by: String, context: Variant = null) -> String:
	return open_prompt(request, by, Callable(), {"hook": true, "context": context if context != null else {}})


## Open one prompt per player in `request.to` (a list) that together
## answer one question: `continuation` runs once, with {player: answer},
## when the last has answered or timed out. Returns the prompt ids.
func open_prompt_group(request: Dictionary, by: String, continuation: Callable, context: Dictionary = {}) -> Array:
	var players: Array = request.get("to", []) if request.get("to") is Array else [request.get("to", "gm")]
	var answers := {}
	var ids := []
	var group := JsonDoc.new_id("pg")
	var n := players.size()
	if n == 0:
		if continuation.is_valid():
			continuation.call({})
		return ids
	for pl in players:
		var pid := str(pl)
		var one: Dictionary = request.duplicate(true)
		one.to = pid
		var ctx: Dictionary = context.duplicate()
		ctx.group = group
		var id := open_prompt(one, by, func(p_answer: Variant) -> void:
			answers[pid] = p_answer
			if answers.size() == n and continuation.is_valid():
				continuation.call(JsonDoc.deep(answers)), ctx)
		ids.append(id)
	return ids


## Close a prompt nothing waits on without answering it: the plugin that
## opened it (`by`) decided it is no longer needed (the roll it asked for
## was made from the sheet, or the GM took the request back). No hook
## fires. "" or why not.
func close(id: String, by := "") -> String:
	var rec: Dictionary = prompts().get(id, {})
	if rec.is_empty():
		return "no prompt '%s'" % id
	if not bool(rec.get("context", {}).get("hook", false)):
		return "an action is waiting on that prompt: answer it instead"
	if by != "" and str(rec.get("by", "")) != by:
		return "that prompt is %s's" % str(rec.get("by", ""))
	var why := kernel.commit([{"t": "pending.close", "kind": "prompts", "id": id}], "Close", {"by": by if by != "" else "gm"})
	if why != "":
		return why
	_continuations.erase(id)
	_deadlines.erase(id)
	_timed_out.erase(id)
	closed.emit("prompts", id, null)
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
			_timed_out[id] = true
			answer_default(str(id))


## Prompts without a continuation (a Table restarted with them open):
## close them with their defaults. Unattended prompts are not orphans:
## their answers reach the plugins whenever they come.
func close_orphans() -> void:
	for id in prompts().keys():
		var rec: Dictionary = prompts()[id]
		if not _continuations.has(id) and not bool(rec.get("context", {}).get("hook", false)):
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
	var me: WeakRef = weakref(self)
	var kind := str(request.get("kind", ""))
	var context := {"action": call.action if call is PluginHost.PluginCall else ""}
	if kind == "prompt_all":
		open_prompt_group(request, by, func(p_answers: Variant) -> void:
			var pd: Pending = me.get_ref()
			if pd == null:
				return
			call.resume(p_answers)
			pd.drive(call, by, done), context)
		return
	if kind != "prompt":
		# not a prompt: nothing else can wait yet — give it nothing
		call.resume(null)
		drive(call, by, done)
		return
	open_prompt(request, by, func(p_answer: Variant) -> void:
		var pd: Pending = me.get_ref()
		if pd == null:
			return
		call.resume(p_answer)
		pd.drive(call, by, done), context)


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
