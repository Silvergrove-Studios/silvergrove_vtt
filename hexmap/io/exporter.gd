class_name Exporter
extends RefCounted
## One place that turns a map into files. Each method renders what it needs
## through MapRenderer (so needs a live renderer and a node in the tree) and
## writes next to `path`. Returns OK or an Error; `last_message` says more.

static var last_message := ""


static func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())


## Flat PNG of a level at `ppx` pixels per hex.
static func png(host: Node, map: HexMap, packs: PackLibrary, path: String, ppx: int, opts: Dictionary = {}) -> Error:
	_ensure_dir(path)
	var img := await MapRenderer.render_map(host, map, packs, ppx, opts)
	var err := img.save_png(path)
	last_message = "wrote %s (%d×%d)" % [path, img.get_width(), img.get_height()]
	return err


## Universal VTT: one .dd2vtt with the image embedded.
static func uvtt(host: Node, map: HexMap, packs: PackLibrary, path: String, ppx: int, level := 0) -> Error:
	_ensure_dir(path)
	var units := UvttExport.image_size_units(map)
	var img := await MapRenderer.render(host, map, packs, ppx, Rect2(Vector2.ZERO, Vector2(units)), {"level": level})
	var flat := MapRenderer.flatten(img, Color(str(map.style.get("background", "#1c1a17"))))
	var text := UvttExport.to_json(map, level, ppx, flat.save_png_to_buffer())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	last_message = "wrote %s (%d×%d px, %d walls, %d lights)" % [path, flat.get_width(), flat.get_height(), map.level(level).walls.size(), map.level(level).lights.size()]
	return OK


## Foundry: scene JSON plus the background image (WebP) beside it. Multi-level
## maps produce one scene per level. Copy both into Foundry's Data folder and
## use the scene's "Import Data".
static func foundry(host: Node, map: HexMap, packs: PackLibrary, path: String, ppx: int) -> Error:
	_ensure_dir(path)
	var base := path.get_basename()
	var written := PackedStringArray()
	for i in map.levels.size():
		var suffix := "" if map.levels.size() == 1 else "_%s" % str(map.level(i).get("id", i))
		var img_path := "%s%s.webp" % [base, suffix]
		var json_path := "%s%s.json" % [base, suffix]
		var img := await MapRenderer.render_map(host, map, packs, ppx, {"level": i, "show_grid": false})
		var flat := MapRenderer.flatten(img, Color(str(map.style.get("background", "#1c1a17"))))
		var err := flat.save_webp(img_path, false)
		if err != OK:
			return err
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		if f == null:
			return FileAccess.get_open_error()
		f.store_string(FoundryExport.to_json(map, i, ppx, img_path.get_file()))
		f.close()
		written.append(json_path.get_file())
	last_message = "wrote " + ", ".join(written)
	return OK


## Tiled: .tmj plus a tiles/ folder of terrain images.
static func tiled(map: HexMap, packs: PackLibrary, path: String, ppx: int, level := 0) -> Error:
	_ensure_dir(path)
	var r := TiledExport.to_json(map, level, ppx)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(r.json)
	f.close()
	var size := TiledExport.tile_size(map.grid, ppx)
	var tile_w := size.x
	var tile_h := size.y
	for t in r.tiles:
		var out := path.get_base_dir().path_join(t.file)
		_ensure_dir(out)
		var tex := packs.terrain_texture(t.ref, t.variant, ppx)
		var img := tex.get_image()
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(tile_w, tile_h, Image.INTERPOLATE_LANCZOS)
		var err := img.save_png(out)
		if err != OK:
			return err
	last_message = "wrote %s and %d tile images" % [path, r.tiles.size()]
	return OK


## Print PDF; see PdfExport for options.
static func pdf(host: Node, map: HexMap, packs: PackLibrary, path: String, opts: Dictionary) -> Error:
	_ensure_dir(path)
	var lay := PdfExport.layout(map.grid.map_size(), opts)
	var err := await PdfExport.export(host, map, packs, path, opts)
	last_message = "wrote %s (%d page%s, %s\" hexes)" % [path, lay.pages.size() + (1 if lay.pages.size() > 1 and lay.options.labels else 0), "" if lay.pages.size() == 1 else "s", PdfWriter.n(snappedf(float(lay.hex_pt) / 72.0, 0.01))]
	return err


## Print bundle for an external layout pipeline (pdf-lib, InDesign...):
##   <dir>/map.png         raster at `dpi` for `hex_size_in` hexes, no grid
##   <dir>/overlay.svg     grid + GM layers as vectors, same pixel size
##   <dir>/map.json        the map document
##   <dir>/bundle.json     sizes and scale so the consumer need not compute them
static func bundle(host: Node, map: HexMap, packs: PackLibrary, dir: String, dpi: int, hex_size_in: float, level := 0) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	var ppx := float(dpi) * hex_size_in
	var img := await MapRenderer.render_map(host, map, packs, ppx, {"level": level, "show_grid": false})
	var err := img.save_png(dir.path_join("map.png"))
	if err != OK:
		return err
	var svg := SvgExport.overlay(map, level, ppx)
	var f := FileAccess.open(dir.path_join("overlay.svg"), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(svg)
	f.close()
	f = FileAccess.open(dir.path_join("map.json"), FileAccess.WRITE)
	f.store_string(map.to_json())
	f.close()
	var size_hex := map.grid.map_size()
	var meta := {
		"map": "map.png", "overlay": "overlay.svg", "document": "map.json",
		"pixels": [img.get_width(), img.get_height()],
		"pixels_per_hex": ppx, "dpi": dpi, "hex_size_in": hex_size_in,
		"size_hex": [size_hex.x, size_hex.y],
		"size_in": [size_hex.x * hex_size_in, size_hex.y * hex_size_in],
		"grid": map.grid.to_dict(), "level": map.level(level).get("id", ""),
	}
	f = FileAccess.open(dir.path_join("bundle.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  ") + "\n")
	f.close()
	last_message = "wrote bundle to %s (%d×%d px)" % [dir, img.get_width(), img.get_height()]
	return OK
