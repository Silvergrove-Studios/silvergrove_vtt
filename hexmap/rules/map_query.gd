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
##   path(from, to)            the cheapest way there, round the walls, what
##                             its cells cost by their tags (rough ground)
##   cells                     neighbours, rings, lines; per-cell plugin state
##
## A ref is "token:<id>", a cell is Vector2i or "q,r", a point is Vector2.

var kernel: RulesKernel
## plugin id -> [{name, max}] in edge-distance hex units, ascending; the
## last band is what lies beyond the previous ones.
var band_tables: Dictionary = {}
## The art the scene's maps are painted with, for what their terrain is
## tagged (a pack's rubble is "difficult"): the Table's own library. With
## none, a cell's terrain carries no tags.
var art: PackLibrary = null


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


# ------------------------------------------------------------------ picks --

## What a press at `p` picks for `spec` on a scene: the token under it
## (hidden ones only for the GM), the cell under it, or the area spec
## with its origin and direction filled in — for a circle the tapped
## cell, for a cone or line the `from` token pointed at the tap. Null
## when there is nothing to pick.
static func pick_target(st: EncounterState, sid: String, spec: Dictionary, p: Vector2, gm: bool) -> Variant:
	var m := st.map_for(sid)
	if m == null:
		return null
	var cell := m.grid.world_to_axial(p)
	match str(spec.get("kind", "")):
		"token":
			var toks: Array = st.tokens(sid)
			for i in range(toks.size() - 1, -1, -1):
				var tk: Dictionary = toks[i]
				if not gm and bool(tk.get("hidden", false)):
					continue
				if Vision.token_pos(tk).distance_to(p) <= float(tk.get("size", 1)) * 0.5:
					return "token:" + str(tk.id)
			return null
		"cell":
			return HexMap.cell_key(cell) if m.grid.in_bounds(cell) else null
		"area":
			if not m.grid.in_bounds(cell):
				return null
			var area: Dictionary = spec.get("area", {}).duplicate(true) if spec.get("area") is Dictionary else {}
			var shape := str(area.get("shape", "circle"))
			var from := str(spec.get("from", ""))
			var out := area
			out.shape = shape
			if shape == "circle" or from == "" or st.token(sid, from).is_empty():
				out.at = HexMap.cell_key(cell)
				out.direction = 0.0
			else:
				var origin := Vision.token_pos(st.token(sid, from))
				out.at = "token:" + from
				out.direction = rad_to_deg((p - origin).angle())
			out.from = ("token:" + from) if from != "" else ""
			return out
	return null


# ------------------------------------------------------------------ sight --

## Sight from a to b: rays from a's centre to b's centre and the corners
## of b's cell against walls (doors as they are) and, optionally, other
## tokens' cells. {clear, cover: none | partial | total, blocked_by: [ids
## of the tokens in the way], walls: how many of the rays a wall stopped,
## seen, of} — so a ruleset can price cover from walls and from creatures
## differently with one call.
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
	var walls := 0
	for t in targets:
		var v: Vector2 = t - pa
		var dist: float = v.length()
		if dist < 1e-6:
			seen += 1
			continue
		var hit := Lighting.ray_hit(pa, v / dist, segs, dist)
		if hit < dist:
			walls += 1
			continue
		var blocked := false
		for bl in blockers:
			if _segment_hits_circle(pa, t, bl.pos, bl.r):
				by[bl.id] = true
				blocked = true
		if not blocked:
			seen += 1
	var cover := "none" if seen == targets.size() else ("total" if seen == 0 else "partial")
	return {"clear": seen > 0, "cover": cover, "blocked_by": by.keys(), "walls": walls, "seen": seen, "of": targets.size()}


static func _segment_hits_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var ab := b - a
	var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return (a + ab * t).distance_to(c) <= r


