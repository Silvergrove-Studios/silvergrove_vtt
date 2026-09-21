class_name RulesKernel
extends RefCounted
## The rules engine the Table runs: an EncounterState, its EventLog, the
## HookBus the rulesets listen on, and the derivation that keeps every
## actor's `derived` block current. Rulesets register here — in Phase 1
## as GDScript callables (the tests' fixture), from Phase 2 as sandboxed
## Lua plugins behind the same registration — and everything they do
## comes out as events through commit().
##
## Derivation: after any committed change that touches an actor (its
## data, overlays, effects on it or on its tokens, its resources), the
## kernel rebuilds the actor's view, calls each ruleset's `derive`,
## applies effects' changes to the result and writes actor.derived.
## `derived` is never an event: it is a function of the document, so a
## replay recomputes it and a Player receives it as a view.

## An actor's derived block was rewritten.
signal derived_changed(actor_id: String)
## A ruleset's derive threw or returned nonsense.
signal ruleset_failed(ruleset_id: String, message: String)

var state: EncounterState
var log: EventLog
var hooks := HookBus.new()
var turns: TurnRunner
var clock: Clock
var pending: Pending
## Content packs: the rulesets' and the table's, indexed.
var comp := Compendium.new()
## Distances, templates, sight, light, regions, cells.
var map: MapQuery
## id -> {derive: Callable(view) -> Dictionary, fields: {name: expr},
##        policy: {type: stack|best|override}, order, depends_on_state}
var rulesets: Dictionary = {}
## [{owner, fn: Callable(actor) -> "" | why}] consulted before an actor is
## added or changed: plugins' schemas, mostly.
var validators: Array = []
var _order := 0


func _init(p_state: EncounterState, p_log: EventLog = null) -> void:
	state = p_state
	log = p_log if p_log != null else EventLog.new(p_state)
	if log.state == null:
		log.state = p_state
	turns = TurnRunner.new(self)
	clock = Clock.new(self)
	pending = Pending.new(self)
	map = MapQuery.new(self)
	# Through a weak reference: the log must not keep the kernel alive.
	var me: WeakRef = weakref(self)
	log.changed.connect(func() -> void:
		var k: RulesKernel = me.get_ref()
		if k != null:
			k._on_history_changed())


## Register a ruleset. `spec` keys: derive (Callable taking the actor
## view, returning the derived Dictionary), fields ({name: Expr source}
## evaluated with {actor: view} — the data-only way), policy (stacking
## per part type), depends_on_state (re-derive everyone when encounter
## state changes), owner (the object the callables live on; the kernel
## keeps it alive).
func register_ruleset(id: String, spec: Dictionary) -> void:
	_order += 1
	var r: Dictionary = spec.duplicate()
	r.order = int(spec.get("order", _order))
	rulesets[id] = r
	rederive_all()


func unregister_ruleset(id: String) -> void:
	rulesets.erase(id)
	hooks.off(id)
	turns.unregister(id)
	map.band_tables.erase(id)
	rederive_all()


## Everything a trigger ends: effects and regions alike.
func expire(trigger: Dictionary) -> Array:
	var out := Effects.expire(state, trigger)
	out.append_array(map.expire_all_regions(trigger))
	return out


## Move a token (and what is attached to it) with the rulesets asked:
## `token_moved` may veto or add events; `region_entered` / `region_left`
## fire for the zones crossed. One undo step. "" or why not.
func move_token(scene_id: String, id: String, to: Vector2, by := "gm") -> String:
	var mv := map.move(scene_id, id, to)
	if mv.has("error"):
		return str(mv.error)
	return transaction("Move", func() -> String:
		var asked := ask("token_moved", {"scene": scene_id, "token": id, "actor": actor_of_ref("token:" + id), "from": mv.from, "to": mv.to,
			"cells": mv.cells, "entered": mv.entered, "left": mv.left, "by": by})
		if not asked.ok:
			return asked.why
		var events: Array = mv.events.duplicate()
		events.append_array(asked.events)
		var why := commit(events, "Move", {"hook": "token_moved", "by": by})
		if why != "":
			return why
		for rid in mv.left:
			why = fire("region_left", {"scene": scene_id, "token": id, "actor": actor_of_ref("token:" + id), "region": rid, "record": state.encounter.scene(scene_id).regions.get(rid, {})}, "Left")
			if why != "":
				return why
		for rid in mv.entered:
			why = fire("region_entered", {"scene": scene_id, "token": id, "actor": actor_of_ref("token:" + id), "region": rid, "record": state.encounter.scene(scene_id).regions.get(rid, {})}, "Entered")
			if why != "":
				return why
		return "")


