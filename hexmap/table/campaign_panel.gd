class_name CampaignPanel
extends VBoxContainer
## The session's frame around the fight: the campaign this encounter
## belongs to (start a session from it, bank the session back, the
## recap), the checkpoints the table can go back to, the prep triggers
## on this scene (fire one by hand), and the journal — rulings, handouts
## and notes from this session and every one before, searchable.

var ctx: TableContext
var _campaign: Label
var _campaign_buttons: HBoxContainer
var _checkpoints: VBoxContainer
var _checkpoint_name: LineEdit
var _triggers: VBoxContainer
var _search: LineEdit
var _journal: VBoxContainer
var _ruling: LineEdit
var _rule: LineEdit
## Set by the window: (kind) -> void for "new", "open", "recap".
var on_campaign_action: Callable


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
	# campaign
	_campaign = Label.new()
	_campaign.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_campaign)
	_campaign_buttons = HBoxContainer.new()
	_button(_campaign_buttons, "Start session", "The next session: the counter, the rules' session refills, a checkpoint to recap from", func() -> void: _say(ctx.start_session(), "Session started"))
	_button(_campaign_buttons, "End session", "Close the session: the journal stamped, the recap kept, the campaign saved", func() -> void:
		var r := ctx.end_session(Recap.markdown(ctx.encounter(), "all") if ctx.campaign_is_live() else "")
		_say(str(r.get("error", "")), "Session ended: %d journal entries kept" % int(r.get("journal", 0))))
	_button(_campaign_buttons, "Recap…", "The session recap as Markdown", func() -> void:
		if on_campaign_action.is_valid():
			on_campaign_action.call("recap"))
	box.add_child(_campaign_buttons)
	# checkpoints
	_header(box, "Checkpoints")
	var row := HBoxContainer.new()
	_checkpoint_name = LineEdit.new()
	_checkpoint_name.placeholder_text = "Before the fight…"
	_checkpoint_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_checkpoint_name.text_submitted.connect(func(_t: String) -> void: _mark())
	row.add_child(_checkpoint_name)
	_button(row, "Mark", "Remember where things stand, by name", _mark)
	box.add_child(row)
	_checkpoints = VBoxContainer.new()
	box.add_child(_checkpoints)
	# triggers
	_header(box, "Prep on this scene")
	_triggers = VBoxContainer.new()
	box.add_child(_triggers)
	# journal
	_header(box, "Journal")
	var rrow := HBoxContainer.new()
	_ruling = LineEdit.new()
	_ruling.placeholder_text = "We ruled that…"
	_ruling.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ruling.text_submitted.connect(func(_t: String) -> void: _add_ruling())
	rrow.add_child(_ruling)
	_rule = LineEdit.new()
	_rule.placeholder_text = "rule"
	_rule.custom_minimum_size = Vector2(80, 0)
	_rule.tooltip_text = "The rule it rests on (a compendium id, a page, a phrase)"
	rrow.add_child(_rule)
	_button(rrow, "Add", "Record the ruling (GM only; kept in the campaign's journal)", _add_ruling)
	box.add_child(rrow)
	_search = LineEdit.new()
	_search.placeholder_text = "Search rulings, handouts and notes"
	_search.text_changed.connect(func(_t: String) -> void: _refresh_journal())
	box.add_child(_search)
	_journal = VBoxContainer.new()
	box.add_child(_journal)
	ctx.encounter_changed.connect(refresh)
	ctx.scene_changed.connect(refresh)


func bind() -> void:
	ctx.encounter().changed.connect(func(what: String, _s: String) -> void:
		if what in ["checkpoints", "log", "scenes", "regions", "restore", "clock", "encounter"]:
			refresh())
	if not ctx.campaign_changed.is_connected(refresh):
		ctx.campaign_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if ctx.state == null:
		return
	var e := ctx.encounter()
	if ctx.campaign != null:
		var n := int(e.clock.get("session", 0))
		var open_session := not ctx.campaign.session_entry(n).is_empty() and not ctx.campaign.session_entry(n).has("ended")
		_campaign.text = "%s — %s, day %d" % [ctx.campaign.name, ("session %d" % n) if open_session else ("between sessions (%d played)" % n), int(e.clock.get("day", 1))]
		if ctx.campaign.path == "":
			_campaign.text += "\nNot saved as a campaign yet (File › Save campaign)."
	else:
		_campaign.text = "No campaign open (File › Open campaign…)."
	for b in _campaign_buttons.get_children():
		(b as Button).disabled = ctx.campaign == null
	# checkpoints
	_clear(_checkpoints)
	if e.checkpoints.is_empty():
		_dim(_checkpoints, "None yet.")
	for cp in e.checkpoints:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s  (%s)" % [str(cp.get("name", "")), str(cp.get("when", "")).replace("T", " ")]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		_button(row, "Restore", "Put the encounter back as it was then (undoable)", func() -> void: _say(ctx.kernel.restore_checkpoint(str(cp.id)), "Restored " + str(cp.get("name", ""))))
		var drop := Button.new()
		drop.set_meta("icon", "trash")
		drop.tooltip_text = "Forget this checkpoint"
		drop.theme_type_variation = "ToolButton"
		drop.pressed.connect(func() -> void: ctx.kernel.drop_checkpoint(str(cp.id)))
		row.add_child(drop)
		_checkpoints.add_child(row)
	# triggers on the scene and its regions
	_clear(_triggers)
	var sc := ctx.scene()
	var any := false
	for tr in sc.get("triggers", []):
		_trigger_row(tr, "")
		any = true
	for rid in sc.get("regions", {}):
		for tr in sc.regions[rid].get("triggers", []):
			_trigger_row(tr, str(sc.regions[rid].get("label", rid)))
			any = true
	if not any:
		_dim(_triggers, "Nothing prepared. Triggers are data on the scene or a region (docs/encounter-format.md).")
	_refresh_journal()


