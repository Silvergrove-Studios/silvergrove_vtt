class_name TableInspector
extends VBoxContainer
## Properties of the selected token, or the table-relevant state of a
## selected map element (a door's state, a light on or off, a GM-only thing
## revealed). Every edit is a command, so it is undoable.

var ctx: TableContext
var _title: Label
var _form: PropertyForm
var _hint: Label
var _buttons: HBoxContainer
var _current: Dictionary = {}
var _suspend := false

const STATES := ["closed", "open", "locked"]


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	custom_minimum_size.x = 260
	_title = Label.new()
	_title.text = "Nothing selected"
	_title.theme_type_variation = "HeaderLabel"
	add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_form = PropertyForm.new()
	_form.value_changed.connect(_on_value)
	scroll.add_child(_form)
	_buttons = HBoxContainer.new()
	add_child(_buttons)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.theme_type_variation = "DimLabel"
	add_child(_hint)
	ctx.selection_changed.connect(refresh)
	ctx.scene_changed.connect(refresh)
	ctx.encounter_changed.connect(refresh)


func bind() -> void:
	ctx.encounter().changed.connect(func(_what: String, _s: String) -> void:
		if not _suspend:
			refresh())
	refresh()


func _player_options() -> Array:
	var out := ["(the DM)"]
	for p in ctx.encounter().players:
		out.append(str(p.name))
	return out


func _player_id(option: String) -> Variant:
	for p in ctx.encounter().players:
		if str(p.name) == option:
			return str(p.id)
	return null


## The scene's grid: a token's sight in feet is so many of its hexes.
func _grid() -> HexGrid:
	var m := ctx.map() if ctx.state != null else null
	return m.grid if m != null else null


func _player_name(id) -> String:
	if id == null:
		return "(the DM)"
	return str(ctx.encounter().player(str(id)).get("name", "(the DM)"))


func refresh() -> void:
	if _suspend:
		return
	for b in _buttons.get_children():
		b.queue_free()
	if ctx.state == null or ctx.selection.size() != 1:
		_current = {}
		_title.text = "Nothing selected" if ctx.state == null or ctx.selection.is_empty() else "%d tokens" % ctx.selection.size()
		_form.build([])
		_hint.text = "Click a token or a door, light, prop or note. Shift-click adds tokens; drag on empty space for a box." if ctx.selection.is_empty() else "Drag to move them together. H hides or reveals; Delete removes."
		return
	_current = ctx.selection[0]
	if _current.kind == "token":
		var tk := ctx.selected_token()
		if tk.is_empty():
			_title.text = "Nothing selected"
			_form.build([])
			return
		_title.text = str(tk.get("name", "Token"))
		_form.build([
			{"key": "name", "label": "Name", "type": "string"},
			{"key": "label", "label": "Label", "type": "string", "tooltip": "Shown on the disc when there is no art"},
			{"key": "color", "label": "Colour", "type": "color", "alpha": false},
			{"key": "size", "label": "Size", "type": "int", "min": 1, "max": 6, "suffix": " hex"},
			{"key": "owner", "label": "Owner", "type": "enum", "options": _player_options(), "tooltip": "The player who may move it and sees through it"},
			{"key": "hidden", "label": "Hidden", "type": "bool", "tooltip": "Players cannot see it"},
			{"key": "vision", "label": "Sees", "type": "bool", "tooltip": "Off: a marker, which sees nothing. How far a token sees is the scene's light and the walls' to say"},
			{"key": "dark_radius", "label": "Sees in the dark", "type": "float", "min": 0, "max": 60, "step": 0.5, "suffix": " hex", "tooltip": "Darkvision: how far it sees unlit space (0: needs light)"},
			{"key": "art", "label": "Art", "type": "string", "tooltip": "pack:token from a pack's tokens, or blank for a plain disc"},
			{"key": "tags", "label": "Tags", "type": "string", "tooltip": "Comma-separated, shown on the token"},
		], {
			"name": tk.get("name", ""), "label": tk.get("label", ""), "color": tk.get("color", "#c0392b"), "size": tk.get("size", 1),
			"owner": _player_name(tk.get("owner", null)), "hidden": tk.get("hidden", false),
			"vision": Vision.eyes(tk, _grid()).sees, "dark_radius": snappedf(float(Vision.eyes(tk, _grid()).dark), 0.1), "art": tk.get("art", ""), "tags": ", ".join(PackedStringArray(tk.get("tags", []))),
		})
		_hint.text = "Drag on the map to move. H hides or reveals; Delete removes."
		return
	var el := ctx.selected_element()
	if el.is_empty():
		_title.text = "Nothing selected"
		_form.build([])
		return
	var coll: String = _current.collection
	var kind: String = {"walls": "Door", "lights": "Light", "props": "Prop", "notes": "Note"}.get(coll, coll)
	_title.text = "%s: %s" % [kind, str(el.get("name", el.get("title", el.get("asset", el.get("id", "")))))]
	var schema := []
	var values := {}
	if coll == "walls" and str(el.get("door", "none")) != "none":
		schema.append({"key": "state", "label": "Door", "type": "enum", "options": STATES})
		values["state"] = str(el.get("state", "closed"))
	if coll == "lights":
		schema.append({"key": "on", "label": "Lit", "type": "bool"})
		values["on"] = bool(el.get("on", true))
	if coll == "notes":
		schema.append({"key": "revealed", "label": "Players see it", "type": "bool"})
		values["revealed"] = not bool(el.get("gm_only", false))
	else:
		schema.append({"key": "revealed", "label": "Players see it", "type": "bool", "tooltip": "GM-only elements are hidden from players until revealed"})
		values["revealed"] = not bool(el.get("hidden", false))
	_form.build(schema, values)
	if coll == "notes":
		_hint.text = str(el.get("text", ""))
	else:
		_hint.text = "Changes here are this encounter's; the map stays as drawn."
	var ref := LayerTree.ref(coll, str(el.id))
	if not ctx.state.override_of(ctx.scene_id, ref).is_empty():
		var reset := Button.new()
		reset.text = "As drawn"
		reset.tooltip_text = "Drop this encounter's changes to it"
		reset.pressed.connect(func() -> void: ctx.commands.reset_element(ctx.scene_id, ref))
		_buttons.add_child(reset)


