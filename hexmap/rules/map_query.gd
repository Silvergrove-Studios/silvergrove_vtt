class_name MapQuery
extends RefCounted
## What a ruleset may ask the map, and the few things it may put on it —
## queries and placement, never mutation of the map itself. Everything is
## computed over the scene's effective level (doors as they are now) and
## its tokens, in hex units, with the plugin supplying what varies by
## game: a band table, a template's origin rule, what counts as cover.
##
##   distance(a, b)            centre and edge distance (token size), cells, band
##   within(origin, r)         tokens within an edge distance
##   template(spec)            cells and tokens in a circle / cone / line / band
##   line_of_sight(a, b)       clear?, cover none | partial | total, what blocks
##   light_at(p)               bright | dim | dark and the sources
##   can_see(viewer, target)   sight polygon, light and vision mode together
##   regions_at(cell)          tagged regions and zones covering a cell
##   move events               a token and what is attached to it, with the
##                             regions entered and left
##   cells                     neighbours, rings, lines; per-cell plugin state
##
## A ref is "token:<id>", a cell is Vector2i or "q,r", a point is Vector2.

var kernel: RulesKernel
## plugin id -> [{name, max}] in edge-distance hex units, ascending; the
## last band is what lies beyond the previous ones.
var band_tables: Dictionary = {}


func _init(p_kernel: RulesKernel) -> void:
	kernel = p_kernel


func register_bands(plugin: String, bands: Array) -> void:
	var list := []
	for b in bands:
		if b is Dictionary and b.has("name"):
			list.append({"name": str(b.name), "max": float(b.get("max", INF))})
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.max < y.max)
	band_tables[plugin] = list


# ----------------------------------------------------------------- basics --

func scene(scene_id: String) -> Dictionary:
	return kernel.state.encounter.scene(scene_id)


func grid(scene_id: String) -> HexGrid:
	var m := kernel.state.map_for(scene_id)
	return m.grid if m != null else null


func token(scene_id: String, id: String) -> Dictionary:
	return kernel.state.token(scene_id, id)


## A ref, point, cell or token record as a point in hex units.
func point_of(scene_id: String, what: Variant) -> Vector2:
	if what is Vector2:
		return what
	if what is Vector2i:
		var g := grid(scene_id)
		return g.cell_center(what) if g != null else Vector2(what)
	if what is Dictionary:
		if what.has("pos"):
			return Vision.token_pos(what)
		if what.has("x") and what.has("y"):
			return Vector2(float(what.x), float(what.y))
	if what is Array and what.size() == 2:
		return Vector2(float(what[0]), float(what[1]))
	if what is String:
		var s: String = what
		if s.begins_with("token:"):
			var tk := token(scene_id, s.substr(6))
			return Vision.token_pos(tk) if not tk.is_empty() else Vector2.INF
		if EncounterState._is_cell_key(s):
			return point_of(scene_id, HexMap.key_cell(s))
	return Vector2.INF


## A token's size in hexes (1 when the ref is not a token).
func size_of(scene_id: String, what: Variant) -> float:
	if what is String and (what as String).begins_with("token:"):
		return float(token(scene_id, (what as String).substr(6)).get("size", 1))
	if what is Dictionary and what.has("size"):
		return float(what.size)
	return 0.0


func cell_of(scene_id: String, what: Variant) -> Vector2i:
	if what is Vector2i:
		return what
	var g := grid(scene_id)
	var p := point_of(scene_id, what)
	return g.world_to_axial(p) if g != null and p != Vector2.INF else Vector2i(-9999, -9999)


# --------------------------------------------------------------- distance --

