class_name EventLog
extends History
## The encounter's log of applied events: what undo, replication, replay,
## checkpoints and the session recap all read. Every applied event is an
## entry with a sequence number, a label, a reason (which plugin, hook or
## roll caused it) and an audience. The log is append-only: undo applies
## the inverse *and appends it* as a new entry, so replaying the log from
## the starting document always reproduces the current one, undo included.
##
## It is a History, so the Table's undo/redo menu and grouping work as
## before; the difference is that the log records events, not closures,
## and applies them to the EncounterState itself.

## An entry was appended: hosts broadcast it, autosave notices it.
signal appended(entry: Dictionary)

var state: EncounterState
## Entries in order; entry = {seq, t (the event's t), ev, inv, label,
## reason, audience, undo_of (seq, when this entry is an undo/redo)}.
var entries: Array = []
## The next sequence number (entries.size() when nothing was trimmed).
var seq := 1
## Named sequence positions the table can go back to.
var checkpoints: Dictionary = {}

## Audience of an entry when the event says nothing: everyone.
const AUDIENCE_ALL := "all"


func _init(p_state: EncounterState = null) -> void:
	state = p_state


## Validate, apply and record an event as one undo step (or as part of
## the open group). Returns "" or why it was refused. `reason` is data
## about the cause ({by: plugin, hook, roll}); `audience` is who may see
## the entry ("all", "gm", "owner:<player>"…).
func record(ev: Dictionary, label := "", reason: Dictionary = {}, audience := AUDIENCE_ALL) -> String:
	if state == null:
		return "no state"
	var why := state.validate(ev)
	if why != "":
		return why
	var event: Dictionary = JsonDoc.deep(ev)
	var box := {"inv": {}, "seq": 0}
	var lbl := label if label != "" else str(ev.t)
	# The closures live in the undo stack this log owns: they must hold
	# the log weakly or the two keep each other alive for ever.
	var me: WeakRef = weakref(self)
	commit(lbl,
		func() -> void:
			var lg: EventLog = me.get_ref()
			if lg == null:
				return
			var first: bool = (box.inv as Dictionary).is_empty()
			var to_apply: Dictionary = event if first else JsonDoc.deep(event)
			var inv := lg.state.apply(to_apply)
			var entry := lg._append(to_apply, inv, lbl, reason, audience, 0 if first else int(box.seq))
			if first:
				box.inv = inv
				box.seq = entry.seq
			else:
				box.inv = inv,
		func() -> void:
			var lg: EventLog = me.get_ref()
			if lg == null:
				return
			var inv: Dictionary = JsonDoc.deep(box.inv)
			var back := lg.state.apply(inv)
			lg._append(inv, back, "Undo " + lbl, reason, audience, int(box.seq))
			box.inv = back)
	return ""


## Several events as one undo step. Every event is validated against the
## state *as it will be* when its turn comes, so a bad third event leaves
## the first two undone. Returns "" or the reason.
func record_all(events: Array, label: String, reason: Dictionary = {}, audience := AUDIENCE_ALL) -> String:
	begin_group()
	var n := 0
	for ev in events:
		var why := record(ev, label, reason, audience)
		if why != "":
			# roll back what this group applied so far
			for i in n:
				var c: Dictionary = _group.pop_back()
				c.undo.call()
			_group_depth = maxi(0, _group_depth - 1)
			return why
		n += 1
	end_group(label)
	return ""


## Entries appended after `since_seq`, for a client catching up.
func since(since_seq: int) -> Array:
	var out := []
	for e in entries:
		if int(e.seq) > since_seq:
			out.append(e)
	return out


## Remember where we are under a name.
func checkpoint(p_name: String) -> void:
	checkpoints[p_name] = {"seq": seq - 1, "when": JsonDoc.now()}


## Go back to a checkpoint: undo every entry after it, as one step.
func restore(p_name: String) -> bool:
	if not checkpoints.has(p_name):
		return false
	var at := int(checkpoints[p_name].seq)
	var todo := []
	for e in entries:
		if int(e.seq) > at:
			todo.append(e)
	if todo.is_empty():
		return true
	# Apply each inverse, newest first, as compensating entries: the log
	# stays append-only and replay still reproduces the state.
	begin_group()
	var me: WeakRef = weakref(self)
	for i in range(todo.size() - 1, -1, -1):
		var e: Dictionary = todo[i]
		var inv: Dictionary = JsonDoc.deep(e.inv)
		var box := {"inv": inv, "seq": int(e.seq)}
		commit("Restore " + p_name,
			func() -> void:
				var lg: EventLog = me.get_ref()
				if lg == null:
					return
				var back := lg.state.apply(JsonDoc.deep(box.inv))
				lg._append(box.inv, back, "Restore " + p_name, {"restore": p_name}, AUDIENCE_ALL, int(box.seq))
				box.inv = back,
			func() -> void:
				var lg: EventLog = me.get_ref()
				if lg == null:
					return
				var back := lg.state.apply(JsonDoc.deep(box.inv))
				lg._append(box.inv, back, "Undo restore " + p_name, {"restore": p_name}, AUDIENCE_ALL, int(box.seq))
				box.inv = back)
	end_group("Restore " + p_name)
	return true


## Replay entries' events onto a state (a fresh one from the starting
## document). Returns "" or the first refusal.
static func replay(onto: EncounterState, p_entries: Array) -> String:
	for e in p_entries:
		var ev: Dictionary = e.ev if e.has("ev") else e
		var why := onto.validate(ev)
		if why != "":
			return "entry %s: %s" % [str(e.get("seq", "?")), why]
		onto.apply(JsonDoc.deep(ev))
	return ""


## The log as plain data, for saving beside the encounter or sending on.
func to_array() -> Array:
	return JsonDoc.deep(entries)


func clear() -> void:
	super()
	entries.clear()
	checkpoints.clear()
	seq = 1


func _append(ev: Dictionary, inv: Dictionary, label: String, reason: Dictionary, audience: String, undo_of: int) -> Dictionary:
	var entry := {"seq": seq, "t": str(ev.get("t", "")), "ev": JsonDoc.deep(ev), "inv": JsonDoc.deep(inv), "label": label,
		"reason": JsonDoc.deep(reason), "audience": audience, "when": JsonDoc.now()}
	if undo_of > 0:
		entry.undo_of = undo_of
	seq += 1
	entries.append(entry)
	appended.emit(entry)
	return entry
