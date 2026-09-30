class_name Vision
extends RefCounted
## What tokens can see. Pure functions over an effective level (overrides
## merged: an open door does not block) and tokens, in hex units, so the
## Table, the Player and the tests all compute the same thing. Sight is a
## set of polygons per token (Lighting does the geometry against walls
## that block sight); a cell is seen when its centre is inside one.
##
## How far a token sees is the light's to say, not the token's. In
## daylight or dim light — or with `vision.mode: "dark"` — it sees
## everything in its line of sight, out to the map's far corner, stopped
## only by walls. In the dark it sees what its darkvision reaches, and
## whatever a light lights that it has a line of sight to. (A playtest's
## maps were black beyond six hexes, the sunlit road too: `radius` used to
## be how far a token saw, and the light did nothing.)

const RING_RAYS := 72
## A scene's light (EncounterState.light_level): the scene's own, else its
## map level's, else daylight.
const LIGHT_LEVELS := ["daylight", "dim", "dark"]
## How dark the sheet over a scene is drawn at each light; the DM's is half
## as dark (they must still read the map).
const DARKNESS := {"daylight": 0.0, "dim": 0.4, "dark": 1.0}
## One of each unit in metres, to turn a token's `vision.units` into the
## map's (`grid.distance` of `grid.units` a hex).
const METRES := {"in": 0.0254, "ft": 0.3048, "feet": 0.3048, "foot": 0.3048, "yd": 0.9144, "yard": 0.9144, "yards": 0.9144,
	"m": 1.0, "metre": 1.0, "metres": 1.0, "meter": 1.0, "meters": 1.0, "km": 1000.0, "mi": 1609.344, "mile": 1609.344, "miles": 1609.344}


## Sight-blocking segments of an effective level.
static func segments(level: Dictionary) -> Array:
	return Lighting.blocking_segments(level, {}, "sight")


static func token_pos(tk: Dictionary) -> Vector2:
	var p: Array = tk.get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))


## The darkness sheet for a light level: the players', or the DM's (half).
static func darkness(light: String, gm := false) -> float:
	return float(DARKNESS.get(light, 0.0)) * (0.5 if gm else 1.0)


## A token's eyes in hex units on this grid: {sees, dark, mode}. `sees`: a
## `vision.radius` above 0 (0 is a marker, which sees nothing; how far a
## token sees is no longer the radius's to say). `dark`: how far it sees
## with no light (`vision.dark_radius`, darkvision). `mode: "dark"` sees
## with no light at any distance. The numbers are in `vision.units` when
## it names one — a ruleset writes the sheet's feet, `{dark_radius: 60,
## units: "ft"}` — and the map's scale makes them hexes: twelve of five
## feet, or twelve of 1.5 m. Without units, or with ones that can't be
## turned into the map's, they are hexes.
static func eyes(tk: Dictionary, grid: HexGrid) -> Dictionary:
	var v: Dictionary = tk.get("vision") if tk.get("vision") is Dictionary else {}
	var k := hexes_per(str(v.get("units", "")), grid)
	return {"sees": float(v.get("radius", 0)) > 0.0, "dark": maxf(0.0, float(v.get("dark_radius", 0))) * k, "mode": str(v.get("mode", "normal")), "per": k}


## Hexes in one of `units` on a grid: 1 for none, or for a unit that can't
## be turned into the map's.
static func hexes_per(units: String, grid: HexGrid) -> float:
	var u := units.strip_edges().to_lower()
	if u == "" or grid == null or grid.distance <= 0.0:
		return 1.0
	var g := grid.units.strip_edges().to_lower()
	if u == g:
		return 1.0 / grid.distance
	if METRES.has(u) and METRES.has(g):
		return float(METRES[u]) / (float(METRES[g]) * grid.distance)
	return 1.0


## The lights a scene's sight counts: the map's that are on and not hidden,
## those its tokens carry (Vision.carried_lights) — but not a hidden
## token's (its torch would give away the goblin the DM has not revealed) —
## and those effects put at places on it (Vision.placed_lights). The same
## set the web snapshot draws. [{id, pos, bright, dim, angle, direction,
## shadows}]
static func lights(state: EncounterState, scene_id: String, lvl: Dictionary) -> Array:
	var out := []
	for l in lvl.get("lights", []):
		if bool(l.get("on", true)) and not bool(l.get("hidden", false)):
			out.append(_light("light:" + str(l.get("id", "")), l, l.get("pos", [0, 0])))
	var m := state.map_for(scene_id)
	var index := effect_lights(state)
	for tk in state.tokens(scene_id):
		if bool(tk.get("hidden", false)):
			continue
		for l in carried_lights(state, tk, m.grid if m != null else null, index):
			out.append(_light("token:" + str(tk.get("id", "")), l, tk.get("pos", [0, 0])))
	for l in placed_lights(state, scene_id, m.grid if m != null else null, index):
		out.append(_light("effect:" + str(l.effect), l, l.pos))
	return out


