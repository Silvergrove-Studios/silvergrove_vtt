class_name PropertyForm
extends GridContainer
## A two-column form built from a schema, used by the inspector and the
## export dialogs. Schema entries:
##   { key, label, type: float|int|bool|enum|color|string|text|vec2|list|choose|scores,
##     min, max, step, options: [..] (enum, choose), suffix, tooltip,
##     fields: [..] (list: the sub-form each item is edited with) }
## A `list` is a repeater: its value is an array of records, one sub-form
## per item with add and remove. `choose` and `scores` are the plugins'
## (docs/plugin-authoring.md): some of a list of options, as check boxes
## (or one, `single`); numbers for named stats under a method, as spin
## boxes. The web screens draw both more fully; the rules check either.
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
		"choose":
			var ch := ChooseField.new(item)
			ch.changed.connect(func() -> void: _emit(key, ch.get_value()))
			return ch
		"scores":
			var sc := ScoresField.new(item)
			sc.changed.connect(func() -> void: _emit(key, sc.get_value()))
			return sc
		"list":
			var rep := ListField.new()
			rep.fields = item.get("fields", []) if item.get("fields") is Array else []
			rep.add_label = str(item.get("add_label", "Add"))
			rep.changed.connect(func() -> void: _emit(key, rep.get_values()))
			return rep
		"bool":
			var cb := CheckBox.new()
			cb.toggled.connect(func(v: bool) -> void: _emit(key, v))
			return cb
		"enum":
			var ob := OptionButton.new()
			# options are plain strings, or {id, name} records: the id is the value
			for o in item.get("options", []):
				ob.add_item(str(o.get("name", o.get("id", ""))) if o is Dictionary else str(o))
			ob.item_selected.connect(func(i: int) -> void: _emit(key, _option_value(item, i)))
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
				(ctl as CheckBox).set_pressed_no_signal(v == true or (v is String and str(v) == "true"))
			"enum":
				var ob := ctl as OptionButton
				var i := -1
				for n in (item.get("options", []) as Array).size():
					if _option_value(item, n) == str(v):
						i = n
				# (a field whose choices are still on their way has none yet)
				if ob.item_count > 0:
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
			"list":
				(ctl as ListField).set_values(v if v is Array else [])
			"choose":
				(ctl as ChooseField).set_value(v)
			"scores":
				(ctl as ScoresField).set_value(v)
			_:
				(ctl as LineEdit).text = str(v if v != null else "")
	_updating = false


## The value an enum option stands for: a record's `id`, or the string itself.
static func _option_value(item: Dictionary, i: int) -> String:
	var options: Array = item.get("options", [])
	if i < 0 or i >= options.size():
		return ""
	var o: Variant = options[i]
	return str((o as Dictionary).get("id", o.get("name", ""))) if o is Dictionary else str(o)


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
			"enum": out[key] = _option_value(item, (ctl as OptionButton).selected)
			"color":
				var c := (ctl as ColorPickerButton).color
				out[key] = "#" + c.to_html(c.a < 1.0)
			"text": out[key] = (ctl as TextEdit).text
			"vec2": out[key] = [(ctl.get_node("x") as SpinBox).value, (ctl.get_node("y") as SpinBox).value]
			"list": out[key] = (ctl as ListField).get_values()
			"choose": out[key] = (ctl as ChooseField).get_value()
			"scores": out[key] = (ctl as ScoresField).get_value()
			_: out[key] = (ctl as LineEdit).text
	return out


func control(key: String) -> Control:
	return _controls.get(key)


## The repeater behind a `list` field: one PropertyForm per item, add
## and remove buttons, values as an array of records.
class ListField extends VBoxContainer:
	signal changed
	var fields: Array = []
	var add_label := "Add"
	var _rows: Array = []

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 4)
		var add := Button.new()
		add.text = add_label
		add.pressed.connect(func() -> void:
			_add_row({})
			changed.emit())
		add.name = "add"
		add_child(add)

	func _ready() -> void:
		(get_node("add") as Button).text = add_label

	func _add_row(values: Dictionary) -> void:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pf := PropertyForm.new()
		pf.build(fields, values)
		pf.value_changed.connect(func(_k: String, _v: Variant) -> void: changed.emit())
		row.add_child(pf)
		var rm := Button.new()
		rm.text = "−"
		rm.tooltip_text = "Remove"
		rm.pressed.connect(func() -> void:
			_rows.erase(row)
			remove_child(row)
			row.queue_free()
			changed.emit())
		row.add_child(rm)
		add_child(row)
		move_child(get_node("add"), get_child_count() - 1)
		_rows.append(row)

	func set_values(values: Array) -> void:
		for r in _rows:
			remove_child(r)
			r.queue_free()
		_rows.clear()
		for v in values:
			_add_row(v if v is Dictionary else {})

	func get_values() -> Array:
		var out := []
		for r in _rows:
			out.append((r.get_child(0) as PropertyForm).get_values())
		return out

	func count() -> int:
		return _rows.size()


