class_name Palette
extends TabContainer
## The left dock: what to paint or place. Picking something sets it on the
## EditorContext and asks Main (via `picked`) to switch to the matching tool.

signal picked(kind: String)

var ctx: EditorContext
var _lists: Dictionary = {}       # kind -> ItemList
var _filters: Dictionary = {}     # kind -> LineEdit
var _variant: OptionButton
var _brush: SpinBox
var _snap: OptionButton
var _wall_preset: OptionButton
var _wall_snap: CheckBox
var _refreshing := false

const ICON := 56


func _init(p_ctx: EditorContext) -> void:
	ctx = p_ctx
	custom_minimum_size.x = 300
	size_flags_horizontal = Control.SIZE_FILL
	_build_tab("terrain", "Terrain")
	_build_tab("props", "Props")
	_build_tab("walls", "Walls")
	_build_tab("lights", "Lights")
	ctx.packs.loaded.connect(refresh)


func _build_tab(kind: String, title: String) -> void:
	var box := VBoxContainer.new()
	box.name = title
	add_child(box)
	var filter := LineEdit.new()
	filter.placeholder_text = "Filter…"
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(_t: String) -> void: _fill(kind))
	box.add_child(filter)
	_filters[kind] = filter
	match kind:
		"terrain":
			var row := HBoxContainer.new()
			row.add_child(_label("Variant"))
			_variant = OptionButton.new()
			_variant.add_item("Random")
			_variant.item_selected.connect(func(i: int) -> void: ctx.terrain_variant = i - 1)
			_variant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(_variant)
			row.add_child(_label("Brush"))
			_brush = SpinBox.new()
			_brush.min_value = 0
			_brush.max_value = 6
			_brush.value_changed.connect(func(v: float) -> void: ctx.brush_radius = int(v))
			row.add_child(_brush)
			box.add_child(row)
		"props":
			var row := HBoxContainer.new()
			row.add_child(_label("Snap"))
			_snap = OptionButton.new()
			for o in ["Off", "Hex centre", "Hex corner"]:
				_snap.add_item(o)
			_snap.select(ctx.snap)
			_snap.item_selected.connect(func(i: int) -> void: ctx.snap = i as EditorContext.Snap)
			_snap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(_snap)
			box.add_child(row)
			var hint := Label.new()
			hint.text = "R rotate · F flip · [ ] scale · Shift: free placement"
			hint.add_theme_font_size_override("font_size", 11)
			hint.modulate = Color(1, 1, 1, 0.6)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(hint)
		"walls":
			var row := HBoxContainer.new()
			row.add_child(_label("Type"))
			_wall_preset = OptionButton.new()
			for k in EditorContext.WALL_PRESETS.keys():
				_wall_preset.add_item(k.capitalize())
				_wall_preset.set_item_metadata(_wall_preset.item_count - 1, k)
			_wall_preset.item_selected.connect(func(i: int) -> void:
				ctx.wall_preset = _wall_preset.get_item_metadata(i)
				picked.emit("walls"))
			_wall_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(_wall_preset)
			box.add_child(row)
			_wall_snap = CheckBox.new()
			_wall_snap.text = "Snap to hex corners"
			_wall_snap.button_pressed = ctx.snap_walls
			_wall_snap.toggled.connect(func(v: bool) -> void: ctx.snap_walls = v)
			box.add_child(_wall_snap)
			var hint := Label.new()
			hint.text = "Style is how the wall is drawn; type is what it blocks. Doors are two clicks."
			hint.add_theme_font_size_override("font_size", 11)
			hint.modulate = Color(1, 1, 1, 0.6)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(hint)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.max_columns = 0
	list.same_column_width = true
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.fixed_icon_size = Vector2i(ICON, ICON)
	list.fixed_column_width = ICON + 28
	list.auto_height = false
	list.item_selected.connect(func(i: int) -> void: _on_pick(kind, i))
	box.add_child(list)
	_lists[kind] = list


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func refresh() -> void:
	for kind in _lists:
		_fill(kind)


func _fill(kind: String) -> void:
	_refreshing = true
	var list: ItemList = _lists[kind]
	var filter: String = (_filters[kind] as LineEdit).text.to_lower()
	list.clear()
	var collection: String = {"terrain": "terrains", "props": "props", "walls": "walls", "lights": "lights"}[kind]
	if kind == "walls":
		list.add_item("No style")
		list.set_item_metadata(0, "")
		list.set_item_icon(0, ctx.packs.placeholder(Color(0.5, 0.5, 0.5)))
	for a in ctx.packs.all(collection):
		var label := "%s" % a.get("name", a.id)
		if filter != "" and not (label.to_lower().contains(filter) or str(a._ref).contains(filter) or _tags(a).contains(filter)):
			continue
		var i := list.add_item(label)
		list.set_item_metadata(i, a._ref)
		list.set_item_tooltip(i, "%s\n%s" % [a._ref, ", ".join(PackedStringArray(a.get("tags", [])))])
		var icon: Texture2D
		match kind:
			"terrain": icon = ctx.packs.terrain_texture(a._ref, 0, ICON)
			"props": icon = ctx.packs.prop_texture(a._ref, ICON / maxf(0.2, float(a.get("size", [1, 1])[0])))
			_: icon = ctx.packs.placeholder(Color(str(a.get("color", "#808080"))))
		list.set_item_icon(i, icon)
	_refreshing = false


static func _tags(a: Dictionary) -> String:
	return " ".join(PackedStringArray(a.get("tags", []))).to_lower()


func _on_pick(kind: String, index: int) -> void:
	if _refreshing:
		return
	var list: ItemList = _lists[kind]
	var ref := str(list.get_item_metadata(index))
	match kind:
		"terrain":
			ctx.terrain_ref = ref
			var def := ctx.packs.terrain(ref)
			var n: int = (def.get("textures", []) as Array).size()
			_variant.clear()
			_variant.add_item("Random")
			for v in n:
				_variant.add_item("Variant %d" % (v + 1))
			_variant.select(0)
			ctx.terrain_variant = -1
		"props":
			ctx.prop_ref = ref
		"walls":
			ctx.wall_style = ref
		"lights":
			ctx.light_preset = ctx.packs.light_preset(ref).duplicate()
	picked.emit(kind)


## Reflect context state that tools change with keys.
func sync() -> void:
	if _brush != null and int(_brush.value) != ctx.brush_radius:
		_brush.set_value_no_signal(ctx.brush_radius)
	if _snap != null and _snap.selected != ctx.snap:
		_snap.select(ctx.snap)
