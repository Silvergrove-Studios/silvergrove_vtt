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
## Scene › Light: as the map, then Vision.LIGHT_LEVELS in order (clear of
## the viewpoints' ids, however many players).
const S_LIGHT_BASE := 3000
const LIGHT_CHOICES := [["", "As the map"], ["daylight", "Daylight"], ["dim", "Dim"], ["dark", "Dark"]]
var light_menu: PopupMenu

var app: App
var ctx := TableContext.new()
var host: HostSession
## The ports the table is hosted on (a test harness may move them).
var host_port := Protocol.DEFAULT_PORT
var web_port := WebServer.DEFAULT_PORT
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
var party_pane: PartyPane
var reference: ReferencePanel
## The mode buttons (World, Fight, Prep) and the session bar's parts.
var mode_buttons: Dictionary = {}
var _session_bar: Control
var _tools_row: Control
var _opts_panel: Control
var _banner: PanelContainer
var _banner_label: Label
var _banner_action: Button
var _banner_hidden := false
## The DM's web screen (WebDm) and the token its address carries.
var web_dm: WebDm
var _dm_token := ""
var _campaign_label: Label
var _session_label: Label
var _session_button: Button
var _show_players: Button
var _fight_button: Button
## Each mode's layout, loaded when the mode is first used.
var _layouts: Dictionary = {}
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
## What this window shows while a game runs: the game is running, the DM's
## screen is in the browser, how players join (playtest 2: the whole Table
## at once read as Photoshop). The full Table is a press away.
var _running: Control
var _full_table := false
## The last address opened in the browser (for tests: no browser opens there).
var last_opened := ""
var _picker_recent: VBoxContainer
var _picker_packages: VBoxContainer
var _picker_continue: VBoxContainer

enum { M_NEW, M_OPEN, M_SAVE, M_SAVE_AS, M_ADD_SCENE, M_HOME, M_QUIT,
	M_NEW_CAMPAIGN, M_OPEN_CAMPAIGN, M_SAVE_CAMPAIGN, M_RECAP, M_CLOSE_CAMPAIGN, M_FROM_PACKAGE, M_EXPORT_PACKAGE, M_DUPLICATE, M_REVIEW_UPDATE, M_RESTORE_POINT,
	M_UNDO, M_REDO, M_DELETE, M_SELECT_ALL, M_HIDE, M_CHECKPOINT, M_BULK, M_IMPROVISE,
	V_GRID, V_WALLS, V_LIGHTS, V_NOTES, V_TOKENS, V_FOG, V_HIDDEN, V_FIT, V_100, V_DOCK, V_SCALE_UP, V_SCALE_DOWN, V_LOOKUP, V_WORLD, V_FIGHT, V_PREP, V_RUNNING, V_DM_SCREEN,
	S_SHOW, S_RENAME, S_REMOVE, S_FOG, S_RESET_FOG, N_HOST,
	T_FREE, T_DM, T_ORDERED, T_START, T_NEXT, T_PREV, T_END,
	H_SHORTCUTS, H_ABOUT }


func _ready() -> void:
	if app == null:
		app = App.new()
	ctx.app = app
	_dm_token = "%08x%08x" % [randi(), randi()]
	web_dm = WebDm.new(self)
	# a dialog closing (a native file dialog above all, on macOS) can leave the
	# Table's window not the key window: it then ignores clicks and hover until
	# the app menu is used (playtest 1). Every dialog hands focus back.
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is Window and n != get_window() and not (n is PopupMenu) and not (n as Window).visibility_changed.is_connected(_on_dialog_visibility):
			(n as Window).visibility_changed.connect(_on_dialog_visibility.bind(n)))
	_refocus.call_deferred()
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
	ctx.campaign_changed.connect(_update_menus)
	ctx.campaign_changed.connect(func() -> void:
		_refresh_scene_select()
		_update_session_bar()
		_update_banner()
		if host != null:
			host.refresh_views()
			host.refresh_dm())
	_update_menus()
	_autosave.wait_time = AUTOSAVE_SECONDS
	_autosave.timeout.connect(_autosave_now)
	add_child(_autosave)
	_autosave.start()
	_layout_save.wait_time = 2.0
	_layout_save.one_shot = true
	_layout_save.timeout.connect(func() -> void: LayoutStore.save(dock.layout, LayoutStore.table_path(ctx.mode)))
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
		host.packs = ctx.art
	if view != null:
		_bind_panels()
		_refresh_scene_select()
		_refresh_viewpoints()
		view.show_scene()
		ctx.selection_changed.emit()
	_update_title()


func _bind_panels() -> void:
	for p in [scenes, tokens, inspector, turns, rules, compendium, players, campaign_panel, party, npcs, notes, maps, party_pane, reference]:
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
	if what in ["clock", "scenes", "active_scene", "players", "actors", "restore", "encounter"]:
		_update_session_bar()
		_update_banner()
		if host != null:
			host.refresh_dm()
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
	_session_bar = _build_session_bar()
	root.add_child(_session_bar)
	_banner = _build_banner()
	root.add_child(_banner)
	_tools_row = _build_toolbar()
	root.add_child(_tools_row)
	_opts_panel = PanelContainer.new()
	_opts_panel.theme_type_variation = "DockHeader"
	_opts_panel.add_child(_build_tool_options())
	root.add_child(_opts_panel)

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
	campaign_panel.on_show_maps = _show_maps_pane
	campaign_panel.on_join_info = _join_info
	campaign_panel.on_start_session = _toggle_session
	campaign_panel.host_info = _host_info
	party = RosterPanel.new(ctx, true)
	npcs = RosterPanel.new(ctx, false)
	notes = NotesPanel.new(ctx)
	maps = MapsPanel.new(ctx)
	party_pane = PartyPane.new(ctx)
	reference = ReferencePanel.new(ctx)
	reference.go_place = func(pid: String) -> void: ctx.say(maps.go_to_place(pid))
	reference.show_map = func(mid: String) -> void: ctx.say(maps.show_map(mid))
	reference.pick_picture_file = func(then: Callable) -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.png, *.jpg, *.jpeg, *.webp, *.svg ; Pictures"])
		fd.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		fd.file_selected.connect(then)
		fd.popup_centered_ratio(0.7)
	ctx.show_ref = func(ref: String) -> void:
		reference.open(ref)
		_reveal_pane("Reference")
	# a fight launched is a fight on screen; back from it, the world again
	# (a fight goes in turns, ready for the DM to Start once the scene is set;
	# afterwards everyone moves freely again)
	maps.fight_started.connect(func(_enc: String) -> void:
		if str(ctx.encounter().turns.get("mode", "free")) == "free":
			ctx.commands.set_turn_mode("ordered")
		set_mode("fight"))
	maps.fight_ended.connect(func(_enc: String) -> void:
		if bool(ctx.encounter().turns.get("running", false)):
			ctx.commands.stop_turns()
		ctx.commands.set_turn_mode("free")
		set_mode("world"))
	lookup = LookupPopup.new()
	add_child(lookup)
	# a rule looked up from a sheet opens in the Reference pane, the DM's book
	ctx.lookup = func(collection: String, id: String) -> void:
		if dock != null and not dock.layout.is_tab_hidden("Reference"):
			ctx.show_ref.call("entry:%s/%s" % [collection, id])
			return
		_prepare_lookup()
		lookup.show_entry(collection, id)
	compendium.pick_content_file = func(then: Callable) -> void:
		var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_ANY, ["*.json ; Packs and entry files"])
		# the table's library is where loose packs wait to be imported
		DirAccess.make_dir_recursive_absolute(ctx.library_dir)
		fd.current_dir = ProjectSettings.globalize_path(ctx.library_dir)
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
	_running = _build_running()
	stack.add_child(_running)
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
		DockPane.new("Characters", party, party.header_actions()),
		DockPane.new("NPCs", npcs, npcs.header_actions()),
		DockPane.new("Notes", notes),
		DockPane.new("Maps", maps),
		DockPane.new("Party", party_pane),
		DockPane.new("Reference", reference),
	]
	for p in _panes:
		dock.add_child(p)
	dock.layout = _layout_for(ctx.mode)
	return dock