## What lights a point: {level: bright | dim | dark, sources: [ids],
## ambient}. It starts from the scene's own light (`ambient`: daylight is
## bright everywhere, dim is dim) and the lights raise it.
func light_at(scene_id: String, p: Variant) -> Dictionary:
	var pt := point_of(scene_id, p)
	var ambient := kernel.state.light_level(scene_id)
	if pt == Vector2.INF:
		return {"level": "dark", "sources": [], "ambient": ambient}
	var lvl := kernel.state.effective_level(scene_id)
	var segs: Array = Lighting.blocking_segments(lvl, {}, "light")
	var best: String = {"daylight": "bright", "dim": "dim"}.get(ambient, "dark")
	var sources := []
	var lights := []
	for l in lvl.get("lights", []):
		if bool(l.get("on", true)) and not bool(l.get("hidden", false)):
			lights.append({"id": "light:" + str(l.get("id", "")), "pos": Vector2(float(l.pos[0]), float(l.pos[1])), "bright": float(l.get("bright", 0)), "dim": float(l.get("dim", 0)), "shadows": bool(l.get("shadows", true))})
	# what tokens carry: their own lights and their effects' (Vision.carried_lights)
	var index := Vision.effect_lights(kernel.state)
	for tk in kernel.state.tokens(scene_id):
		for tl in Vision.carried_lights(kernel.state, tk, grid(scene_id), index):
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
	return {"level": best, "sources": sources, "ambient": ambient}


## Whether a token sees another: it has eyes, the line of sight is clear
## and the target lit — unless the viewer sees in the dark: everywhere
## (`vision.mode = "dark"`) or within its darkvision (`vision.dark_radius`,
## in its `units` on this map), in which case `dark_sight` says so. How far
## is the light's to say, not the token's: in light, a line of sight is
## enough.
func can_see(scene_id: String, viewer: String, target: String) -> Dictionary:
	var v := token(scene_id, viewer.trim_prefix("token:"))
	var t := token(scene_id, target.trim_prefix("token:"))
	if v.is_empty() or t.is_empty():
		return {"sees": false, "why": "unknown token"}
	var eyes := Vision.eyes(v, grid(scene_id))
	var d := distance(scene_id, "token:" + str(v.id), "token:" + str(t.id))
	if not eyes.sees:
		return {"sees": false, "why": "no vision", "distance": d}
	var los := line_of_sight(scene_id, "token:" + str(v.id), "token:" + str(t.id), false)
	if not los.clear:
		return {"sees": false, "why": "no line of sight", "distance": d, "cover": los.cover}
	var light := light_at(scene_id, "token:" + str(t.id))
	if light.level == "dark" and str(eyes.mode) != "dark":
		if d.edge <= float(eyes.dark):
			return {"sees": true, "distance": d, "cover": los.cover, "light": light, "dark_sight": true}
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


## A cell's record: {ext, revealed, terrain (from the map, with its art's
## `tags` when the art is here)}.
func cell(scene_id: String, key: Variant) -> Dictionary:
	var k := key_of(scene_id, key)
	var rec: Dictionary = JsonDoc.deep(scene(scene_id).get("cells", {}).get(k, {}))
	var lvl := kernel.state.effective_level(scene_id)
	rec.terrain = JsonDoc.deep(lvl.get("terrain", {}).get(k, {}))
	if not (rec.terrain as Dictionary).is_empty():
		rec.terrain.tags = _terrain_tags(str(rec.terrain.get("t", "")), {})
	rec.key = k
	# where it is, in hex units (a creature put on a cell the DM picked)
	var m := kernel.state.map_for(scene_id)
	if m != null and HexMap.is_cell_key(k):
		var c := m.grid.cell_center(HexMap.key_cell(k))
		rec.center = [c.x, c.y]
	return rec


# ------------------------------------------------------------------- paths --

## The terrain's tags on a cell, from its art: [] with no art, or no terrain.
func terrain_tags(scene_id: String, cell_ref: Variant) -> Array:
	var t: Variant = kernel.state.effective_level(scene_id).get("terrain", {}).get(key_of(scene_id, cell_ref))
	return _terrain_tags(str(t.get("t", "")) if t is Dictionary else "", {})


## A terrain's tags by its art ref, remembered in `cache` for one search.
func _terrain_tags(ref: String, cache: Dictionary) -> Array:
	if ref == "" or art == null:
		return []
	if not cache.has(ref):
		var tags: Variant = art.terrain(ref).get("tags", [])
		cache[ref] = (tags as Array).map(func(x: Variant) -> String: return str(x)) if tags is Array else []
	return cache[ref]