## {units, edge, cells, band}: centre-to-centre in hex units, edge-to-edge
## (token sizes taken off), cells (axial steps), and the band from the
## plugin's table when one is given.
func distance(scene_id: String, a: Variant, b: Variant, plugin := "") -> Dictionary:
	var pa := point_of(scene_id, a)
	var pb := point_of(scene_id, b)
	if pa == Vector2.INF or pb == Vector2.INF:
		return {"units": INF, "edge": INF, "cells": -1, "band": "", "error": "unknown place"}
	var units := pa.distance_to(pb)
	var edge := maxf(0.0, units - (size_of(scene_id, a) + size_of(scene_id, b)) * 0.5)
	var g := grid(scene_id)
	var ca := cell_of(scene_id, a)
	var cb := cell_of(scene_id, b)
	var cells := g.steps(ca, cb) if g != null else -1
	return {"units": units, "edge": edge, "cells": cells, "diagonals": g.diagonals(ca, cb) if g != null else 0, "band": band_of(plugin, edge)}


## The band an edge distance falls in, "" without a table.
func band_of(plugin: String, edge: float) -> String:
	var table: Array = band_tables.get(plugin, [])
	for b in table:
		if edge <= float(b.max):
			return str(b.name)
	return str(table[table.size() - 1].name) if not table.is_empty() else ""


## Tokens (other than the origin token) within an edge distance.
func within(scene_id: String, origin: Variant, r: float, include_hidden := true) -> Array:
	var out := []
	var self_id := (origin as String).substr(6) if origin is String and (origin as String).begins_with("token:") else ""
	for tk in kernel.state.tokens(scene_id):
		if str(tk.id) == self_id:
			continue
		if not include_hidden and bool(tk.get("hidden", false)):
			continue
		if distance(scene_id, origin, "token:" + str(tk.id)).edge <= r + 1e-6:
			out.append(str(tk.id))
	return out


# --------------------------------------------------------------- templates --

## Cells and tokens in an area. spec:
##   {shape: "circle", at, radius}                     around a point or token
##   {shape: "cone", at, direction (deg), length, angle (deg, default 60)}
##   {shape: "line", at, direction, length, width (default 1)}
##   {shape: "band", at, band, plugin}                  a band's reach around a token
##   origin: "center" (default) | "edge" — cones and lines start at the
##           token's edge in the given direction
##   blocked_by_walls: true — cells the origin cannot see are left out
## Result: {cells: ["q,r"], tokens: [ids], origin: [x, y]}.
func template(scene_id: String, spec: Dictionary) -> Dictionary:
	var g := grid(scene_id)
	if g == null:
		return {"cells": [], "tokens": [], "error": "no map"}
	var at: Variant = spec.get("at")
	var origin := point_of(scene_id, at)
	if origin == Vector2.INF:
		return {"cells": [], "tokens": [], "error": "unknown place"}
	var shape := str(spec.get("shape", "circle"))
	var dir := deg_to_rad(float(spec.get("direction", 0)))
	var d := Vector2(cos(dir), sin(dir))
	if str(spec.get("origin", "center")) == "edge" and (shape == "cone" or shape == "line"):
		origin += d * size_of(scene_id, at) * 0.5
	var reach := 0.0
	match shape:
		"circle": reach = float(spec.get("radius", 1)) + size_of(scene_id, at) * 0.5
		"band": reach = _band_max(str(spec.get("plugin", "")), str(spec.get("band", ""))) + size_of(scene_id, at) * 0.5
		_: reach = float(spec.get("length", 1))
	var segs: Array = Lighting.blocking_segments(kernel.state.effective_level(scene_id), {}, "sight") if bool(spec.get("blocked_by_walls", false)) else []
	var cells := []
	var center_cell := g.world_to_axial(origin)
	for c in g.spiral(center_cell, int(ceil(reach)) + 1):
		if not g.in_bounds(c):
			continue
		var p := g.cell_center(c)
		var inside := false
		match shape:
			"circle", "band":
				inside = p.distance_to(origin) <= reach + 1e-6
			"cone":
				var v: Vector2 = p - origin
				var half := deg_to_rad(float(spec.get("angle", 60))) * 0.5
				inside = v.length() <= reach + 1e-6 and (v.length() < 1e-6 or absf(angle_difference(v.angle(), dir)) <= half + 1e-6)
			"line":
				var v: Vector2 = p - origin
				var along := v.dot(d)
				var across := absf(v.cross(d))
				inside = along >= -1e-6 and along <= reach + 1e-6 and across <= float(spec.get("width", 1)) * 0.5 + 1e-6
		if inside and not segs.is_empty() and not Lighting.is_lit(origin, reach + 2.0, p, segs):
			inside = false
		if inside:
			cells.append(HexMap.cell_key(c))
	var tokens := []
	var self_id := (at as String).substr(6) if at is String and (at as String).begins_with("token:") else ""
	for tk in kernel.state.tokens(scene_id):
		if str(tk.id) == self_id and not bool(spec.get("include_self", false)):
			continue
		if cells.has(HexMap.cell_key(g.world_to_axial(Vision.token_pos(tk)))):
			tokens.append(str(tk.id))
	return {"cells": cells, "tokens": tokens, "origin": [origin.x, origin.y]}


