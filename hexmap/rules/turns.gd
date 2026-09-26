class_name TurnRunner
extends RefCounted
## Turns as a strategy the ruleset supplies. Two shapes are first-class:
##
##   ordered — an order of participants with rounds: initiative from a
##             statistic the plugin names, a tie-break policy, per-turn
##             budgets (counters reset when a turn starts), delay and
##             insertion, hidden entries kept by the host's token flag,
##             and groups: several tokens on one slot ("group:<id>" in
##             the order, members in data.groups[id]), each member getting
##             its own turn_start / turn_end, budgets and expiries.
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
	# the scene the order is for (a screen shows another scene's order only
	# while it runs), and no turn ended yet
	var base := {"mode": "ordered", "strategy": str(spec.shape), "plugin": str(spec.plugin), "running": true,
		"counters": {}, "requests": [], "history": [], "focus": "", "scene": scene_id, "last": null}
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
	# groups formed before a restart keep their slot, at the first member's place
	var groups: Dictionary = turns().get("data", {}).get("groups", {}) if turns().get("data") is Dictionary else {}
	order = _collapse_groups(order, groups)
	for gid in groups:
		labels["group:" + str(gid)] = str(groups[gid].get("label", gid))
	base.order = order
	base.turn = 0
	base.round = 1
	base.data = {"labels": labels, "groups": JsonDoc.deep(groups)}
	base.counters = {}
	for entry in order:
		for id in EncounterState.turn_members({"data": {"groups": groups}}, str(entry)):
			base.counters["token:" + str(id)] = spec.budgets.duplicate()
	events.append({"t": "turns.set", "changes": base})
	var why := kernel.commit(events, "Start turns")
	if why != "":
		return why
	var first := _ref_of(str(order[0])) if not order.is_empty() else ""
	var fired := _fire("round_start", {"round": 1, "scene": scene_id}, "Round 1")
	if fired != "":
		return fired
	return _begin_turn(first) if first != "" else ""


## End the turns. What lasted rounds or turns ends with the fight, and the
## rulesets hear of it (`combat_end`): what their handlers add — the
## fight's initiative put away, say — lands in the same step. "" or why not.
func stop() -> String:
	var asked := kernel.ask("combat_end", {"scene": str(turns().get("scene", "")), "round": int(turns().get("round", 1))})
	if not asked.ok:
		return asked.why
	var events: Array = [{"t": "turns.set", "changes": {"running": false}}]
	events.append_array(kernel.expire({"kind": "combat_end"}))
	events.append_array(asked.events)
	return kernel.commit(events, "End turns", {"hook": "combat_end"})


# --------------------------------------------------------------- ordered --

## Advance one turn: end the current one, start the next, wrapping into a
## new round. `opts.by` says who ended it: "gm" (the default), a player's
## id or a plugin's. `opts.expect` ({round, turn}) is the turn the caller
## means to end: when that turn has already ended — a player's End turn
## and the DM's Next a few seconds apart, in a playtest, took two turns —
## nothing changes and the answer says whose turn it is now. The turn
## that ended is kept as `last` ({by, entry, round, turn, at}, and what
## the new turn began with: `log`, the newest log entry, and `pos`, where
## its tokens stood), and a player's end is said in the log for everyone.
## "" or why not.
func next(opts := {}) -> String:
	var late := stale(kernel.state, opts.get("expect"))
	if late != "":
		return late
	return kernel.transaction("Next turn", func() -> String: return _next(opts))


func _next(opts: Dictionary) -> String:
	var t := turns()
	if shape() == "focus":
		return "focus turns have no next; grant the focus"
	var order: Array = t.get("order", [])
	if order.is_empty():
		return "no turn order"
	var turn := int(t.get("turn", 0))
	var round := int(t.get("round", 1))
	var entry := str(order[turn]) if turn >= 0 and turn < order.size() else ""
	var cur := _ref_of(entry) if entry != "" else ""
	var ended := {}
	if bool(t.get("running", false)) and cur != "":
		var why := _end_turn(cur)
		if why != "":
			return why
		ended = {"by": str(opts.get("by", "gm")), "entry": entry, "round": round, "turn": turn, "at": JsonDoc.now()}
	turn += 1
	var wrapped := false
	if turn >= order.size():
		turn = 0
		round += 1
		wrapped = true
	var changes := {"turn": turn, "round": round, "running": true}
	if not ended.is_empty():
		changes.last = ended
	var events := [{"t": "turns.set", "changes": changes}]
	# a player's End turn, said where everyone reads (the DM's Next and a
	# player's End turn crossed without either knowing)
	if not ended.is_empty() and not kernel.state.encounter.player(str(ended.by)).is_empty():
		events.append({"t": "log.add", "entry": {"id": JsonDoc.new_id("n"), "kind": "note", "text": "%s ends their turn" % entry_name(kernel.state, entry), "audience": "all"}})
	var why := kernel.commit(events, "Next turn")
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
	why = _begin_turn(_ref_of(str(order[turn])))
	if why != "" or ended.is_empty():
		return why
	# what the new turn began with, so a screen can tell whether anything has
	# happened on it since: the newest log entry, where its tokens stand
	var entries: Array = kernel.state.encounter.log
	var pos := {}
	for id in kernel.state.current_turn_tokens():
		var tk := kernel.state.find_token(str(id))
		if not tk.is_empty():
			pos[str(id)] = JsonDoc.deep(tk.get("pos", [0, 0]))
	return kernel.commit([{"t": "turns.set", "changes": {"last/log": str(entries.back().get("id", "")) if not entries.is_empty() else "", "last/pos": pos}}], "Next turn")


