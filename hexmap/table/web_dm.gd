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
		# (where it's fought, when the table leaves it to each fight, and its own settings: TableSettings.set_fight)
		out.encounters.append({"id": str(enc.id), "name": str(enc.get("name", "")), "map": str(enc.get("map", "")), "notes": str(enc.get("notes", "")),
			"live": live.duplicate(true), "creatures": JsonDoc.deep(enc.get("creatures", [])), "light": str(enc.get("light", "")),
			"space": str(enc.get("space", "")), "settings": JsonDoc.deep(enc.get("settings", {})) if enc.get("settings") is Dictionary else {},
			"plays_in": TableSettings.fight_space(c, enc)})
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
		# what the players see of a monster's health (the rulesets' HealthShown: exact, marks,
		# none), for the DM's list of a fight in the theatre of the mind to say beside each
		var shown := ctx.kernel.health_policies()
		out.players_see_health = str(shown[0].get("players", "marks")) if not shown.is_empty() else ""
	# how the table runs: the level, the questions, every setting (TableSettings)
	out.table = win.table_settings.registry()
	return out


## Each loaded ruleset's settings, as its manifest declares them, with the
## campaign's values over the defaults, by ruleset (the DM's screen draws
## Table settings from `state().table`, TableSettings' model, instead).
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
## schema, kept in the campaign (one step of the Table's undo), the rules
## loaded again with it (a view built from a setting shows the new one),
## every screen sent afresh (TableSettings).
func set_rule(pid: String, key: String, value: Variant) -> String:
	return win.table_settings.set_setting(pid, key, value)


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
		# (`space`: on its map or in the theatre of the mind, where the table leaves it to each fight)
		"launch":
			return maps.launch(str(intent.get("encounter", "")), true, str(intent.get("space", "")))
		# a creature into the fight in the theatre of the mind: no token to put down
		"fight_join":
			return maps.join_fight({"collection": str(intent.get("collection", "creatures")), "id": str(intent.get("entry", "")),
				"name": str(intent.get("name", intent.get("entry", "")))}, clampi(int(intent.get("count", 1)), 1, 20), bool(intent.get("hidden", false)))
		"end_fight":
			var fight := maps.live_fight()
			return maps.return_from(fight) if fight != "" else "no fight is running"
		# the scene's light, from the map bar: daylight, dim, dark, or "" for the map's
		"scene_light":
			var light := str(intent.get("light", ""))
			if light != "" and not Vision.LIGHT_LEVELS.has(light):
				return "daylight, dim or dark"
			return ctx.commands.set_scene_light(str(intent.get("scene", ctx.encounter().active_scene_id)), light)
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
		# the party's marker to a place, from its card
		"party_to_place":
			return maps.party_to_place(str(intent.get("place", "")))
		# on a battle map, the party's tokens where the DM tapped ("Move the party here")
		"party_here":
			var here: Array = intent.get("cell", []) if intent.get("cell") is Array else []
			if here.size() != 2:
				return "where?"
			return maps.party_here(str(intent.get("scene", ctx.encounter().active_scene_id)), Vector2i(int(here[0]), int(here[1])))
		# a token for a thing or a person with no stat block, where the DM tapped
		# (a playtest's DM couldn't put the peddler's cart, nor the two on the
		# bell rope, on the map)
		"add_token":
			return _add_thing(intent)
		"remove_token":
			var sid := str(intent.get("scene", ctx.encounter().active_scene_id))
			var tk := ctx.state.token(sid, str(intent.get("id", "")))
			if tk.is_empty():
				return "no such token"
			# (a thing put down by hand, or a spell's: one of a caster's lights)
			if not (tk.get("tags", []) as Array).has("thing") and not Encounter.is_object(tk):
				return "only a token put down by hand, or a thing on the map, comes off the map this way"
			return ctx.commands.run({"t": "token.remove", "scene": sid, "id": str(tk.id)}, "Take off " + str(tk.get("name", "a token")))
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
		# (one in the theatre of the mind needs no map: `map` "")
		"new_fight":
			var map_id := str(intent.get("map", ""))
			if map_id != "" and ctx.campaign.map_entry(map_id).is_empty():
				return "choose a map for the fight"
			if map_id == "" and str(TableSettings.table_of(ctx.campaign).get("space", "maps")) == "maps":
				return "choose a map for the fight: this table's fights are on maps"
			maps.new_encounter(str(intent.get("name", "")), map_id, _first_level(map_id) if map_id != "" else "", str(intent.get("id", "")))
			return ""
		"fight_set":
			var fe := ctx.campaign.encounter_entry(str(intent.get("encounter", "")))
			if fe.is_empty():
				return "no such fight"
			# (checked before anything changes)
			if intent.has("light") and str(intent.light) != "" and not Vision.LIGHT_LEVELS.has(str(intent.light)):
				return "daylight, dim or dark"
			# where it's fought and its own settings: one step of the Table's undo each
			if intent.has("space") or intent.has("settings"):
				var own := {}
				for k in ["space", "settings"]:
					if intent.has(k):
						own[k] = intent[k]
				var why_own := win.table_settings.set_fight(str(fe.id), own)
				if why_own != "":
					return why_own
			for k in ["name", "notes"]:
				if intent.has(k):
					fe[k] = str(intent[k])
			if intent.has("map"):
				# (none: a fight in the theatre of the mind, where the table's fights may be)
				if str(intent.map) == "" and str(TableSettings.table_of(ctx.campaign).get("space", "maps")) != "maps":
					fe.map = ""
					fe.level = ""
				elif ctx.campaign.map_entry(str(intent.map)).is_empty():
					return "no such map"
				else:
					fe.map = str(intent.map)
					fe.level = _first_level(str(intent.map))
			# its light, given to the scene when it starts ("" for the map's own)
			if intent.has("light"):
				if str(intent.light) == "":
					fe.erase("light")
				else:
					fe.light = str(intent.light)
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
		# a creature's name told to the players, or kept from them again: "Reveal
		# its name" on its token or stat block, "Reveal all" in the fight (its
		# actor's audience.name: Knowledge), one step of the Table's undo
		"reveal_names":
			return reveal_names(Array(intent.get("actors", [])) if intent.get("actors") is Array else [str(intent.get("actor", ""))], intent.get("known", true) != false)
		"folder":
			return _folder(intent)
		"rules_setting":
			return set_rule(str(intent.get("plugin", "")), str(intent.get("key", "")), intent.get("value"))
		# Table settings: a level (every setting it names, as one step), a section
		# back to the level, the table's own (where fights happen, house rules),
		# the walkthrough's answers, and the newest change taken back
		"table_level":
			return win.table_settings.set_level(str(intent.get("level", "")))
		"table_reset":
			return win.table_settings.reset_question(str(intent.get("question", "")))
		"table_set":
			var changes := {}
			for k in ["space", "house_rules"]:
				if intent.has(k):
					changes[k] = intent[k]
			return win.table_settings.set_table(changes)
		"table_setup":
			var answers := {}
			for k in ["level", "space", "house_rules", "settings"]:
				if intent.has(k):
					answers[k] = intent[k]
			var done := win.table_settings.finish_setup(answers)
			if done == "":
				win.walkthrough_done(true)
			return done
		"table_undo":
			return win.table_settings.undo_last()
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


