class_name EditorWindow
extends Control
## The Editor mode's window. Builds the whole UI in code, owns the open map,
## and routes menus, shortcuts, files and exports. Panels and tools live
## under hexmap/editor/; this file is the glue. The shell
## (hexmap/shell/main.gd) creates it with an App and swaps it out for the
## home screen or another mode on `go_home`.

signal go_home

const AUTOSAVE_SECONDS := 60.0

var app: App
var ctx := EditorContext.new()
var view: MapView
var palette: Palette
var inspector: Inspector
var layers: LayersPanel
var tool_options: ToolOptions
var tool_buttons: Dictionary = {}
var level_select: OptionButton
var status_left: Label
var status_right: Label
var undo_item: PopupMenu
var view_menu: PopupMenu
var _autosave := Timer.new()
var _ui_root: Control
var dock: DockableContainer
var _panes: Array = []
var _layout_save := Timer.new()
var theme_menu: PopupMenu
const TOOL_ICONS := {"select": "mouse-pointer-2", "terrain": "paintbrush", "fill": "paint-bucket", "prop": "trees",
	"wall": "brick-wall", "light": "lamp", "note": "sticky-note", "erase": "eraser"}
const V_THEME_BASE := 1000
const V_SCALE_BASE := 1100
var scale_menu: PopupMenu
## Theme choices, offered in the toolbar dropdown and under View → Theme.
static func theme_ids() -> PackedStringArray:
	return ThemeBuilder.names()
var _native_menus := NativeMenuMirror.new()
var _last_menu := [-1, -1]   # [id, frame] — the same command from both menu bars in one frame runs once

enum { M_NEW, M_OPEN, M_SAVE, M_SAVE_AS, M_EXPORT_PNG, M_EXPORT_UVTT, M_EXPORT_FOUNDRY, M_EXPORT_TILED, M_EXPORT_PDF, M_EXPORT_BUNDLE, M_HOME, M_QUIT,
	M_UNDO, M_REDO, M_DELETE, M_SELECT_ALL, M_GROUP, M_MAP_SETTINGS, M_PREFS,
	V_GRID, V_WALLS, V_LIGHTS, V_NOTES, V_HIDDEN, V_DARK, V_FIT, V_100, V_RELOAD_PACKS, V_DOCK, V_SCALE_UP, V_SCALE_DOWN,
	L_ADD, L_REMOVE, L_RENAME, L_UP, L_DOWN,
	H_SHORTCUTS, H_ABOUT }


func _ready() -> void:
	if app == null:
		app = App.new()
	ctx.packs = app.packs
	ctx.history = History.new()
	theme = app.build_theme()
	app.theme_changed.connect(_on_theme_changed)
	app.ui_scale_changed.connect(_on_ui_scale)
	_set_map(HexMap.create("Untitled", HexGrid.new()))
	_build_ui()
	_restyle()
	ctx.status.connect(func(t: String) -> void: status_left.text = t)
	ctx.selection_changed.connect(func() -> void: view.canvas.overlay.queue_redraw())
	ctx.history.changed.connect(_update_menus)
	_autosave.wait_time = AUTOSAVE_SECONDS
	_autosave.timeout.connect(_autosave_now)
	add_child(_autosave)
	_autosave.start()
	_layout_save.wait_time = 2.0
	_layout_save.one_shot = true
	_layout_save.timeout.connect(func() -> void: LayoutStore.save(dock.layout))
	add_child(_layout_save)
	_select_tool("select")
	for w in ctx.packs.warnings:
		push_warning(w)
	_update_title()


## The shell is about to screenshot the window (`--shot`).
func prepare_shot() -> void:
	view.zoom_to_fit()


## A map path from the command line or the home screen (via the shell).
func open_argument(path: String) -> void:
	_open_path(App.resolve_path(path))


func _set_map(m: HexMap) -> void:
	if ctx.map != null and ctx.map.changed.is_connected(_on_map_changed):
		ctx.map.changed.disconnect(_on_map_changed)
	ctx.map = m
	ctx.level_index = 0
	ctx.commands = Commands.new(m, ctx.history)
	ctx.history.clear()
	ctx.selection = []
	m.changed.connect(_on_map_changed)
	if view != null:
		view.set_map(m)
		_refresh_levels()
		inspector.refresh()
		layers.bind_map()
		ctx.selection_changed.emit()
	_update_title()


func _on_map_changed(what: String) -> void:
	view.canvas.refresh()
	if what == "levels":
		_refresh_levels()
	if what == "grid":
		view.canvas.ppx = float(ctx.map.reference_ppx)
		view.zoom_to_fit()
	_update_title()


