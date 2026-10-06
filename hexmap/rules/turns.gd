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
## focus, `round_start` / `round_end` (ordered only), `focus_changed`,
## `combat_end` — expires effects whose durations are tied to those
## moments, and commits everything as one undo step. Plugins' handlers
## may append events to `payload.events`, veto the step, or wait on a card
## (a roll its roller makes): the step then waits with it, and goes on
## once it's answered (the steps, below).
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
## The step waiting on a card, {} when none (the steps, below):
## {id, label, stages, at, waited, wait}.
var _step: Dictionary = {}
## A step is running its stages now (a call into the turns from inside one
## is refused: the turns are already moving).
var _running := false


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
## the focus. Returns "" or why not (a start that waits on a card goes on
## once it's answered: the steps, below).
func start(scene_id: String, strategy_id := "list") -> String:
	var busy := waiting()
	if busy != "":
		return busy
	return _run("Start turns", [func() -> Variant: return _start(scene_id, strategy_id)])


func _start(scene_id: String, strategy_id: String) -> Variant:
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
		# (the rulesets are asked first: the start lands with what they add)
		return [_hook_stage("focus_changed", {"from": "", "to": "gm", "by": "gm", "scene": scene_id}, "Start turns",
			func() -> Array: return [{"t": "turns.set", "changes": base}])]
	var entries := []
	var labels := {}
	var by_id := {}
	for tk in kernel.state.tokens(scene_id):
		# (a thing on the map takes no turn: its caster moves it on theirs)
		if Encounter.is_object(tk):
			continue
		var view := kernel.actor_view(str(tk.get("actor", "")))
		var init: Variant = _initiative(spec, view, tk)
		entries.append({"id": str(tk.id), "init": init, "name": str(tk.get("name", ""))})
		by_id[str(tk.id)] = tk
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
	var groups: Dictionary = JsonDoc.deep(turns().get("data", {}).get("groups", {})) if turns().get("data") is Dictionary else {}
	order = _collapse_groups(order, groups)
	for gid in groups:
		labels["group:" + str(gid)] = str(groups[gid].get("label", gid))
	# those that take their turns with another's, or right after it
	order = place_followers(order, groups, labels, by_id)
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
	var stages := [_hook_stage("round_start", {"round": 1, "scene": scene_id}, "Round 1")]
	if first != "":
		stages.append(func() -> Variant: return _begin_turn(first))
	return stages


## End the turns. What lasted rounds or turns ends with the fight, and the
## rulesets hear of it (`combat_end`): what their handlers add — the
## fight's initiative put away, say — lands in the same step. "" or why not.
## A step of the turns waiting on a card is given up (its card stays: the
## roll is still its roller's, and what it brings still lands); an end that
## waits on a card itself ends the turns once it's answered.
func stop() -> String:
	if _running:
		return "the turns are moving on: end them once this step is done"
	if not _step.is_empty() and waiting_on().size() > 0:
		if str(_step.get("label", "")) == "End turns":
			return waiting()
		_step.given_up = true
		_step = {}
	return _run("End turns", [_hook_stage("combat_end", {"scene": str(turns().get("scene", "")), "round": int(turns().get("round", 1))}, "End turns",
		func() -> Array: return [{"t": "turns.set", "changes": {"running": false}}] + kernel.expire({"kind": "combat_end"}))])


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
## "" or why not. While a step of the turns waits on a card (a roll its
## roller makes as a turn ends or starts), another Next is refused, saying
## on whom it waits.
func next(opts := {}) -> String:
	var late := stale(kernel.state, opts.get("expect"))
	if late != "":
		return late
	var busy := waiting()
	if busy != "":
		return busy
	return _run("Next turn", [func() -> Variant: return _next(opts)])


## The stages of a Next: the turn ending (its hooks, what ends with it), the
## order moving on, the round's end and start when it wraps, the next turn's
## start, what that turn began with, a turn the DM said is lost.
func _next(opts: Dictionary) -> Variant:
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
	var ending := bool(t.get("running", false)) and cur != ""
	var stages: Array = _end_turn(cur) if ending else []
	stages.append(func() -> Variant: return _move_on(opts, entry, turn, round, ending))
	return stages


