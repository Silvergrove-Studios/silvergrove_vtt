class_name MapCanvas
extends Node2D
## Draws one level of a HexMap. Local units are pixels: canvas position in hex
## units × `ppx`. The same node draws the live editor view (under a Camera2D)
## and off-screen exports (inside a SubViewport), so what you see is what
## prints.
##
## Drawing is split into child layers so lights can blend additively and so
## tools can put an overlay on top without redrawing everything.
##
## With an EncounterState and a scene (set_scene) it draws the scene's
## *effective* level — overrides merged, so an open door is open and a light
## that was put out is dark — plus tokens and fog, from a viewpoint: the GM
## ("") sees everything, a player id sees only what their tokens can.

var map: HexMap
var packs: PackLibrary
var level_index := 0
## Encounter drawing; null for the editor and exports.
var state: EncounterState
var scene_id := ""
## "" = the GM sees everything; a player id sees through their tokens.
var viewpoint := ""
var show_tokens := true
var show_fog := true
## Pixels per hex unit for geometry.
var ppx := 256.0
## Pixels per hex the textures should be rasterised for; the live view sets
## this to ppx × zoom so zooming in stays sharp.
var texture_ppx := 256.0

var show_grid := true
var show_walls := true
var show_lights := true
var show_notes := true
var show_hidden := true      # GM view: hidden props/notes are drawn
var darkness := 0.0          # 0 = daylight preview, 1 = only lights show
var grid_color_override := Color(0, 0, 0, 0)
## Soft shadow around the map in the editor view; transparent = none. The
## export renderer leaves it off.
var shadow_color := Color(0, 0, 0, 0)

var _terrain := DrawLayer.new()
var _props := DrawLayer.new()
var _lights := DrawLayer.new()
var _dark := DrawLayer.new()
var _grid := DrawLayer.new()
var _regions := DrawLayer.new()
var _walls := DrawLayer.new()
var _tokens := DrawLayer.new()
var _notes := DrawLayer.new()
var _fog := DrawLayer.new()
## Tools draw selection boxes and previews here.
var overlay := DrawLayer.new()

var _radial: GradientTexture2D
const FOG_UNSEEN := Color(0.03, 0.03, 0.05, 1.0)

## Per-refresh derived state from the layer tree.
var _order: Dictionary = {}       # ref -> draw index
var _visible: Dictionary = {}     # ref -> effective visibility
var _locked: Dictionary = {}      # ref -> effective lock
var _segments: Array = []         # light-blocking wall segments (hex units)
var _poly_cache: Dictionary = {}  # light key -> PackedVector2Array
var _segments_key := ""
## Encounter-derived state, per refresh.
var _eff_level: Dictionary = {}    # effective level of the scene
var _explored: Dictionary = {}     # cell key -> true
var _seen_cells: Dictionary = {}   # cell key -> true, what the viewpoint sees now
var _seen_polys: Array = []        # vision polygons of the viewpoint's tokens
## Meshes handed to draw_mesh must stay alive until the renderer has consumed
## the draw list that references them. Each layer keeps the meshes from its
## current and previous draw; older ones are released when it draws again.
var _mesh_keep: Dictionary = {}   # layer instance id -> {"cur": [], "prev": []}


class DrawLayer extends Node2D:
	var fn: Callable
	var canvas: MapCanvas
	func _draw() -> void:
		if canvas != null:
			canvas._begin_layer_draw(self)
		if fn.is_valid():
			fn.call(self)


func _init() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_terrain.fn = _draw_terrain
	_props.fn = _draw_props
	_lights.fn = _draw_lights
	_dark.fn = _draw_darkness
	_grid.fn = _draw_grid
	_regions.fn = _draw_regions
	_walls.fn = _draw_walls
	_tokens.fn = _draw_tokens
	_notes.fn = _draw_notes
	_fog.fn = _draw_fog
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = add
	for l in [_terrain, _props, _dark, _lights, _grid, _regions, _walls, _tokens, _notes, _fog, overlay]:
		l.canvas = self
		add_child(l)
	if _radial == null:
		_radial = GradientTexture2D.new()
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
		_radial.width = 256
		_radial.height = 256
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_radial.gradient = g