# =================================================================== UI build ==

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	_ui_root = root

	root.add_child(_build_menus())
	root.add_child(_build_toolbar())
	tool_options = ToolOptions.new(ctx)
	var opts_panel := PanelContainer.new()
	opts_panel.theme_type_variation = "DockHeader"
	opts_panel.add_child(tool_options)
	root.add_child(opts_panel)

	palette = Palette.new(ctx)
	palette.name = "Palette"
	palette.picked.connect(_on_palette_pick)
	view = MapView.new(ctx)
	view.name = "Canvas"
	view.cursor_moved.connect(_on_cursor)
	view.zoom_changed.connect(func(z: float) -> void: _on_cursor(view.screen_to_hex(view.get_local_mouse_position())))
	layers = LayersPanel.new(ctx)
	layers.name = "Layers"
	layers.focus_requested.connect(_focus_on)
	inspector = Inspector.new(ctx)
	inspector.name = "Inspector"
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL

	root.add_child(_build_dock_layout())
	layers.bind_map()

	var status := HBoxContainer.new()
	status.name = "StatusBar"
	status_left = Label.new()
	status_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_left.clip_text = true
	status_left.theme_type_variation = "DimLabel"
	status_right = Label.new()
	status_right.theme_type_variation = "MonoLabel"
	status.add_child(status_left)
	status.add_child(status_right)
	for entry in [["zoom-out", "Zoom out", func() -> void: view.set_zoom(view.zoom() / 1.25)],
			["maximize", "Zoom to fit (Ctrl/Cmd+0)", func() -> void: view.zoom_to_fit()],
			["zoom-in", "Zoom in", func() -> void: view.set_zoom(view.zoom() * 1.25)]]:
		var zb := Button.new()
		zb.set_meta("icon", entry[0])
		zb.tooltip_text = entry[1]
		zb.theme_type_variation = "ToolButton"
		zb.focus_mode = Control.FOCUS_NONE
		zb.pressed.connect(entry[2])
		status.add_child(zb)
	var status_panel := PanelContainer.new()
	status_panel.add_child(status)
	root.add_child(status_panel)
	palette.refresh()
	_refresh_levels()


## Panels are tabs in a DockableContainer: drag a tab onto another panel to
## group with it, or to an edge to split. The arrangement is saved per user
## (LayoutStore) and restored next start; View → Reset layout puts it back.
func _build_dock_layout() -> Control:
	dock = DockableContainer.new()
	dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.tab_alignment = TabBar.ALIGNMENT_LEFT
	dock.hide_single_tab = true   # a lone pane's title bar is its handle; groups get tabs too
	_panes = [
		DockPane.new("Palette", palette),
		DockPane.new("Canvas", view),
		DockPane.new("Layers", layers, layers.header_actions()),
		DockPane.new("Inspector", inspector),
		DockPane.new("View options", _build_view_options()),
	]
	for p in _panes:
		dock.add_child(p)
	dock.layout = LayoutStore.load_or_default()
	dock.layout.changed.connect(func() -> void: _layout_save.start())
	return dock


func _reset_layout() -> void:
	dock.layout = LayoutStore.default_layout()
	dock.layout.changed.connect(func() -> void: _layout_save.start())
	_layout_save.start()


## Tear the panels down and build them again (layout switch). Panels are
## plain views over EditorContext, so nothing is lost.
func _rebuild_ui() -> void:
	var map := ctx.map
	view.set_tool(null)
	_ui_root.queue_free()
	_native_menus.free_menus()
	tool_buttons.clear()
	_build_ui()
	_restyle()
	view.set_map(map)
	_refresh_levels()
	inspector.refresh()
	_select_tool("select")