## A mode's layout, loaded (as the user left it, or the default) the first time.
func _layout_for(mode: String) -> DockableLayout:
	if not _layouts.has(mode):
		var layout := LayoutStore.load_table_mode(mode)
		layout.changed.connect(func() -> void: _layout_save.start())
		_layouts[mode] = layout
	return _layouts[mode]


## Switch what the Table shows: "world" (the party, the map, the reference),
## "fight" (turns, tokens, stat blocks) or "prep" (every pane).
func set_mode(mode: String) -> void:
	if not LayoutStore.TABLE_MODES.has(mode):
		return
	ctx.mode = mode
	if dock != null:
		dock.layout = _layout_for(mode)
	for m in mode_buttons:
		(mode_buttons[m] as Button).set_pressed_no_signal(m == mode)
	_sync_chrome()
	if mode == "world" and _tool_name != "select":
		_select_tool("select")
	ctx.mode_changed.emit()


## Bring a pane forward (its tab), showing it if the mode hides it.
func _reveal_pane(p_name: String) -> void:
	if dock == null:
		return
	var layout := dock.layout
	var pane: Node = null
	for p in _panes:
		if p is DockPane and str((p as DockPane).name) == p_name:
			pane = p
	var leaf := layout.get_leaf_for_node(pane) if pane != null else null
	if leaf == null:
		return
	if layout.is_tab_hidden(p_name):
		layout.set_tab_hidden(p_name, false)
	# a leaf's current tab counts the tabs shown, not the hidden ones
	var at := 0
	for n in leaf.names:
		if n == p_name:
			break
		if not layout.is_tab_hidden(n):
			at += 1
	leaf.current_tab = at


## What of the Table's chrome shows: nothing but the picker before a
## campaign is open; the map's tools only in a fight and in prep.
func _sync_chrome() -> void:
	_refresh_running()
	var picking := (_picker != null and _picker.visible) or (_running != null and _running.visible)
	if _session_bar != null:
		_session_bar.visible = not picking
	# (in the world, a tool picked by its key brings the row until Esc)
	var tools := not picking and (ctx.mode != "world" or _tool_name != "select")
	if _tools_row != null:
		_tools_row.visible = tools
	if _opts_panel != null:
		_opts_panel.visible = tools and _tool_name == "token"
	_update_banner()
	_update_session_bar()


## The line under the session bar that says what to do next, until the
## first things are done (playtest 1: "not obvious what the next steps are").
func _build_banner() -> PanelContainer:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var head := Label.new()
	head.text = "Next"
	head.theme_type_variation = "HeaderLabel"
	row.add_child(head)
	_banner_label = Label.new()
	_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_banner_label)
	_banner_action = Button.new()
	_banner_action.theme_type_variation = "AccentButton"
	row.add_child(_banner_action)
	var hide := Button.new()
	hide.text = "Hide"
	hide.theme_type_variation = "ToolButton"
	hide.tooltip_text = "Hide these hints (the Session pane in Prep keeps the list)"
	hide.pressed.connect(func() -> void:
		_banner_hidden = true
		_update_banner())
	row.add_child(hide)
	panel.visible = false
	return panel


func _update_banner() -> void:
	if _banner == null or campaign_panel == null:
		return
	var picking := (_picker != null and _picker.visible) or (_running != null and _running.visible)
	if picking or ctx.campaign == null or _banner_hidden:
		_banner.visible = false
		return
	var next := {}
	for st in campaign_panel.steps(_host_info()):
		if not bool(st.done):
			next = st
			break
	_banner.visible = not next.is_empty()
	if next.is_empty():
		return
	_banner_label.text = str(next.text)
	for c in _banner_action.pressed.get_connections():
		_banner_action.pressed.disconnect(c.callable)
	var call: Variant = next.get("call")
	_banner_action.visible = str(next.get("action", "")) != "" and call is Callable and (call as Callable).is_valid()
	if _banner_action.visible:
		_banner_action.text = str(next.action)
		_banner_action.pressed.connect(func() -> void: (call as Callable).call())


func _host_info() -> Dictionary:
	if host == null:
		return {"hosting": false}
	var names := []
	for pid in players.online:
		names.append(str(ctx.encounter().player(str(pid)).get("name", pid)))
	return {"hosting": true, "address": host_address(), "code": host.cogm_code, "connected": names}


## The campaign, its session, the modes, who can join.
func _update_session_bar() -> void:
	if _session_bar == null or _campaign_label == null:
		return
	var e := ctx.encounter()
	if ctx.campaign == null:
		_campaign_label.text = e.name
		_session_label.text = ""
		_session_button.visible = false
	else:
		_campaign_label.text = ctx.campaign.name + ("*" if ctx.campaign_dirty() else "")
		var n := int(e.clock.get("session", 0))
		var open_session := n > 0 and not ctx.campaign.session_entry(n).is_empty() and not ctx.campaign.session_entry(n).has("ended")
		_session_label.text = "Day %d, %02d:%02d" % [int(e.clock.get("day", 1)), int(e.clock.get("minute", 0)) / 60, int(e.clock.get("minute", 0)) % 60]
		_session_label.tooltip_text = ("Session %d is running" % n) if open_session else ("Between sessions (%d played)" % n)
		_session_button.visible = true
		_session_button.text = ("End session %d" % n) if open_session else ("Start session %d" % (n + 1))
		_session_button.theme_type_variation = "" if open_session else "AccentButton"
	var fight := _live_fight()
	if mode_buttons.has("fight"):
		(mode_buttons.fight as Button).text = "Fight ●" if not fight.is_empty() else "Fight"
		(mode_buttons.fight as Button).tooltip_text = ("%s is running: turns, tokens and stat blocks" % str(fight.get("name", ""))) if not fight.is_empty() else "Turns, tokens and stat blocks — a fight on the map"
	if _fight_button != null:
		_fight_button.visible = not fight.is_empty()
	if host_button != null:
		host_button.set_pressed_no_signal(host != null)
		var info := _host_info()
		host_button.text = ("%d joined" % (info.get("connected", []) as Array).size()) if host != null else "Closed"
		host_button.tooltip_text = ("Players can join from their phones (%s). Press to close the table to them." % ", ".join(PackedStringArray(info.get("connected", []))) if not (info.get("connected", []) as Array).is_empty() else "Players can join from their phones. Press to close the table to them.") if host != null else "Players cannot join now. Press to open the table to them."


## The prepared encounter running now, or {}.
func _live_fight() -> Dictionary:
	if ctx.campaign == null:
		return {}
	for enc in ctx.campaign.encounters:
		if enc is Dictionary and enc.has("live") and not (enc.live as Dictionary).is_empty():
			return enc
	return {}


## The running fight is over: Return (its creatures and scene go).
func _end_fight() -> void:
	var fight := _live_fight()
	if fight.is_empty():
		set_mode("world")
		return
	_confirm("End '%s'? Its creatures and its map go, and the map before comes back. The party keeps its wounds. Nothing is looted by itself: what they take, you give them (a character's sheet → Give an item)." % str(fight.get("name", "the fight")), func() -> void:
		var why := maps.return_from(str(fight.get("id", "")))
		ctx.say(why if why != "" else "Back from " + str(fight.get("name", "the fight"))))


func _toggle_session() -> void:
	if ctx.campaign == null:
		return
	var e := ctx.encounter()
	var n := int(e.clock.get("session", 0))
	var open_session := n > 0 and not ctx.campaign.session_entry(n).is_empty() and not ctx.campaign.session_entry(n).has("ended")
	if not open_session:
		var why := ctx.start_session()
		ctx.say(why if why != "" else "Session %d started" % int(ctx.encounter().clock.get("session", 0)))
	else:
		_confirm("End session %d? The recap is kept, the journal stamped and the campaign saved." % n, func() -> void:
			var r := ctx.end_session(Recap.markdown(ctx.encounter(), "all") if ctx.campaign_is_live() else "")
			ctx.say(str(r.get("error", "")) if str(r.get("error", "")) != "" else "Session %d ended" % n))
	_update_session_bar()
	_update_banner()


## How players somewhere else can join: the table serves the local network only.
const PLAY_APART := "Players somewhere else? Hexmap serves your local network only and does not reach them over the internet by itself. To play apart, first put this computer and their devices on one private network with a VPN app (Tailscale, ZeroTier), then send them this computer's address on it. If nobody can open the address, check that this computer's firewall lets Hexmap accept connections."