func refresh() -> void:
	_rebuild_state()
	for c in get_children():
		(c as Node2D).queue_redraw()
	queue_redraw()


## Draw a scene of an encounter: its map, level and overlay, tokens and fog.
func set_scene(p_state: EncounterState, p_scene_id: String) -> void:
	state = p_state
	scene_id = p_scene_id
	_eff_level = {}
	map = state.map_for(scene_id) if state != null else null
	if map != null:
		var want := str(state.encounter.scene(scene_id).get("level", ""))
		level_index = 0
		for i in map.levels.size():
			if str(map.level(i).get("id", "")) == want:
				level_index = i
		ppx = float(map.reference_ppx)
	refresh()


func gm_view() -> bool:
	return viewpoint == ""


## Recompute what the layer tree implies and which walls block light.
func _rebuild_state() -> void:
	_order.clear()
	_visible.clear()
	_locked.clear()
	_segments.clear()
	_eff_level = {}
	_explored.clear()
	_seen_cells.clear()
	_seen_polys.clear()
	if map == null:
		return
	if state != null and scene_id != "":
		_eff_level = state.effective_level(scene_id)
		_explored = state.explored(scene_id)
		var eyes: Array = state.tokens_owned_by(scene_id, viewpoint) if not gm_view() else _player_tokens()
		var v := Vision.of(state, scene_id, eyes)
		_seen_polys = v.polygons
		for c in v.cells:
			_seen_cells[HexMap.cell_key(c)] = true
	var lvl := level()
	if lvl.is_empty():
		return
	LayerTree.ensure(lvl)
	var tree: Array = lvl.tree
	_order = LayerTree.order(tree)
	_visible = LayerTree.effective(tree, "visible")
	_locked = LayerTree.effective(tree, "locked")
	_segments = Lighting.blocking_segments(lvl, _visible)
	var key := str(_segments.hash())
	if key != _segments_key:
		_segments_key = key
		_poly_cache.clear()


## Effective visibility of an element, as the layer tree has it.
func is_layer_visible(collection: String, id: String) -> bool:
	return _visible.get(LayerTree.ref(collection, id), true)


func is_layer_locked(collection: String, id: String) -> bool:
	return _locked.get(LayerTree.ref(collection, id), false)


## Is this element drawn right now (layer visible, and GM-only rules)?
func is_shown(collection: String, o: Dictionary) -> bool:
	if not is_layer_visible(collection, str(o.get("id", ""))):
		return false
	var gm := bool(o.get("gm_only", false)) if collection == "notes" else bool(o.get("hidden", false))
	return (show_hidden and gm_view()) or not gm


## Props in draw order (bottom first), visible ones only.
func props_in_order() -> Array:
	var out: Array = []
	for p in level().get("props", []):
		if is_shown("props", p):
			out.append(p)
	out.sort_custom(func(a, b) -> bool:
		return _order.get(LayerTree.ref("props", str(a.get("id", ""))), 1 << 30) < _order.get(LayerTree.ref("props", str(b.get("id", ""))), 1 << 30))
	return out


func level() -> Dictionary:
	if state != null and scene_id != "":
		if _eff_level.is_empty():
			_eff_level = state.effective_level(scene_id)
		return _eff_level
	return map.level(level_index) if map != null else {}


## Every token a player owns: what the GM's fog preview is computed from.
func _player_tokens() -> Array:
	var out := []
	for t in state.tokens(scene_id):
		if t.get("owner", null) != null:
			out.append(t)
	return out


## Is a canvas point (hex units) seen by the viewpoint right now? The GM
## sees everywhere; with fog off, so does everyone.
func point_seen(p: Vector2) -> bool:
	if gm_view() or state == null or not state.fog_enabled(scene_id):
		return true
	return Vision.sees(_seen_polys, p)