## The stacking policy rolls total their parts under: every registered
## ruleset's, merged in order (a later one overrides a type).
func policy() -> Dictionary:
	var out := {}
	var ids := rulesets.keys()
	ids.sort_custom(func(x, y) -> bool: return ruleset_order(x) < ruleset_order(y))
	for rid in ids:
		for t in rulesets[rid].get("policy", {}):
			out[t] = rulesets[rid].policy[t]
	return out


func ruleset_order(id: String) -> int:
	return int(rulesets.get(id, {}).get("order", 0))


# --------------------------------------------------------------- commit --

## Apply events as one undo step, then re-derive whoever they touched.
## Returns "" or why the batch was refused (nothing applied then).
func commit(events: Array, label: String, reason: Dictionary = {}, audience := EventLog.AUDIENCE_ALL) -> String:
	if events.is_empty():
		return ""
	var why_v := _validate_actors(events)
	if why_v != "":
		return why_v
	var touched := {}
	var everyone := [false]
	_collect(events, touched, everyone)   # effects about to be removed are still here
	_committing = true
	var why := log.record_all(events, label, reason, audience)
	_committing = false
	if why != "":
		return why
	_collect(events, touched, everyone)   # actors and effects just added
	if everyone[0]:
		rederive_all()
	else:
		var ids := touched.keys()
		ids.sort()
		for id in ids:
			rederive(str(id))
	return ""


## Run the validators over the actors a batch adds or changes (as they
## will be after the change). "" or the first complaint.
func _validate_actors(events: Array) -> String:
	if validators.is_empty():
		return ""
	for ev in events:
		var actor := {}
		match str(ev.get("t", "")):
			"actor.add":
				actor = JsonDoc.deep(ev.get("actor", {}))
				Encounter.fill_actor(actor)
			"actor.set":
				var cur := state.encounter.actor(str(ev.get("id", "")))
				if cur.is_empty() or not (ev.get("changes") is Dictionary):
					continue
				actor = JsonDoc.deep(cur)
				JsonDoc.merge_paths(actor, ev.changes)
			_:
				continue
		for v in validators:
			var why: String = (v.fn as Callable).call(actor)
			if why != "":
				return why
	return ""


func commit_one(ev: Dictionary, label := "", reason: Dictionary = {}) -> String:
	return commit([ev], label if label != "" else str(ev.get("t", "")), reason)


var _committing := false

func _on_history_changed() -> void:
	# Undo, redo and restore change the document under us: derive everyone.
	# (A commit of our own already derived exactly whom it touched.)
	if not _committing:
		rederive_all()


## Run a hook synchronously with an `events` list the handlers may append
## to. {ok, why, events, payload}: the events are not committed.
func ask(hook: String, payload: Dictionary) -> Dictionary:
	var p: Dictionary = payload.duplicate()
	p.events = []
	var out := hooks.run_sync(hook, p)
	if out.has("veto") and out.veto != null and str(out.veto) != "":
		return {"ok": false, "why": str(out.veto), "events": [], "payload": out}
	var events: Array = out.get("events", []) if out.get("events") is Array else []
	return {"ok": true, "why": "", "events": events, "payload": out}


## ask(), then commit what the handlers gathered. "" or the veto / refusal.
func fire(hook: String, payload: Dictionary, label: String) -> String:
	var a := ask(hook, payload)
	if not a.ok:
		return a.why
	return commit(a.events, label, {"hook": hook})


