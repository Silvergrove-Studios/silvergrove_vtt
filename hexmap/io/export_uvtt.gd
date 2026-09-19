class_name UvttExport
extends RefCounted
## Universal VTT v1 (.dd2vtt / .uvtt) — the interchange format Dungeondraft
## introduced. Imported natively by Roll20, Fantasy Grounds Unity and
## Arkenforge, and through free importers by Foundry (Universal Battlemap
## Importer) and Owlbear Rodeo (scene-importer + Dynamic Fog).
##
## The format only knows square grids, so the receiving VTT is told the
## pixel density and the hex grid must be chosen there; positions are still
## exact because 1 grid unit = 1 hex unit here. A `hexmap_grid` key carries
## our grid description for tools that want it; standard importers ignore it.
##
## Lossy by design: walls that do not block sight (fences, windows) have no
## representation and are dropped; one-way and limited walls become plain
## walls; secret doors become closed portals.

const FORMAT_VERSION := 0.3


## Size in whole grid units the image must be rendered at (the format wants
## integers; hex maps have half-cell overhangs, so round up).
static func image_size_units(map: HexMap) -> Vector2i:
	var s := map.grid.map_size()
	return Vector2i(ceili(s.x - 1e-6), ceili(s.y - 1e-6))


static func build(map: HexMap, level_index: int, ppx: int, image_png: PackedByteArray) -> Dictionary:
	var lvl := map.level(level_index)
	var size := image_size_units(map)
	var los: Array = []
	var portals: Array = []
	for w in lvl.get("walls", []):
		var pts: Array = w.get("points", [])
		if pts.size() < 2:
			continue
		var door := str(w.get("door", "none"))
		if door != "none":
			var a := _pt(pts[0])
			var b := _pt(pts[pts.size() - 1])
			portals.append({
				"position": _xy((a + b) / 2.0),
				"bounds": [_xy(a), _xy(b)],
				"rotation": (b - a).angle(),
				"closed": str(w.get("state", "closed")) != "open",
				"freestanding": false,
			})
			continue
		var blocks: Dictionary = w.get("blocks", {})
		if not bool(blocks.get("sight", true)) and not bool(blocks.get("light", true)):
			continue   # movement-only barriers do not exist in UVTT
		var line: Array = []
		for p in pts:
			line.append(_xy(_pt(p)))
		los.append(line)
	var lights: Array = []
	for l in lvl.get("lights", []):
		var dim := float(l.get("dim", 0.0))
		var bright := float(l.get("bright", 0.0))
		var c := Color(str(l.get("color", "#ffb060")))
		lights.append({
			"position": _xy(_pt(l.get("pos", [0, 0]))),
			"range": maxf(dim, bright),
			"intensity": float(l.get("intensity", 1.0)),
			# Dungeondraft writes Godot 3 ARGB hex; importers strip the alpha.
			"color": "ff" + c.to_html(false),
			"shadows": bool(l.get("shadows", true)),
		})
	return {
		"format": FORMAT_VERSION,
		"resolution": {
			"map_origin": {"x": 0, "y": 0},
			"map_size": {"x": size.x, "y": size.y},
			"pixels_per_grid": ppx,
		},
		"line_of_sight": los,
		"objects_line_of_sight": [],
		"portals": portals,
		"environment": {"baked_lighting": false, "ambient_light": "ffffffff"},
		"lights": lights,
		"hexmap_grid": map.grid.to_dict(),
		"image": Marshalls.raw_to_base64(image_png) if not image_png.is_empty() else "",
	}


static func to_json(map: HexMap, level_index: int, ppx: int, image_png: PackedByteArray) -> String:
	return JSON.stringify(build(map, level_index, ppx, image_png), "", false)


static func _pt(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _xy(v: Vector2) -> Dictionary:
	return {"x": snappedf(v.x, 0.0001), "y": snappedf(v.y, 0.0001)}