func _build_menus() -> MenuBar:
	var bar := MenuBar.new()
	bar.flat = true
	# Keep the menus in the window; on macOS NativeMenuMirror also puts a copy
	# in the system menu bar (see the end of this function).
	bar.prefer_global_menu = false
	var file := PopupMenu.new()
	file.name = "File"
	_item(file, "New…", M_NEW, KEY_N, true)
	_item(file, "Open…", M_OPEN, KEY_O, true)
	file.add_separator()
	_item(file, "Save", M_SAVE, KEY_S, true)
	_item(file, "Save As…", M_SAVE_AS, KEY_S, true, true)
	file.add_separator()
	var exp := PopupMenu.new()
	exp.name = "Export"
	_item(exp, "PNG image…", M_EXPORT_PNG)
	_item(exp, "Universal VTT (.dd2vtt)…", M_EXPORT_UVTT)
	_item(exp, "Foundry VTT scene…", M_EXPORT_FOUNDRY)
	_item(exp, "Tiled map (.tmj)…", M_EXPORT_TILED)
	exp.add_separator()
	_item(exp, "Print PDF…", M_EXPORT_PDF, KEY_P, true)
	_item(exp, "Print bundle (PNG + SVG + JSON)…", M_EXPORT_BUNDLE)
	exp.id_pressed.connect(_on_menu)
	file.add_child(exp)
	file.add_submenu_node_item("Export", exp)
	file.add_separator()
	_item(file, "Home", M_HOME)
	_item(file, "Quit", M_QUIT, KEY_Q, true)
	file.id_pressed.connect(_on_menu)
	bar.add_child(file)

	var edit := PopupMenu.new()
	edit.name = "Edit"
	_item(edit, "Undo", M_UNDO, KEY_Z, true)
	_item(edit, "Redo", M_REDO, KEY_Z, true, true)
	edit.add_separator()
	_item(edit, "Delete", M_DELETE)
	_item(edit, "Select all objects", M_SELECT_ALL, KEY_A, true)
	_item(edit, "Group selection into folder", M_GROUP, KEY_G, true)
	edit.add_separator()
	_item(edit, "Map settings…", M_MAP_SETTINGS, KEY_COMMA, true)
	_item(edit, "Pack folders…", M_PREFS)
	edit.id_pressed.connect(_on_menu)
	bar.add_child(edit)
	undo_item = edit

	view_menu = PopupMenu.new()
	view_menu.name = "View"
	_check(view_menu, "Grid", V_GRID, true, KEY_G)
	_check(view_menu, "Walls", V_WALLS, true)
	_check(view_menu, "Lights", V_LIGHTS, true)
	_check(view_menu, "Notes", V_NOTES, true)
	_check(view_menu, "GM-only objects", V_HIDDEN, true)
	_check(view_menu, "Darkness preview", V_DARK, false, KEY_D, true)
	view_menu.add_separator()
	_item(view_menu, "Zoom to fit", V_FIT, KEY_0, true)
	_item(view_menu, "Zoom 100%", V_100, KEY_1, true)
	view_menu.add_separator()
	_item(view_menu, "Reload packs", V_RELOAD_PACKS, KEY_R, true, true)
	view_menu.add_separator()
	_item(view_menu, "Reset panel layout", V_DOCK)
	scale_menu = PopupMenu.new()
	scale_menu.name = "UI size"
	var si := 0
	for sc in App.UI_SCALES:
		scale_menu.add_radio_check_item(App.scale_label(sc), V_SCALE_BASE + si)
		scale_menu.set_item_checked(si, is_equal_approx(float(sc), app.ui_scale))
		si += 1
	scale_menu.add_separator()
	_item(scale_menu, "Bigger", V_SCALE_UP, KEY_EQUAL, true)
	_item(scale_menu, "Smaller", V_SCALE_DOWN, KEY_MINUS, true)
	scale_menu.id_pressed.connect(_on_menu)
	view_menu.add_child(scale_menu)
	view_menu.add_submenu_node_item("UI size", scale_menu)
	theme_menu = PopupMenu.new()
	theme_menu.name = "Theme"
	var ti := 0
	for n in theme_ids():
		theme_menu.add_radio_check_item(str(ThemeBuilder.tokens(n).label), V_THEME_BASE + ti)
		theme_menu.set_item_checked(ti, n == app.theme_name)
		ti += 1
	theme_menu.id_pressed.connect(_on_menu)
	view_menu.add_child(theme_menu)
	view_menu.add_submenu_node_item("Theme", theme_menu)
	view_menu.id_pressed.connect(_on_menu)
	bar.add_child(view_menu)

	var lvl := PopupMenu.new()
	lvl.name = "Level"
	_item(lvl, "Add level…", L_ADD)
	_item(lvl, "Rename level…", L_RENAME)
	_item(lvl, "Remove level", L_REMOVE)
	lvl.add_separator()
	_item(lvl, "Move level up", L_UP)
	_item(lvl, "Move level down", L_DOWN)
	lvl.id_pressed.connect(_on_menu)
	bar.add_child(lvl)

	var help := PopupMenu.new()
	help.name = "Help"
	_item(help, "Shortcuts", H_SHORTCUTS, KEY_SLASH, true)
	_item(help, "About", H_ABOUT)
	help.id_pressed.connect(_on_menu)
	bar.add_child(help)
	_native_menus.mirror(bar)
	return bar


func _item(menu: PopupMenu, label: String, id: int, key := KEY_NONE, cmd := false, shift := false) -> void:
	var accel := KEY_NONE
	if key != KEY_NONE:
		accel = key | (KEY_MASK_CMD_OR_CTRL if cmd else 0) | (KEY_MASK_SHIFT if shift else 0)
	menu.add_item(label, id, accel)


func _check(menu: PopupMenu, label: String, id: int, checked: bool, key := KEY_NONE, shift := false) -> void:
	var accel := KEY_NONE
	if key != KEY_NONE:
		accel = key | (KEY_MASK_SHIFT if shift else 0)
	menu.add_check_item(label, id, accel)
	menu.set_item_checked(menu.get_item_index(id), checked)


func _build_toolbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	for entry in [["file-plus", M_NEW, "New map (Ctrl/Cmd+N)"], ["folder-open", M_OPEN, "Open a map (Ctrl/Cmd+O)"], ["save", M_SAVE, "Save (Ctrl/Cmd+S)"],
			["undo-2", M_UNDO, "Undo (Ctrl/Cmd+Z)"], ["redo-2", M_REDO, "Redo (Shift+Ctrl/Cmd+Z)"]]:
		var fb := Button.new()
		fb.set_meta("icon", entry[0])
		fb.tooltip_text = entry[2]
		fb.theme_type_variation = "ToolButton"
		fb.focus_mode = Control.FOCUS_NONE
		fb.pressed.connect(_on_menu.bind(entry[1]))
		bar.add_child(fb)
		if entry[0] == "save":
			bar.add_child(VSeparator.new())
	bar.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for t in EditorTools.all_tools():
		var b := Button.new()
		b.set_meta("icon", TOOL_ICONS[t.name])
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = "%s (%s)\n%s" % [t.label, t.key, t.hint]
		b.theme_type_variation = "ToolButton"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_select_tool.bind(t.name))
		bar.add_child(b)
		tool_buttons[t.name] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var l := Label.new()
	l.text = "Level"
	bar.add_child(l)
	level_select = OptionButton.new()
	level_select.custom_minimum_size.x = 160
	level_select.item_selected.connect(_on_level_selected)
	bar.add_child(level_select)
	return bar


func _build_view_options() -> Control:
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Darkness preview"
	box.add_child(title)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value_changed.connect(func(v: float) -> void:
		view.canvas.darkness = v
		view.canvas.refresh()
		view_menu.set_item_checked(view_menu.get_item_index(V_DARK), v > 0.0))
	slider.name = "Darkness"
	box.add_child(slider)
	return box


