class_name EditorContext
extends RefCounted
## What every tool and panel needs to see: the open map, the packs, the undo
## history and the commands wrapper, which level is active, the canvas, what
## is selected, and what the palette currently has picked. Owned by Main.

signal selection_changed
signal level_changed
signal status(text: String)
## The fit tool dragged from one grid corner to another (hex units).
signal fit_dragged(a: Vector2, b: Vector2)

var map: HexMap
var packs: PackLibrary
var history: History
var commands: Commands
var canvas: MapCanvas
var level_index := 0
## View zoom (screen px per canvas px), kept current by MapView so tools can
## size handles in screen pixels.
var zoom := 1.0

## [{collection: "props"|"walls"|"lights"|"notes"|"terrain", id | key}]
var selection: Array = []

## Palette picks.
var terrain_ref := ""          # "woodland:grass"
var terrain_variant := -1      # -1 = random
var brush_radius := 0
var prop_ref := ""
var prop_rotation := 0.0
var prop_scale := 1.0
var prop_flip := false
var wall_preset := "wall"
var wall_style := ""
var light_preset := {}         # a light preset dictionary (without pos)

enum Snap { NONE, CENTER, CORNER }
var snap := Snap.CENTER
var snap_walls := true

const WALL_PRESETS := {
	"wall": {"blocks": {"move": true, "sight": true, "light": true, "sound": true}, "sight_mode": "normal", "door": "none"},
	"door": {"blocks": {"move": true, "sight": true, "light": true, "sound": true}, "sight_mode": "normal", "door": "door", "state": "closed"},
	"secret": {"blocks": {"move": true, "sight": true, "light": true, "sound": true}, "sight_mode": "normal", "door": "secret", "state": "closed"},
	"window": {"blocks": {"move": true, "sight": false, "light": false, "sound": true}, "sight_mode": "normal", "door": "none"},
	"fence": {"blocks": {"move": true, "sight": false, "light": false, "sound": false}, "sight_mode": "normal", "door": "none"},
	"terrain": {"blocks": {"move": false, "sight": true, "light": true, "sound": false}, "sight_mode": "limited", "door": "none"},
	"invisible": {"blocks": {"move": true, "sight": false, "light": false, "sound": false}, "sight_mode": "normal", "door": "none", "hidden": true},
	"ethereal": {"blocks": {"move": false, "sight": true, "light": true, "sound": true}, "sight_mode": "normal", "door": "none"},
}


func level() -> Dictionary:
	return map.level(level_index) if map != null else {}


func set_selection(items: Array) -> void:
	selection = items
	selection_changed.emit()
	canvas.overlay.queue_redraw()


func select_one(collection: String, id: String) -> void:
	set_selection([{"collection": collection, "id": id}])


func clear_selection() -> void:
	if not selection.is_empty():
		set_selection([])


func is_selected(collection: String, id: String) -> bool:
	for s in selection:
		if s.collection == collection and s.get("id", "") == id:
			return true
	return false


func selected_object() -> Dictionary:
	if selection.size() != 1 or selection[0].collection == "terrain":
		return {}
	return HexMap.find_in(level(), selection[0].collection, selection[0].id)


func say(text: String) -> void:
	status.emit(text)


## Canvas hex-unit position of the mouse.
func mouse_hex() -> Vector2:
	return canvas.get_local_mouse_position() / canvas.ppx


## One authored pixel, in hex units.
func ref_px() -> float:
	return 1.0 / float(map.reference_ppx)


func snapped_point(p: Vector2, for_wall := false) -> Vector2:
	if for_wall:
		return map.grid.snap_to_corner(p) if snap_walls else p
	match snap:
		Snap.CENTER: return map.grid.snap_to_center(p)
		Snap.CORNER: return map.grid.snap_to_corner(p)
	return p


## A fresh wall from the current preset/style, with no points.
func new_wall() -> Dictionary:
	var preset: Dictionary = WALL_PRESETS.get(wall_preset, WALL_PRESETS.wall)
	var w := {
		"id": HexMap.new_id("w"), "points": [],
		"blocks": (preset.blocks as Dictionary).duplicate(), "sight_mode": preset.sight_mode,
		"door": preset.door, "state": preset.get("state", "closed"), "one_way": null,
		"z": [0, 1], "hidden": bool(preset.get("hidden", false)),
	}
	if wall_style != "":
		w["style"] = wall_style
	return w


func new_light(pos: Vector2) -> Dictionary:
	var p := light_preset
	return {
		"id": HexMap.new_id("l"), "pos": [snappedf(pos.x, 0.0001), snappedf(pos.y, 0.0001)], "z": 0.5,
		"bright": float(p.get("bright", 1.0)), "dim": float(p.get("dim", 2.0)),
		"color": str(p.get("color", "#ffb060")), "intensity": float(p.get("intensity", 1.0)),
		"angle": 360, "direction": 0, "shadows": true,
		"animation": str(p.get("animation", "none")), "hidden": false,
	}


func new_prop(pos: Vector2) -> Dictionary:
	var def := packs.prop(prop_ref)
	var parts := PackLibrary.split_ref(prop_ref)
	if parts.size() == 2:
		map.note_pack(parts[0], packs.pack_version(parts[0]))
	return {
		"id": HexMap.new_id("p"), "asset": prop_ref,
		"pos": [snappedf(pos.x, 0.0001), snappedf(pos.y, 0.0001)],
		"rot": prop_rotation, "scale": prop_scale, "flip": prop_flip,
		"z": 0, "height": float(def.get("height", 0.5)), "hidden": false,
	}


## Which layer folder a prop of this definition goes into: the folder
## selected in the layers panel if any, else the default for the pack's
## `layer` hint (ground / objects / overhead).
var target_folder := ""

func folder_for_prop(def: Dictionary) -> String:
	if target_folder != "" and not LayerTree.find(level().tree, target_folder).is_empty():
		return target_folder
	return str(LayerTree.LEGACY_LAYER.get(str(def.get("layer", "objects")), "f_props"))


func new_terrain_cell() -> Dictionary:
	var parts := PackLibrary.split_ref(terrain_ref)
	if parts.size() == 2:
		map.note_pack(parts[0], packs.pack_version(parts[0]))
	var variants := packs.terrain_variants(terrain_ref, cell_shape())
	var v := terrain_variant if terrain_variant >= 0 else randi() % variants
	return {"t": terrain_ref, "v": v, "rot": 0, "z": 0}


## "hex" or "square": the shape of the cells of the map being edited.
func cell_shape() -> String:
	return "square" if map != null and map.grid.is_square() else "hex"
