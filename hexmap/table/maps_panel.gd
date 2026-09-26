class_name MapsPanel
extends VBoxContainer
## The campaign's maps and its prepared encounters. A map is a place,
## drawn in the Editor and listed here by path with a role (battle or
## regional); it is never changed from the Table. A prepared encounter is
## a recipe for a scene over a map: creatures from the compendium with a
## count, a cell and whether they start hidden, and the DM's notes.
## *Launch* makes the scene, places the creatures through the ruleset's
## entry action and shows it; *Stage* does the same but leaves the players
## where they are, so the DM can arrange the fight unseen and *Go* when it
## is ready; *Return* takes the creatures out again, leaves the party as
## the fight left them, and goes back to the scene before. The creature
## search filters on the facets the ruleset's entry action names
## (`facets = {"type", "cr"}`: a value list, or a range for numbers) and
## shows its `fields`. Old scenes can also be shown from here. On a regional map,
## *places* are markers (tokens tagged `place`, hidden until revealed)
## that link to a prepared encounter, another map or a note, and the
## party marker (a token tagged `party`) says where the party is.

## A prepared encounter launched (or staged), and returned from: the
## window switches to the fight and back to the world.
signal fight_started(enc_id: String)
signal fight_ended(enc_id: String)

var ctx: TableContext
var selected_map := ""
var selected_enc := ""
var _maps: ItemList
var _encs: ItemList
var _creatures: VBoxContainer
var _enc_notes: TextEdit
var _search: LineEdit
var _results: ItemList
var _filters: HFlowContainer
var _filter_widgets := {}   # collection -> {field: Control}
var _launch: Button
var _stage: Button
var _go: Button
var _return: Button
var _places: VBoxContainer
var _places_box: VBoxContainer
var _place_name: LineEdit
var _place_kind: OptionButton
var _place_target: OptionButton
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
	_launch = _button(erow, "Launch", "Make the scene, place the creatures, show it to the players", func() -> void: ctx.say(launch(selected_enc)))
	_stage = _button(erow, "Stage", "Make the scene and place the creatures here, unseen: the players stay where they are until Go", func() -> void: ctx.say(launch(selected_enc, false)))
	_go = _button(erow, "Go", "Show the staged fight to the players", func() -> void: ctx.say(go(selected_enc)))
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
	_filters = HFlowContainer.new()
	box.add_child(_filters)
	_results = ItemList.new()
	_results.custom_minimum_size = Vector2(0, 70)
	_results.item_activated.connect(func(i: int) -> void: add_creature(selected_enc, _results.get_item_metadata(i)))
	_results.visible = false
	box.add_child(_results)
	# places on the shown regional map
	_places_box = VBoxContainer.new()
	_header(_places_box, "Places on this map")
	_places = VBoxContainer.new()
	_places_box.add_child(_places)
	var prow := HBoxContainer.new()
	_place_name = LineEdit.new()
	_place_name.placeholder_text = "Place name"
	_place_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(_place_name)
	_place_kind = OptionButton.new()
	# a place is somewhere to be (a village: its description and its people);
	# the others lead on — to a fight, another map, a note
	for k in ["place", "encounter", "map", "note"]:
		_place_kind.add_item(k)
	_place_kind.item_selected.connect(func(_i: int) -> void: _fill_place_targets())
	prow.add_child(_place_kind)
	_place_target = OptionButton.new()
	_place_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(_place_target)
	_places_box.add_child(prow)
	var prow2 := HBoxContainer.new()
	_button(prow2, "Add place at the selected cell", "A marker where the selected token stands (or the map's origin), hidden until revealed", func() -> void:
		var tk := ctx.selected_token()
		var cell := ctx.map().grid.axial_to_offset(ctx.map().grid.world_to_axial(Vision.token_pos(tk))) if not tk.is_empty() and ctx.map() != null else Vector2i(1, 1)
		var target := str(_place_target.get_item_metadata(_place_target.selected)) if _place_target.selected >= 0 and _place_target.item_count > 0 else ""
		ctx.say(add_place(_place_name.text, str(_place_kind.get_item_text(_place_kind.selected)), target, cell))
		_place_name.text = "")
	_button(prow2, "Party is here", "Put the party marker where the selected token stands", func() -> void:
		var tk := ctx.selected_token()
		if tk.is_empty() or ctx.map() == null:
			ctx.say("Select a token (or a place) to mark where the party is")
			return
		ctx.say(set_party(ctx.map().grid.axial_to_offset(ctx.map().grid.world_to_axial(Vision.token_pos(tk))))))
	_places_box.add_child(prow2)
	box.add_child(_places_box)
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
	if not ctx.scene_changed.is_connected(refresh):
		ctx.scene_changed.connect(refresh)
	refresh()