## Some of a list of options ({id, name, text, tag} records or strings):
## check boxes, as many as `count` (or `max`) allows, those `fixed` ticked
## and locked, those `allowed` leaves out not shown; `single`, a list to
## pick one from. Its value: the ids (or the one id).
class ChooseField extends VBoxContainer:
	signal changed
	var item: Dictionary
	var _boxes: Dictionary = {}
	var _pick: OptionButton
	var _ids: Array = []

	func _init(p_item: Dictionary) -> void:
		item = p_item
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var allowed: Variant = item.get("allowed")
		var fixed: Array = item.get("fixed", []) if item.get("fixed") is Array else []
		if bool(item.get("single", false)):
			_pick = OptionButton.new()
			_pick.add_item("Choose…")
			_ids.append("")
		for o in item.get("options", []):
			var id := str(o.get("id", o.get("name", ""))) if o is Dictionary else str(o)
			if allowed is Array and not (allowed as Array).has(id) and not fixed.has(id):
				continue
			var label := str(o.get("name", id)) if o is Dictionary else id
			if o is Dictionary and str(o.get("tag", "")) != "":
				label += "  (%s)" % str(o.tag)
			if _pick != null:
				_pick.add_item(label)
				_ids.append(id)
				continue
			var cb := CheckBox.new()
			cb.text = label
			cb.tooltip_text = str(o.get("text", "")) if o is Dictionary else ""
			if fixed.has(id):
				cb.button_pressed = true
				cb.disabled = true
				cb.text += "  — " + str(item.get("fixed_label", "yours already"))
			else:
				cb.toggled.connect(func(_on: bool) -> void:
					_limit()
					changed.emit())
			_boxes[id] = cb
			add_child(cb)
		if _pick != null:
			_pick.item_selected.connect(func(_i: int) -> void: changed.emit())
			add_child(_pick)

	func _most() -> int:
		if item.has("count") and item.count != null:
			return int(item.count)
		return int(item.get("max", 1 << 30)) if item.get("max") != null else 1 << 30

	func _limit() -> void:
		var fixed: Array = item.get("fixed", []) if item.get("fixed") is Array else []
		var full: bool = (get_value() as Array).size() >= _most()
		for id in _boxes:
			var cb: CheckBox = _boxes[id]
			if not fixed.has(id):
				cb.disabled = full and not cb.button_pressed

	func set_value(v: Variant) -> void:
		if _pick != null:
			_pick.select(maxi(0, _ids.find(str(v if v != null else ""))))
			return
		var fixed: Array = item.get("fixed", []) if item.get("fixed") is Array else []
		var want: Array = v if v is Array else []
		for id in _boxes:
			if not fixed.has(id):
				(_boxes[id] as CheckBox).set_pressed_no_signal(want.has(id))
		_limit()

	func get_value() -> Variant:
		if _pick != null:
			return _ids[_pick.selected] if _pick.selected >= 0 and _pick.selected < _ids.size() else ""
		var fixed: Array = item.get("fixed", []) if item.get("fixed") is Array else []
		var out := []
		for id in _boxes:
			if not fixed.has(id) and (_boxes[id] as CheckBox).button_pressed:
				out.append(id)
		return out


