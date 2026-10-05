class_name Measure
extends RefCounted
## How far, as the map counts it: a ruler's distance and the walk beside it.
##
## In the map's own units (its scale: `grid.distance` of `grid.units` a
## cell, five feet or 1.5 metres), cell to cell on a map that draws its grid
## — hex steps, or on squares the diagonal rule the rules registered
## (MapQuery.measure_rule: every square one, every second diagonal two, or
## as the crow flies) — and point to point on a map drawn without one (a
## painted region). The walk is priced by the way movement goes
## (MapQuery.path: round the walls, doors as they are, a diagonal never
## cutting a wall's corner), and said only where it is longer than the
## ground alone would make it: "30 ft straight, 45 ft to walk round".
##
## A player's walk goes only over the ground their party knows (under fog,
## the cells explored): measuring into the dark says nothing of what is
## there. The web screens count the straight distance themselves the same
## way (web/src/lib/map/measure.ts) while a ruler is dragged.

const RULES := ["5-5-5", "5-10-5", "euclid"]


## The straight distance along `points` (hex units, Vector2), in the map's
## units: each point's cell to the next's on a grid that is drawn, the
## points themselves on one that isn't (`gridless`). Under 5-10-5 every
## second diagonal costs two, counted along the whole ruler.
static func straight(grid: HexGrid, points: Array, diagonals := "5-5-5", gridless := false) -> float:
	var total := 0.0
	var parity := 0
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		if gridless:
			total += a.distance_to(b)
			continue
		var ca := grid.world_to_axial(a)
		var cb := grid.world_to_axial(b)
		if not grid.is_square():
			total += grid.steps(ca, cb)
			continue
		var dx := absi(cb.x - ca.x)
		var dy := absi(cb.y - ca.y)
		var diag := mini(dx, dy)
		var orth := maxi(dx, dy) - diag
		match diagonals:
			"euclid":
				total += sqrt(float(dx * dx + dy * dy))
			"5-10-5":
				var dear := (diag + parity) / 2
				parity = (diag + parity) % 2
				total += orth + diag + dear
			_:
				total += orth + diag
	return total * grid.distance


## What walking from cell to cell along `points` costs with nothing in the
## way (the grid's own count, each leg on its own as MapQuery.path counts
## it), in the map's units: the walk is a detour only when it is more.
static func open_walk(grid: HexGrid, points: Array, diagonals := "5-5-5") -> float:
	var total := 0.0
	for i in range(1, points.size()):
		var ca := grid.world_to_axial(points[i - 1])
		var cb := grid.world_to_axial(points[i])
		if not grid.is_square():
			total += grid.steps(ca, cb)
			continue
		var dx := absi(cb.x - ca.x)
		var dy := absi(cb.y - ca.y)
		var diag := mini(dx, dy)
		var orth := maxi(dx, dy) - diag
		match diagonals:
			"euclid": total += orth + diag * sqrt(2.0)
			"5-10-5": total += orth + diag + diag / 2
			_: total += orth + diag
	return total * grid.distance


## The walk along `points`, leg by leg, by MapQuery.path: {ok, length (map
## units), cells (every cell of the way, in order), why}. `blocked` cells
## are never entered (a player's unknown ground). `legs` keeps each leg
## walked (a ruler dragged asks again and again), for as long as the caller
## knows nothing has changed.
static func walk(mq: MapQuery, scene_id: String, points: Array, diagonals := "5-5-5", blocked: Array = [], legs: Variant = null) -> Dictionary:
	var g := mq.grid(scene_id)
	if g == null:
		return {"ok": false, "why": "no map", "length": 0.0, "cells": []}
	var cells := []
	var length := 0.0
	for i in range(1, points.size()):
		var a := g.world_to_axial(points[i - 1])
		var b := g.world_to_axial(points[i])
		if a == b:
			continue
		var key := "%s|%d,%d|%d,%d|%s|%d" % [scene_id, a.x, a.y, b.x, b.y, diagonals, blocked.size()]
		var p: Dictionary = (legs as Dictionary).get(key, {}) if legs is Dictionary else {}
		if p.is_empty():
			p = mq.path(scene_id, a, b, {"diagonals": diagonals, "blocked": blocked})
			if legs is Dictionary:
				if (legs as Dictionary).size() > 512:
					(legs as Dictionary).clear()
				legs[key] = p
		if not bool(p.get("ok", false)):
			return {"ok": false, "why": str(p.get("why", "walls")), "length": 0.0, "cells": cells}
		length += float(p.get("length", 0.0))
		for k in p.get("cells", []):
			if cells.is_empty() or str(cells[-1]) != str(k):
				cells.append(str(k))
	return {"ok": true, "why": "", "length": length * g.distance, "cells": cells}


