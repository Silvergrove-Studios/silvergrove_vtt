class_name Effects
extends RefCounted
## Effect records: what changes an actor's numbers or a roll for a while.
## The kernel knows what an effect *is* — where it sits, what it changes,
## when it ends, how it stacks — and nothing about what it means; the
## plugin gives it a key and reacts to that key in hooks.
##
##   { "id": "e_01", "on": "token:t_7f" | "actor:a_1" | "encounter",
##     "plugin": "sample", "key": "shaken", "label": "Shaken", "icon": "…",
##     "value": 2,                                   optional, numeric badge
##     "source": {"actor": "a_hero", "roll": 41},    optional, who caused it
##     "duration": {"kind": "turn_end", "of": "t_7f", "turns": 1},
##     "changes": [{"path": "defence", "mode": "add", "value": -2, "type": "status"}],
##     "stack": "highest",                           stack | highest | none
##     "audience": "all" }
##
## Duration kinds: rounds {rounds}, turn_start / turn_end {of, turns},
## until_check, linked {to}, until_cleared, scene, rest, long_rest,
## session, time {until}. Which triggers fire when is the TurnStrategy's
## and the Clock's business; expire() only answers "given this trigger,
## what ends".
##
## Every function here returns *events*; nothing mutates state.

const STACK_MODES := ["stack", "highest", "none"]


## Events that put `effect` on its target under its stacking rule. An
## effect of the same key already on the target: "stack" adds another,
## "highest" keeps the larger value (updating the record to the new one
## when it is larger, nothing otherwise), "none"
## does nothing.
static func apply(state: EncounterState, effect: Dictionary) -> Array:
	var fx: Dictionary = JsonDoc.deep(effect)
	if not fx.has("id") or str(fx.id) == "":
		fx.id = JsonDoc.new_id("e")
	if not fx.has("stack"):
		fx.stack = "stack"
	if not fx.has("changes"):
		fx.changes = []
	if not fx.has("audience"):
		fx.audience = "all"
	var same := on(state, str(fx.get("on", "")), str(fx.get("key", "")))
	match str(fx.stack):
		"none":
			if not same.is_empty():
				return []
		"highest":
			if not same.is_empty():
				var cur: Dictionary = same[0]
				if float(cur.get("value", 0)) >= float(fx.get("value", 0)):
					return []
				var changes := {"value": fx.get("value", 0)}
				for k in ["duration", "changes", "label", "icon", "source"]:
					if fx.has(k):
						changes[k] = fx[k]
				return [{"t": "effect.set", "id": str(cur.id), "changes": changes}]
	return [{"t": "effect.apply", "effect": fx}]


## Effects on a ref (and, with `key`, only those with that key).
static func on(state: EncounterState, ref: String, key := "") -> Array:
	var out := []
	for id in state.encounter.effects:
		var fx: Dictionary = state.encounter.effects[id]
		if str(fx.get("on", "")) == ref and (key == "" or str(fx.get("key", "")) == key):
			out.append(fx)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return out


## Events removing `id` and everything linked to it.
static func remove(state: EncounterState, id: String) -> Array:
	var out := []
	_remove_linked(state, id, _link_index(state), out)
	return out


## id -> the ids of effects linked to it, built once so removing many
## effects at a time stays linear.
static func _link_index(state: EncounterState) -> Dictionary:
	var links := {}
	for other_id in state.encounter.effects:
		var d: Dictionary = state.encounter.effects[other_id].get("duration", {})
		if str(d.get("kind", "")) == "linked":
			var to := str(d.get("to", ""))
			if not links.has(to):
				links[to] = []
			links[to].append(str(other_id))
	return links


static func _remove_linked(state: EncounterState, id: String, links: Dictionary, out: Array) -> void:
	if not state.encounter.effects.has(id):
		return
	out.append({"t": "effect.remove", "id": id})
	for other_id in links.get(id, []):
		_remove_linked(state, str(other_id), links, out)


