class_name Triggers
extends RefCounted
## Prep that fires during play (G3): a trigger is data on a scene or a
## region — when it fires and what it does — laid down before the
## session and run by the kernel when the moment comes. The host does
## the table half (read-aloud text, tokens, lights, doors, fog, tracks,
## effects, any event); the rules half is a plugin action the trigger
## dispatches. Everything a trigger does is committed as one undo step
## labelled with the trigger, and a trigger that fires once remembers it
## in the document.
##
## Trigger record (in `scene.triggers` or `region.triggers`):
##   {id, label, on, once (default true), fired, do: [step, …],
##    ref (door triggers: the wall's ref), cells (reveal triggers), state}
## `on`: enter | leave (regions) · scene (shown to the players) ·
##       door (a wall's state becomes `state`, default open) · reveal
##       (any of `cells` explored) · manual (the DM's button)
## Steps (`do`):
##   {kind: "read", text, title, audience}      a handout in the log (players see it)
##   {kind: "spawn", tokens: [{name, actor, at: [x, y] | "q,r", …token fields}]}
##   {kind: "actor", actor}                     an actor record to add (before its token)
##   {kind: "light", ref, on}                   {kind: "door", ref, state}
##   {kind: "hide", ref, hidden}                any GM-only element revealed (or hidden)
##   {kind: "reveal", cells}                    fog lifted from cells
##   {kind: "track", name, max, plugin, kind, advance, audience, on_done}
##   {kind: "effect", effect}                   an effect applied (on a ref)
##   {kind: "region", region}                   a region laid down
##   {kind: "event", ev}                        any event
##   {kind: "action", plugin, action, ctx}      the rules half: a plugin action
##   {kind: "note", text, audience}             a GM note in the log

const KINDS := ["enter", "leave", "scene", "door", "reveal", "manual"]


static func make(on: String, steps: Array, extra: Dictionary = {}) -> Dictionary:
	var t := {"id": JsonDoc.new_id("tr"), "label": "", "on": on, "once": true, "fired": false, "do": steps}
	t.merge(extra, true)
	return t


## Why a trigger record is malformed, or "".
static func check(t: Variant) -> String:
	if not (t is Dictionary):
		return "a trigger is an object"
	if str(t.get("id", "")) == "":
		return "a trigger needs an id"
	if not KINDS.has(str(t.get("on", ""))):
		return "trigger '%s': 'on' must be one of %s" % [str(t.id), KINDS]
	if not (t.get("do") is Array):
		return "trigger '%s': 'do' must be a list of steps" % str(t.id)
	for s in t.do:
		if not (s is Dictionary) or str(s.get("kind", "")) == "":
			return "trigger '%s': every step has a kind" % str(t.id)
	return ""


# --------------------------------------------------------------- lookup --

## Triggers on a scene (and, with `region_id`, on that region) that fire
## on `on` and have not fired yet (or fire every time).
static func armed(state: EncounterState, scene_id: String, on: String, region_id := "") -> Array:
	var out := []
	var holder: Dictionary = state.encounter.scene(scene_id)
	if region_id != "":
		holder = holder.get("regions", {}).get(region_id, {})
	for t in holder.get("triggers", []):
		if not (t is Dictionary) or str(t.get("on", "")) != on:
			continue
		if bool(t.get("once", true)) and bool(t.get("fired", false)):
			continue
		out.append(t)
	return out


## The triggers a batch of applied events arms: {scene, trigger, region,
## ctx} per firing. Region enter/leave come from the kernel's move path,
## not from here.
static func due(state: EncounterState, events: Array) -> Array:
	var out := []
	for ev in events:
		var t := str(ev.get("t", ""))
		match t:
			"scene.activate":
				for tr in armed(state, str(ev.id), "scene"):
					out.append({"scene": str(ev.id), "trigger": tr, "region": "", "ctx": {}})
			"element.set":
				var sid := str(ev.scene)
				var ref := str(ev.ref)
				var now := state.effective(sid, LayerTree.split(ref)[0], HexMap.find_in(state.level_for(sid), LayerTree.split(ref)[0], LayerTree.split(ref)[1]))
				for tr in armed(state, sid, "door"):
					if str(tr.get("ref", "")) != ref:
						continue
					var want := str(tr.get("state", "open"))
					if ev.changes.has("state") and str(now.get("state", "")) == want:
						out.append({"scene": sid, "trigger": tr, "region": "", "ctx": {"ref": ref, "state": want}})
			"fog.reveal":
				var sid := str(ev.scene)
				var cells := {}
				for c in ev.cells:
					cells[str(c)] = true
				for tr in armed(state, sid, "reveal"):
					var hit := ""
					for c in tr.get("cells", []):
						if cells.has(str(c)):
							hit = str(c)
							break
					if hit != "":
						out.append({"scene": sid, "trigger": tr, "region": "", "ctx": {"cell": hit}})
	return out


# ----------------------------------------------------------------- fire --