## What the players do to join: the address likeliest to work, this
## computer's others said for what they are, and how to play apart (a
## playtest's DM, her players in four places, read "the same Wi-Fi" and four
## addresses, and worried before anyone had joined).
func _join_info() -> void:
	var name := ctx.campaign.name if ctx.campaign != null else ctx.encounter().name
	if host == null:
		_info("The table is closed to players right now. Press \"Closed\" at the top to open it; then players open its address in a browser (Invite players on your screen shows it, with a code to scan).")
		return
	var info := _host_info()
	var here: Array = info.get("connected", [])
	var urls := Array(host.join_urls()) if host.web != null else []
	var text := "Players with you: scan the code, or open this address in any browser. Their phone or computer must be on the same network as this one (the same Wi-Fi or router).\n\n1. Open %s — or scan the code that Invite players shows on your screen.\n2. Type their name (or tap it, if they have played here before).\n3. Make a character (or take the one you made)." % (str(urls[0]) if not urls.is_empty() else "the address your screen shows")
	if urls.size() > 1:
		text += "\n\nOther addresses of this computer:"
		for u in urls.slice(1):
			text += "\n%s — %s" % [str(u), WebServer.address_kind(str(u))]
	text += "\n\n" + PLAY_APART
	text += "\n\nIn the Hexmap app instead: Join a game → \"%s\" (or type %s).\n\nJoined now: %s\n\nA second DM on another laptop joins with the co-DM code %s." % [
		name, str(info.get("address", "")), ", ".join(PackedStringArray(here)) if not here.is_empty() else "nobody yet", str(info.get("code", ""))]
	_info(text)


## The first screen of the Table: carry on with the last campaign, start an
## adventure (the packages in the library and in Downloads), or open, make
## or import one. (Playtest 1: the DM with a downloaded adventure could not
## find the way in among four equal buttons and the editor's chrome.)
func _build_picker() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "Run a game"
	title.theme_type_variation = "DisplayLabel"
	box.add_child(title)
	var blurb := Label.new()
	blurb.text = "A campaign keeps everything between sessions: the party, the people and places of the world, your notes, the maps. Carry on with yours, or start one."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.theme_type_variation = "DimLabel"
	box.add_child(blurb)
	_picker_continue = VBoxContainer.new()
	box.add_child(_picker_continue)
	_picker_packages = VBoxContainer.new()
	_picker_packages.add_theme_constant_override("separation", 6)
	box.add_child(_picker_packages)
	var start_file := Button.new()
	start_file.text = "Start an adventure from a file…"
	start_file.tooltip_text = "A .campaignpkg you downloaded: it becomes a campaign of your own; the file is never changed"
	start_file.alignment = HORIZONTAL_ALIGNMENT_LEFT
	start_file.pressed.connect(func() -> void: _from_package_dialog())
	box.add_child(start_file)
	var rl := Label.new()
	rl.text = "Your campaigns"
	rl.theme_type_variation = "HeaderLabel"
	box.add_child(rl)
	_picker_recent = VBoxContainer.new()
	box.add_child(_picker_recent)
	var open_b := Button.new()
	open_b.text = "Open a campaign…"
	open_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open_b.pressed.connect(_open_campaign_dialog)
	box.add_child(open_b)
	var own := Label.new()
	own.text = "Or build your own"
	own.theme_type_variation = "HeaderLabel"
	box.add_child(own)
	var actions := HFlowContainer.new()
	var new_b := Button.new()
	new_b.text = "New campaign from scratch…"
	new_b.tooltip_text = "An empty campaign: you choose the rules and add the maps, the people and the places"
	new_b.pressed.connect(_new_campaign_dialog)
	actions.add_child(new_b)
	var imp := Button.new()
	imp.text = "Import an old encounter…"
	imp.tooltip_text = "An encounter file from before campaigns: opened as a campaign of its own"
	imp.pressed.connect(_open_dialog)
	actions.add_child(imp)
	box.add_child(actions)
	var home := Button.new()
	home.text = "‹ Home"
	home.theme_type_variation = "ToolButton"
	home.pressed.connect(func() -> void: go_home.emit())
	box.add_child(home)
	return panel


func _show_picker(on: bool) -> void:
	if _picker == null:
		return
	_picker.visible = on
	_sync_chrome()
	if not on:
		return
	for box in [_picker_recent, _picker_continue]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_refresh_packages()
	var last := HomeScreen.last_campaign(app.recent())
	if last != "":
		var cont := HomeScreen.card("Continue “%s”" % HomeScreen.campaign_title(last), "The campaign you had open last: everything as you left it", "", true)
		cont.name = "Continue"
		cont.tooltip_text = last
		cont.pressed.connect(func() -> void: _open_path(last))
		_picker_continue.add_child(cont)
		HomeScreen.restyle_cards(_picker_continue, ThemeBuilder.tokens(app.theme_name))
	var any := false
	for p in app.recent():
		if not (str(p).ends_with(".campaign") or str(p).ends_with(".encounter")) or str(p) == last:
			continue
		any = true
		var b := Button.new()
		b.text = HomeScreen.campaign_title(str(p)) + ("" if str(p).ends_with(".campaign") else "  (an old encounter)")
		b.tooltip_text = str(p)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var path := str(p)
		b.pressed.connect(func() -> void: _open_path(path))
		_picker_recent.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "None yet: an adventure you start becomes one." if last == "" else "Only the one above."
		l.theme_type_variation = "DimLabel"
		_picker_recent.add_child(l)


## The lookup popup over this table's compendium and its rulesets' cards.
func _prepare_lookup() -> void:
	lookup.source = party._comp
	lookup.cards = EntryCard.cards_of(ctx.host)
	lookup.collections = ctx.kernel.comp.collections() if ctx.kernel != null else []
	lookup.role = "gm"


func _reset_layout() -> void:
	var layout := LayoutStore.table_mode_layout(ctx.mode)
	layout.changed.connect(func() -> void: _layout_save.start())
	_layouts[ctx.mode] = layout
	dock.layout = layout
	_layout_save.start()


func _build_menus() -> MenuBar:
	var bar := MenuBar.new()
	bar.flat = true
	bar.prefer_global_menu = false
	var file := PopupMenu.new()
	file.name = "File"
	_item(file, "New campaign…", M_NEW_CAMPAIGN, KEY_N, true)
	_item(file, "New from a package…", M_FROM_PACKAGE)
	_item(file, "Open campaign…", M_OPEN_CAMPAIGN, KEY_O, true)
	file.add_separator()
	_item(file, "Duplicate this campaign…", M_DUPLICATE)
	_item(file, "Export as a package…", M_EXPORT_PACKAGE)
	_item(file, "Update from its package…", M_REVIEW_UPDATE)
	file.add_separator()
	_item(file, "Save campaign", M_SAVE, KEY_S, true)
	_item(file, "Save campaign as…", M_SAVE_AS, KEY_S, true, true)
	file.add_separator()
	_item(file, "Add a map…", M_ADD_SCENE, KEY_M, true)
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
	_item(edit_menu, "Mark a restore point…", M_CHECKPOINT, KEY_K, true)
	_item(edit_menu, "Go back to a restore point…", M_RESTORE_POINT)
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
	_item(view_menu, "The game, running (how players join)", V_RUNNING)
	_item(view_menu, "Open the DM's screen in the browser", V_DM_SCREEN)
	view_menu.add_separator()
	_item(view_menu, "World — the party, the map, the reference", V_WORLD)
	_item(view_menu, "Fight — turns, tokens, stat blocks", V_FIGHT)
	_item(view_menu, "Prep — every pane", V_PREP)
	_item(view_menu, "Reset this layout", V_DOCK)
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
	# how lit the scene is: what the players see is the light's to say
	light_menu = PopupMenu.new()
	light_menu.name = "Light"
	for i in LIGHT_CHOICES.size():
		light_menu.add_radio_check_item(str(LIGHT_CHOICES[i][1]), S_LIGHT_BASE + i)
	light_menu.id_pressed.connect(_on_menu)
	scene.add_child(light_menu)
	scene.add_submenu_node_item("Light", light_menu)
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
	_check(net, "Open to players on this network", N_HOST, false)
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


