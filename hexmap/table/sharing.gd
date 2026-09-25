class_name Sharing
extends RefCounted
## Showing the players things — a place's description, a person, a note, a
## picture — to all of them or to some, and taking it back. A thing shown
## is a *handout*: in the session's log now (the phones pop it up), in the
## campaign's journal once the session ends (their Journal keeps it). Who
## sees it is its audience: "all", or "players:<id>,<id>". What it was shown
## from is its `ref` ("place:<id>", "actor:<id>", "note:<id>",
## "picture:<pack:asset>"), so a card can say who has seen it.


## Show something: a handout {title, text, image, ref} to `audience`. "" or why.
static func share(ctx: TableContext, ref: String, title: String, text: String, image: String, audience: String) -> String:
	if ctx.kernel == null:
		return "no table is running"
	if text.strip_edges() == "" and image == "":
		return "There is nothing to show yet: no description and no picture."
	if audience == "" or audience == "gm":
		return "Show it to someone: everyone, or some of the players."
	var entry := {"id": JsonDoc.new_id("h"), "kind": "handout", "title": title, "text": text, "audience": audience, "ref": ref}
	if image != "":
		entry.image = image
	return ctx.kernel.commit([{"t": "log.add", "entry": entry}], "Show the players: " + title, {"by": "gm"}, audience)


## Take back everything shown from `ref`: this session's handouts leave the
## log (and the phones), earlier ones go back to being the DM's. "" or why.
static func unshare(ctx: TableContext, ref: String) -> String:
	var events := []
	for entry in ctx.encounter().log:
		if str(entry.get("kind", "")) == "handout" and str(entry.get("ref", "")) == ref:
			events.append({"t": "log.remove", "id": str(entry.id)})
	var why := ctx.kernel.commit(events, "Stop showing it", {"by": "gm"}) if not events.is_empty() else ""
	if why != "":
		return why
	var changed := false
	if ctx.campaign != null:
		for j in ctx.campaign.journal:
			if str(j.get("kind", "")) == "handout" and str(j.get("ref", "")) == ref and str(j.get("audience", "")) != "gm":
				j.audience = "gm"
				changed = true
	if changed:
		ctx.campaign.touch()
		ctx.campaign_changed.emit()
	return ""


## Every handout: the campaign's journal and this session's, once each.
static func handouts(ctx: TableContext) -> Array:
	var out := []
	var seen := {}
	if ctx.campaign != null:
		for j in ctx.campaign.journal:
			if str(j.get("kind", "")) == "handout":
				out.append(j)
				seen[str(j.get("id", ""))] = true
	if ctx.state != null:
		for entry in ctx.encounter().log:
			if str(entry.get("kind", "")) == "handout" and not seen.has(str(entry.get("id", ""))):
				out.append(entry)
	return out


## Who has been shown `ref`: "" (nobody), "all", or "players:<id>,<id>".
static func shown_to(ctx: TableContext, ref: String) -> String:
	var players := {}
	for h in handouts(ctx):
		if str(h.get("ref", "")) != ref:
			continue
		var aud := str(h.get("audience", "gm"))
		if aud == "all" or aud == "":
			return "all"
		if aud.begins_with("players:"):
			for p in aud.substr(8).split(","):
				players[p] = true
		elif aud.begins_with("owner:"):
			players[aud.substr(6)] = true
	if players.is_empty():
		return ""
	var ids := players.keys()
	ids.sort()
	return "players:" + ",".join(PackedStringArray(ids))


## "everyone", "Ana and Ben", "only you" — an audience in words.
static func audience_words(ctx: TableContext, audience: String) -> String:
	if audience == "all" or audience == "":
		return "everyone"
	if audience == "gm":
		return "only you"
	var ids: PackedStringArray = audience.substr(8).split(",") if audience.begins_with("players:") else PackedStringArray([audience.substr(6)]) if audience.begins_with("owner:") else PackedStringArray()
	var names := PackedStringArray()
	for id in ids:
		names.append(str(ctx.encounter().player(id).get("name", id)))
	if names.size() <= 1:
		return names[0] if names.size() == 1 else "nobody"
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]


## The audience for "everyone", or one player.
static func for_player(pid: String) -> String:
	return "all" if pid == "" else "players:" + pid
