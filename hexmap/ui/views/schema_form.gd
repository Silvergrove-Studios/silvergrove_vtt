class_name SchemaForm
extends VBoxContainer
## An editor generated from a JSON Schema: the homebrew editor for any
## record a plugin declared (`hm.schema.define("creature", …)`), and the
## way a plugin's settings are edited. Objects become sections, scalars
## become fields, enums menus, arrays of scalars comma lists, arrays of
## objects repeaters; `title` and `description` become labels and
## tooltips. `values()` gives the record back and `validate()` runs the
## schema over it, so the form can point at what is wrong by path.

signal changed

var schema: Dictionary = {}
var _values: Dictionary = {}
var _controls: Dictionary = {}   # path -> {ctl, node}
var _errors: Label
var _updating := false
const MAX_DEPTH := 8


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)


## Build the form for `p_schema` (an object schema) with initial values.
func build(p_schema: Dictionary, p_values: Dictionary = {}) -> void:
	schema = p_schema
	_values = JsonDoc.deep(p_values)
	_controls.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_updating = true
	_object(schema, "", _values, self, 0)
	_errors = Label.new()
	_errors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_errors.theme_type_variation = "DimLabel"
	add_child(_errors)
	_updating = false


## The record as the fields hold it.
func values() -> Dictionary:
	return JsonDoc.deep(_values)


## Run the schema; show the problems; true when clean.
func validate() -> bool:
	var errors := JsonSchema.new(schema).validate(_values)
	if errors.is_empty():
		_errors.text = ""
		return true
	var lines := PackedStringArray()
	for e in errors:
		lines.append("%s: %s" % [e.path if e.path != "" else "/", e.message])
	_errors.text = "\n".join(lines)
	return false


# ------------------------------------------------------------------- build --

