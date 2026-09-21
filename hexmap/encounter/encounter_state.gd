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
	"fog.set", "fog.reveal", "fog.hide", "turns.set",
	"player.add", "player.remove", "player.set",
	# version 2: the rules families (docs/encounter-format.md, "Version 2")
	"actor.add", "actor.remove", "actor.set", "actor.overlay.push", "actor.overlay.pop",
	"effect.apply", "effect.set", "effect.remove", "resource.set", "ext.set",
	"log.add", "log.remove",
	"track.add", "track.remove", "track.set", "pending.open", "pending.close", "pending.set", "clock.set"]
const PENDING_KINDS := ["prompts", "rolls"]
## Where an `ext.set` may point.
const EXT_SCOPES := ["encounter", "scene", "token"]
## What a reference to a thing that carries effects or resources looks like.
const REF_KINDS := ["token", "actor", "encounter"]
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
			for k in ["format", "version", "id", "scenes", "active_scene", "turns", "players"]:
				if ev.changes.has(k):
					return "encounter.set cannot change '%s'; use its own events" % k
		"turns.set":
			var e := _need_dict(ev, "changes")
			if e != "":
				return e
			if ev.changes.has("mode") and not Encounter.TURN_MODES.has(str(ev.changes.mode)):
				return "turns.set: mode must be one of %s" % [Encounter.TURN_MODES]
			if ev.changes.has("strategy") and not Encounter.TURN_STRATEGIES.has(str(ev.changes.strategy)):
				return "turns.set: strategy must be one of %s" % [Encounter.TURN_STRATEGIES]
			for k in ["order", "active", "requests", "history"]:
				if ev.changes.has(k) and not (ev.changes[k] is Array):
					return "turns.set: '%s' must be a list" % k
			if ev.changes.has("counters") and not (ev.changes.counters is Dictionary):
				return "turns.set: 'counters' must be an object"
			if ev.changes.has("focus") and not (ev.changes.focus is String):
				return "turns.set: 'focus' must be a ref or \"gm\" or \"\""
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
		"actor.add":
			if not (ev.get("actor") is Dictionary) or str(ev.actor.get("id", "")) == "":
				return "actor.add needs an actor with an id"
			if encounter.actors.has(str(ev.actor.id)):
				return "actor '%s' already exists" % str(ev.actor.id)
		"actor.remove":
			return _need_actor(ev)
		"actor.set":
			var e := _need_actor(ev)
			if e != "":
				return e
			e = _need_dict(ev, "changes")
			if e != "":
				return e
			for k in ev.changes:
				var key := str(k)
				if key == "id" or key == "derived" or key.begins_with("derived/") or key == "overlays" or key.begins_with("overlays/"):
					return "actor.set cannot change '%s'" % key
		"actor.overlay.push":
			var e := _need_actor(ev)
			if e != "":
				return e
			if not (ev.get("overlay") is Dictionary) or str(ev.overlay.get("id", "")) == "":
				return "actor.overlay.push needs an overlay with an id"
			for o in encounter.actor(str(ev.id)).get("overlays", []):
				if str(o.get("id", "")) == str(ev.overlay.id):
					return "overlay '%s' is already on actor '%s'" % [str(ev.overlay.id), str(ev.id)]
		"actor.overlay.pop":
			var e := _need_actor(ev)
			if e != "":
				return e
			if _overlay_index(str(ev.id), str(ev.get("overlay_id", ""))) < 0:
				return "no overlay '%s' on actor '%s'" % [str(ev.get("overlay_id", "")), str(ev.id)]
		"effect.apply":
			if not (ev.get("effect") is Dictionary) or str(ev.effect.get("id", "")) == "":
				return "effect.apply needs an effect with an id"
			if encounter.effects.has(str(ev.effect.id)):
				return "effect '%s' already exists" % str(ev.effect.id)
			var e := _need_ref(str(ev.effect.get("on", "")), "effect.apply: 'on'")
			if e != "":
				return e
			if str(ev.effect.get("key", "")) == "":
				return "effect.apply needs a 'key'"
		"effect.set":
			if not encounter.effects.has(str(ev.get("id", ""))):
				return "no effect '%s'" % str(ev.get("id", ""))
			var e := _need_dict(ev, "changes")
			if e != "":
				return e
			if ev.changes.has("id"):
				return "effect.set cannot change 'id'"
		"effect.remove":
			if not encounter.effects.has(str(ev.get("id", ""))):
				return "no effect '%s'" % str(ev.get("id", ""))
		"resource.set":
			var e := _need_ref(str(ev.get("ref", "")), "resource.set: 'ref'")
			if e != "":
				return e
			if str(ev.get("plugin", "")) == "" or str(ev.get("name", "")) == "":
				return "resource.set needs 'plugin' and 'name'"
			if ev.has("record") and ev.record != null and not (ev.record is Dictionary):
				return "resource.set: 'record' must be an object or null"
		"ext.set":
			var scope := str(ev.get("scope", ""))
			if not EXT_SCOPES.has(scope):
				return "ext.set: scope must be one of %s" % [EXT_SCOPES]
			if str(ev.get("plugin", "")) == "":
				return "ext.set needs 'plugin'"
			var e := _need_dict(ev, "changes")
			if e != "":
				return e
			if scope == "scene":
				return _need_scene(ev, "id")
			if scope == "token":
				var sc := _need_scene(ev, "scene")
				return sc if sc != "" else _need_token(ev)
		"log.add":
			if not (ev.get("entry") is Dictionary) or str(ev.entry.get("id", "")) == "" or str(ev.entry.get("kind", "")) == "":
				return "log.add needs an entry with an id and a kind"
			if _log_index(str(ev.entry.id)) >= 0:
				return "log entry '%s' already exists" % str(ev.entry.id)
		"log.remove":
			if _log_index(str(ev.get("id", ""))) < 0:
				return "no log entry '%s'" % str(ev.get("id", ""))
		"track.add":
			if not (ev.get("track") is Dictionary) or str(ev.track.get("id", "")) == "":
				return "track.add needs a track with an id"
			if encounter.tracks.has(str(ev.track.id)):
				return "track '%s' already exists" % str(ev.track.id)
		"track.remove":
			if not encounter.tracks.has(str(ev.get("id", ""))):
				return "no track '%s'" % str(ev.get("id", ""))
		"track.set":
			if not encounter.tracks.has(str(ev.get("id", ""))):
				return "no track '%s'" % str(ev.get("id", ""))
			var e := _need_dict(ev, "changes")
			if e != "":
				return e
			if ev.changes.has("id"):
				return "track.set cannot change 'id'"
		"pending.open":
			if not PENDING_KINDS.has(str(ev.get("kind", ""))):
				return "pending.open: kind must be one of %s" % [PENDING_KINDS]
			if not (ev.get("record") is Dictionary) or str(ev.record.get("id", "")) == "":
				return "pending.open needs a record with an id"
			if encounter.pending[str(ev.kind)].has(str(ev.record.id)):
				return "pending %s '%s' already exists" % [str(ev.kind), str(ev.record.id)]
		"pending.close":
			if not PENDING_KINDS.has(str(ev.get("kind", ""))) or not encounter.pending[str(ev.kind)].has(str(ev.get("id", ""))):
				return "no pending %s '%s'" % [str(ev.get("kind", "")), str(ev.get("id", ""))]
		"pending.set":
			if not PENDING_KINDS.has(str(ev.get("kind", ""))) or not encounter.pending[str(ev.kind)].has(str(ev.get("id", ""))):
				return "no pending %s '%s'" % [str(ev.get("kind", "")), str(ev.get("id", ""))]
			var e := _need_dict(ev, "changes")
			if e != "":
				return e
			if ev.changes.has("id"):
				return "pending.set cannot change 'id'"
		"clock.set":
			var e := _need_dict(ev, "changes")
			if e != "":
				return e
			for k in ev.changes:
				if not Encounter.DEFAULT_CLOCK.has(str(k)) or not (ev.changes[k] is float or ev.changes[k] is int):
					return "clock.set: '%s' is not a clock field or not a number" % str(k)
	return ""


