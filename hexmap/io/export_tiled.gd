class_name TiledExport
extends RefCounted
## Tiled (mapeditor.org) JSON map, `.tmj`. Tiled is open source (the format
## is documented and stable) and half the tools in the hobby read it, so it
## is the generic interchange: terrain becomes a hexagonal tile layer over an
## image-collection tileset; props, walls, lights and notes become objects
## with properties. Terrain rotation is dropped (Tiled only has flips).
##
## `tiles` in the result lists the tile images the caller must write next to
## the map: [{ "file": "tiles/woodland_grass_0.png", "ref": "woodland:grass", "variant": 0 }].


static func build(map: HexMap, level_index: int, ppx: int, tiles_dir := "tiles") -> Dictionary:
	var grid := map.grid
	var lvl := map.level(level_index)
	var pointy := grid.orientation == HexGrid.Orient.POINTY
	var tile_w := ppx if pointy else roundi(2.0 * HexGrid.R * ppx)
	var tile_h := roundi(2.0 * HexGrid.R * ppx) if pointy else ppx
	var side := roundi(HexGrid.R * ppx)

	# One tile id per (terrain, variant) actually used.
	var tile_ids := {}      # "ref@v" -> local id
	var tiles: Array = []
	var terrain: Dictionary = lvl.get("terrain", {})
	var data: Array = []
	for row in grid.rows:
		for col in grid.columns:
			var key := HexMap.cell_key(grid.offset_to_axial(col, row))
			if not terrain.has(key):
				data.append(0)
				continue
			var t: Dictionary = terrain[key]
			var ref := str(t.get("t", ""))
			var v := int(t.get("v", 0))
			var tk := "%s@%d" % [ref, v]
			if not tile_ids.has(tk):
				var id := tiles.size()
				tile_ids[tk] = id
				var parts := PackLibrary.split_ref(ref)
				var fname := "%s/%s_%s_%d.png" % [tiles_dir, parts[0] if parts.size() == 2 else "x", parts[1] if parts.size() == 2 else ref, v]
				tiles.append({
					"id": id, "image": fname, "imagewidth": tile_w, "imageheight": tile_h,
					"properties": [
						{"name": "terrain", "type": "string", "value": ref},
						{"name": "variant", "type": "int", "value": v},
					],
					"_ref": ref, "_variant": v,
				})
			data.append(tile_ids[tk] + 1)   # firstgid is 1

	var tileset := {
		"firstgid": 1, "name": "terrain", "tilecount": tiles.size(), "columns": 0,
		"tilewidth": tile_w, "tileheight": tile_h, "margin": 0, "spacing": 0,
		"grid": {"orientation": "orthogonal", "width": tile_w, "height": tile_h},
		"tiles": [],
	}
	var tile_files: Array = []
	for t in tiles:
		tile_files.append({"file": t.image, "ref": t._ref, "variant": t._variant})
		var clean: Dictionary = t.duplicate()
		clean.erase("_ref")
		clean.erase("_variant")
		tileset.tiles.append(clean)

	var shown := LayerTree.visible_refs(lvl)
	var objects_props: Array = []
	var next_id := 1
	for p in lvl.get("props", []):
		if not shown.get(LayerTree.ref("props", str(p.get("id", ""))), true):
			continue
		var pos := _pt(p.get("pos", [0, 0])) * ppx
		objects_props.append({
			"id": next_id, "name": str(p.get("id", "")), "type": "prop", "point": true,
			"x": snappedf(pos.x, 0.01), "y": snappedf(pos.y, 0.01), "width": 0, "height": 0,
			"rotation": float(p.get("rot", 0.0)), "visible": not bool(p.get("hidden", false)),
			"properties": _props({
				"asset": str(p.get("asset", "")), "scale": float(p.get("scale", 1.0)),
				"flip": bool(p.get("flip", false)), "layer": _folder_path(lvl, "props", str(p.get("id", ""))),
				"z": float(p.get("z", 0.0)), "height": float(p.get("height", 0.0)),
			}),
		})
		next_id += 1
	var objects_walls: Array = []
	for w in lvl.get("walls", []):
		var pts: Array = w.get("points", [])
		if pts.size() < 2 or not shown.get(LayerTree.ref("walls", str(w.get("id", ""))), true):
			continue
		var origin := _pt(pts[0]) * ppx
		var poly: Array = []
		for q in pts:
			var v := _pt(q) * ppx - origin
			poly.append({"x": snappedf(v.x, 0.01), "y": snappedf(v.y, 0.01)})
		var blocks: Dictionary = w.get("blocks", {})
		var z: Array = w.get("z", [0, 1])
		objects_walls.append({
			"id": next_id, "name": str(w.get("id", "")), "type": "wall",
			"x": snappedf(origin.x, 0.01), "y": snappedf(origin.y, 0.01), "width": 0, "height": 0, "rotation": 0,
			"visible": not bool(w.get("hidden", false)),
			"polyline": poly,
			"properties": _props({
				"blocks_move": bool(blocks.get("move", true)), "blocks_sight": bool(blocks.get("sight", true)),
				"blocks_light": bool(blocks.get("light", true)), "blocks_sound": bool(blocks.get("sound", true)),
				"sight_mode": str(w.get("sight_mode", "normal")),
				"door": str(w.get("door", "none")), "state": str(w.get("state", "closed")),
				"one_way": str(w.get("one_way", "")) if w.get("one_way", null) != null else "",
				"z_bottom": float(z[0]), "z_top": float(z[1]),
			}),
		})
		next_id += 1
	var objects_lights: Array = []
	for l in lvl.get("lights", []):
		if not shown.get(LayerTree.ref("lights", str(l.get("id", ""))), true):
			continue
		var pos := _pt(l.get("pos", [0, 0])) * ppx
		var r := float(l.get("dim", 0.0)) * ppx
		objects_lights.append({
			"id": next_id, "name": str(l.get("id", "")), "type": "light", "ellipse": true,
			"x": snappedf(pos.x - r, 0.01), "y": snappedf(pos.y - r, 0.01), "width": snappedf(2 * r, 0.01), "height": snappedf(2 * r, 0.01),
			"rotation": 0, "visible": not bool(l.get("hidden", false)),
			"properties": _props({
				"bright": float(l.get("bright", 0.0)), "dim": float(l.get("dim", 0.0)),
				"color": str(l.get("color", "#ffb060")), "intensity": float(l.get("intensity", 1.0)),
				"angle": float(l.get("angle", 360.0)), "direction": float(l.get("direction", 0.0)),
				"animation": str(l.get("animation", "none")), "z": float(l.get("z", 0.0)),
			}),
		})
		next_id += 1
	var objects_notes: Array = []
	for n_ in lvl.get("notes", []):
		if not shown.get(LayerTree.ref("notes", str(n_.get("id", ""))), true):
			continue
		var pos := _pt(n_.get("pos", [0, 0])) * ppx
		objects_notes.append({
			"id": next_id, "name": str(n_.get("title", "")), "type": "note", "point": true,
			"x": snappedf(pos.x, 0.01), "y": snappedf(pos.y, 0.01), "width": 0, "height": 0, "rotation": 0,
			"visible": true,
			"properties": _props({"text": str(n_.get("text", "")), "gm_only": bool(n_.get("gm_only", true))}),
		})
		next_id += 1

	var stagger := grid.tiled_stagger()
	var layer_id := 1
	var layers: Array = [{
		"id": layer_id, "name": "terrain", "type": "tilelayer", "visible": true, "opacity": 1,
		"x": 0, "y": 0, "width": grid.columns, "height": grid.rows, "data": data,
	}]
	for entry in [["props", objects_props], ["walls", objects_walls], ["lights", objects_lights], ["notes", objects_notes]]:
		layer_id += 1
		layers.append({
			"id": layer_id, "name": entry[0], "type": "objectgroup", "visible": true, "opacity": 1,
			"x": 0, "y": 0, "draworder": "topdown", "objects": entry[1],
		})
	var doc := {
		"type": "map", "version": "1.10", "tiledversion": "1.11.0",
		"orientation": "hexagonal", "renderorder": "right-down",
		"staggeraxis": stagger.staggeraxis, "staggerindex": stagger.staggerindex,
		"hexsidelength": side,
		"width": grid.columns, "height": grid.rows,
		"tilewidth": tile_w, "tileheight": tile_h,
		"infinite": false, "compressionlevel": -1,
		"nextlayerid": layer_id + 1, "nextobjectid": next_id,
		"backgroundcolor": str(map.style.get("background", "#1c1a17")),
		"properties": _props({"hexmap_id": str(map.doc.get("id", "")), "name": map.name, "level": str(lvl.get("id", "")),
			"distance": grid.distance, "units": grid.units}),
		"tilesets": [tileset],
		"layers": layers,
	}
	return {"map": doc, "tiles": tile_files}


static func to_json(map: HexMap, level_index: int, ppx: int, tiles_dir := "tiles") -> Dictionary:
	var b := build(map, level_index, ppx, tiles_dir)
	return {"json": JSON.stringify(b.map, " ", false) + "\n", "tiles": b.tiles}


static func _folder_path(lvl: Dictionary, collection: String, id: String) -> String:
	var tree: Array = lvl.get("tree", [])
	var names := PackedStringArray()
	for fid in LayerTree.ancestors(tree, LayerTree.ref(collection, id)):
		names.append(str(LayerTree.find(tree, fid).get("name", fid)))
	return "/".join(names)


static func _props(d: Dictionary) -> Array:
	var out: Array = []
	var keys := d.keys()
	keys.sort()
	for k in keys:
		var v = d[k]
		var t := "string"
		if v is bool:
			t = "bool"
		elif v is int:
			t = "int"
		elif v is float:
			t = "float"
		out.append({"name": k, "type": t, "value": v})
	return out


static func _pt(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
