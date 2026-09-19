class_name SvgExport
extends RefCounted
## Vector overlay (grid, walls, lights, notes) as SVG, in pixels at `ppx`,
## for print pipelines that composite it over the raster. Pure; unit-tested.


static func overlay(map: HexMap, level_index: int, ppx: float) -> String:
	var grid := map.grid
	var size := grid.map_size() * ppx
	var lvl := map.level(level_index)
	var s := PackedStringArray()
	s.append('<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="0 0 %s %s">' % [_n(size.x), _n(size.y), _n(size.x), _n(size.y)])
	s.append('<g id="grid" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="%s" stroke-linejoin="round">' % [
		_hex(Color(str(map.style.get("grid_color", "#00000066")))), _n(Color(str(map.style.get("grid_color", "#00000066"))).a),
		_n(maxf(float(map.style.get("grid_width", 0.012)) * ppx, 0.5))])
	for cell in grid.all_cells():
		var pts := PackedStringArray()
		for c in grid.cell_corners(cell):
			pts.append("%s,%s" % [_n(c.x * ppx), _n(c.y * ppx)])
		s.append('<polygon points="%s"/>' % " ".join(pts))
	s.append('</g>')
	var shown := LayerTree.visible_refs(lvl)
	s.append('<g id="walls" fill="none" stroke-linecap="round" stroke-linejoin="round">')
	for w in lvl.get("walls", []):
		if not shown.get(LayerTree.ref("walls", str(w.get("id", ""))), true):
			continue
		var pts := PackedStringArray()
		for p in w.get("points", []):
			pts.append("%s,%s" % [_n(float(p[0]) * ppx), _n(float(p[1]) * ppx)])
		var color := MapCanvas.wall_color(w)
		var dash := ' stroke-dasharray="%s %s"' % [_n(ppx * 0.08), _n(ppx * 0.06)] if str(w.get("sight_mode", "normal")) == "limited" or str(w.get("door", "none")) == "secret" else ""
		s.append('<polyline id="%s" data-door="%s" points="%s" stroke="%s" stroke-width="%s"%s/>' % [
			str(w.get("id", "")), str(w.get("door", "none")), " ".join(pts), _hex(color), _n(ppx * (0.07 if str(w.get("door", "none")) != "none" else 0.045)), dash])
	s.append('</g>')
	s.append('<g id="lights" fill="none" stroke-dasharray="4 4">')
	for l in lvl.get("lights", []):
		if not shown.get(LayerTree.ref("lights", str(l.get("id", ""))), true):
			continue
		var c := Vector2(float(l.pos[0]), float(l.pos[1])) * ppx
		var color := _hex(Color(str(l.get("color", "#ffb060"))))
		for radius in [float(l.get("bright", 0.0)), float(l.get("dim", 0.0))]:
			if radius > 0.0:
				s.append('<circle cx="%s" cy="%s" r="%s" stroke="%s" stroke-width="1"/>' % [_n(c.x), _n(c.y), _n(radius * ppx), color])
		s.append('<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="none"/>' % [_n(c.x), _n(c.y), _n(ppx * 0.08), color])
	s.append('</g>')
	s.append('<g id="notes" font-family="Helvetica, Arial, sans-serif" font-size="%s">' % _n(ppx * 0.14))
	for n_ in lvl.get("notes", []):
		if not shown.get(LayerTree.ref("notes", str(n_.get("id", ""))), true):
			continue
		var c := Vector2(float(n_.pos[0]), float(n_.pos[1])) * ppx
		s.append('<circle cx="%s" cy="%s" r="%s" fill="#f0d060" stroke="#000" stroke-width="1"/>' % [_n(c.x), _n(c.y), _n(ppx * 0.1)])
		s.append('<text x="%s" y="%s">%s</text>' % [_n(c.x + ppx * 0.14), _n(c.y + ppx * 0.05), str(n_.get("title", "")).xml_escape()])
	s.append('</g>')
	s.append('</svg>')
	return "\n".join(s) + "\n"


static func _n(v: float) -> String:
	return PdfWriter.n(snappedf(v, 0.01))


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)
