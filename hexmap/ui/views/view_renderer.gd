class_name ViewRenderer
extends VBoxContainer
## Renders a declarative view — a JSON schema a plugin registered — against
## a data document, on the Table, on a phone and in the log alike. The
## client never runs plugin code: the schema says what to show and which
## *intent* a control sends when tapped; the Table decides what it means.
##
## A node is {"type": …, …}. Values may be literal, bound (`bind`: a JSON
## pointer into the data, "/derived/defence") or computed (`expr`: an Expr
## over the data, "@derived.defence.total .. ' AC'"). An intent is a
## Dictionary; string values that start with "$/" are pointers into the
## data, filled in when sent.
##
## Types:
##   column | row | section {title} | tabs {tabs: [{title, children}]}
##   text {text | bind | expr, style: header|dim|mono}
##   number {label, bind}            a typed number with its breakdown as tooltip
##   pool {label, bind}              current / max, with optional spend/gain intents
##   track {label, bind, on_mark, on_clear}   boxes: marked, crossed
##   effects {bind}                  badges for effect records
##   list {bind, item}               a repeater; the item schema sees {item, index, ...data}
##   cards {bind, on_tap}            a hand of cards (strings or {id, label, text})
##   button {label, intent, enabled (expr), cost}
##       an intent with pick: token | cell | area (and area: {shape, …})
##       is not sent at once: the window asks for a target on the map and
##       sends it with ctx.target filled in
##   action_bar {actions: [button…]}
##   tracker {bind}                  a progress track
##   prompt {bind}                   a prompt record: its form and a Submit
##   form {fields (PropertyForm schema), submit (intent), label}
##   log {bind, limit}
## Unknown types render as text, so a client of version N shows a plugin
## of version N+1 legibly.

## A control was used: send this to the Table.
signal intent(payload: Dictionary)
## An intent that wants a target picked on the map first: {pick, area,
## …intent}. The window resolves the pick and sends the intent itself.
signal pick_requested(payload: Dictionary)

var schema: Dictionary = {}
var data: Dictionary = {}
## Widget types this renderer knows; a schema may ask for more.
const KNOWN := ["column", "row", "section", "tabs", "text", "number", "pool", "track", "effects", "list", "cards", "button", "action_bar", "tracker", "prompt", "form", "log", "spacer"]
const MAX_DEPTH := 24


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Build (or rebuild) the controls for `p_schema` over `p_data`.
func render(p_schema: Dictionary, p_data: Dictionary) -> void:
	schema = p_schema
	data = p_data
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var root := _build(schema, data, 0)
	if root != null:
		add_child(root)


## Re-render with new data (schemas rarely change; data does).
func update(p_data: Dictionary) -> void:
	render(schema, p_data)


# ------------------------------------------------------------------ values --

## The value a node shows: literal `text`/`value`, a bound pointer, or an
## expression.
static func value_of(node: Dictionary, ctx: Dictionary, key := "value") -> Variant:
	if node.has("expr"):
		return Expr.evaluate(str(node.expr), ctx)
	if node.has("bind"):
		return at_pointer(ctx, str(node.bind))
	return node.get(key, node.get("text"))


## JSON-pointer lookup: "/a/b/0" (a leading slash is optional).
static func at_pointer(doc: Variant, pointer: String) -> Variant:
	var v: Variant = doc
	for part in pointer.trim_prefix("/").split("/"):
		if part == "":
			continue
		var key := part.replace("~1", "/").replace("~0", "~")
		if v is Dictionary and (v as Dictionary).has(key):
			v = v[key]
		elif v is Array and key.is_valid_int() and int(key) >= 0 and int(key) < (v as Array).size():
			v = v[int(key)]
		else:
			return null
	return v


## An intent with its "$/pointer" strings resolved against the data.
static func fill_intent(template: Variant, ctx: Dictionary) -> Variant:
	if template is String and (template as String).begins_with("$/"):
		return at_pointer(ctx, (template as String).substr(1))
	if template is Dictionary:
		var out := {}
		for k in template:
			out[k] = fill_intent(template[k], ctx)
		return out
	if template is Array:
		var out := []
		for item in template:
			out.append(fill_intent(item, ctx))
		return out
	return template