## Why a step meant to end the turn `expect` ({round, turn}) comes too
## late, or "" when that turn is the current one (or none was named):
## "Ada Vex's turn has already ended: it's Grace's turn now."
static func stale(st: EncounterState, expect: Variant) -> String:
	if not (expect is Dictionary) or not (expect as Dictionary).has("turn"):
		return ""
	var t := st.encounter.turns
	if not bool(t.get("running", false)):
		return "The turns have stopped: roll initiative or start them again."
	var order: Array = t.get("order", [])
	var round := int(t.get("round", 1))
	var turn := int(t.get("turn", 0))
	var was := int(expect.get("turn", -1))
	if int(expect.get("round", round)) == round and was == turn:
		return ""
	var who := entry_name(st, str(order[was])) if was >= 0 and was < order.size() else ""
	var now := entry_name(st, str(order[turn])) if turn >= 0 and turn < order.size() else ""
	return "%s turn has already ended: %s" % [(who + "'s") if who != "" else "That", ("it's %s's turn now." % now) if now != "" else "it's round %d now." % round]


## What an order entry is called: a group's label, a token's name (or its
## actor's), else the entry itself.
static func entry_name(st: EncounterState, entry: String) -> String:
	var t := st.encounter.turns
	if entry.begins_with("group:"):
		var data: Dictionary = t.get("data", {}) if t.get("data") is Dictionary else {}
		var g: Dictionary = data.get("groups", {}).get(entry.substr(6), {})
		return str(g.get("label", data.get("labels", {}).get(entry, entry.substr(6))))
	var tk := st.find_token(entry)
	if tk.is_empty():
		return entry
	var n := str(tk.get("name", ""))
	if n == "" and str(tk.get("actor", "")) != "":
		n = str(st.encounter.actor(str(tk.actor)).get("name", ""))
	return n if n != "" else entry


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


## Replace the order (delay, ready, a late arrival): entries are token
## ids or "group:<id>". The participant whose turn it is stays current
## when it is still there.
func reorder(order: Array) -> String:
	var t := turns()
	var old: Array = t.get("order", [])
	var turn := int(t.get("turn", 0))
	var cur := str(old[turn]) if turn >= 0 and turn < old.size() else ""
	var clean := []
	for e in order:
		if not clean.has(str(e)):
			clean.append(str(e))
	var next_turn := clean.find(cur) if cur != "" else 0
	if next_turn < 0:
		next_turn = clampi(turn, 0, maxi(0, clean.size() - 1))
	return kernel.commit([{"t": "turns.set", "changes": {"order": clean, "turn": next_turn}}], "Reorder")


## Put an entry at `index` (the end when -1), taking it out of wherever
## it was. A token new to the order gets its counters.
func insert(entry: String, index := -1) -> String:
	var order: Array = (turns().get("order", []) as Array).duplicate()
	order.erase(entry)
	if index < 0 or index > order.size():
		index = order.size()
	order.insert(index, entry)
	var why := reorder(order)
	if why != "":
		return why
	var spec := current()
	var changes := {}
	for id in EncounterState.turn_members(turns(), entry):
		if not turns().get("counters", {}).has("token:" + str(id)) and not spec.budgets.is_empty():
			changes["counters/token:" + str(id)] = spec.budgets.duplicate()
	return kernel.commit([{"t": "turns.set", "changes": changes}], "Budgets") if not changes.is_empty() else ""


func remove(entry: String) -> String:
	var order: Array = (turns().get("order", []) as Array).duplicate()
	if not order.has(entry):
		return "not in the order"
	order.erase(entry)
	return reorder(order)