# ====================================================================== theme ==

func _set_theme(name: String) -> void:
	app.set_theme(name)


func _on_ui_scale(s: float) -> void:
	if scale_menu == null:
		return
	for i in App.UI_SCALES.size():
		scale_menu.set_item_checked(i, is_equal_approx(float(App.UI_SCALES[i]), s))
	ctx.say("UI size %s" % App.scale_label(s))


func _on_theme_changed(name: String) -> void:
	theme = app.build_theme()
	var i := 0
	for n in theme_ids():
		theme_menu.set_item_checked(i, n == name)
		i += 1
	_restyle()


## Everything that depends on the theme's tokens but is not a Theme item:
## icon colours, the canvas surround, panel icon refreshes.
func _restyle() -> void:
	var t := ThemeBuilder.tokens(app.theme_name)
	var text := ThemeBuilder.c(t, "text")
	var icon_size: int = t.icon
	for b in find_children("*", "Button", true, false):
		if b.has_meta("icon"):
			(b as Button).icon = UiIcons.get_icon(str(b.get_meta("icon")), icon_size, text, t.stroke)
	view.set_surround(ThemeBuilder.c(t, "canvas"), ThemeBuilder.c(t, "shadow"))
	for p in _panes:
		if is_instance_valid(p):
			(p as DockPane).restyle(t)
	layers.restyle(t)
	palette.restyle(t)
	inspector.restyle(t)
	view.canvas.refresh()


# ================================================================== tools etc ==

func _select_tool(tool_name: String) -> void:
	view.set_tool(EditorTools.make(tool_name, ctx))
	if tool_buttons.has(tool_name):
		(tool_buttons[tool_name] as Button).button_pressed = true
	if tool_options != null:
		tool_options.show_for(tool_name)
	if palette != null:
		palette.show_tab_for_tool(tool_name)
	for t in EditorTools.all_tools():
		if t.name == tool_name:
			ctx.say(t.hint)


func _on_palette_pick(kind: String) -> void:
	var current := view.tool.tool_name if view.tool != null else ""
	match kind:
		"terrain":
			if current != "fill":
				_select_tool("terrain")
		"props": _select_tool("prop")
		"walls": _select_tool("wall")
		"lights": _select_tool("light")
	tool_options.sync()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var e := event as InputEventKey
	if view.tool != null and view.tool.key(e):
		palette.sync()
		tool_options.sync()
		view.canvas.overlay.queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if e.ctrl_pressed or e.meta_pressed or e.alt_pressed:
		return
	for t in EditorTools.all_tools():
		if e.keycode == OS.find_keycode_from_string(t.key):
			_select_tool(t.name)
			get_viewport().set_input_as_handled()
			return
	if e.keycode == KEY_ESCAPE:
		ctx.clear_selection()
		_select_tool("select")


## Pan the view to an element (double-click in the Layers panel).
func _focus_on(collection: String, id: String) -> void:
	var o := HexMap.find_in(ctx.level(), collection, id)
	if o.is_empty():
		return
	var pos: Vector2
	if o.has("pos"):
		pos = Vector2(o.pos[0], o.pos[1])
	else:
		var pts: Array = o.get("points", [])
		if pts.is_empty():
			return
		for p in pts:
			pos += Vector2(p[0], p[1])
		pos /= pts.size()
	view.camera.position = pos * view.canvas.ppx
	if view.zoom() < 0.4:
		view.set_zoom(0.6)
	_select_tool("select")


func _on_cursor(hex: Vector2) -> void:
	if ctx.map == null:
		return
	var cell := ctx.map.grid.world_to_axial(hex)
	var off := ctx.map.grid.axial_to_offset(cell)
	var ppx := ctx.map.reference_ppx
	status_right.text = "col %d row %d  (q %d, r %d)   %d, %d px   %d%%" % [off.x, off.y, cell.x, cell.y, roundi(hex.x * ppx), roundi(hex.y * ppx), roundi(view.zoom() * 100.0)]


func _update_title() -> void:
	if ctx.map == null:
		return
	var t := "%s%s — %s" % [ctx.map.name, "*" if ctx.map.dirty else "", App.NAME]
	get_window().title = t


func _update_menus() -> void:
	var i := undo_item.get_item_index(M_UNDO)
	undo_item.set_item_text(i, "Undo %s" % ctx.history.undo_label() if ctx.history.can_undo() else "Undo")
	undo_item.set_item_disabled(i, not ctx.history.can_undo())
	i = undo_item.get_item_index(M_REDO)
	undo_item.set_item_text(i, "Redo %s" % ctx.history.redo_label() if ctx.history.can_redo() else "Redo")
	undo_item.set_item_disabled(i, not ctx.history.can_redo())
	_native_menus.sync_all()
	_update_title()


func _refresh_levels() -> void:
	level_select.clear()
	for l in ctx.map.levels:
		level_select.add_item(str(l.get("name", l.get("id", "?"))))
	ctx.level_index = clampi(ctx.level_index, 0, ctx.map.levels.size() - 1)
	level_select.select(ctx.level_index)
	view.canvas.level_index = ctx.level_index
	view.canvas.refresh()