## The cheapest way from one place to another, cell by cell (a hex's six
## neighbours, a square's eight), round the walls that stop movement (doors
## as they are now; on squares a diagonal never cuts a wall's corner). Each
## cell entered costs 1 — or, the dearest that applies, what a ruleset says
## it costs (so two kinds of rough ground are no worse than one):
##   costs      {tag: n}    by the cell's tags: its regions' and its
##                          terrain's (the art's: rubble is "difficult")
##   cell_costs {"q,r": n}  single cells (another creature's space)
##   blocked    ["q,r"]     cells that can't be entered or passed
##   diagonals  on squares, "5-5-5" (every step 1: the default), "5-10-5"
##              (every second diagonal 2) or "euclid" (a diagonal √2)
##   max        a cost past which it stops looking
## Returns {ok, cells: ["q,r", …] from the start to the end, steps, cost,
## length (the same way with no cell dearer than 1), diagonals, costly: [the
## cells entered for more than 1], why}. Not ok, `why` says: "walls" (no way
## round them), "blocked" (the only ways go through blocked cells: `through`
## lists those on the shortest), "far" (dearer than `max`: `cost` is at least
## that), "off the map", "no map".
func path(scene_id: String, from: Variant, to: Variant, opts: Dictionary = {}) -> Dictionary:
	var g := grid(scene_id)
	if g == null:
		return _no_path("no map")
	var start := cell_of(scene_id, from)
	var goal := cell_of(scene_id, to)
	if not g.in_bounds(goal) or not g.in_bounds(start):
		return _no_path("off the map")
	var blocked := {}
	for k in (opts.get("blocked") as Array if opts.get("blocked") is Array else []):
		blocked[str(k)] = true
	var found := _search(scene_id, g, start, goal, opts, blocked)
	if not bool(found.ok) and str(found.why) == "walls" and not blocked.is_empty():
		# through the cells that are blocked there would be a way: they are in it
		var free := opts.duplicate()
		free.erase("max")
		var through := _search(scene_id, g, start, goal, free, {})
		if bool(through.ok):
			found.why = "blocked"
			found.through = (through.cells as Array).filter(func(k: Variant) -> bool: return blocked.has(str(k)))
	return found


static func _no_path(why: String) -> Dictionary:
	return {"ok": false, "why": why, "cells": [], "steps": 0, "cost": 0.0, "length": 0.0, "diagonals": 0, "costly": []}


## A* over the cells (a state is a cell and, under 5-10-5, whether the next
## diagonal is the dear one). The heuristic is the grid's own step count,
## never more than what is left, so the first time the goal comes off the
## heap its way is the cheapest.
func _search(scene_id: String, g: HexGrid, start: Vector2i, goal: Vector2i, opts: Dictionary, blocked: Dictionary) -> Dictionary:
	var lvl := kernel.state.effective_level(scene_id)
	var walls := _wall_buckets(Lighting.blocking_segments(lvl, {}, "move"))
	var costs: Dictionary = opts.get("costs", {}) if opts.get("costs") is Dictionary else {}
	var cell_costs: Dictionary = opts.get("cell_costs", {}) if opts.get("cell_costs") is Dictionary else {}
	var rule := str(opts.get("diagonals", "5-5-5"))
	var max_cost := float(opts.get("max")) if (opts.get("max") is float or opts.get("max") is int) else INF
	# the tags on each cell: its regions', then its terrain's
	var tags_of := {}
	if not costs.is_empty():
		var regions: Dictionary = scene(scene_id).get("regions", {})
		for rid in regions:
			for k in regions[rid].get("cells", []):
				var list: Array = tags_of.get(str(k), [])
				for tg in regions[rid].get("tags", []):
					list.append(str(tg))
				tags_of[str(k)] = list
	var terrain: Dictionary = lvl.get("terrain", {})
	var tag_cache := {}
	var mults := {}
	var square := g.is_square()
	var s0 := Vector3i(start.x, start.y, 0)
	var best := {s0: 0.0}
	var prev := {}
	var closed := {}
	var heap: Array = []
	var seq := 0
	_heap_push(heap, [float(g.steps(start, goal)), seq, s0])
	var reached: Variant = null
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var st: Vector3i = top[2]
		if closed.has(st):
			continue
		closed[st] = true
		if float(top[0]) > max_cost + 1e-9:
			var far := _no_path("far")
			far.cost = float(top[0])
			return far
		var c := Vector2i(st.x, st.y)
		if c == goal:
			reached = st
			break
		var pc := g.cell_center(c)
		var here: float = best[st]
		for n in g.neighbors(c, square):
			if not g.in_bounds(n):
				continue
			var nk := HexMap.cell_key(n)
			if blocked.has(nk) or _walled(walls, pc, g.cell_center(n)):
				continue
			var base := 1.0
			var parity := st.z
			if square and n.x != c.x and n.y != c.y:
				match rule:
					"euclid":
						base = sqrt(2.0)
					"5-10-5":
						base = 2.0 if parity == 1 else 1.0
						parity = 1 - parity
			if not mults.has(nk):
				mults[nk] = _cell_mult(nk, costs, cell_costs, tags_of, terrain, tag_cache)
			var ns := Vector3i(n.x, n.y, parity)
			var cost := here + base * float(mults[nk])
			if cost < float(best.get(ns, INF)) - 1e-9:
				best[ns] = cost
				prev[ns] = [st, base]
				seq += 1
				_heap_push(heap, [cost + float(g.steps(n, goal)), seq, ns])
	if reached == null:
		return _no_path("walls")
	# back from the goal: the cells, and what each step was
	var cells := []
	var length := 0.0
	var diagonals := 0
	var costly := []
	var at: Vector3i = reached
	while prev.has(at):
		var key := HexMap.cell_key(Vector2i(at.x, at.y))
		cells.push_front(key)
		var step: Array = prev[at]
		var from_st: Vector3i = step[0]
		length += float(step[1])
		if square and from_st.x != at.x and from_st.y != at.y:
			diagonals += 1
		if float(mults.get(key, 1.0)) > 1.0:
			costly.push_front(key)
		at = from_st
	cells.push_front(HexMap.cell_key(start))
	return {"ok": true, "why": "", "cells": cells, "steps": cells.size() - 1, "cost": float(best[reached]), "length": length, "diagonals": diagonals, "costly": costly}