func _on_changed(what: String, _s: String) -> void:
	if what in ["scenes", "active_scene", "restore", "encounter", "tokens"]:
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
	_show_places()


func _show_encounter() -> void:
	for c in _creatures.get_children():
		_creatures.remove_child(c)
		c.queue_free()
	var e := ctx.campaign.encounter_entry(selected_enc) if ctx.campaign != null else {}
	var live: bool = not e.is_empty() and e.has("live") and not (e.live as Dictionary).is_empty()
	_launch.disabled = e.is_empty() or live
	_stage.disabled = e.is_empty() or live
	_go.disabled = not live or str((e.live as Dictionary).get("scene", "")) == ctx.encounter().active_scene_id
	_return.disabled = not live
	_search.editable = not e.is_empty()
	if not e.is_empty() and _filter_widgets.is_empty():
		_build_filters()
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


# -------------------------------------------------------------- places --

## The library map under the shown scene, and whether it is regional.
func shown_map_entry() -> Dictionary:
	if ctx.campaign == null:
		return {}
	return ctx.campaign.map_entry(str(ctx.scene().get("map", "")))


func _show_places() -> void:
	for c in _places.get_children():
		_places.remove_child(c)
		c.queue_free()
	var entry := shown_map_entry()
	var regional := not entry.is_empty() and str(entry.get("role", "battle")) == "regional"
	_places_box.visible = regional
	if not regional:
		return
	_fill_place_targets()
	var any := false
	for pl in ctx.campaign.places:
		if str(pl.get("map", "")) != str(entry.id):
			continue
		any = true
		var row := HBoxContainer.new()
		var tk := ctx.state.token(ctx.scene_id, str(pl.get("id", "")))
		var l := Label.new()
		l.text = "%s → %s %s%s" % [str(pl.get("name", "")), str(pl.get("kind", "")), _target_name(pl), "  (hidden)" if bool(tk.get("hidden", true)) else ""]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var pid := str(pl.get("id", ""))
		_button(row, "Go", "Launch the encounter, show the map, or read the note", func() -> void: ctx.say(go_to_place(pid)))
		_button(row, "Reveal" if bool(tk.get("hidden", true)) else "Hide", "Whether the players see this marker", func() -> void:
			if not tk.is_empty():
				ctx.commands.run({"t": "token.set", "scene": ctx.scene_id, "id": pid, "changes": {"hidden": not bool(tk.get("hidden", true))}}, "Reveal " + str(pl.get("name", ""))))
		var rm := Button.new()
		rm.set_meta("icon", "trash")
		rm.theme_type_variation = "ToolButton"
		rm.tooltip_text = "Remove the place"
		rm.pressed.connect(func() -> void: ctx.say(remove_place(pid)))
		row.add_child(rm)
		_places.add_child(row)
	if not any:
		var l := Label.new()
		l.text = "No places yet."
		l.theme_type_variation = "DimLabel"
		_places.add_child(l)


func _fill_place_targets() -> void:
	_place_target.clear()
	if ctx.campaign == null:
		return
	match str(_place_kind.get_item_text(maxi(_place_kind.selected, 0))):
		"encounter":
			for e in ctx.campaign.encounters:
				_place_target.add_item(str(e.get("name", "")))
				_place_target.set_item_metadata(_place_target.item_count - 1, str(e.get("id", "")))
		"map":
			for m in ctx.campaign.maps:
				_place_target.add_item(str(m.get("name", "")))
				_place_target.set_item_metadata(_place_target.item_count - 1, str(m.get("id", "")))
		"note":
			for j in ctx.campaign.journal:
				if str(j.get("kind", "")) == "note" or str(j.get("kind", "")) == "handout":
					_place_target.add_item(str(j.get("title", "")) if str(j.get("title", "")) != "" else str(j.get("text", "")).left(30))
					_place_target.set_item_metadata(_place_target.item_count - 1, str(j.get("id", "")))


