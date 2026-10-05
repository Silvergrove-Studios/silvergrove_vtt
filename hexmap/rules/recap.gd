class_name Recap
extends RefCounted
## The session recap (G6): what happened, from the encounter's own
## record — the informational log (rolls, notes, handouts, rulings) and
## the difference between the session-start checkpoint and now — as
## Markdown the DM edits and hands out. Nothing here asks a plugin: it is
## a reading of the document, so it works for any ruleset and after the
## session, from the saved file.
##
## `audience` picks what goes in: "all" is the players' version — what every
## player may know, nothing more: no GM note or ruling, no roll, note,
## handout, track or effect not shown to them all, no creature they haven't
## been shown (a hidden one, one added to a fight staged elsewhere) nor its
## hit points, no effect on a creature whose conditions they don't know, no
## scene they weren't shown, a creature's name only as they know it ("a
## creature"), a ruleset's words as they read them; `known` the rulesets'
## declarations of what the players know (Knowledge). "gm" is everything.


## The structured recap. {title, session, players: [{name, actors}],
## scenes, rolls: {actor: {count, outcomes: {kind: n}, best}}, notes,
## handouts, rulings, changes (the diff against the start checkpoint or
## null), tracks_done, effects_active}
static func summary(e: Encounter, audience := "gm", known: Array = []) -> Dictionary:
	var out := _summary(e, audience)
	if audience != "gm":
		_as_players_know(out, e, known)
	return out


static func _summary(e: Encounter, audience := "gm") -> Dictionary:
	var out := {"title": e.name, "session": int(e.clock.get("session", 1)), "day": int(e.clock.get("day", 1)),
		"players": [], "scenes": [], "rolls": {}, "notes": [], "handouts": [], "rulings": [], "changes": null,
		"tracks_done": [], "effects_active": []}
	for p in e.players:
		var mine := []
		var ids := e.actors.keys()
		ids.sort()
		for aid in ids:
			if str(e.actors[aid].get("owner", "")) == str(p.id):
				mine.append(str(e.actors[aid].get("name", aid)))
		out.players.append({"name": str(p.get("name", p.id)), "actors": mine})
	for sc in e.scenes:
		out.scenes.append(str(sc.get("name", sc.id)))
	for entry in e.log:
		if not Views.can_see(str(entry.get("audience", "all")), "", Views.ROLE_GM if audience == "gm" else Views.ROLE_DISPLAY):
			continue
		match str(entry.get("kind", "")):
			"roll":
				var who := str(entry.get("actor", ""))
				var name := str(e.actor(who).get("name", who)) if who != "" else "the table"
				if not out.rolls.has(name):
					out.rolls[name] = {"count": 0, "outcomes": {}, "best": 0.0, "labels": {}}
				var r: Dictionary = out.rolls[name]
				r.count += 1
				var oc := str(entry.get("result", {}).get("outcome", ""))
				if oc != "":
					r.outcomes[oc] = int(r.outcomes.get(oc, 0)) + 1
				r.best = maxf(float(r.best), float(entry.get("result", {}).get("total", 0)))
				var lbl := Knowledge.plain(str(entry.get("label", "")))
				if lbl != "":
					r.labels[lbl] = int(r.labels.get(lbl, 0)) + 1
			"note":
				out.notes.append({"text": Knowledge.plain(str(entry.get("text", ""))), "audience": str(entry.get("audience", "all")), "by": str(entry.get("plugin", ""))})
			"handout":
				out.handouts.append({"title": str(entry.get("title", "")), "text": str(entry.get("text", ""))})
			"ruling":
				out.rulings.append({"text": Knowledge.plain(str(entry.get("text", ""))), "rule": str(entry.get("rule", "")), "tags": Array(entry.get("tags", []))})
	for tid in e.tracks:
		var tr: Dictionary = e.tracks[tid]
		if bool(tr.get("done", false)) and Views.can_see(str(tr.get("audience", "all")), "", Views.ROLE_GM if audience == "gm" else Views.ROLE_DISPLAY):
			out.tracks_done.append(str(tr.get("name", tid)))
	for fid in e.effects:
		var fx: Dictionary = e.effects[fid]
		if Views.can_see(str(fx.get("audience", "all")), "", Views.ROLE_GM if audience == "gm" else Views.ROLE_DISPLAY):
			out.effects_active.append("%s on %s" % [Knowledge.plain(str(fx.get("label", fx.get("key", fid)))), _ref_name(e, str(fx.get("on", "")))])
	var start := session_start(e)
	if not start.is_empty():
		out.changes = diff(start.snapshot, e.snapshot())
	return out


