class_name GmIntents
extends RefCounted
## What happens when the DM presses a button a ruleset drew — on a sheet, in
## the party view, in a GM view: one place for every pane that renders
## rulesets' views on the Table. Actions are dispatched as the GM, their
## prompts driven to the players; `lookup` opens an entry's card; `show`
## opens something of the campaign's (a character, a person, a place) in the
## Reference pane.


## Run an intent. "" or why it did not happen (said to the DM by the caller).
static func run(ctx: TableContext, payload: Dictionary) -> String:
	match str(payload.get("kind", "")):
		"answer":
			return ctx.kernel.pending.answer(str(payload.get("prompt", "")), payload.get("answer", {}), "")
		"action":
			if ctx.host == null:
				return "no rules are loaded"
			var plugin := str(payload.get("plugin", ""))
			var c: Dictionary = payload.get("ctx", {}) if payload.get("ctx") is Dictionary else {}
			c = c.duplicate()
			if not c.has("scene") and ctx.scene_id != "":
				c.scene = ctx.scene_id
			var pc := ctx.host.dispatch(plugin, str(payload.get("action", "")), c)
			if pc.status == PluginHost.PluginCall.ERROR:
				return pc.error
			ctx.kernel.pending.drive(pc, plugin, func(done: PluginHost.PluginCall) -> void:
				if done.status == PluginHost.PluginCall.ERROR:
					ctx.say(done.error))
			return ""
		"focus":
			return ctx.kernel.turns.set_focus(str(payload.get("ref", "")), "gm")
		"lookup":
			if not ctx.lookup.is_valid():
				return "nowhere to show it"
			ctx.lookup.call(str(payload.get("collection", "")), str(payload.get("id", "")))
			return ""
		"show":
			if not ctx.show_ref.is_valid():
				return "nowhere to show it"
			var ref := str(payload.get("ref", ""))
			if ref == "" and str(payload.get("actor", "")) != "":
				ref = "actor:" + str(payload.actor)
			ctx.show_ref.call(ref)
			return ""
		"preview":
			return preview(ctx, payload)
	return "unknown intent"


## A spell's or a power's Preview (`{kind = "preview", area, actor, cast}`,
## docs/plugin-authoring.md): its shape on the map for everyone, as the DM's
## mark — at once around its caster, or where the DM points (a sphere's
## middle; a cone's way from its caster). "" or why not.
static func preview(ctx: TableContext, payload: Dictionary) -> String:
	var area: Dictionary = payload.get("area", {}) if payload.get("area") is Dictionary else {}
	var shape := preview_shape(area)
	if shape.is_empty() or ctx.map() == null:
		return "nothing to show on the map" if ctx.map() != null else "no map is shown"
	var label := str(area.get("label", ""))
	var actor := str(payload.get("actor", ""))
	var from := ""
	for tk in ctx.state.tokens(ctx.scene_id):
		if actor != "" and str(tk.get("actor", "")) == actor:
			from = str(tk.id)
			break
	var put := func(points: Array, direction: float, token: String) -> void:
		var m := {"kind": "preview", "points": points, "shape": shape, "direction": direction, "label": label, "actor": actor}
		if token != "":
			m.token = token
		if ctx.put_mark(m) != "":
			ctx.say("%s: on the map for everyone" % label)
	if str(area.get("from", "point")) == "self":
		if from == "":
			return "%s isn't on this map" % str(ctx.encounter().actor(actor).get("name", "the caster"))
		var at := Vision.token_pos(ctx.state.token(ctx.scene_id, from))
		if str(shape.type) == "circle":
			put.call([[at.x, at.y]], 0.0, from)
			return ""
		# which way it goes: the DM points (the pick shows its cells as it will be)
		var spec := Measure.template_spec({"points": [[at.x, at.y]], "token": from, "shape": shape})
		spec.erase("at")
		spec.erase("direction")
		ctx.begin_pick({"kind": "area", "area": spec, "from": from, "label": label}, func(target: Variant) -> void:
			put.call([[at.x, at.y]], float(target.get("direction", 0.0)) if target is Dictionary else 0.0, from))
		return ""
	ctx.begin_pick({"kind": "cell", "label": label}, func(target: Variant) -> void:
		var c := ctx.map().grid.cell_center(HexMap.key_cell(str(target)))
		put.call([[c.x, c.y] if not square_even(shape) else [c.x + 0.5, c.y + 0.5]], 0.0, ""))
	return ""


## What the loaded rulesets do on a template (an action registered with
## `target = "template"`: docs/plugin-authoring.md, "Table tools"), the DM's:
## [{plugin, action, label, hint}], in a steady order.
static func template_actions(ctx: TableContext) -> Array:
	var out := []
	if ctx.host == null:
		return out
	var ids := ctx.host.plugins.keys()
	ids.sort()
	for pid in ids:
		var p: PluginHost.Plugin = ctx.host.plugins[pid]
		var names := p.actions.keys()
		names.sort()
		for name in names:
			var spec: Dictionary = p.actions[name]
			if str(spec.get("target", "")) == "template":
				out.append({"plugin": str(pid), "action": str(name), "label": str(spec.get("label", name)), "hint": str(spec.get("hint", ""))})
	return out