func _target_name(pl: Dictionary) -> String:
	match str(pl.get("kind", "")):
		"encounter": return str(ctx.campaign.encounter_entry(str(pl.get("target", ""))).get("name", "?"))
		"map": return str(ctx.campaign.map_entry(str(pl.get("target", ""))).get("name", "?"))
		"note": return str(ctx.campaign.journal_entry(str(pl.get("target", ""))).get("title", "?"))
	return ""


## A place on the shown regional map: a marker token (hidden) and the
## record with its link. "" or why.
func add_place(p_name: String, kind: String, target: String, cell: Vector2i) -> String:
	var entry := shown_map_entry()
	if entry.is_empty() or str(entry.get("role", "battle")) != "regional":
		return "show a regional map first"
	if p_name.strip_edges() == "":
		return "a place needs a name"
	var m := ctx.map()
	var pos := m.grid.cell_center(m.grid.offset_to_axial(cell.x, cell.y))
	var pid := JsonDoc.new_id("pl")
	var tk := Encounter.new_token(p_name.strip_edges(), pos, {"id": pid, "label": "◆", "color": "#d9a441", "hidden": true, "tags": ["place"], "vision": null})
	var why := ctx.commands.add_token(ctx.scene_id, tk)
	if why != "":
		return why
	ctx.campaign.places.append({"id": pid, "map": str(entry.id), "cell": "%d,%d" % [cell.x, cell.y], "name": p_name.strip_edges(), "kind": kind, "target": target})
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	return ""


func remove_place(pid: String) -> String:
	for i in ctx.campaign.places.size():
		if str(ctx.campaign.places[i].get("id", "")) == pid:
			ctx.campaign.places.remove_at(i)
			break
	var why := ""
	if not ctx.state.token(ctx.scene_id, pid).is_empty():
		why = ctx.commands.remove_tokens(ctx.scene_id, [pid])
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	return why


## What the place links to: launch the encounter, show the map, or say
## the note; a place that is only a place opens its card.
func go_to_place(pid: String) -> String:
	var pl := {}
	for p in ctx.campaign.places:
		if str(p.get("id", "")) == pid:
			pl = p
	if pl.is_empty():
		return "no such place"
	match str(pl.get("kind", "")):
		"encounter":
			selected_enc = str(pl.get("target", ""))
			# a fight staged ahead: Go brings the players to it
			var e := ctx.campaign.encounter_entry(selected_enc)
			if e.has("live") and bool((e.live as Dictionary).get("staged", false)):
				return go(selected_enc)
			return launch(selected_enc)
		"map":
			return show_map(str(pl.get("target", "")))
		"note":
			var j := ctx.campaign.journal_entry(str(pl.get("target", "")))
			if j.is_empty():
				return "the note is gone"
			ctx.say("%s: %s" % [str(j.get("title", "Note")), str(j.get("text", ""))])
			return ""
	if ctx.show_ref.is_valid():
		ctx.show_ref.call("place:" + pid)
		return ""
	return "the place links to nothing"