func _need_actor(ev: Dictionary) -> String:
	return "" if encounter.actors.has(str(ev.get("id", ""))) else "no actor '%s'" % str(ev.get("id", ""))


## A ref is "token:<id>" (in any scene), "actor:<id>" or "encounter".
func _need_ref(ref: String, what: String) -> String:
	if ref == "encounter":
		return ""
	var parts := ref.split(":", true, 1)
	if parts.size() != 2 or not REF_KINDS.has(parts[0]) or parts[1] == "":
		return "%s must be 'token:<id>', 'actor:<id>' or 'encounter'" % what
	if parts[0] == "token" and find_token(parts[1]).is_empty():
		return "%s: no token '%s'" % [what, parts[1]]
	if parts[0] == "actor" and not encounter.actors.has(parts[1]):
		return "%s: no actor '%s'" % [what, parts[1]]
	return ""


## A token by id in whichever scene holds it ({} when none does).
func find_token(id: String) -> Dictionary:
	for sc in encounter.scenes:
		var tk := Encounter.token_in(sc, id)
		if not tk.is_empty():
			return tk
	return {}


## The scene id holding a token, or "".
func scene_of_token(id: String) -> String:
	for sc in encounter.scenes:
		if not Encounter.token_in(sc, id).is_empty():
			return str(sc.id)
	return ""


