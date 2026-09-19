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
var _ground := DrawLayer.new()
var _objects := DrawLayer.new()
var _overhead := DrawLayer.new()
var _lights := DrawLayer.new()
var _dark := DrawLayer.new()
var _grid := DrawLayer.new()
var _walls := DrawLayer.new()
var _notes := DrawLayer.new()
## Tools draw selection boxes and previews here.
var overlay := DrawLayer.new()

static var _radial: GradientTexture2D


class DrawLayer extends Node2D:
	var fn: Callable
	func _draw() -> void:
		if fn.is_valid():
			fn.call(self)


func _init() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_terrain.fn = _draw_terrain
	_ground.fn = func(c: Node2D) -> void: _draw_props(c, "ground")
	_objects.fn = func(c: Node2D) -> void: _draw_props(c, "objects")
	_overhead.fn = func(c: Node2D) -> void: _draw_props(c, "overhead")
	_lights.fn = _draw_lights
	_dark.fn = _draw_darkness
	_grid.fn = _draw_grid
	_walls.fn = _draw_walls
	_notes.fn = _draw_notes
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = add
	for l in [_terrain, _ground, _objects, _overhead, _dark, _lights, _grid, _walls, _notes, overlay]:
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
	for c in get_children():
		(c as Node2D).queue_redraw()
	queue_redraw()


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

func _draw_props(c: Node2D, layer_name: String) -> void:
	if map == null or packs == null:
		return
	for p in level().get("props", []):
		var def := packs.prop(str(p.get("asset", "")))
		var layer := str(p.get("layer", def.get("layer", "objects")))
		if layer != layer_name:
			continue
		if p.get("hidden", false) and not show_hidden:
			continue
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
	for l in level().get("lights", []):
		if l.get("hidden", false) and not show_hidden:
			continue
		draw_light(c, l, 1.0)


func draw_light(c: Node2D, l: Dictionary, alpha := 1.0) -> void:
	var pos := from_list(l.get("pos", [0, 0])) * ppx
	var color := Color(str(l.get("color", "#ffb060")))
	var intensity := float(l.get("intensity", 1.0))
	var dim := float(l.get("dim", 0.0)) * ppx
	var bright := float(l.get("bright", 0.0)) * ppx
	var angle := float(l.get("angle", 360.0))
	if angle < 359.0:
		# Cones: a wedge of the radial. Approximate with a clipped polygon fan.
		_draw_cone(c, pos, maxf(dim, bright), deg_to_rad(float(l.get("direction", 0.0))), deg_to_rad(angle), Color(color, 0.35 * intensity * alpha))
		return
	if dim > 0.0:
		c.draw_texture_rect(_radial, Rect2(pos - Vector2.ONE * dim, Vector2.ONE * dim * 2.0), false, Color(color, 0.30 * intensity * alpha))
	if bright > 0.0:
		c.draw_texture_rect(_radial, Rect2(pos - Vector2.ONE * bright, Vector2.ONE * bright * 2.0), false, Color(color, 0.45 * intensity * alpha))


func _draw_cone(c: Node2D, pos: Vector2, radius: float, dir: float, angle: float, color: Color) -> void:
	var pts := PackedVector2Array([pos])
	var steps := 24
	for i in steps + 1:
		var a := dir - angle / 2.0 + angle * i / steps
		pts.append(pos + Vector2(cos(a), sin(a)) * radius)
	c.draw_colored_polygon(pts, color)


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
	for w in level().get("walls", []):
		if w.get("hidden", false) and not show_hidden:
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
	for n in level().get("notes", []):
		if n.get("gm_only", true) and not show_hidden:
			continue
		var pos := from_list(n.get("pos", [0, 0])) * ppx
		var r := ppx * 0.12
		c.draw_circle(pos, r + 2.0, Color(0, 0, 0, 0.7))
		c.draw_circle(pos, r, Color("#f0d060"))
		var title := str(n.get("title", ""))
		if title != "":
			var fs := int(ppx * 0.14)
			c.draw_string(font, pos + Vector2(r * 1.4, fs * 0.4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