## The order moves on from `entry` (the turn that ended, the `turn`th of the
## order in `round`): to the one after it in the order as it is now (one that
## left the order while its turn ended — a creature its own turn's end killed
## — leaves the next where it stood), wrapping into a new round.
func _move_on(opts: Dictionary, entry: String, turn: int, round: int, ending: bool) -> Variant:
	var order: Array = turns().get("order", [])
	if order.is_empty():
		return "no turn order"
	var at := order.find(entry) if entry != "" else -1
	var nturn := at + 1 if at >= 0 else (turn if entry != "" else turn + 1)
	var nround := round
	var wrapped := false
	if nturn >= order.size():
		nturn = 0
		nround += 1
		wrapped = true
	var ended := {}
	if ending:
		ended = {"by": str(opts.get("by", "gm")), "entry": entry, "round": round, "turn": turn, "at": JsonDoc.now()}
	var changes := {"turn": nturn, "round": nround, "running": true}
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
	var next_entry := str(order[nturn])
	var stages := []
	if wrapped:
		stages.append(_hook_stage("round_end", {"round": nround - 1}, "Round %d ends" % (nround - 1)))
		stages.append(func() -> Variant: return kernel.commit(Effects.expire(kernel.state, {"kind": "round"}), "Round effects"))
		stages.append(_hook_stage("round_start", {"round": nround}, "Round %d" % nround))
	stages.append(func() -> Variant: return _begin_turn(_ref_of(next_entry)))
	if ending:
		stages.append(func() -> Variant: return _began_with())
		stages.append(func() -> Variant: return _skip_if_marked(next_entry))
	return stages


## What the new turn began with, so a screen can tell whether anything has
## happened on it since: the newest log entry, where its tokens stand.
func _began_with() -> String:
	var entries: Array = kernel.state.encounter.log
	var pos := {}
	for id in kernel.state.current_turn_tokens():
		var tk := kernel.state.find_token(str(id))
		if not tk.is_empty():
			pos[str(id)] = JsonDoc.deep(tk.get("pos", [0, 0]))
	return kernel.commit([{"t": "turns.set", "changes": {"last/log": str(entries.back().get("id", "")) if not entries.is_empty() else "", "last/pos": pos}}], "Next turn")


## A participant marked to lose its next turn (`data.skip`: a token id, or
## a group's entry, -> true; a group's slot when every member is marked):
## its turn has begun — what starts a turn has started, its hooks have run
## — and it ends at once, as the DM's Next would end it, and the next turn
## begins. The marks go as they are used, so each pass takes one away.
func _skip_if_marked(entry: String) -> Variant:
	var t := turns()
	var data: Dictionary = t.get("data", {}) if t.get("data") is Dictionary else {}
	var skip: Dictionary = data.get("skip", {}) if data.get("skip") is Dictionary else {}
	if skip.is_empty():
		return ""
	var members := EncounterState.turn_members(t, entry)
	var marked := bool(skip.get(entry, false))
	if not marked and not members.is_empty():
		marked = true
		for id in members:
			if not bool(skip.get(str(id), false)):
				marked = false
	if not marked:
		return ""
	var changes := {}
	for k in [entry] + members:
		if skip.has(str(k)):
			changes["data/skip/" + str(k)] = null
	var why := kernel.commit([{"t": "turns.set", "changes": changes}], "Turn skipped")
	if why != "":
		return why
	return _next({"by": "gm"})


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
## Not while a step of the turns waits on a card: that's answered first.
func previous() -> String:
	var busy := waiting()
	if busy != "":
		return busy
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
## it was. A token new to the order gets its counters. With no index, a
## token that takes its turns with another's or right after it
## (`turn_with`, `turn_after`: place_followers) goes there, its leader's
## slot made a group when it shares it.
func insert(entry: String, index := -1) -> String:
	var order: Array = (turns().get("order", []) as Array).duplicate()
	order.erase(entry)
	if index < 0 and not entry.begins_with("group:"):
		var tk := kernel.state.find_token(entry)
		if str(tk.get("turn_with", "")) != "" or str(tk.get("turn_after", "")) != "":
			return _insert_follower(entry, order)
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