## The top of the Table while a campaign is open: the campaign and its
## session, the three modes (World — the party, the map, the reference;
## Fight; Prep — every pane), what is on screen, who can join, save.
func _build_session_bar() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DockHeader"
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	panel.add_child(bar)
	_campaign_label = Label.new()
	_campaign_label.theme_type_variation = "HeaderLabel"
	bar.add_child(_campaign_label)
	_session_label = Label.new()
	_session_label.theme_type_variation = "DimLabel"
	# (it gives way first when the window is narrow)
	_session_label.clip_text = true
	_session_label.custom_minimum_size.x = 92
	bar.add_child(_session_label)
	_session_button = Button.new()
	_session_button.tooltip_text = "Start the session: the clock and the recap begin, and the rules' once-a-session things refill"
	_session_button.pressed.connect(_toggle_session)
	bar.add_child(_session_button)
	bar.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for m in [["world", "World", "The party, the map and everything to look up — exploring, talking, most of a session"],
			["fight", "Fight", "Turns, tokens and stat blocks — a fight on the map"],
			["prep", "Prep", "Every pane — maps and encounters, people, notes, characters, the compendium — for building between sessions"]]:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = m[2]
		b.focus_mode = Control.FOCUS_NONE
		var mode: String = m[0]
		b.pressed.connect(func() -> void: set_mode(mode))
		bar.add_child(b)
		mode_buttons[mode] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	scene_select = OptionButton.new()
	scene_select.custom_minimum_size.x = 170
	scene_select.clip_text = true
	scene_select.set_meta("icon", "map")
	scene_select.item_selected.connect(func(i: int) -> void:
		var sid := str(scene_select.get_item_metadata(i))
		if sid == "":
			_show_maps_pane()
		elif sid.begins_with("map:"):
			ctx.say(maps.show_map(sid.substr(4)))
		else:
			ctx.set_scene(sid))
	# (with no map at all the one item is always selected: pressing it goes to the maps)
	scene_select.pressed.connect(func() -> void:
		if ctx.encounter().scenes.is_empty() and (ctx.campaign == null or ctx.campaign.maps.is_empty()):
			scene_select.get_popup().hide.call_deferred()
			_show_maps_pane())
	bar.add_child(scene_select)
	_show_players = Button.new()
	_show_players.text = "Show to players"
	_show_players.tooltip_text = "You are looking at a map the players are not: put it on their screens too"
	_show_players.visible = false
	_show_players.pressed.connect(func() -> void:
		if has_scene():
			ctx.commands.activate_scene(ctx.scene_id))
	bar.add_child(_show_players)
	_fight_button = Button.new()
	_fight_button.text = "End the fight"
	_fight_button.tooltip_text = "The fight is over: its creatures and its map go, the party keeps its wounds, and the map before comes back"
	_fight_button.visible = false
	_fight_button.pressed.connect(_end_fight)
	bar.add_child(_fight_button)
	host_button = Button.new()
	host_button.toggle_mode = true
	host_button.set_meta("icon", "scan")
	host_button.theme_type_variation = "ToolButton"
	host_button.focus_mode = Control.FOCUS_NONE
	host_button.tooltip_text = "Whether players can join from their phones"
	host_button.toggled.connect(func(on: bool) -> void: _set_hosting(on))
	bar.add_child(host_button)
	var how := Button.new()
	how.text = "How to join"
	how.theme_type_variation = "ToolButton"
	how.focus_mode = Control.FOCUS_NONE
	how.tooltip_text = "What the players do on their phones, and this table's address"
	how.pressed.connect(_join_info)
	bar.add_child(how)
	for entry in [["save", M_SAVE, "Save the campaign (Ctrl/Cmd+S)"], ["undo-2", M_UNDO, "Undo (Ctrl/Cmd+Z)"], ["redo-2", M_REDO, "Redo (Shift+Ctrl/Cmd+Z)"]]:
		var fb := Button.new()
		fb.set_meta("icon", entry[0])
		fb.tooltip_text = entry[2]
		fb.theme_type_variation = "ToolButton"
		fb.focus_mode = Control.FOCUS_NONE
		fb.pressed.connect(_on_menu.bind(entry[1]))
		bar.add_child(fb)
	return panel


## The map's tools, for a fight and for prep: select, place tokens, fog, …,
## and seeing the scene as a player would.
func _build_toolbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for t in TableTools.all_tools():
		var b := Button.new()
		b.set_meta("icon", t.icon)
		b.text = t.label
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
	var l2 := Label.new()
	l2.text = "Preview as"
	l2.theme_type_variation = "DimLabel"
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
	var shown := {}
	for s in e.scenes:
		var i := scene_select.item_count
		scene_select.add_item(("● " if str(s.id) == e.active_scene_id else "   ") + str(s.get("name", s.id)))
		scene_select.set_item_metadata(i, str(s.id))
		if str(s.id) == ctx.scene_id:
			scene_select.select(i)
		shown[str(s.get("map", ""))] = true
	# the campaign's maps not up yet: choosing one puts it on screen
	if ctx.campaign != null:
		for m in ctx.campaign.maps:
			if not shown.has(str(m.get("id", ""))):
				var i := scene_select.item_count
				scene_select.add_item("   %s  (%s)" % [str(m.get("name", "")), "the region" if str(m.get("role", "")) == "regional" else "a map"])
				scene_select.set_item_metadata(i, "map:" + str(m.get("id", "")))
	# nothing at all: say so, and choosing it goes to where maps are added (playtest 1: "the drop-down does nothing")
	if scene_select.item_count == 0:
		scene_select.add_item("No map yet — add one…")
		scene_select.set_item_metadata(0, "")
		scene_select.select(0)
	elif ctx.scene_id == "" or e.scene(ctx.scene_id).is_empty():
		scene_select.select(-1)
	scene_select.disabled = false
	scene_select.tooltip_text = "What is on screen, and the campaign's other maps: pick one to put it up (● is the one the players see)"
	if _show_players != null:
		_show_players.visible = has_scene() and ctx.scene_id != e.active_scene_id


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
	_sync_chrome()
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
	if light_menu != null:
		var own := str(ctx.scene().get("light", "")) if ctx.scene_id != "" else ""
		for li in LIGHT_CHOICES.size():
			light_menu.set_item_checked(li, str(LIGHT_CHOICES[li][0]) == own)
			light_menu.set_item_disabled(li, ctx.scene_id == "")
		# "As the map" says what the map is
		var map_light := str(ctx.state.level_for(ctx.scene_id).get("light", "daylight")) if ctx.scene_id != "" else "daylight"
		light_menu.set_item_text(0, "As the map (%s)" % (map_light if Vision.LIGHT_LEVELS.has(map_light) else "daylight"))
	var tm := _menu("Turns")
	if tm != null:
		var mode := str(ctx.encounter().turns.get("mode", "free"))
		for pair in [[T_FREE, "free"], [T_DM, "dm"], [T_ORDERED, "ordered"]]:
			tm.set_item_checked(tm.get_item_index(pair[0]), mode == pair[1])
	# what only means something with a map on screen waits for one (playtest 1)
	var has_scene := has_scene()
	for pair in [[scene_menu, [S_SHOW, S_RENAME, S_REMOVE, S_FOG, S_RESET_FOG]], [tm, [T_START, T_NEXT]], [edit_menu, [M_HIDE, M_DELETE, M_SELECT_ALL]]]:
		var pm: PopupMenu = pair[0]
		if pm == null:
			continue
		for id in pair[1]:
			var at := pm.get_item_index(id)
			if at >= 0:
				pm.set_item_disabled(at, not has_scene)
	for tname in tool_buttons:
		var b: Button = tool_buttons[tname]
		if not b.has_meta("tip"):
			b.set_meta("tip", b.tooltip_text)
		var needs_map: bool = str(tname) != "select"
		b.disabled = needs_map and not has_scene
		b.tooltip_text = str(b.get_meta("tip")) + ("\n\nPut a map on screen first (\"On screen\" at the top)." if b.disabled else "")
	if not has_scene and _tool_name != "" and _tool_name != "select":
		_select_tool("select")
	# the package it came from, and whether there is a newer one to take
	var fm := _menu("File")
	if fm != null:
		var at := fm.get_item_index(M_REVIEW_UPDATE)
		var came: Dictionary = ctx.campaign.doc.get("package", {}) if ctx.campaign != null and ctx.campaign.doc.get("package") is Dictionary else {}
		var newer := CampaignPackage.newer_for(ctx.campaign, App.packages_dir()) if not came.is_empty() else {}
		if came.is_empty():
			fm.set_item_text(at, "Update from its package (not started from one)")
		elif newer.is_empty():
			fm.set_item_text(at, "Update from its package (%s %s is up to date)" % [str(came.get("name", "")), str(came.get("version", ""))])
		else:
			fm.set_item_text(at, "Update from its package (%s available)…" % str(newer.package_version))
		fm.set_item_disabled(at, newer.is_empty())
	_native_menus.sync_all()
	_update_title()