## Events for a trigger: {kind: "turn_end", of: "t_7f"} | {kind: "round"}
## | {kind: "scene"} | {kind: "rest"} | {kind: "long_rest"} | {kind:
## "session"} | {kind: "time", now: <clock value>} | {kind: "check", id}.
## Counted durations tick down and end at zero; the rest end outright.
static func expire(state: EncounterState, trigger: Dictionary) -> Array:
	var out := []
	var kind := str(trigger.get("kind", ""))
	var ids := state.encounter.effects.keys()
	ids.sort()
	var links := _link_index(state)
	for id in ids:
		var fx: Dictionary = state.encounter.effects[id]
		var d: Dictionary = fx.get("duration", {})
		var dk := str(d.get("kind", "until_cleared"))
		match kind:
			"turn_start", "turn_end":
				if dk == kind and str(d.get("of", "")) == str(trigger.get("of", "")):
					var left := int(d.get("turns", 1)) - 1
					if left <= 0:
						_remove_linked(state, str(id), links, out)
					else:
						out.append({"t": "effect.set", "id": str(id), "changes": {"duration/turns": left}})
			"round":
				if dk == "rounds":
					var left := int(d.get("rounds", 1)) - 1
					if left <= 0:
						_remove_linked(state, str(id), links, out)
					else:
						out.append({"t": "effect.set", "id": str(id), "changes": {"duration/rounds": left}})
			# the fight is over: what lasted rounds or turns ends with it (a playtest's
			# barbarian stayed Raging after the fight had ended)
			"combat_end":
				if dk == "rounds" or dk == "turn_start" or dk == "turn_end":
					_remove_linked(state, str(id), links, out)
			"scene", "rest", "session":
				if dk == kind or (kind == "rest" and dk == "long_rest" and bool(trigger.get("long", false))):
					_remove_linked(state, str(id), links, out)
			"long_rest":
				if dk == "long_rest" or dk == "rest":
					_remove_linked(state, str(id), links, out)
			"time":
				if dk == "time" and float(d.get("until", 0)) <= float(trigger.get("now", 0)):
					_remove_linked(state, str(id), links, out)
			"check":
				if dk == "until_check" and str(trigger.get("id", "")) == str(id):
					_remove_linked(state, str(id), links, out)
	# an effect may be reached twice through links; keep the first removal
	var seen := {}
	var unique := []
	for ev in out:
		var k := "%s:%s" % [ev.t, ev.id]
		if not seen.has(k):
			seen[k] = true
			unique.append(ev)
	return unique


## Apply effects' `changes` to a derived block in place. A change is
## {path, mode: add | multiply | override | upgrade, value | expr, type}.
## On a typed number, `add` appends a part (so the breakdown shows the
## effect); `multiply` and `override` append the delta as a part, so the
## parts still sum to the total; on a plain number they do arithmetic.
## `expr` is evaluated with {actor, derived, effect, value}.
static func apply_changes(derived: Dictionary, effects: Array, ctx: Dictionary = {}, policy: Dictionary = {}) -> void:
	for fx in effects:
		for ch in fx.get("changes", []):
			var path := str(ch.get("path", ""))
			if path == "":
				continue
			var amount: float
			if ch.has("expr"):
				var c := ctx.duplicate()
				c.effect = fx
				c.value = fx.get("value", 0)
				var v: Variant = Expr.evaluate(str(ch.expr), c)
				amount = float(v) if (v is float or v is int) else 0.0
			else:
				amount = float(ch.get("value", 0))
			var cur: Variant = JsonDoc.at_path(derived, path)
			var label := str(fx.get("label", fx.get("key", "")))
			var ptype := str(ch.get("type", "effect"))
			var mode := str(ch.get("mode", "add"))
			if TypedNumber.is_typed(cur):
				var total: float = TypedNumber.value(cur)
				var delta := 0.0
				match mode:
					"add": delta = amount
					"multiply": delta = total * (amount - 1.0)
					"override": delta = amount - total
					"upgrade": delta = maxf(0.0, amount - total)
				var part := {"label": label, "type": ptype, "value": delta, "source": str(fx.get("id", ""))}
				var next := TypedNumber.add(cur, part, policy)
				JsonDoc.set_at_path(derived, path, next)
			else:
				var base := float(cur) if (cur is float or cur is int) else 0.0
				var next_v := base
				match mode:
					"add": next_v = base + amount
					"multiply": next_v = base * amount
					"override": next_v = amount
					"upgrade": next_v = maxf(base, amount)
				JsonDoc.set_at_path(derived, path, next_v)
