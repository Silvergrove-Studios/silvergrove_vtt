class_name TurnRunner
extends RefCounted
## Turns as a strategy the ruleset supplies. Two shapes are first-class:
##
##   ordered — an order of participants with rounds: initiative from a
##             statistic the plugin names, a tie-break policy, per-turn
##             budgets (counters reset when a turn starts), delay and
##             insertion, hidden entries kept by the host's token flag.
##   focus   — no order and no rounds: a holder ("token:id", "actor:id"
##             or "gm") that Players may ask for and the GM grants or
##             seizes; a history of who held it; counters per participant.
##
## Whatever the shape, the runner fires the same hooks — `turn_start` /
## `turn_end` for the participant gaining or losing the turn or the
## focus, `round_start` / `round_end` (ordered only), `focus_changed` —
## expires effects whose durations are tied to those moments, and
## commits everything as one undo step. Plugins' handlers may append
## events to `payload.events`.
##
## A strategy is a spec registered by a plugin (or the host's "list"):
##   { plugin, shape: "ordered" | "focus", name, description,
##     initiative: Callable(actor_view) -> float | "derived path" | "",
##     tie_break: "highest" | "lowest" | "name",
##     budgets: {counter: amount}, order_label: Callable(view) -> String }

const LIST := {"plugin": "", "shape": "ordered", "name": "As listed", "description": "The DM arranges the order by hand.", "budgets": {}}

var kernel: RulesKernel
## strategy id ("list" or a plugin id) -> spec
var strategies: Dictionary = {"list": LIST}


func _init(p_kernel: RulesKernel) -> void:
	kernel = p_kernel


func register(id: String, spec: Dictionary) -> void:
	var s: Dictionary = spec.duplicate()
	s.plugin = id
	if not s.has("shape"):
		s.shape = "ordered"
	if not s.has("name"):
		s.name = id
	if not s.has("budgets"):
		s.budgets = {}
	strategies[id] = s


func unregister(id: String) -> void:
	strategies.erase(id)


func strategy(id: String) -> Dictionary:
	return strategies.get(id, LIST)


func turns() -> Dictionary:
	return kernel.state.encounter.turns


## The strategy running now (the list one when the encounter's plugin is
## not loaded here, so a saved order still steps).
func current() -> Dictionary:
	return strategy(str(turns().get("plugin", "")) if str(turns().get("plugin", "")) != "" else "list")


func running() -> bool:
	return bool(turns().get("running", false))


func shape() -> String:
	return str(turns().get("strategy", "ordered"))


# ----------------------------------------------------------------- start --

## Begin turns on a scene under a strategy. Ordered: initiative for every
## token on the scene, sorted; the first turn starts. Focus: the GM holds
## the focus. Returns "" or why not.
func start(scene_id: String, strategy_id := "list") -> String:
	return kernel.transaction("Start turns", func() -> String: return _start(scene_id, strategy_id))


func _start(scene_id: String, strategy_id: String) -> String:
	var spec := strategy(strategy_id)
	var events := []
	var base := {"mode": "ordered", "strategy": str(spec.shape), "plugin": str(spec.plugin), "running": true,
		"counters": {}, "requests": [], "history": [], "focus": ""}
	if str(spec.shape) == "focus":
		base.order = []
		base.turn = 0
		base.round = 1
		base.focus = "gm"
		base.history = ["gm"]
		var asked := kernel.ask("focus_changed", {"from": "", "to": "gm", "by": "gm", "scene": scene_id})
		if not asked.ok:
			return asked.why
		events.append({"t": "turns.set", "changes": base})
		events.append_array(asked.events)
		return kernel.commit(events, "Start turns", {"hook": "focus_changed"})
	var entries := []
	var labels := {}
	for tk in kernel.state.tokens(scene_id):
		var view := kernel.actor_view(str(tk.get("actor", "")))
		var init: Variant = _initiative(spec, view, tk)
		entries.append({"id": str(tk.id), "init": init, "name": str(tk.get("name", ""))})
		if init != null:
			labels[str(tk.id)] = _label(spec, view, init)
	if spec.plugin != "":
		var tie := str(spec.get("tie_break", "highest"))
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var x := float(a.init) if a.init != null else -INF
			var y := float(b.init) if b.init != null else -INF
			if x != y:
				return x < y if tie == "lowest" else x > y
			return a.name < b.name)
	else:
		# the list keeps the order the DM had, newcomers last
		var have := {}
		var kept := []
		for id in turns().get("order", []):
			for e in entries:
				if e.id == str(id):
					kept.append(e)
					have[e.id] = true
		for e in entries:
			if not have.has(e.id):
				kept.append(e)
		entries = kept
	var order := []
	for e in entries:
		order.append(e.id)
	base.order = order
	base.turn = 0
	base.round = 1
	base.data = {"labels": labels}
	base.counters = {}
	for id in order:
		base.counters["token:" + str(id)] = spec.budgets.duplicate()
	events.append({"t": "turns.set", "changes": base})
	var why := kernel.commit(events, "Start turns")
	if why != "":
		return why
	var first := "token:" + str(order[0]) if not order.is_empty() else ""
	var fired := _fire("round_start", {"round": 1, "scene": scene_id}, "Round 1")
	if fired != "":
		return fired
	return _begin_turn(first) if first != "" else ""