func _on_value(key: String, value: Variant) -> void:
	if _current.is_empty():
		return
	_suspend = true
	if _current.kind == "token":
		var id: String = _current.id
		match key:
			"owner":
				var pid = _player_id(str(value))
				ctx.commands.update_token(ctx.scene_id, id, {"owner": pid}, "Assign token")
			"vision", "dark_radius":
				var tk := ctx.state.token(ctx.scene_id, id)
				var vision: Dictionary = JsonDoc.deep(tk.get("vision", {})) if tk.get("vision") is Dictionary else {}
				if key == "vision":
					vision.radius = 6 if bool(value) else 0
				else:
					# hexes here, kept in the token's own units (a ruleset's feet)
					vision.dark_radius = snappedf(float(value) / float(Vision.eyes(tk, _grid()).per), 0.01)
				ctx.commands.update_token(ctx.scene_id, id, {"vision": vision}, "Vision" if key == "vision" else "Darkvision")
			"tags":
				var tags := []
				for t in str(value).split(","):
					if t.strip_edges() != "":
						tags.append(t.strip_edges())
				ctx.commands.update_token(ctx.scene_id, id, {"tags": tags}, "Tags")
			"hidden":
				ctx.commands.update_token(ctx.scene_id, id, {"hidden": bool(value)}, "Hide" if bool(value) else "Reveal")
			_:
				ctx.commands.update_token(ctx.scene_id, id, {key: value})
		if key == "name":
			_title.text = str(value)
	else:
		var coll: String = _current.collection
		var id: String = _current.id
		match key:
			"state": ctx.commands.set_door(ctx.scene_id, id, str(value))
			"on": ctx.commands.set_light(ctx.scene_id, id, bool(value))
			"revealed":
				if coll == "notes":
					ctx.commands.run({"t": "element.set", "scene": ctx.scene_id, "ref": LayerTree.ref("notes", id), "changes": {"gm_only": not bool(value)}}, "Reveal" if bool(value) else "Hide")
				else:
					ctx.commands.set_revealed(ctx.scene_id, coll, id, bool(value))
	_suspend = false
	refresh()