func _on_level_selected(i: int) -> void:
	ctx.level_index = i
	view.canvas.level_index = i
	ctx.clear_selection()
	view.canvas.refresh()
	ctx.level_changed.emit()


# ====================================================================== menus ==

func _on_menu(id: int) -> void:
	var frame := Engine.get_process_frames()
	if _last_menu[0] == id and _last_menu[1] == frame:
		return
	_last_menu = [id, frame]
	if id >= V_THEME_BASE and id < V_THEME_BASE + theme_ids().size():
		_set_theme(theme_ids()[id - V_THEME_BASE])
		return
	if id >= V_SCALE_BASE and id < V_SCALE_BASE + App.UI_SCALES.size():
		app.set_ui_scale(float(App.UI_SCALES[id - V_SCALE_BASE]))
		return
	match id:
		M_NEW: _new_map_dialog()
		M_OPEN: _open_dialog()
		M_SAVE: _save(false)
		M_SAVE_AS: _save(true)
		M_HOME: _guard_unsaved(func() -> void: go_home.emit())
		M_QUIT: request_quit()
		M_EXPORT_PNG: _export_png_dialog()
		M_EXPORT_UVTT: _export_simple("uvtt")
		M_EXPORT_FOUNDRY: _export_simple("foundry")
		M_EXPORT_TILED: _export_simple("tiled")
		M_EXPORT_PDF: _export_pdf_dialog()
		M_EXPORT_BUNDLE: _export_bundle_dialog()
		M_UNDO: ctx.history.undo()
		M_REDO: ctx.history.redo()
		M_DELETE:
			if view.tool != null:
				var ev := InputEventKey.new()
				ev.keycode = KEY_DELETE
				ev.pressed = true
				view.tool.key(ev)
		M_SELECT_ALL:
			var sel := []
			for coll in ["props", "walls", "lights", "notes"]:
				for o in ctx.level().get(coll, []):
					sel.append({"collection": coll, "id": o.id})
			ctx.set_selection(sel)
			_select_tool("select")
		M_GROUP: layers._group_selection()
		M_MAP_SETTINGS: _map_settings_dialog()
		M_PREFS: _prefs_dialog()
		V_GRID, V_WALLS, V_LIGHTS, V_NOTES, V_HIDDEN, V_DARK:
			var idx := view_menu.get_item_index(id)
			var on := not view_menu.is_item_checked(idx)
			view_menu.set_item_checked(idx, on)
			match id:
				V_GRID: view.canvas.show_grid = on
				V_WALLS: view.canvas.show_walls = on
				V_LIGHTS: view.canvas.show_lights = on
				V_NOTES: view.canvas.show_notes = on
				V_HIDDEN: view.canvas.show_hidden = on
				V_DARK:
					view.canvas.darkness = 0.8 if on else 0.0
					(find_child("Darkness", true, false) as HSlider).set_value_no_signal(view.canvas.darkness)
			view.canvas.refresh()
		V_DOCK: _reset_layout()
		V_SCALE_UP: app.step_ui_scale(true)
		V_SCALE_DOWN: app.step_ui_scale(false)
		V_FIT: view.zoom_to_fit()
		V_100: view.set_zoom(1.0)
		V_RELOAD_PACKS:
			ctx.packs.reload()
			view.canvas.refresh()
			ctx.say("Packs reloaded: " + ", ".join(ctx.packs.pack_ids()))
		L_ADD:
			_prompt("Add level", "Name", "Level %d" % (ctx.map.levels.size() + 1), func(n: String) -> void:
				ctx.commands.add_level(n)
				_refresh_levels()
				level_select.select(ctx.map.levels.size() - 1)
				_on_level_selected(ctx.map.levels.size() - 1))
		L_RENAME:
			_prompt("Rename level", "Name", str(ctx.level().get("name", "")), func(n: String) -> void:
				ctx.commands.update_level(ctx.level_index, {"name": n}))
		L_REMOVE:
			if ctx.map.levels.size() > 1:
				_confirm("Remove level '%s' and everything on it?" % ctx.level().get("name", ""), func() -> void:
					ctx.commands.remove_level(ctx.level_index)
					ctx.level_index = 0
					_refresh_levels())
		L_UP, L_DOWN:
			var levels: Array = ctx.map.levels
			var to := ctx.level_index + (-1 if id == L_UP else 1)
			if to >= 0 and to < levels.size():
				var l = levels[ctx.level_index]
				var from := ctx.level_index
				ctx.history.commit("Reorder levels",
					func() -> void:
						levels.remove_at(from)
						levels.insert(to, l)
						ctx.map.touch("levels"),
					func() -> void:
						levels.remove_at(to)
						levels.insert(from, l)
						ctx.map.touch("levels"))
				ctx.level_index = to
				_refresh_levels()
		H_SHORTCUTS: _shortcuts_dialog()
		H_ABOUT:
			_info("%s %s\n\nHex-grid encounter maps: editor, table and player.\nSilvergrove Studios.\nGodot %s" % [App.NAME, App.build_stamp(), Engine.get_version_info().string])


# ================================================================ file actions ==