## The party marker on the shown regional map, at a cell. "" or why.
func set_party(cell: Vector2i) -> String:
	var entry := shown_map_entry()
	if entry.is_empty():
		return "show a library map first"
	var m := ctx.map()
	var pos := m.grid.cell_center(m.grid.offset_to_axial(cell.x, cell.y))
	var why := ""
	var existing := ""
	for tk in ctx.state.tokens(ctx.scene_id):
		if (tk.get("tags", []) as Array).has("party"):
			existing = str(tk.id)
	if existing != "":
		why = ctx.commands.move_token(ctx.scene_id, existing, pos)
	else:
		why = ctx.commands.add_token(ctx.scene_id, Encounter.new_token("The party", pos, {"id": JsonDoc.new_id("party"), "label": "★", "color": "#4f9cf6", "hidden": false, "tags": ["party"], "vision": {"radius": 3}}))
	if why == "":
		ctx.campaign.doc.party = {"map": str(entry.id), "cell": "%d,%d" % [cell.x, cell.y]}
		ctx.campaign.touch()
		ctx.campaign_changed.emit()
	return why


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
	# the campaign carries the map and the art it is drawn with
	var brought := ctx.bring_in_map(path)
	var entry := {"id": mid, "path": str(brought.path), "role": role, "name": m.name}
	if str(brought.get("source", "")) != "":
		entry.source = str(brought.source)
	ctx.campaign.maps.append(entry)
	ctx.state.attach_map(m)
	selected_map = mid
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	if not (brought.missing as Array).is_empty():
		return "added, but the art pack%s %s it is drawn with %s not on this machine" % ["s" if (brought.missing as Array).size() > 1 else "",
			", ".join(PackedStringArray(brought.missing)), "are" if (brought.missing as Array).size() > 1 else "is"]
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
	# a regional map's places and the party marker are the campaign's: a new
	# scene over it (a package just started, a copy) shows them where they were
	for pl in ctx.campaign.places:
		if str(pl.get("map", "")) == mid:
			var at := _cell_pos(m, str(pl.get("cell", "")))
			scene.tokens.append(Encounter.new_token(str(pl.get("name", "")), at, {"id": str(pl.id), "label": "◆", "color": "#d9a441", "hidden": true, "tags": ["place"], "vision": null}))
	var party: Dictionary = ctx.campaign.doc.get("party", {}) if ctx.campaign.doc.get("party") is Dictionary else {}
	if str(party.get("map", "")) == mid:
		scene.tokens.append(Encounter.new_token("The party", _cell_pos(m, str(party.get("cell", ""))), {"id": JsonDoc.new_id("party"), "label": "★", "color": "#4f9cf6", "hidden": false, "tags": ["party"], "vision": {"radius": 3}}))
	var why := ctx.commands.add_scene(scene, true)
	if why == "":
		ctx.set_scene(str(scene.id))
	return why


