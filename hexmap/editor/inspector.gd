class_name Inspector
extends VBoxContainer
## The right dock: properties of the selected object, edited through
## Commands so everything is undoable. Positions are shown in authored
## pixels (reference_ppx) as well as hex units, because artists think in
## pixels.

var ctx: EditorContext
var _title: Label
var _form: PropertyForm
var _hint: Label
var _current: Dictionary = {}     # the selection entry being shown
var _suspend := false

const LAYERS := ["ground", "objects", "overhead"]
const SIGHT_MODES := ["normal", "limited", "proximity"]
const DOORS := ["none", "door", "secret"]
const STATES := ["closed", "open", "locked"]
const ONE_WAY := ["none", "left", "right"]
const ANIMATIONS := ["none", "torch", "flicker", "pulse"]


func _init(p_ctx: EditorContext) -> void:
	ctx = p_ctx
	custom_minimum_size.x = 290
	_title = Label.new()
	_title.text = "Nothing selected"
	_title.add_theme_font_size_override("font_size", 15)
	add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_form = PropertyForm.new()
	_form.value_changed.connect(_on_value)
	scroll.add_child(_form)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.modulate = Color(1, 1, 1, 0.6)
	add_child(_hint)
	ctx.selection_changed.connect(refresh)
	ctx.map.changed.connect(func(_w: String) -> void: refresh())


func refresh() -> void:
	if _suspend:
		return
	if ctx.selection.size() != 1:
		_current = {}
		_title.text = "Nothing selected" if ctx.selection.is_empty() else "%d objects selected" % ctx.selection.size()
		_form.build([])
		_hint.text = "Shift-click adds to the selection. Drag on empty space for a box." if ctx.selection.is_empty() else "Drag or nudge with arrow keys. Delete removes all."
		return
	var sel: Dictionary = ctx.selection[0]
	var ppx := float(ctx.map.reference_ppx)
	if sel.collection == "terrain":
		var cell := HexMap.key_cell(sel.id)
		var t: Dictionary = ctx.level().get("terrain", {}).get(sel.id, {})
		var off := ctx.map.grid.axial_to_offset(cell)
		_title.text = "Cell col %d, row %d" % [off.x, off.y]
		var def := ctx.packs.terrain(str(t.get("t", "")))
		var variants: int = maxi(1, (def.get("textures", []) as Array).size())
		var opts := []
		for v in variants:
			opts.append(str(v + 1))
		_set_form(sel, [
			{"key": "t", "label": "Terrain", "type": "string"},
			{"key": "v", "label": "Variant", "type": "enum", "options": opts},
			{"key": "rot", "label": "Rotation", "type": "enum", "options": ["0", "1", "2", "3", "4", "5"], "tooltip": "In sixths of a turn"},
			{"key": "z", "label": "Elevation", "type": "float", "step": 0.25, "suffix": " hex"},
		], {"t": t.get("t", ""), "v": str(int(t.get("v", 0)) + 1), "rot": str(int(t.get("rot", 0))), "z": float(t.get("z", 0))})
		_hint.text = "Axial (%d, %d). %s" % [cell.x, cell.y, def.get("name", "")]
		return
	var obj := ctx.selected_object()
	if obj.is_empty():
		_form.build([])
		return
	match sel.collection:
		"props":
			var def := ctx.packs.prop(str(obj.get("asset", "")))
			_title.text = str(def.get("name", obj.get("asset", "Prop")))
			_set_form(sel, [
				{"key": "asset", "label": "Asset", "type": "string"},
				{"key": "pos_px", "label": "Position (px)", "type": "vec2", "step": 1, "tooltip": "Authored pixels at %d px per hex" % int(ppx)},
				{"key": "pos", "label": "Position (hex)", "type": "vec2", "step": 0.01},
				{"key": "rot", "label": "Rotation", "type": "float", "step": 0.5, "suffix": "°"},
				{"key": "scale", "label": "Scale", "type": "float", "step": 0.01, "min": 0.01},
				{"key": "flip", "label": "Flip", "type": "bool"},
				{"key": "layer", "label": "Layer", "type": "enum", "options": LAYERS},
				{"key": "z", "label": "Elevation", "type": "float", "step": 0.25, "suffix": " hex"},
				{"key": "height", "label": "Height", "type": "float", "step": 0.25, "suffix": " hex"},
				{"key": "tint", "label": "Tint", "type": "color"},
				{"key": "hidden", "label": "GM only", "type": "bool"},
			], _with_px(obj, ppx))
			_hint.text = "Size %s hex · anchor %s · %s" % [str(def.get("size", "?")), str(def.get("anchor", "?")), "PgUp/PgDn change draw order"]
		"walls":
			_title.text = "Wall" if str(obj.get("door", "none")) == "none" else str(obj.get("door")).capitalize() + " door"
			var blocks: Dictionary = obj.get("blocks", {})
			var z: Array = obj.get("z", [0, 1])
			_set_form(sel, [
				{"key": "b_move", "label": "Blocks movement", "type": "bool"},
				{"key": "b_sight", "label": "Blocks sight", "type": "bool"},
				{"key": "b_light", "label": "Blocks light", "type": "bool"},
				{"key": "b_sound", "label": "Blocks sound", "type": "bool"},
				{"key": "sight_mode", "label": "Sight mode", "type": "enum", "options": SIGHT_MODES, "tooltip": "limited = see one such wall past (Foundry terrain wall)"},
				{"key": "door", "label": "Door", "type": "enum", "options": DOORS},
				{"key": "state", "label": "Door state", "type": "enum", "options": STATES},
				{"key": "one_way", "label": "One way", "type": "enum", "options": ONE_WAY, "tooltip": "Blocks only from one side (right-hand rule from the first point)"},
				{"key": "z0", "label": "Bottom", "type": "float", "step": 0.25, "suffix": " hex"},
				{"key": "z1", "label": "Top", "type": "float", "step": 0.25, "suffix": " hex"},
				{"key": "style", "label": "Style", "type": "string"},
				{"key": "hidden", "label": "GM only", "type": "bool"},
			], {
				"b_move": blocks.get("move", true), "b_sight": blocks.get("sight", true), "b_light": blocks.get("light", true), "b_sound": blocks.get("sound", true),
				"sight_mode": obj.get("sight_mode", "normal"), "door": obj.get("door", "none"), "state": obj.get("state", "closed"),
				"one_way": str(obj.get("one_way", "none")) if obj.get("one_way", null) != null else "none",
				"z0": float(z[0]), "z1": float(z[1]), "style": obj.get("style", ""), "hidden": obj.get("hidden", false),
			})
			_hint.text = "%d points. Drag a point to move it; Shift while dragging skips corner snap." % (obj.get("points", []) as Array).size()
		"lights":
			_title.text = "Light"
			_set_form(sel, [
				{"key": "pos_px", "label": "Position (px)", "type": "vec2", "step": 1},
				{"key": "pos", "label": "Position (hex)", "type": "vec2", "step": 0.01},
				{"key": "bright", "label": "Bright radius", "type": "float", "step": 0.25, "min": 0, "suffix": " hex"},
				{"key": "dim", "label": "Dim radius", "type": "float", "step": 0.25, "min": 0, "suffix": " hex"},
				{"key": "color", "label": "Colour", "type": "color", "alpha": false},
				{"key": "intensity", "label": "Intensity", "type": "float", "step": 0.05, "min": 0, "max": 2},
				{"key": "angle", "label": "Cone angle", "type": "float", "step": 5, "min": 5, "max": 360, "suffix": "°"},
				{"key": "direction", "label": "Direction", "type": "float", "step": 5, "suffix": "°"},
				{"key": "animation", "label": "Animation", "type": "enum", "options": ANIMATIONS},
				{"key": "shadows", "label": "Casts shadows", "type": "bool"},
				{"key": "z", "label": "Elevation", "type": "float", "step": 0.25, "suffix": " hex"},
				{"key": "hidden", "label": "GM only", "type": "bool"},
			], _with_px(obj, ppx))
			_hint.text = "Radii in hexes: %s %s bright, %s %s dim." % [
				PdfWriter.n(float(obj.get("bright", 0)) * ctx.map.grid.distance), ctx.map.grid.units,
				PdfWriter.n(float(obj.get("dim", 0)) * ctx.map.grid.distance), ctx.map.grid.units]
		"notes":
			_title.text = "Note"
			_set_form(sel, [
				{"key": "title", "label": "Title", "type": "string"},
				{"key": "text", "label": "Text", "type": "text"},
				{"key": "gm_only", "label": "GM only", "type": "bool"},
				{"key": "pos", "label": "Position (hex)", "type": "vec2", "step": 0.01},
			], obj)
			_hint.text = ""