## What entering a cell costs: 1, or the dearest of what its tags and the
## cell itself are said to cost.
func _cell_mult(key: String, costs: Dictionary, cell_costs: Dictionary, tags_of: Dictionary, terrain: Dictionary, cache: Dictionary) -> float:
	var m := 1.0
	if not costs.is_empty():
		var tags: Array = tags_of.get(key, [])
		var t: Variant = terrain.get(key)
		if t is Dictionary:
			tags = tags + _terrain_tags(str(t.get("t", "")), cache)
		for tg in tags:
			if costs.has(tg):
				m = maxf(m, float(costs[tg]))
	if cell_costs.has(key):
		m = maxf(m, float(cell_costs[key]))
	return m


## Wall segments by the unit squares their boxes cover, so a step between
## two cells tests only the few near it.
static func _wall_buckets(segs: Array) -> Dictionary:
	var out := {}
	for s in segs:
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		for x in range(floori(minf(a.x, b.x) - 0.01), floori(maxf(a.x, b.x) + 0.01) + 1):
			for y in range(floori(minf(a.y, b.y) - 0.01), floori(maxf(a.y, b.y) + 0.01) + 1):
				var k := Vector2i(x, y)
				if not out.has(k):
					out[k] = []
				(out[k] as Array).append([a, b])
	return out


## Whether a step from p to q meets a wall: crosses it, or touches it (a
## diagonal through the corner where a wall ends is a corner cut).
static func _walled(buckets: Dictionary, p: Vector2, q: Vector2) -> bool:
	if buckets.is_empty():
		return false
	for x in range(floori(minf(p.x, q.x) - 0.01), floori(maxf(p.x, q.x) + 0.01) + 1):
		for y in range(floori(minf(p.y, q.y) - 0.01), floori(maxf(p.y, q.y) + 0.01) + 1):
			for s in buckets.get(Vector2i(x, y), []):
				if _meets(p, q, s[0], s[1]):
					return true
	return false


static func _meets(p: Vector2, q: Vector2, a: Vector2, b: Vector2) -> bool:
	var r := q - p
	var e := b - a
	var denom := r.cross(e)
	if absf(denom) < 1e-12:
		return false
	var d := a - p
	var t := d.cross(e) / denom
	var u := d.cross(r) / denom
	return t >= -1e-6 and t <= 1.0 + 1e-6 and u >= -1e-6 and u <= 1.0 + 1e-6


## A binary heap of [f, seq, state], the least f (then the first pushed) on top.
static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _heap_less(heap[i], heap[parent]):
			break
		var tmp: Variant = heap[i]
		heap[i] = heap[parent]
		heap[parent] = tmp
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Variant = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var least := i
		if l < n and _heap_less(heap[l], heap[least]):
			least = l
		if r < n and _heap_less(heap[r], heap[least]):
			least = r
		if least == i:
			break
		var tmp: Variant = heap[i]
		heap[i] = heap[least]
		heap[least] = tmp
		i = least
	return top


static func _heap_less(x: Array, y: Array) -> bool:
	return float(x[0]) < float(y[0]) - 1e-9 or (absf(float(x[0]) - float(y[0])) <= 1e-9 and int(x[1]) < int(y[1]))
