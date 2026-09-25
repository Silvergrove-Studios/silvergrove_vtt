class_name RosterPanel
extends VBoxContainer
## The party, or the NPCs: the campaign's actors of some kinds, and the
## selected one's sheet as the GM sees it — the rulesets' own sheet
## views, every button dispatched as the GM, picks taken on the map. A
## character can be given to a player, brought in from a character file,
## made through a ruleset's GM view, or retired. NPCs are also added from
## the compendium through the rulesets' entry actions (a stat block
## becomes an actor with no token; the fight places one).

var ctx: TableContext
## Which kinds this roster lists.
var kinds: Array = ["pc", "companion"]
## Whether this is the party (players' characters) or the NPCs.
var party := true
var selected := ""
var _list: ItemList
var _sheet: VBoxContainer
var _owner: OptionButton
var _search: LineEdit
var _results: ItemList
var _renderers: Array = []
var _bound_encounter: Encounter


func _init(p_ctx: TableContext, p_party := true) -> void:
	ctx = p_ctx
	party = p_party
	kinds = ["pc", "companion"] if party else ["npc", "environment", "hazard", "custom"]
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	# who
	var top := VBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 120)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 90)
	_list.item_selected.connect(func(i: int) -> void:
		selected = str(_list.get_item_metadata(i))
		_render_sheet())
	top.add_child(_list)
	var row := HBoxContainer.new()
	var owner_label := Label.new()
	owner_label.text = "Player"
	owner_label.theme_type_variation = "DimLabel"
	row.add_child(owner_label)
	_owner = OptionButton.new()
	_owner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_owner.tooltip_text = "Whose character this is: they see and act with it from their phone"
	_owner.item_selected.connect(func(i: int) -> void: _set_owner(str(_owner.get_item_metadata(i))))
	row.add_child(_owner)
	var retire := Button.new()
	retire.text = "Retire"
	retire.tooltip_text = "Take this character out of the campaign (undoable)"
	retire.pressed.connect(_retire)
	row.add_child(retire)
	top.add_child(row)
	if not party:
		_search = LineEdit.new()
		_search.placeholder_text = "Add from the compendium: search creatures…"
		_search.text_changed.connect(func(_t: String) -> void: _search_compendium())
		top.add_child(_search)
		_results = ItemList.new()
		_results.custom_minimum_size = Vector2(0, 70)
		_results.item_activated.connect(func(i: int) -> void: _add_from_compendium(_results.get_item_metadata(i)))
		_results.visible = false
		top.add_child(_results)
	split.add_child(top)
	# the sheet
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet = VBoxContainer.new()
	_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet.add_theme_constant_override("separation", 8)
	scroll.add_child(_sheet)
	split.add_child(scroll)


## Buttons for the pane's title bar.
func header_actions() -> Array:
	var out := []
	if party:
		out.append(_tool("file-plus", "Bring a character file (.character) into the campaign", _import_dialog))
	out.append(_tool("plus", "New character through a ruleset's own wizard" if party else "New NPC through a ruleset's own wizard", func() -> void:
		selected = ""
		_list.deselect_all()
		_render_sheet()))
	return out