## The players' version of a summary, in place: what every player may know of
## it (summary's "all"). The rolls, notes and effects were read from what all
## of them were shown; here the creatures, scenes and words go as they know them.
static func _as_players_know(out: Dictionary, e: Encounter, known: Array) -> void:
	var knows := Knowledge.knower(e.actors, known, false)
	var words := func(text: String) -> String: return Knowledge.render(text, knows)
	# the scenes they were shown: the one they see, and those the party stood in
	var shown := {}
	var shown_ids := _shown_scenes(e)
	for sc in e.scenes:
		if shown_ids.has(str(sc.id)):
			shown[str(sc.get("name", sc.id))] = true
	out.scenes = (out.scenes as Array).filter(func(n: String) -> bool: return shown.has(n))
	# rolls by who made them, as they know them (a creature whose name they don't
	# know is "A creature"); a ruleset's words as they read them
	var rolls := {}
	for entry in e.log:
		if str(entry.get("kind", "")) != "roll" or not Views.can_see(str(entry.get("audience", "all")), "", Views.ROLE_DISPLAY):
			continue
		var who := str(entry.get("actor", ""))
		var name := "the table"
		if who != "":
			var a := e.actor(who)
			name = str(a.get("name", who)) if knows.call("name", who) else Knowledge.UNKNOWN_START
		if not rolls.has(name):
			rolls[name] = {"count": 0, "outcomes": {}, "best": 0.0, "labels": {}}
		var r: Dictionary = rolls[name]
		r.count += 1
		var oc := str(entry.get("result", {}).get("outcome", ""))
		if oc != "":
			r.outcomes[oc] = int(r.outcomes.get(oc, 0)) + 1
		r.best = maxf(float(r.best), float(entry.get("result", {}).get("total", 0)))
		var lbl := str(words.call(str(entry.get("label", ""))))
		if lbl != "":
			r.labels[lbl] = int(r.labels.get(lbl, 0)) + 1
	out.rolls = rolls
	out.notes = []
	for entry in e.log:
		if str(entry.get("kind", "")) == "note" and Views.can_see(str(entry.get("audience", "all")), "", Views.ROLE_DISPLAY):
			var t := str(words.call(str(entry.get("text", ""))))
			if t != "":
				out.notes.append({"text": t, "audience": str(entry.get("audience", "all")), "by": str(entry.get("plugin", ""))})
	out.rulings = []
	# what is still on whom: only on what they know of, as they know it
	out.effects_active = []
	for fid in e.effects:
		var fx: Dictionary = e.effects[fid]
		if not Views.can_see(str(fx.get("audience", "all")), "", Views.ROLE_DISPLAY):
			continue
		var on := _known_ref(e, str(fx.get("on", "")), known)
		if on == "":
			continue
		var aid := _actor_of(e, str(fx.get("on", "")))
		if aid != "" and not Knowledge.conditions_known(e.actor(aid), known):
			continue
		out.effects_active.append("%s on %s" % [words.call(str(fx.get("label", fx.get("key", fid)))), on])
	out.tracks_done = []
	for tid in e.tracks:
		var tr: Dictionary = e.tracks[tid]
		if bool(tr.get("done", false)) and Views.can_see(str(tr.get("audience", "all")), "", Views.ROLE_DISPLAY):
			out.tracks_done.append(str(tr.get("name", tid)))
	var ch: Variant = out.get("changes")
	if not (ch is Dictionary):
		return
	var start := session_start(e)
	var before: Dictionary = start.get("snapshot", {}) if start.get("snapshot") is Dictionary else {}
	# who came and went: the party, and the creatures they have been shown, by
	# the names they know; never a creature's hit points (the party's own, theirs)
	ch.actors_added = []
	ch.actors_removed = []
	for aid in e.actors:
		if not before.get("actors", {}).has(aid) and _known_actor(e, str(aid), known):
			ch.actors_added.append(_name_as_known(e, str(aid), known))
	for aid in before.get("actors", {}):
		if not e.actors.has(aid) and not Knowledge.unowned_actor(before.actors[aid]):
			ch.actors_removed.append(str(before.actors[aid].get("name", aid)))
	ch.resources = (ch.resources as Array).filter(func(r: Dictionary) -> bool:
		var aid := _actor_of(e, str(r.get("ref", "")))
		return aid != "" and not Knowledge.unowned_actor(e.actor(aid)))
	ch.tokens_added = (ch.tokens_added as Array).filter(func(t: Dictionary) -> bool: return shown.has(str(t.scene)) and _known_token_name(e, str(t.get("id", "")), known) != "")
	for t in ch.tokens_added:
		t.name = _known_token_name(e, str(t.get("id", "")), known)
	ch.tokens_removed = (ch.tokens_removed as Array).filter(func(t: Dictionary) -> bool: return shown.has(str(t.scene)) and bool(t.get("party", false)))
	ch.tracks = (ch.tracks as Array).filter(func(t: Dictionary) -> bool: return Views.can_see(str(e.tracks.get(str(t.get("id", "")), {}).get("audience", "all")), "", Views.ROLE_DISPLAY))
	ch.effects_added = []
	ch.effects_removed = []
	ch.state = []


