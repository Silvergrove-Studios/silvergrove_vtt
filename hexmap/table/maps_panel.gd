class_name MapsPanel
extends VBoxContainer
## The campaign's maps and its prepared encounters. A map is a place,
## drawn in the Editor and listed here by path with a role (battle or
## regional); it is never changed from the Table. A prepared encounter is
## a recipe for a scene over a map: creatures from the compendium with a
## count, a cell and whether they start hidden, and the DM's notes.
## *Launch* makes the scene, places the creatures through the ruleset's
## entry action and shows it; *Return* takes the creatures out again,
## leaves the party as the fight left them, and goes back to the scene
## before. Old scenes can also be shown from here.

var ctx: TableContext
var selected_map := ""
var selected_enc := ""
var _maps: ItemList
var _encs: ItemList
var _creatures: VBoxContainer
var _enc_notes: TextEdit
var _search: LineEdit
var _results: ItemList
var _launch: Button
var _return: Button
var _bound_encounter: Encounter
## Set by the window: opens a file dialog and calls back with a map path.
var pick_map_file: Callable


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	# maps
	_header(box, "Maps")
	_maps = ItemList.new()
	_maps.custom_minimum_size = Vector2(0, 90)
	_maps.item_selected.connect(func(i: int) -> void: selected_map = str(_maps.get_item_metadata(i)))
	box.add_child(_maps)
	var mrow := HBoxContainer.new()
	_button(mrow, "Add map…", "A map drawn in the Editor, into this campaign's library", func() -> void:
		if pick_map_file.is_valid():
			pick_map_file.call(func(path: String) -> void: ctx.say(add_map(path))))
	_button(mrow, "Regional / battle", "Flip the selected map's role", func() -> void:
		var m := ctx.campaign.map_entry(selected_map) if ctx.campaign != null else {}
		if not m.is_empty():
			m.role = "regional" if str(m.get("role", "battle")) == "battle" else "battle"
			ctx.campaign.touch()
			ctx.campaign_changed.emit())
	_button(mrow, "Show", "Show the selected map as a scene: the one already over it, or a new one", func() -> void: ctx.say(show_map(selected_map)))
	_button(mrow, "Remove", "Take the map out of the library (scenes over it stay)", func() -> void:
		if ctx.campaign != null:
			for i in ctx.campaign.maps.size():
				if str(ctx.campaign.maps[i].get("id", "")) == selected_map:
					ctx.campaign.maps.remove_at(i)
					break
			selected_map = ""
			ctx.campaign.touch()
			ctx.campaign_changed.emit())
	box.add_child(mrow)
	# prepared encounters
	_header(box, "Prepared encounters")
	_encs = ItemList.new()
	_encs.custom_minimum_size = Vector2(0, 90)
	_encs.item_selected.connect(func(i: int) -> void:
		selected_enc = str(_encs.get_item_metadata(i))
		_show_encounter())
	box.add_child(_encs)
	var erow := HBoxContainer.new()
	_button(erow, "New…", "A prepared encounter over the selected map", _new_encounter_dialog)
	_launch = _button(erow, "Launch", "Make the scene, place the creatures, show it", func() -> void: ctx.say(launch(selected_enc)))
	_return = _button(erow, "Return", "The fight is over: take its creatures out and go back to the scene before", func() -> void: ctx.say(return_from(selected_enc)))
	_button(erow, "Delete", "Forget this prepared encounter", func() -> void:
		if ctx.campaign != null:
			for i in ctx.campaign.encounters.size():
				if str(ctx.campaign.encounters[i].get("id", "")) == selected_enc:
					ctx.campaign.encounters.remove_at(i)
					break
			selected_enc = ""
			ctx.campaign.touch()
			ctx.campaign_changed.emit())
	box.add_child(erow)
	_creatures = VBoxContainer.new()
	box.add_child(_creatures)
	_search = LineEdit.new()
	_search.placeholder_text = "Add a creature from the compendium…"
	_search.text_changed.connect(func(_t: String) -> void: _search_compendium())
	box.add_child(_search)
	_results = ItemList.new()
	_results.custom_minimum_size = Vector2(0, 70)
	_results.item_activated.connect(func(i: int) -> void: add_creature(selected_enc, _results.get_item_metadata(i)))
	_results.visible = false
	box.add_child(_results)
	_enc_notes = TextEdit.new()
	_enc_notes.custom_minimum_size = Vector2(0, 70)
	_enc_notes.placeholder_text = "Notes for running it"
	_enc_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_enc_notes.text_changed.connect(func() -> void:
		var e := ctx.campaign.encounter_entry(selected_enc) if ctx.campaign != null else {}
		if not e.is_empty():
			e.notes = _enc_notes.text
			ctx.campaign.touch())
	box.add_child(_enc_notes)