## Is a scene (a map) on screen? The map tools wait for one.
func has_scene() -> bool:
	return ctx.state != null and ctx.scene_id != "" and not ctx.encounter().scene(ctx.scene_id).is_empty()


## Bring the Maps pane forward: where a scene is made from a library map.
func _show_maps_pane() -> void:
	if ctx.campaign != null and not ctx.campaign.maps.is_empty() and scene_select != null and scene_select.is_visible_in_tree():
		scene_select.show_popup()
		ctx.say("Pick a map to put it on screen.")
		return
	_reveal_pane("Maps")
	ctx.say("This campaign has no maps yet: add one with Add map… in the Maps pane (or File → Add a map…).")


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
	if id >= S_LIGHT_BASE and id < S_LIGHT_BASE + LIGHT_CHOICES.size():
		if ctx.scene_id != "":
			var why := ctx.commands.set_scene_light(ctx.scene_id, str(LIGHT_CHOICES[id - S_LIGHT_BASE][0]))
			if why != "":
				ctx.say(why)
		return
	var sid := ctx.scene_id
	match id:
		M_NEW: _new_encounter_dialog()
		M_OPEN: _open_dialog()
		M_SAVE: _save(false)
		M_SAVE_AS: _save(true)
		M_ADD_SCENE: _add_map_dialog() if ctx.campaign != null else _add_scene_dialog()
		M_NEW_CAMPAIGN: _new_campaign_dialog()
		M_OPEN_CAMPAIGN: _open_campaign_dialog()
		M_SAVE_CAMPAIGN: _save(false)
		M_CLOSE_CAMPAIGN: _close_campaign()
		M_FROM_PACKAGE: _from_package_dialog()
		M_EXPORT_PACKAGE: _export_package_dialog()
		M_DUPLICATE: _duplicate_dialog()
		M_REVIEW_UPDATE: _review_update()
		M_RECAP: _recap_dialog()
		M_CHECKPOINT:
			# a restore point: the whole table as it is now, to come back to in one step
			_prompt("Mark a restore point — the whole table as it is now (tokens, sheets, hit points, turns), to come back to in one step if things go wrong",
				"Call it", "Before %s" % (ctx.scene().get("name", "the fight") if not ctx.scene().is_empty() else "this"), func(v: String) -> void:
				ctx.say("Restore point marked: " + v + " (Edit → Go back to a restore point)" if ctx.kernel.checkpoint(v if v.strip_edges() != "" else "Restore point") != "" else "Could not mark a restore point"))
		M_RESTORE_POINT: _restore_point_dialog()
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
		V_RUNNING:
			_full_table = false
			_sync_chrome()
		V_DM_SCREEN: open_dm_screen()
		V_WORLD: set_mode("world")
		V_FIGHT: set_mode("fight")
		V_PREP: set_mode("prep")
		V_LOOKUP:
			# the Reference pane's search where it is up; the popup elsewhere
			if ctx.mode != "prep" or not dock.layout.is_tab_hidden("Reference"):
				_reveal_pane("Reference")
				reference.focus_search()
			else:
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
		host = HostSession.new(ctx.state, ctx.art)
		host.kernel = ctx.kernel
		host.plugins = ctx.host
		host.apply_request = _apply_player_request
		# what the campaign showed the players in earlier sessions: their Journal keeps it
		host.journal_source = func() -> Array: return ctx.campaign.journal if ctx.campaign != null else []
		# the players' own notes, kept in the campaign (never shown here unless shared with the DM)
		host.notes_source = func() -> Array: return ctx.campaign.player_notes if ctx.campaign != null else []
		host.notes_changed = func() -> void:
			if ctx.campaign != null:
				ctx.campaign.touch()
				ctx.campaign_changed.emit()
		# the web screens: the DM's own (a token in its address), players who join by name, the chat kept
		host.dm_token = _dm_token
		host.add_player = func(ev: Dictionary) -> String: return ctx.commands.run(ev, "%s joins" % str(ev.player.get("name", "")))
		host.dm_handler = func(intent: Dictionary) -> String: return web_dm.op(intent)
		host.dm_state_source = func() -> Dictionary: return web_dm.state()
		host.chat_source = func() -> Array: return ctx.campaign.chat_log if ctx.campaign != null else []
		# pictures from the screens: a token's, a journal's, kept in the campaign's uploads
		host.uploads_dir = Uploads.dir_of(ctx.campaign)
		host.upload_handler = func(pid: String, gm: bool, msg: Dictionary) -> Dictionary: return upload(pid, gm, msg)
		host.log.connect(ctx.say)
		host.announcer.answered.connect(func(ip: String) -> void:
			ctx.say("Answered a player looking for tables at %s" % ip)
			print("discovery: answered %s" % ip))
		host.client_joined.connect(func(_p: String) -> void: _refresh_online())
		host.client_left.connect(func(_p: String) -> void: _refresh_online())
		var err := host.start(host_port, true, web_port)
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
	_update_session_bar()
	_update_banner()
	var net := _menu("Network")
	if net != null:
		net.set_item_checked(net.get_item_index(N_HOST), host != null)


## The DM's web screen on this machine, with its token; "" when not hosting.
# ================================================================ running ==

func _build_running() -> Control:
	var panel := PanelContainer.new()
	panel.name = "Running"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	var center := CenterContainer.new()
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = "DisplayLabel"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var lead := Label.new()
	lead.text = "The game is running."
	lead.theme_type_variation = "HeaderLabel"
	box.add_child(lead)
	var how := Label.new()
	how.text = "Your screen as the DM is in your browser: the book, the map, the fight. The players' screens are in theirs. Keep this window open — it runs the game."
	how.theme_type_variation = "DimLabel"
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(how)
	var open := HomeScreen.card("Open the DM's screen", "In your browser. If it is closed, this brings it back.", "eye", true)
	open.name = "OpenDm"
	open.pressed.connect(open_dm_screen)
	box.add_child(open)
	var join_head := Label.new()
	join_head.text = "Players join at"
	join_head.theme_type_variation = "DimLabel"
	box.add_child(join_head)
	var urls := VBoxContainer.new()
	urls.name = "Urls"
	box.add_child(urls)
	var hint := Label.new()
	hint.text = "Players with you: on a phone or computer on the same network as this one (the same Wi-Fi or router), in any browser. Invite players, on your screen, shows a code to scan, and how players somewhere else can join."
	hint.theme_type_variation = "DimLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var here := Label.new()
	here.name = "Here"
	here.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(here)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(func() -> void:
		var why := ctx.save_campaign()
		ctx.say(why if why != "" else "Saved"))
	row.add_child(save)
	var full := Button.new()
	full.name = "FullTable"
	full.text = "The full Table: maps, prep, everything…"
	full.tooltip_text = "Everything this window can do: drawing up places and fights, the maps, the rules. The game goes on meanwhile."
	full.pressed.connect(func() -> void:
		_full_table = true
		_sync_chrome())
	row.add_child(full)
	var close := Button.new()
	close.text = "Close the campaign"
	close.pressed.connect(_close_campaign)
	row.add_child(close)
	box.add_child(row)
	HomeScreen.restyle_cards(panel, ThemeBuilder.tokens(app.theme_name) if app != null else ThemeBuilder.tokens(""))
	return panel