func _band_max(plugin: String, band: String) -> float:
	for b in band_tables.get(plugin, []):
		if str(b.name) == band:
			return float(b.max) if is_finite(float(b.max)) else 100.0
	return 0.0


# ------------------------------------------------------------------ sight --

## Sight from a to b: rays from a's centre to b's centre and the corners
## of b's cell against walls (doors as they are) and, optionally, other
## tokens' cells. {clear, cover: none | partial | total, blocked_by: [ids]}.
func line_of_sight(scene_id: String, a: Variant, b: Variant, tokens_block := true) -> Dictionary:
	var g := grid(scene_id)
	var pa := point_of(scene_id, a)
	var pb := point_of(scene_id, b)
	if g == null or pa == Vector2.INF or pb == Vector2.INF:
		return {"clear": false, "cover": "total", "blocked_by": [], "error": "unknown place"}
	var segs: Array = Lighting.blocking_segments(kernel.state.effective_level(scene_id), {}, "sight")
	var targets := [pb]
	for c in g.corners_at(pb):
		targets.append(pb.lerp(c, 0.9))
	var blockers := []
	var ida := (a as String).substr(6) if a is String and (a as String).begins_with("token:") else ""
	var idb := (b as String).substr(6) if b is String and (b as String).begins_with("token:") else ""
	if tokens_block:
		for tk in kernel.state.tokens(scene_id):
			if str(tk.id) == ida or str(tk.id) == idb:
				continue
			blockers.append({"id": str(tk.id), "pos": Vision.token_pos(tk), "r": float(tk.get("size", 1)) * 0.45})
	var seen := 0
	var by := {}
	for t in targets:
		var v: Vector2 = t - pa
		var dist: float = v.length()
		if dist < 1e-6:
			seen += 1
			continue
		var hit := Lighting.ray_hit(pa, v / dist, segs, dist)
		if hit < dist:
			continue
		var blocked := false
		for bl in blockers:
			if _segment_hits_circle(pa, t, bl.pos, bl.r):
				by[bl.id] = true
				blocked = true
		if not blocked:
			seen += 1
	var cover := "none" if seen == targets.size() else ("total" if seen == 0 else "partial")
	return {"clear": seen > 0, "cover": cover, "blocked_by": by.keys(), "seen": seen, "of": targets.size()}


static func _segment_hits_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return (a + ab * t).distance_to(c) <= r


