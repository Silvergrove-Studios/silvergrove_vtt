class_name EncounterState
extends RefCounted
## The running encounter: the Encounter document, the maps it references,
## and the one way to change it — apply(event). Every change is a small
## serialisable event (docs/encounter-format.md, "Events"); apply() returns
## the inverse event, so undo, autosave, replication to players and replay
## all work from the same log. validate() says whether an event is
## well-formed against the current state and allowed() whether a given
## player may send it. The Table applies; players request.
##
## effective() merges a scene's overrides onto a map element, which is how
## the canvas and Vision see doors that are open now and lights that are
## out, while the map file stays as drawn.

## An event was applied. Hosts broadcast `event`; History keeps `inverse`.
signal applied(event: Dictionary, inverse: Dictionary)

const EVENTS := ["encounter.set", "scene.add", "scene.remove", "scene.set", "scene.activate",
	"token.add", "token.remove", "token.set", "element.set",
	"fog.set", "fog.reveal", "fog.hide", "initiative.set",
	"player.add", "player.remove", "player.set"]
## What a player may change on a token they own.
const PLAYER_TOKEN_FIELDS := ["pos", "rot", "elevation"]
## Which overlay fields make sense on which collections; `effective()`
## merges any, these are what the table offers.
const OVERRIDE_FIELDS := {
	"walls": ["state", "hidden"], "props": ["hidden"], "lights": ["on", "hidden"], "notes": ["hidden"],
}
const COLLECTIONS := ["props", "walls", "lights", "notes"]

var encounter: Encounter
## map id -> HexMap
var maps: Dictionary = {}
## Problems found resolving maps, for the UI to show.
var warnings: PackedStringArray = []


func _init(p_encounter: Encounter = null) -> void:
	encounter = p_encounter if p_encounter != null else Encounter.create("Untitled")


# --------------------------------------------------------------------- maps --

## Load every map the encounter references, by `map_path` relative to the
## encounter file (or `base_dir`). Missing or mismatched maps are warnings;
## scenes without a map still exist, they just cannot be drawn.
func resolve_maps(base_dir := "") -> PackedStringArray:
	warnings.clear()
	if base_dir == "":
		base_dir = encounter.base_dir()
	for s in encounter.scenes:
		var id := str(s.get("map", ""))
		if maps.has(id):
			continue
		var p := str(s.get("map_path", ""))
		if p == "":
			warnings.append("scene '%s' names no map file" % str(s.get("name", s.get("id", ""))))
			continue
		if not p.is_absolute_path():
			p = base_dir.path_join(p)
		var err: Array = []
		var m := HexMap.load_file(p, err)
		if m == null:
			warnings.append("scene '%s': %s" % [str(s.get("name", "")), "; ".join(PackedStringArray(err))])
			continue
		if str(m.doc.get("id", "")) != id:
			warnings.append("scene '%s': %s is a different map than the one this scene was made on (using it anyway)" % [str(s.get("name", "")), p.get_file()])
			s["map"] = str(m.doc.get("id", ""))
			id = s["map"]
		maps[id] = m
	return warnings


## Register a map that arrived some other way (a player got it from the
## table).
func attach_map(m: HexMap) -> void:
	maps[str(m.doc.get("id", ""))] = m


func map_for(scene_id: String) -> HexMap:
	return maps.get(str(encounter.scene(scene_id).get("map", "")), null)


## The base map level a scene sits on, as stored in the map ({} if the map
## is missing).
func level_for(scene_id: String) -> Dictionary:
	var m := map_for(scene_id)
	if m == null:
		return {}
	return m.level_by_id(str(encounter.scene(scene_id).get("level", "")))


# ---------------------------------------------------------------- effective --

## A map element with the scene's overrides merged on. Never the stored
## object itself, so callers can't edit the map by accident.
func effective(scene_id: String, collection: String, obj: Dictionary) -> Dictionary:
	var out: Dictionary = obj.duplicate(true)
	var ov: Dictionary = encounter.scene(scene_id).get("overrides", {}).get(LayerTree.ref(collection, str(obj.get("id", ""))), {})
	for k in ov:
		out[k] = JsonDoc.deep(ov[k])
	return out


