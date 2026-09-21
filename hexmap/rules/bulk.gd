class_name Bulk
extends RefCounted
## Bulk operations (G13): one thing done to many targets as one undo
## step — an effect on everything in a template, a pool spent on every
## selected token, a save rolled for a group with a different outcome
## applied per result, a horde moved together, an action dispatched for
## each. Targets are refs (`token:<id>`, `actor:<id>`); operations are
## data, so the Table's dialog, a plugin (`hm.bulk`) and a test speak the
## same thing.
##
## op = {kind, …}:
##   effect    {effect}                                   applied on each target (its `on` is set here)
##   resource  {plugin, name, delta}                      spent (negative) or gained per target's actor
##   set       {changes}                                  token.set on each token target
##   move      {delta: [dx, dy]}                          each token moved by the same step (through the kernel)
##   remove    {}                                         each token removed
##   roll      {spec, ctx, label, per: {outcome: [op…]}}  one roll per target (ctx.actor is the target's actor),
##                                                        then the ops listed under its outcome ("" for any)
##   action    {plugin, action, ctx}                      the plugin action dispatched per target (ctx.actor/target set)
##   each      {ops: [op…]}                               several ops per target, in order


## Run `op` over `targets` as one step. {ok, why, results: [{ref, …}]}.
## A refusal on any target undoes everything.
static func run(kernel: RulesKernel, targets: Array, op: Dictionary, label := "") -> Dictionary:
	var results := []
	var lbl := label if label != "" else "Bulk %s (%d)" % [str(op.get("kind", "")), targets.size()]
	var why := kernel.transaction(lbl, func() -> String:
		for ref in targets:
			var r := _one(kernel, str(ref), op, lbl)
			results.append(r)
			if r.has("error"):
				return "%s: %s" % [str(ref), str(r.error)]
		return "")
	return {"ok": why == "", "why": why, "results": results}


## Refs for what a template covers, a selection, or a scene's tokens.
static func refs_for_tokens(ids: Array) -> Array:
	var out := []
	for id in ids:
		out.append("token:" + str(id))
	return out


static func _one(kernel: RulesKernel, ref: String, op: Dictionary, label: String) -> Dictionary:
	var st := kernel.state
	var actor := kernel.actor_of_ref(ref)
	var tk := st.find_token(ref.substr(6)) if ref.begins_with("token:") else {}
	var scene_id := ""
	if not tk.is_empty():
		for sc in st.encounter.scenes:
			if not Encounter.token_in(sc, str(tk.id)).is_empty():
				scene_id = str(sc.id)
	if tk.is_empty() and actor == "" and ref != "encounter":
		return {"ref": ref, "error": "no such target"}
	match str(op.get("kind", "")):
		"effect":
			if not (op.get("effect") is Dictionary):
				return {"ref": ref, "error": "an effect op needs an effect"}
			var fx: Dictionary = JsonDoc.deep(op.effect)
			fx.on = ref
			fx.erase("id")
			var events := Effects.apply(st, fx)
			var why := kernel.commit(events, label)
			return {"ref": ref, "error": why} if why != "" else {"ref": ref, "events": events.size()}
		"resource":
			var who := ("actor:" + actor) if actor != "" else ref
			var delta := float(op.get("delta", 0))
			var ev := Resources.spend(st, who, str(op.get("plugin", "")), str(op.get("name", "")), -delta) if delta < 0 else Resources.gain(st, who, str(op.get("plugin", "")), str(op.get("name", "")), delta)
			if ev.is_empty():
				# nothing to take from (no such pool, or not enough): floor at zero rather than refuse
				var rec := Resources.get_record(st, who, str(op.get("plugin", "")), str(op.get("name", "")))
				if rec.get("kind") == Resources.POOL and delta < 0:
					var next: Dictionary = JsonDoc.deep(rec)
					next.current = 0.0
					ev = Resources.set_event(who, str(op.get("plugin", "")), str(op.get("name", "")), next)
				else:
					return {"ref": ref, "skipped": "no pool %s" % str(op.get("name", ""))}
			var why := kernel.commit([ev], label)
			return {"ref": ref, "error": why} if why != "" else {"ref": ref, "now": ev.record.current}
		"set":
			if tk.is_empty():
				return {"ref": ref, "skipped": "not a token"}
			var why := kernel.commit([{"t": "token.set", "scene": scene_id, "id": str(tk.id), "changes": JsonDoc.deep(op.get("changes", {}))}], label)
			return {"ref": ref, "error": why} if why != "" else {"ref": ref}
		"move":
			if tk.is_empty():
				return {"ref": ref, "skipped": "not a token"}
			var d: Array = op.get("delta", [0, 0])
			var to := Vision.token_pos(tk) + Vector2(float(d[0]), float(d[1]))
			var why := kernel.move_token(scene_id, str(tk.id), to, str(op.get("by", "gm")))
			return {"ref": ref, "error": why} if why != "" else {"ref": ref, "to": [to.x, to.y]}
		"remove":
			if tk.is_empty():
				return {"ref": ref, "skipped": "not a token"}
			var why := kernel.commit([{"t": "token.remove", "scene": scene_id, "id": str(tk.id)}], label)
			return {"ref": ref, "error": why} if why != "" else {"ref": ref}
		"roll":
			var ctx: Dictionary = JsonDoc.deep(op.get("ctx", {})) if op.get("ctx") is Dictionary else {}
			if actor != "":
				ctx.actor = actor
			ctx.ref = ref
			var entry := kernel.roll(op.get("spec", "1d20"), ctx, str(op.get("label", "Save")))
			if entry.is_empty():
				return {"ref": ref, "error": kernel.last_veto}
			var outcome := str(entry.result.get("outcome", ""))
			var per: Dictionary = op.get("per", {}) if op.get("per") is Dictionary else {}
			var then: Array = per.get(outcome, per.get("", []))
			var out := {"ref": ref, "roll": entry.id, "total": entry.result.total, "outcome": outcome, "then": []}
			for sub in then:
				var r := _one(kernel, ref, sub, label)
				out.then.append(r)
				if r.has("error"):
					return {"ref": ref, "error": r.error}
			return out
		"action":
			var host: PluginHost = kernel.plugin_host.get_ref() if kernel.plugin_host != null else null
			if host == null:
				return {"ref": ref, "error": "no plugins here"}
			var ctx: Dictionary = JsonDoc.deep(op.get("ctx", {})) if op.get("ctx") is Dictionary else {}
			if not ctx.has("actor") and actor != "":
				ctx.actor = actor
			if not tk.is_empty():
				ctx.token = str(tk.id)
				ctx.scene = scene_id
			if not ctx.has("target"):
				ctx.target = ref
			var pc := host.dispatch(str(op.get("plugin", "")), str(op.get("action", "")), ctx)
			if pc.status == PluginHost.PluginCall.ERROR:
				return {"ref": ref, "error": pc.error}
			kernel.pending.drive(pc, str(op.get("plugin", "")))
			return {"ref": ref, "value": pc.value}
		"each":
			var out := {"ref": ref, "then": []}
			for sub in op.get("ops", []):
				var r := _one(kernel, ref, sub, label)
				out.then.append(r)
				if r.has("error"):
					return {"ref": ref, "error": r.error}
			return out
	return {"ref": ref, "error": "unknown bulk op '%s'" % str(op.get("kind", ""))}
