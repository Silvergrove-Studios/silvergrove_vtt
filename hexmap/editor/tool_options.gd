class_name ToolOptions
extends HBoxContainer
## The strip under the toolbar: options for the active tool (brush size,
## variant, snapping, wall type, light radii...). Reads and writes the
## EditorContext; `sync()` pulls values back after keyboard changes.

var ctx: EditorContext
var _tool := ""
var _controls: Dictionary = {}
var _syncing := false


func _init(p_ctx: EditorContext) -> void:
	ctx = p_ctx
	add_theme_constant_override("separation", 8)
	custom_minimum_size.y = 30


func show_for(tool_name: String) -> void:
	_tool = tool_name
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_controls.clear()
	match tool_name:
		"terrain", "fill":
			_variant()
			if tool_name == "terrain":
				_spin("brush", "Brush", 0, 6, 1, ctx.brush_radius, func(v: float) -> void: ctx.brush_radius = int(v), " hex")
		"prop":
			_snap()
			_spin("rot", "Rotation", -360, 360, 1, ctx.prop_rotation, func(v: float) -> void: ctx.prop_rotation = fposmod(v, 360.0), "°")
			_spin("scale", "Scale", 0.05, 20, 0.05, ctx.prop_scale, func(v: float) -> void: ctx.prop_scale = v)
			_check("flip", "Flip", ctx.prop_flip, func(v: bool) -> void: ctx.prop_flip = v)
		"select":
			_snap()
		"wall":
			var ob := OptionButton.new()
			for k in EditorContext.WALL_PRESETS.keys():
				ob.add_item(str(k).capitalize())
				ob.set_item_metadata(ob.item_count - 1, k)
				if k == ctx.wall_preset:
					ob.select(ob.item_count - 1)
			ob.item_selected.connect(func(i: int) -> void: ctx.wall_preset = str(ob.get_item_metadata(i)))
			_labelled("Type", ob, "type")
			_check("snap_walls", "Snap to hex corners", ctx.snap_walls, func(v: bool) -> void: ctx.snap_walls = v)
		"light":
			_spin("bright", "Bright", 0, 50, 0.25, float(ctx.light_preset.get("bright", 1.0)), func(v: float) -> void: ctx.light_preset["bright"] = v, " hex")
			_spin("dim", "Dim", 0, 50, 0.25, float(ctx.light_preset.get("dim", 2.0)), func(v: float) -> void: ctx.light_preset["dim"] = v, " hex")
			var pb := ColorPickerButton.new()
			pb.edit_alpha = false
			pb.color = Color(str(ctx.light_preset.get("color", "#ffb060")))
			pb.custom_minimum_size = Vector2(44, 24)
			pb.color_changed.connect(func(c: Color) -> void: ctx.light_preset["color"] = "#" + c.to_html(false))
			_labelled("Colour", pb, "color")
		"note":
			_hint("Click to place a GM note; edit its text in the Inspector.")
		"erase":
			_hint("Click an object to delete it, or a cell to clear its terrain.")


func _labelled(text: String, control: Control, key: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "DimLabel"
	add_child(l)
	add_child(control)
	_controls[key] = control


func _spin(key: String, label: String, lo: float, hi: float, step: float, value: float, on_change: Callable, suffix := "") -> void:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.suffix = suffix
	sb.custom_minimum_size.x = 90
	sb.set_value_no_signal(value)
	sb.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			on_change.call(v))
	_labelled(label, sb, key)


func _check(key: String, label: String, value: bool, on_change: Callable) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.set_pressed_no_signal(value)
	cb.toggled.connect(func(v: bool) -> void:
		if not _syncing:
			on_change.call(v))
	add_child(cb)
	_controls[key] = cb


func _snap() -> void:
	var ob := OptionButton.new()
	for o in ["Snap off", "Snap to hex centre", "Snap to hex corner"]:
		ob.add_item(o)
	ob.select(ctx.snap)
	ob.item_selected.connect(func(i: int) -> void: ctx.snap = i as EditorContext.Snap)
	add_child(ob)
	_controls["snap"] = ob


func _variant() -> void:
	var ob := OptionButton.new()
	_fill_variants(ob)
	ob.item_selected.connect(func(i: int) -> void: ctx.terrain_variant = i - 1)
	_labelled("Variant", ob, "variant")


func _fill_variants(ob: OptionButton) -> void:
	ob.clear()
	ob.add_item("Random")
	var def := ctx.packs.terrain(ctx.terrain_ref)
	for v in (def.get("textures", []) as Array).size():
		ob.add_item("Variant %d" % (v + 1))
	ob.select(clampi(ctx.terrain_variant + 1, 0, ob.item_count - 1))


func _hint(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "DimLabel"
	add_child(l)


## Pull current context values into the controls (after key shortcuts or a
## palette pick changed them).
func sync() -> void:
	_syncing = true
	if _controls.has("brush"):
		(_controls.brush as SpinBox).set_value_no_signal(ctx.brush_radius)
	if _controls.has("rot"):
		(_controls.rot as SpinBox).set_value_no_signal(ctx.prop_rotation)
	if _controls.has("scale"):
		(_controls.scale as SpinBox).set_value_no_signal(ctx.prop_scale)
	if _controls.has("flip"):
		(_controls.flip as CheckBox).set_pressed_no_signal(ctx.prop_flip)
	if _controls.has("snap"):
		(_controls.snap as OptionButton).select(ctx.snap)
	if _controls.has("variant"):
		_fill_variants(_controls.variant as OptionButton)
	if _controls.has("bright"):
		(_controls.bright as SpinBox).set_value_no_signal(float(ctx.light_preset.get("bright", 1.0)))
	if _controls.has("dim"):
		(_controls.dim as SpinBox).set_value_no_signal(float(ctx.light_preset.get("dim", 2.0)))
	if _controls.has("color"):
		(_controls.color as ColorPickerButton).color = Color(str(ctx.light_preset.get("color", "#ffb060")))
	if _controls.has("type"):
		var ob := _controls.type as OptionButton
		for i in ob.item_count:
			if str(ob.get_item_metadata(i)) == ctx.wall_preset:
				ob.select(i)
	_syncing = false


func tool_name() -> String:
	return _tool