func _overlay_index(actor_id: String, overlay_id: String) -> int:
	var ovs: Array = encounter.actor(actor_id).get("overlays", [])
	for i in ovs.size():
		if str(ovs[i].get("id", "")) == overlay_id:
			return i
	return -1


func _log_index(id: String) -> int:
	var lg: Array = encounter.log
	for i in lg.size():
		if str(lg[i].get("id", "")) == id:
			return i
	return -1


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
## anything. A player may only move a token, and only one the turn mode
## lets them move now (may_move).
func allowed(ev: Dictionary, player_id: String) -> bool:
	if player_id == "":
		return true
	if str(ev.get("t", "")) != "token.set":
		return false
	var tk := token(str(ev.get("scene", "")), str(ev.get("id", "")))
	if tk.is_empty() or not may_move(tk, player_id):
		return false
	if not (ev.get("changes") is Dictionary):
		return false
	for k in ev.changes:
		if not PLAYER_TOKEN_FIELDS.has(str(k)):
			return false
	return true


## Whether a player may move a token right now, by the turn mode:
## free — any token they can see; dm — one of theirs the DM has enabled;
## ordered — one of theirs whose turn it is.
func may_move(tk: Dictionary, player_id: String) -> bool:
	if player_id == "":
		return true
	if bool(tk.get("hidden", false)):
		return false
	var turns := encounter.turns
	match str(turns.get("mode", "free")):
		"free":
			return true
		"dm":
			return _owns(tk, player_id) and (turns.get("active", []) as Array).has(str(tk.id))
		"ordered":
			return _owns(tk, player_id) and current_turn_token() == str(tk.id)
	return false


static func _owns(tk: Dictionary, player_id: String) -> bool:
	return tk.get("owner", null) != null and str(tk.owner) == player_id


## The token whose turn it is in ordered mode, or "". In the focus shape
## it is the focus holder when that is a token.
func current_turn_token() -> String:
	var turns := encounter.turns
	if str(turns.get("strategy", "ordered")) == "focus":
		var f := str(turns.get("focus", ""))
		if bool(turns.get("running", false)) and f.begins_with("token:") and not find_token(f.substr(6)).is_empty():
			return f.substr(6)
		return ""
	if str(turns.get("mode", "free")) != "ordered" or not bool(turns.get("running", false)):
		return ""
	var order: Array = turns.get("order", [])
	var turn := int(turns.get("turn", 0))
	return str(order[turn]) if turn >= 0 and turn < order.size() else ""


