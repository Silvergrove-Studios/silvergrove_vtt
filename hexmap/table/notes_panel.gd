class_name NotesPanel
extends VBoxContainer
## Notes and handouts: written ahead of a session with an audience and
## tags, kept in the campaign's journal, handed out to the players' phones
## when the moment comes (a `handout` entry in the log, which the journal
## keeps under the same id). Rulings from play arrive in the journal at
## the end of a session and show here too, read-only.

var ctx: TableContext
var selected := ""
var _list: ItemList
var _search: LineEdit
var _title: LineEdit
var _audience: OptionButton
var _tags: LineEdit
var _text: TextEdit
var _hand: Button
var _delete: Button
var _bound_encounter: Encounter


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var top := VBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 110)
	_search = LineEdit.new()
	_search.placeholder_text = "Search notes, handouts and rulings"
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	top.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 80)
	_list.item_selected.connect(func(i: int) -> void:
		selected = str(_list.get_item_metadata(i))
		_show())
	top.add_child(_list)
	split.add_child(top)
	var editor := VBoxContainer.new()
	editor.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	_title = LineEdit.new()
	_title.placeholder_text = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)
	_audience = OptionButton.new()
	_audience.tooltip_text = "Who may read it once handed out"
	row.add_child(_audience)
	editor.add_child(row)
	_tags = LineEdit.new()
	_tags.placeholder_text = "tags, comma separated"
	editor.add_child(_tags)
	_text = TextEdit.new()
	_text.custom_minimum_size = Vector2(0, 140)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.placeholder_text = "The note. A handout is a note the players get to read."
	editor.add_child(_text)
	var verbs := HBoxContainer.new()
	_button(verbs, "New", "Start a new note", func() -> void:
		selected = ""
		_list.deselect_all()
		_show())
	_button(verbs, "Save", "Keep it in the campaign's journal", save)
	_hand = _button(verbs, "Hand out", "Give it to the players now: it appears on their phones, for its audience", hand_out)
	_delete = _button(verbs, "Delete", "Remove it from the journal", delete)
	editor.add_child(verbs)
	split.add_child(editor)


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
	if what in ["log", "players", "restore", "encounter"]:
		refresh()


## The journal's notes, handouts and rulings, plus this session's handouts
## and journal notes not banked yet (marked live).
func entries() -> Array:
	var out := []
	var seen := {}
	if ctx.campaign != null:
		for j in ctx.campaign.journal:
			out.append(j)
			seen[str(j.get("id", ""))] = true
	for en in ctx.encounter().log:
		var kind := str(en.get("kind", ""))
		if not Campaign.JOURNAL_KINDS.has(kind) or seen.has(str(en.get("id", ""))):
			continue
		if kind == "note" and not bool(en.get("journal", false)):
			continue
		var live: Dictionary = JsonDoc.deep(en)
		live.live = true
		out.append(live)
	return out


func entry(id: String) -> Dictionary:
	for en in entries():
		if str(en.get("id", "")) == id:
			return en
	return {}


func refresh() -> void:
	if ctx.state == null:
		return
	_list.clear()
	var q := _search.text.strip_edges().to_lower()
	var found := false
	var list := entries()
	list.reverse()
	for en in list:
		var hay := ("%s %s %s" % [str(en.get("title", "")), str(en.get("text", "")), " ".join(PackedStringArray(en.get("tags", [])))]).to_lower()
		if q != "" and not hay.contains(q):
			continue
		var kind := str(en.get("kind", ""))
		var mark: String = {"ruling": "R", "handout": "H", "note": "N"}.get(kind, "?")
		var label := str(en.get("title", "")) if str(en.get("title", "")) != "" else str(en.get("text", "")).left(48)
		var where := ""
		if bool(en.get("live", false)):
			where = "  (this session)"
		elif en.has("session") and int(en.session) > 0:
			where = "  (session %d)" % int(en.session)
		if en.has("handed"):
			where += "  handed out"
		var i := _list.add_item("[%s] %s — %s%s" % [mark, label, str(en.get("audience", "gm")), where])
		_list.set_item_metadata(i, str(en.get("id", "")))
		if str(en.get("id", "")) == selected:
			_list.select(i)
			found = true
	if not found:
		selected = ""
	_audience.clear()
	_audience.add_item("GM only")
	_audience.set_item_metadata(0, "gm")
	_audience.add_item("everyone")
	_audience.set_item_metadata(1, "all")
	for p in ctx.encounter().players:
		var i := _audience.item_count
		_audience.add_item(str(p.get("name", "")))
		_audience.set_item_metadata(i, "owner:" + str(p.get("id", "")))
	_show()