## Several commits as one undo step that either all happen or none do:
## `fn` returns "" or why it stopped, and on a refusal the step is undone.
func transaction(label: String, fn: Callable) -> String:
	var depth := log.undo_depth()
	log.begin_group()
	var why: String = fn.call()
	log.end_group(label)
	if why != "" and log.undo_depth() > depth:
		log.undo()
		log._redo.clear()   # a step that never happened is not there to redo
		log.changed.emit()
	return why


## A rest of some kind ("rest", "long_rest", or whatever the ruleset
## names): refills, expiries, tracks, the `rest` hook, the clock's count.
func rest(kind := "rest", label := "") -> String:
	var lbl := label if label != "" else kind.capitalize()
	return transaction(lbl, func() -> String:
		var why := commit([{"t": "clock.set", "changes": {"rests": int(state.encounter.clock.get("rests", 0)) + 1}}], lbl)
		if why == "":
			why = commit(expire({"kind": kind}) + Resources.refill(state, kind) + Tracks.on_trigger(state, kind), lbl)
		if why == "":
			why = fire("rest", {"kind": kind}, lbl)
		return why)


# ------------------------------------------------------------------ rolls --

## Roll with the rulesets consulted: `before_roll` may add parts, change
## the spec or veto; the dice draw from the encounter's stream;
## `after_roll` classifies (sets result.outcome and whatever else).
## The roll is recorded as a log entry of kind "roll" and returned; an
## empty Dictionary means it was vetoed (reason in `last_veto`).
var last_veto := ""

func roll(spec: Variant, ctx: Dictionary = {}, label := "Roll", reason: Dictionary = {}) -> Dictionary:
	last_veto = ""
	var s: Dictionary = {"expr": spec} if spec is String else JsonDoc.deep(spec)
	if not s.has("parts"):
		s.parts = []
	var before := hooks.run_sync("before_roll", {"spec": s, "ctx": ctx})
	if before.has("veto") and before.veto != null and str(before.veto) != "":
		last_veto = str(before.veto)
		return {}
	s = before.spec
	if not s.has("policy"):
		s.policy = policy()
	var rng: Dictionary = state.encounter.doc.rng
	var result := Dice.roll(s, int(rng.seed), int(rng.index))
	if not result.ok:
		last_veto = result.error
		return {}
	var after := hooks.run_sync("after_roll", {"spec": s, "result": result, "ctx": ctx})
	result = after.result
	var entry := {"id": JsonDoc.new_id("r"), "kind": "roll", "label": label, "spec": s, "result": result, "draw": result.draw,
		"actor": str(ctx.get("actor", "")), "audience": str(result.get("visibility", "all"))}
	var why := log.record({"t": "log.add", "entry": entry}, label, reason, str(entry.audience))
	if why != "":
		last_veto = why
		return {}
	# tracks that move on rolls, then the ruleset hears about any that finished
	var moved := Tracks.on_roll(state, entry)
	if not moved.is_empty():
		var done := Tracks.completed_by(state, moved)
		commit(moved, "Tracks", {"roll": entry.id})
		for id in done:
			fire("track_done", {"track": id, "roll": entry.id}, "Track done")
	return entry


# ------------------------------------------------------------ derivation --

## Everything a ruleset's derive may look at for one actor: the record
## with overlays merged into `ext`, the effects on it, its resources and
## its tokens. A copy: derive is pure.
func actor_view(actor_id: String) -> Dictionary:
	var a := state.encounter.actor(actor_id)
	if a.is_empty():
		return {}
	var view: Dictionary = JsonDoc.deep(a)
	for ov in a.get("overlays", []):
		_merge_patch(view.ext, ov.get("patch", {}))
	view.effects = effects_on_actor(actor_id)
	view.resources = JsonDoc.deep(state.encounter.resources.get("actor:" + actor_id, {}))
	view.tokens = []
	for sc in state.encounter.scenes:
		for tk in sc.tokens:
			if str(tk.get("actor", "")) == actor_id:
				view.tokens.append(JsonDoc.deep(tk))
				var tres: Dictionary = state.encounter.resources.get("token:" + str(tk.id), {})
				for pid in tres:
					if not view.resources.has(pid):
						view.resources[pid] = {}
					for n in tres[pid]:
						view.resources[pid][n] = JsonDoc.deep(tres[pid][n])
	view.state = JsonDoc.deep(state.encounter.doc.state)
	return view