## Several tokens on one slot: "group:<id>" replaces the members in the
## order (at the first member's place, or the end), and data.groups[id]
## keeps them with a label.
func group(id: String, tokens: Array, label := "") -> String:
	if id == "" or tokens.is_empty():
		return "a group needs an id and members"
	var t := turns()
	var order: Array = (t.get("order", []) as Array).duplicate()
	var groups: Dictionary = JsonDoc.deep(t.get("data", {}).get("groups", {})) if t.get("data") is Dictionary else {}
	if groups.has(id):
		return "group '%s' exists" % id
	var members := []
	for tk in tokens:
		members.append(str(tk))
	groups[id] = {"tokens": members, "label": label if label != "" else id}
	var collapsed := _collapse_groups(order, {id: groups[id]})
	var why := kernel.commit([{"t": "turns.set", "changes": {"data/groups": groups, "data/labels/group:" + id: groups[id].label}}], "Group")
	if why != "":
		return why
	return reorder(collapsed)


func ungroup(id: String) -> String:
	var t := turns()
	var groups: Dictionary = JsonDoc.deep(t.get("data", {}).get("groups", {})) if t.get("data") is Dictionary else {}
	if not groups.has(id):
		return "no group '%s'" % id
	var order: Array = (t.get("order", []) as Array).duplicate()
	var at := order.find("group:" + id)
	if at >= 0:
		order.remove_at(at)
		var members: Array = groups[id].get("tokens", [])
		for i in members.size():
			order.insert(at + i, str(members[i]))
	groups.erase(id)
	var labels: Dictionary = JsonDoc.deep(t.get("data", {}).get("labels", {})) if t.get("data") is Dictionary else {}
	labels.erase("group:" + id)
	var why := kernel.commit([{"t": "turns.set", "changes": {"data/groups": groups, "data/labels": labels}}], "Ungroup")
	if why != "":
		return why
	return reorder(order)


## Members of `groups` fold into one "group:<id>" entry where the first of
## them stood; a group with no member in the order goes at the end.
static func _collapse_groups(order: Array, groups: Dictionary) -> Array:
	var out := []
	var placed := {}
	for e in order:
		var entry := str(e)
		var in_group := ""
		for gid in groups:
			if (groups[gid].get("tokens", []) as Array).has(entry):
				in_group = str(gid)
				break
		if in_group == "":
			out.append(entry)
		elif not placed.has(in_group):
			placed[in_group] = true
			out.append("group:" + in_group)
	for gid in groups:
		if not placed.has(str(gid)) and not out.has("group:" + str(gid)):
			out.append("group:" + str(gid))
	return out


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


## The ref of an order entry: "group:<id>" stays, a token id gets its prefix.
static func _ref_of(entry: String) -> String:
	return entry if entry.begins_with("group:") else "token:" + entry


## The refs a slot stands for: "token:<id>" per member of a group, or the
## ref itself.
func _slot_refs(ref: String) -> Array:
	if ref.begins_with("group:"):
		var out := []
		for id in EncounterState.turn_members(turns(), ref):
			out.append("token:" + str(id))
		return out
	return [ref]


func _end_turn(ref: String) -> String:
	var group := ref.substr(6) if ref.begins_with("group:") else ""
	for r in _slot_refs(ref):
		var payload := {"ref": r, "actor": kernel.actor_of_ref(r)}
		if group != "":
			payload.group = group
		var why := _fire("turn_end", payload, "Turn ends")
		if why != "":
			return why
		var token: String = r.substr(6) if r.begins_with("token:") else ""
		why = kernel.commit(kernel.expire({"kind": "turn_end", "of": token if token != "" else r}), "Turn effects")
		if why != "":
			return why
	return ""


func _begin_turn(ref: String) -> String:
	var spec := current()
	var group := ref.substr(6) if ref.begins_with("group:") else ""
	var refs := _slot_refs(ref)
	var events := []
	if not spec.budgets.is_empty():
		for r in refs:
			events.append({"t": "turns.set", "changes": {"counters/" + r: spec.budgets.duplicate()}})
	var why := kernel.commit(events, "Budgets")
	if why != "":
		return why
	for r in refs:
		var token: String = r.substr(6) if r.begins_with("token:") else ""
		why = kernel.commit(kernel.expire({"kind": "turn_start", "of": token if token != "" else r}), "Turn effects")
		if why != "":
			return why
		var payload := {"ref": r, "actor": kernel.actor_of_ref(r)}
		if group != "":
			payload.group = group
		why = _fire("turn_start", payload, "Turn starts")
		if why != "":
			return why
	return ""
