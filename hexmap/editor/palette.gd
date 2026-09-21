class_name Palette
extends VBoxContainer
## The asset picker: one search across every tab, assets grouped under
## collapsible pack headers with Favourites and Recent on top, big tiles
## with a hover preview. Picking sets the EditorContext and asks Main (via
## `picked`) for the matching tool. Tool options live in ToolOptions, not
## here. Data logic is in PaletteModel; favourites/recents persist per user.

signal picked(kind: String)

var ctx: EditorContext
var search: LineEdit
var tabs: TabContainer
var state: Dictionary = PaletteModel.default_state()
var _lists: Dictionary = {}       # kind -> VBoxContainer of sections
var _tiles: Dictionary = {}       # kind -> {ref: Button}
var _groups: Dictionary = {}      # kind -> ButtonGroup
var _tokens: Dictionary = ThemeBuilder.tokens("slate")
var _preview: PopupPanel
var _preview_timer := Timer.new()
var _preview_for := ""
var _refreshing := false

const TILE := Vector2(92, 100)
const ICON := 60
const TAB_TITLES := {"terrain": "Terrain", "props": "Props", "walls": "Walls", "lights": "Lights"}


func _init(p_ctx: EditorContext) -> void:
	ctx = p_ctx
	state = PaletteModel.load_state()
	custom_minimum_size.x = 300
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	search = LineEdit.new()
	search.placeholder_text = "Search all packs…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t: String) -> void: refresh())
	add_child(search)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	for kind in PaletteModel.KINDS:
		var scroll := ScrollContainer.new()
		scroll.name = TAB_TITLES[kind]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 2)
		scroll.add_child(box)
		tabs.add_child(scroll)
		_lists[kind] = box
		_tiles[kind] = {}
		_groups[kind] = ButtonGroup.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.35
	_preview_timer.timeout.connect(_show_preview)
	add_child(_preview_timer)
	_preview = PopupPanel.new()
	_preview.theme_type_variation = "PopupPanel"
	add_child(_preview)
	ctx.packs.loaded.connect(refresh)


func restyle(t: Dictionary) -> void:
	_tokens = t
	search.right_icon = UiIcons.get_icon("search", t.icon - 4, ThemeBuilder.c(t, "text_dim"), t.stroke)
	refresh()


## Show the tab that matches a tool.
func show_tab_for_tool(tool_name: String) -> void:
	var kind: String = {"terrain": "terrain", "fill": "terrain", "prop": "props", "wall": "walls", "light": "lights"}.get(tool_name, "")
	if kind != "":
		tabs.current_tab = PaletteModel.KINDS.find(kind)


# --------------------------------------------------------------------- build --

func refresh() -> void:
	_refreshing = true
	var q := search.text
	for kind in PaletteModel.KINDS:
		var assets := _assets(kind)
		var box: VBoxContainer = _lists[kind]
		for c in box.get_children():
			c.queue_free()
		_tiles[kind].clear()
		var pack_names := {}
		for pid in ctx.packs.pack_ids():
			pack_names[pid] = ctx.packs.packs[pid].get("name", pid)
		var secs := PaletteModel.sections(assets, q, state.favorites[kind], state.recent[kind], pack_names)
		if kind == "walls" and q == "":
			secs.insert(0, {"id": "none", "title": "Plain", "items": [{"_ref": "", "_pack": "", "name": "No style", "color": "#808080", "tags": []}]})
		for sec in secs:
			box.add_child(_section(kind, sec))
		var idx := PaletteModel.KINDS.find(kind)
		var title: String = TAB_TITLES[kind]
		if q != "":
			title += " (%d)" % PaletteModel.count(assets, q)
		tabs.set_tab_title(idx, title)
		if secs.is_empty():
			var empty := Label.new()
			empty.text = "Nothing matches “%s”." % q if q != "" else "No packs loaded."
			empty.theme_type_variation = "DimLabel"
			box.add_child(empty)
	_refreshing = false
	_sync_pressed()
	# Searching from a tab with no matches jumps to the first tab that has some.
	if q != "" and PaletteModel.count(_assets(PaletteModel.KINDS[tabs.current_tab]), q) == 0:
		for i in PaletteModel.KINDS.size():
			if PaletteModel.count(_assets(PaletteModel.KINDS[i]), q) > 0:
				tabs.current_tab = i
				break


