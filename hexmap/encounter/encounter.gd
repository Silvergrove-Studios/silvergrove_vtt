class_name Encounter
extends RefCounted
## The encounter document in memory: the JSON described in
## docs/encounter-format.md, plus load/save and lookups. It references maps
## and never edits them. Changes go through EncounterState.apply() as events
## so they can be undone and replicated; this class only holds the data.

signal changed(what: String, scene_id: String)

const FORMAT := "silvergrove.encounter"
const VERSION := 2
## mode: free (anyone moves any visible token) | dm (the DM picks who may
## move: `active`) | ordered (a turn system orders them: `order`, `turn`,
## `round`; `system` names it, `data` is its own state).
const TURN_MODES := ["free", "dm", "ordered"]
const DEFAULT_TURNS := {"mode": "free", "order": [], "turn": 0, "round": 1, "running": false, "active": [], "system": "list", "data": {},
	# version 2: the shape of turns (ordered | focus), the plugin whose
	# strategy runs them, the focus holder ("token:id", "actor:id", "gm"
	# or ""), per-participant counters, focus requests and history
	"strategy": "ordered", "plugin": "", "focus": "", "counters": {}, "requests": [], "history": []}
const TURN_STRATEGIES := ["ordered", "focus"]
const DEFAULT_CLOCK := {"session": 1, "scene": 1, "day": 1, "minute": 0, "rests": 0}

var doc: Dictionary = {}
## Where it was loaded from / last saved to. Empty for a new encounter.
var path: String = ""
var dirty: bool = false


static func create(p_name: String) -> Encounter:
	var e := Encounter.new()
	var now := JsonDoc.now()
	e.doc = {
		"format": FORMAT,
		"version": VERSION,
		"id": JsonDoc.uuid(),
		"name": p_name,
		"scenes": [],
		"active_scene": "",
		"turns": DEFAULT_TURNS.duplicate(true),
		"players": [],
		"notes": [],
		"actors": {},
		"effects": {},
		"resources": {},
		"state": {"ext": {}},
		"tracks": {},
		"pending": {"prompts": {}, "rolls": {}},
		"clock": DEFAULT_CLOCK.duplicate(),
		"log": [],
		"rng": {"seed": int(randi()) & 0x7fffffff, "index": 0},
		# the campaign this session belongs to ({id, path}) and the
		# campaign-scoped plugin state carried in and banked back out
		"campaign": {"id": "", "path": "", "ext": {}},
		# named snapshots the table can go back to
		"checkpoints": [],
		"meta": {"author": "", "description": "", "created": now, "modified": now},
		"ext": {},
	}
	return e


## A scene over one level of a map. `map_path` should be relative to where
## the encounter will be saved when it can be.
static func new_scene(map: HexMap, level_id: String, p_name := "", map_path := "") -> Dictionary:
	var lvl := map.level_by_id(level_id)
	return {
		"id": JsonDoc.new_id("s"),
		"name": p_name if p_name != "" else "%s — %s" % [map.name, str(lvl.get("name", level_id))],
		"map": str(map.doc.get("id", "")),
		"map_path": map_path if map_path != "" else map.path.get_file(),
		"level": level_id,
		"overrides": {},
		"fog": {"enabled": false, "explored": []},
		"tokens": [],
		"regions": {},
		"cells": {},
	}


## `owner` and `light` are simply absent when a token has none: an event's
## `null` means "remove", so a stored null could not be undone exactly.
static func new_token(p_name: String, pos: Vector2, extra := {}) -> Dictionary:
	var t := {
		"id": JsonDoc.new_id("t"), "name": p_name, "label": p_name.left(2).to_upper(),
		"art": "", "color": "#c0392b",
		"pos": [pos.x, pos.y], "size": 1, "rot": 0, "elevation": 0,
		"hidden": false,
		"vision": {"radius": 6},
		"tags": [],
	}
	for k in extra:
		if extra[k] == null:
			t.erase(k)
		else:
			t[k] = extra[k]
	return t


static func new_player(p_name: String, color := "#4f9cf6") -> Dictionary:
	return {"id": JsonDoc.new_id("pl"), "name": p_name, "color": color}


# ------------------------------------------------------------------ accessors --

var name: String:
	get: return str(doc.get("name", "Untitled"))

var scenes: Array:
	get: return doc.get("scenes", [])

var players: Array:
	get: return doc.get("players", [])

var turns: Dictionary:
	get: return doc.get("turns", {})

## Actors by id: anything with a sheet (docs/campaign-format.md).
var actors: Dictionary:
	get: return doc.actors
## Effect records by id (docs/encounter-format.md, version 2).
var effects: Dictionary:
	get: return doc.effects