## A follower put into the order where it follows (insert): the order and
## its groups worked out again with it, its counters given, whoever is up
## staying up (in its leader's slot made a group, when that was theirs).
func _insert_follower(entry: String, order: Array) -> String:
	var t := turns()
	var data: Dictionary = JsonDoc.deep(t.get("data", {})) if t.get("data") is Dictionary else {}
	var groups: Dictionary = data.get("groups", {}) if data.get("groups") is Dictionary else {}
	var labels: Dictionary = data.get("labels", {}) if data.get("labels") is Dictionary else {}
	var old: Array = t.get("order", [])
	var turn := int(t.get("turn", 0))
	var cur := str(old[turn]) if turn >= 0 and turn < old.size() else ""
	var up: Array = EncounterState.turn_members(t, cur) if cur != "" else []
	order.append(entry)
	var by_id := {}
	for tk in kernel.state.tokens(kernel.state.scene_of_token(entry)):
		by_id[str(tk.id)] = tk
	var placed := place_followers(order, groups, labels, by_id)
	# whoever was up stays up: their entry, or the group their token is in now
	var at := placed.find(cur) if cur != "" else -1
	if at < 0 and not up.is_empty():
		at = _slot_index(placed, groups, str(up[0]))
	if at < 0:
		at = clampi(turn, 0, maxi(0, placed.size() - 1))
	var changes := {"order": placed, "turn": at, "data/groups": groups, "data/labels": labels}
	var spec := current()
	if not spec.budgets.is_empty():
		for e in placed:
			for id in _members_of(str(e), groups):
				if not t.get("counters", {}).has("token:" + str(id)):
					changes["counters/token:" + str(id)] = spec.budgets.duplicate()
	return kernel.commit([{"t": "turns.set", "changes": changes}], "Order")


## Those that take their turns with another's or right after it — a
## creature a spell summoned that acts on its caster's turn or right after
## it, a mount its rider controls. A token's `turn_with` names the token in
## whose slot it acts: the two share it, a group ("with_<leader>") whose
## members each get their own turn_start, budgets and expiries. Its
## `turn_after` names the token after whose slot its own comes: those after
## the same leader share one ("after_<leader>", a group when there are
## several). Each takes its leader's label (its initiative). One whose
## leader isn't in the order, or that follows its own follower, keeps its
## own place. `groups` and `labels` are changed in place; `by_id` has the
## scene's tokens by id. Returns the order.
static func place_followers(order: Array, groups: Dictionary, labels: Dictionary, by_id: Dictionary) -> Array:
	var out: Array = order.duplicate()
	var present := {}
	# (in the order they stand: those already placed keep theirs among themselves)
	var standing := []
	for e in out:
		for id in _members_of(str(e), groups):
			present[str(id)] = true
			standing.append(str(id))
	var follows := {}
	for id in standing:
		var tk: Dictionary = by_id.get(id, {})
		var w := str(tk.get("turn_with", "")) if tk.get("turn_with") != null else ""
		var a := str(tk.get("turn_after", "")) if tk.get("turn_after") != null else ""
		var leader := w if w != "" else a
		if leader == "" or leader == id or not present.has(leader):
			continue
		follows[id] = {"how": "with" if w != "" else "after", "leader": leader}
	# (a loop — each following the other — leaves them where they stood)
	for id in follows.keys():
		var seen := {id: true}
		var at: String = follows[id].leader
		while follows.has(at):
			if seen.has(at):
				follows.erase(id)
				break
			seen[at] = true
			at = follows[at].leader
	if follows.is_empty():
		return out
	# out of wherever they stood
	out = out.filter(func(e: Variant) -> bool: return not follows.has(str(e)))
	var gids := groups.keys()
	for gid in gids:
		var members: Array = groups[gid].get("tokens", [])
		var kept := members.filter(func(x: Variant) -> bool: return not follows.has(str(x)))
		if kept.size() == members.size():
			continue
		if kept.is_empty():
			groups.erase(gid)
			labels.erase("group:" + str(gid))
			out.erase("group:" + str(gid))
		else:
			groups[gid].tokens = kept
	# each after its leader, leaders first (one may lead another)
	var left: Array = standing.filter(func(id: String) -> bool: return follows.has(id))
	var after_slot := {}
	var touched := {}
	var rounds := left.size() + 1
	while not left.is_empty() and rounds > 0:
		rounds -= 1
		var later := []
		for id in left:
			var f: Dictionary = follows[id]
			var leader := str(f.leader)
			var at := _slot_index(out, groups, leader)
			if at < 0:
				later.append(id)
				continue
			if f.how == "with":
				var entry := str(out[at])
				if entry.begins_with("group:"):
					(groups[entry.substr(6)].tokens as Array).append(id)
					touched[entry.substr(6)] = leader
				else:
					var gid := "with_" + leader
					groups[gid] = {"tokens": [leader, id], "label": ""}
					out[at] = "group:" + gid
					labels["group:" + gid] = str(labels.get(leader, ""))
					touched[gid] = leader
			else:
				var gid := "after_" + leader
				if after_slot.has(leader):
					var e := str(after_slot[leader])
					if e.begins_with("group:"):
						(groups[e.substr(6)].tokens as Array).append(id)
					else:
						groups[gid] = {"tokens": [e, id], "label": ""}
						out[out.find(e)] = "group:" + gid
						labels.erase(e)
						after_slot[leader] = "group:" + gid
					touched[gid] = leader
				else:
					out.insert(at + 1, id)
					labels[id] = str(labels.get(leader, ""))
					after_slot[leader] = id
		left = later
	# those whose leader never came (it follows one that follows it): at the end
	for id in left:
		out.append(id)
	# what each group made or grown here is called (its members' names), and
	# its label its leader's initiative
	for gid in touched:
		if groups.has(gid):
			groups[gid].label = _names_of(groups[gid].tokens, by_id)
			labels["group:" + str(gid)] = str(labels.get(str(touched[gid]), ""))
	return out