## What lights a point: {level: bright | dim | dark, sources: [ids]}.
func light_at(scene_id: String, p: Variant) -> Dictionary:
	var pt := point_of(scene_id, p)
	if pt == Vector2.INF:
		return {"level": "dark", "sources": []}
	var lvl := kernel.state.effective_level(scene_id)
	var segs: Array = Lighting.blocking_segments(lvl, {}, "light")
	var best := "dark"
	var sources := []
	var lights := []
	for l in lvl.get("lights", []):
		if bool(l.get("on", true)) and not bool(l.get("hidden", false)):
			lights.append({"id": "light:" + str(l.get("id", "")), "pos": Vector2(float(l.pos[0]), float(l.pos[1])), "bright": float(l.get("bright", 0)), "dim": float(l.get("dim", 0)), "shadows": bool(l.get("shadows", true))})
	for tk in kernel.state.tokens(scene_id):
		var tl: Variant = tk.get("light")
		if tl is Dictionary and not (tl as Dictionary).is_empty():
			lights.append({"id": "token:" + str(tk.id), "pos": Vision.token_pos(tk), "bright": float(tl.get("bright", 0)), "dim": float(tl.get("dim", 0)), "shadows": bool(tl.get("shadows", true))})
	for l in lights:
		var radius := maxf(float(l.bright), float(l.dim))
		var lit := Lighting.is_lit(l.pos, radius, pt, segs if l.shadows else [])
		if not lit:
			continue
		sources.append(l.id)
		if pt.distance_to(l.pos) <= float(l.bright):
			best = "bright"
		elif best != "bright":
			best = "dim"
	return {"level": best, "sources": sources}


## Whether a token sees another: within its vision, line of sight clear,
## and the target lit unless the viewer's vision mode is "dark".
func can_see(scene_id: String, viewer: String, target: String) -> Dictionary:
	var v := token(scene_id, viewer.trim_prefix("token:"))
	var t := token(scene_id, target.trim_prefix("token:"))
	if v.is_empty() or t.is_empty():
		return {"sees": false, "why": "unknown token"}
	var radius := float(v.get("vision", {}).get("radius", 0))
	var d := distance(scene_id, "token:" + str(v.id), "token:" + str(t.id))
	if d.edge > radius:
		return {"sees": false, "why": "out of range", "distance": d}
	var los := line_of_sight(scene_id, "token:" + str(v.id), "token:" + str(t.id), false)
	if not los.clear:
		return {"sees": false, "why": "no line of sight", "distance": d, "cover": los.cover}
	var mode := str(v.get("vision", {}).get("mode", "normal"))
	var light := light_at(scene_id, "token:" + str(t.id))
	if light.level == "dark" and mode != "dark":
		return {"sees": false, "why": "dark", "distance": d, "light": light}
	return {"sees": true, "distance": d, "cover": los.cover, "light": light}


# --------------------------------------------------------------- regions --

## The "q,r" key of any place.
func key_of(scene_id: String, what: Variant) -> String:
	if what is String and EncounterState._is_cell_key(what):
		return what
	return HexMap.cell_key(cell_of(scene_id, what))


## Regions covering a cell (as records).
func regions_at(scene_id: String, cell: Variant) -> Array:
	var key := key_of(scene_id, cell)
	var out := []
	var regions: Dictionary = scene(scene_id).get("regions", {})
	var ids := regions.keys()
	ids.sort()
	for id in ids:
		if (regions[id].get("cells", []) as Array).has(key):
			out.append(regions[id])
	return out


## Tags of every region at a cell, unique.
func tags_at(scene_id: String, cell: Variant) -> Array:
	var out := []
	for r in regions_at(scene_id, cell):
		for tg in r.get("tags", []):
			if not out.has(str(tg)):
				out.append(str(tg))
	return out


## A region record ready for region.add.
static func region(id: String, cells: Array, tags: Array = [], extra: Dictionary = {}) -> Dictionary:
	var keys := []
	for c in cells:
		keys.append(c if c is String else HexMap.cell_key(c))
	var r := {"id": id, "cells": keys, "tags": tags.duplicate(), "audience": "all", "label": "", "color": "#ffb060"}
	r.merge(extra, true)
	return r