func _assets(kind: String) -> Array:
	var out := ctx.packs.all(PaletteModel.COLLECTION[kind])
	for a in out:
		a["_pack_name"] = str(ctx.packs.packs.get(a._pack, {}).get("name", a._pack))
	return out


func _section(kind: String, sec: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var key := "%s/%s" % [kind, sec.id]
	var collapsed := bool(state.collapsed.get(key, false))
	var head := Button.new()
	head.theme_type_variation = "ToolButton"
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text = "%s  ·  %d" % [sec.title, (sec.items as Array).size()]
	head.icon = UiIcons.get_icon("chevron-right" if collapsed else "chevron-down", _tokens.icon - 4, ThemeBuilder.c(_tokens, "text_dim"), _tokens.stroke)
	head.focus_mode = Control.FOCUS_NONE
	box.add_child(head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	flow.visible = not collapsed
	for a in sec.items:
		flow.add_child(_tile(kind, a))
	box.add_child(flow)
	head.pressed.connect(func() -> void:
		flow.visible = not flow.visible
		state.collapsed[key] = not flow.visible
		head.icon = UiIcons.get_icon("chevron-down" if flow.visible else "chevron-right", _tokens.icon - 4, ThemeBuilder.c(_tokens, "text_dim"), _tokens.stroke)
		_save())
	return box


func _tile(kind: String, a: Dictionary) -> Button:
	var ref := str(a._ref)
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _groups[kind]
	b.custom_minimum_size = TILE
	b.text = str(a.get("name", a.get("id", ref)))
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", ICON)
	b.add_theme_font_size_override("font_size", int(_tokens.font_size) - 2)
	b.icon = _icon(kind, a, ICON)
	b.focus_mode = Control.FOCUS_NONE
	var fav: bool = (state.favorites[kind] as Array).has(ref)
	b.tooltip_text = "%s%s\n%s\n%s\nRight-click to %s favourites" % [
		a.get("name", ""), "  ★" if fav else "", ref if ref != "" else "no wall style",
		", ".join(PackedStringArray(a.get("tags", []))), "remove from" if fav else "add to"]
	b.set_meta("ref", ref)
	b.set_meta("kind", kind)
	b.pressed.connect(func() -> void: _on_pick(kind, ref))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and ref != "":
			state.favorites[kind] = PaletteModel.toggle(state.favorites[kind], ref)
			_save()
			refresh())
	b.mouse_entered.connect(func() -> void:
		_preview_for = "%s|%s" % [kind, ref]
		_preview_timer.start())
	b.mouse_exited.connect(func() -> void:
		_preview_timer.stop()
		if _preview.visible:
			_preview.hide())
	if fav:
		b.add_theme_color_override("font_color", ThemeBuilder.c(_tokens, "accent"))
	_tiles[kind][ref] = b
	return b


func _icon(kind: String, a: Dictionary, px: int) -> Texture2D:
	var ref := str(a._ref)
	match kind:
		"terrain": return ctx.packs.terrain_texture(ref, 0, px, _shape())
		"props": return ctx.packs.prop_texture(ref, px / maxf(0.2, float(a.get("size", [1, 1])[0])))
		_: return ctx.packs.placeholder(Color(str(a.get("color", "#808080"))))


## Reflect the context's current picks as pressed tiles.
func _sync_pressed() -> void:
	var current := {"terrain": ctx.terrain_ref, "props": ctx.prop_ref, "walls": ctx.wall_style, "lights": str(ctx.light_preset.get("_ref", ""))}
	for kind in PaletteModel.KINDS:
		for ref in _tiles[kind]:
			(_tiles[kind][ref] as Button).set_pressed_no_signal(ref == current[kind])


# ---------------------------------------------------------------------- picks --

func _on_pick(kind: String, ref: String) -> void:
	if _refreshing:
		return
	match kind:
		"terrain":
			ctx.terrain_ref = ref
			ctx.terrain_variant = -1
		"props":
			ctx.prop_ref = ref
		"walls":
			ctx.wall_style = ref
		"lights":
			ctx.light_preset = ctx.packs.light_preset(ref).duplicate()
			ctx.light_preset["_ref"] = ref
	if ref != "":
		state.recent[kind] = PaletteModel.push_recent(state.recent[kind], ref)
		_save()
	picked.emit(kind)
	# Rebuild so Recent updates, but keep the scroll position sane.
	refresh.call_deferred()


func _save() -> void:
	PaletteModel.save_state(state)


## Reflect context state that tools change with keys (kept for Main).
func sync() -> void:
	_sync_pressed()


# -------------------------------------------------------------------- preview --

func _show_preview() -> void:
	var parts := _preview_for.split("|")
	if parts.size() != 2 or parts[1] == "":
		return
	var kind := parts[0]
	var ref := parts[1]
	var tile: Button = _tiles[kind].get(ref)
	if tile == null or not tile.is_visible_in_tree():
		return
	for c in _preview.get_children():
		c.queue_free()
	var col: String = PaletteModel.COLLECTION[kind]
	var a := ctx.packs.asset(col, ref)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = str(a.get("name", ref))
	title.theme_type_variation = "HeaderLabel"
	box.add_child(title)
	var sub := Label.new()
	var parts_ref := PackLibrary.split_ref(ref)
	sub.text = "%s · %s" % [ctx.packs.packs.get(parts_ref[0], {}).get("name", parts_ref[0]) if parts_ref.size() == 2 else "", ref]
	sub.theme_type_variation = "DimLabel"
	box.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	match kind:
		"terrain":
			var n := ctx.packs.terrain_variants(ref, _shape())
			for v in mini(n, 4):
				row.add_child(_tex_rect(ctx.packs.terrain_texture(ref, v, 160, _shape()), 160))
		"props":
			var size: Array = a.get("size", [1, 1])
			row.add_child(_tex_rect(ctx.packs.prop_texture(ref, 200.0 / maxf(0.2, float(size[0]))), 200))
			var info := Label.new()
			info.text = "%s × %s hex\nheight %s hex\nblocks: %s" % [size[0], size[1], a.get("height", "?"),
				", ".join(PackedStringArray((a.get("blocks", {}) as Dictionary).keys().filter(func(k): return a.blocks[k])))]
			info.theme_type_variation = "DimLabel"
			row.add_child(info)
		"walls":
			var preset: Dictionary = EditorContext.WALL_PRESETS.get(str(a.get("preset", "wall")), {})
			var info := Label.new()
			info.text = "type: %s\nwidth %s hex\nblocks: %s" % [a.get("preset", "wall"), a.get("width", "?"),
				", ".join(PackedStringArray((preset.get("blocks", {}) as Dictionary).keys().filter(func(k): return preset.blocks[k])))]
			info.theme_type_variation = "DimLabel"
			row.add_child(_tex_rect(ctx.packs.placeholder(Color(str(a.get("color", "#808080")))), 64))
			row.add_child(info)
		"lights":
			var info := Label.new()
			info.text = "bright %s hex · dim %s hex\ncolour %s · %s" % [a.get("bright", "?"), a.get("dim", "?"), a.get("color", "?"), a.get("animation", "none")]
			info.theme_type_variation = "DimLabel"
			row.add_child(_tex_rect(ctx.packs.placeholder(Color(str(a.get("color", "#ffb060")))), 64))
			row.add_child(info)
	box.add_child(row)
	var tags := ", ".join(PackedStringArray(a.get("tags", [])))
	if tags != "":
		var tl := Label.new()
		tl.text = tags
		tl.theme_type_variation = "DimLabel"
		box.add_child(tl)
	_preview.add_child(box)
	# To the right of the palette, level with the tile.
	var tile_rect := tile.get_global_rect()
	var at := Vector2i(int(get_global_rect().end.x + 8), int(tile_rect.position.y))
	_preview.popup(Rect2i(at, Vector2i.ZERO))


func _tex_rect(tex: Texture2D, px: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tr


## The cell shape of the map being edited, for terrain thumbnails.
func _shape() -> String:
	return "square" if ctx.map != null and ctx.map.grid.is_square() else "hex"