## How fog covers a cell for the viewpoint: 0 clear, 1 explored but not in
## sight now, 2 never seen. The GM only gets 0 or 2 (a preview of what the
## players have not found).
func fog_of(cell: Vector2i) -> int:
	if state == null or not state.fog_enabled(scene_id):
		return 0
	var k := HexMap.cell_key(cell)
	if gm_view():
		return 0 if _explored.has(k) or _seen_cells.has(k) else 2
	if _seen_cells.has(k):
		return 0
	return 1 if _explored.has(k) else 2


func px(p: Vector2) -> Vector2:
	return p * ppx


func from_list(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


# ------------------------------------------------------------------ background --

func _draw() -> void:
	if map == null:
		return
	var size := map.grid.map_size() * ppx
	if state != null and not gm_view() and state.fog_enabled(scene_id):
		# Under fog the gaps between the edge hexes are unseen too.
		draw_rect(Rect2(Vector2.ZERO, size), FOG_UNSEEN)
		return
	if shadow_color.a > 0.0:
		# A few expanding rects fading out read as a soft drop shadow at any zoom.
		var steps := 8
		var spread := ppx * 0.35
		for i in steps:
			var f := float(i) / steps
			var grow := spread * f
			var a := shadow_color.a * (1.0 - f) * (1.0 - f) * 0.35
			draw_rect(Rect2(Vector2(-grow, -grow * 0.6 + spread * 0.25), size + Vector2(grow, grow) * 2.0), Color(shadow_color, a))
	var bg := Color(str(map.style.get("background", "#1c1a17")))
	draw_rect(Rect2(Vector2.ZERO, size), bg)


# --------------------------------------------------------------------- terrain --

func _draw_terrain(c: Node2D) -> void:
	if map == null or packs == null:
		return
	var lvl := level()
	var terrain: Dictionary = lvl.get("terrain", {})
	var grid := map.grid
	var pointy := grid.orientation == HexGrid.Orient.POINTY
	var colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for key in terrain:
		var cell := HexMap.key_cell(key)
		var t: Dictionary = terrain[key]
		var ref := str(t.get("t", ""))
		var def := packs.terrain(ref)
		var center := grid.cell_center(cell)
		var corners := grid.corners_at(center)
		var pts := PackedVector2Array()
		pts.resize(6)
		for i in 6:
			pts[i] = corners[i] * ppx
		if def.is_empty():
			c.draw_colored_polygon(pts, Color.MAGENTA.darkened(0.3))
			continue
		var tex := packs.terrain_texture(ref, int(t.get("v", 0)), texture_ppx)
		var uvs := PackedVector2Array()
		uvs.resize(6)
		var fit := str(def.get("fit", "hex"))
		var rot_sixths := int(t.get("rot", 0))
		if fit == "square":
			# Cut the cell out of a texture that repeats every 2 hexes.
			var ang := rot_sixths * PI / 3.0
			for i in 6:
				var d := (corners[i] - center).rotated(ang)
				uvs[i] = (center + d) * 0.5
		else:
			# Map the hex's bounding box (in pointy-top space) to the image.
			var ang := rot_sixths * PI / 3.0 + (0.0 if pointy else -PI / 6.0)
			for i in 6:
				var d := (corners[i] - center).rotated(ang)
				uvs[i] = Vector2(d.x + 0.5, (d.y + HexGrid.R) / (2.0 * HexGrid.R))
		c.draw_polygon(pts, colors, uvs, tex)


# ----------------------------------------------------------------------- props --

func _draw_props(c: Node2D) -> void:
	if map == null or packs == null:
		return
	if _order.is_empty():
		_rebuild_state()
	for p in props_in_order():
		var def := packs.prop(str(p.get("asset", "")))
		draw_prop(c, p, def, 1.0 if not p.get("hidden", false) else 0.55)


## Also used by tools for ghost previews (alpha < 1).
func draw_prop(c: Node2D, p: Dictionary, def: Dictionary, alpha := 1.0) -> void:
	var ref := str(p.get("asset", ""))
	var pos := from_list(p.get("pos", [0, 0])) * ppx
	var scale := float(p.get("scale", 1.0))
	var size_hex: Array = def.get("size", [1, 1])
	var size := Vector2(float(size_hex[0]), float(size_hex[1])) * ppx * scale
	var anchor_a: Array = def.get("anchor", [0.5, 0.5])
	var anchor := Vector2(float(anchor_a[0]), float(anchor_a[1]))
	var flip := bool(p.get("flip", false))
	var tint := Color(str(p.get("tint", "#ffffff")))
	tint.a *= alpha
	var tex: Texture2D = packs.prop_texture(ref, texture_ppx * scale) if not def.is_empty() else packs.placeholder(Color.MAGENTA)
	c.draw_set_transform(pos, deg_to_rad(float(p.get("rot", 0.0))), Vector2(-1.0 if flip else 1.0, 1.0))
	c.draw_texture_rect(tex, Rect2(-anchor * size, size), false, tint)
	c.draw_set_transform(Vector2.ZERO)


## Axis-aligned bounds of a prop in pixels (before rotation), for picking.
func prop_rect(p: Dictionary, def: Dictionary) -> Rect2:
	var pos := from_list(p.get("pos", [0, 0])) * ppx
	var scale := float(p.get("scale", 1.0))
	var size_hex: Array = def.get("size", [1, 1])
	var size := Vector2(float(size_hex[0]), float(size_hex[1])) * ppx * scale
	var anchor_a: Array = def.get("anchor", [0.5, 0.5])
	var anchor := Vector2(float(anchor_a[0]), float(anchor_a[1]))
	return Rect2(pos - anchor * size, size)


## Is a pixel point inside a (possibly rotated) prop?
func prop_hit(p: Dictionary, def: Dictionary, point: Vector2) -> bool:
	var r := prop_rect(p, def)
	var pos := from_list(p.get("pos", [0, 0])) * ppx
	var local := (point - pos).rotated(-deg_to_rad(float(p.get("rot", 0.0)))) + pos
	if bool(p.get("flip", false)):
		local.x = 2.0 * pos.x - local.x
	return r.has_point(local)


# ---------------------------------------------------------------------- lights --

func _draw_lights(c: Node2D) -> void:
	if map == null or not show_lights:
		return
	if _order.is_empty():
		_rebuild_state()
	for l in level().get("lights", []):
		if not is_shown("lights", l) or not bool(l.get("on", true)):
			continue
		draw_light(c, l, 1.0)
	# Lights tokens carry: a torch moves with its bearer.
	if state != null and show_tokens:
		for t in tokens_in_view():
			var tl = t.get("light", null)
			if tl is Dictionary and not (tl as Dictionary).is_empty():
				var l: Dictionary = (tl as Dictionary).duplicate()
				l["pos"] = t.get("pos", [0, 0])
				if not l.has("shadows"):
					l["shadows"] = true
				draw_light(c, l, 1.0)


## Lights are drawn as the radial gradient mapped onto the polygon the light
## can actually reach, so walls that block light cast shadows in the editor
## the way they will in the VTT. `shadows: false` lights ignore walls.
func draw_light(c: Node2D, l: Dictionary, alpha := 1.0) -> void:
	var origin := from_list(l.get("pos", [0, 0]))
	var color := Color(str(l.get("color", "#ffb060")))
	var intensity := float(l.get("intensity", 1.0))
	var dim := float(l.get("dim", 0.0))
	var bright := float(l.get("bright", 0.0))
	var outer := maxf(dim, bright)
	if outer <= 0.0:
		return
	var angle := float(l.get("angle", 360.0))
	var direction := float(l.get("direction", 0.0))
	var segs := _segments if bool(l.get("shadows", true)) else []
	var key := "%s|%s|%s|%s|%d" % [origin, outer, angle, direction, segs.size()]
	var poly: PackedVector2Array
	if _poly_cache.has(key):
		poly = _poly_cache[key]
	else:
		poly = Lighting.visibility_polygon(origin, outer, segs, 64, angle, direction)
		_poly_cache[key] = poly
	if poly.size() < 3:
		return
	_draw_fan(c, origin, outer, poly, Color(color, 0.30 * intensity * alpha))
	if bright > 0.0 and bright < outer:
		_draw_fan(c, origin, bright, Lighting.clamp_radius(origin, poly, bright), Color(color, 0.45 * intensity * alpha))
	elif bright > 0.0:
		_draw_fan(c, origin, outer, poly, Color(color, 0.45 * intensity * alpha))


func _draw_fan(c: Node2D, origin: Vector2, radius: float, poly: PackedVector2Array, color: Color) -> void:
	var f := Lighting.fan(origin, radius, poly, ppx)
	if (f.vertices as PackedVector2Array).is_empty():
		return
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = f.vertices
	arrays[Mesh.ARRAY_TEX_UV] = f.uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_begin_layer_draw(c, false)
	(_mesh_keep[c.get_instance_id()].cur as Array).append(mesh)
	c.draw_mesh(mesh, _radial, Transform2D.IDENTITY, color)


## Called at the start of every layer draw: the meshes of the draw before
## last are no longer referenced by any draw list and can go.
func _begin_layer_draw(c: Node2D, rotate := true) -> void:
	var id := c.get_instance_id()
	if not _mesh_keep.has(id):
		_mesh_keep[id] = {"cur": [], "prev": []}
		return
	if rotate:
		var k: Dictionary = _mesh_keep[id]
		k.prev = k.cur
		k.cur = []


## Darkness preview: a tinted sheet with lights punched out. Cheap and
## approximate — VTTs do the real thing — but it shows where torches reach.
func _draw_darkness(c: Node2D) -> void:
	if map == null or darkness <= 0.0:
		return
	var size := map.grid.map_size() * ppx
	var pad := 3.0 * ppx   # cover props that overhang the map edge
	c.draw_rect(Rect2(Vector2(-pad, -pad), size + Vector2(pad, pad) * 2.0), Color(0.02, 0.02, 0.06, darkness * 0.85))


# ------------------------------------------------------------------------ grid --

## Regions the encounter put on the scene (zones, tagged cells) and the
## scene's highlight (a template being shown): filled cells with a label.
## Players do not see GM-only regions.
func _draw_regions(c: Node2D) -> void:
	if map == null or state == null or scene_id == "":
		return
	var sc := state.encounter.scene(scene_id)
	var grid := map.grid
	var regions: Dictionary = sc.get("regions", {})
	var ids := regions.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = regions[id]
		if not gm_view() and str(r.get("audience", "all")) == "gm":
			continue
		_draw_cells(c, grid, r.get("cells", []), Color(str(r.get("color", "#ffb060"))), 0.22, str(r.get("label", "")))
	var hl: Variant = sc.get("highlight")
	if hl is Dictionary and hl.get("cells") is Array:
		_draw_cells(c, grid, hl.cells, Color(str(hl.get("color", "#ffffff"))), 0.35, str(hl.get("label", "")))


func _draw_cells(c: Node2D, grid: HexGrid, cells: Array, color: Color, alpha: float, label: String) -> void:
	var first := true
	for key in cells:
		if not (key is String):
			continue
		var cell := HexMap.key_cell(key)
		var corners := grid.cell_corners(cell)
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(corners[i] * ppx)
		c.draw_colored_polygon(pts, Color(color, alpha))
		var outline := pts.duplicate()
		outline.append(pts[0])
		c.draw_polyline(outline, Color(color, alpha * 2.0), maxf(1.0, 0.02 * ppx), true)
		if first and label != "":
			var font := ThemeDB.fallback_font
			var size := maxi(10, int(0.22 * ppx))
			c.draw_string(font, grid.cell_center(cell) * ppx + Vector2(-0.4 * ppx, 0.1 * ppx), label, HORIZONTAL_ALIGNMENT_CENTER, 0.8 * ppx, size, Color(1, 1, 1, 0.9))
			first = false


func _draw_grid(c: Node2D) -> void:
	if map == null or not show_grid:
		return
	var grid := map.grid
	var color := grid_color_override if grid_color_override.a > 0.0 else Color(str(map.style.get("grid_color", "#00000066")))
	var width := float(map.style.get("grid_width", 0.012)) * ppx
	width = maxf(width, 1.0)
	for cell in grid.all_cells():
		var corners := grid.cell_corners(cell)
		var pts := PackedVector2Array()
		pts.resize(7)
		for i in 6:
			pts[i] = corners[i] * ppx
		pts[6] = pts[0]
		c.draw_polyline(pts, color, width, true)


# ----------------------------------------------------------------------- walls --

static func wall_color(w: Dictionary) -> Color:
	var b: Dictionary = w.get("blocks", {})
	var door := str(w.get("door", "none"))
	if door == "secret":
		return Color("#b070e0")
	if door == "door":
		return Color("#e0a040") if str(w.get("state", "closed")) != "open" else Color("#e0d090")
	var move := bool(b.get("move", true))
	var sight := bool(b.get("sight", true))
	var light := bool(b.get("light", true))
	if move and sight and light:
		return Color("#d8d8d8")
	if move and not sight:
		return Color("#60c8e0") if bool(b.get("sound", false)) else Color("#c8a060")   # window / fence
	if not move and sight:
		return Color("#7090ff")   # ethereal
	if str(w.get("sight_mode", "normal")) == "limited":
		return Color("#70c070")
	return Color("#909090")


func _draw_walls(c: Node2D) -> void:
	if map == null or not show_walls:
		return
	if _order.is_empty():
		_rebuild_state()
	for w in level().get("walls", []):
		if not is_shown("walls", w):
			continue
		draw_wall(c, w, 1.0)


func draw_wall(c: Node2D, w: Dictionary, alpha := 1.0, selected := false) -> void:
	var raw: Array = w.get("points", [])
	if raw.size() < 2:
		return
	var pts := PackedVector2Array()
	for p in raw:
		pts.append(from_list(p) * ppx)
	var style := packs.wall_style(str(w.get("style", ""))) if packs != null else {}
	var width := float(style.get("width", 0.06)) * ppx
	var color := wall_color(w)
	var b: Dictionary = w.get("blocks", {})
	var invisible := bool(b.get("move", true)) and not bool(b.get("sight", true)) and not bool(b.get("light", true)) and not bool(b.get("sound", true))
	color.a *= alpha
	if selected:
		c.draw_polyline(pts, Color(1, 1, 0.3, 0.9 * alpha), width + 6.0, true)
	if str(w.get("door", "none")) != "none":
		# Doors: a thick bar with a gap when open.
		var open := str(w.get("state", "closed")) == "open"
		c.draw_polyline(pts, Color(0, 0, 0, 0.6 * alpha), width + 3.0, true)
		if open:
			var a := pts[0]
			var bb := pts[pts.size() - 1]
			c.draw_line(a, a.lerp(bb, 0.3), color, width, true)
			c.draw_line(bb, bb.lerp(a, 0.3), color, width, true)
		else:
			c.draw_polyline(pts, color, width, true)
	elif invisible or str(w.get("sight_mode", "normal")) == "limited":
		_dashed(c, pts, color, maxf(width * 0.8, 2.0))
	else:
		c.draw_polyline(pts, Color(0, 0, 0, 0.5 * alpha), width + 2.0, true)
		c.draw_polyline(pts, color, width, true)
	# One-way arrows
	var one_way = w.get("one_way", null)
	if one_way != null:
		for i in pts.size() - 1:
			var a := pts[i]
			var bb := pts[i + 1]
			var mid := (a + bb) / 2.0
			var d := (bb - a).normalized()
			var n := Vector2(d.y, -d.x)   # right-hand normal
			if str(one_way) == "left":
				n = -n
			c.draw_line(mid, mid + n * width * 3.0, color, maxf(width * 0.5, 2.0), true)
	for p in pts:
		c.draw_circle(p, maxf(width * 0.55, 2.5), Color(0, 0, 0, 0.7 * alpha))
		c.draw_circle(p, maxf(width * 0.35, 1.5), color)


static func _dashed(c: Node2D, pts: PackedVector2Array, color: Color, width: float) -> void:
	for i in pts.size() - 1:
		c.draw_dashed_line(pts[i], pts[i + 1], color, width, width * 3.0, true, true)


# ---------------------------------------------------------------------- tokens --

## Tokens the viewpoint gets to see: the GM all of them, a player the ones
## not hidden and either theirs or in sight.
func tokens_in_view() -> Array:
	var out := []
	if state == null or scene_id == "":
		return out
	for t in state.tokens(scene_id):
		if gm_view():
			out.append(t)
			continue
		if bool(t.get("hidden", false)):
			continue
		var mine := t.get("owner", null) != null and str(t.owner) == viewpoint
		if mine or point_seen(Vision.token_pos(t)):
			out.append(t)
	return out


func _draw_tokens(c: Node2D) -> void:
	if not show_tokens or state == null:
		return
	if _eff_level.is_empty():
		_rebuild_state()
	var up := state.highlighted_token_ids()
	for t in tokens_in_view():
		draw_token(c, t, 0.5 if bool(t.get("hidden", false)) else 1.0, up.has(str(t.get("id", ""))))


func token_radius_px(tk: Dictionary) -> float:
	return 0.5 * float(tk.get("size", 1)) * ppx * 0.92


## A token: a disc in its colour (or its art, clipped round), a ring in its
## owner's colour, its label. Also used by tools for ghosts (alpha < 1).
func draw_token(c: Node2D, tk: Dictionary, alpha := 1.0, active := false, selected := false) -> void:
	var pos := Vision.token_pos(tk) * ppx
	var r := token_radius_px(tk)
	var color := Color(str(tk.get("color", "#c0392b")))
	var ring := Color.WHITE
	if tk.get("owner", null) != null and state != null:
		var p := state.encounter.player(str(tk.owner))
		if not p.is_empty():
			ring = Color(str(p.get("color", "#ffffff")))
	var art := str(tk.get("art", ""))
	var tex: Texture2D = packs.token_texture(art, texture_ppx, float(tk.get("size", 1))) if packs != null and art != "" else null
	var n := 48
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	pts.resize(n)
	uvs.resize(n)
	var rot := deg_to_rad(float(tk.get("rot", 0.0)))
	for i in n:
		var a := TAU * i / n
		pts[i] = pos + Vector2(cos(a), sin(a)) * r
		uvs[i] = Vector2(0.5, 0.5) + Vector2(cos(a - rot), sin(a - rot)) * 0.5
	c.draw_circle(pos + Vector2(r * 0.06, r * 0.08), r, Color(0, 0, 0, 0.35 * alpha))
	if tex != null:
		var white := PackedColorArray()
		white.resize(n)
		white.fill(Color(1, 1, 1, alpha))
		c.draw_polygon(pts, white, uvs, tex)
	else:
		c.draw_colored_polygon(pts, Color(color, alpha))
		var label := str(tk.get("label", ""))
		if label != "":
			var font := ThemeDB.fallback_font
			var fs := int(r * (0.9 if label.length() <= 2 else 0.6))
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			var at := pos + Vector2(-w / 2.0, fs * 0.36)
			c.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(maxf(2.0, fs * 0.12)), Color(0, 0, 0, 0.8 * alpha))
			c.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, alpha))
	var ring_w := maxf(r * 0.09, 1.5)
	c.draw_arc(pos, r - ring_w * 0.5, 0.0, TAU, n, Color(0, 0, 0, 0.6 * alpha), ring_w + 1.5, true)
	c.draw_arc(pos, r - ring_w * 0.5, 0.0, TAU, n, Color(ring, alpha), ring_w, true)
	if bool(tk.get("hidden", false)):
		# Dotted outer ring: the GM's reminder that players cannot see it.
		for i in range(0, n, 4):
			var a := TAU * i / n
			c.draw_arc(pos, r + ring_w * 1.2, a, a + TAU / n * 2.0, 4, Color(1, 1, 1, 0.7), ring_w, true)
	if active:
		c.draw_arc(pos, r + ring_w * 2.2, 0.0, TAU, n, Color("#ffd75a"), ring_w * 1.2, true)
	if selected:
		c.draw_arc(pos, r + ring_w * 3.6, 0.0, TAU, n, Color(1, 1, 0.3, 0.9), ring_w, true)
	# Facing tick when rotated.
	if absf(float(tk.get("rot", 0.0))) > 0.01:
		var d := Vector2(cos(rot - PI / 2.0), sin(rot - PI / 2.0))
		c.draw_line(pos + d * r * 0.75, pos + d * (r + ring_w), Color(1, 1, 1, alpha), ring_w, true)