func _new_map_dialog() -> void:
	var form := PropertyForm.new()
	form.build([
		{"key": "name", "label": "Name", "type": "string"},
		{"key": "columns", "label": "Columns", "type": "int", "min": 1, "max": 400},
		{"key": "rows", "label": "Rows", "type": "int", "min": 1, "max": 400},
		{"key": "orientation", "label": "Hex orientation", "type": "enum", "options": ["pointy", "flat"], "tooltip": "pointy: rows of hexes; flat: columns"},
		{"key": "offset", "label": "Shifted rows/columns", "type": "enum", "options": ["odd", "even"]},
		{"key": "distance", "label": "One hex is", "type": "float", "min": 0.01, "step": 0.5},
		{"key": "units", "label": "Units", "type": "string"},
		{"key": "reference_ppx", "label": "Authoring pixels per hex", "type": "int", "min": 16, "max": 2048},
	], {"name": "Untitled", "columns": 20, "rows": 14, "orientation": "pointy", "offset": "odd", "distance": 5.0, "units": "ft", "reference_ppx": 256})
	_form_dialog("New map", form, func(v: Dictionary) -> void:
		_guard_unsaved(func() -> void:
			var g := HexGrid.from_dict(v)
			var m := HexMap.create(v.name, g)
			m.doc["reference_ppx"] = int(v.reference_ppx)
			_set_map(m)))


func _map_settings_dialog() -> void:
	var g := ctx.map.grid.to_dict()
	var s := ctx.map.style
	var form := PropertyForm.new()
	form.build([
		{"key": "name", "label": "Name", "type": "string"},
		{"key": "author", "label": "Author", "type": "string"},
		{"key": "description", "label": "Description", "type": "text"},
		{"key": "columns", "label": "Columns", "type": "int", "min": 1, "max": 400},
		{"key": "rows", "label": "Rows", "type": "int", "min": 1, "max": 400},
		{"key": "orientation", "label": "Hex orientation", "type": "enum", "options": ["pointy", "flat"], "tooltip": "Changing this reinterprets painted cells; expect to repaint."},
		{"key": "offset", "label": "Shifted rows/columns", "type": "enum", "options": ["odd", "even"]},
		{"key": "distance", "label": "One hex is", "type": "float", "min": 0.01, "step": 0.5},
		{"key": "units", "label": "Units", "type": "string"},
		{"key": "reference_ppx", "label": "Authoring pixels per hex", "type": "int", "min": 16, "max": 2048},
		{"key": "background", "label": "Background", "type": "color", "alpha": false},
		{"key": "grid_color", "label": "Grid colour", "type": "color"},
		{"key": "grid_width", "label": "Grid width", "type": "float", "min": 0.0, "max": 0.2, "step": 0.002, "suffix": " hex"},
	], {"name": ctx.map.name, "author": ctx.map.doc.meta.get("author", ""), "description": ctx.map.doc.meta.get("description", ""),
		"columns": g.columns, "rows": g.rows, "orientation": g.orientation, "offset": g.offset, "distance": g.distance, "units": g.units,
		"reference_ppx": ctx.map.reference_ppx, "background": s.get("background", "#1c1a17"), "grid_color": s.get("grid_color", "#00000066"), "grid_width": s.get("grid_width", 0.012)})
	_form_dialog("Map settings", form, func(v: Dictionary) -> void:
		var meta: Dictionary = ctx.map.doc.meta.duplicate()
		meta.author = v.author
		meta.description = v.description
		ctx.commands.update_map({
			"name": v.name, "meta": meta, "reference_ppx": int(v.reference_ppx),
			"grid": {"orientation": v.orientation, "offset": v.offset, "columns": int(v.columns), "rows": int(v.rows), "distance": v.distance, "units": v.units},
			"style": {"background": v.background, "grid_color": v.grid_color, "grid_width": v.grid_width},
		}))


func _prefs_dialog() -> void:
	var form := PropertyForm.new()
	form.build([{"key": "dirs", "label": "Extra pack folders\n(one per line)", "type": "text"}], {"dirs": "\n".join(PackedStringArray(app.prefs.pack_dirs))})
	_form_dialog("Pack folders", form, func(v: Dictionary) -> void:
		var dirs := []
		for line in str(v.dirs).split("\n"):
			if line.strip_edges() != "":
				dirs.append(line.strip_edges())
		app.set_pack_dirs(dirs)
		view.canvas.refresh())


func _open_dialog() -> void:
	_guard_unsaved(func() -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.hexmap ; Hex maps", "*.json ; Map JSON"])
		fd.file_selected.connect(_open_path)
		fd.popup_centered_ratio(0.7))


func _open_path(path: String) -> void:
	var err: Array = []
	var m := HexMap.load_file(path, err)
	if m == null:
		_info("Could not open %s:\n%s" % [path, "\n".join(PackedStringArray(err))])
		return
	var auto := path + ".autosave"
	if FileAccess.file_exists(auto) and FileAccess.get_modified_time(auto) > FileAccess.get_modified_time(path):
		_confirm("An autosave newer than this file exists. Restore it?", func() -> void:
			var m2 := HexMap.load_file(auto, err)
			if m2 != null:
				m2.path = path
				m2.dirty = true
				_set_map(m2)
				ctx.say("Restored autosave. Save to keep it."),
			func() -> void:
				_set_map(m))
		return
	_set_map(m)
	app.note_recent(path)
	ctx.say("Opened " + path)


func _save(as_new: bool) -> void:
	# A bundled example is read-only: save it somewhere of the user's.
	if ctx.map.path == "" or as_new or ctx.map.path.begins_with("res://"):
		var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.hexmap ; Hex maps"])
		fd.current_file = ctx.map.name.to_snake_case() + ".hexmap"
		fd.file_selected.connect(func(p: String) -> void: _save_to(p))
		fd.popup_centered_ratio(0.7)
		return
	_save_to(ctx.map.path)


