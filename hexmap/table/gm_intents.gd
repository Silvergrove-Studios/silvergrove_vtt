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
	return "unknown intent"


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
