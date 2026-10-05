class_name WebScene
extends RefCounted
## What a web client is sent of a scene: a snapshot, built for one viewer,
## instead of the stream of scene events the Godot clients apply to a
## document of their own. The host filters it — a player never receives a
## hidden token, nor (under fog) one their characters cannot see — and does
## the geometry: what the viewer's tokens see (polygons, in hex units),
## what has been explored, and the shape of each light. The web client only
## draws.
##
##   {id, name, map, level, active, fog, light, darkness, overrides, tokens,
##    explored: [cell keys], visible: [polygon], los: [polygon],
##    dark_sight: [polygon], lights: [{pos, color, intensity, bright, dim,
##    polygon}], regions, turns}
##
## `light` is the scene's (daylight, dim or dark) and `darkness` the sheet
## drawn for it. In the dark, `los` is the viewer's line of sight — there
## only the dark hides things, not walls — and `dark_sight` what their
## darkvision reaches (seen, not lit). The DM's also carries the scene's
## own setting (`light_set`, "" for the map's) and the map's (`map_light`).


## The snapshot of `scene_id` for a viewer: a player (their id), or the GM
## (`gm`), who sees every token and gets the players' sight as a preview.
## A player sees the rest of the party wherever they are (a playtest's
## player saw a friend's token vanish through a doorway, and took it for a
## dropped connection); everything else only in their characters' sight.
## `known`: what the rulesets say the players know of a creature no player
## owns (Knowledge): its health — its marks left out for a player where they
## see nothing of it, its hit points (`hp`: [current, max]) on its token for
## everyone where they see them exactly; its name — "a creature" to a player
## until the DM reveals it, labelled "?" (or a number, of several), the DM's
## told the label the players see it by (`player_label`) and whether they
## know its name (`name_known`); its conditions.
static func build(state: EncounterState, scene_id: String, player_id: String, gm: bool, known: Array = []) -> Dictionary:
	var e := state.encounter
	var sc := e.scene(scene_id)
	if sc.is_empty():
		return {}
	var fog := state.fog_enabled(scene_id)
	var eyes := _eyes(state, scene_id, player_id, gm)
	var sight: Dictionary = Vision.of(state, scene_id, eyes) if (fog or gm) else {"polygons": [], "cells": [], "los": [], "dark": []}
	# labels worked out over every token, the hidden ones too: a player sees
	# the GW2 the DM calls out, whatever else they can't see — but a creature
	# whose name the players don't know, "?" or a number of the ones they see
	var labels := TokenLabels.of_scene(state.tokens(scene_id), state)
	var unnamed := Knowledge.player_labels(state.tokens(scene_id), e.actors, known)
	var tokens := []
	for tk in state.tokens(scene_id):
		if not gm and not shows(state, tk, player_id, fog, sight.polygons):
			continue
		var out := token_out(state, tk, gm, known)
		out.label = str(labels.get(str(tk.id), out.get("label", "")))
		if unnamed.has(str(tk.id)):
			if gm:
				out.player_label = str(unnamed[str(tk.id)])
				out.name_known = false
			else:
				Knowledge.unname(out, str(unnamed[str(tk.id)]))
		elif gm and Knowledge.names_hidden(known) and Knowledge.unowned(tk, e.actors) and not Encounter.is_object(tk):
			# its name revealed to the players: the DM may keep it again
			out.name_known = true
		tokens.append(out)
	var lvl := state.effective_level(scene_id)
	var regions := {}
	for id in sc.get("regions", {}):
		var r: Dictionary = sc.regions[id]
		if gm or str(r.get("audience", "all")) != "gm":
			regions[id] = JsonDoc.deep(r)
	var light := state.light_level(scene_id)
	var out := {"id": str(sc.id), "name": str(sc.get("name", "")), "map": str(sc.get("map", "")), "level": str(sc.get("level", "")),
		"active": e.active_scene_id == scene_id, "fog": fog, "light": light, "darkness": Vision.darkness(light, gm),
		"overrides": JsonDoc.deep(sc.get("overrides", {})), "tokens": tokens,
		"explored": state.explored(scene_id).keys() if fog else [],
		"visible": (sight.polygons as Array).map(func(p: PackedVector2Array) -> Array: return _points(p)),
		"los": (sight.los as Array).map(func(p: PackedVector2Array) -> Array: return _points(p)) if light == "dark" else [],
		"dark_sight": (sight.dark as Array).map(func(p: PackedVector2Array) -> Array: return _points(p)),
		"lights": lights(state, scene_id, lvl, tokens), "regions": regions,
		"turns": JsonDoc.deep(e.turns) if gm else Knowledge.player_turns(e.turns, e.doc, known)}
	if gm:
		out.light_set = str(sc.get("light", "")) if Vision.LIGHT_LEVELS.has(str(sc.get("light", ""))) else ""
		out.map_light = str(state.level_for(scene_id).get("light", ""))
	# a fight in the theatre of the mind: no map to draw; the screens list who's in it
	if Encounter.is_mind(sc):
		out.space = Encounter.SPACE_MIND
	return out