static func _text(v: Variant) -> String:
	if v == null:
		return ""
	if v is Dictionary and TypedNumber.is_typed(v):
		return _num(v.total)
	if v is float or v is int:
		return _num(v)
	if v is String:
		return v
	return JSON.stringify(v)


static func _num(v: Variant) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, floor(f)) else "%.1f" % f


# ----------------------------------------------------------------- build --

func _build(node: Variant, ctx: Dictionary, depth: int) -> Control:
	if depth > MAX_DEPTH or not (node is Dictionary):
		return _fallback(node)
	var n: Dictionary = node
	if n.has("if") and not Expr.truthy(Expr.evaluate(str(n["if"]), ctx)):
		return null
	match str(n.get("type", "")):
		"column": return _box(n, ctx, depth, true)
		"row": return _box(n, ctx, depth, false)
		"spacer":
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sp.custom_minimum_size = Vector2(0, float(n.get("height", 8)))
			return sp
		"section":
			var box := VBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var title := Label.new()
			title.text = _text(value_of(n, ctx, "title"))
			title.theme_type_variation = "HeaderLabel"
			box.add_child(title)
			_children(n, ctx, depth, box)
			return box
		"tabs":
			var tabs := TabContainer.new()
			tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
			for tab in n.get("tabs", []):
				var page := VBoxContainer.new()
				page.name = str(tab.get("title", "Tab"))
				_children(tab, ctx, depth + 1, page)
				tabs.add_child(page)
			return tabs
		"text":
			var l := Label.new()
			l.text = _text(value_of(n, ctx, "text"))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			match str(n.get("style", "")):
				"header": l.theme_type_variation = "HeaderLabel"
				"dim": l.theme_type_variation = "DimLabel"
				"mono": l.theme_type_variation = "MonoLabel"
			return l
		"number": return _number(n, ctx)
		"pool": return _pool(n, ctx)
		"track": return _track(n, ctx)
		"effects": return _effects(n, ctx)
		"list":
			var box := VBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var items: Variant = value_of(n, ctx)
			if items is Dictionary:
				items = items.values()
			if not (items is Array):
				items = []
			var i := 0
			for item in items:
				var sub: Dictionary = ctx.duplicate()
				sub.item = item
				sub.index = i
				var c := _build(n.get("item", {"type": "text", "expr": "str(@item)"}), sub, depth + 1)
				if c != null:
					box.add_child(c)
				i += 1
			if items.is_empty() and n.has("empty"):
				var l := Label.new()
				l.text = str(n.empty)
				l.theme_type_variation = "DimLabel"
				box.add_child(l)
			return box
		"cards": return _cards(n, ctx)
		"button": return _button(n, ctx)
		"action_bar":
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for a in n.get("actions", []):
				var b := _button(a, ctx)
				if b != null:
					flow.add_child(b)
			return flow
		"tracker": return _tracker(n, ctx)
		"prompt": return _prompt(n, ctx)
		"form": return _form(n, ctx)
		"log": return _log(n, ctx)
	return _fallback(n)


func _box(n: Dictionary, ctx: Dictionary, depth: int, vertical: bool) -> Control:
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if n.has("separation"):
		box.add_theme_constant_override("separation", int(n.separation))
	_children(n, ctx, depth, box)
	return box


func _children(n: Dictionary, ctx: Dictionary, depth: int, into: Control) -> void:
	for child in n.get("children", []):
		var c := _build(child, ctx, depth + 1)
		if c != null:
			into.add_child(c)


## Anything this build does not know: its type and its value, as text.
func _fallback(node: Variant) -> Control:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.theme_type_variation = "DimLabel"
	if node is Dictionary:
		var v: Variant = value_of(node, data)
		l.text = "%s: %s" % [str(node.get("type", "?")), _text(v) if v != null else JSON.stringify(node)]
	else:
		l.text = _text(node)
	l.set_meta("fallback", true)
	return l


func _labelled(label: String, ctl: Control) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(ctl)
	return row


