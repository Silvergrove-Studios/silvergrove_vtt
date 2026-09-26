class_name WebDm
extends RefCounted
## The DM's web screen, as the Table sees it: what it is shown of the
## campaign (`state`) and what it may do (`op`). The screen reads the
## rules through its projection (a GM view, like a co-DM's) and the scene
## as a snapshot (WebScene); this is the rest — the places, the people and
## what the DM knows of them, the maps and the prepared fights, the
## journal, the pictures, the DM's own arrangement of the contents, what
## has been shown — and the operations behind its buttons, run through the
## Table's own panes and commands so the Godot Table and the web screen
## stay one table.

var win: TableWindow


func _init(p_win: TableWindow) -> void:
	win = p_win


# ------------------------------------------------------------------ state --

## Everything the DM's web screen draws that is not in its view or scene.
func state() -> Dictionary:
	var ctx := win.ctx
	var c := ctx.campaign
	var e := ctx.encounter()
	var n := int(e.clock.get("session", 0))
	var open := c != null and n > 0 and not c.session_entry(n).is_empty() and not c.session_entry(n).has("ended")
	var out := {"campaign": {"name": c.name if c != null else e.name, "id": c.id if c != null else "", "saved": not ctx.campaign_dirty()},
		"session": {"n": n, "open": open, "day": int(e.clock.get("day", 1)), "minute": int(e.clock.get("minute", 0))},
		"hosting": {"urls": Array(win.host.join_urls()) if win.host != null else [], "online": Array(win.host.connected_players()) if win.host != null else []},
		"places": [], "maps": [], "encounters": [], "people": [], "journal": [], "pictures": [], "shown": [],
		"contents": {}, "player_notes": [], "party": {}, "party_views": [], "cards": {}, "sections": [], "rules": []}
	if c == null:
		return out
	for p in c.places:
		var marker := {}
		for sc in e.scenes:
			var tk := Encounter.token_in(sc, str(p.get("id", "")))
			if not tk.is_empty():
				marker = {"scene": str(sc.id), "hidden": bool(tk.get("hidden", false))}
		out.places.append({"id": str(p.id), "name": str(p.get("name", "")), "kind": str(p.get("kind", "place")), "target": str(p.get("target", "")),
			"map": str(p.get("map", "")), "cell": str(p.get("cell", "")), "text": str(p.get("text", "")), "notes": str(p.get("notes", "")),
			"image": str(p.get("image", "")), "marker": marker})
	var shown_maps := {}
	for sc in e.scenes:
		shown_maps[str(sc.get("map", ""))] = str(sc.id)
	for m in c.maps:
		out.maps.append({"id": str(m.id), "name": str(m.get("name", "")), "role": str(m.get("role", "battle")), "scene": str(shown_maps.get(str(m.id), ""))})
	for enc in c.encounters:
		var live: Dictionary = enc.get("live", {}) if enc.get("live") is Dictionary else {}
		out.encounters.append({"id": str(enc.id), "name": str(enc.get("name", "")), "map": str(enc.get("map", "")), "notes": str(enc.get("notes", "")),
			"live": live.duplicate(true), "creatures": JsonDoc.deep(enc.get("creatures", []))})
	for aid in e.actors:
		var a: Dictionary = e.actors[aid]
		var kind := str(a.get("kind", ""))
		if kind in ["pc", "companion"] or bool(a.get("persistent", false)) or c.actors.has(aid):
			out.people.append({"id": str(aid), "name": str(a.get("name", "")), "kind": kind, "owner": str(a.get("owner", "")),
				"place": str(a.get("place", "")), "image": str(a.get("image", "")), "public": str(a.get("public", "")), "notes": str(a.get("notes", ""))})
	out.journal = JsonDoc.deep(win.reference.journal())
	out.pictures = CampaignPictures.all(ctx)
	for h in Sharing.handouts(ctx):
		out.shown.append({"id": str(h.get("id", "")), "ref": str(h.get("ref", "")), "title": str(h.get("title", "")),
			"audience": str(h.get("audience", "gm")), "words": Sharing.audience_words(ctx, str(h.get("audience", "gm")))})
	out.contents = JsonDoc.deep(win.reference.layout())
	out.sections = win.reference.SECTIONS.map(func(s: Array) -> Dictionary: return {"key": s[0], "title": win.reference.section_title(str(s[0]))})
	out.player_notes = PlayerNotes.for_viewer(c.player_notes, "", Views.ROLE_GM)
	out.party = JsonDoc.deep(c.doc.get("party", {})) if c.doc.get("party") is Dictionary else {}
	if ctx.host != null and ctx.kernel != null:
		var projection := Views.project(ctx.kernel, ctx.host, "", Views.ROLE_GM)
		var ids := ctx.host.plugins.keys()
		ids.sort()
		for pid in ids:
			var p: PluginHost.Plugin = ctx.host.plugins[pid]
			var kind := "party" if p.views.has("party") else ("gm" if p.views.has("gm") else "")
			if kind != "":
				out.party_views.append({"plugin": str(pid), "schema": p.views[kind], "data": Views.status_data(ctx.kernel, projection, str(pid), "", Views.ROLE_GM)})
		out.cards = EntryCard.cards_of(ctx.host)
		out.rules = rules_settings()
	return out


