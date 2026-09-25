class_name PdfExport
extends RefCounted
## Print-ready PDF. Two modes:
##
##  - **tiled**: hexes at a physical size ("1-inch hexes") across as many
##    pages as it takes, with overlap, crop marks and an assembly page — for
##    playing on with miniatures.
##  - **fit**: the whole map on one page, hex size chosen to fit — for a
##    rulebook figure or a GM handout.
##
## The raster (terrain and props) is rendered at `dpi`; the grid, walls,
## lights and labels are drawn as vectors on top so they print crisp at any
## size. `layout()` is pure and unit-tested; `export()` needs a renderer.

const DEFAULTS := {
	"mode": "tiled",          # tiled | fit
	"paper": "letter",        # key of PdfWriter.PAPER
	"landscape": false,
	"hex_size_in": 1.0,       # flat-to-flat, inches (tiled mode)
	"margin_in": 0.5,
	"overlap_in": 0.25,
	"dpi": 150,
	"jpeg_quality": 0.9,      # < 0 for lossless Flate
	"crop_marks": true,
	"grid": true,
	"grid_color": Color(0, 0, 0, 0.45),
	"gm_layers": false,       # walls, lights, notes as vector overlays
	"labels": true,           # page labels and assembly page
	"background": "map",      # map | white — what shows outside the hexes
	"level": 0,
}


static func options(overrides: Dictionary) -> Dictionary:
	var o := DEFAULTS.duplicate()
	for k in overrides:
		o[k] = overrides[k]
	return o


## Page geometry. Returns:
##   { page: Vector2 (pt), printable: Rect2 (pt, on page), hex_pt: float,
##     cols: int, rows: int, pages: [ { col, row, region_pt: Rect2 (map space, pt) } ] }
static func layout(map_size_hex: Vector2, opts: Dictionary) -> Dictionary:
	var o := options(opts)
	var page: Vector2 = PdfWriter.PAPER.get(str(o.paper), PdfWriter.PAPER.letter)
	if bool(o.landscape):
		page = Vector2(page.y, page.x)
	var margin := float(o.margin_in) * PdfWriter.PT_PER_INCH
	var printable := Rect2(Vector2(margin, margin), page - Vector2(margin, margin) * 2.0)
	var overlap := float(o.overlap_in) * PdfWriter.PT_PER_INCH
	var hex_pt: float
	var pages: Array = []
	var cols := 1
	var rows := 1
	if str(o.mode) == "fit":
		hex_pt = minf(printable.size.x / map_size_hex.x, printable.size.y / map_size_hex.y)
		pages.append({"col": 0, "row": 0, "region_pt": Rect2(Vector2.ZERO, map_size_hex * hex_pt)})
	else:
		hex_pt = float(o.hex_size_in) * PdfWriter.PT_PER_INCH
		var map_pt := map_size_hex * hex_pt
		var step := printable.size - Vector2(overlap, overlap)
		step.x = maxf(step.x, 1.0)
		step.y = maxf(step.y, 1.0)
		cols = maxi(1, ceili((map_pt.x - overlap - 1e-6) / step.x))
		rows = maxi(1, ceili((map_pt.y - overlap - 1e-6) / step.y))
		for r in rows:
			for c in cols:
				var origin := Vector2(c * step.x, r * step.y)
				var size := printable.size
				# The last column/row is trimmed to the map edge.
				size.x = minf(size.x, map_pt.x - origin.x)
				size.y = minf(size.y, map_pt.y - origin.y)
				pages.append({"col": c, "row": r, "region_pt": Rect2(origin, size)})
	return {"page": page, "printable": printable, "hex_pt": hex_pt, "cols": cols, "rows": rows, "pages": pages, "options": o}


