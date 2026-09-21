class_name Tracks
extends RefCounted
## Progress tracks: countdowns, clocks and subsystem meters — one primitive
## for what rulesets implement three ways. A track has a value that moves
## between 0 and `max` (down for a countdown, up for a clock), an advance
## rule the kernel drives from rolls and rests, an audience, and text for
## what happens when it completes.
##
##   { "id": "k_1", "plugin": "sample.focus", "name": "Reinforcements",
##     "kind": "countdown" | "clock" | "meter",
##     "value": 4, "max": 4,                      countdown: counts down to 0
##     "direction": "down" | "up",                 (clock: counts up to max)
##     "advance": { "on": "manual" | "roll" | "roll_outcome" | "rest" | "long_rest" | "turn",
##                  "outcomes": ["fear"], "amount": 1, "actor": "" },
##     "audience": "all" | "gm", "on_done": "The gate opens.", "done": false,
##     "linked": "" }                              (a track that moves when this one does)
##
## Everything here returns events; the kernel commits and fires
## `track_done` when a track completes.


static func make(plugin: String, p_name: String, max_value: int, kind := "countdown", advance: Dictionary = {}, audience := "all", on_done := "") -> Dictionary:
	var down := kind != "clock"
	return {"id": JsonDoc.new_id("k"), "plugin": plugin, "name": p_name, "kind": kind, "value": max_value if down else 0, "max": max_value,
		"direction": "down" if down else "up", "advance": advance if not advance.is_empty() else {"on": "manual", "amount": 1},
		"audience": audience, "on_done": on_done, "done": false}


static func add_event(track: Dictionary) -> Dictionary:
	return {"t": "track.add", "track": track}


static func is_done(track: Dictionary) -> bool:
	return (float(track.get("value", 0)) <= 0.0) if str(track.get("direction", "down")) == "down" else (float(track.get("value", 0)) >= float(track.get("max", 0)))


## Move a track by `n` steps in its direction (negative to move it back),
## and whatever is linked to it by the same amount. [] when nothing moves.
static func advance(state: EncounterState, id: String, n := 1) -> Array:
	var moves := {}
	_collect(state, id, n, moves)
	return _events(state, moves)


## Tracks that a roll's outcome advances: `advance.on` is "roll" (every
## roll) or "roll_outcome" with `outcomes` containing the entry's outcome;
## `advance.actor` narrows to one actor's rolls.
static func on_roll(state: EncounterState, entry: Dictionary) -> Array:
	var moves := {}
	var ids := state.encounter.tracks.keys()
	ids.sort()
	var outcome := str(entry.get("result", {}).get("outcome", ""))
	for id in ids:
		var tr: Dictionary = state.encounter.tracks[id]
		var adv: Dictionary = tr.get("advance", {})
		var on := str(adv.get("on", "manual"))
		if bool(tr.get("done", false)):
			continue
		if str(adv.get("actor", "")) != "" and str(adv.get("actor", "")) != str(entry.get("actor", "")):
			continue
		if on == "roll" or (on == "roll_outcome" and (adv.get("outcomes", []) as Array).has(outcome)):
			_collect(state, str(id), int(adv.get("amount", 1)), moves)
	return _events(state, moves)


## Tracks that a trigger kind advances ("rest", "long_rest", "turn", "session").
static func on_trigger(state: EncounterState, kind: String) -> Array:
	var moves := {}
	var ids := state.encounter.tracks.keys()
	ids.sort()
	for id in ids:
		var tr: Dictionary = state.encounter.tracks[id]
		var adv: Dictionary = tr.get("advance", {})
		if not bool(tr.get("done", false)) and str(adv.get("on", "manual")) == kind:
			_collect(state, str(id), int(adv.get("amount", 1)), moves)
	return _events(state, moves)


## Gather how far each track moves (links included) before making any
## event, so a track reached twice moves once by the sum.
static func _collect(state: EncounterState, id: String, n: int, moves: Dictionary, depth := 0) -> void:
	var tr: Dictionary = state.encounter.tracks.get(id, {})
	if tr.is_empty() or n == 0 or depth > 8:
		return
	moves[id] = int(moves.get(id, 0)) + n
	var linked := str(tr.get("linked", ""))
	if linked != "" and linked != id and n > 0:
		_collect(state, linked, n, moves, depth + 1)


static func _events(state: EncounterState, moves: Dictionary) -> Array:
	var out := []
	var ids := moves.keys()
	ids.sort()
	for id in ids:
		var tr: Dictionary = state.encounter.tracks[id]
		var n := int(moves[id])
		var v := float(tr.get("value", 0))
		var mx := float(tr.get("max", 0))
		var next_v := clampf(v - n if str(tr.get("direction", "down")) == "down" else v + n, 0.0, mx)
		if next_v == v:
			continue
		var changes := {"value": next_v}
		var probe: Dictionary = JsonDoc.deep(tr)
		probe.value = next_v
		var done := is_done(probe)
		if done != bool(tr.get("done", false)):
			changes.done = done
		out.append({"t": "track.set", "id": id, "changes": changes})
	return out


## Ids of tracks a batch of events completes (for the `track_done` hook).
static func completed_by(state: EncounterState, events: Array) -> Array:
	var out := []
	for ev in events:
		if str(ev.get("t", "")) == "track.set" and ev.get("changes", {}).get("done", false) == true:
			out.append(str(ev.id))
	return out