## The tokens an order entry stands for.
static func _members_of(entry: String, groups: Dictionary) -> Array:
	if entry.begins_with("group:"):
		var g: Variant = groups.get(entry.substr(6))
		return (g.get("tokens", []) as Array) if g is Dictionary else []
	return [entry]


## Where a token's slot is in an order: its own entry, or its group's; -1.
static func _slot_index(order: Array, groups: Dictionary, token_id: String) -> int:
	for i in order.size():
		if _members_of(str(order[i]), groups).has(token_id):
			return i
	return -1


## A group's name from its members': "Wren and Owl", "Wolf 1, Wolf 2 and 2 more".
static func _names_of(ids: Array, by_id: Dictionary) -> String:
	var names := []
	for id in ids:
		var n := str(by_id.get(str(id), {}).get("name", ""))
		names.append(n if n != "" else str(id))
	if names.size() <= 2:
		return " and ".join(PackedStringArray(names))
	if names.size() == 3:
		return "%s, %s and %s" % names
	return "%s, %s and %d more" % [names[0], names[1], names.size() - 2]


## Take an entry out of the order: a token id or "group:<id>", or one
## member of a group's slot — it leaves the group and the others keep the
## slot; a group left with nobody goes (a goblin fleeing a fight in which
## its kin shared its initiative).
func remove(entry: String) -> String:
	var order: Array = (turns().get("order", []) as Array).duplicate()
	if order.has(entry):
		order.erase(entry)
		return reorder(order)
	var t := turns()
	var data: Dictionary = t.get("data", {}) if t.get("data") is Dictionary else {}
	var groups: Dictionary = JsonDoc.deep(data.get("groups", {}))
	for gid in groups:
		var members: Array = (groups[gid].get("tokens", []) as Array).duplicate()
		if not members.has(entry):
			continue
		members.erase(entry)
		if not members.is_empty():
			return kernel.commit([{"t": "turns.set", "changes": {"data/groups/%s/tokens" % gid: members}}], "Leave the group")
		groups.erase(gid)
		var labels: Dictionary = JsonDoc.deep(data.get("labels", {}))
		labels.erase("group:" + str(gid))
		var why := kernel.commit([{"t": "turns.set", "changes": {"data/groups": groups, "data/labels": labels}}], "Leave the order")
		if why != "":
			return why
		order.erase("group:" + str(gid))
		return reorder(order)
	return "not in the order"


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
	var busy := waiting()
	if busy != "":
		return busy
	return _run("Focus", [func() -> Variant: return _set_focus(holder, by)])


func _set_focus(holder: String, by: String) -> Variant:
	var t := turns()
	var from := str(t.get("focus", ""))
	if from == holder:
		return ""
	if holder != "gm" and holder != "" and kernel.state._need_ref(holder, "focus") != "":
		return kernel.state._need_ref(holder, "focus")
	var stages: Array = _end_turn(from) if from != "" and from != "gm" else []
	# the rulesets are asked before the focus moves: one may veto (a cost
	# it cannot pay) or add events (the cost it pays)
	stages.append(_hook_stage("focus_changed", {"from": from, "to": holder, "by": by}, "Focus", func() -> Array:
		var now := turns()
		var history: Array = (now.get("history", []) as Array).duplicate()
		history.append(holder)
		if history.size() > 50:
			history = history.slice(history.size() - 50)
		var requests: Array = []
		for r in now.get("requests", []):
			if str(r.get("ref", "")) != holder:
				requests.append(r)
		return [{"t": "turns.set", "changes": {"focus": holder, "history": history, "requests": requests}}]))
	if holder != "gm" and holder != "":
		stages.append(func() -> Variant: return _begin_turn(holder))
	return stages


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