func stop() -> String:
	return kernel.commit([{"t": "turns.set", "changes": {"running": false}}], "End turns")


# --------------------------------------------------------------- ordered --

## Advance one turn: end the current one, start the next, wrapping into a
## new round. "" or why not.
func next() -> String:
	return kernel.transaction("Next turn", func() -> String: return _next())


func _next() -> String:
	var t := turns()
	if shape() == "focus":
		return "focus turns have no next; grant the focus"
	var order: Array = t.get("order", [])
	if order.is_empty():
		return "no turn order"
	var turn := int(t.get("turn", 0))
	var round := int(t.get("round", 1))
	var cur := "token:" + str(order[turn]) if turn >= 0 and turn < order.size() else ""
	if bool(t.get("running", false)) and cur != "":
		var why := _end_turn(cur)
		if why != "":
			return why
	turn += 1
	var wrapped := false
	if turn >= order.size():
		turn = 0
		round += 1
		wrapped = true
	var why := kernel.commit([{"t": "turns.set", "changes": {"turn": turn, "round": round, "running": true}}], "Next turn")
	if why != "":
		return why
	if wrapped:
		why = _fire("round_end", {"round": round - 1}, "Round %d ends" % (round - 1))
		if why != "":
			return why
		why = kernel.commit(Effects.expire(kernel.state, {"kind": "round"}), "Round effects")
		if why != "":
			return why
		why = _fire("round_start", {"round": round}, "Round %d" % round)
		if why != "":
			return why
	return _begin_turn("token:" + str(order[turn]))


## Step back one turn without firing anything (a correction, not play).
func previous() -> String:
	var t := turns()
	var order: Array = t.get("order", [])
	if order.is_empty() or shape() == "focus":
		return "no turn order"
	var turn := int(t.get("turn", 0)) - 1
	var round := int(t.get("round", 1))
	if turn < 0:
		if round <= 1:
			return "already at the start"
		turn = order.size() - 1
		round -= 1
	return kernel.commit([{"t": "turns.set", "changes": {"turn": turn, "round": round}}], "Previous turn")


## Move a participant to another position in the order (delay, insert).
func reorder(order: Array) -> String:
	return kernel.commit([{"t": "turns.set", "changes": {"order": order}}], "Reorder")


# ----------------------------------------------------------------- focus --

## Give the focus to a holder ("token:id", "actor:id" or "gm"). `by` says
## who did it: "gm", a player id, or a plugin. The holder losing it gets a
## turn_end, the one gaining it a turn_start.
func set_focus(holder: String, by := "gm") -> String:
	if shape() != "focus":
		return "not a focus encounter"
	return kernel.transaction("Focus", func() -> String: return _set_focus(holder, by))