## The scene's level with every collection replaced by effective elements:
## what Vision and the canvas draw from. Terrain and the tree are shared,
## not copied.
func effective_level(scene_id: String) -> Dictionary:
	var lvl := level_for(scene_id)
	if lvl.is_empty():
		return {}
	var out := {}
	for k in lvl:
		out[k] = lvl[k]
	for c in COLLECTIONS:
		var arr := []
		for o in lvl.get(c, []):
			arr.append(effective(scene_id, c, o))
		out[c] = arr
	return out


func override_of(scene_id: String, ref: String) -> Dictionary:
	return encounter.scene(scene_id).get("overrides", {}).get(ref, {})


func tokens(scene_id: String) -> Array:
	return encounter.scene(scene_id).get("tokens", [])


func token(scene_id: String, id: String) -> Dictionary:
	return Encounter.token_in(encounter.scene(scene_id), id)


func tokens_owned_by(scene_id: String, player_id: String) -> Array:
	var out := []
	for t in tokens(scene_id):
		if t.get("owner", null) != null and str(t.owner) == player_id:
			out.append(t)
	return out


## What a player is allowed to know about: tokens that are not hidden.
func tokens_visible_to_players(scene_id: String) -> Array:
	var out := []
	for t in tokens(scene_id):
		if not bool(t.get("hidden", false)):
			out.append(t)
	return out


## Explored cells of a scene as a set (cell key -> true).
func explored(scene_id: String) -> Dictionary:
	var out := {}
	for k in encounter.scene(scene_id).get("fog", {}).get("explored", []):
		out[str(k)] = true
	return out


func fog_enabled(scene_id: String) -> bool:
	return bool(encounter.scene(scene_id).get("fog", {}).get("enabled", false))


# ------------------------------------------------------------------ validate --

## Why `ev` cannot be applied to the current state, or "" if it can.
func validate(ev: Dictionary) -> String:
	var t := str(ev.get("t", ""))
	if not EVENTS.has(t):
		return "unknown event '%s'" % t
	match t:
		"encounter.set":
			var e := _need_dict(ev, "changes")
			if e != "":
				return e
			for k in ["format", "version", "id", "scenes", "active_scene", "initiative", "players"]:
				if ev.changes.has(k):
					return "encounter.set cannot change '%s'; use its own events" % k
		"initiative.set":
			return _need_dict(ev, "changes")
		"scene.add":
			if not (ev.get("scene") is Dictionary) or str(ev.scene.get("id", "")) == "":
				return "scene.add needs a scene with an id"
			if not encounter.scene(str(ev.scene.id)).is_empty():
				return "scene '%s' already exists" % str(ev.scene.id)
		"scene.remove", "scene.activate":
			return _need_scene(ev, "id")
		"scene.set":
			var e := _need_scene(ev, "id")
			if e != "":
				return e
			e = _need_dict(ev, "changes")
			if e != "":
				return e
			for k in ["id", "tokens", "overrides", "fog"]:
				if ev.changes.has(k):
					return "scene.set cannot change '%s'; use its own events" % k
		"token.add":
			var e := _need_scene(ev, "scene")
			if e != "":
				return e
			if not (ev.get("token") is Dictionary) or str(ev.token.get("id", "")) == "":
				return "token.add needs a token with an id"
			if not token(str(ev.scene), str(ev.token.id)).is_empty():
				return "token '%s' already exists" % str(ev.token.id)
		"token.remove":
			return _need_token(ev)
		"token.set":
			var e := _need_token(ev)
			if e != "":
				return e
			e = _need_dict(ev, "changes")
			if e != "":
				return e
			if ev.changes.has("id"):
				return "token.set cannot change 'id'"
		"element.set":
			var e := _need_scene(ev, "scene")
			if e != "":
				return e
			var ref := str(ev.get("ref", ""))
			var parts := LayerTree.split(ref)
			if parts.size() != 2 or not COLLECTIONS.has(parts[0]) or parts[1] == "":
				return "element.set needs a ref like 'walls:w_1'"
			e = _need_dict(ev, "changes")
			if e != "":
				return e
			var lvl := level_for(str(ev.scene))
			if not lvl.is_empty() and HexMap.find_in(lvl, parts[0], parts[1]).is_empty():
				return "no %s on the map" % ref
		"fog.set":
			var e := _need_scene(ev, "scene")
			if e != "":
				return e
			if not (ev.get("enabled") is bool):
				return "fog.set needs 'enabled'"
		"fog.reveal", "fog.hide":
			var e := _need_scene(ev, "scene")
			if e != "":
				return e
			if not (ev.get("cells") is Array):
				return "%s needs 'cells'" % t
		"player.add":
			if not (ev.get("player") is Dictionary) or str(ev.player.get("id", "")) == "":
				return "player.add needs a player with an id"
			if not encounter.player(str(ev.player.id)).is_empty():
				return "player '%s' already exists" % str(ev.player.id)
		"player.remove":
			if encounter.player(str(ev.get("id", ""))).is_empty():
				return "no player '%s'" % str(ev.get("id", ""))
		"player.set":
			if encounter.player(str(ev.get("id", ""))).is_empty():
				return "no player '%s'" % str(ev.get("id", ""))
			var e := _need_dict(ev, "changes")
			if e != "":
				return e
			if ev.changes.has("id"):
				return "player.set cannot change 'id'"
	return ""