## Numbers for named stats (`stats`: {id, name, text}) under a `method`:
## a point buy (spin boxes from its minimum to its maximum, the points
## left said), a fixed array or rolled numbers (each used once, said), or
## typed (`manual`). A background's bonus goes where the class wants it
## (+2 on its key ability when offered, +1 on the next). Its value:
## {method, base, bonus, final}.
class ScoresField extends VBoxContainer:
	signal changed
	var item: Dictionary
	var _spins: Dictionary = {}
	var _finals: Dictionary = {}
	var _note: Label
	# a bonus given with the value (the answers so far): kept, not worked out again
	var _given_bonus: Dictionary = {}

	func _init(p_item: Dictionary) -> void:
		item = p_item
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_note = Label.new()
		_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_note.theme_type_variation = "DimLabel"
		add_child(_note)
		var grid := GridContainer.new()
		grid.columns = 3
		add_child(grid)
		var lo := 1
		var hi := 30
		var m := str(item.get("method", "manual"))
		if m == "point_buy":
			var pb: Dictionary = item.get("point_buy", {}) if item.get("point_buy") is Dictionary else {}
			lo = int(pb.get("min", 8))
			hi = int(pb.get("max", 15))
		elif _pool().size() > 0:
			lo = int(_pool().min())
			hi = int(_pool().max())
		elif m == "manual" and item.get("manual") is Dictionary:
			lo = int(item.manual.get("min", 1))
			hi = int(item.manual.get("max", 30))
		for st in item.get("stats", []):
			if not (st is Dictionary) or str(st.get("id", "")) == "":
				continue
			var name := Label.new()
			name.text = str(st.get("name", st.id))
			name.tooltip_text = str(st.get("text", ""))
			name.mouse_filter = Control.MOUSE_FILTER_STOP
			grid.add_child(name)
			var sb := SpinBox.new()
			sb.min_value = lo
			sb.max_value = hi
			sb.step = 1
			sb.value_changed.connect(func(_v: float) -> void:
				_refresh()
				changed.emit())
			grid.add_child(sb)
			_spins[str(st.id)] = sb
			var fin := Label.new()
			grid.add_child(fin)
			_finals[str(st.id)] = fin
		set_value(null)

	func _pool() -> Array:
		var m := str(item.get("method", ""))
		if m == "array":
			return item.get("array", []) if item.get("array") is Array else []
		if m == "rolled" and item.get("rolled") is Dictionary and item.rolled.get("values") is Array:
			return item.rolled.values
		return []

	func _cost(score: int) -> int:
		var pb: Dictionary = item.get("point_buy", {}) if item.get("point_buy") is Dictionary else {}
		var cost: Dictionary = pb.get("cost", {}) if pb.get("cost") is Dictionary else {"8": 0, "9": 1, "10": 2, "11": 3, "12": 4, "13": 5, "14": 7, "15": 9}
		return int(cost.get(str(score), 99))

	func _bonus() -> Dictionary:
		var b: Variant = item.get("bonus")
		if not (b is Dictionary) or not (b.get("among") is Array) or (b.among as Array).size() < 2:
			return {}
		var among: Array = b.among
		var primary: Array = item.get("primary", []) if item.get("primary") is Array else []
		var two := ""
		for p in primary:
			if among.has(p) and two == "":
				two = str(p)
		if two == "":
			two = str(among[0])
		var one := ""
		for p in primary + among:
			if str(p) != two and among.has(p) and one == "":
				one = str(p)
		return {two: 2, one: 1}

	func set_value(v: Variant) -> void:
		var base: Dictionary = v.get("base", {}) if v is Dictionary and v.get("base") is Dictionary else {}
		_given_bonus = (v.bonus as Dictionary).duplicate() if v is Dictionary and v.get("bonus") is Dictionary else {}
		var sug: Dictionary = item.get("suggest", {}) if item.get("suggest") is Dictionary else {}
		var pool := _pool().duplicate()
		pool.sort()
		pool.reverse()
		var i := 0
		for id in _spins:
			var sb: SpinBox = _spins[id]
			var start: Variant = base.get(id, sug.get(id, pool[i] if i < pool.size() else (sb.min_value if str(item.get("method", "")) == "point_buy" else 10)))
			sb.set_value_no_signal(float(start))
			i += 1
		_refresh()

	func _refresh() -> void:
		var fin: Dictionary = get_value().final
		for id in _finals:
			var f := int(fin.get(id, 10))
			(_finals[id] as Label).text = "→ %d (%s%d)" % [f, "+" if f >= 10 else "", floori((f - 10) / 2.0)]
		match str(item.get("method", "manual")):
			"point_buy":
				var pb: Dictionary = item.get("point_buy", {}) if item.get("point_buy") is Dictionary else {}
				var spent := 0
				for id in _spins:
					spent += _cost(int((_spins[id] as SpinBox).value))
				_note.text = "Point buy: %d of %d points spent." % [spent, int(pb.get("budget", 27))]
			"array", "rolled":
				var pool := _pool()
				_note.text = ("Use each of %s once." % ", ".join(pool.map(func(x: Variant) -> String: return str(int(x))))) if not pool.is_empty() else "Roll the scores first (on the player's screen)."
			_:
				_note.text = "Type each score."

	func get_value() -> Dictionary:
		var base := {}
		for id in _spins:
			base[id] = int((_spins[id] as SpinBox).value)
		var bonus := _given_bonus if not _given_bonus.is_empty() else _bonus()
		var cap := int((item.bonus as Dictionary).get("cap", 20)) if item.get("bonus") is Dictionary else 20
		var final := {}
		for id in base:
			final[id] = mini(cap, int(base[id]) + int(bonus.get(id, 0))) if int(bonus.get(id, 0)) > 0 else int(base[id])
		return {"method": str(item.get("method", "manual")), "base": base, "bonus": bonus, "final": final}