## The centre of a "col,row" cell on a map.
static func _cell_pos(m: HexMap, cell: String) -> Vector2:
	var parts := cell.split(",")
	if parts.size() != 2:
		return Vector2.ZERO
	return m.grid.cell_center(m.grid.offset_to_axial(int(parts[0]), int(parts[1])))


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
func new_encounter(p_name: String, map_id: String, level_id: String, p_id := "") -> String:
	# (the web DM screen names its new fight's id, to open its card at once)
	var eid := p_id if p_id != "" and ctx.campaign.encounter_entry(p_id).is_empty() else JsonDoc.new_id("enc")
	var rec := {"id": eid, "name": p_name if p_name.strip_edges() != "" else "Encounter %d" % (ctx.campaign.encounters.size() + 1),
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
				out[str(spec.collection)] = {"plugin": str(pid), "action": str(name), "label": str(spec.get("label", name)),
					"fields": PluginHost._as_list(spec.get("fields", [])), "facets": PluginHost._as_list(spec.get("facets", [])),
					"filter": PluginHost._as_dict(spec.get("query", {})).get("filter", {})}
	return out


## A field spec from an entry action: "cr" or {key, label, values}
## (values: what to show for a raw value, "0.25" → "1/4").
static func _field_spec(f: Variant) -> Dictionary:
	if f is Dictionary:
		return {"key": str(f.get("key", "")), "label": str(f.get("label", f.get("key", ""))), "values": f.get("values", {}) if f.get("values") is Dictionary else {}}
	return {"key": str(f), "label": str(f), "values": {}}


static func _shown(spec: Dictionary, v: Variant) -> String:
	var sv := str(v)
	return str(spec.values.get(sv, sv))


## The filters the rulesets' entry actions ask for: one control per facet
## field — a dropdown of the collection's values, or a min/max pair when
## every value is a number.
func _build_filters() -> void:
	for c in _filters.get_children():
		_filters.remove_child(c)
		c.queue_free()
	_filter_widgets = {}
	if ctx.kernel == null:
		return
	var acts := _entry_actions()
	for coll in acts:
		var facets: Array = acts[coll].get("facets", [])
		if facets.is_empty():
			continue
		var specs := {}
		for f in acts[coll].get("fields", []):
			var fs := _field_spec(f)
			specs[fs.key] = fs
		var page: Dictionary = ctx.kernel.comp.query_for(coll, {"per_page": 1, "facets": facets, "filter": acts[coll].get("filter", {})}, true)
		var widgets := {}
		for field in facets:
			var spec: Dictionary = specs.get(field, _field_spec(field))
			var counts: Dictionary = page.get("facets", {}).get(field, {})
			var values := counts.keys()
			var numeric := not values.is_empty() and values.all(func(v: Variant) -> bool: return str(v).is_valid_float())
			if numeric:
				var lo := SpinBox.new()
				var hi := SpinBox.new()
				var nums := values.map(func(v: Variant) -> float: return float(str(v)))
				nums.sort()
				for sb in [lo, hi]:
					sb.min_value = nums[0]
					sb.max_value = nums[-1]
					sb.step = 0.125 if nums.any(func(n: float) -> bool: return n != floor(n)) else 1.0
					sb.custom_minimum_size = Vector2(72, 0)
					sb.value_changed.connect(func(_v: float) -> void: _search_compendium())
				lo.value = nums[0]
				hi.value = nums[-1]
				lo.tooltip_text = "%s from" % str(spec.label)
				hi.tooltip_text = "%s up to" % str(spec.label)
				var l := Label.new()
				l.text = str(spec.label)
				l.theme_type_variation = "DimLabel"
				_filters.add_child(l)
				_filters.add_child(lo)
				_filters.add_child(hi)
				widgets[field] = [lo, hi]
			else:
				var ob := OptionButton.new()
				ob.add_item("any %s" % str(spec.label))
				ob.set_item_metadata(0, "")
				values.sort()
				for v in values:
					var i := ob.item_count
					ob.add_item("%s (%d)" % [_shown(spec, v), int(counts[v])])
					ob.set_item_metadata(i, str(v))
				ob.item_selected.connect(func(_i: int) -> void: _search_compendium())
				_filters.add_child(ob)
				widgets[field] = ob
		_filter_widgets[coll] = widgets


## The filter a collection's controls express, for a query.
func _filter_for(coll: String) -> Dictionary:
	var out := {}
	for field in _filter_widgets.get(coll, {}):
		var w: Variant = _filter_widgets[coll][field]
		if w is Array:
			var lo: SpinBox = w[0]
			var hi: SpinBox = w[1]
			if lo.value > lo.min_value or hi.value < hi.max_value:
				out[field] = {"min": lo.value, "max": hi.value}
		elif w is OptionButton and w.selected > 0:
			out[field] = str(w.get_item_metadata(w.selected))
	return out


func _search_compendium() -> void:
	var q := _search.text.strip_edges()
	_results.clear()
	var acts := _entry_actions()
	var filtered := acts.keys().any(func(coll: String) -> bool: return not _filter_for(coll).is_empty())
	_results.visible = q != "" or filtered
	if not _results.visible or ctx.kernel == null:
		return
	for coll in acts:
		var fields: Array = acts[coll].get("fields", []).map(_field_spec)
		var keys: Array = fields.map(func(fs: Dictionary) -> String: return str(fs.key))
		var filter: Dictionary = _filter_for(coll)
		# the action's own filter (the ruleset's rules version, say) underneath the DM's
		for k in acts[coll].get("filter", {}):
			if not filter.has(k):
				filter[k] = acts[coll].filter[k]
		var opts := {"text": q, "per_page": 24, "fields": ["name"] + keys, "filter": filter}
		if not fields.is_empty():
			opts.sort = str(keys[0])
		var page: Dictionary = ctx.kernel.comp.query_for(coll, opts, true)
		for e in page.get("entries", []):
			var extra := PackedStringArray()
			for fs in fields:
				if e.has(fs.key) and str(e[fs.key]) != "":
					extra.append("%s %s" % [str(fs.label), _shown(fs, e[fs.key])])
			var i := _results.add_item("%s%s  (%s)" % [str(e.get("name", e.get("id", ""))), ("  —  " + " · ".join(extra)) if not extra.is_empty() else "", coll])
			_results.set_item_metadata(i, {"collection": coll, "id": str(e.get("id", "")), "name": str(e.get("name", e.get("id", "")))})
		if int(page.get("total", 0)) > 24:
			var i := _results.add_item("… %d more: narrow the search" % (int(page.total) - 24))
			_results.set_item_disabled(i, true)


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
## shown — or, not `show`n, staged: the Table looks at it while the
## players stay on the scene they had, until `go`. Remembers what it
## made, for Return. "" or why.
func launch(enc_id: String, show := true) -> String:
	var e := ctx.campaign.encounter_entry(enc_id) if ctx.campaign != null else {}
	if e.is_empty():
		return "pick a prepared encounter"
	if e.has("live") and not (e.live as Dictionary).is_empty():
		return "'%s' is already running" % str(e.name)
	var m := load_map(str(e.get("map", "")))
	if m == null:
		return "the encounter's map could not be loaded"
	var entry := ctx.campaign.map_entry(str(e.get("map", "")))
	# a fight the players are brought to has its own turns: another's end (a
	# playtest's second fight opened on the first one's order, in raw ids)
	if show and bool(ctx.encounter().turns.get("running", false)):
		ctx.commands.stop_turns()
	var previous := ctx.encounter().active_scene_id
	var scene := Encounter.new_scene(m, str(e.get("level", m.levels[0].get("id", "ground"))), str(e.get("name", "")), str(entry.get("path", "")))
	scene.fog.enabled = true
	var why := ctx.commands.add_scene(scene, show)
	if why != "":
		return why
	ctx.set_scene(str(scene.id))
	var acts := _entry_actions()
	var made := []
	var problems := PackedStringArray()
	# creatures with no cell of their own stand side by side, each on a free
	# cell, east of the middle (a fight the DM made at the table put them all
	# on the map's corner, one on top of another)
	var taken := {}
	for tk in ctx.state.tokens(str(scene.id)):
		taken[m.grid.world_to_axial(Vision.token_pos(tk))] = true
	var east := m.grid.offset_to_axial(int(m.grid.columns * 2 / 3), int(m.grid.rows / 2))
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
			var at := pos + Vector2(float(n) * 1.0, 0.0)
			if not cell.contains(","):
				var free := _free_cell(m.grid, east, taken)
				taken[free] = true
				at = m.grid.cell_center(free)
			var pc := ctx.host.dispatch(act.plugin, act.action, {"entry": record, "collection": coll, "scene": str(scene.id), "x": at.x, "y": at.y,
				"count": 1, "hidden": bool(c.get("hidden", true))})
			if pc.status == PluginHost.PluginCall.ERROR:
				problems.append("%s: %s" % [str(c.get("name", "")), pc.error])
				break
			ctx.kernel.pending.drive(pc, act.plugin)
			for aid in ctx.encounter().actors.keys():
				if not before.has(aid):
					made.append(str(aid))
	# the party comes too: without their tokens the players would see only fog
	var why_party := place_party(str(scene.id), m, e)
	if why_party != "":
		problems.append(why_party)
	# (with no scene active before, the kernel shows the first one: nothing to stage behind)
	e.live = {"scene": str(scene.id), "actors": made, "previous": previous, "staged": ctx.encounter().active_scene_id != str(scene.id)}
	if not e.has("played") or not (e.played is Array):
		e.played = []
	(e.played as Array).append(int(ctx.encounter().clock.get("session", 0)))
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	fight_started.emit(enc_id)
	if not problems.is_empty():
		return "Launched with problems: " + "; ".join(problems)
	return ""


## The party on a fight's map: a token for every player character and
## companion not already there, owned by its player, side by side from the
## encounter's `party_cell` ("col,row", where the author says the party
## comes in) or else the middle of the map's west edge. "" or why.
func place_party(scene_id: String, m: HexMap, e: Dictionary) -> String:
	var enc := ctx.encounter()
	var grid := m.grid
	var start := grid.offset_to_axial(1, grid.rows / 2)
	var spec := str(e.get("party_cell", ""))
	if spec.contains(","):
		start = grid.offset_to_axial(int(spec.get_slice(",", 0)), int(spec.get_slice(",", 1)))
	var taken := {}
	var here := {}
	for tk in ctx.state.tokens(scene_id):
		taken[grid.world_to_axial(Vision.token_pos(tk))] = true
		if str(tk.get("actor", "")) != "":
			here[str(tk.actor)] = true
	var ids := enc.actors.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return str(enc.actors[a].get("name", a)).naturalnocasecmp_to(str(enc.actors[b].get("name", b))) < 0)
	var events := []
	for aid in ids:
		var a: Dictionary = enc.actors[aid]
		if not (str(a.get("kind", "")) in ["pc", "companion"]) or here.has(str(aid)):
			continue
		var cell := _free_cell(grid, start, taken)
		taken[cell] = true
		var owner := str(a.get("owner", ""))
		var color := str(enc.player(owner).get("color", "#4f9cf6")) if owner != "" else "#4f9cf6"
		var words := str(a.get("name", "?")).split(" ", false)
		var label := (words[0].left(1) + (words[1].left(1) if words.size() > 1 else words[0].substr(1, 1))).to_upper() if not words.is_empty() else "?"
		var extra := {"actor": str(aid), "label": label, "color": color, "hidden": false, "vision": {"radius": 6}}
		if owner != "":
			extra.owner = owner
		# what the character's own token says (art, size, sight) wins
		var own: Variant = a.get("token", {})
		if own is Dictionary:
			for k in ["art", "size", "color", "label", "vision"]:
				if (own as Dictionary).has(k) and own[k] != null and str(own[k]) != "":
					extra[k] = JsonDoc.deep(own[k])
		events.append({"t": "token.add", "scene": scene_id, "token": Encounter.new_token(str(a.get("name", "")), grid.cell_center(cell), extra)})
	if events.is_empty():
		return ""
	return ctx.commands.run_all(events, "The party arrives")