func _need_dict(ev: Dictionary, key: String) -> String:
	return "" if ev.get(key) is Dictionary else "%s needs '%s'" % [str(ev.get("t")), key]


func _need_scene(ev: Dictionary, key: String) -> String:
	var id := str(ev.get(key, ""))
	if encounter.scene(id).is_empty():
		return "no scene '%s'" % id
	return ""


func _need_token(ev: Dictionary) -> String:
	var e := _need_scene(ev, "scene")
	if e != "":
		return e
	if token(str(ev.scene), str(ev.get("id", ""))).is_empty():
		return "no token '%s' in scene '%s'" % [str(ev.get("id", "")), str(ev.scene)]
	return ""


## May `player_id` send this event? The table ("" — the DM) may send
## anything. A player may only move a token they own.
func allowed(ev: Dictionary, player_id: String) -> bool:
	if player_id == "":
		return true
	if str(ev.get("t", "")) != "token.set":
		return false
	var tk := token(str(ev.get("scene", "")), str(ev.get("id", "")))
	if tk.is_empty() or tk.get("owner", null) == null or str(tk.owner) != player_id:
		return false
	if not (ev.get("changes") is Dictionary):
		return false
	for k in ev.changes:
		if not PLAYER_TOKEN_FIELDS.has(str(k)):
			return false
	return true


# --------------------------------------------------------------------- apply --

