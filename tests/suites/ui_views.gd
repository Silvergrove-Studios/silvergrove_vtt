extends TestCase
## ViewRenderer: declarative views drawn from data, intents from taps,
## unknown widgets as text.


func _find(root: Node, cls: String, text := "") -> Node:
	if root.get_class() == cls and (text == "" or ("text" in root and str(root.text).contains(text))):
		return root
	for c in root.get_children():
		var f := _find(c, cls, text)
		if f != null:
			return f
	return null


func _count(root: Node, cls: String) -> int:
	var n := 1 if root.get_class() == cls else 0
	for c in root.get_children():
		n += _count(c, cls)
	return n


func test_view_renderer_widgets() -> void:
	var r := ViewRenderer.new()
	root.add_child(r)
	var sent := []
	r.intent.connect(func(p: Dictionary) -> void: sent.append(p))
	var data := {
		"actor": {"id": "a_1", "name": "Ana", "mine": true},
		"derived": {"defence": TypedNumber.make([{"label": "base", "type": "base", "value": 10}, {"label": "agility", "type": "ability", "value": 3}]), "hand": ["dash", {"id": "rally", "label": "Rally!", "text": "heal"}], "label": "Level 2"},
		"resources": {"hp": {"kind": "pool", "current": 4, "max": 9}, "armour": {"kind": "track", "max": 3, "marked": 1, "extra": 1, "crossed": [3]}},
		"effects": [{"key": "shaken", "label": "Shaken", "value": 2}],
		"tracks": [{"name": "Doom", "kind": "countdown", "value": 1, "max": 3, "direction": "down"}],
		"prompts": [{"id": "p_1", "to": "pl_1", "form": {"title": "Spend armour?", "fields": [{"key": "spend", "type": "bool", "label": "Spend"}]}, "default": {"spend": true}}],
		"log": [{"kind": "roll", "label": "Strike", "result": {"total": 17, "outcome": "hit"}}, {"kind": "note", "text": "hello"}],
	}
	var schema := {"type": "column", "children": [
		{"type": "text", "bind": "/actor/name", "style": "header"},
		{"type": "text", "expr": "'Level ' .. 2 .. ' ' .. @actor.name"},
		{"type": "number", "label": "Defence", "bind": "/derived/defence"},
		{"type": "pool", "label": "HP", "bind": "/resources/hp", "spend": {"kind": "action", "plugin": "p", "action": "hurt", "ctx": {"actor": "$/actor/id"}}},
		{"type": "track", "label": "Armour", "bind": "/resources/armour", "on_mark": {"kind": "action", "action": "mark", "ctx": {"actor": "$/actor/id"}}},
		{"type": "effects", "bind": "/effects"},
		{"type": "cards", "bind": "/derived/hand", "on_tap": {"kind": "action", "action": "play", "ctx": {"card": "$/card_id", "actor": "$/actor/id"}}},
		{"type": "action_bar", "actions": [{"type": "button", "label": "Act", "cost": {"actions": 1}, "intent": {"kind": "action", "action": "act"}}, {"type": "button", "label": "Never", "enabled": "@actor.mine == false", "intent": {"kind": "x"}}]},
		{"type": "list", "bind": "/tracks", "item": {"type": "tracker", "bind": "/item"}},
		{"type": "prompt", "bind": "/prompts/0"},
		{"type": "log", "bind": "/log"},
		{"type": "hologram", "label": "3D", "bind": "/derived/label"},
		{"type": "section", "title": "Hidden", "if": "@actor.mine == false", "children": [{"type": "text", "text": "never"}]},
	]}
	r.render(schema, data)
	await tree.process_frame
	check(_find(r, "Label", "Ana") != null, "a bound text")
	check(_find(r, "Label", "Level 2 Ana") != null, "an expression text")
	var def := _find(r, "Label", "13")
	check(def != null and def.tooltip_text.contains("agility +3"), "a typed number with its breakdown as tooltip: %s" % [def.tooltip_text if def != null else "none"])
	check(_find(r, "Label", "4 / 9") != null, "a pool")
	var boxes := 0
	var crossed := 0
	for b in _all(r, "Button"):
		if b.text == "■" or b.text == "□":
			boxes += 1
		if b.text == "✕":
			crossed += 1
	check(boxes == 3 and crossed == 1, "a track: 3 + 1 boxes, one crossed out (%d boxes, %d crossed)" % [boxes, crossed])
	check(_find(r, "Button", "Shaken 2") != null, "an effect badge with its value")
	check(_find(r, "Button", "dash") != null and _find(r, "Button", "Rally!") != null, "cards from strings and from records")
	var act := _find(r, "Button", "Act  [1 actions]")
	check(act != null and not act.disabled, "an action button with its cost")
	check(_find(r, "Button", "Never").disabled, "an enabled expression that is false disables the button")
	check(_find(r, "Label", "Doom") != null and _find(r, "Label", "■") != null, "a tracker")
	check(_find(r, "Label", "Spend armour?") != null and _find(r, "CheckBox") != null and _find(r, "Button", "Answer") != null, "a prompt renders its form and an Answer button")
	check(_find(r, "Label", "Strike: 17 — hit") != null and _find(r, "Label", "hello") != null, "log entries")
	var holo := _find(r, "Label", "hologram")
	check(holo != null and holo.text.contains("Level 2") and holo.has_meta("fallback"), "an unknown widget renders as text with its value: %s" % [holo.text if holo != null else ""])
	check(_find(r, "Label", "never") == null, "an `if` that is false hides the node")
	# intents
	act.pressed.emit()
	_find(r, "Button", "dash").pressed.emit()
	_find(r, "Button", "−").pressed.emit()
	var mark := _find(r, "Button", "□")
	mark.pressed.emit()
	_find(r, "Button", "Answer").pressed.emit()
	check(sent.size() == 5, "five intents sent: %d" % sent.size())
	check(sent[0] == {"kind": "action", "action": "act"}, "a plain intent")
	check(sent[1].ctx.card == "dash" and sent[1].ctx.actor == "a_1", "'$/pointer' values are filled from the data (and the card): %s" % [sent[1]])
	check(sent[2].ctx.actor == "a_1", "the pool's spend intent")
	check(sent[3].kind == "action" and sent[3].action == "mark", "the track's mark intent")
	check(sent[4].kind == "answer" and sent[4].prompt == "p_1" and sent[4].answer.spend == true, "the prompt's answer carries the form's values: %s" % [sent[4]])
	# rebuild with new data
	data.resources.hp.current = 2
	r.update(data)
	await tree.process_frame
	check(_find(r, "Label", "2 / 9") != null and _find(r, "Label", "4 / 9") == null, "update redraws from the new data")
	r.queue_free()
	await tree.process_frame


