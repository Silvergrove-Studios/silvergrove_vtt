class_name RulesPanel
extends VBoxContainer
## The rulesets at this table and what the DM can do with them: the
## plugins loaded (and what they complained about), the actions a plugin
## offers for the selected token's actor, the prompts waiting on players
## (answer for them, or wave them through with their defaults), and the
## GM views plugins registered. Everything is drawn from the GM's
## projection (Views.project with the GM audience) and every button goes
## through the kernel, exactly as a Player's intent would.

var ctx: TableContext
var _plugins: Label
var _actions: VBoxContainer
var _prompts: VBoxContainer
var _gm: VBoxContainer
var _target: OptionButton
var _renderers: Array = []
var _log: Label


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
	_plugins = Label.new()
	_plugins.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plugins.theme_type_variation = "DimLabel"
	box.add_child(_plugins)
	var ah := Label.new()
	ah.text = "Actions"
	ah.theme_type_variation = "HeaderLabel"
	box.add_child(ah)
	var trow := HBoxContainer.new()
	var tl := Label.new()
	tl.text = "Target"
	trow.add_child(tl)
	_target = OptionButton.new()
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.tooltip_text = "The actor an action aims at (its own actor is the selected token's)"
	trow.add_child(_target)
	box.add_child(trow)
	_actions = VBoxContainer.new()
	box.add_child(_actions)
	var ph := Label.new()
	ph.text = "Waiting on players"
	ph.theme_type_variation = "HeaderLabel"
	box.add_child(ph)
	_prompts = VBoxContainer.new()
	box.add_child(_prompts)
	_gm = VBoxContainer.new()
	_gm.add_theme_constant_override("separation", 8)
	box.add_child(_gm)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.theme_type_variation = "DimLabel"
	box.add_child(_log)
	ctx.selection_changed.connect(refresh)
	ctx.encounter_changed.connect(refresh)


func bind() -> void:
	ctx.encounter().changed.connect(func(_what: String, _s: String) -> void: refresh())
	refresh()


## The actor behind the first selected token, or "".
func selected_actor() -> String:
	for s in ctx.selection:
		if s.kind == "token":
			var tk := ctx.state.token(ctx.scene_id, str(s.id))
			if not tk.is_empty() and str(tk.get("actor", "")) != "":
				return str(tk.actor)
	return ""


func selected_token() -> String:
	for s in ctx.selection:
		if s.kind == "token":
			return str(s.id)
	return ""


func refresh() -> void:
	if ctx.state == null or ctx.kernel == null:
		return
	_renderers.clear()
	for c in _actions.get_children() + _prompts.get_children() + _gm.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	var host := ctx.host
	if host == null:
		_plugins.text = "No rules runtime in this build." if not PluginHost.available() else "No plugins loaded (put them under user://plugins)."
	else:
		var lines := PackedStringArray()
		for id in host.plugins:
			var p: PluginHost.Plugin = host.plugins[id]
			lines.append("%s %s%s" % [str(p.manifest.get("name", id)), str(p.manifest.get("version", "")), (" — %d error(s)" % p.errors.size()) if not p.errors.is_empty() else ""])
		_plugins.text = "\n".join(lines) if not lines.is_empty() else "No plugins loaded (put them under user://plugins)."
	# targets: every actor with a token on this scene
	var current_target := str(_target.get_item_metadata(_target.selected)) if _target.selected >= 0 and _target.item_count > 0 else ""
	_target.clear()
	var i := 0
	for tk in ctx.state.tokens(ctx.scene_id):
		var aid := str(tk.get("actor", ""))
		if aid == "":
			continue
		_target.add_item(str(tk.get("name", aid)))
		_target.set_item_metadata(i, aid)
		if aid == current_target:
			_target.select(i)
		i += 1
	# actions for the selected token's actor
	var actor := selected_actor()
	if host != null and actor != "":
		var ids := host.plugins.keys()
		ids.sort()
		for pid in ids:
			var p: PluginHost.Plugin = host.plugins[pid]
			if p.actions.is_empty():
				continue
			var flow := HFlowContainer.new()
			var names := p.actions.keys()
			names.sort()
			for name in names:
				var spec: Dictionary = p.actions[name]
				var b := Button.new()
				b.text = str(spec.get("label", name))
				if spec.get("cost") is Dictionary and not (spec.cost as Dictionary).is_empty():
					var bits := PackedStringArray()
					for k in spec.cost:
						bits.append("%s %s" % [str(spec.cost[k]), str(k)])
					b.text += "  [%s]" % ", ".join(bits)
				b.tooltip_text = "%s / %s" % [pid, name]
				b.pressed.connect(_dispatch.bind(str(pid), str(name), str(spec.get("target", ""))))
				flow.add_child(b)
			_actions.add_child(flow)
	elif actor == "":
		var l := Label.new()
		l.text = "Select a token with an actor to see its actions."
		l.theme_type_variation = "DimLabel"
		_actions.add_child(l)
	# prompts
	var prompts := ctx.kernel.pending.prompts()
	if prompts.is_empty():
		var l := Label.new()
		l.text = "Nothing."
		l.theme_type_variation = "DimLabel"
		_prompts.add_child(l)
	var pids := prompts.keys()
	pids.sort()
	for id in pids:
		var rec: Dictionary = prompts[id]
		var row := VBoxContainer.new()
		var head := HBoxContainer.new()
		var who := Label.new()
		who.text = "%s — for %s" % [str(rec.get("title", "A question")), str(ctx.encounter().player(str(rec.get("to", ""))).get("name", rec.get("to", "?")))]
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(who)
		var dflt := Button.new()
		dflt.text = "Default"
		dflt.tooltip_text = "Answer with the default, as the deadline would"
		dflt.pressed.connect(func() -> void: ctx.say(ctx.kernel.pending.answer_default(str(id))))
		head.add_child(dflt)
		row.add_child(head)
		var r := ViewRenderer.new()
		r.intent.connect(_gm_intent)
		row.add_child(r)
		r.render({"type": "prompt", "bind": "/rec"}, {"rec": rec})
		_renderers.append(r)
		_prompts.add_child(row)
	# GM views
	if host != null:
		var projection := Views.project(ctx.kernel, host, "", Views.ROLE_GM)
		var ids := host.plugins.keys()
		ids.sort()
		for pid in ids:
			var p: PluginHost.Plugin = host.plugins[pid]
			if not p.views.has("gm"):
				continue
			var title := Label.new()
			title.text = str(p.manifest.get("name", pid))
			title.theme_type_variation = "HeaderLabel"
			_gm.add_child(title)
			var r := ViewRenderer.new()
			r.intent.connect(_gm_intent)
			_gm.add_child(r)
			r.render(p.views["gm"], Views.status_data(ctx.kernel, projection, str(pid), "", Views.ROLE_GM))
			_renderers.append(r)
	_log.text = "\n".join(ctx.plugin_log) if not ctx.plugin_log.is_empty() else ""