## Regions a trigger ends (same durations as effects: turn_end/of, round,
## scene, rest, time…): region.remove events.
func expire_regions(scene_id: String, trigger: Dictionary) -> Array:
	var out := []
	var regions: Dictionary = scene(scene_id).get("regions", {})
	var ids := regions.keys()
	ids.sort()
	var kind := str(trigger.get("kind", ""))
	for id in ids:
		var d: Dictionary = regions[id].get("duration", {})
		if d.is_empty():
			continue
		var dk := str(d.get("kind", ""))
		var ends := false
		match kind:
			"turn_start", "turn_end":
				if dk == kind and str(d.get("of", "")) == str(trigger.get("of", "")):
					var left := int(d.get("turns", 1)) - 1
					if left <= 0:
						ends = true
					else:
						out.append({"t": "region.set", "scene": scene_id, "id": str(id), "changes": {"duration/turns": left}})
			"round":
				if dk == "rounds":
					var left := int(d.get("rounds", 1)) - 1
					if left <= 0:
						ends = true
					else:
						out.append({"t": "region.set", "scene": scene_id, "id": str(id), "changes": {"duration/rounds": left}})
			"scene", "rest", "session":
				ends = dk == kind
			"long_rest":
				ends = dk == "long_rest" or dk == "rest"
			"time":
				ends = dk == "time" and float(d.get("until", 0)) <= float(trigger.get("now", 0))
		if ends:
			out.append({"t": "region.remove", "scene": scene_id, "id": str(id)})
	return out


## Every scene's regions for a trigger.
func expire_all_regions(trigger: Dictionary) -> Array:
	var out := []
	for sc in kernel.state.encounter.scenes:
		out.append_array(expire_regions(str(sc.id), trigger))
	return out


# ------------------------------------------------------------------ moves --

## Events moving a token (and whatever is attached to it, by the same
## step) and what that means: {events, entered: [region ids], left: [...],
## from, to}. Nothing is applied.
func move(scene_id: String, id: String, to: Vector2) -> Dictionary:
	var tk := token(scene_id, id)
	if tk.is_empty():
		return {"events": [], "error": "no token"}
	var from := Vision.token_pos(tk)
	var delta := to - from
	var events := [{"t": "token.set", "scene": scene_id, "id": id, "changes": {"pos": [to.x, to.y]}}]
	for other in kernel.state.tokens(scene_id):
		if str(other.get("attached_to", "")) == id:
			var p := Vision.token_pos(other) + delta
			events.append({"t": "token.set", "scene": scene_id, "id": str(other.id), "changes": {"pos": [p.x, p.y]}})
	var before := {}
	for r in regions_at(scene_id, from):
		before[str(r.id)] = true
	var after := {}
	for r in regions_at(scene_id, to):
		after[str(r.id)] = true
	var entered := []
	var left := []
	for rid in after:
		if not before.has(rid):
			entered.append(rid)
	for rid in before:
		if not after.has(rid):
			left.append(rid)
	entered.sort()
	left.sort()
	return {"events": events, "entered": entered, "left": left, "from": [from.x, from.y], "to": [to.x, to.y], "cells": grid(scene_id).steps(cell_of(scene_id, from), cell_of(scene_id, to))}


# ------------------------------------------------------------------ cells --

func neighbors(scene_id: String, cell: Variant) -> Array:
	var g := grid(scene_id)
	var out := []
	if g == null:
		return out
	for c in g.neighbors(cell_of(scene_id, cell)):
		if g.in_bounds(c):
			out.append(HexMap.cell_key(c))
	return out


func cells_within(scene_id: String, cell: Variant, r: int) -> Array:
	var g := grid(scene_id)
	var out := []
	if g == null:
		return out
	for c in g.spiral(cell_of(scene_id, cell), r):
		if g.in_bounds(c):
			out.append(HexMap.cell_key(c))
	return out


func cells_between(scene_id: String, a: Variant, b: Variant) -> Array:
	var out := []
	var g := grid(scene_id)
	if g == null:
		return out
	for c in g.line(cell_of(scene_id, a), cell_of(scene_id, b)):
		out.append(HexMap.cell_key(c))
	return out


## A cell's record: {ext, revealed, terrain (from the map)}.
func cell(scene_id: String, key: Variant) -> Dictionary:
	var k := key_of(scene_id, key)
	var rec: Dictionary = JsonDoc.deep(scene(scene_id).get("cells", {}).get(k, {}))
	var lvl := kernel.state.effective_level(scene_id)
	rec.terrain = JsonDoc.deep(lvl.get("terrain", {}).get(k, {}))
	rec.key = k
	return rec