## Write the PDF. `host` is any node in the tree (rendering needs one).
static func export(host: Node, map: HexMap, packs: PackLibrary, path: String, opts: Dictionary) -> Error:
	var lay := layout(map.grid.map_size(), opts)
	var o: Dictionary = lay.options
	var pdf := PdfWriter.new()
	pdf.title = map.name
	pdf.author = str(map.doc.get("meta", {}).get("author", ""))
	pdf.subject = "%s map, %s\" %s = %s %s" % [map.grid.cell_word().capitalize(), _inches(lay.hex_pt), map.grid.cell_word(true), PdfWriter.n(map.grid.distance), map.grid.units]
	var hex_pt: float = lay.hex_pt
	var ppx := float(o.dpi) * hex_pt / PdfWriter.PT_PER_INCH
	var level := int(o.level)
	var font_pt := 9.0

	if bool(o.labels) and lay.pages.size() > 1:
		_assembly_page(pdf, map, lay)

	for pg in lay.pages:
		var region_pt: Rect2 = pg.region_pt
		var region_hex := Rect2(region_pt.position / hex_pt, region_pt.size / hex_pt)
		var page := pdf.add_page(lay.page.x, lay.page.y)
		var printable: Rect2 = lay.printable
		var place := Rect2(printable.position, region_pt.size)
		# Raster
		var img := await MapRenderer.render(host, map, packs, ppx, region_hex, {
			"level": level, "show_grid": false, "show_walls": false, "show_lights": false, "show_notes": false,
		})
		if str(o.background) == "white":
			img = _strip_background(img, map, region_hex, ppx)
		var flat := MapRenderer.flatten(img, Color.WHITE)
		var name := pdf.add_image(flat, float(o.jpeg_quality))
		pdf.image(page, name, place)
		# Vector overlays, clipped to the placed map region.
		pdf.push_clip(page, place)
		var to_page := func(p_hex: Vector2) -> Vector2:
			return place.position + (p_hex - region_hex.position) * hex_pt
		if bool(o.grid) and map.shows_grid():
			var gw := maxf(float(map.style.get("grid_width", 0.012)) * hex_pt, 0.4)
			pdf.set_line(page, gw, o.grid_color)
			var pad := region_hex.grow(1.0)
			for cell in map.grid.all_cells():
				var c := map.grid.cell_center(cell)
				if not pad.has_point(c):
					continue
				var pts := PackedVector2Array()
				for k in map.grid.cell_corners(cell):
					pts.append(to_page.call(k))
				pdf.polyline(page, pts, true)
		if bool(o.gm_layers):
			_gm_overlays(pdf, page, map.level(level), to_page, hex_pt)
		pdf.pop_clip(page)
		# Trim: a hairline around the placed region.
		pdf.set_line(page, 0.3, Color(0, 0, 0, 0.6))
		pdf.stroke_rect(page, place)
		if bool(o.crop_marks) and lay.pages.size() > 1:
			_crop_marks(pdf, page, place, lay.page)
		if bool(o.labels):
			var label := map.name
			if lay.pages.size() > 1:
				label += "  —  row %d / %d, column %d / %d" % [pg.row + 1, lay.rows, pg.col + 1, lay.cols]
			label += "  —  %s\" %s, 1 %s = %s %s" % [_inches(hex_pt), map.grid.cell_word(true), map.grid.cell_word(), PdfWriter.n(map.grid.distance), map.grid.units]
			pdf.text(page, label, Vector2(printable.position.x, lay.page.y - printable.position.y + font_pt * 1.6), font_pt, Color(0.25, 0.25, 0.25))
	return pdf.save(path)


static func _inches(pt: float) -> String:
	return PdfWriter.n(snappedf(pt / 72.0, 0.01))


## Rendering outside the hex outline (the map background colour) becomes
## transparent so it flattens to paper white.
static func _strip_background(img: Image, map: HexMap, region_hex: Rect2, ppx: float) -> Image:
	var out: Image = img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	var bg := Color(str(map.style.get("background", "#1c1a17")))
	var w := out.get_width()
	var h := out.get_height()
	# Cheap and exact enough: a pixel is background if it matches the
	# background colour closely and lies outside every cell (checked by the
	# hex test, which is what makes edges clean).
	for y in h:
		for x in w:
			var c := out.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.02:
				continue
			var p := region_hex.position + Vector2(x + 0.5, y + 0.5) / ppx
			if not map.grid.in_bounds(map.grid.world_to_axial(p)):
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out


