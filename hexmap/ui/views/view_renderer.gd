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
##       a field of type "list" with its own `fields` is a repeater
##   log {bind, limit}
##   picker {label, bind | collection, query, fields, search, multi, on_pick, per_page}
##       a searchable list to choose from: a bound list of strings or
##       {id, name|label}, or a compendium collection fetched through
##       `comp_source` a page at a time; the choice sends on_pick with
##       @pick (the chosen record) or, with multi, @picks (the ids) on Done
##   wizard {steps: [{title, fields}], submit (intent), label}
##       one step at a time with Back and Next; submit carries $values
##       merged from every step
##   image {bind | src, height}    pack art by ref ("pack:asset") through `packs`
##   field {label, bind, kind (a PropertyForm type), on_change (intent with $value), options}
##       one value edited in place; on_change is sent when it changes
## Unknown types render as text, so a client of version N shows a plugin
## of version N+1 legibly.

## A control was used: send this to the Table.
signal intent(payload: Dictionary)
## An intent that wants a target picked on the map first: {pick, area,
## …intent}. The window resolves the pick and sends the intent itself.
signal pick_requested(payload: Dictionary)

var schema: Dictionary = {}
var data: Dictionary = {}
## Where a picker over a collection gets its pages: Callable(collection,
## req, on_reply) shaped like Session.comp. Unset: collection pickers
## show "no compendium".
var comp_source: Callable = Callable()
## Where an image widget finds pack art (a PackLibrary); unset: a label.
var packs: PackLibrary = null
## Widget types this renderer knows; a schema may ask for more.
const KNOWN := ["column", "row", "section", "tabs", "text", "number", "pool", "track", "effects", "list", "cards", "button", "action_bar", "tracker", "prompt", "form", "log", "spacer",
	"picker", "wizard", "image", "field"]
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
		"picker": return _picker(n, ctx)
		"wizard": return _wizard(n, ctx)
		"image": return _image(n, ctx)
		"field": return _field(n, ctx)
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
		intent.emit(_put_value(fill_intent(tpl, ctx), pf.get_values(), "$values")))
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


# ------------------------------------------------------------- pickers --