## "<ref>" -> plugin id -> name -> pool or track.
var resources: Dictionary:
	get: return doc.resources
## Progress tracks (countdowns, clocks, subsystems) by id.
var tracks: Dictionary:
	get: return doc.tracks
## Open prompts and pending rolls: {"prompts": {id: …}, "rolls": {id: …}}.
var pending: Dictionary:
	get: return doc.pending
## In-game time: session, scene, day, minute of the day, rests taken.
var clock: Dictionary:
	get: return doc.clock
## Informational entries (rolls, notes) in order.
var log: Array:
	get: return doc.log
## The campaign reference and campaign-scoped plugin state: {id, path, ext}.
var campaign: Dictionary:
	get: return doc.campaign
## Named snapshots: [{id, name, when, snapshot}].
var checkpoints: Array:
	get: return doc.checkpoints
var active_scene_id: String:
	get: return str(doc.get("active_scene", ""))


func scene(id: String) -> Dictionary:
	for s in scenes:
		if str(s.get("id", "")) == id:
			return s
	return {}


func scene_index(id: String) -> int:
	var arr: Array = scenes
	for i in arr.size():
		if str(arr[i].get("id", "")) == id:
			return i
	return -1


func active_scene() -> Dictionary:
	var s := scene(active_scene_id)
	if s.is_empty() and not scenes.is_empty():
		return scenes[0]
	return s


static func token_in(p_scene: Dictionary, id: String) -> Dictionary:
	for t in p_scene.get("tokens", []):
		if str(t.get("id", "")) == id:
			return t
	return {}


static func token_index(p_scene: Dictionary, id: String) -> int:
	var arr: Array = p_scene.get("tokens", [])
	for i in arr.size():
		if str(arr[i].get("id", "")) == id:
			return i
	return -1


func actor(id: String) -> Dictionary:
	return doc.actors.get(id, {})


func effect(id: String) -> Dictionary:
	return doc.effects.get(id, {})


## The events that take an actor off the table with everything kept under
## it: the effects on it and on its tokens, its pools and theirs, its tokens,
## then the actor (a playtest's removed goblins left their deaths behind, and
## the next ones given their ids came back dead). [] for no such actor.
func actor_removal_events(id: String) -> Array:
	if not doc.actors.has(id):
		return []
	var refs := ["actor:" + id]
	var tokens := []
	for sc in scenes:
		for tk in sc.tokens:
			if str(tk.get("actor", "")) == id:
				refs.append("token:" + str(tk.id))
				tokens.append({"t": "token.remove", "scene": str(sc.id), "id": str(tk.id)})
	var events := []
	var fids: Array = doc.effects.keys()
	fids.sort()
	for fid in fids:
		if refs.has(str(doc.effects[fid].get("on", ""))):
			events.append({"t": "effect.remove", "id": str(fid)})
	for ref in refs:
		var held: Dictionary = doc.resources.get(ref, {})
		for plugin in held:
			for name in held[plugin]:
				events.append({"t": "resource.set", "ref": ref, "plugin": str(plugin), "name": str(name), "record": null})
	events.append_array(tokens)
	events.append({"t": "actor.remove", "id": id})
	return events


## Several actors off the table as one batch: each one's removal events,
## then — once for the batch — their tokens out of the turn order, its
## groups, labels and budgets. (An order left naming a removed token picked
## up the next one given its id: a playtest's chapel goblin took the
## lookout's place.)
func removal_events(ids: Array) -> Array:
	var events := []
	var gone := []
	for id in ids:
		for sc in scenes:
			for tk in sc.tokens:
				if str(tk.get("actor", "")) == str(id):
					gone.append(str(tk.id))
		events.append_array(actor_removal_events(str(id)))
	var pruned := turns_without(gone)
	if not pruned.is_empty():
		events.append({"t": "turns.set", "changes": pruned})
	return events