## The stages of a slot's turn ending: each member's `turn_end`, then what
## ends with its turn.
func _end_turn(ref: String) -> Array:
	var group := ref.substr(6) if ref.begins_with("group:") else ""
	var out := []
	for r in _slot_refs(ref):
		out.append(_hook_stage("turn_end", func() -> Dictionary:
			var payload := {"ref": r, "actor": kernel.actor_of_ref(r)}
			if group != "":
				payload.group = group
			return payload, "Turn ends"))
		var token: String = r.substr(6) if r.begins_with("token:") else ""
		out.append(func() -> Variant: return kernel.commit(kernel.expire({"kind": "turn_end", "of": token if token != "" else r}), "Turn effects"))
	return out


## The stages of a slot's turn beginning: its budgets, then each member's
## turn-start expiries and `turn_start`.
func _begin_turn(ref: String) -> Variant:
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
	var out := []
	for r in refs:
		var token: String = r.substr(6) if r.begins_with("token:") else ""
		out.append(func() -> Variant: return kernel.commit(kernel.expire({"kind": "turn_start", "of": token if token != "" else r}), "Turn effects"))
		out.append(_hook_stage("turn_start", func() -> Dictionary:
			var payload := {"ref": r, "actor": kernel.actor_of_ref(r)}
			if group != "":
				payload.group = group
			return payload, "Turn starts"))
	return out


# ------------------------------------------------------------- the steps --
# A step of the turns — Next, the start, a focus given, the end — runs its
# moments in order (a turn's end and what ends with it, the order moving on,
# a round's end and start, the next turn's start) as one undo step that all
# happens or none of it does. A hook's handler may wait on a card (a roll
# its roller makes: the DM's recharge die typed, a player's save — a
# HookBus.Wait, a plugin's hm.prompt): the step keeps what it has done, the
# card opens (its context's `turn` names the step: the waiting list says on
# whom the turn waits, Views), and the rest of the step runs once the hook
# has finished — each part after a wait an undo step of its own. A veto
# before any wait refuses the step as a whole, as ever; one after a wait
# stops it there, and the DM is told why. While a step waits, the turns
# wait with it: Next, Back, a focus given or a start is refused, saying on
# whom it waits; ending the fight gives the rest of it up (the card stays:
# the roll is still its roller's, and what it brings still lands). A card
# opened anywhere else may hold the turns the same way (`holds_turn`: a save
# a player owes on someone else's action, which nothing waits on): while the
# turns run, nothing moves them on until it's answered.
#
# A stage is a Callable returning "" (go on), why it stopped, an Array of
# stages to run next, or a hook run that waits ({wait, label, before}).

## Run a step from its first stage. "" (done, or waiting on a card) or why
## it was refused (nothing of it happened then).
func _run(label: String, stages: Array) -> String:
	if _running:
		return "the turns are moving on already"
	return _go({"id": JsonDoc.new_id("ts"), "label": label, "stages": stages, "at": 0, "waited": false}, Callable())


## Run a step's stages from where it stands, as one transaction (`first`
## before them: the hook it waited on, finished). Stopping, what this part
## did is undone; waiting on a card, it's kept, and the card opens.
func _go(step: Dictionary, first: Callable) -> String:
	var paused := [{}]
	_running = true
	var why := kernel.transaction(str(step.label), func() -> String:
		if first.is_valid():
			var w := _absorb(step, first.call(), paused)
			if w != "" or not (paused[0] as Dictionary).is_empty():
				return w
		while int(step.at) < (step.stages as Array).size():
			var stage: Callable = step.stages[int(step.at)]
			step.at = int(step.at) + 1
			var w := _absorb(step, stage.call(), paused)
			if w != "" or not (paused[0] as Dictionary).is_empty():
				return w
		return "")
	_running = false
	var wait: Dictionary = paused[0]
	if wait.is_empty():
		if str(_step.get("id", "")) == str(step.id):
			_step = {}
		if why != "" and bool(step.waited):
			# (nobody waits on the answer: the DM is told why it stopped there)
			kernel.commit([{"t": "log.add", "entry": {"id": JsonDoc.new_id("n"), "kind": "note", "audience": "gm",
				"text": "%s stopped: %s" % [str(step.label), why]}}], "Turn stopped", {}, "gm")
		return why
	step.waited = true
	step.wait = wait
	_step = step
	var run: HookBus.HookRun = wait.wait
	var me: WeakRef = weakref(self)
	kernel.pending.drive(run, RulesKernel._waiting_owner(run), func(r: HookBus.HookRun) -> void:
		var tr: TurnRunner = me.get_ref()
		if tr != null:
			tr._resume(step, r), {"turn": str(step.id)})
	return ""