## Run a trigger: its steps as events in one step, marked fired, then
## its plugin actions dispatched (prompts driven like any action's).
## Returns "" or why it stopped; a refusal undoes the whole trigger.
static func fire(kernel: RulesKernel, scene_id: String, trigger: Dictionary, region_id := "", ctx: Dictionary = {}) -> String:
	var why_c := check(trigger)
	if why_c != "":
		return why_c
	var label := "Trigger: " + (str(trigger.get("label", "")) if str(trigger.get("label", "")) != "" else str(trigger.get("on", "")))
	var actions := []
	return kernel.transaction(label, func() -> String:
		var events := []
		for step in trigger.do:
			var got := step_events(kernel, scene_id, step, ctx)
			if got.has("error"):
				return str(got.error)
			events.append_array(got.events)
			if step.kind == "action":
				actions.append(step)
		var fired := mark_events(kernel.state, scene_id, str(trigger.id), region_id)
		var why := kernel.commit(events + fired, label, {"trigger": str(trigger.id)})
		if why != "":
			return why
		var host: PluginHost = kernel.plugin_host.get_ref() if kernel.plugin_host != null else null
		for step in actions:
			if host == null:
				return "trigger '%s' needs a plugin for %s/%s" % [str(trigger.id), str(step.get("plugin", "")), str(step.get("action", ""))]
			var actx: Dictionary = JsonDoc.deep(step.get("ctx", {})) if step.get("ctx") is Dictionary else {}
			actx.merge(ctx)
			actx.scene = scene_id
			actx.trigger = str(trigger.id)
			var pc := host.dispatch(str(step.get("plugin", "")), str(step.get("action", "")), actx)
			if pc.status == PluginHost.PluginCall.ERROR:
				return pc.error
			kernel.pending.drive(pc, str(step.get("plugin", "")))
		return "")


## The events that mark a trigger fired (an empty list when it fires
## every time).
static func mark_events(state: EncounterState, scene_id: String, trigger_id: String, region_id := "") -> Array:
	var holder: Dictionary = state.encounter.scene(scene_id)
	if region_id != "":
		holder = holder.get("regions", {}).get(region_id, {})
	var list: Array = holder.get("triggers", [])
	for i in list.size():
		if str(list[i].get("id", "")) == trigger_id:
			if not bool(list[i].get("once", true)):
				return []
			var changes := {"triggers/%d/fired" % i: true}
			if region_id != "":
				return [{"t": "region.set", "scene": scene_id, "id": region_id, "changes": changes}]
			return [{"t": "scene.set", "id": scene_id, "changes": changes}]
	return []


## The events one step means. {events} or {error}.
static func step_events(kernel: RulesKernel, scene_id: String, step: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var st := kernel.state
	var out := []
	match str(step.get("kind", "")):
		"read":
			out.append({"t": "log.add", "entry": {"id": JsonDoc.new_id("h"), "kind": "handout", "title": str(step.get("title", "")),
				"text": str(step.get("text", "")), "audience": str(step.get("audience", "all"))}})
		"note":
			out.append({"t": "log.add", "entry": {"id": JsonDoc.new_id("n"), "kind": "note", "text": str(step.get("text", "")), "audience": str(step.get("audience", "gm"))}})
		"actor":
			if not (step.get("actor") is Dictionary):
				return {"error": "an actor step needs an actor"}
			var a: Dictionary = JsonDoc.deep(step.actor)
			if str(a.get("id", "")) == "":
				a.id = JsonDoc.new_id("a")
			if st.encounter.actor(str(a.id)).is_empty():
				out.append({"t": "actor.add", "actor": a})
		"spawn":
			var m := st.map_for(scene_id)
			for spec in step.get("tokens", []):
				if not (spec is Dictionary):
					continue
				var s: Dictionary = JsonDoc.deep(spec)
				var pos := Vector2.ZERO
				var at: Variant = s.get("at")
				if at is String and m != null:
					var cell: Vector2i = m.key_cell(str(at))
					pos = m.grid.cell_center(cell)
				elif at is Array and (at as Array).size() == 2:
					pos = Vector2(float(at[0]), float(at[1]))
				s.erase("at")
				var p_name := str(s.get("name", "Token"))
				s.erase("name")
				if s.get("actor") is Dictionary:
					var a: Dictionary = s.actor
					if str(a.get("id", "")) == "":
						a.id = JsonDoc.new_id("a")
					if st.encounter.actor(str(a.id)).is_empty():
						out.append({"t": "actor.add", "actor": JsonDoc.deep(a)})
					s.actor = str(a.id)
				out.append({"t": "token.add", "scene": scene_id, "token": Encounter.new_token(p_name, pos, s)})
		"light":
			out.append({"t": "element.set", "scene": scene_id, "ref": str(step.get("ref", "")), "changes": {"on": bool(step.get("on", true))}})
		"door":
			out.append({"t": "element.set", "scene": scene_id, "ref": str(step.get("ref", "")), "changes": {"state": str(step.get("state", "open"))}})
		"hide":
			out.append({"t": "element.set", "scene": scene_id, "ref": str(step.get("ref", "")), "changes": {"hidden": bool(step.get("hidden", false))}})
		"reveal":
			var fresh := st.unexplored(scene_id, Array(step.get("cells", [])))
			if not fresh.is_empty():
				out.append({"t": "fog.reveal", "scene": scene_id, "cells": fresh})
		"track":
			var tr := Tracks.make(str(step.get("plugin", "")), str(step.get("name", "Countdown")), int(step.get("max", 4)), str(step.get("kind", "countdown")),
				step.get("advance", {}) if step.get("advance") is Dictionary else {}, str(step.get("audience", "all")), str(step.get("on_done", "")))
			if step.has("id"):
				tr.id = str(step.id)
			out.append(Tracks.add_event(tr))
		"effect":
			if not (step.get("effect") is Dictionary):
				return {"error": "an effect step needs an effect"}
			out.append_array(Effects.apply(st, step.effect))
		"region":
			if not (step.get("region") is Dictionary):
				return {"error": "a region step needs a region"}
			out.append({"t": "region.add", "scene": scene_id, "region": JsonDoc.deep(step.region)})
		"event":
			if not (step.get("ev") is Dictionary):
				return {"error": "an event step needs an ev"}
			out.append(JsonDoc.deep(step.ev))
		"action":
			pass   # dispatched after the events, by fire()
		_:
			return {"error": "unknown trigger step '%s'" % str(step.get("kind", ""))}
	return {"events": out}