## The turns' changes that take these tokens out of the order (a group that
## loses its last member goes too), the groups, the labels and the budgets,
## whoever is up staying up — or, gone, the turn passing to the next. {}
## when none of them is there.
func turns_without(token_ids: Array) -> Dictionary:
	var t: Dictionary = doc.turns
	var gone := {}
	for id in token_ids:
		gone[str(id)] = true
	var data: Dictionary = JsonDoc.deep(t.get("data", {})) if t.get("data") is Dictionary else {}
	var groups: Dictionary = data.get("groups", {}) if data.get("groups") is Dictionary else {}
	var labels: Dictionary = data.get("labels", {}) if data.get("labels") is Dictionary else {}
	var counters: Dictionary = JsonDoc.deep(t.get("counters", {})) if t.get("counters") is Dictionary else {}
	var changed := false
	for gid in groups.keys():
		var members: Array = groups[gid].get("tokens", [])
		var kept := members.filter(func(x: Variant) -> bool: return not gone.has(str(x)))
		if kept.size() == members.size():
			continue
		changed = true
		if kept.is_empty():
			groups.erase(gid)
			labels.erase("group:" + str(gid))
		else:
			groups[gid].tokens = kept
	for id in gone:
		for k in [id, "token:" + str(id)]:
			if labels.has(k):
				labels.erase(k)
				changed = true
			if counters.has(k):
				counters.erase(k)
				changed = true
	var order: Array = t.get("order", [])
	var turn := int(t.get("turn", 0))
	var kept_order := []
	var before_turn := 0
	for i in order.size():
		var entry := str(order[i])
		if gone.has(entry) or (entry.begins_with("group:") and not groups.has(entry.substr(6))):
			changed = true
			continue
		kept_order.append(entry)
		if i < turn:
			before_turn += 1
	if not changed:
		return {}
	var out := {"order": kept_order, "counters": counters}
	if not data.is_empty():
		out.data = data
	# the one up stays up; one that went passes the turn to the next
	var cur := str(order[turn]) if turn >= 0 and turn < order.size() else ""
	var at := kept_order.find(cur)
	out.turn = at if at >= 0 else (before_turn if before_turn < kept_order.size() else 0)
	return out


func player(id: String) -> Dictionary:
	for p in players:
		if str(p.get("id", "")) == id:
			return p
	return {}


func checkpoint(id: String) -> Dictionary:
	for c in checkpoints:
		if str(c.get("id", "")) == id:
			return c
	return {}


## The document as a checkpoint holds it: everything but the checkpoints
## themselves (a snapshot inside a snapshot would grow without bound).
## Keys a restore never touches are left out too.
const SNAPSHOT_SKIPS := ["checkpoints", "format", "version", "id"]

func snapshot() -> Dictionary:
	var out := {}
	for k in doc:
		if not SNAPSHOT_SKIPS.has(str(k)):
			out[k] = JsonDoc.deep(doc[k])
	return out


## Put a snapshot back, in place (the doc Dictionary is what everything
## holds). Returns what was there, as a snapshot.
func restore_snapshot(snap: Dictionary) -> Dictionary:
	var before := snapshot()
	for k in doc.keys():
		if not SNAPSHOT_SKIPS.has(str(k)):
			doc.erase(k)
	for k in snap:
		if not SNAPSHOT_SKIPS.has(str(k)):
			doc[k] = JsonDoc.deep(snap[k])
	_upgrade(VERSION)
	return before


func player_index(id: String) -> int:
	var arr: Array = players
	for i in arr.size():
		if str(arr[i].get("id", "")) == id:
			return i
	return -1


## Map ids this encounter needs, in scene order without repeats.
func map_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in scenes:
		var id := str(s.get("map", ""))
		if id != "" and not out.has(id):
			out.append(id)
	return out


## Mark modified and tell listeners. `what` is a coarse hint ("scenes",
## "tokens", "overrides", "fog", "initiative", "players", "encounter").
func touch(what: String = "", scene_id := "") -> void:
	dirty = true
	doc.get("meta", {})["modified"] = JsonDoc.now()
	changed.emit(what, scene_id)


# ------------------------------------------------------------------- file IO --

func to_json() -> String:
	doc["format"] = FORMAT
	doc["version"] = VERSION
	return JsonDoc.stringify(doc)


## Parse a document. Returns null and fills `error` on failure.
static func from_json(text: String, error: Array = []) -> Encounter:
	var d := JsonDoc.parse(text, error)
	if d.is_empty():
		return null
	if d.get("format", "") != FORMAT:
		error.append("not a %s document (format is '%s')" % [FORMAT, d.get("format", "")])
		return null
	var version := int(d.get("version", 0))
	if version > VERSION:
		error.append("written by a newer Hexmap (version %d, this reads %d)" % [version, VERSION])
		return null
	var e := Encounter.new()
	e.doc = d
	e._upgrade(version)
	return e


