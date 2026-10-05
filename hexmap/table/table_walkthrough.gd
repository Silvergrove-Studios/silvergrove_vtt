class_name TableWalkthrough
extends AcceptDialog
## The walkthrough a new campaign opens with (New campaign, or an adventure
## started from a package): how this table runs, in five steps. Where
## fights happen; how much the app does (four levels, three lines each on
## what the players will notice; Assisted offered first, for the DM to
## confirm or change); the table's questions, each with a line of what the
## level answers and a Change to open it; the rules options and the house
## rules; and a summary. Nothing changes until Done: then it is one step of
## the Table's undo (TableSettings.finish_setup), and the campaign is set
## up. "Not now" leaves it to be done later (the DM's web screen offers it).

signal finished(see_all: bool)
signal closed

const STEPS := ["space", "level", "questions", "rules", "summary"]
const STEP_TITLES := {"space": "Where fights happen", "level": "How much the app does", "questions": "The table's questions",
	"rules": "Rules options", "summary": "Your table"}

var settings: TableSettings
var reg: Dictionary = {}
var step := 0
## What the DM has answered so far: where fights happen, the level, each
## setting's value (id → value), the house rules.
var draft := {"space": "maps", "level": TableSettings.NEW_LEVEL, "values": {}, "house_rules": ""}
## The question opened with Change on the third step.
var opened := ""
var _title: Label
var _body: VBoxContainer
var _back: Button
var _see_all: Button
var _error: Label
var _done := false


func _init(p_settings: TableSettings) -> void:
	settings = p_settings
	title = "Set up this table"
	min_size = Vector2i(680, 560)
	dialog_hide_on_ok = false
	dialog_close_on_escape = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = Label.new()
	_title.name = "StepTitle"
	_title.theme_type_variation = "HeaderLabel"
	box.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 440)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	_error = Label.new()
	_error.name = "Error"
	_error.visible = false
	_error.add_theme_color_override("font_color", Color("#e36b5b"))
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_error)
	# (each added to the left of the last: Not now, Back, See every setting, Next)
	_see_all = add_button("See every setting", false, "see_all")
	_back = add_button("Back", false, "back")
	add_button("Not now", false, "not_now")
	custom_action.connect(func(action: StringName) -> void:
		if action == &"back":
			back()
		elif action == &"see_all":
			finish(true)
		elif action == &"not_now":
			_closed())
	confirmed.connect(func() -> void: next())
	canceled.connect(_closed)


func _ready() -> void:
	reg = settings.registry()
	var table: Dictionary = TableSettings.table_of(settings.ctx.campaign)
	draft.space = str(table.get("space", "maps")) if TableSettings.SPACES.has(str(table.get("space", ""))) else "maps"
	draft.house_rules = str(table.get("house_rules", ""))
	for it in reg.get("settings", []):
		draft.values[str(it.id)] = JsonDoc.deep(it.value)
	# an adventure's author may suggest how a table runs it: offered first, only a suggestion
	var rec: Dictionary = reg.get("recommended", {})
	if rec.has("space"):
		draft.space = str(rec.space)
	choose_level(str(rec.get("level", TableSettings.NEW_LEVEL)))
	for id in rec.get("answers", {}):
		draft.values[str(id)] = JsonDoc.deep(rec.answers[id])
	_show()


## What the author of the adventure suggests, in words ("" for none).
func suggestion() -> String:
	var rec: Dictionary = reg.get("recommended", {})
	if rec.is_empty():
		return ""
	var by := str(rec.get("by", ""))
	var said := str(rec.get("words", ""))
	if by != "":
		said = said.trim_suffix(".") + " for " + by + "."
	if str(rec.get("note", "")) != "":
		said += " " + str(rec.note)
	return said + " It's only a suggestion: choose what suits your table."


func _closed() -> void:
	if _done:
		return
	_done = true
	hide()
	closed.emit()
	queue_free()


func step_name() -> String:
	return STEPS[step]