## Whether a player's screen shows a token (`polys`: what their characters
## see, under `fog`): not one the DM hides, nor one only its owner sees; under
## fog their own, the party's, and what their characters see.
static func shows(state: EncounterState, tk: Dictionary, player_id: String, fog: bool, polys: Array) -> bool:
	if bool(tk.get("hidden", false)) or _owners_only(state, tk, player_id):
		return false
	return not fog or _owns(state, tk, player_id) or _party(state, tk) or Vision.sees(polys, Vision.token_pos(tk))


## Why a player's screen leaves out the creatures it does, for the DM's
## See as: {token id: "hidden" | "dark" | "walls" | "none"} — the DM hasn't
## revealed it; it is in their line of sight but too dark to see; walls
## (or where their sight ends) are in the way; nothing of theirs on the
## scene sees at all. Their own tokens and the party are always there. (A
## playtest's DM saw a player's screen black and couldn't tell why.)
static func unseen(state: EncounterState, scene_id: String, player_id: String) -> Dictionary:
	var out := {}
	if state.encounter.scene(scene_id).is_empty():
		return out
	var fog := state.fog_enabled(scene_id)
	var eyes := _eyes(state, scene_id, player_id, false)
	var sight: Dictionary = Vision.of(state, scene_id, eyes) if fog else {}
	var m := state.map_for(scene_id)
	var sees := eyes.any(func(tk: Dictionary) -> bool: return bool(Vision.eyes(tk, m.grid if m != null else null).sees))
	for tk in state.tokens(scene_id):
		if _owns(state, tk, player_id) or _party(state, tk):
			continue
		var id := str(tk.get("id", ""))
		var at := Vision.token_pos(tk)
		if bool(tk.get("hidden", false)) or _owners_only(state, tk, player_id):
			out[id] = "hidden"
		elif not fog or Vision.sees(sight.polygons, at):
			continue
		elif not sees:
			out[id] = "none"
		elif Vision.sees(sight.los, at):
			out[id] = "dark"
		else:
			out[id] = "walls"
	return out


## The tokens a viewer sees through: a player's own (and their
## characters'), or for the DM every player's, as a preview. Not one whose
## sight isn't shared (Vision.shares: a familiar's, until its caster looks
## through its eyes).
static func _eyes(state: EncounterState, scene_id: String, player_id: String, gm: bool) -> Array:
	var out := []
	for tk in state.tokens(scene_id):
		if not Vision.shares(tk):
			continue
		if (gm and tk.get("owner", null) != null) or (not gm and _owns(state, tk, player_id)):
			out.append(tk)
	return out