func _number(n: Dictionary, ctx: Dictionary) -> Control:
	var v: Variant = value_of(n, ctx)
	var l := Label.new()
	l.text = _text(v)
	l.theme_type_variation = "HeaderLabel"
	if v is Dictionary and TypedNumber.is_typed(v):
		var parts := PackedStringArray()
		for p in v.parts:
			parts.append("%s %s%s" % [str(p.get("label", "")), "+" if float(p.get("value", 0)) >= 0 else "", _num(p.get("value", 0))])
		l.tooltip_text = "\n".join(parts)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
	return _labelled(str(n.get("label", "")), l)


func _pool(n: Dictionary, ctx: Dictionary) -> Control:
	var rec: Variant = value_of(n, ctx)
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "%s / %s" % [_num(rec.get("current", 0)), _num(rec.get("max", 0))] if rec is Dictionary else "—"
	l.theme_type_variation = "HeaderLabel"
	row.add_child(l)
	for key in ["spend", "gain"]:
		if n.has(key):
			var b := Button.new()
			b.text = "−" if key == "spend" else "+"
			b.theme_type_variation = "ToolButton"
			var tpl: Variant = n[key]
			b.pressed.connect(func() -> void: intent.emit(fill_intent(tpl, ctx)))
			row.add_child(b)
	return _labelled(str(n.get("label", "")), row)


func _track(n: Dictionary, ctx: Dictionary) -> Control:
	var rec: Variant = value_of(n, ctx)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	if rec is Dictionary:
		var total := int(rec.get("max", 0)) + int(rec.get("extra", 0))
		var marked := int(rec.get("marked", 0))
		var crossed: Array = rec.get("crossed", [])
		var seen := 0
		for i in total:
			var b := Button.new()
			b.custom_minimum_size = Vector2(22, 22)
			b.focus_mode = Control.FOCUS_NONE
			if crossed.has(i):
				b.text = "✕"
				b.disabled = true
			else:
				b.text = "■" if seen < marked else "□"
				seen += 1
				var key := "on_mark" if b.text == "□" else "on_clear"
				if n.has(key):
					var tpl: Variant = n[key]
					b.pressed.connect(func() -> void: intent.emit(fill_intent(tpl, ctx)))
				else:
					b.disabled = true
			row.add_child(b)
	else:
		var l := Label.new()
		l.text = "—"
		row.add_child(l)
	return _labelled(str(n.get("label", "")), row)


func _effects(n: Dictionary, ctx: Dictionary) -> Control:
	var list: Variant = value_of(n, ctx)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if list is Array:
		for fx in list:
			if not (fx is Dictionary):
				continue
			var b := Button.new()
			b.text = str(fx.get("label", fx.get("key", "?"))) + ((" %s" % _num(fx.value)) if fx.has("value") and fx.value != null else "")
			b.tooltip_text = str(fx.get("key", ""))
			b.disabled = true
			flow.add_child(b)
	if flow.get_child_count() == 0:
		var l := Label.new()
		l.text = str(n.get("empty", "none"))
		l.theme_type_variation = "DimLabel"
		flow.add_child(l)
	return _labelled(str(n.get("label", "")), flow) if n.has("label") else flow


func _cards(n: Dictionary, ctx: Dictionary) -> Control:
	var list: Variant = value_of(n, ctx)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if list is Array:
		for card in list:
			var b := Button.new()
			var id := str(card.get("id", "")) if card is Dictionary else str(card)
			b.text = str(card.get("label", id)) if card is Dictionary else id
			if card is Dictionary and card.has("text"):
				b.tooltip_text = str(card.text)
			b.custom_minimum_size = Vector2(72, 48)
			if n.has("on_tap"):
				var sub: Dictionary = ctx.duplicate()
				sub.card = card
				sub.card_id = id
				var tpl: Variant = n.on_tap
				b.pressed.connect(func() -> void: intent.emit(fill_intent(tpl, sub)))
			flow.add_child(b)
	if flow.get_child_count() == 0:
		var l := Label.new()
		l.text = str(n.get("empty", "no cards"))
		l.theme_type_variation = "DimLabel"
		flow.add_child(l)
	return _labelled(str(n.get("label", "")), flow) if n.has("label") else flow