func header_actions() -> Array:
	return []


func bind() -> void:
	if _bound_encounter != null and _bound_encounter.changed.is_connected(_on_changed):
		_bound_encounter.changed.disconnect(_on_changed)
	_bound_encounter = ctx.encounter()
	_bound_encounter.changed.connect(_on_changed)
	if not ctx.campaign_changed.is_connected(refresh):
		ctx.campaign_changed.connect(refresh)
	refresh()


func _on_changed(what: String, _s: String) -> void:
	if what in ["scenes", "active_scene", "restore", "encounter"]:
		refresh()


func refresh() -> void:
	if ctx.state == null:
		return
	_maps.clear()
	_encs.clear()
	if ctx.campaign == null:
		_show_encounter()
		return
	for m in ctx.campaign.maps:
		var i := _maps.add_item("%s  —  %s" % [str(m.get("name", m.get("path", ""))), str(m.get("role", "battle"))])
		_maps.set_item_metadata(i, str(m.get("id", "")))
		if str(m.get("id", "")) == selected_map:
			_maps.select(i)
	for e in ctx.campaign.encounters:
		var mp := ctx.campaign.map_entry(str(e.get("map", "")))
		var live: bool = e.has("live") and not (e.live as Dictionary).is_empty()
		var i := _encs.add_item("%s  —  %s%s%s" % [str(e.get("name", "")), str(mp.get("name", "?")), ("  ● running" if live else ""),
			("  (played %d×)" % (e.played as Array).size()) if e.has("played") and not (e.played as Array).is_empty() else ""])
		_encs.set_item_metadata(i, str(e.get("id", "")))
		if str(e.get("id", "")) == selected_enc:
			_encs.select(i)
	_show_encounter()


func _show_encounter() -> void:
	for c in _creatures.get_children():
		_creatures.remove_child(c)
		c.queue_free()
	var e := ctx.campaign.encounter_entry(selected_enc) if ctx.campaign != null else {}
	var live: bool = not e.is_empty() and e.has("live") and not (e.live as Dictionary).is_empty()
	_launch.disabled = e.is_empty() or live
	_return.disabled = not live
	_search.editable = not e.is_empty()
	_enc_notes.editable = not e.is_empty()
	if e.is_empty():
		_enc_notes.text = ""
		return
	if _enc_notes.text != str(e.get("notes", "")):
		_enc_notes.text = str(e.get("notes", ""))
	var creatures: Array = e.get("creatures", [])
	if creatures.is_empty():
		var l := Label.new()
		l.text = "No creatures yet: search the compendium below."
		l.theme_type_variation = "DimLabel"
		_creatures.add_child(l)
	for i in creatures.size():
		var c: Dictionary = creatures[i]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = str(c.get("name", c.get("entry", "")))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var count := SpinBox.new()
		count.min_value = 1
		count.max_value = 20
		count.value = int(c.get("count", 1))
		count.tooltip_text = "How many"
		count.value_changed.connect(func(v: float) -> void:
			c.count = int(v)
			ctx.campaign.touch())
		row.add_child(count)
		var cell := LineEdit.new()
		cell.text = str(c.get("cell", ""))
		cell.placeholder_text = "col,row"
		cell.custom_minimum_size = Vector2(70, 0)
		cell.tooltip_text = "Where the first one stands (column,row); the rest line up beside it"
		cell.text_changed.connect(func(t: String) -> void:
			c.cell = t.strip_edges()
			ctx.campaign.touch())
		row.add_child(cell)
		var hidden := CheckBox.new()
		hidden.text = "hidden"
		hidden.button_pressed = bool(c.get("hidden", true))
		hidden.toggled.connect(func(on: bool) -> void:
			c.hidden = on
			ctx.campaign.touch())
		row.add_child(hidden)
		var rm := Button.new()
		rm.set_meta("icon", "trash")
		rm.theme_type_variation = "ToolButton"
		rm.tooltip_text = "Take it out of the encounter"
		var idx := i
		rm.pressed.connect(func() -> void:
			creatures.remove_at(idx)
			ctx.campaign.touch()
			_show_encounter())
		row.add_child(rm)
		_creatures.add_child(row)


# ---------------------------------------------------------------- maps --