static func _gm_overlays(pdf: PdfWriter, page: int, lvl: Dictionary, to_page: Callable, hex_pt: float) -> void:
	var shown := LayerTree.visible_refs(lvl)
	for w in lvl.get("walls", []):
		if not shown.get(LayerTree.ref("walls", str(w.get("id", ""))), true):
			continue
		var pts := PackedVector2Array()
		for p in w.get("points", []):
			pts.append(to_page.call(Vector2(float(p[0]), float(p[1]))))
		var color := MapCanvas.wall_color(w)
		color = color.darkened(0.45)
		var door := str(w.get("door", "none"))
		var width := hex_pt * (0.07 if door != "none" else 0.045)
		var dash := PackedFloat32Array([hex_pt * 0.08, hex_pt * 0.06]) if str(w.get("sight_mode", "normal")) == "limited" or door == "secret" else PackedFloat32Array()
		# White halo under the line so it reads on any terrain.
		pdf.set_line(page, width + 1.5, Color(1, 1, 1, 0.85))
		pdf.polyline(page, pts)
		pdf.set_line(page, width, color, dash)
		pdf.polyline(page, pts)
	for l in lvl.get("lights", []):
		if not shown.get(LayerTree.ref("lights", str(l.get("id", ""))), true):
			continue
		var c: Vector2 = to_page.call(Vector2(float(l.pos[0]), float(l.pos[1])))
		var color := Color(str(l.get("color", "#ffb060"))).darkened(0.2)
		pdf.set_line(page, 0.8, color, PackedFloat32Array([3.0, 3.0]))
		for radius in [float(l.get("bright", 0.0)), float(l.get("dim", 0.0))]:
			if radius <= 0.0:
				continue
			var pts := PackedVector2Array()
			for i in 48:
				var a := TAU * i / 48.0
				pts.append(c + Vector2(cos(a), sin(a)) * radius * hex_pt)
			pdf.polyline(page, pts, true)
		pdf.fill_polygon(page, _star(c, hex_pt * 0.12), color)
	for n_ in lvl.get("notes", []):
		if not shown.get(LayerTree.ref("notes", str(n_.get("id", ""))), true):
			continue
		var c: Vector2 = to_page.call(Vector2(float(n_.pos[0]), float(n_.pos[1])))
		pdf.fill_polygon(page, _circle(c, hex_pt * 0.1), Color("#f0d060"))
		pdf.text(page, str(n_.get("title", "")), c + Vector2(hex_pt * 0.14, hex_pt * 0.04), maxf(hex_pt * 0.14, 5.0), Color.BLACK)


static func _circle(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0 - PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	return pts


static func _crop_marks(pdf: PdfWriter, page: int, place: Rect2, page_size: Vector2) -> void:
	pdf.set_line(page, 0.4, Color.BLACK)
	var len := 14.0
	var gap := 4.0
	var xs := [place.position.x, place.end.x]
	var ys := [place.position.y, place.end.y]
	for x in xs:
		pdf.line(page, Vector2(x, maxf(place.position.y - gap - len, 2.0)), Vector2(x, place.position.y - gap))
		pdf.line(page, Vector2(x, place.end.y + gap), Vector2(x, minf(place.end.y + gap + len, page_size.y - 2.0)))
	for y in ys:
		pdf.line(page, Vector2(maxf(place.position.x - gap - len, 2.0), y), Vector2(place.position.x - gap, y))
		pdf.line(page, Vector2(place.end.x + gap, y), Vector2(minf(place.end.x + gap + len, page_size.x - 2.0), y))


## First page of a multi-page print: how the sheets go together.
static func _assembly_page(pdf: PdfWriter, map: HexMap, lay: Dictionary) -> void:
	var page := pdf.add_page(lay.page.x, lay.page.y)
	var printable: Rect2 = lay.printable
	pdf.text(page, map.name, Vector2(printable.position.x, printable.position.y + 20.0), 20.0, Color.BLACK)
	var info := "%d sheets (%d across × %d down) — %s\" %s — trim on the hairline, overlap %s\" and tape from the top-left sheet." % [
		lay.pages.size(), lay.cols, lay.rows, _inches(lay.hex_pt), map.grid.cell_word(true), PdfWriter.n(float(lay.options.overlap_in))]
	pdf.text(page, info, Vector2(printable.position.x, printable.position.y + 40.0), 10.0, Color(0.25, 0.25, 0.25))
	# Sheet diagram
	var map_pt := map.grid.map_size() * float(lay.hex_pt)
	var avail := Rect2(printable.position + Vector2(0, 60), printable.size - Vector2(0, 60))
	var scale := minf(avail.size.x / map_pt.x, avail.size.y / map_pt.y) * 0.95
	var origin := avail.position + (avail.size - map_pt * scale) / 2.0
	pdf.set_line(page, 0.5, Color(0.3, 0.3, 0.3))
	for pg in lay.pages:
		var r: Rect2 = pg.region_pt
		var rr := Rect2(origin + r.position * scale, r.size * scale)
		pdf.fill_rect(page, rr, Color(0.93, 0.93, 0.93) if (pg.col + pg.row) % 2 == 0 else Color(0.98, 0.98, 0.98))
		pdf.stroke_rect(page, rr)
		pdf.text(page, "%d,%d" % [pg.row + 1, pg.col + 1], rr.get_center() + Vector2(0, 4), minf(rr.size.y * 0.3, 14.0), Color(0.2, 0.2, 0.2), 1)
	pdf.set_line(page, 1.0, Color.BLACK)
	pdf.stroke_rect(page, Rect2(origin, map_pt * scale))