## The names of creatures no player owns (`ids`, actors) told to the players
## (`known`), or kept from them again: one step. "" or why not.
func reveal_names(ids: Array, known := true) -> String:
	var e := win.ctx.encounter()
	var events := []
	var names := []
	for id in ids:
		var a := e.actor(str(id))
		if a.is_empty() or not Knowledge.unowned_actor(a):
			continue
		var aud: Variant = a.get("audience")
		var was := aud is Dictionary and str((aud as Dictionary).get("name", "")) == "all"
		if was == known:
			continue
		events.append({"t": "actor.set", "id": str(id), "changes": {"audience/name": "all" if known else null}})
		names.append(str(a.get("name", id)))
	if events.is_empty():
		return "" if not ids.is_empty() else "whose name?"
	var label := ("Reveal " if known else "Keep hidden: ") + (", ".join(PackedStringArray(names)) if names.size() <= 3 else "%d names" % names.size())
	return win.ctx.commands.run_all(events, label)


## A token for a thing or a person with no stat block (a cart, a villager):
## its name, its label (the initials it is given, or its name's), its
## colour, where it goes, whether the players see it. Tagged `thing`: no
## pick takes it, and the DM's screen can take it off again. "" or why.
func _add_thing(intent: Dictionary) -> String:
	var ctx := win.ctx
	var sid := str(intent.get("scene", ctx.encounter().active_scene_id))
	if ctx.encounter().scene(sid).is_empty():
		return "no map on the table to put it on"
	var named := str(intent.get("name", "")).strip_edges()
	if named == "":
		return "give it a name"
	var pos: Array = intent.get("pos", []) if intent.get("pos") is Array else []
	if pos.size() != 2:
		return "where?"
	var label := str(intent.get("label", "")).strip_edges().to_upper().left(3)
	if label == "":
		var words := named.split(" ", false)
		label = (words[0].left(1) + (words[1].left(1) if words.size() > 1 else words[0].substr(1, 1))).to_upper()
	var color := str(intent.get("color", ""))
	if not color.begins_with("#") or not color.is_valid_html_color():
		color = "#8a7a5a"
	var tk := Encounter.new_token(named, Vector2(float(pos[0]), float(pos[1])), {"label": label, "color": color, "hidden": bool(intent.get("hidden", false)), "tags": ["thing"], "vision": null})
	return ctx.commands.add_token(sid, tk)


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