## A map file into the library, by a path relative to the campaign file
## when both are saved. The map's id, or "" (why, said).
func add_map(path: String, role := "battle") -> String:
	if ctx.campaign == null:
		return "no campaign is open"
	var err: Array = []
	var m := HexMap.load_file(path, err)
	if m == null:
		return "; ".join(PackedStringArray(err))
	var mid := str(m.doc.get("id", ""))
	if not ctx.campaign.map_entry(mid).is_empty():
		return "'%s' is already in the library" % m.name
	ctx.campaign.maps.append({"id": mid, "path": ctx.relative_path(path), "role": role, "name": m.name})
	ctx.state.attach_map(m)
	selected_map = mid
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	return ""


## The map loaded (from the library entry's path, or the state's cache), or null.
func load_map(mid: String) -> HexMap:
	if ctx.state.maps.has(mid):
		return ctx.state.maps[mid]
	var m := ctx.campaign.map_entry(mid) if ctx.campaign != null else {}
	if m.is_empty():
		return null
	var p := str(m.get("path", ""))
	if not p.is_absolute_path() and not p.begins_with("res://") and not p.begins_with("user://"):
		p = ctx.encounter().base_dir().path_join(p)
	var loaded := HexMap.load_file(p)
	if loaded != null:
		ctx.state.attach_map(loaded)
	return loaded


## Show a library map: the scene already over it, or a new one. "" or why.
func show_map(mid: String) -> String:
	if mid == "":
		return "pick a map"
	for s in ctx.encounter().scenes:
		if str(s.get("map", "")) == mid:
			ctx.commands.activate_scene(str(s.id))
			ctx.set_scene(str(s.id))
			return ""
	var m := load_map(mid)
	if m == null:
		return "the map could not be loaded"
	var entry := ctx.campaign.map_entry(mid)
	var scene := Encounter.new_scene(m, str(m.levels[0].get("id", "ground")), str(entry.get("name", m.name)), str(entry.get("path", "")))
	scene.fog.enabled = str(entry.get("role", "battle")) == "battle"
	var why := ctx.commands.add_scene(scene, true)
	if why == "":
		ctx.set_scene(str(scene.id))
	return why


# ---------------------------------------------------- prepared encounters --

func _new_encounter_dialog() -> void:
	if ctx.campaign == null or selected_map == "":
		ctx.say("Pick a map in the library first")
		return
	var m := load_map(selected_map)
	if m == null:
		ctx.say("the map could not be loaded")
		return
	var levels := []
	for l in m.levels:
		levels.append(str(l.get("name", l.id)))
	var form := PropertyForm.new()
	form.build([{"key": "name", "label": "Name", "type": "string"}, {"key": "level", "label": "Level", "type": "enum", "options": levels}],
		{"name": "", "level": levels[0]})
	var d := ConfirmationDialog.new()
	d.title = "New prepared encounter on " + m.name
	d.add_child(form)
	d.confirmed.connect(func() -> void:
		var v := form.get_values()
		var li := levels.find(str(v.level))
		new_encounter(str(v.name), selected_map, str(m.level(maxi(li, 0)).id)))
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.close_requested.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


## A prepared encounter record. Its id.
func new_encounter(p_name: String, map_id: String, level_id: String) -> String:
	var rec := {"id": JsonDoc.new_id("enc"), "name": p_name if p_name.strip_edges() != "" else "Encounter %d" % (ctx.campaign.encounters.size() + 1),
		"map": map_id, "level": level_id, "creatures": [], "notes": "", "played": []}
	ctx.campaign.encounters.append(rec)
	selected_enc = str(rec.id)
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	return str(rec.id)


## Entry actions the loaded rulesets offer, per collection (a stat block → an actor).
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
			_results.set_item_metadata(i, {"collection": coll, "id": str(e.get("id", "")), "name": str(e.get("name", e.get("id", "")))})


## A creature line in the recipe: {collection, entry, name, count, cell, hidden}.
func add_creature(enc_id: String, pick: Variant, count := 1, cell := "", hidden := true) -> String:
	var e := ctx.campaign.encounter_entry(enc_id) if ctx.campaign != null else {}
	if e.is_empty() or not (pick is Dictionary):
		return "pick a prepared encounter first"
	e.creatures.append({"collection": str(pick.collection), "entry": str(pick.id), "name": str(pick.get("name", pick.id)), "count": count, "cell": cell, "hidden": hidden})
	ctx.campaign.touch()
	_search.text = ""
	_results.visible = false
	_show_encounter()
	return ""


