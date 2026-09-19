class_name FoundryExport
extends RefCounted
## Foundry VTT scene JSON, the shape a Scene's "Import Data" accepts (v12+;
## the fields used here are unchanged through v14). Hex grids map exactly:
## our orientation/offset are Foundry's HEXODDR/HEXEVENR/HEXODDQ/HEXEVENQ and
## our hex unit is Foundry's `grid.size` (flat-to-flat).
##
## Walls keep full semantics (sense types, doors, direction). Wall heights and
## level ranges are written as the flags the Wall Height / Levels modules
## read. Props are baked into the background image. Notes go under
## `flags.hexmap` because Foundry notes need journal entries.
##
## Padding is written as 0 so exported pixel coordinates need no offset; add
## padding in Foundry afterwards if wanted.

const SENSE_NONE := 0
const SENSE_LIMITED := 10
const SENSE_NORMAL := 20
const SENSE_PROXIMITY := 30
const MOVE_NONE := 0
const MOVE_NORMAL := 20

const ANIMATION := {"torch": "torch", "flicker": "flame", "pulse": "pulse", "none": null}


static func build(map: HexMap, level_index: int, ppx: int, background_src: String) -> Dictionary:
	var lvl := map.level(level_index)
	var grid := map.grid
	var size_px := Vector2i((grid.map_size() * ppx).ceil())
	var distance := grid.distance
	var walls: Array = []
	for w in lvl.get("walls", []):
		if not LayerTree.shown(lvl, "walls", str(w.get("id", ""))):
			continue
		var pts: Array = w.get("points", [])
		for i in pts.size() - 1:
			walls.append(_wall(w, _pt(pts[i]) * ppx, _pt(pts[i + 1]) * ppx, distance))
	var lights: Array = []
	for l in lvl.get("lights", []):
		if not LayerTree.shown(lvl, "lights", str(l.get("id", ""))):
			continue
		var pos := _pt(l.get("pos", [0, 0])) * ppx
		var anim = ANIMATION.get(str(l.get("animation", "none")), null)
		lights.append({
			"_id": _id(),
			"x": roundi(pos.x), "y": roundi(pos.y),
			"elevation": snappedf(float(l.get("z", 0.0)) * distance, 0.01),
			"rotation": float(l.get("direction", 0.0)),
			"walls": true, "vision": false,
			"config": {
				"negative": false, "priority": 0,
				"alpha": 0.5,
				"angle": float(l.get("angle", 360.0)),
				"bright": snappedf(float(l.get("bright", 0.0)) * distance, 0.01),
				"dim": snappedf(float(l.get("dim", 0.0)) * distance, 0.01),
				"color": Color(str(l.get("color", "#ffb060"))).to_html(false).insert(0, "#"),
				"coloration": 1,
				"attenuation": 0.5,
				"luminosity": clampf(float(l.get("intensity", 1.0)) * 0.5, 0.0, 1.0),
				"saturation": 0, "contrast": 0,
				"shadows": 0,
				"animation": {"type": anim, "speed": 5, "intensity": 5, "reverse": false},
				"darkness": {"min": 0, "max": 1},
			},
			"hidden": bool(l.get("hidden", false)),
			"flags": {},
		})
	var range_a: Array = lvl.get("elevation_range", [0, 1])
	var scene := {
		"name": map.name if map.levels.size() == 1 else "%s — %s" % [map.name, lvl.get("name", "")],
		"navigation": true,
		"width": size_px.x, "height": size_px.y, "padding": 0,
		"background": {"src": background_src, "offsetX": 0, "offsetY": 0, "scaleX": 1, "scaleY": 1, "rotation": 0},
		"backgroundColor": str(map.style.get("background", "#1c1a17")),
		"grid": {
			"type": grid.foundry_grid_type(),
			"size": ppx,
			"style": "solidLines", "thickness": 1,
			"color": "#000000", "alpha": 0.15,
			"distance": distance, "units": grid.units,
		},
		"tokenVision": true,
		"fog": {"exploration": true},
		"environment": {"darknessLevel": 0.0, "globalLight": {"enabled": true}},
		"initial": {"x": size_px.x / 2, "y": size_px.y / 2, "scale": 1},
		"walls": walls,
		"lights": lights,
		"tokens": [], "notes": [], "tiles": [], "drawings": [], "sounds": [], "templates": [], "regions": [],
		"flags": {
			"hexmap": {
				"id": map.doc.get("id", ""), "level": lvl.get("id", ""), "grid": grid.to_dict(),
				"notes": lvl.get("notes", []),
			},
			"levels": {"sceneLevels": [[snappedf(float(range_a[0]) * distance, 0.01), snappedf(float(range_a[1]) * distance, 0.01), str(lvl.get("name", ""))]]},
		},
	}
	return scene


static func to_json(map: HexMap, level_index: int, ppx: int, background_src: String) -> String:
	return JSON.stringify(build(map, level_index, ppx, background_src), "  ", false) + "\n"


static func _wall(w: Dictionary, a: Vector2, b: Vector2, distance: float) -> Dictionary:
	var blocks: Dictionary = w.get("blocks", {})
	var door := str(w.get("door", "none"))
	var sight_sense := SENSE_NONE
	if bool(blocks.get("sight", true)):
		match str(w.get("sight_mode", "normal")):
			"limited": sight_sense = SENSE_LIMITED
			"proximity": sight_sense = SENSE_PROXIMITY
			_: sight_sense = SENSE_NORMAL
	var light_sense := sight_sense if bool(blocks.get("light", true)) else SENSE_NONE
	if bool(blocks.get("light", true)) and not bool(blocks.get("sight", true)):
		light_sense = SENSE_NORMAL
	var dir := 0
	match w.get("one_way", null):
		"left": dir = 1
		"right": dir = 2
	var ds := 0
	match str(w.get("state", "closed")):
		"open": ds = 1
		"locked": ds = 2
	var flags := {}
	if w.has("z"):
		var z: Array = w["z"]
		flags["wall-height"] = {"bottom": snappedf(float(z[0]) * distance, 0.01), "top": snappedf(float(z[1]) * distance, 0.01)}
	return {
		"_id": _id(),
		"c": [roundi(a.x), roundi(a.y), roundi(b.x), roundi(b.y)],
		"light": light_sense,
		"sight": sight_sense,
		"sound": SENSE_NORMAL if bool(blocks.get("sound", true)) else SENSE_NONE,
		"move": MOVE_NORMAL if bool(blocks.get("move", true)) else MOVE_NONE,
		"dir": dir,
		"door": {"none": 0, "door": 1, "secret": 2}.get(door, 0),
		"ds": ds if door != "none" else 0,
		"doorSound": "",
		"threshold": {"light": null, "sight": null, "sound": null, "attenuation": false},
		"flags": flags,
	}


static func _pt(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Foundry document ids are 16 alphanumerics.
static func _id() -> String:
	const CH := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var s := ""
	for i in 16:
		s += CH[randi() % CH.length()]
	return s
