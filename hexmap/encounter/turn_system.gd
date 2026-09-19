class_name TurnSystem
extends RefCounted
## How turns are ordered in an encounter's "ordered" mode. Hexmap knows
## nothing about initiative bonuses, speed, phases or ties: a turn system
## decides the order (build_order) and how to step through it (next /
## previous), and may keep its own state in `data`, which Hexmap stores in
## the encounter untouched and replicates as is.
##
## This class is the *internal* interface. Game systems are not GDScript
## dropped into a folder — that would hand a plugin the whole engine — but
## data: a manifest with the token stats the system needs and a sandboxed
## ordering expression, loaded by a built-in subclass (to come). Whatever
## the system is, only the Table runs it: players get the order and
## `data.labels` as plain data and need no plugin to show them.
##
## The one system Hexmap ships is "list": the DM arranges the order by hand.
## It is not a game system; it is what you get without one.

var id := "list"
var name := "As listed"
var description := "The DM arranges the order by hand."


## The order for a scene's tokens and any system state to keep with it:
## {"order": [token ids], "data": {}}. `data` is the plugin's own; Hexmap
## never reads it. The default keeps the existing order where the tokens
## still exist and appends newcomers.
func build_order(state: EncounterState, scene_id: String) -> Dictionary:
	var turns := state.encounter.turns
	var have := {}
	var order := []
	for id in turns.get("order", []):
		if not state.token(scene_id, str(id)).is_empty():
			order.append(str(id))
			have[str(id)] = true
	for t in state.tokens(scene_id):
		if not have.has(str(t.id)):
			order.append(str(t.id))
	return {"order": order, "data": {}}


## Changes to the turns block for advancing one turn. `turns` is the block
## as it is now; return only what changes (a `turns.set` event's changes).
func next(turns: Dictionary) -> Dictionary:
	var n: int = (turns.get("order", []) as Array).size()
	if n == 0:
		return {}
	var turn := int(turns.get("turn", 0)) + 1
	var round := int(turns.get("round", 1))
	if turn >= n:
		turn = 0
		round += 1
	return {"turn": turn, "round": round, "running": true}


func previous(turns: Dictionary) -> Dictionary:
	var n: int = (turns.get("order", []) as Array).size()
	if n == 0:
		return {}
	var turn := int(turns.get("turn", 0)) - 1
	var round := int(turns.get("round", 1))
	if turn < 0:
		if round <= 1:
			return {}
		turn = n - 1
		round -= 1
	return {"turn": turn, "round": round}


## Something to show beside a token in the order (an initiative value, a
## phase). Systems put these in `data.labels` when they build the order so
## clients without the system still show them; the list system has none.
func label(turns: Dictionary, token_id: String) -> String:
	return str(turns.get("data", {}).get("labels", {}).get(token_id, ""))


# ----------------------------------------------------------------- registry --

static var _systems: Dictionary = {}


static func register(system: TurnSystem) -> void:
	_systems[system.id] = system


static func unregister(id: String) -> void:
	_systems.erase(id)


## The system with this id, or the list system when it is unknown (a plugin
## that is not installed here must not break an encounter that used it).
static func get_system(id: String) -> TurnSystem:
	if _systems.is_empty():
		register(TurnSystem.new())
	return _systems.get(id, _systems.get("list"))


static func all_systems() -> Array:
	if _systems.is_empty():
		register(TurnSystem.new())
	var out := _systems.values()
	out.sort_custom(func(a: TurnSystem, b: TurnSystem) -> bool: return a.id < b.id if a.id != "list" and b.id != "list" else a.id == "list")
	return out
