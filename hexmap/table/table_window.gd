class_name TableWindow
extends Control
## The Table: where a DM runs a campaign — the party's sheets, the NPCs,
## the notes, the maps — and, from it, sessions and fights on the maps
## (docs/campaign-plan.md). Owns the open campaign and its live encounter
## (through a TableContext), the docked panels, menus, files and autosave.
## With no campaign open it shows the picker. Desktop only — it docks panels and opens file dialogs. The map
## itself is drawn by the same MapCanvas as the editor, given the encounter
## state, so what the DM sees is what the players' clients will draw.

signal go_home

const AUTOSAVE_SECONDS := 60.0
const V_THEME_BASE := 1000
const V_SCALE_BASE := 1100
var scale_menu: PopupMenu
const V_PLAYER_BASE := 2000

var app: App
var ctx := TableContext.new()
var host: HostSession
var host_button: Button
var bonjour := Bonjour.new()
var view: TableView
var scenes: ScenesPanel
var tokens: TokensPanel
var inspector: TableInspector
var turns: TurnsPanel
var rules: RulesPanel
var lookup: LookupPopup
var compendium: CompendiumPanel
var players: PlayersPanel
var campaign_panel: CampaignPanel
var party: RosterPanel
var npcs: RosterPanel
var notes: NotesPanel
var maps: MapsPanel
var tool_options: HBoxContainer
## The tool the DM chose; a pick borrows the view and gives it back.
var _tool_name := "select"
var tool_buttons: Dictionary = {}
var scene_select: OptionButton
var viewpoint_select: OptionButton
var status_left: Label
var status_right: Label
var edit_menu: PopupMenu
var view_menu: PopupMenu
var theme_menu: PopupMenu
var viewpoint_menu: PopupMenu
var dock: DockableContainer
var _panes: Array = []
var _ui_root: Control
var _autosave := Timer.new()
var _layout_save := Timer.new()
var _native_menus := NativeMenuMirror.new()
var _last_menu := [-1, -1]
var _token_form: PropertyForm
## The campaign picker shown over the dock while no campaign is open.
var _picker: Control
var _picker_recent: VBoxContainer

enum { M_NEW, M_OPEN, M_SAVE, M_SAVE_AS, M_ADD_SCENE, M_HOME, M_QUIT,
	M_NEW_CAMPAIGN, M_OPEN_CAMPAIGN, M_SAVE_CAMPAIGN, M_RECAP, M_CLOSE_CAMPAIGN,
	M_UNDO, M_REDO, M_DELETE, M_SELECT_ALL, M_HIDE, M_CHECKPOINT, M_BULK, M_IMPROVISE,
	V_GRID, V_WALLS, V_LIGHTS, V_NOTES, V_TOKENS, V_FOG, V_HIDDEN, V_FIT, V_100, V_DOCK, V_SCALE_UP, V_SCALE_DOWN, V_LOOKUP,
	S_SHOW, S_RENAME, S_REMOVE, S_FOG, S_RESET_FOG, N_HOST,
	T_FREE, T_DM, T_ORDERED, T_START, T_NEXT, T_PREV, T_END,
	H_SHORTCUTS, H_ABOUT }


func _ready() -> void:
	if app == null:
		app = App.new()
	ctx.app = app
	theme = app.build_theme()
	app.theme_changed.connect(_on_theme_changed)
	app.ui_scale_changed.connect(_on_ui_scale)
	_set_encounter(Encounter.create("Untitled encounter"))
	_build_ui()
	_restyle()
	ctx.status.connect(func(t: String) -> void: status_left.text = t)
	ctx.selection_changed.connect(func() -> void: view.canvas.overlay.queue_redraw(); _update_menus())
	ctx.pick_changed.connect(func() -> void:
		view.set_tool(TableTools.make("pick" if not ctx.pick.is_empty() else _tool_name, ctx))
		view.canvas.overlay.queue_redraw())
	ctx.scene_changed.connect(_on_scene_changed)
	ctx.history.changed.connect(_update_menus)
	_autosave.wait_time = AUTOSAVE_SECONDS
	_autosave.timeout.connect(_autosave_now)
	add_child(_autosave)
	_autosave.start()
	_layout_save.wait_time = 2.0
	_layout_save.one_shot = true
	_layout_save.timeout.connect(func() -> void: LayoutStore.save(dock.layout, LayoutStore.table_path()))
	add_child(_layout_save)
	_select_tool("select")
	_update_title()
	_show_picker(true)


func _process(delta: float) -> void:
	if host != null:
		host.poll(delta)


## A campaign (or an encounter to import) from the command line or the
## home screen. On the command line, `--host` starts hosting at once and
## `--turns free|dm|ordered` sets the turn mode
## (`./run.sh table reach.campaign --host --turns free`).
func open_argument(path: String) -> void:
	_open_path(App.resolve_path(path))
	var args := OS.get_cmdline_user_args()
	var ti := args.find("--turns")
	if ti >= 0 and ti + 1 < args.size() and Encounter.TURN_MODES.has(args[ti + 1]):
		ctx.commands.set_turn_mode(args[ti + 1])
	if args.has("--host"):
		_set_hosting(true)


func prepare_shot() -> void:
	view.zoom_to_fit()


func _set_encounter(e: Encounter) -> void:
	ctx.set_encounter(e)
	e.changed.connect(_on_encounter_changed)
	if host != null:
		host.set_state(ctx.state)
		host.kernel = ctx.kernel
		host.plugins = ctx.host
	if view != null:
		_bind_panels()
		_refresh_scene_select()
		_refresh_viewpoints()
		view.show_scene()
		ctx.selection_changed.emit()
	_update_title()


func _bind_panels() -> void:
	for p in [scenes, tokens, inspector, turns, rules, compendium, players, campaign_panel, party, npcs, notes, maps]:
		p.bind()


func _on_encounter_changed(what: String, scene_id: String) -> void:
	if what == "scenes" or what == "active_scene" or what == "restore":
		_refresh_scene_select()
	if what == "players" or what == "restore":
		_refresh_viewpoints()
	if what == "restore":
		ctx.clear_selection()
		view.show_scene()
	if scene_id == ctx.scene_id or scene_id == "" or what == "turns":
		view.canvas.refresh()
	_update_title()
	_update_menus()