func _upgrade(_from_version: int) -> void:
	# Version 1 had no rules blocks: version 2 adds actors, effects,
	# resources, plugin state, the informational log and the dice stream,
	# all empty here. Then fill in anything a hand-written file omitted.
	for k in ["scenes", "players", "notes", "log"]:
		if not doc.has(k):
			doc[k] = []
	for k in ["meta", "ext", "actors", "effects", "resources", "state", "tracks", "pending", "clock"]:
		if not doc.has(k):
			doc[k] = {}
	if not doc["state"].has("ext"):
		doc["state"]["ext"] = {}
	for k in ["prompts", "rolls"]:
		if not doc["pending"].has(k):
			doc["pending"][k] = {}
	for k in DEFAULT_CLOCK:
		if not doc["clock"].has(k):
			doc["clock"][k] = DEFAULT_CLOCK[k]
	if not (doc.get("rng") is Dictionary):
		doc["rng"] = {"seed": int(randi()) & 0x7fffffff, "index": 0}
	if not (doc.get("campaign") is Dictionary):
		doc["campaign"] = {}
	for k in ["id", "path"]:
		if not doc["campaign"].has(k):
			doc["campaign"][k] = ""
	if not (doc["campaign"].get("ext") is Dictionary):
		doc["campaign"]["ext"] = {}
	if not (doc.get("checkpoints") is Array):
		doc["checkpoints"] = []
	doc["version"] = VERSION
	if doc.has("initiative") and not doc.has("turns"):
		# Pre-release files had a D&D-shaped "initiative" block.
		doc["turns"] = doc["initiative"]
		doc["turns"]["mode"] = "ordered" if not (doc["turns"].get("order", []) as Array).is_empty() else "free"
	doc.erase("initiative")
	if not doc.has("turns"):
		doc["turns"] = {}
	var turns: Dictionary = doc["turns"]
	for k in DEFAULT_TURNS:
		if not turns.has(k):
			turns[k] = JsonDoc.deep(DEFAULT_TURNS[k])
	if not TURN_MODES.has(str(turns.mode)):
		turns.mode = "free"
	if not TURN_STRATEGIES.has(str(turns.strategy)):
		turns.strategy = "ordered"
	for s in doc["scenes"]:
		fill_scene(s)
	for id in doc["actors"]:
		fill_actor(doc["actors"][id])
	if not doc.has("active_scene"):
		doc["active_scene"] = str(doc["scenes"][0].get("id", "")) if not (doc["scenes"] as Array).is_empty() else ""
	if not doc.has("id"):
		doc["id"] = JsonDoc.uuid()


## Give a hand-written or partial scene every field it is expected to have.
## Applied on load and on scene.add so a scene built by hand and one that
## went through a file agree byte for byte (the replay tests rely on it).
static func fill_scene(s: Dictionary) -> void:
	if not s.has("overrides"):
		s["overrides"] = {}
	if not s.has("tokens"):
		s["tokens"] = []
	if not s.has("fog"):
		s["fog"] = {}
	if not s["fog"].has("explored"):
		s["fog"]["explored"] = []
	(s["fog"]["explored"] as Array).sort()
	if not s["fog"].has("enabled"):
		s["fog"]["enabled"] = false
	for k in ["regions", "cells"]:
		if not (s.get(k) is Dictionary):
			s[k] = {}
	for t in s["tokens"]:
		fill_token(t)


## Give a hand-written or partial actor every field it is expected to have.
static func fill_actor(a: Dictionary) -> void:
	if not a.has("kind"):
		a["kind"] = "custom"
	if not a.has("name"):
		a["name"] = ""
	for k in ["ext", "derived", "token", "audience"]:
		if not (a.get(k) is Dictionary):
			a[k] = {}
	if not (a.get("overlays") is Array):
		a["overlays"] = []


## Give a hand-written or partial token every field it is expected to have.
static func fill_token(t: Dictionary) -> void:
	var defaults := new_token(str(t.get("name", "Token")), Vector2.ZERO)
	for k in defaults:
		if not t.has(k):
			t[k] = defaults[k]
	for k in ["owner", "light"]:
		if t.has(k) and t[k] == null:
			t.erase(k)


func save(p_path: String = "") -> Error:
	if p_path != "":
		path = p_path
	if path == "":
		return ERR_FILE_BAD_PATH
	var real := path
	if DirAccess.dir_exists_absolute(path):
		real = path.path_join("encounter.json")
	var f := FileAccess.open(real, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	f.close()
	dirty = false
	return OK


static func load_file(p_path: String, error: Array = []) -> Encounter:
	var real := p_path
	# A bundle directory holds encounter.json.
	if DirAccess.dir_exists_absolute(p_path):
		real = p_path.path_join("encounter.json")
	if not FileAccess.file_exists(real):
		error.append("no such file: " + real)
		return null
	var e := from_json(FileAccess.get_file_as_string(real), error)
	if e != null:
		e.path = p_path
	return e


## The directory scene `map_path`s are relative to: beside the file, or
## beside the bundle directory.
func base_dir() -> String:
	return path.get_base_dir() if path != "" else ""
