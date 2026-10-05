class_name TableSettingsDialog
extends AcceptDialog
## Table settings, on the Table (File → Table settings…, the Rules pane):
## how much the app does here (a level, with "Customized" once anything
## differs from it), and every setting sorted by the question it answers —
## each section back to the level with a press, a level switch that says
## what it will change before it does, settings that wait for the next
## fight marked as such, a search, and the house rules. Every change is
## kept as it is made, one step of the Table's undo (TableSettings); the
## DM's web screen has the same window.

signal closed

var settings: TableSettings
## The level a press on its button asked for, waiting on Switch or Cancel.
var pending_level := ""
var _search: LineEdit
var _scroll: ScrollContainer
var _body: VBoxContainer
var _levels: HBoxContainer
var _badge: Label
var _preview: VBoxContainer
var _preview_words: Label
var _undo: Button
var _switch: Button
var _house: TextEdit
var _closing := false


func _init(p_settings: TableSettings) -> void:
	settings = p_settings
	title = "Table settings"
	ok_button_text = "Done"
	min_size = Vector2i(640, 560)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var lead := Label.new()
	lead.text = "How much the app does at this table, and what it checks, asks and shows. Each change is kept as you make it."
	lead.theme_type_variation = "DimLabel"
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lead.custom_minimum_size.x = 600
	box.add_child(lead)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var ll := Label.new()
	ll.text = "Level"
	ll.theme_type_variation = "HeaderLabel"
	top.add_child(ll)
	_levels = HBoxContainer.new()
	_levels.name = "Levels"
	top.add_child(_levels)
	_badge = Label.new()
	_badge.name = "Badge"
	_badge.theme_type_variation = "DimLabel"
	_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_badge)
	box.add_child(top)
	# what a level switch will change, said before it does
	_preview = VBoxContainer.new()
	_preview.name = "Preview"
	_preview.visible = false
	_preview_words = Label.new()
	_preview_words.name = "PreviewWords"
	_preview_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_words.custom_minimum_size.x = 600
	_preview.add_child(_preview_words)
	var prow := HBoxContainer.new()
	prow.name = "Buttons"
	_switch = Button.new()
	_switch.name = "Switch"
	_switch.text = "Switch"
	_switch.pressed.connect(func() -> void: confirm_level())
	prow.add_child(_switch)
	var no := Button.new()
	no.text = "Cancel"
	no.pressed.connect(func() -> void: cancel_level())
	prow.add_child(no)
	_preview.add_child(prow)
	box.add_child(_preview)
	var srow := HBoxContainer.new()
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search the settings"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	srow.add_child(_search)
	_undo = Button.new()
	_undo.name = "Undo"
	_undo.theme_type_variation = "ToolButton"
	_undo.pressed.connect(func() -> void:
		var why := settings.undo_last()
		if why != "":
			settings.ctx.say(why))
	srow.add_child(_undo)
	box.add_child(srow)
	_scroll = ScrollContainer.new()
	# (small at least, filling what the window has: a level switch's preview
	# above it takes room from it rather than growing the window off screen)
	_scroll.custom_minimum_size = Vector2(600, 200)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)
	confirmed.connect(_close)
	canceled.connect(_close)
	close_requested.connect(_close)


func _ready() -> void:
	settings.ctx.campaign_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if settings.ctx.campaign_changed.is_connected(refresh):
		settings.ctx.campaign_changed.disconnect(refresh)


func _close() -> void:
	if _closing:
		return
	_closing = true
	hide()
	closed.emit()
	queue_free()


## A press on a level: what it would change, before it does.
func ask_level(level: String) -> void:
	var reg := settings.registry()
	if level == str(reg.get("level", "")) and bool(reg.get("level_set", false)) and not bool(reg.get("customized", false)):
		cancel_level()
		return
	pending_level = level
	var changes := TableSettings.changes_for_level(reg, level)
	var lines := PackedStringArray(["Switch to %s? %s" % [str(TableSettings.LEVEL_INFO[level].title), TableSettings.change_words(changes).get_slice(":", 0) + (":" if not changes.is_empty() else "")]])
	for ch in changes:
		lines.append("   •  %s:  %s → %s%s" % [str(ch.title), str(ch.from_words), str(ch.to_words), "  (takes effect at the next fight)" if bool(ch.next_fight) else ""])
	_preview_words.text = "\n".join(lines)
	_preview.visible = true
	_switch.text = "Switch to %s" % str(TableSettings.LEVEL_INFO[level].title)
	_refresh_levels(reg)


func confirm_level() -> String:
	if pending_level == "":
		return "no level asked for"
	var level := pending_level
	pending_level = ""
	_preview.visible = false
	var why := settings.set_level(level)
	if why != "":
		settings.ctx.say(why)
	else:
		settings.ctx.say("This table runs at %s now" % str(TableSettings.LEVEL_INFO[level].title))
	refresh()
	return why