## The lights a token carries, in hex units on this grid: its own `light`,
## and those of the effects on it and on its creature — a ruleset puts a
## light on an effect when the light lasts as long as the effect does (the
## SRD's Sacred Weapon: "The weapon also emits Bright Light in a 20-foot
## radius and Dim Light 20 feet beyond that", for ten minutes). A light's
## `bright` and `dim` (its outer radius) are in its `units` when it names
## them — `{bright: 20, dim: 40, units: "ft"}`, the map's scale making them
## hexes, as `vision.dark_radius` — else in hexes. `index` is
## effect_lights(state), worked out once for many tokens.
## [{bright, dim, color, intensity, angle, direction, shadows}]
static func carried_lights(state: EncounterState, tk: Dictionary, grid: HexGrid, index: Dictionary = {}) -> Array:
	var out := []
	var own: Variant = tk.get("light")
	if own is Dictionary and not (own as Dictionary).is_empty():
		out.append(in_hexes(own, grid))
	if index.is_empty() and not state.encounter.effects.is_empty():
		index = effect_lights(state)
	var refs := ["token:" + str(tk.get("id", ""))]
	if str(tk.get("actor", "")) != "":
		refs.append("actor:" + str(tk.actor))
	for r in refs:
		for l in index.get(r, []):
			out.append(in_hexes(l, grid))
	return out


## The effects that carry a light, by what they are on: {ref: [light]}. A
## light that names a place — `at` (a point, as a token's `pos`) on its
## `scene` — stands there instead, whoever its effect is on, under
## "at:<scene>" (Vision.placed_lights): a light left where it was put, as a
## rod planted in the ground or a spell's sunlight at a point.
static func effect_lights(state: EncounterState) -> Dictionary:
	var out := {}
	for id in state.encounter.effects:
		var fx: Variant = state.encounter.effects[id]
		if fx is Dictionary and fx.get("light") is Dictionary and not (fx.light as Dictionary).is_empty():
			var l: Dictionary = fx.light
			var key := str(fx.get("on", ""))
			var at: Variant = l.get("at")
			if at is Array and (at as Array).size() >= 2 and str(l.get("scene", "")) != "":
				key = "at:" + str(l.scene)
				l = l.duplicate()
				l["effect"] = str(id)
			if not out.has(key):
				out[key] = []
			out[key].append(l)
	return out


## The lights effects have put at places on a scene (effect_lights), in hex
## units on its grid, each with its `pos` (the light's `at`) and whose
## effect it is (`effect`). [{pos, effect, bright, dim, color, …}]
static func placed_lights(state: EncounterState, scene_id: String, grid: HexGrid, index: Dictionary = {}) -> Array:
	if index.is_empty() and not state.encounter.effects.is_empty():
		index = effect_lights(state)
	var out := []
	for l in index.get("at:" + scene_id, []):
		var h := in_hexes(l, grid)
		h["pos"] = [float(l.at[0]), float(l.at[1])]
		h.erase("at")
		h.erase("scene")
		out.append(h)
	return out


## A light's radii in hexes: from its `units` by the map's scale, or as given.
static func in_hexes(l: Dictionary, grid: HexGrid) -> Dictionary:
	var out: Dictionary = l.duplicate()
	var k := hexes_per(str(l.get("units", "")), grid)
	out.bright = float(l.get("bright", 0.0)) * k
	out.dim = float(l.get("dim", 0.0)) * k
	out.erase("units")
	return out


static func _light(id: String, l: Dictionary, pos: Variant) -> Dictionary:
	var p: Array = pos if pos is Array and (pos as Array).size() >= 2 else [0, 0]
	return {"id": id, "pos": Vector2(float(p[0]), float(p[1])), "bright": float(l.get("bright", 0.0)), "dim": float(l.get("dim", 0.0)),
		"angle": float(l.get("angle", 360.0)), "direction": float(l.get("direction", 0.0)), "shadows": bool(l.get("shadows", true))}