func token_hit(tk: Dictionary, p: Vector2) -> bool:
	return Vision.token_pos(tk).distance_to(p) * ppx <= token_radius_px(tk)


# ------------------------------------------------------------------------- fog --

## Fog: for players, the unexplored is black and the explored-but-out-of-
## sight is dim; for the GM, a light hatch over what the players have not
## found yet.
func _draw_fog(c: Node2D) -> void:
	if not show_fog or state == null or map == null or not state.fog_enabled(scene_id):
		return
	if _eff_level.is_empty():
		_rebuild_state()
	var grid := map.grid
	var unseen := FOG_UNSEEN if not gm_view() else Color(0.05, 0.05, 0.12, 0.55)
	var dim := Color(0.03, 0.03, 0.05, 0.62)
	var size := grid.map_size() * ppx
	if not gm_view():
		# Off-map surround is never seen either.
		var pad := 3.0 * ppx
		c.draw_rect(Rect2(Vector2(-pad, -pad), Vector2(size.x + pad * 2.0, pad)), unseen)
		c.draw_rect(Rect2(Vector2(-pad, size.y), Vector2(size.x + pad * 2.0, pad)), unseen)
		c.draw_rect(Rect2(Vector2(-pad, 0), Vector2(pad, size.y)), unseen)
		c.draw_rect(Rect2(Vector2(size.x, 0), Vector2(pad, size.y)), unseen)
	for cell in grid.all_cells():
		var f := fog_of(cell)
		if f == 0:
			continue
		var corners := grid.cell_corners(cell)
		var pts := PackedVector2Array()
		pts.resize(6)
		for i in 6:
			pts[i] = corners[i] * ppx
		# Overdraw a hair so neighbouring cells leave no seam.
		var center := grid.cell_center(cell) * ppx
		for i in 6:
			pts[i] = center + (pts[i] - center) * 1.02
		c.draw_colored_polygon(pts, unseen if f == 2 else dim)


# ----------------------------------------------------------------------- notes --

func _draw_notes(c: Node2D) -> void:
	if map == null or not show_notes:
		return
	var font := ThemeDB.fallback_font
	if _order.is_empty():
		_rebuild_state()
	for n in level().get("notes", []):
		if not is_shown("notes", n):
			continue
		var pos := from_list(n.get("pos", [0, 0])) * ppx
		var r := ppx * 0.12
		c.draw_circle(pos, r + 2.0, Color(0, 0, 0, 0.7))
		c.draw_circle(pos, r, Color("#f0d060"))
		var title := str(n.get("title", ""))
		if title != "":
			var fs := int(ppx * 0.14)
			c.draw_string(font, pos + Vector2(r * 1.4, fs * 0.4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