func next() -> void:
	if step >= STEPS.size() - 1:
		finish(false)
		return
	step += 1
	opened = ""
	_show()


func back() -> void:
	if step > 0:
		step -= 1
		opened = ""
		_show()


func choose_space(space: String) -> void:
	if TableSettings.SPACES.has(space):
		draft.space = space
		if is_inside_tree():
			_show()


## A level: every setting it names takes its value in the draft (a change
## made on the questions before is the level's again).
func choose_level(level: String) -> void:
	if not TableSettings.LEVELS.has(level):
		return
	draft.level = level
	for it in reg.get("settings", []):
		if (it.levels as Dictionary).has(level):
			draft.values[str(it.id)] = JsonDoc.deep(it.levels[level])
	if is_inside_tree() and step_name() == "level":
		_show()


func set_value(id: String, value: Variant) -> void:
	draft.values[id] = value


func set_house_rules(text: String) -> void:
	draft.house_rules = text


## Done: the answers as one change. "" or why not (said in the window).
func finish(see_all := false) -> String:
	var own := {}
	for it in reg.get("settings", []):
		var id := str(it.id)
		var base: Variant = it.levels[draft.level] if (it.levels as Dictionary).has(str(draft.level)) else it.value
		if draft.values.has(id) and not JsonDoc.same(draft.values[id], base):
			own[id] = JsonDoc.deep(draft.values[id])
	var why := settings.finish_setup({"level": draft.level, "space": draft.space, "house_rules": str(draft.house_rules), "settings": own})
	if why != "":
		_error.text = why
		_error.visible = true
		return why
	_done = true
	finished.emit(see_all)
	return ""


## A question's settings in a line, as the draft has them.
func question_preview(question: String) -> String:
	return TableSettings.question_line(reg, question, draft.values)


## The summary's words (for tests): everything on the last step.
func summary_text() -> String:
	return "\n".join(PackedStringArray(_summary_lines()))


func _show() -> void:
	if _body == null:
		return
	_error.visible = false
	_title.text = "Step %d of %d · %s" % [step + 1, STEPS.size(), str(STEP_TITLES[step_name()])]
	_back.visible = step > 0
	_see_all.visible = step_name() == "summary"
	get_ok_button().text = "Done" if step_name() == "summary" else "Next"
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	# the adventure's author's suggestion, where it is chosen (the space and the level)
	if step_name() in ["space", "level"] and suggestion() != "":
		var sl := Label.new()
		sl.name = "Suggestion"
		sl.text = suggestion()
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size.x = 600
		_body.add_child(sl)
	match step_name():
		"space":
			_say("Do your fights happen on maps with tokens, or in the theatre of the mind? (The rolls work either way.)")
			var group := ButtonGroup.new()
			for s in TableSettings.SPACES:
				var b := HomeScreen.card(str(TableSettings.SPACE_INFO[s].title), str(TableSettings.SPACE_INFO[s].words), "", false)
				b.name = "Space_" + str(s)
				b.toggle_mode = true
				b.button_group = group
				b.button_pressed = s == draft.space
				var id := str(s)
				b.pressed.connect(func() -> void: choose_space(id))
				_body.add_child(b)
		"level":
			_say("How much should the app do? You can change it, and any setting, at any time in Table settings.")
			var group := ButtonGroup.new()
			for lv in TableSettings.LEVELS:
				var info: Dictionary = TableSettings.LEVEL_INFO[lv]
				var b := HomeScreen.card("%s — %s" % [str(info.title), str(info.tagline)], "• " + "\n• ".join(PackedStringArray(info.lines)), "", false)
				b.name = "Level_" + str(lv)
				b.toggle_mode = true
				b.button_group = group
				b.button_pressed = lv == draft.level
				var id := str(lv)
				b.pressed.connect(func() -> void: choose_level(id))
				_body.add_child(b)
		"questions":
			var any := false
			_say("What %s answers to each of the table's questions. Change any of them; the rest stay as the level has them." % str(TableSettings.LEVEL_INFO[draft.level].title))
			for q in reg.get("questions", []):
				if not bool(q.level) or (q.settings as Array).is_empty():
					continue
				any = true
				_question_row(q)
			if not any:
				_say("The rules at this table ask nothing more.")
		"rules":
			_say("The rules you play by, whatever the level.")
			var by_id := _by_id()
			for q in reg.get("questions", []):
				if bool(q.level):
					continue
				for id in q.settings:
					_setting_row(by_id[id])
			var hl := Label.new()
			hl.text = "House rules (optional): what your table does its own way. Players read them."
			hl.theme_type_variation = "DimLabel"
			hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(hl)
			var te := TextEdit.new()
			te.name = "HouseRules"
			te.text = str(draft.house_rules)
			te.custom_minimum_size.y = 90
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			te.text_changed.connect(func() -> void: draft.house_rules = te.text)
			_body.add_child(te)
		"summary":
			for line in _summary_lines():
				var l := Label.new()
				l.text = line
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size.x = 600
				if line.begins_with("Change any of this"):
					l.theme_type_variation = "DimLabel"
				_body.add_child(l)