func _with_px(obj: Dictionary, ppx: float) -> Dictionary:
	var v := obj.duplicate()
	var pos: Array = obj.get("pos", [0, 0])
	v["pos_px"] = [roundf(float(pos[0]) * ppx), roundf(float(pos[1]) * ppx)]
	if not v.has("layer") and v.has("asset"):
		v["layer"] = ctx.packs.prop(str(v.asset)).get("layer", "objects")
	if not v.has("tint"):
		v["tint"] = "#ffffff"
	return v


func _set_form(sel: Dictionary, schema: Array, values: Dictionary) -> void:
	if _current.get("collection") == sel.collection and _current.get("id") == sel.id and _form.get_child_count() > 0:
		_form.set_values(values)
	else:
		_current = sel.duplicate()
		_form.build(schema, values)


func _on_value(key: String, value: Variant) -> void:
	if _current.is_empty():
		return
	var coll: String = _current.collection
	var id: String = _current.id
	_suspend = true
	if coll == "terrain":
		var t: Dictionary = (ctx.level().get("terrain", {}).get(id, {}) as Dictionary).duplicate()
		match key:
			"v": t["v"] = int(value) - 1
			"rot": t["rot"] = int(value)
			_: t[key] = value
		ctx.commands.set_terrain(ctx.level_index, [HexMap.key_cell(id)], t)
	else:
		var changes := {}
		match key:
			"pos_px":
				var ppx := float(ctx.map.reference_ppx)
				changes["pos"] = [snappedf(float(value[0]) / ppx, 0.0001), snappedf(float(value[1]) / ppx, 0.0001)]
			"b_move", "b_sight", "b_light", "b_sound":
				var obj := HexMap.find_in(ctx.level(), coll, id)
				var blocks: Dictionary = (obj.get("blocks", {}) as Dictionary).duplicate()
				blocks[key.trim_prefix("b_")] = value
				changes["blocks"] = blocks
			"one_way":
				changes["one_way"] = null if str(value) == "none" else str(value)
				if str(value) == "none":
					# update_object treats null as "remove key"; keep the key present.
					var obj := HexMap.find_in(ctx.level(), coll, id)
					obj["one_way"] = null
					changes = {"one_way": null}
			"z0", "z1":
				var obj := HexMap.find_in(ctx.level(), coll, id)
				var z: Array = (obj.get("z", [0, 1]) as Array).duplicate()
				z[0 if key == "z0" else 1] = float(value)
				changes["z"] = z
			"style":
				changes["style"] = str(value) if str(value) != "" else null
			_:
				changes[key] = value
		ctx.commands.update_object(ctx.level_index, coll, id, changes, "Edit " + key)
	_suspend = false
	refresh()