## A stage's result taken into the step: "" to go on (more stages put next,
## or a wait noted in `paused`), or why it stopped.
func _absorb(step: Dictionary, r: Variant, paused: Array) -> String:
	if r is Dictionary and (r as Dictionary).has("wait"):
		paused[0] = r
		return ""
	if r is Array:
		var at := int(step.at)
		for i in (r as Array).size():
			(step.stages as Array).insert(at + i, r[i])
		return ""
	return str(r) if r != null else ""


## A hook as a stage: run (`payload` a Dictionary, or a Callable that makes
## it as the stage runs), its events committed as `label` once it has
## finished — after `before`'s (the change it was asked about: a focus
## moved, the turns ended) — or its veto the stage's why.
func _hook_stage(hook: String, payload: Variant, label: String, before := Callable()) -> Callable:
	return func() -> Variant:
		var p: Dictionary = (payload as Callable).call() if payload is Callable else (payload as Dictionary).duplicate()
		p.events = []
		return _hook_done(kernel.hooks.run(hook, p), label, before)


func _hook_done(run: HookBus.HookRun, label: String, before: Callable) -> Variant:
	if run.status == HookBus.HookRun.PENDING:
		return {"wait": run, "label": label, "before": before}
	if run.status == HookBus.HookRun.VETOED:
		var veto := str(run.payload.get("veto", ""))
		return veto if veto != "" else "refused"
	var events: Array = (before.call() as Array).duplicate() if before.is_valid() else []
	events.append_array(run.payload.get("events", []) if run.payload.get("events") is Array else [])
	return kernel.commit(events, label, {"hook": run.hook})


## The hook a step waited on has finished: the step goes on from there —
## unless it was given up meanwhile (the fight ended), when what the hook
## brought still lands and nothing after it runs.
func _resume(step: Dictionary, run: HookBus.HookRun) -> void:
	var wait: Dictionary = step.get("wait", {})
	step.erase("wait")
	if bool(step.get("given_up", false)) or str(_step.get("id", "")) != str(step.id):
		if run.status == HookBus.HookRun.DONE:
			var events: Array = run.payload.get("events", []) if run.payload.get("events") is Array else []
			if not events.is_empty():
				kernel.commit(events, str(wait.get("label", "")), {"hook": run.hook})
		return
	_go(step, func() -> Variant: return _hook_done(run, str(wait.get("label", "")), wait.get("before", Callable())))


## Whether a step of the turns waits on a card: the words a refused Next is
## answered with — "The turn is waiting on Ana: a roll (Brann). It goes on
## once that's answered." — or "" when nothing waits.
func waiting() -> String:
	if _running:
		return "the turns are moving on already"
	return waiting_words()


## On whom a step of the turns waits, in words, or "" (a screen's line: it
## asks nothing of a step that is running now). A step whose card is gone
## (an undo took it back) waits on nothing: a new step may start.
func waiting_words() -> String:
	var on := waiting_on()
	if on.is_empty():
		return ""
	var bits := []
	for rec in on:
		var to := str(rec.get("to", "gm"))
		var who := "the DM" if to == "gm" else str(kernel.state.encounter.player(to).get("name", "a player"))
		var what := str(rec.get("public", ""))
		bits.append(who + (": " + what if what != "" else ""))
	return "The turn is waiting on %s. It goes on once %s answered." % ["; ".join(PackedStringArray(bits)), "that's" if on.size() == 1 else "they're"]


## The cards (prompt records) the turns wait on, oldest first: a waiting
## step's, and while the turns run, any card that holds them (`holds_turn`).
func waiting_on() -> Array:
	var out := []
	var holding := running()
	if _step.is_empty() and not holding:
		return out
	var prompts := kernel.pending.prompts()
	for id in prompts:
		var rec: Dictionary = prompts[id]
		var ctx: Variant = rec.get("context", {})
		var step_card := not _step.is_empty() and ctx is Dictionary and str((ctx as Dictionary).get("turn", "")) == str(_step.id)
		if step_card or (holding and bool(rec.get("holds_turn", false))):
			out.append(rec)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("opened", 0)) < int(b.get("opened", 0)))
	return out