func _set_focus(holder: String, by: String) -> String:
	var t := turns()
	var from := str(t.get("focus", ""))
	if from == holder:
		return ""
	if holder != "gm" and holder != "" and kernel.state._need_ref(holder, "focus") != "":
		return kernel.state._need_ref(holder, "focus")
	var why := ""
	if from != "" and from != "gm":
		why = _end_turn(from)
		if why != "":
			return why
	var history: Array = (t.get("history", []) as Array).duplicate()
	history.append(holder)
	if history.size() > 50:
		history = history.slice(history.size() - 50)
	var requests: Array = []
	for r in t.get("requests", []):
		if str(r.get("ref", "")) != holder:
			requests.append(r)
	# the rulesets are asked before the focus moves: one may veto (a cost
	# it cannot pay) or add events (the cost it pays)
	var asked := kernel.ask("focus_changed", {"from": from, "to": holder, "by": by})
	if not asked.ok:
		return asked.why
	var events: Array = [{"t": "turns.set", "changes": {"focus": holder, "history": history, "requests": requests}}]
	events.append_array(asked.events)
	why = kernel.commit(events, "Focus", {"hook": "focus_changed"})
	if why != "":
		return why
	if holder != "gm" and holder != "":
		return _begin_turn(holder)
	return ""


## A Player asks for the focus for one of their refs.
func request_focus(player_id: String, ref: String) -> String:
	if shape() != "focus":
		return "not a focus encounter"
	var t := turns()
	for r in t.get("requests", []):
		if str(r.get("ref", "")) == ref:
			return ""
	var requests: Array = (t.get("requests", []) as Array).duplicate()
	requests.append({"player": player_id, "ref": ref})
	return kernel.commit([{"t": "turns.set", "changes": {"requests": requests}}], "Focus request")


func deny_focus(ref: String) -> String:
	var requests: Array = []
	for r in turns().get("requests", []):
		if str(r.get("ref", "")) != ref:
			requests.append(r)
	return kernel.commit([{"t": "turns.set", "changes": {"requests": requests}}], "Deny")


# -------------------------------------------------------------- counters --

func counters(ref: String) -> Dictionary:
	return turns().get("counters", {}).get(ref, {})


## Spend from a participant's budget this turn. {} when it cannot.
func consume_event(ref: String, counter: String, n := 1) -> Dictionary:
	var c := counters(ref)
	if not c.has(counter) or float(c[counter]) < n:
		return {}
	var next_c: Dictionary = JsonDoc.deep(c)
	next_c[counter] = float(c[counter]) - n
	return {"t": "turns.set", "changes": {"counters/" + ref: next_c}}


func consume(ref: String, counter: String, n := 1) -> String:
	var ev := consume_event(ref, counter, n)
	if ev.is_empty():
		return "no %s left" % counter
	return kernel.commit([ev], "Spend " + counter)


# ------------------------------------------------------------- internals --

func _initiative(spec: Dictionary, view: Dictionary, tk: Dictionary) -> Variant:
	var src: Variant = spec.get("initiative")
	if src is Callable and (src as Callable).is_valid():
		var v: Variant = (src as Callable).call(view, tk)
		return float(v) if (v is float or v is int) else null
	if src is String and str(src) != "" and not view.is_empty():
		var v: Variant = JsonDoc.at_path(view.get("derived", {}).get(str(spec.plugin), {}), str(src))
		return TypedNumber.value(v) if v != null else null
	return null


func _label(spec: Dictionary, view: Dictionary, init: Variant) -> String:
	var fn: Variant = spec.get("order_label")
	if fn is Callable and (fn as Callable).is_valid():
		return str((fn as Callable).call(view, init))
	return str(int(init)) if init != null and is_equal_approx(float(init), floor(float(init))) else str(init)


func _fire(hook: String, payload: Dictionary, label: String) -> String:
	return kernel.fire(hook, payload, label)


func _end_turn(ref: String) -> String:
	var why := _fire("turn_end", {"ref": ref, "actor": kernel.actor_of_ref(ref)}, "Turn ends")
	if why != "":
		return why
	var token := ref.substr(6) if ref.begins_with("token:") else ""
	return kernel.commit(kernel.expire({"kind": "turn_end", "of": token if token != "" else ref}), "Turn effects")


func _begin_turn(ref: String) -> String:
	var spec := current()
	var events := []
	if not spec.budgets.is_empty():
		events.append({"t": "turns.set", "changes": {"counters/" + ref: spec.budgets.duplicate()}})
	var why := kernel.commit(events, "Budgets")
	if why != "":
		return why
	var token := ref.substr(6) if ref.begins_with("token:") else ""
	why = kernel.commit(kernel.expire({"kind": "turn_start", "of": token if token != "" else ref}), "Turn effects")
	if why != "":
		return why
	return _fire("turn_start", {"ref": ref, "actor": kernel.actor_of_ref(ref)}, "Turn starts")