func _on_scene_changed() -> void:
	view.show_scene()
	_refresh_scene_select()
	_update_menus()


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
	var opts_panel := PanelContainer.new()
	opts_panel.theme_type_variation = "DockHeader"
	opts_panel.add_child(_build_tool_options())
	root.add_child(opts_panel)

	view = TableView.new(ctx)
	view.cursor_moved.connect(_on_cursor)
	view.zoom_changed.connect(func(_z: float) -> void: _on_cursor(Vector2.ZERO))
	scenes = ScenesPanel.new(ctx)
	scenes.add_requested.connect(_add_scene_dialog)
	tokens = TokensPanel.new(ctx)
	inspector = TableInspector.new(ctx)
	turns = TurnsPanel.new(ctx)
	rules = RulesPanel.new(ctx)
	compendium = CompendiumPanel.new(ctx)
	players = PlayersPanel.new(ctx)
	campaign_panel = CampaignPanel.new(ctx)
	campaign_panel.on_campaign_action = func(kind: String) -> void:
		if kind == "recap":
			_recap_dialog()
	campaign_panel.on_host = func() -> void: _set_hosting(host == null)
	campaign_panel.host_info = func() -> Dictionary:
		if host == null:
			return {"hosting": false}
		var names := []
		for pid in players.online:
			names.append(str(ctx.encounter().player(str(pid)).get("name", pid)))
		return {"hosting": true, "address": host_address(), "code": host.cogm_code, "connected": names}
	party = RosterPanel.new(ctx, true)
	npcs = RosterPanel.new(ctx, false)
	notes = NotesPanel.new(ctx)
	maps = MapsPanel.new(ctx)
	lookup = LookupPopup.new()
	add_child(lookup)
	ctx.lookup = func(collection: String, id: String) -> void:
		_prepare_lookup()
		lookup.show_entry(collection, id)
	compendium.pick_content_file = func(then: Callable) -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_ANY, ["*.json ; Packs and entry files"])
		fd.file_selected.connect(then)
		fd.dir_selected.connect(then)
		fd.popup_centered_ratio(0.7)
	rules.pick_plugin_file = func(then: Callable) -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.zip ; Ruleset zips"])
		fd.file_selected.connect(then)
		fd.popup_centered_ratio(0.7)
	maps.pick_map_file = func(then: Callable) -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.hexmap ; Hex maps", "*.json ; Map JSON"])
		fd.file_selected.connect(then)
		fd.popup_centered_ratio(0.7)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dock_ctl := _build_dock_layout()
	dock_ctl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(dock_ctl)
	_picker = _build_picker()
	stack.add_child(_picker)
	root.add_child(stack)
	_bind_panels()
	_refresh_scene_select()
	_refresh_viewpoints()
	view.show_scene()

	var status := HBoxContainer.new()
	status.theme_type_variation = "DockHeader"
	status_left = Label.new()
	status_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_left.theme_type_variation = "DimLabel"
	status.add_child(status_left)
	status_right = Label.new()
	status_right.theme_type_variation = "MonoLabel"
	status.add_child(status_right)
	root.add_child(status)


func _build_dock_layout() -> Control:
	dock = DockableContainer.new()
	dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.tab_alignment = TabBar.ALIGNMENT_LEFT
	dock.hide_single_tab = true
	_panes = [
		DockPane.new("Scenes", scenes, scenes.header_actions()),
		DockPane.new("Tokens", tokens, tokens.header_actions()),
		DockPane.new("Canvas", view),
		DockPane.new("Inspector", inspector),
		DockPane.new("Turns", turns, turns.header_actions()),
		DockPane.new("Rules", rules),
		DockPane.new("Compendium", compendium),
		DockPane.new("Players", players, players.header_actions()),
		DockPane.new("Session", campaign_panel),
		DockPane.new("Party", party, party.header_actions()),
		DockPane.new("NPCs", npcs, npcs.header_actions()),
		DockPane.new("Notes", notes),
		DockPane.new("Maps", maps),
	]
	for p in _panes:
		dock.add_child(p)
	dock.layout = LayoutStore.load_or_default(LayoutStore.table_path(), LayoutStore.TABLE_PANELS, LayoutStore.table_layout)
	dock.layout.changed.connect(func() -> void: _layout_save.start())
	return dock


## The first screen of the Table: the campaigns this device has opened,
## and the ways to start one.
func _build_picker() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "Campaigns"
	title.theme_type_variation = "HeaderLabel"
	box.add_child(title)
	var blurb := Label.new()
	blurb.text = "A campaign keeps the party's sheets, the NPCs, the notes and the maps between sessions. Open one, or start a new one."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.theme_type_variation = "DimLabel"
	box.add_child(blurb)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var new_b := Button.new()
	new_b.text = "New campaign…"
	new_b.theme_type_variation = "AccentButton"
	new_b.pressed.connect(_new_campaign_dialog)
	actions.add_child(new_b)
	var open_b := Button.new()
	open_b.text = "Open campaign…"
	open_b.pressed.connect(_open_campaign_dialog)
	actions.add_child(open_b)
	var imp := Button.new()
	imp.text = "Import an encounter…"
	imp.tooltip_text = "An encounter file from before campaigns: opened as a campaign of its own"
	imp.pressed.connect(_open_dialog)
	actions.add_child(imp)
	box.add_child(actions)
	var rl := Label.new()
	rl.text = "Recent"
	rl.theme_type_variation = "HeaderLabel"
	box.add_child(rl)
	_picker_recent = VBoxContainer.new()
	box.add_child(_picker_recent)
	var home := Button.new()
	home.text = "Home"
	home.pressed.connect(func() -> void: go_home.emit())
	box.add_child(home)
	return panel


func _show_picker(on: bool) -> void:
	if _picker == null:
		return
	_picker.visible = on
	if not on:
		return
	for c in _picker_recent.get_children():
		_picker_recent.remove_child(c)
		c.queue_free()
	var any := false
	for p in app.recent():
		if not (str(p).ends_with(".campaign") or str(p).ends_with(".encounter")):
			continue
		any = true
		var b := Button.new()
		b.text = str(p).get_file().get_basename().capitalize() + ("" if str(p).ends_with(".campaign") else "  (encounter)")
		b.tooltip_text = str(p)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var path := str(p)
		b.pressed.connect(func() -> void: _open_path(path))
		_picker_recent.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "Nothing yet."
		l.theme_type_variation = "DimLabel"
		_picker_recent.add_child(l)


## The lookup popup over this table's compendium and its rulesets' cards.
func _prepare_lookup() -> void:
	lookup.source = party._comp
	lookup.cards = EntryCard.cards_of(ctx.host)
	lookup.collections = ctx.kernel.comp.collections() if ctx.kernel != null else []
	lookup.role = "gm"


func _reset_layout() -> void:
	dock.layout = LayoutStore.table_layout()
	dock.layout.changed.connect(func() -> void: _layout_save.start())
	_layout_save.start()