func cancel_level() -> void:
	pending_level = ""
	_preview.visible = false
	_refresh_levels(settings.registry())


## The words shown in the preview of a level switch (for tests).
func preview_text() -> String:
	return _preview_words.text if _preview.visible else ""


func refresh() -> void:
	if _closing:
		return
	var reg := settings.registry()
	if reg.is_empty():
		return
	_refresh_levels(reg)
	var undo := str(reg.get("undo", ""))
	_undo.visible = undo != ""
	_undo.text = "Undo: %s" % undo
	var keep := _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var words := _search.text.strip_edges().to_lower()
	var level := str(reg.level)
	var level_title := str(TableSettings.LEVEL_INFO[level].title)
	var by_id := {}
	for it in reg.settings:
		by_id[str(it.id)] = it
	for q in reg.questions:
		var qid := str(q.id)
		var shown := []
		for id in q.settings:
			if _matches(by_id[id], words, q):
				shown.append(by_id[id])
		var own_shown := (qid == "space" and _words_match(words, ["where fights happen", "maps", "theatre", "mind"])) \
			or (qid == "table" and _words_match(words, ["house rules", "this table"]))
		if shown.is_empty() and not own_shown:
			continue
		var head := HBoxContainer.new()
		head.name = "Section_" + qid
		var ht := VBoxContainer.new()
		ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title_l := Label.new()
		title_l.text = str(q.title)
		title_l.theme_type_variation = "HeaderLabel"
		ht.add_child(title_l)
		var desc := Label.new()
		desc.text = str(q.description)
		desc.theme_type_variation = "DimLabel"
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ht.add_child(desc)
		head.add_child(ht)
		var follows := shown.filter(func(it: Dictionary) -> bool: return (it.levels as Dictionary).has(level))
		if not follows.is_empty():
			var reset := Button.new()
			reset.name = "Reset_" + qid
			reset.text = "Reset to %s" % level_title
			reset.tooltip_text = "This section's settings as %s has them" % level_title
			reset.disabled = follows.filter(func(it: Dictionary) -> bool: return bool(it.differs)).is_empty()
			reset.pressed.connect(func() -> void:
				var why := settings.reset_question(qid)
				settings.ctx.say(why if why != "" else "%s: as %s has it" % [str(q.title), level_title]))
			head.add_child(reset)
		_body.add_child(head)
		if qid == "space":
			_body.add_child(_space_row(str(reg.space)))
		for it in shown:
			_body.add_child(_setting_row(it, bool(reg.get("fight", false)), level_title))
		if qid == "table":
			_body.add_child(_house_rules(str(reg.house_rules)))
		_body.add_child(HSeparator.new())
	_scroll.set_deferred("scroll_vertical", keep)


func _refresh_levels(reg: Dictionary) -> void:
	for c in _levels.get_children():
		_levels.remove_child(c)
		c.queue_free()
	var level := str(reg.get("level", TableSettings.EXISTING_LEVEL))
	for lv in TableSettings.LEVELS:
		var b := Button.new()
		b.name = "Level_" + str(lv)
		b.text = str(TableSettings.LEVEL_INFO[lv].title)
		b.toggle_mode = true
		b.button_pressed = (lv == level and pending_level == "") or lv == pending_level
		b.tooltip_text = "%s: %s\n• %s" % [str(TableSettings.LEVEL_INFO[lv].title), str(TableSettings.LEVEL_INFO[lv].tagline), "\n• ".join(PackedStringArray(TableSettings.LEVEL_INFO[lv].lines))]
		var id := str(lv)
		b.pressed.connect(func() -> void: ask_level(id))
		_levels.add_child(b)
	var n := int(reg.get("differs", 0))
	if bool(reg.get("customized", false)):
		_badge.text = "Customized: %d setting%s differ%s from %s" % [n, "" if n == 1 else "s", "s" if n == 1 else "", str(TableSettings.LEVEL_INFO[level].title)]
	elif not bool(reg.get("level_set", false)):
		_badge.text = "A campaign from before levels: %s" % str(TableSettings.LEVEL_INFO[level].title)
	else:
		_badge.text = "As %s has it" % str(TableSettings.LEVEL_INFO[level].title)


## The badge's words (for tests).
func badge_text() -> String:
	return _badge.text


func _matches(it: Dictionary, words: String, q: Dictionary) -> bool:
	if words == "":
		return true
	var hay := PackedStringArray([str(it.title), str(it.description), str(q.title), str(it.key)])
	for l in it.get("labels", []):
		hay.append(str(l))
	return _words_match(words, Array(hay))


static func _words_match(words: String, hay: Array) -> bool:
	if words == "":
		return true
	var all := " ".join(PackedStringArray(hay)).to_lower()
	for w in words.split(" ", false):
		if not all.contains(w):
			return false
	return true


