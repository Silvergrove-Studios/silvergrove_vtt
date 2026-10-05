class_name MarkDraw
extends RefCounted
## The table's shared marks drawn on a MapCanvas (in its pixels): a ruler's
## line through its points with its measure at the end, a template's cells
## filled in its owner's colour with its outline and the creatures it would
## catch ringed, a ping's rings fading as it goes — each with its owner's
## name ("Wren: 25 ft"). The web screens draw them the same way
## (web/src/lib/map/marks.ts).

## How long a ping's rings take to fade (ms): the Table's Marks keep one 4 s.
const PING_MS := 4000.0


## Draw `list` (Marks records) on `c`. `zoom` keeps lines and words a
## steady size on screen; `cells_of(mark) -> {cells, tokens}` is the
## template's (MapQuery.template); `now_ms` and `born(id) -> ms` age a ping.
static func draw(c: Node2D, canvas: MapCanvas, list: Array, zoom: float, cells_of: Callable, now_ms := 0, born := Callable()) -> void:
	if canvas.map == null:
		return
	var ppx := canvas.ppx
	var px := 1.0 / maxf(zoom, 1e-4)
	for m in list:
		var color := Color(str(m.get("color", "#ffffff")))
		var name := str(m.get("name", ""))
		match str(m.get("kind", "")):
			"ruler":
				_ruler(c, m, color, name, ppx, px)
			"template", "preview":
				_template(c, canvas, m, color, name, ppx, px, cells_of)
			"ping":
				var age := float(now_ms - int(born.call(str(m.id)))) if born.is_valid() else 0.0
				_ping(c, m, color, name, ppx, px, clampf(age / PING_MS, 0.0, 1.0))


static func _ruler(c: Node2D, m: Dictionary, color: Color, name: String, ppx: float, px: float) -> void:
	var pts := PackedVector2Array()
	for i in (m.get("points", []) as Array).size():
		pts.append(Marks.point(m, i) * ppx)
	if pts.size() >= 2:
		c.draw_polyline(pts, Color(0, 0, 0, 0.6), 6.0 * px, true)
		c.draw_polyline(pts, color, 3.0 * px, true)
	for i in pts.size():
		c.draw_circle(pts[i], (5.0 if i == 0 or i == pts.size() - 1 else 3.5) * px, color)
	var me: Dictionary = m.get("measure", {}) if m.get("measure") is Dictionary else {}
	var words := str(me.get("words", ""))
	if pts.size() >= 1:
		label(c, pts[pts.size() - 1] + Vector2(10, -10) * px, "%s: %s" % [name, words] if words != "" else name, color, px)


static func _template(c: Node2D, canvas: MapCanvas, m: Dictionary, color: Color, name: String, ppx: float, px: float, cells_of: Callable) -> void:
	var grid := canvas.map.grid
	var area: Dictionary = cells_of.call(m) if cells_of.is_valid() else {}
	for key in area.get("cells", []):
		var pts := PackedVector2Array()
		for k in grid.cell_corners(HexMap.key_cell(str(key))):
			pts.append(k * ppx)
		c.draw_colored_polygon(pts, Color(color, 0.22))
		pts.append(pts[0])
		c.draw_polyline(pts, Color(color, 0.55), 1.0 * px, true)
	# the creatures it would catch, ringed
	if canvas.state != null:
		for id in area.get("tokens", []):
			var tk := canvas.state.token(str(m.scene), str(id))
			if not tk.is_empty():
				c.draw_arc(Vision.token_pos(tk) * ppx, canvas.token_radius_px(tk) + 5.0 * px, 0.0, TAU, 40, color, 2.5 * px, true)
	var at := Marks.point(m) * ppx
	c.draw_circle(at, 4.0 * px, color)
	var words := str(m.get("label", ""))
	var caught := (area.get("tokens", []) as Array).size()
	if caught > 0:
		words += " · catches %d" % caught
	label(c, at + Vector2(10, -10) * px, "%s: %s" % [name, words] if words != "" else name, color, px)


static func _ping(c: Node2D, m: Dictionary, color: Color, name: String, ppx: float, px: float, t: float) -> void:
	var at := Marks.point(m) * ppx
	var fade := 1.0 - t
	for k in 3:
		var r := (8.0 + 30.0 * fmod(t * 2.0 + k / 3.0, 1.0)) * px
		c.draw_arc(at, r, 0.0, TAU, 36, Color(color, fade * 0.9), 3.0 * px, true)
	c.draw_circle(at, 5.0 * px, Color(color, fade))
	label(c, at + Vector2(12, -12) * px, name, Color(color, fade), px)


## Words on the map at a steady size, on a dark ground.
static func label(c: Node2D, at: Vector2, text: String, color: Color, px: float) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var size := maxi(1, int(round(13.0 * px)))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_rect(Rect2(at + Vector2(-4, -size) * Vector2(px, 1.0) - Vector2(0, 2 * px), Vector2(w + 8 * px, size + 6 * px)), Color(0.06, 0.07, 0.09, 0.82 * color.a))
	c.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, color.a))