## The polygon a light reaches: walls that block light cast its shadows
## (unless it has none).
static func light_polygon(l: Dictionary, light_segs: Array) -> PackedVector2Array:
	var outer := maxf(float(l.bright), float(l.dim))
	if outer <= 0.0:
		return PackedVector2Array()
	return Lighting.visibility_polygon(l.pos, outer, light_segs if bool(l.shadows) else [], 64, float(l.angle), float(l.direction))


## What every token on a scene sees by, worked out once: {grid, segs,
## light, reach (the map's diagonal and a little: nothing on the map is
## further), lit (the lights' polygons, in the dark)}. {} without a map.
static func context(state: EncounterState, scene_id: String) -> Dictionary:
	var lvl := state.effective_level(scene_id)
	var m := state.map_for(scene_id)
	if lvl.is_empty() or m == null:
		return {}
	var light := state.light_level(scene_id)
	var lit := []
	if light == "dark":
		var light_segs := Lighting.blocking_segments(lvl, {}, "light")
		for l in lights(state, scene_id, lvl):
			var poly := light_polygon(l, light_segs)
			if poly.size() >= 3:
				lit.append(poly)
	return {"grid": m.grid, "segs": segments(lvl), "light": light, "reach": m.grid.map_size().length() + 2.0, "lit": lit}


## What one token sees: {los, polygons, dark}. `los` is its line of sight
## (walls alone stop it); `polygons` what it sees now, the same in daylight
## and dim light, and in the dark its darkvision (at least half a hex: a
## token sees its own cell) with every lit place in its line of sight;
## `dark` the darkvision part alone. Empty for a token that sees nothing.
static func token_sight(tk: Dictionary, ctx: Dictionary) -> Dictionary:
	var none := {"los": [], "polygons": [], "dark": []}
	if ctx.is_empty():
		return none
	var e := eyes(tk, ctx.grid)
	if not e.sees:
		return none
	var at := token_pos(tk)
	var los := Lighting.visibility_polygon(at, float(ctx.reach), ctx.segs, RING_RAYS)
	if los.size() < 3:
		return none
	if str(ctx.light) != "dark" or str(e.mode) == "dark":
		return {"los": [los], "polygons": [los], "dark": []}
	var out := []
	var own := Lighting.visibility_polygon(at, maxf(float(e.dark), 0.5), ctx.segs, RING_RAYS)
	if own.size() >= 3:
		out.append(own)
	for lp in ctx.lit:
		# (two star-shaped polygons meet in pieces without holes)
		for piece in Geometry2D.intersect_polygons(los, lp):
			if (piece as PackedVector2Array).size() >= 3:
				out.append(piece)
	return {"los": [los], "polygons": out, "dark": [own] if own.size() >= 3 else []}


## One polygon per region a set of tokens sees (several per token in the
## dark), on a scene's context.
static func polygons(tokens: Array, ctx: Dictionary) -> Array:
	var out := []
	for tk in tokens:
		out.append_array(token_sight(tk, ctx).polygons)
	return out


## Cells whose centre lies inside any of the polygons.
static func cells_in(polys: Array, grid: HexGrid) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if polys.is_empty():
		return out
	var boxes := []
	for poly in polys:
		boxes.append(_box(poly))
	for c in grid.all_cells():
		var p := grid.cell_center(c)
		for i in polys.size():
			# (a box test first: a scene in the dark has many small polygons)
			if (boxes[i] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, polys[i]):
				out.append(c)
				break
	return out


static func _box(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r.grow(1e-4)


## Everything a set of tokens sees on a scene: {"polygons": [...], "cells":
## [Vector2i], "los": [...], "dark": [...], "light"}. Tokens are usually a
## player's own; the Table asks with all of them to preview. `los` is
## their line of sight whatever the light, `dark` what their darkvision
## reaches — so a screen can say that a place in sight is too dark to see.
static func of(state: EncounterState, scene_id: String, tokens: Array) -> Dictionary:
	var ctx := context(state, scene_id)
	if ctx.is_empty():
		return {"polygons": [], "cells": [], "los": [], "dark": [], "light": "daylight"}
	var polys := []
	var los := []
	var dark := []
	for tk in tokens:
		var s := token_sight(tk, ctx)
		polys.append_array(s.polygons)
		los.append_array(s.los)
		dark.append_array(s.dark)
	return {"polygons": polys, "cells": cells_in(polys, ctx.grid), "los": los, "dark": dark, "light": ctx.light}


## Is a point (hex units) seen by any of the polygons?
static func sees(polys: Array, p: Vector2) -> bool:
	for poly in polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false