func _save_to(path: String) -> void:
	if path.get_extension() == "":
		path += ".hexmap"
	var err := ctx.map.save(path)
	if err != OK:
		_info("Save failed: %s" % error_string(err))
		return
	DirAccess.remove_absolute(path + ".autosave")
	_update_title()
	app.note_recent(path)
	ctx.say("Saved " + path)


func _autosave_now() -> void:
	if ctx.map == null or not ctx.map.dirty or ctx.map.path == "":
		return
	var f := FileAccess.open(ctx.map.path + ".autosave", FileAccess.WRITE)
	if f != null:
		f.store_string(ctx.map.to_json())
		f.close()


func _guard_unsaved(then: Callable) -> void:
	if ctx.map == null or not ctx.map.dirty:
		then.call()
		return
	var d := ConfirmationDialog.new()
	d.title = "Unsaved changes"
	d.dialog_text = "'%s' has unsaved changes. Discard them?" % ctx.map.name
	d.ok_button_text = "Discard"
	d.confirmed.connect(then)
	d.close_requested.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


## The shell asks on window close; unsaved work gets a chance to be kept.
func request_quit() -> void:
	_guard_unsaved(func() -> void: get_tree().quit())


## Break the reference cycles (history commands capture the Commands object,
## tools hold the context) so nothing is reported leaked at exit.
func _exit_tree() -> void:
	_autosave.stop()
	if dock != null and is_instance_valid(dock):
		LayoutStore.save(dock.layout)
	_native_menus.free_menus()
	if app != null and app.theme_changed.is_connected(_on_theme_changed):
		app.theme_changed.disconnect(_on_theme_changed)
	if app != null and app.ui_scale_changed.is_connected(_on_ui_scale):
		app.ui_scale_changed.disconnect(_on_ui_scale)
	if ctx.history != null:
		ctx.history.clear()
	if view != null:
		view.set_tool(null)
	ctx.commands = null
	ctx.canvas = null


# ==================================================================== exports ==

func _export_png_dialog() -> void:
	var form := PropertyForm.new()
	form.build([
		{"key": "ppx", "label": "Pixels per hex", "type": "int", "min": 16, "max": 2048},
		{"key": "show_grid", "label": "Grid", "type": "bool"},
		{"key": "gm", "label": "Walls, lights, notes", "type": "bool"},
	], {"ppx": ctx.map.reference_ppx, "show_grid": true, "gm": false})
	_form_dialog("Export PNG", form, func(v: Dictionary) -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.png ; PNG image"])
		fd.current_file = ctx.map.name.to_snake_case() + ".png"
		fd.file_selected.connect(func(p: String) -> void:
			_run_export(func() -> Error: return await Exporter.png(self, ctx.map, ctx.packs, p, int(v.ppx), {
				"level": ctx.level_index, "show_grid": v.show_grid, "show_walls": v.gm, "show_lights": v.gm, "show_notes": v.gm, "show_hidden": v.gm})))
		fd.popup_centered_ratio(0.7))


func _export_simple(kind: String) -> void:
	var form := PropertyForm.new()
	var default_ppx: int = {"uvtt": 140, "foundry": 140, "tiled": ctx.map.reference_ppx}[kind]
	form.build([{"key": "ppx", "label": "Pixels per hex", "type": "int", "min": 16, "max": 2048,
		"tooltip": "VTTs are comfortable around 100–200. Foundry's grid.size becomes this number."}], {"ppx": default_ppx})
	var titles := {"uvtt": "Export Universal VTT", "foundry": "Export Foundry VTT scene", "tiled": "Export Tiled map"}
	var filters := {"uvtt": ["*.dd2vtt ; Universal VTT", "*.uvtt ; Universal VTT"], "foundry": ["*.json ; Foundry scene"], "tiled": ["*.tmj ; Tiled JSON map"]}
	var exts := {"uvtt": ".dd2vtt", "foundry": ".json", "tiled": ".tmj"}
	_form_dialog(titles[kind], form, func(v: Dictionary) -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, filters[kind])
		fd.current_file = ctx.map.name.to_snake_case() + exts[kind]
		fd.file_selected.connect(func(p: String) -> void: _export_kind_to(kind, int(v.ppx), p))
		fd.popup_centered_ratio(0.7))


func _export_kind_to(kind: String, ppx: int, p: String) -> void:
	match kind:
		"uvtt": _run_export(func() -> Error: return await Exporter.uvtt(self, ctx.map, ctx.packs, p, ppx, ctx.level_index))
		"foundry": _run_export(func() -> Error: return await Exporter.foundry(self, ctx.map, ctx.packs, p, ppx))
		"tiled": _report_export(Exporter.tiled(ctx.map, ctx.packs, p, ppx, ctx.level_index))