## A token of the party: a player's, or a player's character's.
static func _party_token(e: Encounter, tk: Dictionary) -> bool:
	if tk.get("owner", null) != null and str(tk.owner) != "":
		return true
	return str(tk.get("actor", "")) != "" and str(e.actor(str(tk.actor)).get("owner", "")) != ""


static func _actor_of(e: Encounter, ref: String) -> String:
	if ref.begins_with("actor:"):
		return ref.substr(6)
	if ref.begins_with("token:"):
		for sc in e.scenes:
			var tk := Encounter.token_in(sc, ref.substr(6))
			if not tk.is_empty():
				return str(tk.get("actor", ""))
	return ""


## The scenes the players were shown: the one they see, and those the party
## stood in (not a fight staged elsewhere). {id: true}
static func _shown_scenes(e: Encounter) -> Dictionary:
	var out := {}
	for sc in e.scenes:
		if str(sc.id) == e.active_scene_id or (sc.get("tokens", []) as Array).any(func(tk: Dictionary) -> bool: return _party_token(e, tk)):
			out[str(sc.id)] = true
	return out


## Whether the players know of an actor at all: the party's, one listed to
## them, or a creature with a token the DM hasn't hidden on a scene they were
## shown.
static func _known_actor(e: Encounter, aid: String, known: Array) -> bool:
	var a := e.actor(aid)
	if a.is_empty():
		return false
	if not Knowledge.unowned_actor(a) or str(a.get("audience", {}).get("visible", "")) == "all":
		return true
	var shown := _shown_scenes(e)
	for sc in e.scenes:
		if not shown.has(str(sc.id)):
			continue
		for tk in sc.get("tokens", []):
			if str(tk.get("actor", "")) == aid and not bool(tk.get("hidden", false)):
				return true
	return false


static func _name_as_known(e: Encounter, aid: String, known: Array) -> String:
	var a := e.actor(aid)
	return str(a.get("name", aid)) if Knowledge.name_known(a, known) else Knowledge.UNKNOWN_START