func _trigger_row(tr: Dictionary, where: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	var label := str(tr.get("label", "")) if str(tr.get("label", "")) != "" else str(tr.get("id", ""))
	l.text = "%s — on %s%s%s" % [label, str(tr.get("on", "")), (" of " + where) if where != "" else "", "  ✓" if bool(tr.get("fired", false)) else ""]
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.tooltip_text = "%d step(s)" % (tr.get("do", []) as Array).size()
	row.add_child(l)
	_button(row, "Fire", "Run it now", func() -> void: _say(ctx.kernel.fire_trigger(ctx.scene_id, str(tr.id)), "Fired " + label))
	_triggers.add_child(row)


func _refresh_journal() -> void:
	_clear(_journal)
	var q := _search.text.strip_edges()
	var entries := []
	# this session's, newest first
	var lg: Array = ctx.encounter().log
	for i in range(lg.size() - 1, -1, -1):
		var en: Dictionary = lg[i]
		if Campaign.JOURNAL_KINDS.has(str(en.get("kind", ""))):
			entries.append(en)
	if ctx.campaign != null:
		for j in ctx.campaign.search_journal(q):
			if lg.any(func(x: Dictionary) -> bool: return str(x.get("id", "")) == str(j.get("id", ""))):
				continue
			entries.append(j)
	var words := q.to_lower().split(" ", false)
	var shown := 0
	for en in entries:
		var hay := ("%s %s %s" % [str(en.get("text", "")), str(en.get("title", "")), str(en.get("rule", ""))]).to_lower()
		var ok := true
		for w in words:
			if not hay.contains(w):
				ok = false
		if not ok:
			continue
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var kind := str(en.get("kind", ""))
		var head: String = {"ruling": "Ruling", "handout": "Handout", "note": "Note"}.get(kind, kind)
		if en.has("session"):
			head += " (session %d)" % int(en.session)
		var text := str(en.get("text", ""))
		if str(en.get("title", "")) != "":
			text = str(en.title) + ": " + text
		if str(en.get("rule", "")) != "":
			text += "  — " + str(en.rule)
		l.text = "%s: %s" % [head, text]
		l.theme_type_variation = "DimLabel" if kind == "note" else ""
		_journal.add_child(l)
		shown += 1
		if shown >= 40:
			break
	if shown == 0:
		_dim(_journal, "Nothing here yet." if q == "" else "No match.")


func _mark() -> void:
	var n := _checkpoint_name.text.strip_edges()
	if n == "":
		n = "Checkpoint %d" % (ctx.encounter().checkpoints.size() + 1)
	_say("" if ctx.kernel.checkpoint(n) != "" else "could not mark", "Marked " + n)
	_checkpoint_name.text = ""


func _add_ruling() -> void:
	var text := _ruling.text.strip_edges()
	if text == "":
		return
	var last_roll := ""
	var lg: Array = ctx.encounter().log
	for i in range(lg.size() - 1, -1, -1):
		if str(lg[i].get("kind", "")) == "roll":
			last_roll = str(lg[i].get("id", ""))
			break
	var entry := {"id": JsonDoc.new_id("j"), "kind": "ruling", "text": text, "rule": _rule.text.strip_edges(), "roll": last_roll, "tags": [], "audience": "gm"}
	_say(ctx.kernel.commit([{"t": "log.add", "entry": entry}], "Ruling", {"by": "gm"}, "gm"), "Ruling recorded")
	_ruling.text = ""
	_rule.text = ""


func _say(why: String, ok: String) -> void:
	ctx.say(why if why != "" else ok)
	refresh()


func _button(parent: Control, text: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _header(parent: Control, text: String) -> void:
	var h := Label.new()
	h.text = text
	h.theme_type_variation = "HeaderLabel"
	parent.add_child(h)


func _dim(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = "DimLabel"
	parent.add_child(l)


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