## The running panel shows while a campaign is open and hosted, unless the
## DM went to the full Table (View → The game, running brings it back).
func _refresh_running() -> void:
	if _running == null:
		return
	var on := ctx.campaign != null and host != null and host.web != null and not _full_table and not (_picker != null and _picker.visible)
	_running.visible = on
	if not on:
		return
	(_running.find_child("Title", true, false) as Label).text = ctx.campaign.name
	var urls := _running.find_child("Urls", true, false) as VBoxContainer
	for c in urls.get_children():
		urls.remove_child(c)
		c.queue_free()
	# the likeliest address, and this computer's others said for what they are
	# (a playtest's DM, shown four alike, worried before anyone had joined)
	var list := Array(host.join_urls())
	if list.is_empty():
		list = ["http://localhost:%d  (this computer only: no network)" % host.web.port]
	var first := Label.new()
	first.text = str(list[0])
	first.theme_type_variation = "HeaderLabel"
	urls.add_child(first)
	if list.size() > 1:
		var rest := Label.new()
		rest.text = "Other addresses of this computer:"
		for u in list.slice(1):
			rest.text += "\n%s — %s" % [str(u), WebServer.address_kind(str(u))]
		rest.theme_type_variation = "DimLabel"
		rest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		urls.add_child(rest)
	var names := PackedStringArray()
	for p in ctx.encounter().players:
		names.append("%s %s" % [str(p.get("name", "")), "(here)" if host.connected_players().has(str(p.get("id", ""))) else "(not yet)"])
	(_running.find_child("Here", true, false) as Label).text = ("At the table: " + ", ".join(names)) if not names.is_empty() else "Nobody has joined yet."


func dm_url() -> String:
	if host == null or host.web == null:
		return ""
	return "http://localhost:%d/dm#t=%s" % [host.web.port, _dm_token]


## Open the DM's web screen in the browser.
func open_dm_screen() -> void:
	var url := dm_url()
	if url == "":
		ctx.say("Start hosting first: the DM's screen is served by the table")
		return
	last_opened = url
	if App.no_browser:
		return
	OS.shell_open(url)


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
	_refresh_running()
	players.online.clear()
	players.cogm_code = host.cogm_code if host != null else ""
	players.cogm_count = host.cogm_count() if host != null else 0
	if host != null:
		for p in host.connected_players():
			players.online[p] = true
	players.refresh()
	campaign_panel.refresh()
	_update_session_bar()
	_update_banner()


# ================================================================== campaign ==