## A ref ("actor:", "token:") as the players know what it is on: "" for one
## they don't know of.
static func _known_ref(e: Encounter, ref: String, known: Array) -> String:
	if ref.begins_with("token:"):
		return _known_token_name(e, ref.substr(6), known)
	if ref.begins_with("actor:"):
		var aid := ref.substr(6)
		return _name_as_known(e, aid, known) if _known_actor(e, aid, known) else ""
	return "the table" if ref == "encounter" else ""


## A token's name as the players know it, "" for one they don't know of (the
## DM hides it).
static func _known_token_name(e: Encounter, tid: String, known: Array) -> String:
	var shown := _shown_scenes(e)
	for sc in e.scenes:
		if not shown.has(str(sc.id)):
			continue
		var tk := Encounter.token_in(sc, tid)
		if tk.is_empty():
			continue
		if bool(tk.get("hidden", false)):
			return ""
		if Knowledge.nameless(tk, e.actors, known):
			return Knowledge.UNKNOWN_START
		return str(tk.get("name", tid))
	return ""


## The most recent checkpoint whose name starts with "Session", or {}.
static func session_start(e: Encounter) -> Dictionary:
	var found := {}
	for cp in e.checkpoints:
		if str(cp.get("name", "")).begins_with("Session"):
			found = cp
	return found


## What changed between two snapshots, as plain data: actors added and
## removed, resources moved (per actor, plugin, name: from → to), tracks
## moved, tokens added/removed per scene, the clock, plugin state keys
## that changed. Enough for "what happened since" beside a checkpoint.
static func diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {"actors_added": [], "actors_removed": [], "resources": [], "tracks": [], "tokens_added": [], "tokens_removed": [],
		"clock": {}, "state": [], "effects_added": [], "effects_removed": []}
	var aa: Dictionary = a.get("actors", {})
	var ba: Dictionary = b.get("actors", {})
	for id in ba:
		if not aa.has(id):
			out.actors_added.append(str(ba[id].get("name", id)))
	for id in aa:
		if not ba.has(id):
			out.actors_removed.append(str(aa[id].get("name", id)))
	var ar: Dictionary = a.get("resources", {})
	var br: Dictionary = b.get("resources", {})
	var refs := {}
	for r in ar:
		refs[r] = true
	for r in br:
		refs[r] = true
	var ref_ids := refs.keys()
	ref_ids.sort()
	for ref in ref_ids:
		var plugins := {}
		for p in ar.get(ref, {}):
			plugins[p] = true
		for p in br.get(ref, {}):
			plugins[p] = true
		for p in plugins:
			var names := {}
			for n in ar.get(ref, {}).get(p, {}):
				names[n] = true
			for n in br.get(ref, {}).get(p, {}):
				names[n] = true
			for n in names:
				var before: Dictionary = ar.get(ref, {}).get(p, {}).get(n, {})
				var after: Dictionary = br.get(ref, {}).get(p, {}).get(n, {})
				var fb: Variant = before.get("current", before.get("marked", null))
				var fa: Variant = after.get("current", after.get("marked", null))
				if not JsonDoc.same(fb, fa):
					var who := _snapshot_ref_name(b, str(ref))
					if who == str(ref):
						who = _snapshot_ref_name(a, str(ref))
					if who == str(ref):
						continue   # a record whose owner is gone from both: noise
					out.resources.append({"ref": str(ref), "who": who, "plugin": str(p), "name": str(n), "from": fb, "to": fa})
	var at: Dictionary = a.get("tracks", {})
	var bt: Dictionary = b.get("tracks", {})
	for id in bt:
		var before: Dictionary = at.get(id, {})
		if before.is_empty():
			out.tracks.append({"id": str(id), "name": str(bt[id].get("name", id)), "from": null, "to": bt[id].get("value"), "done": bool(bt[id].get("done", false))})
		elif not JsonDoc.same(before.get("value"), bt[id].get("value")) or bool(before.get("done", false)) != bool(bt[id].get("done", false)):
			out.tracks.append({"id": str(id), "name": str(bt[id].get("name", id)), "from": before.get("value"), "to": bt[id].get("value"), "done": bool(bt[id].get("done", false))})
	var ascenes := {}
	for sc in a.get("scenes", []):
		ascenes[str(sc.id)] = sc
	for sc in b.get("scenes", []):
		var before: Dictionary = ascenes.get(str(sc.id), {})
		var had := {}
		for tk in before.get("tokens", []):
			had[str(tk.id)] = tk
		var have := {}
		for tk in sc.get("tokens", []):
			have[str(tk.id)] = tk
			if not had.has(str(tk.id)):
				out.tokens_added.append({"scene": str(sc.get("name", sc.id)), "name": str(tk.get("name", tk.id)), "id": str(tk.id)})
		for id in had:
			if not have.has(id):
				out.tokens_removed.append({"scene": str(sc.get("name", sc.id)), "name": str(had[id].get("name", id)), "id": str(id), "party": had[id].get("owner") != null and str(had[id].get("owner")) != ""})
	for k in b.get("clock", {}):
		if not JsonDoc.same(a.get("clock", {}).get(k), b.clock[k]):
			out.clock[k] = {"from": a.get("clock", {}).get(k), "to": b.clock[k]}
	var ae: Dictionary = a.get("effects", {})
	var be: Dictionary = b.get("effects", {})
	for id in be:
		if not ae.has(id):
			out.effects_added.append("%s on %s" % [str(be[id].get("label", be[id].get("key", id))), _snapshot_ref_name(b, str(be[id].get("on", "")))])
	for id in ae:
		if not be.has(id):
			out.effects_removed.append("%s on %s" % [str(ae[id].get("label", ae[id].get("key", id))), _snapshot_ref_name(a, str(ae[id].get("on", "")))])
	for scope in ["state", "campaign"]:
		var ax: Dictionary = a.get(scope, {}).get("ext", {})
		var bx: Dictionary = b.get(scope, {}).get("ext", {})
		for p in bx:
			for k in bx[p]:
				if not JsonDoc.same(ax.get(p, {}).get(k), bx[p][k]):
					out.state.append({"scope": scope, "plugin": str(p), "key": str(k), "from": ax.get(p, {}).get(k), "to": bx[p][k]})
	return out


