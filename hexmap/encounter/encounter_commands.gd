class_name EncounterCommands
extends RefCounted
## The Table's undoable actions over an EncounterState. `run()` applies an
## event and records it in the EventLog, so one gesture is one undo step;
## the named methods are the events the Table's tools send, with the
## bookkeeping (fog after a move, turn order stepping) done here so every
## caller gets it right. Nothing here needs a window: the Player's client
## will reuse it for its own local moves once networking arrives.

var state: EncounterState
var history: EventLog
## When set, turns go through the kernel's runner (hooks, expiry, both
## shapes); without one the built-in list system steps the stored order.
var kernel: RulesKernel


func _init(p_state: EncounterState, p_history: EventLog) -> void:
	state = p_state
	history = p_history
	if history.state == null:
		history.state = state


## Validate, apply and record. Returns "" or why the event was refused.
func run(ev: Dictionary, label := "", reason: Dictionary = {}) -> String:
	return history.record(ev, label, reason)


## Several events as one undo step (all or nothing).
func run_all(events: Array, label: String, reason: Dictionary = {}) -> String:
	return history.record_all(events, label, reason)


func begin_group() -> void:
	history.begin_group()


func end_group(label: String) -> void:
	history.end_group(label)


# ------------------------------------------------------------------- scenes --

func add_scene(scene: Dictionary, activate := true) -> String:
	var why := run({"t": "scene.add", "scene": scene}, "Add scene")
	if why == "" and activate:
		run({"t": "scene.activate", "id": str(scene.id)}, "Show scene")
	return why


func remove_scene(id: String) -> String:
	return run({"t": "scene.remove", "id": id}, "Remove scene")


func activate_scene(id: String) -> String:
	return run({"t": "scene.activate", "id": id}, "Show scene")


func rename_scene(id: String, p_name: String) -> String:
	return run({"t": "scene.set", "id": id, "changes": {"name": p_name}}, "Rename scene")


# ------------------------------------------------------------------- tokens --

func add_token(scene_id: String, tk: Dictionary) -> String:
	return run({"t": "token.add", "scene": scene_id, "token": tk}, "Add %s" % str(tk.get("name", "token")))


func remove_tokens(scene_id: String, ids: Array) -> String:
	begin_group()
	var why := ""
	for id in ids:
		why = run({"t": "token.remove", "scene": scene_id, "id": str(id)})
		if why != "":
			break
	end_group("Remove %d token%s" % [ids.size(), "" if ids.size() == 1 else "s"])
	return why


func update_token(scene_id: String, id: String, changes: Dictionary, label := "Edit token") -> String:
	return run({"t": "token.set", "scene": scene_id, "id": id, "changes": changes}, label)


## Move a token and, when fog is on, reveal what it now sees. One undo step.
func move_token(scene_id: String, id: String, to: Vector2, by := "gm") -> String:
	begin_group()
	var why := kernel.move_token(scene_id, id, to, by) if kernel != null else run({"t": "token.set", "scene": scene_id, "id": id, "changes": {"pos": [to.x, to.y]}})
	if why == "":
		explore_from(scene_id, [state.token(scene_id, id)])
	end_group("Move %s" % str(state.token(scene_id, id).get("name", "token")))
	return why


## Record as explored whatever these tokens see now (no-op without fog).
func explore_from(scene_id: String, tokens: Array) -> void:
	if not state.fog_enabled(scene_id):
		return
	var seen: Array = Vision.of(state, scene_id, tokens).cells
	var fresh := state.unexplored(scene_id, seen)
	if not fresh.is_empty():
		run({"t": "fog.reveal", "scene": scene_id, "cells": fresh})


# ----------------------------------------------------------------- elements --

func set_door(scene_id: String, wall_id: String, door_state: String) -> String:
	return run({"t": "element.set", "scene": scene_id, "ref": LayerTree.ref("walls", wall_id), "changes": {"state": door_state}},
		{"open": "Open door", "closed": "Close door", "locked": "Lock door"}.get(door_state, "Door"))


func set_light(scene_id: String, light_id: String, on: bool) -> String:
	return run({"t": "element.set", "scene": scene_id, "ref": LayerTree.ref("lights", light_id), "changes": {"on": on}},
		"Light on" if on else "Light off")


## Show a GM-only element to players (`shown` true) or hide one.
func set_revealed(scene_id: String, collection: String, id: String, shown: bool) -> String:
	return run({"t": "element.set", "scene": scene_id, "ref": LayerTree.ref(collection, id), "changes": {"hidden": not shown}},
		"Reveal" if shown else "Hide")