func _new_campaign_dialog() -> void:
	_guard_unsaved(func() -> void:
		_prompt("New campaign", "Name", "New campaign", func(v: String) -> void:
			var c := Campaign.create(v if v.strip_edges() != "" else "Untitled campaign")
			var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.campaign ; Campaigns"])
			# a campaign is a folder of its own: its maps, its content and its rules live beside it
			var home := App.campaigns_dir(app.prefs).path_join(c.name)
			DirAccess.make_dir_recursive_absolute(home)
			fd.current_dir = ProjectSettings.globalize_path(home)
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


## A campaign of one's own from a package: the package is copied into a
## folder of its own and that copy is what is played. The package itself
## is never written to.
func _from_package_dialog(path := "") -> void:
	_guard_unsaved(func() -> void:
		if path == "":
			var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.campaignpkg ; Campaign packages"])
			DirAccess.make_dir_recursive_absolute(App.packages_dir())
			fd.current_dir = ProjectSettings.globalize_path(App.packages_dir())
			fd.file_selected.connect(func(p: String) -> void: _from_package_dialog(p))
			fd.popup_centered_ratio(0.7)
			return
		var info := CampaignPackage.read(path)
		if not info.ok:
			_info(str(info.why))
			return
		var unmet := CampaignPackage.unmet(info, _installed_rulesets(), App.version())
		if not unmet.is_empty():
			_info("%s cannot start here:\n\n• %s" % [str(info.name), "\n• ".join(PackedStringArray(unmet))])
			return
		var whole := CampaignPackage.verify(path)
		if not whole.ok:
			_info("%s is damaged and will not start: %s.\n\nDownload it again." % [str(info.name), str(whole.why)])
			return
		# what it is, what to call it, and (a press away) what is inside and under whose terms
		_package_dialog(path, info, whole))


## What a DM reads before starting a package: what it holds and the
## licences and attributions of everything in it.
static func package_summary(path: String, whole: Dictionary) -> String:
	var lines := PackedStringArray()
	for item in CampaignPackage.contents(path):
		var head: String = {"campaign": "Campaign", "ruleset": "Rules", "art": "Art", "content": "Content"}.get(str(item.kind), str(item.kind))
		lines.append("%s: %s %s — %s" % [head, str(item.name), str(item.version), str(item.license) if str(item.license) != "" else "no licence stated"])
		if str(item.attribution) != "" and str(item.kind) != "campaign":
			lines.append("    " + str(item.attribution))
	lines.append("")
	lines.append("Checked: all %d files are as the author made them." % int(whole.checked) if not bool(whole.get("unchecked", false))
		else "This package carries no checksums (made before they existed): it could not be checked.")
	lines.append("The package itself is never changed: starting it makes a campaign of your own.")
	return "\n".join(lines)


## One dialog to start a package: the adventure's own pitch first, the
## name of the campaign it becomes, and — folded away — what is inside
## and under whose terms. (Playtest 1 / J1: licences came first, the pitch
## not at all, and the text ran off the screen.)
func _package_dialog(path: String, info: Dictionary, whole: Dictionary) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.title = "Start “%s”" % str(info.name)
	d.ok_button_text = "Start"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	# its cover first, when it has one
	var img := CampaignPackage.cover_image(path, info, 1040)
	if img != null:
		var cover := TextureRect.new()
		cover.name = "Cover"
		cover.texture = ImageTexture.create_from_image(img)
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cover.custom_minimum_size = Vector2(520, 240)
		cover.clip_contents = true
		box.add_child(cover)
	var title := Label.new()
	title.text = str(info.name)
	title.theme_type_variation = "DisplayLabel"
	box.add_child(title)
	var pitch := RichTextLabel.new()
	pitch.bbcode_enabled = true
	pitch.fit_content = true
	pitch.scroll_active = false
	pitch.custom_minimum_size = Vector2(520, 0)
	var authors := ", ".join(PackedStringArray(info.get("authors", []))) if info.get("authors") is Array else ""
	pitch.text = "%s%s\n\n%s" % [str(info.package_version), ("  ·  by " + authors) if authors != "" else "",
		ViewRenderer.markdown_to_bbcode(str(info.description)) if str(info.description) != "" else "[i]No description.[/i]"]
	box.add_child(pitch)
	var row := HBoxContainer.new()
	var nl := Label.new()
	nl.text = "Call your campaign"
	row.add_child(nl)
	var name_edit := LineEdit.new()
	name_edit.name = "CampaignName"
	name_edit.text = free_campaign_name(App.campaigns_dir(app.prefs), str(info.name))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.select_all_on_focus = true
	row.add_child(name_edit)
	box.add_child(row)
	var note := Label.new()
	note.text = "It becomes a campaign of your own, in %s. The file you started it from is never changed." % ProjectSettings.globalize_path(App.campaigns_dir(app.prefs))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 520
	note.theme_type_variation = "DimLabel"
	box.add_child(note)
	var more := Button.new()
	more.name = "Inside"
	more.text = "▸ What is inside, and the licences"
	more.theme_type_variation = "ToolButton"
	more.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(more)
	var inside := Label.new()
	inside.name = "InsideText"
	inside.text = package_summary(path, whole)
	inside.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inside.custom_minimum_size.x = 520
	inside.theme_type_variation = "DimLabel"
	inside.visible = false
	box.add_child(inside)
	more.pressed.connect(func() -> void:
		inside.visible = not inside.visible
		more.text = ("▾ " if inside.visible else "▸ ") + "What is inside, and the licences"
		d.reset_size())
	d.add_child(box)
	d.confirmed.connect(func() -> void: _start_package(path, info, name_edit.text))
	name_edit.text_submitted.connect(func(_t: String) -> void:
		d.hide()
		_start_package(path, info, name_edit.text))
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.close_requested.connect(d.queue_free)
	add_child(d)
	d.popup_centered_clamped(Vector2i(600, 0), 0.9)
	name_edit.grab_focus.call_deferred()
	return d


## `wanted`, or "wanted 2", "wanted 3"…: a name no campaign folder has yet.
static func free_campaign_name(dir: String, wanted: String) -> String:
	var n := 1
	var v := wanted
	while DirAccess.dir_exists_absolute(dir.path_join(v)):
		n += 1
		v = "%s %d" % [wanted, n]
	return v


func _start_package(path: String, info: Dictionary, p_name: String) -> void:
	var v := p_name.strip_edges() if p_name.strip_edges() != "" else str(info.name)
	var dest := App.campaigns_dir(app.prefs).path_join(v)
	if DirAccess.dir_exists_absolute(dest):
		_info("You already have a campaign called “%s”. Start this one under another name." % v)
		return
	var r := CampaignPackage.instance(path, dest, v)
	if not r.ok:
		_info("Could not start it: " + str(r.why))
		return
	_open_campaign_path(str(r.path))
	ctx.say("'%s' is yours now, in %s. The package is untouched." % [str(r.name), ProjectSettings.globalize_path(dest)])


## The rulesets installed here, {id: version}, for a package's requirements.
func _installed_rulesets() -> Dictionary:
	var out := {}
	for m in PluginHost.discover(ctx.plugin_dirs):
		out[str(m.get("id", ""))] = str(m.get("version", ""))
	return out


## This campaign as a package for someone else: its maps, its content,
## its prepared encounters — not the party's play.
## Release this campaign as a package. The first time it asks where the
## package goes and the campaign becomes the package's working copy;
## after that it asks what changed, bumps the version and writes the same
## file again, keeping a changelog.
func _export_package_dialog() -> void:
	if ctx.campaign == null or ctx.campaign.path == "":
		_info("Save the campaign first: a package is made from what is on disk.")
		return
	ctx.save_campaign()
	var src: Dictionary = ctx.campaign.doc.get("source_of", {}) if ctx.campaign.doc.get("source_of") is Dictionary else {}
	var ask_notes := func(path: String, next: String) -> void:
		_prompt("Release %s %s" % [ctx.campaign.name, next], "What changed in this version", "" if not src.is_empty() else "First release.", func(notes: String) -> void:
			# a package carries what it needs: its rules and its art included
			var r := CampaignPackage.release(ctx.campaign, notes, {"path": path, "plugin_dirs": ctx.plugin_dirs})
			ctx.say("Released %s %s to %s" % [ctx.campaign.name, str(r.version), ProjectSettings.globalize_path(str(r.path))] if r.ok else "Could not package it: " + str(r.why)))
	if not src.is_empty():
		ask_notes.call(str(src.path), CampaignPackage.bump(str(src.get("version", "1.0.0"))))
		return
	var fd := _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, ["*.campaignpkg ; Campaign packages"])
	DirAccess.make_dir_recursive_absolute(App.packages_dir())
	fd.current_dir = ProjectSettings.globalize_path(App.packages_dir())
	fd.current_file = "%s.campaignpkg" % ctx.campaign.name.to_lower().replace(" ", "_")
	fd.file_selected.connect(func(path: String) -> void:
		if path.get_extension() == "":
			path += "." + CampaignPackage.EXT
		var came: Dictionary = ctx.campaign.doc.get("package", {}) if ctx.campaign.doc.get("package") is Dictionary else {}
		ask_notes.call(path, CampaignPackage.bump(str(came.version)) if came.has("version") else "1.0.0"))
	fd.popup_centered_ratio(0.7)


## A newer version of the package this campaign came from, if the library
## has one: what it would change, and the DM's choice — never automatic.
func _review_update() -> void:
	if ctx.campaign == null:
		return
	var newer := CampaignPackage.newer_for(ctx.campaign, App.packages_dir())
	if newer.is_empty():
		_info("No newer version of this campaign's package is in your library.")
		return
	var rep := CampaignPackage.update_report(ctx.campaign, str(newer.path))
	_confirm(update_summary(rep) + "\n\nBring in its new maps, content, art and encounters? (Your party, sessions and journal stay as they are; the rules stay as they are too.)", func() -> void:
		var r := CampaignPackage.apply_update(ctx.campaign, str(newer.path), true, false)
		if not r.ok:
			_info("Could not update: " + str(r.why))
			return
		_open_campaign_path(ctx.campaign.path)
		ctx.say("Brought in: " + (", ".join(PackedStringArray(r.applied)) if not (r.applied as Array).is_empty() else "the newer files")))


## The report a DM reads before taking a newer version of their package.
static func update_summary(rep: Dictionary) -> String:
	var lines := PackedStringArray(["%s %s → %s" % [str(rep.name), str(rep.from), str(rep.to)]])
	for entry in rep.get("changelog", []):
		lines.append("  %s: %s" % [str(entry.get("version", "")), str(entry.get("notes", ""))])
	for kind in ["maps", "packs", "art"]:
		for state in ["added", "changed"]:
			var list: Array = rep[kind][state]
			if not list.is_empty():
				lines.append("%s %s: %s" % [{"maps": "Maps", "packs": "Content", "art": "Art"}[kind], state, ", ".join(PackedStringArray(list))])
	if not (rep.encounters.added as Array).is_empty():
		lines.append("New encounters: " + ", ".join(PackedStringArray(rep.encounters.added)))
	for r in rep.get("rules", []):
		lines.append("Rules: %s %s → %s (not moved unless you choose to)" % [str(r.id), str(r.from), str(r.to)])
	return "\n".join(lines)


## The same campaign again, as its own folder: for a second group, or to
## take it somewhere new without touching this one.
func _duplicate_dialog() -> void:
	if ctx.campaign == null or ctx.campaign.path == "":
		_info("Save the campaign first.")
		return
	_prompt("Duplicate", "Call the copy", ctx.campaign.name + " (copy)", func(v: String) -> void:
		var name := v.strip_edges() if v.strip_edges() != "" else ctx.campaign.name + " (copy)"
		var dest := App.campaigns_dir(app.prefs).path_join(name)
		var copy := func(fresh: bool) -> void:
			var r := Campaign.duplicate_to(ctx.campaign, dest, name, fresh)
			if not r.ok:
				_info("Could not copy it: " + str(r.why))
				return
			ctx.say("Copied%s to %s" % [" as a fresh start" if fresh else "", ProjectSettings.globalize_path(str(r.path))])
		# for another group: the adventure without this group's play
		_confirm("Start the copy fresh, for another group? Its maps, content, rules and prepared encounters come along; this group's party, sessions, journal and played encounters do not.\n\n(Cancel copies everything, play included.)",
			func() -> void: copy.call(true), func() -> void: copy.call(false)))


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


## A picture a screen sent (the team, after the character maker): kept in
## the campaign's uploads. A token's (`kind` "token", `actor`) becomes the
## character's token art, on its tokens on every map and on the ones it
## gets later; a player's for their own characters only, the DM's for
## anyone. `clear` takes a token's picture off. A journal's (`kind`
## "picture") is kept and its ref sent back, for the note it goes in.
## {ok, ref, why}
func upload(pid: String, gm: bool, msg: Dictionary) -> Dictionary:
	var kind := str(msg.get("kind", ""))
	if not Uploads.KINDS.has(kind):
		return {"ok": false, "why": "a picture for what?"}
	var actor_id := str(msg.get("actor", ""))
	if kind == "token":
		var a: Dictionary = ctx.encounter().actor(actor_id)
		if a.is_empty():
			return {"ok": false, "why": "no such character"}
		if not gm and str(a.get("owner", "")) != pid:
			return {"ok": false, "why": "that is not your character"}
	var ref := ""
	if not (kind == "token" and bool(msg.get("clear", false))):
		var r := Uploads.store(Uploads.dir_of(ctx.campaign), kind, Marshalls.base64_to_raw(str(msg.get("data", ""))))
		if not bool(r.ok):
			return r
		ref = str(r.ref)
	if kind == "token":
		var why := set_token_art(actor_id, ref)
		if why != "":
			return {"ok": false, "why": why}
	return {"ok": true, "ref": ref}


## A character's token picture ("" for none): the character's own token
## says it, and its tokens on every map show it. "" or why not.
func set_token_art(actor_id: String, ref: String) -> String:
	var enc := ctx.encounter()
	var own: Variant = enc.actor(actor_id).get("token", {})
	var token: Dictionary = (own as Dictionary).duplicate(true) if own is Dictionary else {}
	token["art"] = ref
	var events: Array = [{"t": "actor.set", "id": actor_id, "changes": {"token": token}}]
	for sc in enc.scenes:
		for t in (sc.get("tokens", []) if sc is Dictionary else []):
			if t is Dictionary and str(t.get("actor", "")) == actor_id and str(t.get("art", "")) != ref:
				events.append({"t": "token.set", "scene": str(sc.id), "id": str(t.id), "changes": {"art": ref}})
	return ctx.commands.run_all(events, "Token picture")


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
		host.packs = ctx.art
		host.uploads_dir = Uploads.dir_of(c)
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
	# a newer version of the package it came from is only ever offered
	var newer := CampaignPackage.newer_for(c, App.packages_dir())
	if not newer.is_empty():
		ctx.say("A newer version (%s) of %s is in your library: File → Update from its package…" % [str(newer.package_version), str(newer.name)])
	# a campaign with nothing on screen opens on its map: the regional one, else the first (playtest 1)
	if ctx.encounter().scenes.is_empty() and not c.maps.is_empty():
		var first := str(c.maps[0].get("id", ""))
		for m in c.maps:
			if str(m.get("role", "")) == "regional":
				first = str(m.get("id", ""))
				break
		maps.show_map(first)
	# the table is there to be joined: host at once, unless the DM turned that off
	if host == null and bool(app.prefs.get("auto_host", true)) and not App.no_auto_host:
		_set_hosting(true)
	# the DM's own screen, in the browser, as the game opens
	_full_table = false
	if host != null and host.web != null and not App.no_browser and bool(app.prefs.get("open_dm_screen", true)):
		open_dm_screen()
	ctx.say("Campaign '%s' open: %d players, %d characters, session %d" % [c.name, c.players.size(), c.actors.size(), int(c.clock.get("session", 0))])
	set_mode("fight" if not _live_fight().is_empty() else "world")
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
## A map into the campaign (its library, and its folder), then on screen.
func _add_map_dialog() -> void:
	var fd := _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, ["*.hexmap ; Hex maps", "*.json ; Map JSON"])
	fd.file_selected.connect(func(path: String) -> void:
		var form := PropertyForm.new()
		form.build([{"key": "role", "label": "It is", "type": "enum", "options": ["a battle map (fog of war)", "the region (places and the party on it)"]}],
			{"role": "the region (places and the party on it)" if ctx.campaign.maps.is_empty() else "a battle map (fog of war)"})
		_form_dialog("Add " + path.get_file().get_basename(), form, func(v: Dictionary) -> void:
			var why := maps.add_map(path, "regional" if str(v.role).begins_with("the region") else "battle")
			if why != "" and not why.begins_with("added"):
				_info(why)
				return
			ctx.say(why if why != "" else "Added")
			if maps.selected_map != "":
				maps.show_map(maps.selected_map)))
	fd.popup_centered_ratio(0.7)


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
	if path.ends_with("." + CampaignPackage.EXT):
		_from_package_dialog(path)
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
		LayoutStore.save(dock.layout, LayoutStore.table_path(ctx.mode))
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
	# a native dialog is not a window of ours: its closing is heard through its signals
	for sig in ["file_selected", "files_selected", "dir_selected", "canceled"]:
		fd.connect(sig, func(_a = null) -> void: _refocus.call_deferred())
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