## Launch: a scene over the encounter's map, the creatures placed through
## the ruleset's entry action (hidden as the recipe says), the scene
## shown. Remembers what it made, for Return. "" or why.
func launch(enc_id: String) -> String:
	var e := ctx.campaign.encounter_entry(enc_id) if ctx.campaign != null else {}
	if e.is_empty():
		return "pick a prepared encounter"
	if e.has("live") and not (e.live as Dictionary).is_empty():
		return "'%s' is already running" % str(e.name)
	var m := load_map(str(e.get("map", "")))
	if m == null:
		return "the encounter's map could not be loaded"
	var entry := ctx.campaign.map_entry(str(e.get("map", "")))
	var previous := ctx.encounter().active_scene_id
	var scene := Encounter.new_scene(m, str(e.get("level", m.levels[0].get("id", "ground"))), str(e.get("name", "")), str(entry.get("path", "")))
	scene.fog.enabled = true
	var why := ctx.commands.add_scene(scene, true)
	if why != "":
		return why
	ctx.set_scene(str(scene.id))
	var acts := _entry_actions()
	var made := []
	var problems := PackedStringArray()
	for c in e.get("creatures", []):
		var coll := str(c.get("collection", ""))
		if not acts.has(coll):
			problems.append("no ruleset places %s" % coll)
			continue
		var record := ctx.kernel.comp.entry_for(coll, str(c.get("entry", "")), true)
		if record.is_empty():
			problems.append("no entry %s" % str(c.get("entry", "")))
			continue
		var pos := Vector2.ZERO
		var cell := str(c.get("cell", ""))
		if cell.contains(","):
			var parts := cell.split(",")
			pos = m.grid.cell_center(m.grid.offset_to_axial(int(parts[0]), int(parts[1])))
		var act: Dictionary = acts[coll]
		# one dispatch per creature (rulesets need not know `count`), each a cell along
		for n in int(c.get("count", 1)):
			var before := ctx.encounter().actors.keys()
			var at := pos + Vector2(float(n) * 1.0, 0.0) if cell.contains(",") else pos
			var pc := ctx.host.dispatch(act.plugin, act.action, {"entry": record, "collection": coll, "scene": str(scene.id), "x": at.x, "y": at.y,
				"count": 1, "hidden": bool(c.get("hidden", true))})
			if pc.status == PluginHost.PluginCall.ERROR:
				problems.append("%s: %s" % [str(c.get("name", "")), pc.error])
				break
			ctx.kernel.pending.drive(pc, act.plugin)
			for aid in ctx.encounter().actors.keys():
				if not before.has(aid):
					made.append(str(aid))
	e.live = {"scene": str(scene.id), "actors": made, "previous": previous}
	if not e.has("played") or not (e.played is Array):
		e.played = []
	(e.played as Array).append(int(ctx.encounter().clock.get("session", 0)))
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	if not problems.is_empty():
		return "Launched with problems: " + "; ".join(problems)
	return ""


## Return: the fight's creatures and its scene go; the party keeps its
## wounds and its loot; the scene before comes back. "" or why.
func return_from(enc_id: String) -> String:
	var e := ctx.campaign.encounter_entry(enc_id) if ctx.campaign != null else {}
	if e.is_empty() or not e.has("live") or (e.live as Dictionary).is_empty():
		return "nothing to return from"
	var live: Dictionary = e.live
	var events := []
	var sid := str(live.get("scene", ""))
	for aid in live.get("actors", []):
		if ctx.encounter().actors.has(aid):
			for sc in ctx.encounter().scenes:
				for tk in sc.tokens:
					if str(tk.get("actor", "")) == str(aid):
						events.append({"t": "token.remove", "scene": str(sc.id), "id": str(tk.id)})
			events.append({"t": "actor.remove", "id": str(aid)})
	if not ctx.encounter().scene(sid).is_empty():
		events.append({"t": "scene.remove", "id": sid})
	var why := ctx.commands.run_all(events, "Return from " + str(e.get("name", ""))) if not events.is_empty() else ""
	if why != "":
		return why
	var previous := str(live.get("previous", ""))
	if previous != "" and not ctx.encounter().scene(previous).is_empty():
		ctx.commands.activate_scene(previous)
		ctx.set_scene(previous)
	e.erase("live")
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	return ""


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HeaderLabel"
	parent.add_child(l)


func _button(parent: Control, text: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(fn)
	parent.add_child(b)
	return b