## Effects on the actor itself and on any token linked to it.
func effects_on_actor(actor_id: String) -> Array:
	var out := Effects.on(state, "actor:" + actor_id)
	for sc in state.encounter.scenes:
		for tk in sc.tokens:
			if str(tk.get("actor", "")) == actor_id:
				out.append_array(Effects.on(state, "token:" + str(tk.id)))
	return out


## The actor a ref resolves to ("" for the encounter or an unlinked token).
func actor_of_ref(ref: String) -> String:
	if ref.begins_with("actor:"):
		return ref.substr(6)
	if ref.begins_with("token:"):
		return str(state.find_token(ref.substr(6)).get("actor", ""))
	return ""


func rederive(actor_id: String) -> void:
	var a := state.encounter.actor(actor_id)
	if a.is_empty():
		return
	var view := actor_view(actor_id)
	var derived := {}
	var ids := rulesets.keys()
	ids.sort_custom(func(x, y) -> bool: return ruleset_order(x) < ruleset_order(y))
	for rid in ids:
		var r: Dictionary = rulesets[rid]
		var block := {}
		var fields: Dictionary = r.get("fields", {})
		for f in fields:
			var v: Variant = Expr.evaluate(str(fields[f]), {"actor": view})
			block[f] = v
		var fn: Variant = r.get("derive")
		if fn is Callable and (fn as Callable).is_valid():
			var got: Variant = (fn as Callable).call(view)
			if got is Dictionary:
				if got.has("__error"):
					ruleset_failed.emit(rid, str(got.__error))
				else:
					for k in got:
						block[k] = got[k]
			elif got != null:
				ruleset_failed.emit(rid, "derive returned %s, not an object" % type_string(typeof(got)))
		var mine := []
		for fx in view.effects:
			if str(fx.get("plugin", rid)) == rid:
				mine.append(fx)
		Effects.apply_changes(block, mine, {"actor": view, "derived": block}, r.get("policy", {}))
		TypedNumber.retotal(block, r.get("policy", {}))
		derived[rid] = block
	if not JsonDoc.same(a.get("derived", {}), derived):
		a.derived = JsonDoc.sorted(derived)
		derived_changed.emit(actor_id)


func rederive_all() -> void:
	var ids := state.encounter.actors.keys()
	ids.sort()
	for id in ids:
		rederive(str(id))


## Which actors a batch of events touches, into `touched`; `everyone[0]`
## when it is cheaper (or only possible) to derive them all.
func _collect(events: Array, touched: Dictionary, everyone: Array) -> void:
	for ev in events:
		match str(ev.get("t", "")):
			"actor.add":
				touched[str(ev.actor.get("id", ""))] = true
			"actor.set", "actor.overlay.push", "actor.overlay.pop":
				touched[str(ev.get("id", ""))] = true
			"effect.apply":
				_touch_ref(touched, str(ev.effect.get("on", "")))
			"effect.set", "effect.remove":
				var fx := state.encounter.effect(str(ev.id))
				if not fx.is_empty():
					_touch_ref(touched, str(fx.get("on", "")))
			"resource.set":
				_touch_ref(touched, str(ev.ref))
			"token.set", "token.add", "token.remove":
				everyone[0] = true
			"ext.set":
				if str(ev.scope) == "encounter":
					for rid in rulesets:
						if bool(rulesets[rid].get("depends_on_state", false)):
							everyone[0] = true
				else:
					everyone[0] = true


func _touch_ref(touched: Dictionary, ref: String) -> void:
	var a := actor_of_ref(ref)
	if a != "":
		touched[a] = true


static func _merge_patch(target: Dictionary, patch: Dictionary) -> void:
	for k in patch:
		if patch[k] is Dictionary and target.get(k) is Dictionary:
			_merge_patch(target[k], patch[k])
		elif patch[k] == null:
			target.erase(k)
		else:
			target[k] = JsonDoc.deep(patch[k])
