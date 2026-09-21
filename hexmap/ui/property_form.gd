class_name PropertyForm
extends GridContainer
## A two-column form built from a schema, used by the inspector and the
## export dialogs. Schema entries:
##   { key, label, type: float|int|bool|enum|color|string|text|vec2,
##     min, max, step, options: [..] (enum), suffix, tooltip }
## Emits value_changed(key, value) as the user edits; get_values() reads
## the whole form.

signal value_changed(key: String, value: Variant)

var _controls: Dictionary = {}
var _schema: Array = []
var _updating := false


func _init() -> void:
	columns = 2
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func build(schema: Array, values: Dictionary = {}) -> void:
	for c in get_children():
		c.queue_free()
	_controls.clear()
	_schema = schema
	for item in schema:
		var label := Label.new()
		label.text = str(item.get("label", item.key))
		label.tooltip_text = str(item.get("tooltip", ""))
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(label)
		var ctl := _make_control(item)
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctl.tooltip_text = str(item.get("tooltip", ""))
		add_child(ctl)
		_controls[item.key] = ctl
	set_values(values)


func _make_control(item: Dictionary) -> Control:
	var key: String = item.key
	match str(item.get("type", "string")):
		"float", "int":
			var sb := SpinBox.new()
			sb.min_value = float(item.get("min", -1e9))
			sb.max_value = float(item.get("max", 1e9))
			sb.step = float(item.get("step", 0.01 if item.type == "float" else 1))
			sb.allow_greater = not item.has("max")
			sb.allow_lesser = not item.has("min")
			sb.suffix = str(item.get("suffix", ""))
			sb.custom_arrow_step = float(item.get("arrow_step", sb.step))
			sb.select_all_on_focus = true
			sb.value_changed.connect(func(v: float) -> void: _emit(key, int(v) if item.type == "int" else v))
			return sb
		"bool":
			var cb := CheckBox.new()
			cb.toggled.connect(func(v: bool) -> void: _emit(key, v))
			return cb
		"enum":
			var ob := OptionButton.new()
			for o in item.get("options", []):
				ob.add_item(str(o))
			ob.item_selected.connect(func(i: int) -> void: _emit(key, str(item.options[i])))
			return ob
		"color":
			var pb := ColorPickerButton.new()
			pb.edit_alpha = bool(item.get("alpha", true))
			pb.custom_minimum_size.y = 26
			pb.color_changed.connect(func(c: Color) -> void: _emit(key, "#" + c.to_html(pb.edit_alpha and c.a < 1.0)))
			return pb
		"text":
			var te := TextEdit.new()
			te.custom_minimum_size.y = 80
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			te.text_changed.connect(func() -> void: _emit(key, te.text))
			return te
		"vec2":
			var box := HBoxContainer.new()
			for axis in ["x", "y"]:
				var sb := SpinBox.new()
				sb.name = axis
				sb.step = float(item.get("step", 0.01))
				sb.allow_greater = true
				sb.allow_lesser = true
				sb.min_value = -1e9
				sb.max_value = 1e9
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.select_all_on_focus = true
				sb.suffix = str(item.get("suffix", ""))
				sb.value_changed.connect(func(_v: float) -> void:
					_emit(key, [box.get_node("x").value, box.get_node("y").value]))
				box.add_child(sb)
			return box
		_:
			var le := LineEdit.new()
			le.text_submitted.connect(func(t: String) -> void: _emit(key, t))
			le.focus_exited.connect(func() -> void: _emit(key, le.text))
			return le


func _emit(key: String, value: Variant) -> void:
	if _updating:
		return
	value_changed.emit(key, value)


func set_values(values: Dictionary) -> void:
	_updating = true
	for item in _schema:
		var key: String = item.key
		if not _controls.has(key):
			continue
		var ctl: Control = _controls[key]
		var v = values.get(key, item.get("default", null))
		match str(item.get("type", "string")):
			"float", "int":
				(ctl as SpinBox).set_value_no_signal(float(v) if v != null else 0.0)
			"bool":
				(ctl as CheckBox).set_pressed_no_signal(bool(v))
			"enum":
				var ob := ctl as OptionButton
				var i: int = (item.options as Array).find(str(v))
				ob.select(maxi(i, 0))
			"color":
				(ctl as ColorPickerButton).color = Color(str(v)) if v != null else Color.WHITE
			"text":
				var te := ctl as TextEdit
				if te.text != str(v if v != null else ""):
					te.text = str(v if v != null else "")
			"vec2":
				var a: Array = v if v is Array else [0, 0]
				(ctl.get_node("x") as SpinBox).set_value_no_signal(float(a[0]))
				(ctl.get_node("y") as SpinBox).set_value_no_signal(float(a[1]))
			_:
				(ctl as LineEdit).text = str(v if v != null else "")
	_updating = false


func get_values() -> Dictionary:
	var out := {}
	for item in _schema:
		var key: String = item.key
		var ctl: Control = _controls.get(key)
		if ctl == null:
			continue
		match str(item.get("type", "string")):
			"float": out[key] = (ctl as SpinBox).value
			"int": out[key] = int((ctl as SpinBox).value)
			"bool": out[key] = (ctl as CheckBox).button_pressed
			"enum": out[key] = str(item.options[(ctl as OptionButton).selected])
			"color":
				var c := (ctl as ColorPickerButton).color
				out[key] = "#" + c.to_html(c.a < 1.0)
			"text": out[key] = (ctl as TextEdit).text
			"vec2": out[key] = [(ctl.get_node("x") as SpinBox).value, (ctl.get_node("y") as SpinBox).value]
			_: out[key] = (ctl as LineEdit).text
	return out


func control(key: String) -> Control:
	return _controls.get(key)
