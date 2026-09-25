class_name CampaignPanel
extends VBoxContainer
## The Session pane: the campaign and where it stands, Start and End
## session, hosting (the address and the co-GM code large enough to read
## across a table, who is connected), the in-game clock, the checkpoints
## the table can go back to, the prep triggers on this scene (fire one
## by hand), and the journal — rulings, handouts and notes from this
## session and every one before, searchable.

var ctx: TableContext
var _campaign: Label
var _campaign_buttons: HBoxContainer
var _hosting: Label
var _host_button: Button
var _clock: Label
## Set by the window: hosting on/off, and what to show about it.
var on_host: Callable
var host_info: Callable
var _checkpoints: VBoxContainer
var _checkpoint_name: LineEdit
var _triggers: VBoxContainer
var _search: LineEdit
var _journal: VBoxContainer
var _ruling: LineEdit
var _rule: LineEdit
## Set by the window: (kind) -> void for "new", "open", "recap".
var on_campaign_action: Callable
## Set by the window: bring the Maps pane forward.
var on_show_maps: Callable
## Set by the window: what the players do to join; start the session.
var on_join_info: Callable
var on_start_session: Callable
var _start_box: VBoxContainer
var _steps: VBoxContainer


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
	# what to do next, for a DM who has just started (playtest 1)
	_start_box = VBoxContainer.new()
	_header(_start_box, "Getting started")
	_steps = VBoxContainer.new()
	_start_box.add_child(_steps)
	box.add_child(_start_box)
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
	# hosting
	_header(box, "Players' phones")
	_hosting = Label.new()
	_hosting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hosting.theme_type_variation = "MonoLabel"
	box.add_child(_hosting)
	_host_button = Button.new()
	_host_button.text = "Start hosting"
	_host_button.tooltip_text = "Let players join from their phones on this network"
	_host_button.pressed.connect(func() -> void:
		if on_host.is_valid():
			on_host.call())
	box.add_child(_host_button)
	# the clock
	_header(box, "Clock")
	_clock = Label.new()
	box.add_child(_clock)
	var crow := HBoxContainer.new()
	for pair in [["+10 min", 10], ["+1 hour", 60], ["+8 hours", 480], ["+1 day", 1440]]:
		var mins: int = pair[1]
		_button(crow, pair[0], "Advance the in-game clock (rests, dawn recharges and timed effects follow)", func() -> void: _say(ctx.kernel.clock.advance(mins), "Time passes"))
	box.add_child(crow)
	# restore points
	_header(box, "Restore points")
	_dim(box, "The whole table as it was — tokens, sheets, hit points, turns — to come back to in one step. Mark one before a fight or a big reveal.")
	var row := HBoxContainer.new()
	_checkpoint_name = LineEdit.new()
	_checkpoint_name.placeholder_text = "Before the fight…"
	_checkpoint_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_checkpoint_name.text_submitted.connect(func(_t: String) -> void: _mark())
	row.add_child(_checkpoint_name)
	_button(row, "Mark", "Mark a restore point: where things stand now, to come back to", _mark)
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


## The first things a DM does with a campaign, each ticked off when done;
## the list goes once they all are.
func steps(info: Dictionary) -> Array:
	var e := ctx.encounter()
	var out := []
	out.append({"id": "map", "done": not e.scenes.is_empty(), "text": "Put a map on screen — pick one from “On screen” at the top (the players see it too)",
		"action": "Pick a map", "call": on_show_maps})
	var hosting := bool(info.get("hosting", false))
	var title := ctx.campaign.name if ctx.campaign != null else e.name
	out.append({"id": "host", "done": hosting and not (info.get("connected", []) as Array).is_empty(),
		"text": ("Players join — on each phone: Hexmap → Join a game → “%s”" % title) if hosting else "Players join — open the table to them first",
		"action": "How to join" if hosting else "Open to players", "call": on_join_info if hosting else on_host})
	var owners := {}
	for a in e.actors.values():
		if str(a.get("kind", "")) == "pc" and str(a.get("owner", "")) != "":
			owners[str(a.owner)] = true
	out.append({"id": "characters", "done": not e.players.is_empty() and e.players.all(func(p: Dictionary) -> bool: return owners.has(str(p.get("id", "")))),
		"text": "Everyone has a character — players make theirs on their phones, or you make them (Prep → Characters)"})
	out.append({"id": "session", "done": int(e.clock.get("session", 0)) > 0, "text": "Start the session — the clock, the recap and the rules' once-a-session refills begin",
		"action": "Start session 1", "call": on_start_session})
	return out


func _refresh_steps(info: Dictionary) -> void:
	_clear(_steps)
	var list := steps(info) if ctx.campaign != null else []
	_start_box.visible = not list.is_empty() and not list.all(func(s: Dictionary) -> bool: return bool(s.done))
	for s in list:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = ("✓ " if bool(s.done) else "○ ") + str(s.text)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if bool(s.done):
			l.theme_type_variation = "DimLabel"
		row.add_child(l)
		if not bool(s.done) and str(s.get("action", "")) != "" and (s.get("call") as Callable).is_valid():
			var call: Callable = s.call
			_button(row, str(s.action), "", func() -> void: call.call())
		_steps.add_child(row)


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
	var info: Dictionary = host_info.call() if host_info.is_valid() else {}
	if bool(info.get("hosting", false)):
		_hosting.text = "Address  %s\nCo-GM code  %s\nConnected: %s" % [str(info.get("address", "")), str(info.get("code", "")), ", ".join(PackedStringArray(info.get("connected", []))) if not (info.get("connected", []) as Array).is_empty() else "nobody yet"]
		_host_button.text = "Stop hosting"
	else:
		_hosting.text = "Not hosting. Players cannot join until you are."
		_host_button.text = "Start hosting"
	_clock.text = "Day %d, %02d:%02d" % [int(e.clock.get("day", 1)), int(e.clock.get("minute", 0)) / 60, int(e.clock.get("minute", 0)) % 60]
	_refresh_steps(info)
	# restore points
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