func _all(root: Node, cls: String) -> Array:
	var out := []
	if root.get_class() == cls:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all(c, cls))
	return out


func test_view_helpers() -> void:
	var doc := {"a": {"b": [1, {"c": "x"}]}, "k/y": 2}
	check(ViewRenderer.at_pointer(doc, "/a/b/1/c") == "x" and ViewRenderer.at_pointer(doc, "a/b/0") == 1 and ViewRenderer.at_pointer(doc, "/a/zz") == null and ViewRenderer.at_pointer(doc, "/k~1y") == 2, "JSON pointers, escapes included")
	check(ViewRenderer.fill_intent({"x": "$/a/b/1/c", "y": ["$/k~1y", "lit"], "z": "$notapointer"}, doc) == {"x": "x", "y": [2, "lit"], "z": "$notapointer"}, "fill_intent resolves $/ strings deep inside")
	check(ViewRenderer.value_of({"expr": "@a.b[0] + 1"}, doc) == 2.0 and ViewRenderer.value_of({"bind": "/k~1y"}, doc) == 2 and ViewRenderer.value_of({"text": "t"}, doc, "text") == "t", "value_of: expr, bind, literal")
	var r := ViewRenderer.new()
	root.add_child(r)
	r.render({"type": "column", "children": [{"type": "column", "children": [{"type": "text", "text": "deep"}]}]}, {})
	check(_find(r, "Label", "deep") != null, "nested columns")
	r.render({"type": "text", "text": "top"}, {})
	check(_find(r, "Label", "top") != null and _find(r, "Label", "deep") == null, "render replaces")
	r.render({"type": "list", "bind": "/nope", "empty": "nothing here"}, {})
	check(_find(r, "Label", "nothing here") != null, "a list with no data shows its empty text")
	r.queue_free()
	await tree.process_frame