func _object(s: Dictionary, path: String, holder: Dictionary, into: Control, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	var props: Dictionary = s.get("properties", {})
	var required: Array = s.get("required", [])
	var keys := props.keys()
	# required first, then the rest, both in schema order
	keys.sort_custom(func(a, b) -> bool:
		var ra := required.has(a)
		var rb := required.has(b)
		return ra and not rb if ra != rb else false)
	for key in keys:
		var k := str(key)
		var ps: Variant = props[key]
		if not (ps is Dictionary):
			continue
		var sub := (path + "/" + k) if path != "" else "/" + k
		var t := _type_of(ps)
		if t == "object":
			var section := VBoxContainer.new()
			var title := Label.new()
			title.text = str(ps.get("title", k.capitalize()))
			title.theme_type_variation = "HeaderLabel"
			title.tooltip_text = str(ps.get("description", ""))
			section.add_child(title)
			if not (holder.get(k) is Dictionary):
				holder[k] = {}
			var inner := MarginContainer.new()
			inner.add_theme_constant_override("margin_left", 12)
			var box := VBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			inner.add_child(box)
			section.add_child(inner)
			into.add_child(section)
			_object(ps, sub, holder[k], box, depth + 1)
		elif t == "array" and _type_of(ps.get("items", {})) == "object":
			into.add_child(_repeater(ps, sub, holder, k, depth))
		else:
			into.add_child(_field(ps, sub, holder, k, required.has(k)))


static func _type_of(s: Dictionary) -> String:
	var t: Variant = s.get("type", "string")
	if t is Array:
		for one in t:
			if str(one) != "null":
				return str(one)
		return "string"
	return str(t)


func _field(s: Dictionary, path: String, holder: Dictionary, key: String, required: bool) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = str(s.get("title", key.capitalize())) + ("*" if required else "")
	label.tooltip_text = str(s.get("description", ""))
	label.custom_minimum_size.x = 110
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)
	var ctl: Control
	var t := _type_of(s)
	var v: Variant = holder.get(key, s.get("default"))
	if s.has("enum"):
		var ob := OptionButton.new()
		var i := 0
		for o in s.enum:
			ob.add_item(str(o))
			if v != null and JsonSchema._json_equal(o, v):
				ob.select(i)
			i += 1
		if v == null and not (s.enum as Array).is_empty():
			ob.select(0)
			holder[key] = s.enum[0]
		ob.item_selected.connect(func(idx: int) -> void: _put(holder, key, s.enum[idx]))
		ctl = ob
	else:
		match t:
			"boolean":
				var cb := CheckBox.new()
				cb.button_pressed = bool(v) if v != null else false
				cb.toggled.connect(func(on: bool) -> void: _put(holder, key, on))
				ctl = cb
			"integer", "number":
				var sb := SpinBox.new()
				sb.min_value = float(s.get("minimum", -1e9))
				sb.max_value = float(s.get("maximum", 1e9))
				sb.step = 1.0 if t == "integer" else float(s.get("multipleOf", 0.1))
				sb.allow_greater = not s.has("maximum")
				sb.allow_lesser = not s.has("minimum")
				sb.value = float(v) if v != null else float(s.get("minimum", 0))
				sb.select_all_on_focus = true
				sb.value_changed.connect(func(x: float) -> void: _put(holder, key, int(x) if t == "integer" else x))
				ctl = sb
			"array":
				var le := LineEdit.new()
				le.placeholder_text = "a, b, c"
				le.tooltip_text = "Comma-separated"
				if v is Array:
					le.text = ", ".join(PackedStringArray(v.map(func(x): return str(x))))
				var items: Dictionary = s.get("items", {}) if s.get("items") is Dictionary else {}
				var numeric := _type_of(items) in ["integer", "number"]
				var commit := func() -> void:
					var out := []
					for part in le.text.split(",", false):
						var p := part.strip_edges()
						if p == "":
							continue
						out.append((int(p) if _type_of(items) == "integer" else float(p)) if numeric and p.is_valid_float() else p)
					_put(holder, key, out)
				le.text_submitted.connect(func(_t: String) -> void: commit.call())
				le.focus_exited.connect(commit)
				ctl = le
			_:
				if s.has("maxLength") and int(s.maxLength) > 200 or str(s.get("format", "")) == "text":
					var te := TextEdit.new()
					te.custom_minimum_size.y = 70
					te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
					te.text = str(v) if v != null else ""
					te.text_changed.connect(func() -> void: _put(holder, key, te.text))
					ctl = te
				else:
					var le := LineEdit.new()
					le.text = str(v) if v != null else ""
					le.text_submitted.connect(func(x: String) -> void: _put(holder, key, x))
					le.focus_exited.connect(func() -> void: _put(holder, key, le.text))
					ctl = le
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.tooltip_text = str(s.get("description", ""))
	row.add_child(ctl)
	_controls[path] = {"ctl": ctl, "schema": s}
	return row


## A list of objects: one sub-form per item, add and remove.
func _repeater(s: Dictionary, path: String, holder: Dictionary, key: String, depth: int) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = str(s.get("title", key.capitalize()))
	title.theme_type_variation = "HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var add := Button.new()
	add.text = "+"
	add.theme_type_variation = "ToolButton"
	head.add_child(add)
	box.add_child(head)
	if not (holder.get(key) is Array):
		holder[key] = []
	var list: Array = holder[key]
	var items_schema: Dictionary = s.get("items", {})
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(rows)
	var rebuild := func() -> void:
		for c in rows.get_children():
			rows.remove_child(c)
			c.queue_free()
		for i in list.size():
			if not (list[i] is Dictionary):
				list[i] = {}
			var item_row := HBoxContainer.new()
			var inner := VBoxContainer.new()
			inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_object(items_schema, "%s/%d" % [path, i], list[i], inner, depth + 1)
			item_row.add_child(inner)
			var rm := Button.new()
			rm.text = "−"
			rm.theme_type_variation = "ToolButton"
			rm.pressed.connect(func() -> void:
				list.remove_at(i)
				_changed()
				build(schema, _values))
			item_row.add_child(rm)
			rows.add_child(item_row)
	add.pressed.connect(func() -> void:
		list.append({})
		_changed()
		build(schema, _values))
	rebuild.call()
	return box


func _put(holder: Dictionary, key: String, value: Variant) -> void:
	if _updating:
		return
	holder[key] = value
	_changed()


func _changed() -> void:
	if not _updating:
		changed.emit()


## The control for a field path ("/stats/agi"), for tests.
func control(path: String) -> Control:
	return _controls.get(path, {}).get("ctl")