func _space_row(space: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Space"
	var l := Label.new()
	l.text = "Fights are played"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var ob := OptionButton.new()
	ob.name = "SpaceChoice"
	for s in TableSettings.SPACES:
		ob.add_item(str(TableSettings.SPACE_INFO[s].title))
	ob.select(maxi(0, TableSettings.SPACES.find(space)))
	ob.item_selected.connect(func(i: int) -> void:
		var why := settings.set_table({"space": TableSettings.SPACES[i]})
		if why != "":
			settings.ctx.say(why))
	row.add_child(ob)
	return row


func _setting_row(it: Dictionary, fight: bool, level_title: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "Setting_" + str(it.key)
	row.add_theme_constant_override("separation", 12)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = str(it.title)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(t)
	var bits := PackedStringArray()
	if bool(it.next_fight):
		bits.append("waits for the next fight" if fight else "takes effect at the next fight")
	if str(it.notice) != "":
		bits.append(str(TableSettings.NOTICE_WORDS[it.notice]).to_lower())
	if bool(it.differs):
		bits.append("%s has it %s" % [level_title, TableSettings.value_words(it, it.level_value)])
	if str(it.description) != "" or not bits.is_empty():
		var d := Label.new()
		d.text = ("%s%s" % [str(it.description), ("  ·  " if str(it.description) != "" and not bits.is_empty() else "") + "  ·  ".join(bits)]).strip_edges()
		d.theme_type_variation = "DimLabel"
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(d)
	row.add_child(words)
	var pid := str(it.plugin)
	var key := str(it.key)
	var ctl := control_for(it, it.value, func(v: Variant) -> void:
		var why := settings.set_setting(pid, key, v)
		if why != "":
			settings.ctx.say(why)
			refresh(), true)
	row.add_child(ctl)
	return row


func _house_rules(text: String) -> Control:
	var box := VBoxContainer.new()
	box.name = "HouseRules"
	var l := Label.new()
	l.text = "House rules: what your table does its own way, in your words. Players read them in How this table runs."
	l.theme_type_variation = "DimLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	_house = TextEdit.new()
	_house.name = "HouseRulesText"
	_house.text = text
	_house.custom_minimum_size.y = 100
	_house.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_house)
	var save := Button.new()
	save.name = "SaveHouseRules"
	save.text = "Keep the house rules"
	save.pressed.connect(func() -> void: save_house_rules(_house.text))
	box.add_child(save)
	return box


func save_house_rules(text: String) -> String:
	var why := settings.set_table({"house_rules": text})
	settings.ctx.say(why if why != "" else "House rules kept")
	return why


## A control for a setting's value — a choice, a switch, a number, words —
## that calls `on_change` with the new value. `settle`: a number's arrows
## wait a moment for the last press (each change loads the rules again).
static func control_for(it: Dictionary, value: Variant, on_change: Callable, settle := false) -> Control:
	if it.get("enum") is Array:
		var ob := OptionButton.new()
		var labels: Array = it.get("labels", it.enum)
		for i in (it.enum as Array).size():
			ob.add_item(str(labels[i]))
		ob.select(maxi(0, TableSettings.choice_index(it, value)))
		ob.tooltip_text = str(it.title)
		ob.fit_to_longest_item = false
		ob.clip_text = true
		ob.custom_minimum_size.x = 220
		ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ob.item_selected.connect(func(i: int) -> void: on_change.call(JsonDoc.deep(it.enum[i])))
		return ob
	match str(it.get("type", "")):
		"boolean":
			var cb := CheckButton.new()
			cb.button_pressed = value == true
			cb.text = "On" if value == true else "Off"
			cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cb.tooltip_text = str(it.title)
			cb.toggled.connect(func(on: bool) -> void:
				cb.text = "On" if on else "Off"
				on_change.call(on))
			return cb
		"integer", "number":
			var sb := SpinBox.new()
			sb.custom_minimum_size.x = 110
			sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sb.min_value = float(it.get("minimum", -1e9))
			sb.max_value = float(it.get("maximum", 1e9))
			sb.allow_lesser = not it.has("minimum")
			sb.allow_greater = not it.has("maximum")
			sb.step = 1.0 if str(it.type) == "integer" else 0.01
			sb.value = float(value) if (value is float or value is int) else 0.0
			sb.select_all_on_focus = true
			var presses := {"n": 0}
			sb.value_changed.connect(func(v: float) -> void:
				var out: Variant = int(v) if str(it.type) == "integer" else v
				if not settle or not sb.is_inside_tree():
					on_change.call(out)
					return
				presses.n = int(presses.n) + 1
				var mine := int(presses.n)
				sb.get_tree().create_timer(0.6).timeout.connect(func() -> void:
					if int(presses.n) == mine and is_instance_valid(sb):
						on_change.call(out)))
			return sb
	var le := LineEdit.new()
	le.text = str(value) if value != null else ""
	le.custom_minimum_size.x = 220
	le.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	le.text_submitted.connect(func(t: String) -> void: on_change.call(t))
	return le