func _button(n: Dictionary, ctx: Dictionary) -> Control:
	var b := Button.new()
	b.text = _text(value_of(n, ctx, "label"))
	if n.has("cost") and n.cost is Dictionary and not (n.cost as Dictionary).is_empty():
		var bits := PackedStringArray()
		for k in n.cost:
			bits.append("%s %s" % [_num(n.cost[k]), str(k)])
		b.text += "  [%s]" % ", ".join(bits)
	if n.has("enabled"):
		b.disabled = not Expr.truthy(Expr.evaluate(str(n.enabled), ctx))
	if n.has("tooltip"):
		b.tooltip_text = str(n.tooltip)
	if bool(n.get("accent", false)):
		b.theme_type_variation = "AccentButton"
	if n.has("intent"):
		var tpl: Variant = n.intent
		b.pressed.connect(func() -> void:
			var payload: Variant = fill_intent(tpl, ctx)
			if payload is Dictionary and str((payload as Dictionary).get("pick", "")) != "":
				pick_requested.emit(payload)
			else:
				intent.emit(payload))
	else:
		b.disabled = true
	return b


func _tracker(n: Dictionary, ctx: Dictionary) -> Control:
	var tr: Variant = value_of(n, ctx)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tr is Dictionary:
		var l := Label.new()
		l.text = str(tr.get("name", ""))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var boxes := HBoxContainer.new()
		boxes.add_theme_constant_override("separation", 2)
		var mx := int(tr.get("max", 0))
		var v := int(tr.get("value", 0))
		var filled := v if str(tr.get("direction", "down")) == "up" else mx - v
		for i in mx:
			var b := Label.new()
			b.text = "■" if i < filled else "□"
			boxes.add_child(b)
		row.add_child(boxes)
		if bool(tr.get("done", false)):
			var d := Label.new()
			d.text = str(tr.get("on_done", "done"))
			d.theme_type_variation = "DimLabel"
			row.add_child(d)
	return row


func _prompt(n: Dictionary, ctx: Dictionary) -> Control:
	var rec: Variant = value_of(n, ctx)
	if not (rec is Dictionary):
		return null
	var form: Dictionary = rec.get("form", {}) if rec.get("form") is Dictionary else {}
	var fields: Array = form.get("fields", []) if form.get("fields") is Array else []
	return _form({"label": str(form.get("title", rec.get("title", "A question"))), "fields": fields, "values": rec.get("default", {}),
		"submit": {"kind": "answer", "prompt": str(rec.get("id", "")), "answer": "$values"}, "submit_label": str(form.get("submit", "Answer"))}, ctx)


func _form(n: Dictionary, ctx: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if n.has("label"):
		var title := Label.new()
		title.text = str(n.label)
		title.theme_type_variation = "HeaderLabel"
		box.add_child(title)
	var pf := PropertyForm.new()
	var fields: Array = []
	for f in n.get("fields", []):
		if f is Dictionary and f.has("key"):
			fields.append(f)
	pf.build(fields, n.get("values", {}) if n.get("values") is Dictionary else {})
	box.add_child(pf)
	var submit := Button.new()
	submit.text = str(n.get("submit_label", "Submit"))
	submit.theme_type_variation = "AccentButton"
	var tpl: Variant = n.get("submit", {})
	submit.pressed.connect(func() -> void:
		var payload: Variant = fill_intent(tpl, ctx)
		if payload is Dictionary:
			for k in payload:
				if payload[k] is String and payload[k] == "$values":
					payload[k] = pf.get_values()
		intent.emit(payload))
	box.add_child(submit)
	return box


func _log(n: Dictionary, ctx: Dictionary) -> Control:
	var entries: Variant = value_of(n, ctx)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if entries is Array:
		var limit := int(n.get("limit", 12))
		var start := maxi(0, entries.size() - limit)
		for i in range(start, entries.size()):
			var e: Variant = entries[i]
			if not (e is Dictionary):
				continue
			var l := Label.new()
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			match str(e.get("kind", "")):
				"roll":
					var r: Dictionary = e.get("result", {})
					l.text = "%s: %s%s" % [str(e.get("label", "Roll")), _num(r.get("total", 0)), (" — " + str(r.outcome)) if r.has("outcome") else ""]
				"note":
					l.text = str(e.get("text", ""))
					l.theme_type_variation = "DimLabel"
				_:
					l.text = JSON.stringify(e)
			box.add_child(l)
	return box