func _summary_lines() -> Array:
	var lines := ["Change any of this later in Table settings."]
	var info: Dictionary = TableSettings.LEVEL_INFO[draft.level]
	lines.append("Where fights happen: %s" % str(TableSettings.SPACE_INFO[draft.space].title))
	lines.append("How much the app does: %s — %s" % [str(info.title), str(info.tagline)])
	for l in info.lines:
		lines.append("  • " + str(l))
	for q in reg.get("questions", []):
		if (q.settings as Array).is_empty():
			continue
		lines.append("%s: %s" % [str(q.title), question_preview(str(q.id))])
	if str(draft.house_rules).strip_edges() != "":
		lines.append("House rules: %s" % str(draft.house_rules).strip_edges())
	return lines


func _say(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "DimLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 600
	_body.add_child(l)


func _by_id() -> Dictionary:
	var out := {}
	for it in reg.get("settings", []):
		out[str(it.id)] = it
	return out


func _question_row(q: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.name = "Question_" + str(q.id)
	var head := HBoxContainer.new()
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = str(q.title)
	t.theme_type_variation = "HeaderLabel"
	words.add_child(t)
	var line := Label.new()
	line.name = "Preview"
	line.text = question_preview(str(q.id))
	line.theme_type_variation = "DimLabel"
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.tooltip_text = line.text
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.custom_minimum_size.x = 480
	words.add_child(line)
	head.add_child(words)
	var change := Button.new()
	change.name = "Change"
	change.text = "Done" if opened == str(q.id) else "Change"
	var qid := str(q.id)
	change.pressed.connect(func() -> void:
		opened = "" if opened == qid else qid
		_show())
	head.add_child(change)
	box.add_child(head)
	if opened == qid:
		var by_id := _by_id()
		for id in q.settings:
			box.add_child(_setting_control_row(by_id[id]))
	_body.add_child(box)


func _setting_row(it: Dictionary) -> void:
	_body.add_child(_setting_control_row(it))


func _setting_control_row(it: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Setting_" + str(it.key)
	row.add_theme_constant_override("separation", 12)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = str(it.title)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(t)
	if str(it.description) != "":
		var d := Label.new()
		d.text = str(it.description)
		d.theme_type_variation = "DimLabel"
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(d)
	row.add_child(words)
	var id := str(it.id)
	var ctl := TableSettingsDialog.control_for(it, draft.values.get(id, it.value), func(v: Variant) -> void:
		draft.values[id] = v
		# the question's line says it at once
		var row_box := _body.find_child("Question_" + opened, false, false) if opened != "" else null
		var pv := row_box.find_child("Preview", true, false) as Label if row_box != null else null
		if pv != null:
			pv.text = question_preview(opened)
			pv.tooltip_text = pv.text)
	row.add_child(ctl)
	return row