## The free cell nearest `from` (itself, then ring by ring), on the map.
static func _free_cell(grid: HexGrid, from: Vector2i, taken: Dictionary) -> Vector2i:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if grid.in_bounds(c) and not taken.has(c):
			return c
		for nb in grid.neighbors(c):
			if not seen.has(nb) and seen.size() < 4096:
				seen[nb] = true
				queue.append(nb)
	return from


## Go: the staged fight becomes the scene the players see. "" or why.
func go(enc_id: String) -> String:
	var e := ctx.campaign.encounter_entry(enc_id) if ctx.campaign != null else {}
	if e.is_empty() or not e.has("live") or (e.live as Dictionary).is_empty():
		return "nothing staged"
	var sid := str((e.live as Dictionary).get("scene", ""))
	if ctx.encounter().scene(sid).is_empty():
		return "the staged scene is gone"
	if ctx.encounter().active_scene_id == sid:
		return "the players are already there"
	if bool(ctx.encounter().turns.get("running", false)):
		ctx.commands.stop_turns()
	var why := ctx.commands.activate_scene(sid)
	if why != "":
		return why
	(e.live as Dictionary).staged = false
	ctx.set_scene(sid)
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	return ""


## The running fight to end: the one the players see, or else the last
## running one ("" for none). (A playtest's End the fight ended an older one
## still running, not the one in front of everybody.)
func live_fight() -> String:
	if ctx.campaign == null:
		return ""
	var last := ""
	for e in ctx.campaign.encounters:
		if not (e.get("live") is Dictionary) or (e.live as Dictionary).is_empty():
			continue
		if str(e.live.get("scene", "")) == ctx.encounter().active_scene_id:
			return str(e.id)
		last = str(e.id)
	return last


## Return: the fight's creatures and its scene go (and whatever they
## carried: loot is the DM's to give, by hand); the party keeps its wounds;
## the scene before comes back. "" or why.
func return_from(enc_id: String) -> String:
	var e := ctx.campaign.encounter_entry(enc_id) if ctx.campaign != null else {}
	if e.is_empty() or not e.has("live") or (e.live as Dictionary).is_empty():
		return "nothing to return from"
	var live: Dictionary = e.live
	# the fight's turns end first: what lasted rounds ends with them
	if bool(ctx.encounter().turns.get("running", false)):
		ctx.commands.stop_turns()
	var events := []
	var sid := str(live.get("scene", ""))
	for aid in live.get("actors", []):
		events.append_array(ctx.encounter().actor_removal_events(str(aid)))
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
	fight_ended.emit(enc_id)
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