func _tool(icon: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.set_meta("icon", icon)
	b.tooltip_text = tip
	b.theme_type_variation = "ToolButton"
	b.pressed.connect(fn)
	return b


func bind() -> void:
	if _bound_encounter != null and _bound_encounter.changed.is_connected(_on_changed):
		_bound_encounter.changed.disconnect(_on_changed)
	_bound_encounter = ctx.encounter()
	_bound_encounter.changed.connect(_on_changed)
	if not ctx.campaign_changed.is_connected(refresh):
		ctx.campaign_changed.connect(refresh)
	refresh()


func _on_changed(what: String, _s: String) -> void:
	if what in ["actors", "players", "restore", "encounter"]:
		refresh()
	elif what in ["resources", "effects", "log", "turns", "clock", "tokens", "pending"]:
		_render_sheet()


## The actors this roster shows, by id, in name order.
func actors() -> Array:
	var out := []
	for aid in ctx.encounter().actors:
		var a: Dictionary = ctx.encounter().actors[aid]
		if kinds.has(str(a.get("kind", ""))):
			out.append(str(aid))
	out.sort_custom(func(x: String, y: String) -> bool: return str(ctx.encounter().actors[x].get("name", "")) < str(ctx.encounter().actors[y].get("name", "")))
	return out


func refresh() -> void:
	if ctx.state == null:
		return
	_list.clear()
	var e := ctx.encounter()
	var found := false
	for aid in actors():
		var a: Dictionary = e.actors[aid]
		var who := str(e.player(str(a.get("owner", ""))).get("name", ""))
		var i := _list.add_item("%s%s" % [str(a.get("name", "")), ("  —  " + who) if who != "" else ("  —  " + str(a.get("kind", ""))) if not party else "  —  the DM"])
		_list.set_item_metadata(i, aid)
		if aid == selected:
			_list.select(i)
			found = true
	if not found:
		selected = ""
	_owner.clear()
	_owner.add_item("the DM")
	_owner.set_item_metadata(0, "")
	for p in e.players:
		var i := _owner.item_count
		_owner.add_item(str(p.get("name", "")))
		_owner.set_item_metadata(i, str(p.get("id", "")))
	_render_sheet()


## The selected actor's sheet(s) as the GM sees them; with nothing
## selected, the rulesets' GM views (their wizards make new characters).
func _render_sheet() -> void:
	for r in _renderers:
		if is_instance_valid(r):
			r.queue_free()
	_renderers.clear()
	for c in _sheet.get_children():
		_sheet.remove_child(c)
		c.queue_free()
	var host := ctx.host
	if ctx.kernel == null:
		return
	if selected == "" or ctx.encounter().actor(selected).is_empty():
		_owner.disabled = true
		var l := Label.new()
		l.text = ("Pick a character above, or make one:" if party else "Pick an NPC above, add one from the compendium, or make one:") if host != null and not host.plugins.is_empty() else "No rules loaded: put a ruleset under user://plugins."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.theme_type_variation = "DimLabel"
		_sheet.add_child(l)
		if host != null:
			var projection := Views.project(ctx.kernel, host, "", Views.ROLE_GM)
			var ids := host.plugins.keys()
			ids.sort()
			for pid in ids:
				var p: PluginHost.Plugin = host.plugins[pid]
				if p.views.has("gm"):
					_render(p.views["gm"], Views.status_data(ctx.kernel, projection, str(pid), "", Views.ROLE_GM), str(p.manifest.get("name", pid)))
		return
	_owner.disabled = false
	var a := ctx.encounter().actor(selected)
	for i in _owner.item_count:
		if str(_owner.get_item_metadata(i)) == str(a.get("owner", "")):
			_owner.select(i)
	if host == null:
		return
	var projection := Views.project(ctx.kernel, host, "", Views.ROLE_GM)
	var pa: Dictionary = projection.actors.get(selected, {})
	var sheets: Array = pa.get("sheets", [])
	if sheets.is_empty():
		var l := Label.new()
		l.text = "No ruleset has a sheet for this actor yet: it carries no ruleset data. A ruleset's wizard (below, with nothing selected) makes one."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.theme_type_variation = "DimLabel"
		_sheet.add_child(l)
	for sh in sheets:
		_render(sh.get("schema", {}), sh.get("data", {}), str(host.plugins[str(sh.plugin)].manifest.get("name", sh.plugin)))


func _render(schema: Dictionary, data: Dictionary, title: String) -> void:
	var t := Label.new()
	t.text = title
	t.theme_type_variation = "HeaderLabel"
	_sheet.add_child(t)
	var r := ViewRenderer.new()
	r.intent.connect(_gm_intent)
	r.pick_requested.connect(_pick)
	r.comp_source = _comp
	r.packs = ctx.art
	_sheet.add_child(r)
	r.render(schema, data)
	_renderers.append(r)


## A sheet button pressed by the DM: dispatched as the GM, prompts driven
## to the players.
func _gm_intent(payload: Dictionary) -> void:
	var why := GmIntents.run(ctx, payload)
	if why != "":
		ctx.say(why)
	_render_sheet()


## A sheet button that wants a target on the map: the pick, then the intent.
func _pick(payload: Dictionary) -> void:
	var c: Dictionary = payload.get("ctx", {}) if payload.get("ctx") is Dictionary else {}
	var from := ""
	for tk in ctx.state.tokens(ctx.scene_id):
		if str(tk.get("actor", "")) == str(c.get("actor", "")):
			from = str(tk.id)
			break
	ctx.begin_pick({"kind": str(payload.get("pick", "token")), "area": payload.get("area", {}), "from": from, "label": str(payload.get("label", "Pick"))},
		func(target: Variant) -> void:
			var p: Dictionary = payload.duplicate(true)
			for k in ["pick", "area", "label"]:
				p.erase(k)
			if not (p.get("ctx") is Dictionary):
				p.ctx = {}
			p.ctx.target = target
			p.ctx.scene = ctx.scene_id
			_gm_intent(p))


func _comp(collection: String, req: Dictionary, on_reply: Callable) -> void:
	if ctx.kernel == null:
		on_reply.call({"collection": collection, "error": "no compendium here"})
		return
	if req.has("id"):
		var e := ctx.kernel.comp.entry_for(collection, str(req.id), true)
		on_reply.call({"collection": collection, "entry": e} if not e.is_empty() else {"collection": collection, "error": "no such entry"})
		return
	on_reply.call({"collection": collection, "page": ctx.kernel.comp.query_for(collection, req.get("query", {}) if req.get("query") is Dictionary else {}, true)})


# ---------------------------------------------------------------- verbs --

func _set_owner(pid: String) -> void:
	if selected == "":
		return
	var a := ctx.encounter().actor(selected)
	if str(a.get("owner", "")) == pid:
		return
	ctx.commands.run({"t": "actor.set", "id": selected, "changes": {"owner": pid}}, "Give %s to %s" % [str(a.get("name", "")), str(ctx.encounter().player(pid).get("name", "the DM")) if pid != "" else "the DM"])


func _retire() -> void:
	if selected == "":
		return
	var a := ctx.encounter().actor(selected)
	var events := [{"t": "actor.remove", "id": selected}]
	for sc in ctx.encounter().scenes:
		for tk in sc.tokens:
			if str(tk.get("actor", "")) == selected:
				events.push_front({"t": "token.remove", "scene": str(sc.id), "id": str(tk.id)})
	ctx.commands.run_all(events, "Retire " + str(a.get("name", "")))
	selected = ""
	refresh()


## A .character file becomes one of the party, owned by whoever the
## owner dropdown says (the DM, until assigned).
func _import_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	fd.add_filter("*.character", "Characters")
	fd.file_selected.connect(func(path: String) -> void: ctx.say(import_file(path)))
	fd.close_requested.connect(fd.queue_free)
	fd.canceled.connect(fd.queue_free)
	fd.confirmed.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered_ratio(0.7)


## "" or why not.
func import_file(path: String, owner := "") -> String:
	var err: Array = []
	var doc := CharacterFile.load_file(path, err)
	if doc.is_empty():
		return "; ".join(PackedStringArray(err))
	var a := CharacterFile.to_actor(doc, owner)
	if ctx.encounter().actors.has(str(a.get("id", ""))):
		return "'%s' is already in the campaign" % str(a.get("name", ""))
	var why := ctx.commands.run({"t": "actor.add", "actor": a}, "Bring " + str(a.get("name", "")))
	if why == "":
		selected = str(a.id)
		refresh()
	return why


# ------------------------------------------------------------ compendium --

## Entry actions the loaded rulesets offer (a stat block → an actor), per collection.
func _entry_actions() -> Dictionary:
	var out := {}
	if ctx.host == null:
		return out
	for pid in ctx.host.plugins:
		var p: PluginHost.Plugin = ctx.host.plugins[pid]
		for name in p.actions:
			var spec: Dictionary = p.actions[name]
			if str(spec.get("target", "")) == "entry" and spec.has("collection"):
				out[str(spec.collection)] = {"plugin": str(pid), "action": str(name), "label": str(spec.get("label", name))}
	return out


func _search_compendium() -> void:
	var q := _search.text.strip_edges()
	_results.clear()
	_results.visible = q != ""
	if q == "" or ctx.kernel == null:
		return
	for coll in _entry_actions():
		var page: Dictionary = ctx.kernel.comp.query_for(coll, {"text": q, "per_page": 12, "fields": ["name"]}, true)
		for e in page.get("entries", []):
			var i := _results.add_item("%s  (%s)" % [str(e.get("name", e.get("id", ""))), coll])
			_results.set_item_metadata(i, {"collection": coll, "id": str(e.get("id", ""))})


## The entry action, without a scene: an actor in the roster, no token.
func _add_from_compendium(pick: Variant) -> void:
	if not (pick is Dictionary):
		return
	var acts := _entry_actions()
	var coll := str(pick.collection)
	if not acts.has(coll):
		return
	var record := ctx.kernel.comp.entry_for(coll, str(pick.id), true)
	if record.is_empty():
		return
	var act: Dictionary = acts[coll]
	var before := ctx.encounter().actors.keys()
	var pc := ctx.host.dispatch(act.plugin, act.action, {"entry": record, "collection": coll, "scene": "", "place": false})
	if pc.status == PluginHost.PluginCall.ERROR:
		ctx.say(pc.error)
		return
	ctx.kernel.pending.drive(pc, act.plugin)
	# an NPC added here belongs to the campaign: it is kept, copied and packaged with it
	# (the goblins of one fight are not; they are the fight's)
	for aid in ctx.encounter().actors.keys():
		if not before.has(aid):
			ctx.commands.run({"t": "actor.set", "id": str(aid), "changes": {"persistent": true}}, "Keep " + str(ctx.encounter().actor(str(aid)).get("name", "")))
	_search.text = ""
	_results.visible = false
	refresh()