## Drop every override on an element: back to how the map has it.
func reset_element(scene_id: String, ref: String) -> String:
	var ov := state.override_of(scene_id, ref)
	if ov.is_empty():
		return ""
	var clear := {}
	for k in ov:
		clear[k] = null
	return run({"t": "element.set", "scene": scene_id, "ref": ref, "changes": clear}, "Reset")


# ---------------------------------------------------------------------- fog --

func set_fog(scene_id: String, enabled: bool) -> String:
	return run({"t": "fog.set", "scene": scene_id, "enabled": enabled}, "Fog on" if enabled else "Fog off")


func reveal_cells(scene_id: String, cells: Array) -> String:
	var fresh := state.unexplored(scene_id, cells)
	if fresh.is_empty():
		return ""
	return run({"t": "fog.reveal", "scene": scene_id, "cells": fresh}, "Reveal")


func hide_cells(scene_id: String, cells: Array) -> String:
	var keys := []
	for c in cells:
		keys.append(c if c is String else HexMap.cell_key(c))
	return run({"t": "fog.hide", "scene": scene_id, "cells": keys}, "Hide")


func reset_fog(scene_id: String) -> String:
	return run({"t": "fog.hide", "scene": scene_id, "cells": state.explored(scene_id).keys()}, "Reset fog")


# -------------------------------------------------------------------- turns --

func set_turn_mode(mode: String) -> String:
	return run({"t": "turns.set", "changes": {"mode": mode}}, {"free": "Free movement", "dm": "DM picks who moves", "ordered": "Ordered turns"}.get(mode, "Turn mode"))


## dm mode: who may move now.
func set_active_tokens(ids: Array) -> String:
	return run({"t": "turns.set", "changes": {"active": ids}}, "Who may move")


func toggle_active_token(id: String) -> String:
	var active: Array = (state.encounter.turns.get("active", []) as Array).duplicate()
	if active.has(id):
		active.erase(id)
	else:
		active.append(id)
	return set_active_tokens(active)


## ordered mode: let the turn system order the scene's tokens and begin.
func start_turns(scene_id: String, system_id := "") -> String:
	if kernel != null:
		var sid := system_id if system_id != "" else str(state.encounter.turns.get("system", "list"))
		return kernel.turns.start(scene_id, sid if kernel.turns.strategies.has(sid) else "list")
	var turns := state.encounter.turns
	var sid := system_id if system_id != "" else str(turns.get("system", "list"))
	var sys := TurnSystem.get_system(sid)
	var built := sys.build_order(state, scene_id)
	return run({"t": "turns.set", "changes": {"mode": "ordered", "system": sys.id, "order": built.get("order", []), "data": built.get("data", {}),
		"turn": 0, "round": 1, "running": true}}, "Start turns")


func set_turn_order(order: Array) -> String:
	return run({"t": "turns.set", "changes": {"order": order}}, "Reorder")


func stop_turns() -> String:
	if kernel != null:
		return kernel.turns.stop()
	return run({"t": "turns.set", "changes": {"running": false}}, "End turns")


## `opts` as TurnRunner.next has them: {by, expect: {round, turn}}.
func next_turn(opts := {}) -> String:
	if kernel != null:
		return kernel.turns.next(opts)
	var late := TurnRunner.stale(state, opts.get("expect"))
	if late != "":
		return late
	var turns := state.encounter.turns
	var changes := TurnSystem.get_system(str(turns.get("system", "list"))).next(turns)
	if changes.is_empty():
		return "no turn order"
	return run({"t": "turns.set", "changes": changes}, "Next turn")


func previous_turn() -> String:
	if kernel != null:
		return kernel.turns.previous()
	var turns := state.encounter.turns
	var changes := TurnSystem.get_system(str(turns.get("system", "list"))).previous(turns)
	if changes.is_empty():
		return "already at the start" if not (turns.get("order", []) as Array).is_empty() else "no turn order"
	return run({"t": "turns.set", "changes": changes}, "Previous turn")


# ------------------------------------------------------------------ players --

func add_player(p: Dictionary) -> String:
	return run({"t": "player.add", "player": p}, "Add player")


func remove_player(id: String) -> String:
	return run({"t": "player.remove", "id": id}, "Remove player")


func update_player(id: String, changes: Dictionary) -> String:
	return run({"t": "player.set", "id": id, "changes": changes}, "Edit player")


func rename(p_name: String) -> String:
	return run({"t": "encounter.set", "changes": {"name": p_name}}, "Rename encounter")
