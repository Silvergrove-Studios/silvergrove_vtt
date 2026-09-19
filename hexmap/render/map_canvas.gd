class_name MapCanvas
extends Node2D
## Draws one level of a HexMap. Local units are pixels: canvas position in hex
## units × `ppx`. The same node draws the live editor view (under a Camera2D)
## and off-screen exports (inside a SubViewport), so what you see is what
## prints.
##
## Drawing is split into child layers so lights can blend additively and so
## tools can put an overlay on top without redrawing everything.

var map: HexMap
var packs: PackLibrary
var level_index := 0
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

var _terrain := DrawLayer.new()
var _props := DrawLayer.new()
var _lights := DrawLayer.new()
var _dark := DrawLayer.new()
var _grid := DrawLayer.new()
var _walls := DrawLayer.new()
var _notes := DrawLayer.new()
## Tools draw selection boxes and previews here.
var overlay := DrawLayer.new()

var _radial: GradientTexture2D

## Per-refresh derived state from the layer tree.
var _order: Dictionary = {}       # ref -> draw index
var _visible: Dictionary = {}     # ref -> effective visibility
var _locked: Dictionary = {}      # ref -> effective lock
var _segments: Array = []         # light-blocking wall segments (hex units)
var _poly_cache: Dictionary = {}  # light key -> PackedVector2Array
var _segments_key := ""
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
	_walls.fn = _draw_walls
	_notes.fn = _draw_notes
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = add
	for l in [_terrain, _props, _dark, _lights, _grid, _walls, _notes, overlay]:
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


## Recompute what the layer tree implies and which walls block light.
func _rebuild_state() -> void:
	_order.clear()
	_visible.clear()
	_locked.clear()
	_segments.clear()
	if map == null:
		return
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
	return show_hidden or not gm


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
	return map.level(level_index) if map != null else {}


func px(p: Vector2) -> Vector2:
	return p * ppx


func from_list(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


# ------------------------------------------------------------------ background --

func _draw() -> void:
	if map == null:
		return
	var size := map.grid.map_size() * ppx
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
		if not is_shown("lights", l):
			continue
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
