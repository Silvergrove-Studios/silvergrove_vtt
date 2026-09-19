class_name Vision
extends RefCounted
## What tokens can see. Pure functions over an effective level (overrides
## merged: an open door does not block) and tokens, in hex units, so the
## Table, the Player and the tests all compute the same thing. Sight is a
## visibility polygon per token (Lighting does the geometry against walls
## that block sight); a cell is seen when its centre is inside one.

const RING_RAYS := 72


## Sight-blocking segments of an effective level.
static func segments(level: Dictionary) -> Array:
	return Lighting.blocking_segments(level, {}, "sight")


static func token_pos(tk: Dictionary) -> Vector2:
	var p: Array = tk.get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))


## The region one token sees, or an empty polygon for a token with no vision.
static func token_polygon(tk: Dictionary, segs: Array) -> PackedVector2Array:
	var radius := float(tk.get("vision", {}).get("radius", 0))
	if radius <= 0.0:
		return PackedVector2Array()
	return Lighting.visibility_polygon(token_pos(tk), radius, segs, RING_RAYS)


## One polygon per token that can see.
static func polygons(tokens: Array, level: Dictionary) -> Array:
	var segs := segments(level)
	var out := []
	for tk in tokens:
		var poly := token_polygon(tk, segs)
		if poly.size() >= 3:
			out.append(poly)
	return out


## Cells whose centre lies inside any of the polygons.
static func cells_in(polys: Array, grid: HexGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if polys.is_empty():
		return out
	# Only cells near a polygon can be inside it.
	for c in grid.all_cells():
		var p := grid.cell_center(c)
		for poly in polys:
			if Geometry2D.is_point_in_polygon(p, poly):
				out.append(c)
				break
	return out


## Everything a set of tokens sees on a scene: {"polygons": [...], "cells":
## [Vector2i]}. Tokens are usually a player's own; the Table asks with all
## of them to preview.
static func of(state: EncounterState, scene_id: String, tokens: Array) -> Dictionary:
	var lvl := state.effective_level(scene_id)
	var m := state.map_for(scene_id)
	if lvl.is_empty() or m == null:
		return {"polygons": [], "cells": []}
	var polys := polygons(tokens, lvl)
	return {"polygons": polys, "cells": cells_in(polys, m.grid)}


## Is a point (hex units) seen by any of the polygons?
static func sees(polys: Array, p: Vector2) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false