## The restore points marked so far; going back to one asks first.
func _restore_point_dialog() -> void:
	var points: Array = ctx.encounter().checkpoints
	if points.is_empty():
		_info("No restore points yet.\n\nMark one (Edit → Mark a restore point…) before something you may want to take back whole: a fight, a big reveal, a risky ruling. Going back to it puts every token, sheet and hit point back as it was then; Undo can take the going-back back.")
		return
	var d := ConfirmationDialog.new()
	d.title = "Go back to a restore point"
	d.ok_button_text = "Go back"
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(420, 200)
	for i in range(points.size() - 1, -1, -1):
		var cp: Dictionary = points[i]
		var at := list.add_item("%s   ·  %s" % [str(cp.get("name", "")), str(cp.get("when", "")).replace("T", " ").left(16)])
		list.set_item_metadata(at, str(cp.id))
	list.select(0)
	d.add_child(list)
	d.confirmed.connect(func() -> void:
		var sel := list.get_selected_items()
		if sel.is_empty():
			return
		var why := ctx.kernel.restore_checkpoint(str(list.get_item_metadata(sel[0])))
		ctx.say("Back to " + list.get_item_text(sel[0]).get_slice("   ·", 0) + " (Undo takes it back)" if why == "" else why))
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.close_requested.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


func _on_dialog_visibility(w: Window) -> void:
	if is_instance_valid(w) and not w.visible:
		_refocus.call_deferred()


## Bring the Table's window forward and make it the key window again.
func _refocus() -> void:
	if not is_inside_tree():
		return
	var w := get_window()
	if w == null or DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_move_to_foreground(w.get_window_id())
	w.grab_focus()


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


## Every shortcut the Table has, read from the menus' own accelerators and
## the tools' keys, so the list cannot fall behind them.
func shortcut_lines() -> PackedStringArray:
	var lines := PackedStringArray(["Tools"])
	for t in TableTools.all_tools():
		lines.append("  %s — %s: %s" % [t.key, t.label, t.hint])
	var bar := _ui_root.get_child(0) as MenuBar if _ui_root != null else null
	if bar != null:
		for menu in bar.get_children():
			if not (menu is PopupMenu):
				continue
			var pm := menu as PopupMenu
			var found := PackedStringArray()
			for i in pm.item_count:
				var accel := pm.get_item_accelerator(i)
				if accel != KEY_NONE and not pm.is_item_separator(i):
					found.append("  %s — %s" % [OS.get_keycode_string(accel), pm.get_item_text(i).trim_suffix("…")])
			if not found.is_empty():
				lines.append("")
				lines.append(str(pm.name))
				lines.append_array(found)
	lines.append("")
	lines.append("On the map")
	lines.append("  Space+drag or middle-drag — pan · wheel — zoom")
	lines.append("  Delete — remove the selected tokens · Esc — back to the select tool")
	lines.append("  %s — next turn (ordered turns)" % OS.get_keycode_string(KEY_SPACE | KEY_MASK_CMD_OR_CTRL))
	return lines


func _shortcuts_dialog() -> void:
	_info("\n".join(shortcut_lines()))


## The packages waiting in the library: each starts a campaign of its own.
func _refresh_packages() -> void:
	if _picker_packages == null:
		return
	for c in _picker_packages.get_children():
		_picker_packages.remove_child(c)
		c.queue_free()
	var found := found_packages([App.packages_dir(), OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)])
	if found.is_empty():
		return
	var head := Label.new()
	head.text = "Adventures to start"
	head.theme_type_variation = "HeaderLabel"
	_picker_packages.add_child(head)
	for info in found:
		var unmet := CampaignPackage.unmet(info, _installed_rulesets(), App.version())
		var pitch := str(info.description).strip_edges().get_slice("\n", 0)
		if pitch.length() > 140:
			pitch = pitch.left(137) + "…"
		# its cover, when the author gave it one (playtest 2: adventures had no face)
		var img := CampaignPackage.cover_image(str(info.path), info, 320)
		var b := HomeScreen.card("%s  %s" % [str(info.name), str(info.package_version)], str(unmet[0]) if not unmet.is_empty() else pitch, "map", false,
			ImageTexture.create_from_image(img) if img != null else null)
		b.name = "Adventure_" + str(info.id)
		b.tooltip_text = str(info.path)
		b.disabled = not unmet.is_empty()
		var path := str(info.path)
		b.pressed.connect(func() -> void: _from_package_dialog(path))
		_picker_packages.add_child(b)
	HomeScreen.restyle_cards(_picker_packages, ThemeBuilder.tokens(app.theme_name))


## The packages in these folders, readable, the newest version of each once
## (the library's copy before a download of the same), by name.
static func found_packages(dirs: Array) -> Array:
	var by_id := {}
	for dir in dirs:
		if str(dir) == "":
			continue
		var da := DirAccess.open(str(dir))
		if da == null:
			continue
		for n in da.get_files():
			if not n.ends_with("." + CampaignPackage.EXT):
				continue
			var info := CampaignPackage.read(str(dir).path_join(n))
			if not info.ok:
				continue
			var have: Dictionary = by_id.get(str(info.id), {})
			if have.is_empty() or CampaignPackage._compare(str(info.package_version), str(have.package_version)) > 0:
				by_id[str(info.id)] = info
	var out := by_id.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out