func _export_pdf_dialog() -> void:
	var form := PropertyForm.new()
	form.build([
		{"key": "mode", "label": "Layout", "type": "enum", "options": ["tiled", "fit"], "tooltip": "tiled: real-size hexes across many sheets; fit: whole map on one page"},
		{"key": "paper", "label": "Paper", "type": "enum", "options": ["letter", "legal", "tabloid", "a4", "a3", "a2"]},
		{"key": "landscape", "label": "Landscape", "type": "bool"},
		{"key": "hex_size_in", "label": "Hex size (tiled)", "type": "float", "min": 0.25, "max": 4, "step": 0.05, "suffix": " in", "tooltip": "Flat-to-flat. 1\" suits 28mm minis; 1.25\" for large bases."},
		{"key": "margin_in", "label": "Margin", "type": "float", "min": 0, "max": 2, "step": 0.05, "suffix": " in"},
		{"key": "overlap_in", "label": "Sheet overlap", "type": "float", "min": 0, "max": 2, "step": 0.05, "suffix": " in"},
		{"key": "dpi", "label": "Raster DPI", "type": "int", "min": 72, "max": 600},
		{"key": "jpeg_quality", "label": "JPEG quality", "type": "float", "min": -1, "max": 1, "step": 0.05, "tooltip": "-1 for lossless (large files)"},
		{"key": "grid", "label": "Grid", "type": "bool"},
		{"key": "gm_layers", "label": "Walls, lights, notes", "type": "bool"},
		{"key": "crop_marks", "label": "Crop marks", "type": "bool"},
		{"key": "labels", "label": "Labels and assembly page", "type": "bool"},
		{"key": "background", "label": "Outside the hexes", "type": "enum", "options": ["map", "white"], "tooltip": "map: the map's background colour; white: paper"},
	], PdfExport.DEFAULTS)
	_form_dialog("Print PDF", form, func(v: Dictionary) -> void:
		v["level"] = ctx.level_index
		var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.pdf ; PDF"])
		fd.current_file = ctx.map.name.to_snake_case() + ".pdf"
		fd.file_selected.connect(func(p: String) -> void: _run_export(func() -> Error: return await Exporter.pdf(self, ctx.map, ctx.packs, p, v)))
		fd.popup_centered_ratio(0.7))


func _export_bundle_dialog() -> void:
	var form := PropertyForm.new()
	form.build([
		{"key": "dpi", "label": "DPI", "type": "int", "min": 72, "max": 600},
		{"key": "hex_size_in", "label": "Hex size", "type": "float", "min": 0.25, "max": 4, "step": 0.05, "suffix": " in"},
	], {"dpi": 300, "hex_size_in": 1.0})
	_form_dialog("Print bundle", form, func(v: Dictionary) -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_DIR, [])
		fd.dir_selected.connect(func(p: String) -> void:
			_run_export(func() -> Error: return await Exporter.bundle(self, ctx.map, ctx.packs, p.path_join(ctx.map.name.to_snake_case()), int(v.dpi), float(v.hex_size_in), ctx.level_index)))
		fd.popup_centered_ratio(0.7))


func _run_export(job: Callable) -> void:
	ctx.say("Exporting…")
	var err: Error = await job.call()
	_report_export(err)


func _report_export(err: Error) -> void:
	if err == OK:
		ctx.say(Exporter.last_message)
	else:
		_info("Export failed: %s" % error_string(err))


# ==================================================================== dialogs ==

func _file_dialog(mode: FileDialog.FileMode, filters: Array) -> FileDialog:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	for f in filters:
		fd.add_filter(f.split(";")[0].strip_edges(), f.split(";")[1].strip_edges() if f.contains(";") else "")
	if ctx.map.path != "":
		fd.current_dir = ctx.map.path.get_base_dir()
	fd.close_requested.connect(fd.queue_free)
	fd.canceled.connect(fd.queue_free)
	fd.confirmed.connect(fd.queue_free)
	add_child(fd)
	return fd


func _form_dialog(title: String, form: PropertyForm, on_ok: Callable) -> void:
	var d := ConfirmationDialog.new()
	d.title = title
	d.min_size = Vector2i(420, 0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, minf(520, 40 + form.get_child_count() * 17))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(form)
	d.add_child(scroll)
	d.confirmed.connect(func() -> void: on_ok.call(form.get_values()))
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.close_requested.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


func _prompt(title: String, label: String, initial: String, on_ok: Callable) -> void:
	var form := PropertyForm.new()
	form.build([{"key": "v", "label": label, "type": "string"}], {"v": initial})
	_form_dialog(title, form, func(v: Dictionary) -> void: on_ok.call(str(v.v)))


func _confirm(text: String, on_ok: Callable, on_cancel := Callable()) -> void:
	var d := ConfirmationDialog.new()
	d.dialog_text = text
	d.confirmed.connect(on_ok)
	if on_cancel.is_valid():
		d.canceled.connect(on_cancel)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.close_requested.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


func _info(text: String) -> void:
	var d := AcceptDialog.new()
	d.dialog_text = text
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.close_requested.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


func _shortcuts_dialog() -> void:
	var lines := PackedStringArray()
	for t in EditorTools.all_tools():
		lines.append("%s — %s: %s" % [t.key, t.label, t.hint])
	lines.append("")
	lines.append("Space+drag or middle-drag: pan · wheel: zoom · Ctrl/Cmd+0: fit · Ctrl/Cmd+1: 100%")
	lines.append("Ctrl/Cmd+Z / Shift+Ctrl/Cmd+Z: undo / redo · Ctrl/Cmd+S: save · Ctrl/Cmd+P: print PDF")
	lines.append("G: grid · Shift+D: darkness preview · Esc: select tool")
	_info("\n".join(lines))