## Apply a valid event and return its inverse. Applying an invalid event
## does nothing and returns {} (callers should validate() first; the
## message is pushed as an error so tests and hosts see it).
func apply(ev: Dictionary) -> Dictionary:
	var why := validate(ev)
	if why != "":
		push_error("encounter event rejected: " + why)
		return {}
	var t := str(ev.t)
	var inv := {}
	var what := ""
	var scene_id := str(ev.get("scene", ""))
	var doc := encounter.doc
	match t:
		"encounter.set":
			inv = {"t": t, "changes": JsonDoc.merge(doc, ev.changes)}
			what = "encounter"
		"scene.add":
			var arr: Array = doc.scenes
			var idx := int(ev.get("index", arr.size()))
			idx = clampi(idx, 0, arr.size())
			arr.insert(idx, JsonDoc.deep(ev.scene))
			if str(doc.get("active_scene", "")) == "":
				doc.active_scene = str(ev.scene.id)
			inv = {"t": "scene.remove", "id": str(ev.scene.id)}
			what = "scenes"
			scene_id = str(ev.scene.id)
		"scene.remove":
			var idx := encounter.scene_index(str(ev.id))
			var arr: Array = doc.scenes
			var gone: Dictionary = arr[idx]
			arr.remove_at(idx)
			inv = {"t": "scene.add", "scene": JsonDoc.deep(gone), "index": idx}
			if str(doc.get("active_scene", "")) == str(ev.id):
				# Undo restores the active scene through scene.add's redo of
				# active_scene only when it was empty, so carry it explicitly.
				inv = {"t": "scene.add", "scene": JsonDoc.deep(gone), "index": idx, "activate": true}
				doc.active_scene = str(arr[0].id) if not arr.is_empty() else ""
			what = "scenes"
			scene_id = str(ev.id)
		"scene.set":
			inv = {"t": t, "id": str(ev.id), "changes": JsonDoc.merge(encounter.scene(str(ev.id)), ev.changes)}
			what = "scenes"
			scene_id = str(ev.id)
		"scene.activate":
			inv = {"t": t, "id": str(doc.get("active_scene", ""))}
			doc.active_scene = str(ev.id)
			what = "active_scene"
			scene_id = str(ev.id)
		"token.add":
			var arr: Array = encounter.scene(scene_id).tokens
			var idx := clampi(int(ev.get("index", arr.size())), 0, arr.size())
			var tk: Dictionary = JsonDoc.deep(ev.token)
			Encounter.fill_token(tk)
			arr.insert(idx, tk)
			inv = {"t": "token.remove", "scene": scene_id, "id": str(tk.id)}
			what = "tokens"
		"token.remove":
			var sc := encounter.scene(scene_id)
			var idx := Encounter.token_index(sc, str(ev.id))
			var arr: Array = sc.tokens
			var gone: Dictionary = arr[idx]
			arr.remove_at(idx)
			inv = {"t": "token.add", "scene": scene_id, "token": JsonDoc.deep(gone), "index": idx}
			what = "tokens"
		"token.set":
			inv = {"t": t, "scene": scene_id, "id": str(ev.id), "changes": JsonDoc.merge(token(scene_id, str(ev.id)), ev.changes)}
			what = "tokens"
		"element.set":
			var ovs: Dictionary = encounter.scene(scene_id).overrides
			var ref := str(ev.ref)
			if not ovs.has(ref):
				ovs[ref] = {}
			var before := JsonDoc.merge(ovs[ref], ev.changes)
			if (ovs[ref] as Dictionary).is_empty():
				ovs.erase(ref)
			inv = {"t": t, "scene": scene_id, "ref": ref, "changes": before}
			what = "overrides"
		"fog.set":
			var fog: Dictionary = encounter.scene(scene_id).fog
			inv = {"t": t, "scene": scene_id, "enabled": bool(fog.get("enabled", false))}
			fog.enabled = bool(ev.enabled)
			what = "fog"
		"fog.reveal":
			var fog: Dictionary = encounter.scene(scene_id).fog
			var have := explored(scene_id)
			var added := []
			for c in ev.cells:
				var k := str(c)
				if not have.has(k):
					have[k] = true
					fog.explored.append(k)
					added.append(k)
			inv = {"t": "fog.hide", "scene": scene_id, "cells": added}
			what = "fog"
		"fog.hide":
			var fog: Dictionary = encounter.scene(scene_id).fog
			var drop := {}
			for c in ev.cells:
				drop[str(c)] = true
			var kept := []
			var removed := []
			for k in fog.explored:
				if drop.has(str(k)):
					removed.append(str(k))
				else:
					kept.append(k)
			fog.explored = kept
			inv = {"t": "fog.reveal", "scene": scene_id, "cells": removed}
			what = "fog"
		"initiative.set":
			inv = {"t": t, "changes": JsonDoc.merge(doc.initiative, ev.changes)}
			what = "initiative"
		"player.add":
			(doc.players as Array).append(JsonDoc.deep(ev.player))
			inv = {"t": "player.remove", "id": str(ev.player.id)}
			what = "players"
		"player.remove":
			var idx := encounter.player_index(str(ev.id))
			var gone: Dictionary = doc.players[idx]
			(doc.players as Array).remove_at(idx)
			inv = {"t": "player.add", "player": JsonDoc.deep(gone), "index": idx}
			what = "players"
		"player.set":
			inv = {"t": t, "id": str(ev.id), "changes": JsonDoc.merge(encounter.player(str(ev.id)), ev.changes)}
			what = "players"
	if t == "scene.add" and bool(ev.get("activate", false)):
		doc.active_scene = str(ev.scene.id)
	encounter.touch(what, scene_id)
	applied.emit(ev, inv)
	return inv


## Cells in `cells` that the players have not explored yet on this scene:
## what a fog.reveal after a move should carry, so the log stays small.
func unexplored(scene_id: String, cells: Array) -> Array:
	var have := explored(scene_id)
	var out := []
	for c in cells:
		var k: String = c if c is String else HexMap.cell_key(c)
		if not have.has(k) and not out.has(k):
			out.append(k)
	return out
