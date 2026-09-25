class_name PartyPane
extends VBoxContainer
## The party at a glance, and the rolls a DM asks for long before a fight
## (playtest 1: most of a session is talk). Each ruleset draws it — its
## `party` view: who is here, their numbers, their conditions, "ask for a
## roll" — and a character's name opens their sheet in the Reference pane.
## A ruleset with no party view shows its GM view; with no rules at all,
## the characters by name.

var ctx: TableContext
var _body: VBoxContainer
var _renderers: Array = []
var _bound_encounter: Encounter
var _queued := false


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)


func header_actions() -> Array:
	return []


func bind() -> void:
	if _bound_encounter != null and _bound_encounter.changed.is_connected(_on_changed):
		_bound_encounter.changed.disconnect(_on_changed)
	_bound_encounter = ctx.encounter()
	_bound_encounter.changed.connect(_on_changed)
	if not ctx.campaign_changed.is_connected(_queue):
		ctx.campaign_changed.connect(_queue)
	refresh()


func _on_changed(what: String, _s: String) -> void:
	if what in ["actors", "resources", "effects", "players", "restore", "encounter", "turns", "clock"]:
		_queue()


func _queue() -> void:
	if _queued:
		return
	_queued = true
	# (a method, not a lambda: a pane freed before the frame ends is skipped)
	_flush.call_deferred()


func _flush() -> void:
	_queued = false
	refresh()


func refresh() -> void:
	for r in _renderers:
		if is_instance_valid(r):
			r.queue_free()
	_renderers.clear()
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if ctx.state == null or ctx.kernel == null:
		return
	var drawn := false
	var host := ctx.host
	if host != null:
		var projection := Views.project(ctx.kernel, host, "", Views.ROLE_GM)
		var ids := host.plugins.keys()
		ids.sort()
		for pid in ids:
			var p: PluginHost.Plugin = host.plugins[pid]
			var kind := "party" if p.views.has("party") else ("gm" if p.views.has("gm") else "")
			if kind == "":
				continue
			var r := GmIntents.renderer(ctx, _queue)
			_body.add_child(r)
			r.render(p.views[kind], Views.status_data(ctx.kernel, projection, str(pid), "", Views.ROLE_GM))
			_renderers.append(r)
			drawn = true
	if not drawn:
		_plain_party()


## No ruleset draws a party: the characters by name, each opening their card.
func _plain_party() -> void:
	var any := false
	for aid in ctx.encounter().actors:
		var a: Dictionary = ctx.encounter().actors[aid]
		if str(a.get("kind", "")) in ["pc", "companion"]:
			any = true
			var b := Button.new()
			b.text = str(a.get("name", aid))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var ref := "actor:" + str(aid)
			b.pressed.connect(func() -> void:
				if ctx.show_ref.is_valid():
					ctx.show_ref.call(ref))
			_body.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "No characters yet. Players make theirs on their phones; you can make one in Prep (Characters)."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.theme_type_variation = "DimLabel"
		_body.add_child(l)