## Whether a diff says anything at all.
static func diff_is_empty(d: Dictionary) -> bool:
	for k in d:
		var v: Variant = d[k]
		if (v is Array and not (v as Array).is_empty()) or (v is Dictionary and not (v as Dictionary).is_empty()):
			return false
	return true


# -------------------------------------------------------------- markdown --

static func markdown(e: Encounter, audience := "gm", known: Array = []) -> String:
	var s := summary(e, audience, known)
	var lines := PackedStringArray()
	lines.append("# %s — session %d" % [s.title, s.session])
	lines.append("")
	lines.append("_Day %d%s_" % [s.day, "" if audience == "gm" else " · players' recap"])
	lines.append("")
	if not s.players.is_empty():
		lines.append("## Who was there")
		lines.append("")
		for p in s.players:
			lines.append("- **%s**%s" % [p.name, (" — " + ", ".join(PackedStringArray(p.actors))) if not p.actors.is_empty() else ""])
		lines.append("")
	if not s.scenes.is_empty():
		lines.append("## Where")
		lines.append("")
		for sc in s.scenes:
			lines.append("- " + sc)
		lines.append("")
	if not s.handouts.is_empty():
		lines.append("## Read aloud")
		lines.append("")
		for h in s.handouts:
			if h.title != "":
				lines.append("**%s**" % h.title)
				lines.append("")
			lines.append("> " + h.text.replace("\n", "\n> "))
			lines.append("")
	var changes: Variant = s.changes
	if changes is Dictionary and not diff_is_empty(changes):
		lines.append("## What changed")
		lines.append("")
		for n in changes.actors_added:
			lines.append("- %s joined" % n)
		for n in changes.actors_removed:
			lines.append("- %s is gone" % n)
		for t in changes.tokens_added:
			lines.append("- %s appeared in %s" % [t.name, t.scene])
		for t in changes.tokens_removed:
			lines.append("- %s left %s" % [t.name, t.scene])
		for r in changes.resources:
			lines.append("- %s: %s %s→ %s" % [r.who, r.name, (_num(r.from) + " ") if r.from != null else "", _num(r.to) if r.to != null else "gone"])
		for t in changes.tracks:
			lines.append("- %s: %s → %s%s" % [t.name, "new" if t.from == null else str(t.from), str(t.to), " (done)" if t.done else ""])
		for x in changes.effects_added:
			lines.append("- gained: " + x)
		for x in changes.effects_removed:
			lines.append("- ended: " + x)
		for k in changes.clock:
			lines.append("- clock %s: %s → %s" % [k, str(changes.clock[k].from), str(changes.clock[k].to)])
		if audience == "gm":
			for x in changes.state:
				lines.append("- %s state %s/%s: %s → %s" % [x.scope, x.plugin, x.key, str(x.from), str(x.to)])
		lines.append("")
	if not s.rolls.is_empty():
		lines.append("## Dice")
		lines.append("")
		var names: Array = s.rolls.keys()
		names.sort()
		for n in names:
			var r: Dictionary = s.rolls[n]
			var bits := PackedStringArray()
			var ocs: Array = r.outcomes.keys()
			ocs.sort()
			for oc in ocs:
				bits.append("%d %s" % [int(r.outcomes[oc]), str(oc)])
			lines.append("- **%s**: %d roll%s%s, best %s" % [n, r.count, "" if r.count == 1 else "s", (" (" + ", ".join(bits) + ")") if not bits.is_empty() else "", str(r.best)])
		lines.append("")
	if not s.tracks_done.is_empty():
		lines.append("## Done")
		lines.append("")
		for t in s.tracks_done:
			lines.append("- " + t)
		lines.append("")
	if not s.effects_active.is_empty():
		lines.append("## Still in effect")
		lines.append("")
		for x in s.effects_active:
			lines.append("- " + x)
		lines.append("")
	if not s.notes.is_empty():
		lines.append("## Notes")
		lines.append("")
		for n in s.notes:
			lines.append("- %s%s" % [n.text, " _(GM)_" if n.audience == "gm" else ""])
		lines.append("")
	if audience == "gm" and not s.rulings.is_empty():
		lines.append("## Rulings")
		lines.append("")
		for r in s.rulings:
			lines.append("- %s%s%s" % [r.text, (" — _" + r.rule + "_") if r.rule != "" else "", (" `" + "` `".join(PackedStringArray(r.tags)) + "`") if not r.tags.is_empty() else ""])
		lines.append("")
	return "\n".join(lines)


## "6" for 6.0, "6.5" for 6.5.
static func _num(v: Variant) -> String:
	if v is float and is_equal_approx(v, floorf(v)):
		return str(int(v))
	return str(v)


static func _ref_name(e: Encounter, ref: String) -> String:
	if ref.begins_with("actor:"):
		return str(e.actor(ref.substr(6)).get("name", ref))
	if ref.begins_with("token:"):
		for sc in e.scenes:
			var tk := Encounter.token_in(sc, ref.substr(6))
			if not tk.is_empty():
				return str(tk.get("name", ref))
	return ref if ref != "encounter" else "the table"


static func _snapshot_ref_name(snap: Dictionary, ref: String) -> String:
	if ref.begins_with("actor:"):
		return str(snap.get("actors", {}).get(ref.substr(6), {}).get("name", ref))
	if ref.begins_with("token:"):
		for sc in snap.get("scenes", []):
			for tk in sc.get("tokens", []):
				if str(tk.get("id", "")) == ref.substr(6):
					return str(tk.get("name", ref))
	return ref if ref != "encounter" else "the table"