## Each loaded ruleset's settings, as its manifest declares them, with the
## campaign's values over the defaults: the DM's *Rules settings*.
func rules_settings() -> Array:
	var out := []
	var ctx := win.ctx
	if ctx.host == null:
		return out
	var ids := ctx.host.plugins.keys()
	ids.sort()
	for pid in ids:
		var p: PluginHost.Plugin = ctx.host.plugins[pid]
		var schema: Variant = p.manifest.get("settings", {}).get("schema", {}) if p.manifest.get("settings") is Dictionary else {}
		var props: Variant = schema.get("properties", {}) if schema is Dictionary else {}
		if not (props is Dictionary) or props.is_empty():
			continue
		var items := []
		for key in props:
			var d: Variant = props[key]
			if not (d is Dictionary) or not ["string", "boolean", "integer", "number"].has(str(d.get("type", ""))):
				continue
			var item := {"key": str(key), "title": str(d.get("title", key)), "type": str(d.type), "value": JsonDoc.deep(p.settings.get(key, d.get("default")))}
			if d.has("description"):
				item.description = str(d.description)
			if d.get("enum") is Array:
				item.enum = JsonDoc.deep(d.enum)
				item.labels = JsonDoc.deep(d.enumNames) if d.get("enumNames") is Array and (d.enumNames as Array).size() == (d.enum as Array).size() else JsonDoc.deep(d.enum)
			for bound in ["minimum", "maximum"]:
				if d.has(bound):
					item[bound] = d[bound]
			items.append(item)
		if not items.is_empty():
			out.append({"plugin": str(pid), "name": str(p.manifest.get("name", pid)), "settings": items})
	return out


## A ruleset setting from the DM's screen: checked against the plugin's
## schema, kept in the campaign, the rules loaded again with it (a view
## built from a setting shows the new one), every screen sent afresh.
func set_rule(pid: String, key: String, value: Variant) -> String:
	var ctx := win.ctx
	if ctx.host == null or not ctx.host.plugins.has(pid):
		return "no ruleset '%s' here" % pid
	var item := {}
	for group in rules_settings():
		if str(group.plugin) == pid:
			for it in group.settings:
				if str(it.key) == key:
					item = it
	if item.is_empty():
		return "'%s' has no setting '%s'" % [pid, key]
	var v: Variant = value
	match str(item.type):
		"boolean":
			if not (v is bool):
				return "%s: on or off" % str(item.title)
		"integer", "number":
			if not (v is float or v is int):
				return "%s: a number" % str(item.title)
			if str(item.type) == "integer":
				v = int(v)
			if item.has("minimum") and float(v) < float(item.minimum):
				return "%s: at least %s" % [str(item.title), str(item.minimum)]
			if item.has("maximum") and float(v) > float(item.maximum):
				return "%s: at most %s" % [str(item.title), str(item.maximum)]
		_:
			v = str(v)
	if item.has("enum") and not (item.enum as Array).has(v):
		return "%s: not one of the choices" % str(item.title)
	ctx.campaign.set_plugin_setting(pid, key, v)
	ctx.reload_plugins()
	# the host speaks for the rules loaded now
	if win.host != null:
		win.host.plugins = ctx.host
		win.host.kernel = ctx.kernel
		win.host.refresh_views()
		win.host.refresh_dm()
	ctx.campaign_changed.emit()
	return ""


