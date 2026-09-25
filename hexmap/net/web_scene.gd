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
##   {id, name, map, level, active, fog, darkness, overrides, tokens,
##    explored: [cell keys], visible: [polygon], lights: [{pos, color,
##    intensity, bright, dim, polygon}], regions, turns}


## The snapshot of `scene_id` for a viewer: a player (their id), or the GM
## (`gm`), who sees every token and gets the players' sight as a preview.
static func build(state: EncounterState, scene_id: String, player_id: String, gm: bool) -> Dictionary:
	var e := state.encounter
	var sc := e.scene(scene_id)
	if sc.is_empty():
		return {}
	var fog := state.fog_enabled(scene_id)
	var eyes := []
	for tk in state.tokens(scene_id):
		if (gm and tk.get("owner", null) != null) or (not gm and _owns(state, tk, player_id)):
			eyes.append(tk)
	var sight: Dictionary = Vision.of(state, scene_id, eyes) if (fog or gm) else {"polygons": [], "cells": []}
	var tokens := []
	for tk in state.tokens(scene_id):
		if not gm:
			if bool(tk.get("hidden", false)):
				continue
			if fog and not _owns(state, tk, player_id) and not Vision.sees(sight.polygons, Vision.token_pos(tk)):
				continue
		tokens.append(token_out(state, tk, gm))
	var lvl := state.effective_level(scene_id)
	var regions := {}
	for id in sc.get("regions", {}):
		var r: Dictionary = sc.regions[id]
		if gm or str(r.get("audience", "all")) != "gm":
			regions[id] = JsonDoc.deep(r)
	return {"id": str(sc.id), "name": str(sc.get("name", "")), "map": str(sc.get("map", "")), "level": str(sc.get("level", "")),
		"active": e.active_scene_id == scene_id, "fog": fog, "darkness": float(lvl.get("darkness", 0.0)),
		"overrides": JsonDoc.deep(sc.get("overrides", {})), "tokens": tokens,
		"explored": state.explored(scene_id).keys() if fog else [],
		"visible": (sight.polygons as Array).map(func(p: PackedVector2Array) -> Array: return _points(p)),
		"lights": lights(state, scene_id, lvl, tokens), "regions": regions, "turns": JsonDoc.deep(e.turns)}


## A token as a web client draws it; the DM also learns whether it is hidden.
static func token_out(state: EncounterState, tk: Dictionary, gm: bool) -> Dictionary:
	var out := {}
	for k in ["id", "name", "pos", "size", "color", "label", "art", "owner", "actor", "rot", "tags", "elevation"]:
		if tk.has(k) and tk[k] != null:
			out[k] = JsonDoc.deep(tk[k])
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
	for t in tokens:
		var tl: Variant = state.token(scene_id, str(t.get("id", ""))).get("light", null)
		if tl is Dictionary and not (tl as Dictionary).is_empty():
			var l: Dictionary = (tl as Dictionary).duplicate()
			l.pos = t.get("pos", [0, 0])
			all.append(l)
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


static func _points(p: PackedVector2Array) -> Array:
	var out := []
	for v in p:
		out.append([snappedf(v.x, 0.001), snappedf(v.y, 0.001)])
	return out