## The DM presses an action: the selected token's actor acts, at the
## chosen target, with prompts driven to the players.
func _dispatch(plugin: String, action: String, target_kind: String) -> void:
	var actor := selected_actor()
	if actor == "" or ctx.host == null:
		return
	var ctx_d := {"actor": actor, "token": selected_token(), "scene": ctx.scene_id}
	if target_kind == "actor" or target_kind == "ref":
		var t := str(_target.get_item_metadata(_target.selected)) if _target.selected >= 0 and _target.item_count > 0 else actor
		ctx_d.target = t if target_kind == "actor" else "actor:" + t
	elif target_kind in ["token", "cell", "area"]:
		# picked on the map: the dispatch happens when the DM taps
		var spec: Dictionary = ctx.host.plugin(plugin).actions.get(action, {})
		ctx.begin_pick({"kind": target_kind, "area": spec.get("area", {}), "from": selected_token(), "label": str(spec.get("label", action))},
			func(target: Variant) -> void:
				ctx_d.target = target
				_run(plugin, action, ctx_d))
		return
	_run(plugin, action, ctx_d)


## Dispatch with the context ready, prompts driven to the players.
func _run(plugin: String, action: String, ctx_d: Dictionary) -> void:
	var pc := ctx.host.dispatch(plugin, action, ctx_d)
	if pc.status == PluginHost.PluginCall.ERROR:
		ctx.say("%s: %s" % [action, pc.error])
		return
	ctx.kernel.pending.drive(pc, plugin, func(c: PluginHost.PluginCall) -> void:
		if c.status == PluginHost.PluginCall.ERROR:
			ctx.say("%s: %s" % [action, c.error])
		elif c.value is Dictionary:
			var bits := PackedStringArray()
			for k in c.value:
				bits.append("%s %s" % [str(k), str(c.value[k])])
			ctx.say("%s: %s" % [action, ", ".join(bits)]))
	refresh()


## The DM answering a prompt on a player's behalf, or a GM view's button.
func _gm_intent(payload: Dictionary) -> void:
	var why := ""
	match str(payload.get("kind", "")):
		"answer": why = ctx.kernel.pending.answer(str(payload.get("prompt", "")), payload.get("answer", {}), "")
		"action":
			var pc := ctx.host.dispatch(str(payload.get("plugin", "")), str(payload.get("action", "")), payload.get("ctx", {}) if payload.get("ctx") is Dictionary else {})
			why = pc.error
			if pc.status != PluginHost.PluginCall.ERROR:
				ctx.kernel.pending.drive(pc, str(payload.get("plugin", "")))
		"focus": why = ctx.kernel.turns.set_focus(str(payload.get("ref", "")), "gm")
		_: why = "unknown intent"
	if why != "":
		ctx.say(why)
	refresh()