# -------------------------------------------------------------------- ops --

## What the DM's web screen asked for: {op, …}. "" or why not.
func op(intent: Dictionary) -> String:
	var ctx := win.ctx
	if ctx.campaign == null:
		return "no campaign is open"
	var maps := win.maps
	match str(intent.get("op", "")):
		"show_map":
			return maps.show_map(str(intent.get("map", "")))
		"activate_scene":
			return ctx.commands.activate_scene(str(intent.get("scene", "")))
		"go_place":
			return maps.go_to_place(str(intent.get("place", "")))
		"launch":
			return maps.launch(str(intent.get("encounter", "")))
		"end_fight":
			var fight := maps.live_fight()
			return maps.return_from(fight) if fight != "" else "no fight is running"
		"turns":
			var sid := ctx.encounter().active_scene_id
			match str(intent.get("do", "")):
				"start": return ctx.commands.start_turns(sid)
				# the turn the screen showed: one a player ended meanwhile is not ended twice
				"next": return ctx.commands.next_turn({"by": "gm", "expect": intent.get("from")})
				"previous": return ctx.commands.previous_turn()
				"end": return ctx.commands.stop_turns()
				"mode": return ctx.commands.set_turn_mode(str(intent.get("mode", "free")))
			return "unknown turns step"
		"token":
			var changes := {}
			for k in ["hidden", "pos"]:
				if intent.has(k):
					changes[k] = intent[k]
			if changes.is_empty():
				return "nothing to change"
			var scene := str(intent.get("scene", ctx.encounter().active_scene_id))
			return ctx.commands.run({"t": "token.set", "scene": scene, "id": str(intent.get("id", "")), "changes": changes}, "Token")
		"party_move":
			var cell: Array = intent.get("cell", [])
			if cell.size() != 2:
				return "where?"
			return maps.set_party(Vector2i(int(cell[0]), int(cell[1])))
		"share":
			return Sharing.share(ctx, str(intent.get("ref", "")), str(intent.get("title", "")), str(intent.get("text", "")), str(intent.get("image", "")), str(intent.get("audience", "all")))
		"unshare":
			return Sharing.unshare(ctx, str(intent.get("ref", "")))
		"stop_showing":
			var said := win.reference.stop_showing(str(intent.get("id", "")))
			return "" if said == "Taken back" else said
		"place_set":
			var p := win.reference.place(str(intent.get("place", "")))
			if p.is_empty():
				return "no such place"
			for k in ["text", "notes", "image", "name"]:
				if intent.has(k):
					p[k] = str(intent[k])
			# a fight's place renamed renames the fight (a playtest's DM renamed the
			# lookout "The raid at Mill Crossing" and the fight's bar kept the old name)
			if intent.has("name") and str(p.get("kind", "")) == "encounter":
				var linked := ctx.campaign.encounter_entry(str(p.get("target", "")))
				if not linked.is_empty():
					linked.name = str(intent.name)
			ctx.campaign.touch()
			ctx.campaign_changed.emit()
			return ""
		# fights the DM makes at the table (a playtest's DM could start only the
		# adventure's own): a name and a battle map, creatures from the rules, then
		# Start; its card on the screen is fight:<id>
		"new_fight":
			var map_id := str(intent.get("map", ""))
			if ctx.campaign.map_entry(map_id).is_empty():
				return "choose a map for the fight"
			maps.new_encounter(str(intent.get("name", "")), map_id, _first_level(map_id), str(intent.get("id", "")))
			return ""
		"fight_set":
			var fe := ctx.campaign.encounter_entry(str(intent.get("encounter", "")))
			if fe.is_empty():
				return "no such fight"
			for k in ["name", "notes"]:
				if intent.has(k):
					fe[k] = str(intent[k])
			if intent.has("map"):
				if ctx.campaign.map_entry(str(intent.map)).is_empty():
					return "no such map"
				fe.map = str(intent.map)
				fe.level = _first_level(str(intent.map))
			# its creatures, as the card has them now (a line taken out, a count changed)
			if intent.get("creatures") is Array:
				var lines := []
				for line in intent.creatures:
					if line is Dictionary and str(line.get("entry", "")) != "":
						var kept: Dictionary = JsonDoc.deep(line)
						kept.count = clampi(int(line.get("count", 1)), 1, 20)
						lines.append(kept)
				fe.creatures = lines
			ctx.campaign.touch()
			ctx.campaign_changed.emit()
			return ""
		"fight_add":
			return maps.add_creature(str(intent.get("encounter", "")), {"collection": str(intent.get("collection", "creatures")), "id": str(intent.get("entry", "")),
				"name": str(intent.get("name", intent.get("entry", "")))}, clampi(int(intent.get("count", 1)), 1, 20), str(intent.get("cell", "")), bool(intent.get("hidden", true)))
		"fight_delete":
			var gone := ctx.campaign.encounter_entry(str(intent.get("encounter", "")))
			if gone.is_empty():
				return "no such fight"
			if gone.get("live") is Dictionary and not (gone.live as Dictionary).is_empty():
				return "end the fight first"
			for pl in ctx.campaign.places:
				if str(pl.get("kind", "")) == "encounter" and str(pl.get("target", "")) == str(gone.id):
					return "a place starts this fight (%s): it stays" % str(pl.get("name", ""))
			ctx.campaign.encounters.erase(gone)
			ctx.campaign.touch()
			ctx.campaign_changed.emit()
			return ""
		"actor_set":
			var changes := {}
			for k in ["notes", "public", "place", "image"]:
				if intent.has(k):
					changes[k] = str(intent[k])
			return ctx.commands.run({"t": "actor.set", "id": str(intent.get("actor", "")), "changes": changes}, "Notes")
		"folder":
			return _folder(intent)
		"rules_setting":
			return set_rule(str(intent.get("plugin", "")), str(intent.get("key", "")), intent.get("value"))
		"session":
			if str(intent.get("do", "")) == "start":
				return ctx.start_session()
			var r := ctx.end_session(Recap.markdown(ctx.encounter(), "all") if ctx.campaign_is_live() else "")
			return str(r.get("error", ""))
		"save":
			return ctx.save_campaign()
		# a picture of the DM's own into the book's Pictures, from an upload (a playtest's
		# DM could add none: the Pictures folder offered Rename and New folder only)
		"add_picture":
			var up := str(intent.get("upload", ""))
			if not Uploads.is_ref(up) or ctx.campaign == null:
				return "which picture?"
			var path := Uploads.path_of(Uploads.dir_of(ctx.campaign), up)
			if not FileAccess.file_exists(path):
				return "that picture isn't at the table"
			var added := CampaignPictures.add_file(ctx, path, str(intent.get("name", "")).strip_edges())
			if added.has("why"):
				return str(added.why)
			ctx.campaign_changed.emit()
			return ""
	return "unknown DM operation '%s'" % str(intent.get("op", ""))


## A map's first level (the one a new fight is on).
func _first_level(map_id: String) -> String:
	var m := win.maps.load_map(map_id)
	return str(m.levels[0].get("id", "ground")) if m != null and not m.levels.is_empty() else "ground"


## The DM's own folders in the contents: new, rename, file, move, delete.
func _folder(intent: Dictionary) -> String:
	var ref := win.reference
	match str(intent.get("do", "")):
		"new":
			ref.new_folder(str(intent.get("parent", "")), str(intent.get("title", "New folder")))
		"rename":
			ref.rename(str(intent.get("node", "")), str(intent.get("title", "")))
		"file":
			ref.file(str(intent.get("ref", "")), str(intent.get("folder", "")))
		"move":
			return ref.move_folder(str(intent.get("id", "")), str(intent.get("parent", "")))
		"top":
			ref.move_top(str(intent.get("node", "")), int(intent.get("index", 0)))
		"delete":
			ref.delete_folder(str(intent.get("id", "")))
		_:
			return "unknown folder step"
	win.ctx.campaign_changed.emit()
	return ""