## A token as a web client draws it; the DM also learns whether it is
## hidden. An object also brings its own light, which it is drawn glowing in.
## A creature no player owns shows what `known` says the players know of it
## (Knowledge): its health's marks and its conditions' tags left out of a
## player's, its hit points on everyone's where they're shown exactly. (Its
## name is the scene's to say: build.)
static func token_out(state: EncounterState, tk: Dictionary, gm: bool, known: Array = []) -> Dictionary:
	var out := {}
	for k in ["id", "name", "pos", "size", "color", "label", "art", "owner", "actor", "rot", "tags", "elevation"]:
		if tk.has(k) and tk[k] != null:
			out[k] = JsonDoc.deep(tk[k])
	if not known.is_empty() and Knowledge.unowned(tk, state.encounter.actors):
		if not gm and out.get("tags") is Array:
			var a: Dictionary = state.encounter.actors.get(str(tk.actor), {})
			var fx := Knowledge.condition_keys(state.encounter.effects, tk, known) if not Knowledge.conditions_known(a, known) else {}
			out.tags = Knowledge.player_tags(out.tags, known, fx)
		var hp := Knowledge.shown_hp(state.encounter.resources, str(tk.get("actor", "")), known)
		if not hp.is_empty():
			out.hp = hp
	if Encounter.is_object(tk) and tk.get("light") is Dictionary and not (tk.light as Dictionary).is_empty():
		out.light = JsonDoc.deep(tk.light)
	if gm:
		out.hidden = bool(tk.get("hidden", false))
	# a token of a player's character belongs to that player too
	if not out.has("owner") and str(tk.get("actor", "")) != "":
		var owner := str(state.encounter.actor(str(tk.actor)).get("owner", ""))
		if owner != "":
			out.owner = owner
	return out


## Every light that is on — the map's and the ones tokens carry — with the
## polygon it reaches (walls cast shadows), in hex units.
static func lights(state: EncounterState, scene_id: String, lvl: Dictionary, tokens: Array) -> Array:
	var out := []
	var segs := Lighting.blocking_segments(lvl, {})
	var all := []
	for l in lvl.get("lights", []):
		if bool(l.get("on", true)) and not bool(l.get("hidden", false)):
			all.append(l)
	# what the tokens carry: their own lights and their effects' (Vision.carried_lights)
	var m := state.map_for(scene_id)
	var index := Vision.effect_lights(state)
	for t in tokens:
		var tk := state.token(scene_id, str(t.get("id", "")))
		if tk.is_empty():
			continue
		for tl in Vision.carried_lights(state, tk, m.grid if m != null else null, index):
			var l: Dictionary = (tl as Dictionary).duplicate()
			l.pos = t.get("pos", [0, 0])
			all.append(l)
	# and what effects have put at places on it (Vision.placed_lights)
	all.append_array(Vision.placed_lights(state, scene_id, m.grid if m != null else null, index))
	for l in all:
		var bright := float(l.get("bright", 0.0))
		var dim := float(l.get("dim", 0.0))
		var outer := maxf(bright, dim)
		if outer <= 0.0:
			continue
		var p: Array = l.get("pos", [0, 0])
		var origin := Vector2(float(p[0]), float(p[1]))
		var poly := Lighting.visibility_polygon(origin, outer, segs if bool(l.get("shadows", true)) else [], 64, float(l.get("angle", 360.0)), float(l.get("direction", 0.0)))
		if poly.size() < 3:
			continue
		out.append({"pos": [origin.x, origin.y], "color": str(l.get("color", "#ffb060")), "intensity": float(l.get("intensity", 1.0)),
			"bright": bright, "dim": dim, "polygon": _points(poly)})
	return out


static func _owns(state: EncounterState, tk: Dictionary, player_id: String) -> bool:
	if player_id == "":
		return false
	if tk.get("owner", null) != null and str(tk.owner) == player_id:
		return true
	return str(tk.get("actor", "")) != "" and str(state.encounter.actor(str(tk.actor)).get("owner", "")) == player_id


## A token only its owner (and the DM) may see — `audience: "owner"`: a
## thing invisible to all but its caster (an unseen servant, a phantom
## hound) — that this player doesn't own.
static func _owners_only(state: EncounterState, tk: Dictionary, player_id: String) -> bool:
	return str(tk.get("audience", "all")) == "owner" and not _owns(state, tk, player_id)


## A token of the party: a player's, or a player's character's. Not a
## thing a player put on the map (a spell's light): the other players see
## that only in their sight.
static func _party(state: EncounterState, tk: Dictionary) -> bool:
	if Encounter.is_object(tk):
		return false
	if str(tk.get("owner", "") if tk.get("owner", null) != null else "") != "":
		return true
	return str(tk.get("actor", "")) != "" and str(state.encounter.actor(str(tk.actor)).get("owner", "")) != ""


static func _points(p: PackedVector2Array) -> Array:
	var out := []
	for v in p:
		out.append([snappedf(v.x, 0.001), snappedf(v.y, 0.001)])
	return out