## The cells a player's party doesn't know on a scene: under fog, every
## cell on the map not explored (a cell the DM revealed is explored); none
## without fog. A set ({"q,r": true}).
static func unknown_cells(state: EncounterState, scene_id: String) -> Dictionary:
	var out := {}
	if not state.fog_enabled(scene_id):
		return out
	var m := state.map_for(scene_id)
	if m == null:
		return out
	var known := state.explored(scene_id)
	for c in m.grid.all_cells():
		var k := HexMap.cell_key(c)
		if not known.has(k):
			out[k] = true
	return out


## Whether a level has walls that stop movement (a painted region has none:
## its walk is never worth saying).
static func has_walls(state: EncounterState, scene_id: String) -> bool:
	return not Lighting.blocking_segments(state.effective_level(scene_id), {}, "move").is_empty()


## A ruler's measure on its scene: {straight, units, words, walk (when it is
## a detour), no_way (when nothing walks there), cells (the walk's, kept on
## the Table to tell what a player may be told)}. `owner` is "gm" or a
## player's id: a player's walk keeps to the ground their party knows.
## `legs`: Measure.walk's.
static func ruler(mq: MapQuery, state: EncounterState, scene_id: String, points: Array, owner := "gm", legs: Variant = null) -> Dictionary:
	var m := state.map_for(scene_id)
	if m == null or points.size() < 2:
		return {"straight": 0.0, "units": m.grid.units if m != null else "ft", "words": amount(0.0, m.grid.units if m != null else "ft")}
	var g := m.grid
	var rule := str(mq.measure_rule().get("diagonals", "5-5-5"))
	var gridless := not m.shows_grid()
	var out := {"straight": straight(g, points, rule, gridless), "units": g.units}
	if has_walls(state, scene_id):
		var unknown := unknown_cells(state, scene_id) if owner != "gm" else {}
		var reachable := true
		for p in points:
			if unknown.has(HexMap.cell_key(g.world_to_axial(p))):
				reachable = false
		if reachable:
			var w := walk(mq, scene_id, points, rule, unknown.keys(), legs)
			out.cells = w.cells
			if bool(w.ok):
				# (on a map without a grid, the walk is cells' worth: said when it beats the open walk by a cell)
				var open := open_walk(g, points, rule)
				if float(w.length) > open + (g.distance * 0.99 if gridless else 0.01):
					out.walk = float(w.length)
			elif str(w.why) == "walls" and owner == "gm":
				out.no_way = true
	out.words = words(out)
	return out


## A measure in words: "25 ft", "30 ft straight, 45 ft to walk round", "30
## ft straight; no way to walk there".
static func words(measure: Dictionary) -> String:
	var units := str(measure.get("units", "ft"))
	var s := amount(float(measure.get("straight", 0.0)), units)
	if measure.has("walk"):
		return "%s straight, %s to walk round" % [s, amount(float(measure.walk), units)]
	if bool(measure.get("no_way", false)):
		return "%s straight; no way to walk there" % s
	return s


## A distance with its unit: whole numbers plainly ("25 ft"), others to one
## place ("7.5 m").
static func amount(v: float, units: String) -> String:
	var r := snappedf(v, 0.1)
	var n := str(int(roundf(r))) if absf(r - roundf(r)) < 0.05 else ("%.1f" % r)
	return "%s %s" % [n, units if units != "" else "ft"]


## A template mark's shape as MapQuery.template takes it, at its place: a
## circle, a cone or a line (`origin` "edge" from a token's edge), and a
## square as a line as wide as it is long, centred on the place.
static func template_spec(mark: Dictionary) -> Dictionary:
	var sh: Dictionary = mark.get("shape", {}) if mark.get("shape") is Dictionary else {}
	var pts: Array = mark.get("points", [])
	var p: Vector2 = Vector2(float(pts[0][0]), float(pts[0][1])) if not pts.is_empty() else Vector2.ZERO
	var at: Variant = ("token:" + str(mark.token)) if str(mark.get("token", "")) != "" else p
	var dir := float(mark.get("direction", 0.0))
	var size := float(sh.get("size", 1.0))
	match str(sh.get("type", "circle")):
		"cone":
			return {"shape": "cone", "at": at, "direction": dir, "length": size, "angle": float(sh.get("angle", 53.0)), "origin": str(sh.get("origin", "edge"))}
		"line":
			return {"shape": "line", "at": at, "direction": dir, "length": size, "width": float(sh.get("width", 1.0)), "origin": str(sh.get("origin", "edge"))}
		"square":
			if at is String:
				# from a token: its near side at the token's edge
				return {"shape": "line", "at": at, "direction": dir, "length": size, "width": size, "origin": str(sh.get("origin", "edge"))}
			var r := deg_to_rad(dir)
			return {"shape": "line", "at": p - Vector2(cos(r), sin(r)) * size * 0.5, "direction": dir, "length": size, "width": size}
	return {"shape": "circle", "at": at, "radius": size, "include_self": bool(sh.get("include_self", true))}