func _show() -> void:
	var en := entry(selected)
	_title.text = str(en.get("title", ""))
	_tags.text = ", ".join(PackedStringArray(en.get("tags", [])))
	_text.text = str(en.get("text", ""))
	var aud := str(en.get("audience", "gm"))
	for i in _audience.item_count:
		if str(_audience.get_item_metadata(i)) == aud:
			_audience.select(i)
	var editable := en.is_empty() or (str(en.get("kind", "")) != "ruling" and not bool(en.get("live", false)))
	_title.editable = editable
	_text.editable = editable
	_tags.editable = editable
	_delete.disabled = en.is_empty() or bool(en.get("live", false))
	_hand.disabled = en.is_empty() or bool(en.get("live", false)) or str(en.get("kind", "")) == "ruling"


func _values() -> Dictionary:
	var tags := []
	for t in _tags.text.split(",", false):
		if t.strip_edges() != "":
			tags.append(t.strip_edges())
	return {"title": _title.text.strip_edges(), "text": _text.text, "audience": str(_audience.get_item_metadata(maxi(_audience.selected, 0))), "tags": tags}


## Keep the note in the campaign's journal (new, or the selected one). The id.
func save() -> String:
	if ctx.campaign == null:
		ctx.say("No campaign is open")
		return ""
	var v := _values()
	if v.title == "" and v.text.strip_edges() == "":
		return ""
	var en := entry(selected)
	if en.is_empty() or bool(en.get("live", false)):
		var rec := {"id": JsonDoc.new_id("j"), "kind": "note", "title": v.title, "text": v.text, "audience": v.audience, "tags": v.tags, "journal": true}
		ctx.campaign.journal.append(rec)
		selected = str(rec.id)
	else:
		for k in ["title", "text", "audience", "tags"]:
			en[k] = v[k]
	ctx.campaign.touch()
	ctx.campaign_changed.emit()
	ctx.say("Saved the note")
	return selected


## The players get it now: a handout entry in the log, under the note's
## own id (the journal keeps it once, when the session ends).
func hand_out() -> String:
	var id := save() if selected == "" or not bool(entry(selected).get("live", false)) else selected
	var en := entry(id)
	if en.is_empty():
		return "nothing to hand out"
	var log_entry := {"id": str(en.id), "kind": "handout", "title": str(en.get("title", "")), "text": str(en.get("text", "")), "audience": str(en.get("audience", "all")), "tags": en.get("tags", [])}
	if str(log_entry.audience) == "gm":
		log_entry.audience = "all"
	var why := ctx.kernel.commit([{"t": "log.add", "entry": log_entry}], "Handout", {"by": "gm"}, str(log_entry.audience))
	if why == "":
		en.handed = int(ctx.encounter().clock.get("session", 0))
		en.audience = str(log_entry.audience)
		ctx.campaign.touch()
		ctx.campaign_changed.emit()
		ctx.say("Handed out: " + (str(en.get("title", "")) if str(en.get("title", "")) != "" else "the note"))
	else:
		ctx.say(why)
	return why


func delete() -> void:
	if ctx.campaign == null or selected == "":
		return
	for i in ctx.campaign.journal.size():
		if str(ctx.campaign.journal[i].get("id", "")) == selected:
			ctx.campaign.journal.remove_at(i)
			break
	selected = ""
	ctx.campaign.touch()
	ctx.campaign_changed.emit()


func _button(parent: Control, text: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(fn)
	parent.add_child(b)
	return b
