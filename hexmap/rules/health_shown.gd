class_name HealthShown
extends RefCounted
## What each screen is sent of a creature's health, as its ruleset declares
## it (`hm.ui.health`): the tags its tokens carry for it (bloodied, down,
## dead), the pool its hit points are kept in, the effects that say it is
## dying or dead, and what the players see of a creature no player owns:
##
##   "exact"  its marks and its hit points ([current, max] on its token, for
##            every screen: the DM sees what the players see)
##   "marks"  its marks (the default, as before)
##   "none"   nothing: no mark on its token, no pool, no dying or dead effect
##
## The Table filters before anything is sent (WebScene's snapshots, the
## document a Godot client holds and the token events after it, the rules'
## view): a player's device never holds what the DM keeps. The DM sees
## everything; a creature of the party (a player's, or a player's
## character's) is the party's own to see.
##
## A declaration: {plugin, tags: [..], resource: "", effects: [..],
## players: "exact" | "marks" | "none"}.

const MODES := ["exact", "marks", "none"]


## A ruleset's declaration, checked and made plain; a String when it isn't one.
static func make(plugin: String, spec: Variant) -> Variant:
	if not (spec is Dictionary):
		return "hm.ui.health takes a table: {tags, resource, effects, players}"
	var players := str(spec.get("players", "marks"))
	if not MODES.has(players):
		return "hm.ui.health: players is exact, marks or none, not '%s'" % players
	var out := {"plugin": plugin, "players": players, "resource": str(spec.get("resource", "")), "tags": [], "effects": []}
	for key in ["tags", "effects"]:
		var v: Variant = spec.get(key, [])
		if v is Dictionary:
			v = (v as Dictionary).values()
		if not (v is Array):
			return "hm.ui.health: %s is a list" % key
		for x in v:
			out[key].append(str(x))
	return out


## Whether any declaration keeps something from the players.
static func hides(policies: Array) -> bool:
	return policies.any(func(p: Dictionary) -> bool: return str(p.get("players", "marks")) != "exact")


## Whether any declaration shows hit points.
static func exact(policies: Array) -> bool:
	return policies.any(func(p: Dictionary) -> bool: return str(p.get("players", "marks")) == "exact")


## Whether a token stands for a creature no player owns: it has an actor, and
## neither it nor its actor has an owner, and the actor isn't a player's
## character. (A thing on the map with no actor carries no health.)
static func unowned(tk: Dictionary, actors: Dictionary) -> bool:
	if tk.get("owner", null) != null and str(tk.owner) != "":
		return false
	var aid := str(tk.get("actor", ""))
	if aid == "":
		return false
	var a: Dictionary = actors.get(aid, {})
	return str(a.get("owner", "")) == "" and str(a.get("kind", "")) != "pc"


## A token's tags as a player is sent them: the ones a declaration keeps from
## the players ("none") taken out.
static func player_tags(tags: Array, policies: Array) -> Array:
	var gone := {}
	for p in policies:
		if str(p.get("players", "marks")) == "none":
			for tg in p.get("tags", []):
				gone[str(tg)] = true
	if gone.is_empty():
		return tags
	return tags.filter(func(tg: Variant) -> bool: return not gone.has(str(tg)))


## The hit points a creature's token shows, [current, max], where a declaration
## shows them exactly ("exact"); [] where none does or it has no such pool.
## `resources` is the encounter's ("actor:<id>" -> plugin -> name -> record).
static func shown_hp(resources: Dictionary, actor_id: String, policies: Array) -> Array:
	if actor_id == "":
		return []
	var mine: Dictionary = resources.get("actor:" + actor_id, {})
	for p in policies:
		if str(p.get("players", "marks")) != "exact" or str(p.get("resource", "")) == "":
			continue
		var rec: Variant = mine.get(str(p.plugin), {}).get(str(p.resource))
		if rec is Dictionary and rec.has("current") and rec.has("max"):
			return [float(rec.current), float(rec.max)]
	return []


## A token as a player is sent it, from what the DM's screen would get: its
## tags filtered (a creature no player owns). `actors` the encounter's.
static func player_token(tk: Dictionary, actors: Dictionary, policies: Array) -> Dictionary:
	if not hides(policies) or not unowned(tk, actors) or not (tk.get("tags") is Array):
		return tk
	var out := tk.duplicate()
	out.tags = player_tags(tk.tags, policies)
	return out


## A token event as a player's Godot client is sent it: a token added or
## changed for a creature no player owns, its health tags taken out. `token`
## is the token as it is now (for a change: who it is).
static func player_event(ev: Dictionary, token: Dictionary, actors: Dictionary, policies: Array) -> Dictionary:
	if not hides(policies):
		return ev
	match str(ev.get("t", "")):
		"token.add":
			if ev.get("token") is Dictionary and unowned(ev.token, actors):
				var out := ev.duplicate()
				out.token = player_token(ev.token, actors, policies)
				return out
		"token.set":
			var ch: Variant = ev.get("changes")
			if ch is Dictionary and (ch as Dictionary).get("tags") is Array and unowned(token, actors):
				var out := ev.duplicate()
				out.changes = (ch as Dictionary).duplicate()
				out.changes.tags = player_tags(ch.tags, policies)
				return out
	return ev


## An actor's projection as a player is sent it (Views.project), for a
## creature no player owns: its hit point pool taken out unless shown exactly,
## and with nothing shown its dying and dead effects too.
static func filter_actor(pa: Dictionary, policies: Array) -> void:
	for p in policies:
		var mode := str(p.get("players", "marks"))
		if mode == "exact":
			continue
		var res: Variant = pa.get("resources", {}).get(str(p.plugin))
		if res is Dictionary and str(p.get("resource", "")) != "":
			(res as Dictionary).erase(str(p.resource))
		if mode == "none" and pa.get("effects") is Array:
			var keys: Array = p.get("effects", [])
			pa.effects = (pa.effects as Array).filter(func(fx: Dictionary) -> bool:
				return not (str(fx.get("plugin", "")) == str(p.plugin) and keys.has(str(fx.get("key", "")))))