## Tokens the table should mark as "up": the DM's picks in dm mode, the
## current turn in ordered mode, nobody in free mode.
func highlighted_token_ids() -> Array:
	var turns := encounter.turns
	match str(turns.get("mode", "free")):
		"dm":
			return (turns.get("active", []) as Array).duplicate()
		"ordered":
			var cur := current_turn_token()
			return [cur] if cur != "" else []
	return []


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
			# Explored is a set; keep it sorted so the same set is always the
			# same document, whatever order it was revealed or undone in.
			(fog.explored as Array).sort()
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
		"turns.set":
			inv = {"t": t, "changes": JsonDoc.merge_paths(doc.turns, ev.changes)}
			what = "turns"
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
		"actor.add":
			var a: Dictionary = JsonDoc.deep(ev.actor)
			Encounter.fill_actor(a)
			doc.actors[str(a.id)] = a
			inv = {"t": "actor.remove", "id": str(a.id)}
			what = "actors"
		"actor.remove":
			var gone: Dictionary = doc.actors[str(ev.id)]
			doc.actors.erase(str(ev.id))
			inv = {"t": "actor.add", "actor": JsonDoc.deep(gone)}
			what = "actors"
		"actor.set":
			inv = {"t": t, "id": str(ev.id), "changes": JsonDoc.merge_paths(encounter.actor(str(ev.id)), ev.changes)}
			what = "actors"
		"actor.overlay.push":
			var ovs: Array = encounter.actor(str(ev.id)).overlays
			var idx := clampi(int(ev.get("index", ovs.size())), 0, ovs.size())
			ovs.insert(idx, JsonDoc.deep(ev.overlay))
			inv = {"t": "actor.overlay.pop", "id": str(ev.id), "overlay_id": str(ev.overlay.id)}
			what = "actors"
		"actor.overlay.pop":
			var ovs: Array = encounter.actor(str(ev.id)).overlays
			var idx := _overlay_index(str(ev.id), str(ev.overlay_id))
			var gone: Dictionary = ovs[idx]
			ovs.remove_at(idx)
			inv = {"t": "actor.overlay.push", "id": str(ev.id), "overlay": JsonDoc.deep(gone), "index": idx}
			what = "actors"
		"effect.apply":
			var fx: Dictionary = JsonDoc.deep(ev.effect)
			doc.effects[str(fx.id)] = fx
			inv = {"t": "effect.remove", "id": str(fx.id)}
			what = "effects"
		"effect.set":
			inv = {"t": t, "id": str(ev.id), "changes": JsonDoc.merge_paths(encounter.effect(str(ev.id)), ev.changes)}
			what = "effects"
		"effect.remove":
			var gone: Dictionary = doc.effects[str(ev.id)]
			doc.effects.erase(str(ev.id))
			inv = {"t": "effect.apply", "effect": JsonDoc.deep(gone)}
			what = "effects"
		"resource.set":
			var ref := str(ev.ref)
			var plugin := str(ev.plugin)
			var name := str(ev.name)
			var res: Dictionary = doc.resources
			var before: Variant = res.get(ref, {}).get(plugin, {}).get(name)
			var record: Variant = ev.get("record")
			if record == null:
				if res.has(ref) and res[ref].has(plugin):
					res[ref][plugin].erase(name)
					if res[ref][plugin].is_empty():
						res[ref].erase(plugin)
					if res[ref].is_empty():
						res.erase(ref)
			else:
				if not res.has(ref):
					res[ref] = {}
				if not res[ref].has(plugin):
					res[ref][plugin] = {}
				res[ref][plugin][name] = JsonDoc.deep(record)
			inv = {"t": t, "ref": ref, "plugin": plugin, "name": name, "record": JsonDoc.deep(before) if before != null else null}
			what = "resources"
		"ext.set":
			var holder: Dictionary
			match str(ev.scope):
				"encounter": holder = doc.state.ext
				"scene":
					var sc := encounter.scene(str(ev.id))
					if not sc.has("ext"):
						sc.ext = {}
					holder = sc.ext
				"token":
					var tk := token(scene_id, str(ev.id))
					if not tk.has("ext"):
						tk.ext = {}
					holder = tk.ext
			if not holder.has(str(ev.plugin)):
				holder[str(ev.plugin)] = {}
			inv = JsonDoc.deep(ev)
			inv.changes = JsonDoc.merge_paths(holder[str(ev.plugin)], ev.changes)
			if holder[str(ev.plugin)].is_empty():
				holder.erase(str(ev.plugin))
			what = "ext"
		"log.add":
			var entry: Dictionary = JsonDoc.deep(ev.entry)
			var lg: Array = doc.log
			var idx := clampi(int(ev.get("index", lg.size())), 0, lg.size())
			lg.insert(idx, entry)
			inv = {"t": "log.remove", "id": str(entry.id)}
			# A roll entry says where in the dice stream it was drawn: the
			# stream moves past it, and back again when it is removed.
			if entry.kind == "roll" and entry.has("draw"):
				inv.rng_index = int(doc.rng.index)
				doc.rng.index = int(entry.draw.index) + int(entry.draw.count)
			what = "log"
		"log.remove":
			var idx := _log_index(str(ev.id))
			var gone: Dictionary = doc.log[idx]
			(doc.log as Array).remove_at(idx)
			inv = {"t": "log.add", "entry": JsonDoc.deep(gone), "index": idx}
			if ev.has("rng_index"):
				doc.rng.index = int(ev.rng_index)
			what = "log"
		"track.add":
			var tr: Dictionary = JsonDoc.deep(ev.track)
			doc.tracks[str(tr.id)] = tr
			inv = {"t": "track.remove", "id": str(tr.id)}
			what = "tracks"
		"track.remove":
			var gone: Dictionary = doc.tracks[str(ev.id)]
			doc.tracks.erase(str(ev.id))
			inv = {"t": "track.add", "track": JsonDoc.deep(gone)}
			what = "tracks"
		"track.set":
			inv = {"t": t, "id": str(ev.id), "changes": JsonDoc.merge_paths(doc.tracks[str(ev.id)], ev.changes)}
			what = "tracks"
		"pending.open":
			var rec: Dictionary = JsonDoc.deep(ev.record)
			doc.pending[str(ev.kind)][str(rec.id)] = rec
			inv = {"t": "pending.close", "kind": str(ev.kind), "id": str(rec.id)}
			what = "pending"
		"pending.close":
			var gone: Dictionary = doc.pending[str(ev.kind)][str(ev.id)]
			doc.pending[str(ev.kind)].erase(str(ev.id))
			inv = {"t": "pending.open", "kind": str(ev.kind), "record": JsonDoc.deep(gone)}
			what = "pending"
		"pending.set":
			inv = {"t": t, "kind": str(ev.kind), "id": str(ev.id), "changes": JsonDoc.merge_paths(doc.pending[str(ev.kind)][str(ev.id)], ev.changes)}
			what = "pending"
		"clock.set":
			inv = {"t": t, "changes": JsonDoc.merge(doc.clock, ev.changes)}
			what = "clock"
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