func _build_menus() -> MenuBar:
	var bar := MenuBar.new()
	bar.flat = true
	bar.prefer_global_menu = false
	var file := PopupMenu.new()
	file.name = "File"
	_item(file, "New campaign…", M_NEW_CAMPAIGN, KEY_N, true)
	_item(file, "Open campaign…", M_OPEN_CAMPAIGN, KEY_O, true)
	file.add_separator()
	_item(file, "Save campaign", M_SAVE, KEY_S, true)
	_item(file, "Save campaign as…", M_SAVE_AS, KEY_S, true, true)
	file.add_separator()
	_item(file, "Add map as scene…", M_ADD_SCENE, KEY_M, true)
	_item(file, "Import an encounter…", M_OPEN)
	_item(file, "Export session recap…", M_RECAP)
	file.add_separator()
	_item(file, "Close campaign", M_CLOSE_CAMPAIGN)
	_item(file, "Home", M_HOME)
	_item(file, "Quit", M_QUIT, KEY_Q, true)
	file.id_pressed.connect(_on_menu)
	bar.add_child(file)

	edit_menu = PopupMenu.new()
	edit_menu.name = "Edit"
	_item(edit_menu, "Undo", M_UNDO, KEY_Z, true)
	_item(edit_menu, "Redo", M_REDO, KEY_Z, true, true)
	edit_menu.add_separator()
	_item(edit_menu, "Remove tokens", M_DELETE)
	_item(edit_menu, "Hide / reveal tokens", M_HIDE, KEY_H)
	_item(edit_menu, "Select all tokens", M_SELECT_ALL, KEY_A, true)
	edit_menu.add_separator()
	_item(edit_menu, "Checkpoint…", M_CHECKPOINT, KEY_K, true)
	_item(edit_menu, "Bulk on selected tokens…", M_BULK, KEY_B, true)
	_item(edit_menu, "Improvise a creature…", M_IMPROVISE, KEY_I, true)
	edit_menu.id_pressed.connect(_on_menu)
	bar.add_child(edit_menu)

	view_menu = PopupMenu.new()
	view_menu.name = "View"
	_check(view_menu, "Grid", V_GRID, true, KEY_G)
	_check(view_menu, "Walls", V_WALLS, true)
	_check(view_menu, "Lights", V_LIGHTS, true)
	_check(view_menu, "Notes", V_NOTES, true)
	_check(view_menu, "Tokens", V_TOKENS, true)
	_check(view_menu, "Fog", V_FOG, true)
	_check(view_menu, "GM-only objects", V_HIDDEN, true)
	view_menu.add_separator()
	viewpoint_menu = PopupMenu.new()
	viewpoint_menu.name = "Viewpoint"
	viewpoint_menu.id_pressed.connect(_on_menu)
	view_menu.add_child(viewpoint_menu)
	view_menu.add_submenu_node_item("See as", viewpoint_menu)
	view_menu.add_separator()
	_item(view_menu, "Zoom to fit", V_FIT, KEY_0, true)
	_item(view_menu, "Zoom 100%", V_100, KEY_1, true)
	view_menu.add_separator()
	_item(view_menu, "Reset panel layout", V_DOCK)
	view_menu.add_separator()
	_item(view_menu, "Look up…", V_LOOKUP, KEY_L, true)
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
	for n in ThemeBuilder.names():
		theme_menu.add_radio_check_item(str(ThemeBuilder.tokens(n).label), V_THEME_BASE + ti)
		theme_menu.set_item_checked(ti, n == app.theme_name)
		ti += 1
	theme_menu.id_pressed.connect(_on_menu)
	view_menu.add_child(theme_menu)
	view_menu.add_submenu_node_item("Theme", theme_menu)
	view_menu.id_pressed.connect(_on_menu)
	bar.add_child(view_menu)

	var scene := PopupMenu.new()
	scene.name = "Scene"
	_item(scene, "Show this scene to players", S_SHOW)
	_item(scene, "Rename scene…", S_RENAME)
	_item(scene, "Remove scene", S_REMOVE)
	scene.add_separator()
	_check(scene, "Fog of war", S_FOG, false, KEY_F, true)
	_item(scene, "Reset fog (forget everything explored)", S_RESET_FOG)
	scene.id_pressed.connect(_on_menu)
	bar.add_child(scene)

	var tm := PopupMenu.new()
	tm.name = "Turns"
	tm.add_radio_check_item("Free: anyone moves", T_FREE)
	tm.add_radio_check_item("DM picks who moves", T_DM)
	tm.add_radio_check_item("Ordered turns", T_ORDERED)
	tm.add_separator()
	_item(tm, "Start ordered turns on this scene", T_START)
	_item(tm, "Next turn", T_NEXT, KEY_SPACE, true)
	_item(tm, "Previous turn", T_PREV, KEY_SPACE, true, true)
	_item(tm, "End turns", T_END)
	tm.id_pressed.connect(_on_menu)
	bar.add_child(tm)

	var net := PopupMenu.new()
	net.name = "Network"
	_check(net, "Host on this network", N_HOST, false)
	net.id_pressed.connect(_on_menu)
	bar.add_child(net)

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
	for entry in [["file-plus", M_NEW_CAMPAIGN, "New campaign (Ctrl/Cmd+N)"], ["folder-open", M_OPEN_CAMPAIGN, "Open a campaign (Ctrl/Cmd+O)"], ["save", M_SAVE, "Save the campaign (Ctrl/Cmd+S)"],
			["map", M_ADD_SCENE, "Add a map as a scene (Ctrl/Cmd+M)"],
			["undo-2", M_UNDO, "Undo (Ctrl/Cmd+Z)"], ["redo-2", M_REDO, "Redo (Shift+Ctrl/Cmd+Z)"]]:
		var fb := Button.new()
		fb.set_meta("icon", entry[0])
		fb.tooltip_text = entry[2]
		fb.theme_type_variation = "ToolButton"
		fb.focus_mode = Control.FOCUS_NONE
		fb.pressed.connect(_on_menu.bind(entry[1]))
		bar.add_child(fb)
		if entry[0] == "map":
			bar.add_child(VSeparator.new())
	bar.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for t in TableTools.all_tools():
		var b := Button.new()
		b.set_meta("icon", t.icon)
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = "%s (%s)\n%s" % [t.label, t.key, t.hint]
		b.theme_type_variation = "ToolButton"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_select_tool.bind(t.name))
		bar.add_child(b)
		tool_buttons[t.name] = b
	host_button = Button.new()
	host_button.text = "Host"
	host_button.set_meta("icon", "scan")
	host_button.toggle_mode = true
	host_button.tooltip_text = "Host this encounter on the local network so players can join"
	host_button.theme_type_variation = "ToolButton"
	host_button.focus_mode = Control.FOCUS_NONE
	host_button.toggled.connect(func(on: bool) -> void: _set_hosting(on))
	bar.add_child(host_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var l := Label.new()
	l.text = "Scene"
	bar.add_child(l)
	scene_select = OptionButton.new()
	scene_select.custom_minimum_size.x = 180
	scene_select.item_selected.connect(func(i: int) -> void: ctx.set_scene(str(scene_select.get_item_metadata(i))))
	bar.add_child(scene_select)
	var l2 := Label.new()
	l2.text = "See as"
	bar.add_child(l2)
	viewpoint_select = OptionButton.new()
	viewpoint_select.custom_minimum_size.x = 120
	viewpoint_select.tooltip_text = "Look at the scene the way a player will: fog, hidden things and vision through their tokens"
	viewpoint_select.item_selected.connect(func(i: int) -> void: _set_viewpoint(str(viewpoint_select.get_item_metadata(i))))
	bar.add_child(viewpoint_select)
	return bar


## The token tool's picks: what the next placed token will be.
func _build_tool_options() -> Control:
	tool_options = HBoxContainer.new()
	tool_options.add_theme_constant_override("separation", 8)
	_token_form = PropertyForm.new()
	_token_form.columns = 12
	_token_form.build([
		{"key": "name", "label": "Name", "type": "string"},
		{"key": "color", "label": "Colour", "type": "color", "alpha": false},
		{"key": "size", "label": "Size", "type": "int", "min": 1, "max": 6},
		{"key": "owner", "label": "Owner", "type": "enum", "options": ["(the DM)"]},
		{"key": "hidden", "label": "Hidden", "type": "bool"},
		{"key": "snap", "label": "Snap to cells", "type": "bool"},
	], {"name": ctx.token_name, "color": ctx.token_color, "size": ctx.token_size, "owner": "(the DM)", "hidden": ctx.token_hidden, "snap": ctx.snap_tokens})
	(_token_form.control("name") as LineEdit).custom_minimum_size.x = 140
	_token_form.value_changed.connect(func(k: String, v: Variant) -> void:
		match k:
			"name": ctx.token_name = str(v)
			"color": ctx.token_color = str(v)
			"size": ctx.token_size = int(v)
			"hidden": ctx.token_hidden = bool(v)
			"snap": ctx.snap_tokens = bool(v)
			"owner":
				ctx.token_owner = ""
				for p in ctx.encounter().players:
					if str(p.name) == str(v):
						ctx.token_owner = str(p.id)
		view.canvas.overlay.queue_redraw())
	tool_options.add_child(_token_form)
	return tool_options


func _refresh_token_owner_options() -> void:
	var ob := _token_form.control("owner") as OptionButton
	if ob == null:
		return
	ob.clear()
	ob.add_item("(the DM)")
	var options := ["(the DM)"]
	for p in ctx.encounter().players:
		ob.add_item(str(p.name))
		options.append(str(p.name))
	_token_form._schema[3]["options"] = options
	ctx.token_owner = ""
	ob.select(0)


func _refresh_scene_select() -> void:
	if scene_select == null:
		return
	scene_select.clear()
	var e := ctx.encounter()
	var i := 0
	for s in e.scenes:
		scene_select.add_item(("● " if str(s.id) == e.active_scene_id else "") + str(s.get("name", s.id)))
		scene_select.set_item_metadata(i, str(s.id))
		if str(s.id) == ctx.scene_id:
			scene_select.select(i)
		i += 1
	scene_select.disabled = e.scenes.is_empty()


func _refresh_viewpoints() -> void:
	if viewpoint_select == null:
		return
	viewpoint_select.clear()
	viewpoint_menu.clear()
	viewpoint_select.add_item("The DM")
	viewpoint_select.set_item_metadata(0, "")
	viewpoint_menu.add_radio_check_item("The DM", V_PLAYER_BASE)
	var i := 1
	for p in ctx.encounter().players:
		viewpoint_select.add_item(str(p.name))
		viewpoint_select.set_item_metadata(i, str(p.id))
		viewpoint_menu.add_radio_check_item(str(p.name), V_PLAYER_BASE + i)
		if str(p.id) == view.canvas.viewpoint:
			viewpoint_select.select(i)
		i += 1
	if ctx.encounter().player(view.canvas.viewpoint).is_empty():
		_set_viewpoint("")
	_refresh_token_owner_options()


func _set_viewpoint(pid: String) -> void:
	view.canvas.viewpoint = pid
	view.canvas.refresh()
	for i in viewpoint_select.item_count:
		if str(viewpoint_select.get_item_metadata(i)) == pid:
			viewpoint_select.select(i)
		viewpoint_menu.set_item_checked(i, str(viewpoint_select.get_item_metadata(i)) == pid)
	if pid == "":
		ctx.say("Seeing everything, as the DM")
	else:
		ctx.say("Seeing as %s: fog, vision and hidden things as they get them" % str(ctx.encounter().player(pid).get("name", "")))


# ====================================================================== theme ==

func _on_ui_scale(s: float) -> void:
	if scale_menu == null:
		return
	for i in App.UI_SCALES.size():
		scale_menu.set_item_checked(i, is_equal_approx(float(App.UI_SCALES[i]), s))
	ctx.say("UI size %s" % App.scale_label(s))


func _on_theme_changed(name: String) -> void:
	theme = app.build_theme()
	var i := 0
	for n in ThemeBuilder.names():
		theme_menu.set_item_checked(i, n == name)
		i += 1
	_restyle()


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
	tokens.restyle(t)
	view.canvas.refresh()


# ================================================================== tools etc ==

func _select_tool(tool_name: String) -> void:
	_tool_name = tool_name
	if not ctx.pick.is_empty():
		return
	view.set_tool(TableTools.make(tool_name, ctx))
	if tool_buttons.has(tool_name):
		(tool_buttons[tool_name] as Button).button_pressed = true
	tool_options.visible = tool_name == "token"
	for t in TableTools.all_tools():
		if t.name == tool_name:
			ctx.say(t.hint)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var e := event as InputEventKey
	if view.tool != null and view.tool.key(e):
		get_viewport().set_input_as_handled()
		view.canvas.overlay.queue_redraw()
		return
	if e.ctrl_pressed or e.meta_pressed or e.alt_pressed:
		return
	for t in TableTools.all_tools():
		if e.keycode == OS.find_keycode_from_string(t.key):
			_select_tool(t.name)
			get_viewport().set_input_as_handled()
			return
	if e.keycode == KEY_ESCAPE:
		ctx.clear_selection()
		_select_tool("select")


func _on_cursor(hex: Vector2) -> void:
	var m := ctx.map()
	if m == null:
		status_right.text = ""
		return
	var cell := m.grid.world_to_axial(hex)
	var off := m.grid.axial_to_offset(cell)
	status_right.text = "col %d row %d   %d%%" % [off.x, off.y, roundi(view.zoom() * 100.0)]


func _update_title() -> void:
	var e := ctx.encounter()
	var what := ctx.campaign.name if ctx.campaign != null else e.name
	get_window().title = "%s%s — Table — %s" % [what, "*" if ctx.campaign_dirty() else "", App.NAME]


func _update_menus() -> void:
	var h := ctx.history
	var i := edit_menu.get_item_index(M_UNDO)
	edit_menu.set_item_text(i, "Undo %s" % h.undo_label() if h.can_undo() else "Undo")
	edit_menu.set_item_disabled(i, not h.can_undo())
	i = edit_menu.get_item_index(M_REDO)
	edit_menu.set_item_text(i, "Redo %s" % h.redo_label() if h.can_redo() else "Redo")
	edit_menu.set_item_disabled(i, not h.can_redo())
	var scene_menu := _menu("Scene")
	if scene_menu != null:
		scene_menu.set_item_checked(scene_menu.get_item_index(S_FOG), ctx.scene_id != "" and ctx.state.fog_enabled(ctx.scene_id))
	var tm := _menu("Turns")
	if tm != null:
		var mode := str(ctx.encounter().turns.get("mode", "free"))
		for pair in [[T_FREE, "free"], [T_DM, "dm"], [T_ORDERED, "ordered"]]:
			tm.set_item_checked(tm.get_item_index(pair[0]), mode == pair[1])
	_native_menus.sync_all()
	_update_title()


func _menu(p_name: String) -> PopupMenu:
	var bar := _ui_root.get_child(0) as MenuBar
	return bar.get_node_or_null(p_name) as PopupMenu


func _on_menu(id: int) -> void:
	var frame := Engine.get_process_frames()
	if _last_menu[0] == id and _last_menu[1] == frame:
		return
	_last_menu = [id, frame]
	if id >= V_THEME_BASE and id < V_THEME_BASE + ThemeBuilder.names().size():
		app.set_theme(ThemeBuilder.names()[id - V_THEME_BASE])
		return
	if id >= V_SCALE_BASE and id < V_SCALE_BASE + App.UI_SCALES.size():
		app.set_ui_scale(float(App.UI_SCALES[id - V_SCALE_BASE]))
		return
	if id >= V_PLAYER_BASE and id < V_PLAYER_BASE + viewpoint_select.item_count:
		_set_viewpoint(str(viewpoint_select.get_item_metadata(id - V_PLAYER_BASE)))
		return
	var sid := ctx.scene_id
	match id:
		M_NEW: _new_encounter_dialog()
		M_OPEN: _open_dialog()
		M_SAVE: _save(false)
		M_SAVE_AS: _save(true)
		M_ADD_SCENE: _add_scene_dialog()
		M_NEW_CAMPAIGN: _new_campaign_dialog()
		M_OPEN_CAMPAIGN: _open_campaign_dialog()
		M_SAVE_CAMPAIGN: _save(false)
		M_CLOSE_CAMPAIGN: _close_campaign()
		M_RECAP: _recap_dialog()
		M_CHECKPOINT:
			_prompt("Checkpoint", "Name", "Checkpoint %d" % (ctx.encounter().checkpoints.size() + 1), func(v: String) -> void:
				ctx.say("Marked " + v if ctx.kernel.checkpoint(v if v.strip_edges() != "" else "Checkpoint") != "" else "Could not mark a checkpoint"))
		M_BULK: _bulk_dialog()
		M_IMPROVISE: _improvise_dialog()
		M_HOME: _guard_unsaved(func() -> void: go_home.emit())
		M_QUIT: request_quit()
		M_UNDO: ctx.history.undo()
		M_REDO: ctx.history.redo()
		M_DELETE:
			var ids := ctx.selected_token_ids()
			if not ids.is_empty():
				ctx.commands.remove_tokens(sid, ids)
		M_HIDE:
			var ev := InputEventKey.new()
			ev.keycode = KEY_H
			ev.pressed = true
			if view.tool != null:
				view.tool.key(ev)
		M_SELECT_ALL:
			var sel := []
			for t in ctx.state.tokens(sid):
				sel.append({"kind": "token", "id": t.id})
			ctx.set_selection(sel)
			_select_tool("select")
		V_GRID, V_WALLS, V_LIGHTS, V_NOTES, V_TOKENS, V_FOG, V_HIDDEN:
			var idx := view_menu.get_item_index(id)
			var on := not view_menu.is_item_checked(idx)
			view_menu.set_item_checked(idx, on)
			match id:
				V_GRID: view.canvas.show_grid = on
				V_WALLS: view.canvas.show_walls = on
				V_LIGHTS: view.canvas.show_lights = on
				V_NOTES: view.canvas.show_notes = on
				V_TOKENS: view.canvas.show_tokens = on
				V_FOG: view.canvas.show_fog = on
				V_HIDDEN: view.canvas.show_hidden = on
			view.canvas.refresh()
		V_FIT: view.zoom_to_fit()
		V_100: view.set_zoom(1.0)
		V_DOCK: _reset_layout()
		V_LOOKUP:
			_prepare_lookup()
			lookup.open()
		V_SCALE_UP: app.step_ui_scale(true)
		V_SCALE_DOWN: app.step_ui_scale(false)
		S_SHOW:
			if sid != "":
				ctx.commands.activate_scene(sid)
		S_RENAME:
			if sid != "":
				_prompt("Rename scene", "Name", str(ctx.scene().get("name", "")), func(v: String) -> void: ctx.commands.rename_scene(sid, v))
		S_REMOVE:
			if sid != "":
				_confirm("Remove '%s' from the encounter? Its tokens go with it." % str(ctx.scene().get("name", "")), func() -> void: ctx.commands.remove_scene(sid))
		S_FOG:
			if sid != "":
				ctx.commands.set_fog(sid, not ctx.state.fog_enabled(sid))
		S_RESET_FOG:
			if sid != "":
				ctx.commands.reset_fog(sid)
		N_HOST: _set_hosting(host == null)
		T_FREE: ctx.commands.set_turn_mode("free")
		T_DM: ctx.commands.set_turn_mode("dm")
		T_ORDERED: ctx.commands.set_turn_mode("ordered")
		T_START:
			if sid != "":
				ctx.commands.start_turns(sid)
		T_NEXT: ctx.commands.next_turn()
		T_PREV: ctx.commands.previous_turn()
		T_END: ctx.commands.stop_turns()
		H_SHORTCUTS: _shortcuts_dialog()
		H_ABOUT:
			_info("%s %s — Table\n\nRun encounters on your maps.\nSilvergrove Studios.\nGodot %s" % [App.NAME, App.build_stamp(), Engine.get_version_info().string])


# =================================================================== hosting ==

func _set_hosting(on: bool) -> void:
	if on and host == null:
		host = HostSession.new(ctx.state, app.packs)
		host.kernel = ctx.kernel
		host.plugins = ctx.host
		host.apply_request = _apply_player_request
		host.log.connect(ctx.say)
		host.announcer.answered.connect(func(ip: String) -> void:
			ctx.say("Answered a player looking for tables at %s" % ip)
			print("discovery: answered %s" % ip))
		host.client_joined.connect(func(_p: String) -> void: _refresh_online())
		host.client_left.connect(func(_p: String) -> void: _refresh_online())
		var err := host.start()
		if err != OK:
			_info("Could not start hosting: %s" % error_string(err))
			host = null
			on = false
		else:
			# The OS's mDNS responder owns port 5353 on macOS and Linux; register
			# with it so Bonjour queries — reflected across subnets — get answered.
			if not host.announcer.mdns.listening() and bonjour.available():
				bonjour.register(ctx.encounter().name, host.port)
			var how := host.announcer.summary()
			if bonjour.registered():
				how = "Bonjour via %s, %s" % [bonjour.tool, how]
			ctx.say("Hosting '%s' at %s (%s)" % [ctx.encounter().name, host_address(), how])
			print("hosting '%s' at %s (%s)" % [ctx.encounter().name, host_address(), how])
			_refresh_online()
	elif not on and host != null:
		host.stop()
		host = null
		bonjour.unregister()
		_refresh_online()
	host_button.set_pressed_no_signal(host != null)
	var net := _menu("Network")
	if net != null:
		net.set_item_checked(net.get_item_index(N_HOST), host != null)


## "192.168.1.5:47777" — the address to type when discovery does not work.
func host_address() -> String:
	if host == null:
		return ""
	var ips := []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.is_valid_ip_address() and not s.contains(":") and not s.begins_with("127."):
			ips.append(s)
	return "%s:%d" % [ips[0] if not ips.is_empty() else "127.0.0.1", host.port]


func _refresh_online() -> void:
	players.online.clear()
	players.cogm_code = host.cogm_code if host != null else ""
	players.cogm_count = host.cogm_count() if host != null else 0
	if host != null:
		for p in host.connected_players():
			players.online[p] = true
	players.refresh()
	campaign_panel.refresh()


# ================================================================== campaign ==

func _new_campaign_dialog() -> void:
	_guard_unsaved(func() -> void:
		_prompt("New campaign", "Name", "New campaign", func(v: String) -> void:
			var c := Campaign.create(v if v.strip_edges() != "" else "Untitled campaign")
			var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.campaign ; Campaigns"])
			fd.current_file = c.name.to_lower().replace(" ", "_") + ".campaign"
			fd.file_selected.connect(func(path: String) -> void:
				if path.get_extension() == "":
					path += ".campaign"
				var err := c.save(path)
				if err != OK:
					_info("Could not save the campaign: " + error_string(err))
					return
				_open_campaign(c)
				ctx.say("Campaign '%s' created. Add the party in the Session pane, and a map as a scene when there is somewhere to be." % c.name))
			fd.popup_centered_ratio(0.7)))


func _open_campaign_dialog() -> void:
	_guard_unsaved(func() -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.campaign ; Campaigns"])
		fd.file_selected.connect(_open_campaign_path)
		fd.popup_centered_ratio(0.7))


## A campaign file (the autosave beside it, when newer and the DM wants it).
func _open_campaign_path(path: String) -> void:
	var err: Array = []
	var c := Campaign.load_file(path, err)
	if c == null:
		_info("Could not open %s:\n%s" % [path, "\n".join(PackedStringArray(err))])
		return
	var auto := path + ".autosave"
	if FileAccess.file_exists(auto) and FileAccess.get_modified_time(auto) > FileAccess.get_modified_time(path):
		_confirm("An autosave newer than this campaign exists. Restore it?", func() -> void:
			var c2 := Campaign.load_file(auto, err)
			if c2 != null:
				c2.path = path
				c2.dirty = true
				_open_campaign(c2)
				ctx.say("Restored the autosave. Save to keep it."),
			func() -> void: _open_campaign(c))
		return
	_open_campaign(c)


## Make a campaign the live document.
func _open_campaign(c: Campaign) -> void:
	var warn := ctx.open_campaign(c)
	if ctx.state.encounter.changed.is_connected(_on_encounter_changed):
		ctx.state.encounter.changed.disconnect(_on_encounter_changed)
	ctx.state.encounter.changed.connect(_on_encounter_changed)
	if host != null:
		host.set_state(ctx.state)
		host.kernel = ctx.kernel
		host.plugins = ctx.host
	_bind_panels()
	_refresh_scene_select()
	_refresh_viewpoints()
	view.show_scene()
	ctx.selection_changed.emit()
	_show_picker(false)
	if c.path != "":
		app.note_recent(c.path)
	if warn != "":
		_info("Opened with problems:\n\n" + warn)
	ctx.say("Campaign '%s' open: %d players, %d characters, session %d" % [c.name, c.players.size(), c.actors.size(), int(c.clock.get("session", 0))])
	_update_title()
	_update_menus()


func _close_campaign() -> void:
	_guard_unsaved(func() -> void:
		if host != null:
			_set_hosting(false)
		ctx.campaign = null
		_set_encounter(Encounter.create("Untitled encounter"))
		_show_picker(true))


## The recap as Markdown: shown, and saved beside the encounter on request.
func _recap_dialog() -> void:
	var form := PropertyForm.new()
	form.build([{"key": "who", "label": "For", "type": "enum", "options": ["the players", "the GM"]}], {"who": "the players"})
	_form_dialog("Session recap", form, func(v: Dictionary) -> void:
		var audience := "gm" if str(v.who) == "the GM" else "all"
		var md := Recap.markdown(ctx.encounter(), audience)
		var d := AcceptDialog.new()
		d.title = "Recap"
		d.min_size = Vector2i(560, 480)
		var box := VBoxContainer.new()
		var te := TextEdit.new()
		te.text = md
		te.custom_minimum_size = Vector2(540, 400)
		te.size_flags_vertical = Control.SIZE_EXPAND_FILL
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		box.add_child(te)
		d.add_child(box)
		d.ok_button_text = "Close"
		var save := d.add_button("Save as…", false, "save")
		save.pressed.connect(func() -> void:
			var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.md ; Markdown"])
			fd.current_file = "%s_session_%d_%s.md" % [ctx.encounter().name.to_lower().replace(" ", "_"), int(ctx.encounter().clock.get("session", 1)), audience]
			fd.file_selected.connect(func(path: String) -> void:
				var f := FileAccess.open(path, FileAccess.WRITE)
				if f != null:
					f.store_string(te.text)
					f.close()
					ctx.say("Recap saved to " + path)
				else:
					_info("Could not write " + path))
			fd.popup_centered_ratio(0.7))
		d.confirmed.connect(d.queue_free)
		d.canceled.connect(d.queue_free)
		d.close_requested.connect(d.queue_free)
		add_child(d)
		d.popup_centered())


# ===================================================================== bulk ==

## One thing done to every selected token, as one undo step.
func _bulk_dialog() -> void:
	var ids := ctx.selected_token_ids()
	if ids.is_empty():
		ctx.say("Select the tokens first")
		return
	var plugins := []
	if ctx.host != null:
		plugins = ctx.host.plugins.keys()
		plugins.sort()
	plugins.append(Improv.TABLE_PLUGIN)
	var form := PropertyForm.new()
	form.build([
		{"key": "what", "label": "Do", "type": "enum", "options": ["Change a pool", "Roll for each, then change a pool", "Move together", "Hide", "Reveal", "Remove"]},
		{"key": "plugin", "label": "Ruleset", "type": "enum", "options": plugins},
		{"key": "pool", "label": "Pool", "type": "string"},
		{"key": "delta", "label": "Change (− spends)", "type": "float", "step": 1},
		{"key": "spec", "label": "Roll", "type": "string"},
		{"key": "dc", "label": "Against", "type": "int"},
		{"key": "fail_delta", "label": "On failure", "type": "float", "step": 1},
		{"key": "success_delta", "label": "On success", "type": "float", "step": 1},
		{"key": "dx", "label": "Move by x", "type": "float", "step": 0.5},
		{"key": "dy", "label": "Move by y", "type": "float", "step": 0.5},
	], {"what": "Change a pool", "plugin": plugins[0], "pool": "hp", "delta": -5.0, "spec": "1d20", "dc": 12, "fail_delta": -8.0, "success_delta": -4.0, "dx": 0.0, "dy": 0.0})
	_form_dialog("Bulk on %d token%s" % [ids.size(), "" if ids.size() == 1 else "s"], form, func(v: Dictionary) -> void:
		var op := {}
		match str(v.what):
			"Change a pool": op = {"kind": "resource", "plugin": str(v.plugin), "name": str(v.pool), "delta": float(v.delta)}
			"Roll for each, then change a pool":
				var hit := [{"kind": "resource", "plugin": str(v.plugin), "name": str(v.pool), "delta": float(v.fail_delta)}]
				var miss := [{"kind": "resource", "plugin": str(v.plugin), "name": str(v.pool), "delta": float(v.success_delta)}]
				op = {"kind": "roll", "spec": str(v.spec), "ctx": {"kind": "save", "dc": int(v.dc)}, "label": "Save",
					"per": {"failure": hit, "critical_failure": hit, "fumble": hit, "success": miss, "critical": miss, "critical_success": miss, "": hit}}
			"Move together": op = {"kind": "move", "delta": [float(v.dx), float(v.dy)]}
			"Hide": op = {"kind": "set", "changes": {"hidden": true}}
			"Reveal": op = {"kind": "set", "changes": {"hidden": false}}
			"Remove": op = {"kind": "remove"}
		var r := Bulk.run(ctx.kernel, Bulk.refs_for_tokens(ids), op, "Bulk: " + str(v.what))
		if not r.ok:
			ctx.say("Bulk refused: " + r.why)
			return
		var bits := PackedStringArray()
		for res in r.results:
			if res.has("outcome"):
				bits.append("%s %s" % [str(ctx.state.find_token(str(res.ref).substr(6)).get("name", res.ref)), str(res.outcome)])
		ctx.say("%s on %d token%s%s" % [str(v.what), ids.size(), "" if ids.size() == 1 else "s", (": " + ", ".join(bits)) if not bits.is_empty() else ""]))


# ================================================================ improvise ==

## A creature from a ruleset's benchmark, or a number-only token, placed
## beside the selection or at the middle of the view.
func _improvise_dialog() -> void:
	if ctx.scene_id == "" or ctx.map() == null:
		ctx.say("Add a scene first")
		return
	var benchmarks := Improv.benchmarks(ctx.host)
	var options := ["Numbers only"]
	for b in benchmarks:
		options.append("%s — %s" % [str(b.plugin), str(b.label)])
	var form := PropertyForm.new()
	form.build([
		{"key": "kind", "label": "From", "type": "enum", "options": options},
		{"key": "name", "label": "Name (blank: invent one)", "type": "string"},
		{"key": "numbers", "label": "Numbers (hp=12, ac=15)", "type": "string"},
		{"key": "level", "label": "Level", "type": "int", "min": 0, "max": 30},
		{"key": "role", "label": "Role / variant", "type": "string"},
		{"key": "hidden", "label": "Hidden from players", "type": "bool"},
	], {"kind": options[0], "name": "", "numbers": "hp=10, ac=12", "level": 1, "role": "", "hidden": true})
	_form_dialog("Improvise", form, func(v: Dictionary) -> void:
		var pos := view.screen_to_hex(view.size * 0.5)
		var sel := ctx.selected_token()
		if not sel.is_empty():
			pos = Vision.token_pos(sel) + Vector2(1, 0)
		var opts := {"hidden": bool(v.hidden), "name": str(v.name).strip_edges()}
		if opts.name == "":
			opts.erase("name")
		var r := {}
		var idx := options.find(str(v.kind))
		if idx <= 0:
			var numbers := {}
			for part in str(v.numbers).split(",", false):
				var kv := part.split("=")
				if kv.size() == 2 and kv[1].strip_edges().is_valid_float():
					numbers[kv[0].strip_edges()] = float(kv[1].strip_edges())
			r = Improv.quick(ctx.kernel, str(opts.get("name", "")), numbers, ctx.scene_id, pos, opts)
		else:
			var b: Dictionary = benchmarks[idx - 1]
			var params := {}
			var props: Dictionary = b.params
			if props.has("level"):
				params.level = int(v.level)
			for k in props:
				if k != "level" and str(v.role) != "":
					params[k] = str(v.role)
					break
			r = Improv.spawn(ctx.kernel, str(b.plugin), str(b.name), params, ctx.scene_id, pos, opts)
		if r.has("error"):
			ctx.say("Improvise: " + str(r.error))
			return
		ctx.select_token(str(r.token))
		ctx.say("%s is on the table" % str(ctx.encounter().actor(str(r.actor)).get("name", "It"))))


## A player's request, applied through the table's commands so it is one
## undo step for the DM and explores fog like the DM's own moves.
func _apply_player_request(ev: Dictionary, pid: String) -> String:
	# an empty player id is a co-GM: the request is the Table's own
	var who := str(ctx.encounter().player(pid).get("name", "player")) if pid != "" else "co-GM"
	if str(ev.get("t", "")) == "token.set" and (ev.get("changes", {}) as Dictionary).has("pos"):
		var tk := ctx.state.token(str(ev.scene), str(ev.id))
		var pos: Array = ev.changes.pos
		ctx.commands.begin_group()
		var why := ctx.commands.move_token(str(ev.scene), str(ev.id), Vector2(float(pos[0]), float(pos[1])), pid if pid != "" else "gm")
		if why == "" and ev.changes.size() > 1:
			var rest: Dictionary = ev.changes.duplicate()
			rest.erase("pos")
			why = ctx.commands.run({"t": "token.set", "scene": str(ev.scene), "id": str(ev.id), "changes": rest})
		ctx.commands.end_group("%s moves %s" % [who, str(tk.get("name", "token"))])
		return why
	return ctx.commands.run(ev, who)


# ====================================================================== files ==

## A scratch encounter with no campaign: what the Table ran before
## campaigns. Kept for tests and the command line; the picker offers a
## campaign instead.
func _new_encounter_dialog() -> void:
	_guard_unsaved(func() -> void:
		_prompt("New encounter", "Name", "New encounter", func(v: String) -> void:
			ctx.campaign = null
			_set_encounter(Encounter.create(v if v.strip_edges() != "" else "Untitled encounter"))
			_show_picker(false)
			ctx.say("New encounter. Add a map as a scene to begin (Ctrl/Cmd+M).")))


## Pick a map file, then which of its levels, and add it as a scene.
func _add_scene_dialog() -> void:
	var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.hexmap ; Hex maps", "*.json ; Map JSON"])
	fd.file_selected.connect(func(path: String) -> void:
		var err: Array = []
		var m := HexMap.load_file(path, err)
		if m == null:
			_info("Could not open %s:\n%s" % [path, "\n".join(PackedStringArray(err))])
			return
		var levels := []
		for l in m.levels:
			levels.append(str(l.get("name", l.id)))
		var form := PropertyForm.new()
		form.build([
			{"key": "level", "label": "Level", "type": "enum", "options": levels},
			{"key": "name", "label": "Scene name", "type": "string"},
			{"key": "fog", "label": "Fog of war", "type": "bool"},
		], {"level": levels[0], "name": m.name, "fog": true})
		_form_dialog("Add scene from " + m.name, form, func(v: Dictionary) -> void:
			var li := levels.find(str(v.level))
			var lvl_id := str(m.level(maxi(li, 0)).id)
			var rel := _relative_map_path(path)
			var scene := Encounter.new_scene(m, lvl_id, str(v.name), rel)
			scene.fog.enabled = bool(v.fog)
			ctx.state.attach_map(m)
			ctx.commands.add_scene(scene, ctx.encounter().scenes.size() == 0)
			ctx.set_scene(str(scene.id))
			ctx.say("Added scene '%s'" % str(scene.name))))
	fd.popup_centered_ratio(0.7)


## Map paths are stored relative to the encounter file when it has one.
func _relative_map_path(map_path: String) -> String:
	var base := ctx.encounter().base_dir()
	if base == "":
		return map_path
	if map_path.begins_with(base + "/"):
		return map_path.substr(base.length() + 1)
	return map_path


func _open_dialog() -> void:
	_guard_unsaved(func() -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.encounter ; Encounters"])
		fd.file_selected.connect(_open_path)
		fd.popup_centered_ratio(0.7))


## A path of either kind: a campaign opens; an encounter is imported as
## a campaign of its own (unsaved until the DM saves it as one).
func _open_path(path: String) -> void:
	if path.ends_with(".campaign"):
		_open_campaign_path(path)
		return
	var err: Array = []
	var e := Encounter.load_file(path, err)
	if e == null:
		_info("Could not open %s:\n%s" % [path, "\n".join(PackedStringArray(err))])
		return
	var auto := path + ".autosave"
	if FileAccess.file_exists(auto) and FileAccess.get_modified_time(auto) > FileAccess.get_modified_time(path):
		_confirm("An autosave newer than this file exists. Restore it?", func() -> void:
			var e2 := Encounter.load_file(auto, err)
			if e2 != null:
				e2.path = path
				e2.dirty = true
				_load(e2)
				ctx.say("Restored autosave. Save to keep it."),
			func() -> void: _load(e))
		return
	_load(e)
	ctx.say("Opened " + path)


## An encounter file becomes a campaign of its own: its players and
## persistent actors are the campaign's, the encounter is its runtime.
## Unless it names a campaign beside it, which is opened instead with
## the encounter as a session in it (the version-1 way).
func _load(e: Encounter) -> void:
	var c := Campaign.for_encounter(e)
	if c == null:
		c = Campaign.create(e.name)
		c.doc.id = str(e.campaign.get("id", "")) if str(e.campaign.get("id", "")) != "" else c.id
		e.doc.campaign.id = c.id
		for p in e.players:
			c.players.append(JsonDoc.deep(p))
	ctx.campaign = c
	_set_encounter(e)
	var warn := ctx.state.resolve_maps()
	view.show_scene()
	_show_picker(false)
	app.note_recent(e.path)
	if not warn.is_empty():
		_info("Opened with problems:\n\n" + "\n".join(warn))
	if c.path == "":
		ctx.say("Imported the encounter '%s' as a campaign. Save it as a campaign to keep the party between sessions." % e.name)
	_update_title()


## Save the campaign (the live state captured into it). A campaign with
## no file yet — one made from an imported encounter — asks where. A
## scratch encounter with no campaign saves as an encounter file.
func _save(as_new: bool) -> void:
	if ctx.campaign == null:
		if ctx.encounter().path == "" or as_new or ctx.encounter().path.begins_with("res://"):
			var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.encounter ; Encounters"])
			fd.current_file = ctx.encounter().name.to_snake_case() + ".encounter"
			fd.file_selected.connect(func(p: String) -> void: _save_to(p))
			fd.popup_centered_ratio(0.7)
			return
		_save_to(ctx.encounter().path)
		return
	if ctx.campaign.path == "" or as_new or ctx.campaign.path.begins_with("res://"):
		var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.campaign ; Campaigns"])
		fd.current_file = ctx.campaign.name.to_snake_case() + ".campaign"
		fd.file_selected.connect(func(p: String) -> void: _save_campaign_to(p))
		fd.popup_centered_ratio(0.7)
		return
	_save_campaign_to(ctx.campaign.path)


func _save_campaign_to(path: String) -> void:
	if path.get_extension() == "":
		path += ".campaign"
	var first := ctx.campaign.path == "" or ctx.campaign.path != path
	if first:
		# now that it has a home, the scenes' map paths are relative to it
		var e := ctx.encounter()
		var old_base := e.base_dir()
		for s in e.scenes:
			var mp := str(s.get("map_path", ""))
			if mp != "" and not mp.is_absolute_path() and not mp.begins_with("res://") and old_base != "":
				mp = old_base.path_join(mp)
			s["map_path"] = mp
		ctx.campaign.path = path
		e.path = path
		for s in e.scenes:
			s["map_path"] = _relative_map_path(str(s.get("map_path", "")))
	var why := ctx.save_campaign(path)
	if why != "":
		_info("Save failed: %s" % why)
		return
	DirAccess.remove_absolute(path + ".autosave")
	_update_title()
	app.note_recent(path)
	ctx.say("Saved " + path)


func _save_to(path: String) -> void:
	if path.get_extension() == "":
		path += ".encounter"
	var e := ctx.encounter()
	var first := e.path == ""
	e.path = path
	if first:
		# Now that it has a home, store map paths relative to it.
		for s in e.scenes:
			s["map_path"] = _relative_map_path(str(s.get("map_path", "")))
	var err := e.save(path)
	if err != OK:
		_info("Save failed: %s" % error_string(err))
		return
	DirAccess.remove_absolute(path + ".autosave")
	_update_title()
	app.note_recent(path)
	ctx.say("Saved " + path)


## Every minute: the campaign, live state included, beside its file; a
## scratch encounter beside its own.
func _autosave_now() -> void:
	var e := ctx.encounter()
	if e == null:
		return
	if ctx.campaign != null:
		if not ctx.campaign_dirty() or ctx.campaign.path == "":
			return
		ctx.campaign.capture(e)
		var f := FileAccess.open(ctx.campaign.path + ".autosave", FileAccess.WRITE)
		if f != null:
			f.store_string(ctx.campaign.to_json())
			f.close()
		return
	if not e.dirty or e.path == "":
		return
	var f := FileAccess.open(e.path + ".autosave", FileAccess.WRITE)
	if f != null:
		f.store_string(e.to_json())
		f.close()


func _guard_unsaved(then: Callable) -> void:
	var e := ctx.encounter()
	if e == null or not ctx.campaign_dirty():
		then.call()
		return
	var d := ConfirmationDialog.new()
	d.title = "Unsaved changes"
	d.dialog_text = "'%s' has unsaved changes. Discard them?" % (ctx.campaign.name if ctx.campaign != null else e.name)
	d.ok_button_text = "Discard"
	d.confirmed.connect(then)
	d.close_requested.connect(d.queue_free)
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


func request_quit() -> void:
	_guard_unsaved(func() -> void: get_tree().quit())


func _exit_tree() -> void:
	_autosave.stop()
	if host != null:
		host.stop()
		host = null
	bonjour.unregister()
	if dock != null and is_instance_valid(dock):
		LayoutStore.save(dock.layout, LayoutStore.table_path())
	_native_menus.free_menus()
	if app != null and app.theme_changed.is_connected(_on_theme_changed):
		app.theme_changed.disconnect(_on_theme_changed)
	if app != null and app.ui_scale_changed.is_connected(_on_ui_scale):
		app.ui_scale_changed.disconnect(_on_ui_scale)
	ctx.history.clear()
	if view != null:
		view.set_tool(null)
	ctx.commands = null
	ctx.canvas = null


# ==================================================================== dialogs ==

func _file_dialog(mode: FileDialog.FileMode, filters: Array) -> FileDialog:
	var fd := FileDialog.new()
	fd.file_mode = mode
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	for f in filters:
		fd.add_filter(f.split(";")[0].strip_edges(), f.split(";")[1].strip_edges() if f.contains(";") else "")
	if ctx.encounter().path != "":
		fd.current_dir = ctx.encounter().base_dir()
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
	for t in TableTools.all_tools():
		lines.append("%s — %s: %s" % [t.key, t.label, t.hint])
	lines.append("")
	lines.append("Space+drag or middle-drag: pan · wheel: zoom · Ctrl/Cmd+0: fit · Ctrl/Cmd+1: 100%")
	lines.append("Ctrl/Cmd+Z / Shift+Ctrl/Cmd+Z: undo / redo · Ctrl/Cmd+S: save · Ctrl/Cmd+M: add a map")
	lines.append("H: hide / reveal selected tokens · Delete: remove them · Ctrl/Cmd+Space: next turn (ordered) · Shift+F: fog on/off · Esc: select tool")
	_info("\n".join(lines))