## A searchable list to choose from. Options come from a bound list or a
## collection; each is shown by its `name` (or `label`, or the string
## itself) and picked by its `id`.
func _picker(n: Dictionary, ctx: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if n.has("label"):
		var title := Label.new()
		title.text = str(n.label)
		title.theme_type_variation = "HeaderLabel"
		box.add_child(title)
	var search := LineEdit.new()
	search.placeholder_text = str(n.get("placeholder", "Search…"))
	search.name = "search"
	if bool(n.get("search", true)):
		box.add_child(search)
	var list := ItemList.new()
	list.name = "options"
	list.custom_minimum_size = Vector2(0, float(n.get("height", 160)))
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var multi := bool(n.get("multi", false))
	list.select_mode = ItemList.SELECT_MULTI if multi else ItemList.SELECT_SINGLE
	box.add_child(list)
	var status := Label.new()
	status.name = "status"
	status.theme_type_variation = "DimLabel"
	box.add_child(status)
	# each row keeps the record it stands for as its metadata
	var fill := func(items: Array, total: int) -> void:
		list.clear()
		for it in items:
			list.add_item(_option_label(it))
			list.set_item_metadata(list.item_count - 1, it)
		status.text = "" if total <= items.size() else "%d of %d — narrow the search" % [items.size(), total]
		if items.is_empty():
			status.text = "Nothing matches" if search.text != "" else str(n.get("empty", "Nothing to pick"))
	var load := func() -> void:
		var q := search.text.strip_edges().to_lower()
		if n.has("collection"):
			if not comp_source.is_valid():
				status.text = "No compendium here"
				return
			var query: Dictionary = (n.get("query", {}) as Dictionary).duplicate(true) if n.get("query") is Dictionary else {}
			if q != "":
				query.text = q
			query.per_page = int(n.get("per_page", 25))
			if n.has("fields"):
				query.fields = n.fields
			var me: WeakRef = weakref(self)
			comp_source.call(str(n.collection), {"query": query}, func(reply: Dictionary) -> void:
				if me.get_ref() == null or not is_instance_valid(list):
					return
				if reply.has("error"):
					status.text = str(reply.error)
					return
				var page: Dictionary = reply.get("page", {})
				fill.call(page.get("entries", []), int(page.get("total", 0))))
		else:
			var raw: Variant = value_of(n, ctx)
			var items := []
			if raw is Dictionary:
				for k in raw:
					var rec: Variant = raw[k]
					items.append(rec if rec is Dictionary else {"id": str(k), "name": str(rec)})
			elif raw is Array:
				items = raw
			var shown := []
			for it in items:
				if q == "" or _option_label(it).to_lower().contains(q):
					shown.append(it)
			fill.call(shown, shown.size())
	search.text_changed.connect(func(_t: String) -> void: load.call())
	var tpl: Variant = n.get("on_pick", {})
	var send := func(chosen: Variant) -> void:
		var sub: Dictionary = ctx.duplicate()
		if multi:
			sub.picks = chosen
		else:
			sub.pick = chosen
			sub.pick_id = _option_id(chosen)
		intent.emit(fill_intent(tpl, sub))
	if multi:
		var done := Button.new()
		done.text = str(n.get("done_label", "Done"))
		done.theme_type_variation = "AccentButton"
		done.pressed.connect(func() -> void:
			var ids := []
			for i in list.get_selected_items():
				ids.append(_option_id(list.get_item_metadata(i)))
			send.call(ids))
		box.add_child(done)
	else:
		list.item_selected.connect(func(i: int) -> void:
			if i >= 0 and i < list.item_count:
				send.call(list.get_item_metadata(i)))
	load.call()
	return box


static func _option_label(it: Variant) -> String:
	if it is Dictionary:
		return str(it.get("name", it.get("label", it.get("id", ""))))
	return str(it)


static func _option_id(it: Variant) -> String:
	if it is Dictionary:
		return str(it.get("id", it.get("name", "")))
	return str(it)


# -------------------------------------------------------------- wizard --

## One step at a time; Back and Next; Submit sends every step's values.
func _wizard(n: Dictionary, ctx: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var steps: Array = n.get("steps", []) if n.get("steps") is Array else []
	var values := {}
	var at := [0]
	var title := Label.new()
	title.theme_type_variation = "HeaderLabel"
	box.add_child(title)
	var holder := VBoxContainer.new()
	holder.name = "step"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(holder)
	var nav := HBoxContainer.new()
	var back := Button.new()
	back.text = str(n.get("back_label", "Back"))
	back.name = "back"
	var next := Button.new()
	next.text = str(n.get("next_label", "Next"))
	next.name = "next"
	next.theme_type_variation = "AccentButton"
	nav.add_child(back)
	nav.add_child(next)
	box.add_child(nav)
	var form_ref := [null]
	var show := func() -> void:
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		if steps.is_empty():
			title.text = str(n.get("label", ""))
			next.disabled = true
			back.disabled = true
			return
		var i: int = at[0]
		var step: Dictionary = steps[i] if steps[i] is Dictionary else {}
		title.text = "%s%s (%d/%d)" % [(str(n.label) + ": ") if n.has("label") else "", str(step.get("title", "")), i + 1, steps.size()]
		var pf := PropertyForm.new()
		var fields: Array = []
		for f in step.get("fields", []):
			if f is Dictionary and f.has("key"):
				fields.append(f)
		pf.build(fields, values)
		holder.add_child(pf)
		form_ref[0] = pf
		if step.has("text"):
			var t := Label.new()
			t.text = str(step.text)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			holder.add_child(t)
			holder.move_child(t, 0)
		back.disabled = i == 0
		next.text = str(n.get("submit_label", "Submit")) if i == steps.size() - 1 else str(n.get("next_label", "Next"))
	var keep := func() -> void:
		if form_ref[0] != null:
			for k in (form_ref[0] as PropertyForm).get_values():
				values[k] = (form_ref[0] as PropertyForm).get_values()[k]
	back.pressed.connect(func() -> void:
		keep.call()
		at[0] = maxi(0, at[0] - 1)
		show.call())
	var tpl: Variant = n.get("submit", {})
	next.pressed.connect(func() -> void:
		keep.call()
		if at[0] < steps.size() - 1:
			at[0] += 1
			show.call()
			return
		intent.emit(_put_value(fill_intent(tpl, ctx), values.duplicate(true), "$values")))
	show.call()
	return box


# --------------------------------------------------------------- image --

func _image(n: Dictionary, ctx: Dictionary) -> Control:
	var ref := str(value_of(n, ctx, "src"))
	var tex: Texture2D = null
	if packs != null and ref != "":
		tex = packs.token_texture(ref, 128.0)
	if tex == null:
		var l := Label.new()
		l.text = ref if ref != "" else "(no image)"
		l.theme_type_variation = "DimLabel"
		return l
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(0, float(n.get("height", 96)))
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return tr


# --------------------------------------------------------------- field --

## One value edited in place: a PropertyForm with a single row, whose
## change sends on_change with $value.
func _field(n: Dictionary, ctx: Dictionary) -> Control:
	var pf := PropertyForm.new()
	var item := {"key": "value", "label": str(n.get("label", "")), "type": str(n.get("kind", "string"))}
	for k in ["min", "max", "step", "options", "suffix", "tooltip", "fields"]:
		if n.has(k):
			item[k] = n[k]
	var raw: Variant = at_pointer(ctx, str(n.get("bind", ""))) if n.has("bind") else n.get("value")
	pf.build([item], {"value": raw})
	var tpl: Variant = n.get("on_change", {})
	pf.value_changed.connect(func(_k: String, v: Variant) -> void:
		intent.emit(_put_value(fill_intent(tpl, ctx), v, "$value")))
	return pf


## Replace every `token` string ("$value", "$values") in an intent, at
## any depth, with the value.
static func _put_value(tpl: Variant, v: Variant, token := "$value") -> Variant:
	if tpl is String and tpl == token:
		return v
	if tpl is Dictionary:
		var out := {}
		for k in tpl:
			out[k] = _put_value(tpl[k], v, token)
		return out
	if tpl is Array:
		var out := []
		for it in tpl:
			out.append(_put_value(it, v, token))
		return out
	return tpl