## A ruleset's template action (template_actions) on a template or a
## preview on the map, as the DM's: sent with the creatures it catches as the
## rules lay it (MapQuery.template: `caught`, token ids) and its words
## (`label`); the ruleset asks the DM the rest. "" or why not.
static func on_template(ctx: TableContext, m: Dictionary, act: Dictionary) -> String:
	if m.is_empty() or not (str(m.get("kind", "")) in ["template", "preview"]):
		return "put a template on the map first"
	if ctx.kernel == null:
		return "no rules are loaded"
	var area := ctx.kernel.map.template(str(m.scene), Measure.template_spec(m))
	var caught: Array = (area.get("tokens", []) as Array).map(func(t: Variant) -> String: return str(t))
	if caught.is_empty():
		return "the template catches nobody"
	return run(ctx, {"kind": "action", "plugin": str(act.get("plugin", "")), "action": str(act.get("action", "")),
		"ctx": {"scene": str(m.scene), "caught": caught, "label": str(m.get("label", ""))}})


## A ruleset's preview spec as a mark's shape ({type, size, width, angle,
## origin, include_self}), or {} when it isn't one.
static func preview_shape(area: Dictionary) -> Dictionary:
	var type := str(area.get("type", ""))
	if not Marks.SHAPES.has(type) or not (area.get("size") is float or area.get("size") is int):
		return {}
	var out := {"type": type, "size": float(area.size), "origin": str(area.get("origin", "center")), "include_self": area.get("include_self", true) != false}
	if type == "line":
		out.width = float(area.get("width", 1.0))
	if type == "cone":
		out.angle = float(area.get("angle", 53.0))
	return out


## A square put at a point whose side is an even number of cells stands on the
## corner between four of them, not on one (a 20-foot cube: sixteen squares).
static func square_even(shape: Dictionary) -> bool:
	return str(shape.get("type", "")) == "square" and int(roundf(float(shape.get("size", 0.0)))) % 2 == 0


## A button that wants a target on the map first: the pick, then the intent.
## `then` hears what happened ("" or why not).
static func pick(ctx: TableContext, payload: Dictionary, then := Callable()) -> void:
	var c: Dictionary = payload.get("ctx", {}) if payload.get("ctx") is Dictionary else {}
	var from := ""
	for tk in ctx.state.tokens(ctx.scene_id):
		if str(tk.get("actor", "")) == str(c.get("actor", "")):
			from = str(tk.id)
			break
	ctx.begin_pick({"kind": str(payload.get("pick", "token")), "area": payload.get("area", {}), "from": from, "label": str(payload.get("label", "Pick"))},
		func(target: Variant) -> void:
			var p: Dictionary = payload.duplicate(true)
			for k in ["pick", "area", "label"]:
				p.erase(k)
			if not (p.get("ctx") is Dictionary):
				p.ctx = {}
			p.ctx.target = target
			p.ctx.scene = ctx.scene_id
			var why := run(ctx, p)
			if why != "":
				ctx.say(why)
			if then.is_valid():
				then.call(why))


## Where a view's picker gets its pages: the Table's own compendium, as the GM.
static func comp(ctx: TableContext, collection: String, req: Dictionary, on_reply: Callable) -> void:
	if ctx.kernel == null:
		on_reply.call({"collection": collection, "error": "no compendium here"})
		return
	if req.has("id"):
		var e := ctx.kernel.comp.entry_for(collection, str(req.id), true)
		on_reply.call({"collection": collection, "entry": e} if not e.is_empty() else {"collection": collection, "error": "no such entry"})
		return
	on_reply.call({"collection": collection, "page": ctx.kernel.comp.query_for(collection, req.get("query", {}) if req.get("query") is Dictionary else {}, true)})


## A ViewRenderer wired for the DM: intents run as the GM, picks on the map,
## pickers on the Table's compendium, the campaign's art. `after` runs after
## every intent (a pane re-rendering itself).
static func renderer(ctx: TableContext, after := Callable()) -> ViewRenderer:
	var r := ViewRenderer.new()
	r.intent.connect(func(payload: Dictionary) -> void:
		var why := run(ctx, payload)
		if why != "":
			ctx.say(why)
		if after.is_valid():
			after.call())
	r.pick_requested.connect(func(payload: Dictionary) -> void:
		pick(ctx, payload, func(_why: String) -> void:
			if after.is_valid():
				after.call()))
	r.comp_source = func(collection: String, req: Dictionary, on_reply: Callable) -> void: comp(ctx, collection, req, on_reply)
	r.packs = ctx.art
	return r
