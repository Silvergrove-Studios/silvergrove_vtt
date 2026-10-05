class_name Knowledge
extends RefCounted
## What the players know of the creatures no player owns, as each ruleset
## declares it (`hm.ui.knowledge`, and `hm.ui.health` for the health part),
## and the one filter that keeps the rest from their devices. The Table
## filters before anything is sent — a web screen's snapshot (WebScene), the
## document a Godot client holds and the token events after it (Protocol,
## HostSession), the rules' view (Views), and every message on the wire
## (HostSession._send) — so a player's device never holds what the DM keeps.
## The DM sees everything; a creature of the party (a player's, or a player's
## character's) is the party's own to know.
##
## Three things, each a ruleset's to say (its DM's setting, usually):
##
## - **health** `{tags, resource, effects, players}`: the marks its tokens
##   carry for it (bloodied, down, dead), the pool its hit points are kept
##   in, the effects that say it's dying or dead, and what players see:
##     "exact"  its marks and its hit points ([current, max] on its token,
##              for every screen: the DM sees what the players see)
##     "marks"  its marks (the default, as before)
##     "none"   nothing: no mark on its token, no pool, no dying or dead effect
## - **names** "shown" | "hidden": hidden, a creature is "a creature" to the
##   players — its token's name, its label "?" (or a number, several on the
##   scene: the DM's hidden ones aren't counted, so a number never tells of a
##   creature the players haven't seen), its name in the rules' view, and its
##   name wherever a ruleset's words name it — until the DM reveals it: its
##   actor's `audience.name` is "all" (the DM's "Reveal its name"). A creature
##   a player's spell made is known from the start.
## - **conditions** "shown" | "hidden": hidden, the effects on a creature no
##   player owns are left out of the players' view of it (but those its
##   health declares, which follow its health), and so are its tokens' tags
##   that are its effects' keys.
## - **rolls** "shown" | "hidden": hidden, the ruleset keeps a creature's rolls
##   to the DM (their audience), and the Table leaves out what the turn order
##   says of them: its tokens' labels there (their initiative) — the order
##   itself the players still see.
##
## A ruleset's words name a creature through a mark (`hm.known.name`): the
## words the DM reads, the actor they are about, and what a screen that
## doesn't know them reads instead —
##
##   U+FFF9 words U+FFFA "name <actor id> <unknown words>" U+FFFB
##
## (Unicode's interlinear annotation characters: the annotated text, then
## its annotation.) `conditions` marks words about a creature's conditions
## the same way ("cond <actor id> <unknown words>", usually nothing). The
## Table puts each mark right for each screen as it is sent: a reveal reaches
## every line said of it before, at once. A ruleset that never marks a name
## leaves it as it wrote it.
##
## A declaration: {plugin, players, resource, tags, effects, names,
## conditions, rolls} (the health keys flat, as `hm.ui.health` has always
## given them).

const MODES := ["exact", "marks", "none"]
const SHOWN := ["shown", "hidden"]
## The mark's three characters: anchor, separator, terminator.
const ANCHOR := "\uFFF9"
const SEP := "\uFFFA"
const END := "\uFFFB"
## What a creature is called where its name is kept from a screen.
const UNKNOWN := "a creature"
const UNKNOWN_START := "A creature"
## What a creature's token is labelled there, alone on the scene.
const UNKNOWN_LABEL := "?"
static var _MARK := RegEx.create_from_string("\uFFF9([^\uFFF9\uFFFA\uFFFB]*)\uFFFA([^\uFFF9\uFFFA\uFFFB]*)\uFFFB")


# ------------------------------------------------------------ declaring --

## A ruleset's declaration (`hm.ui.knowledge`'s {health, names, conditions, rolls};
## `hm.ui.health` gives {health} alone), made plain over what it declared
## before (`base`); a String when it isn't one.
static func make(plugin: String, spec: Variant, base: Dictionary = {}) -> Variant:
	if spec is Array and (spec as Array).is_empty():
		spec = {}
	if not (spec is Dictionary):
		return "hm.ui.knowledge takes a table: {health, names, conditions, rolls}"
	var out := {"plugin": plugin, "players": "marks", "resource": "", "tags": [], "effects": [], "names": "shown", "conditions": "shown", "rolls": "shown"}
	for k in base:
		out[k] = JsonDoc.deep(base[k])
	out.plugin = plugin
	var health: Variant = spec.get("health")
	if health is Array and (health as Array).is_empty():
		health = {}
	if health != null:
		if not (health is Dictionary):
			return "hm.ui.health takes a table: {tags, resource, effects, players}"
		var players := str(health.get("players", "marks"))
		if not MODES.has(players):
			return "hm.ui.health: players is exact, marks or none, not '%s'" % players
		out.players = players
		out.resource = str(health.get("resource", ""))
		for key in ["tags", "effects"]:
			var v: Variant = health.get(key, [])
			if v is Dictionary:
				v = (v as Dictionary).values()
			if not (v is Array):
				return "hm.ui.health: %s is a list" % key
			out[key] = (v as Array).map(func(x: Variant) -> String: return str(x))
	for key in ["names", "conditions", "rolls"]:
		if spec.has(key):
			var v := str(spec[key])
			if not SHOWN.has(v):
				return "hm.ui.knowledge: %s is shown or hidden, not '%s'" % [key, v]
			out[key] = v
	return out


## Whether any declaration keeps something from the players.
static func hides(policies: Array) -> bool:
	return policies.any(func(p: Dictionary) -> bool:
		return str(p.get("players", "marks")) != "exact" or str(p.get("names", "shown")) == "hidden" or str(p.get("conditions", "shown")) == "hidden")


## Whether any declaration shows hit points.
static func exact(policies: Array) -> bool:
	return policies.any(func(p: Dictionary) -> bool: return str(p.get("players", "marks")) == "exact")


## Whether any declaration keeps a creature's name from the players.
static func names_hidden(policies: Array) -> bool:
	return policies.any(func(p: Dictionary) -> bool: return str(p.get("names", "shown")) == "hidden")


## Whether any declaration keeps a creature's conditions from the players.
static func conditions_hidden(policies: Array) -> bool:
	return policies.any(func(p: Dictionary) -> bool: return str(p.get("conditions", "shown")) == "hidden")


## Whether any declaration keeps a creature's rolls from the players.
static func rolls_hidden(policies: Array) -> bool:
	return policies.any(func(p: Dictionary) -> bool: return str(p.get("rolls", "shown")) == "hidden")


# ----------------------------------------------------------------- who --

## Whether a token stands for a creature no player owns: it has an actor, and
## neither it nor its actor has an owner, and the actor isn't a player's
## character. (A thing on the map with no actor carries no health.)
static func unowned(tk: Dictionary, actors: Dictionary) -> bool:
	if tk.get("owner", null) != null and str(tk.owner) != "":
		return false
	var aid := str(tk.get("actor", "")) if tk.get("actor") != null else ""
	if aid == "":
		return false
	return unowned_actor(actors.get(aid, {}))


## Whether an actor is a creature no player owns (an actor gone counts as one).
static func unowned_actor(a: Dictionary) -> bool:
	return str(a.get("owner", "")) == "" and str(a.get("kind", "")) != "pc"


## Whether the players know an actor's name: names aren't kept, it's the
## party's, or the DM has revealed it (`audience.name` "all").
static func name_known(a: Dictionary, policies: Array) -> bool:
	if not names_hidden(policies):
		return true
	if a.is_empty():
		return false
	if not unowned_actor(a):
		return true
	var aud: Variant = a.get("audience")
	return aud is Dictionary and str((aud as Dictionary).get("name", "")) == "all"


## Whether a token's name is kept from the players: a creature no player owns
## (not a thing on the map, but for a likeness of one: a copy of the creature
## that looks like it) whose name they don't know.
static func nameless(tk: Dictionary, actors: Dictionary, policies: Array) -> bool:
	if not names_hidden(policies) or not unowned(tk, actors):
		return false
	if Encounter.is_object(tk) and not (tk.get("tags") is Array and (tk.tags as Array).has("likeness")):
		return false
	return not name_known(actors.get(str(tk.actor), {}), policies)


## Whether the players know the conditions on an actor.
static func conditions_known(a: Dictionary, policies: Array) -> bool:
	return not conditions_hidden(policies) or (not a.is_empty() and not unowned_actor(a))


## What a screen knows, for its marks: (aspect, actor id) -> bool. The DM's
## (`gm`) knows everything.
static func knower(actors: Dictionary, policies: Array, gm: bool) -> Callable:
	if gm:
		return func(_aspect: String, _aid: String) -> bool: return true
	var hidden := names_hidden(policies) or conditions_hidden(policies)
	return func(aspect: String, aid: String) -> bool:
		# words only the DM reads (hm.known.dm): never a player's
		if aspect == "dm":
			return false
		if not hidden:
			return true
		var a: Dictionary = actors.get(aid, {})
		if aspect == "cond":
			return conditions_known(a, policies)
		return name_known(a, policies)


# -------------------------------------------------------------- tokens --

## The labels the players see on the creatures whose names they don't know,
## {token id: label}: "?" for one, numbers in the scene's order for several
## — those the DM hides aren't counted (they keep "?"), so a number never
## tells of a creature the players haven't seen. {} with names shown.
static func player_labels(tokens: Array, actors: Dictionary, policies: Array) -> Dictionary:
	var out := {}
	if not names_hidden(policies):
		return out
	var shown := []
	for tk in tokens:
		if tk is Dictionary and nameless(tk, actors, policies):
			out[str(tk.id)] = UNKNOWN_LABEL
			if not bool(tk.get("hidden", false)):
				shown.append(str(tk.id))
	if shown.size() > 1:
		for i in shown.size():
			out[shown[i]] = str(i + 1)
	return out


## A token's tags as a player is sent them: the health marks a declaration
## keeps from the players ("none") taken out, and — conditions hidden — the
## tags that are keys of the creature's effects (`fx_keys`).
static func player_tags(tags: Array, policies: Array, fx_keys: Dictionary = {}) -> Array:
	var gone := fx_keys.duplicate()
	for p in policies:
		if str(p.get("players", "marks")) == "none":
			for tg in p.get("tags", []):
				gone[str(tg)] = true
	if gone.is_empty():
		return tags
	return tags.filter(func(tg: Variant) -> bool: return not gone.has(str(tg)))


## The keys of the effects on a creature (on its actor or on this token) that
## its conditions keep from the players: every one but its health's.
## `effects` the encounter's (id -> record).
static func condition_keys(effects: Dictionary, tk: Dictionary, policies: Array) -> Dictionary:
	var out := {}
	var health := {}
	for p in policies:
		for k in p.get("effects", []):
			health[str(k)] = true
	var refs := ["token:" + str(tk.get("id", "")), "actor:" + str(tk.get("actor", ""))]
	for id in effects:
		var fx: Variant = effects[id]
		if fx is Dictionary and refs.has(str(fx.get("on", ""))) and not health.has(str(fx.get("key", ""))):
			out[str(fx.get("key", ""))] = true
	return out


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


## A token as a player is sent it, from what the DM's screen would get: for a
## creature no player owns, its tags filtered (its health, its conditions)
## and — its name unknown — "a creature", labelled `label` (player_labels).
## `doc` the encounter's document (actors, effects).
static func player_token(tk: Dictionary, doc: Dictionary, policies: Array, label := "") -> Dictionary:
	var actors: Dictionary = doc.get("actors", {}) if doc.get("actors") is Dictionary else {}
	if not hides(policies) or not unowned(tk, actors):
		return tk
	var out := tk.duplicate()
	if tk.get("tags") is Array:
		var fx: Dictionary = doc.get("effects", {}) if doc.get("effects") is Dictionary else {}
		out.tags = player_tags(tk.tags, policies, condition_keys(fx, tk, policies) if conditions_hidden(policies) and not conditions_known(actors.get(str(tk.actor), {}), policies) else {})
	if nameless(tk, actors, policies):
		unname(out, label)
	return out


## A token's name kept from its screen: "a creature", and the label the
## players see it by.
static func unname(out: Dictionary, label: String) -> void:
	out.name = UNKNOWN
	out.label = label if label != "" else UNKNOWN_LABEL
	out.unknown = true


## A token event as a player's Godot client is sent it: a token added or
## changed for a creature no player owns, its health and condition tags taken
## out and its name kept (`label`: the one the players see it by). `token` is
## the token as it is now (for a change: who it is).
static func player_event(ev: Dictionary, token: Dictionary, doc: Dictionary, policies: Array, label := "") -> Dictionary:
	if not hides(policies):
		return ev
	var actors: Dictionary = doc.get("actors", {}) if doc.get("actors") is Dictionary else {}
	match str(ev.get("t", "")):
		"token.add":
			if ev.get("token") is Dictionary and unowned(ev.token, actors):
				var out := ev.duplicate()
				out.token = player_token(ev.token, doc, policies, label)
				return out
		"token.set":
			var ch: Variant = ev.get("changes")
			if ch is Dictionary and unowned(token, actors):
				var out := ev.duplicate()
				out.changes = (ch as Dictionary).duplicate()
				if (ch as Dictionary).get("tags") is Array:
					var probe := token.duplicate()
					probe.tags = ch.tags
					out.changes.tags = player_token(probe, doc, policies).tags
				if nameless(token, actors, policies):
					if out.changes.has("name"):
						out.changes.name = UNKNOWN
					if out.changes.has("label"):
						out.changes.label = label if label != "" else UNKNOWN_LABEL
				return out
	return ev


# ---------------------------------------------------------------- turns --

## The tokens, by id, of the creatures no player owns, in every scene of `doc`.
static func _unowned_tokens(doc: Dictionary) -> Dictionary:
	var out := {}
	var actors: Dictionary = doc.get("actors", {}) if doc.get("actors") is Dictionary else {}
	for sc in doc.get("scenes", []):
		if not (sc is Dictionary) or not (sc.get("tokens") is Array):
			continue
		for tk in sc.tokens:
			if tk is Dictionary and unowned(tk, actors):
				out[str(tk.get("id", ""))] = true
	return out


## The tokens of every scene of `doc` no player's screen leaves out for
## everyone: not hidden by the DM, not a thing only its owner sees (what
## player_turns counts as seen when it isn't told what a screen sees).
static func _shown_tokens(doc: Dictionary) -> Dictionary:
	var out := {}
	for sc in doc.get("scenes", []):
		if not (sc is Dictionary) or not (sc.get("tokens") is Array):
			continue
		for tk in sc.tokens:
			if tk is Dictionary and not bool(tk.get("hidden", false)) and str(tk.get("audience", "all")) != "owner":
				out[str(tk.get("id", ""))] = true
	return out


## The keys of a turn order's `data` a player's screen is sent: the rest is a
## ruleset's own, for its own reading on the Table.
const TURN_DATA_SENT := ["labels", "groups", "notes", "skip", "rolling"]


## The turn order as a player is sent it: only what their screen shows of
## it. `seen` is the tokens their screen is sent ({id: true}: WebScene.seen;
## null for every token the DM hasn't hidden): a creature not among them is
## out of every part of it — the order, its groups, the turn's notes and
## skips, the counters, the labels, the focus and who held it, who may move —
## so nothing says one is there; the turn of one they don't see is nobody's
## to them (`turn` -1: their screens say it's the DM's), and the turn that
## ended (`last`) is told by its place in their order, without where tokens
## stood or what the log held then. A group whose members they know no names
## of is "Creatures" (the ruleset's name for it could be the stat block's);
## where they don't see a creature's rolls, its label (its initiative) is out
## too — of a group of them, the group's. The data a ruleset keeps there for
## itself is not sent (TURN_DATA_SENT). A copy.
static func player_turns(turns: Dictionary, doc: Dictionary, policies: Array, seen: Variant = null) -> Dictionary:
	var out: Dictionary = JsonDoc.deep(turns)
	var ids: Dictionary = seen if seen is Dictionary else _shown_tokens(doc)
	var actors: Dictionary = doc.get("actors", {}) if doc.get("actors") is Dictionary else {}
	var theirs := _unowned_tokens(doc)
	var tokens := {}
	for sc in doc.get("scenes", []):
		if sc is Dictionary and sc.get("tokens") is Array:
			for tk in sc.tokens:
				if tk is Dictionary:
					tokens[str(tk.get("id", ""))] = tk
	var data: Dictionary = out.data if out.get("data") is Dictionary else {}
	for k in data.keys():
		if not TURN_DATA_SENT.has(str(k)):
			data.erase(k)
	# its groups: the members they see, none left none at all
	var groups: Dictionary = data.groups if data.get("groups") is Dictionary else {}
	for gid in groups.keys():
		var g: Variant = groups[gid]
		var members: Array = (g.get("tokens", []) as Array).filter(func(id: Variant) -> bool: return ids.has(str(id))) if g is Dictionary and g.get("tokens") is Array else []
		if members.is_empty():
			groups.erase(gid)
			continue
		g.tokens = members
		if names_hidden(policies) and members.all(func(id: Variant) -> bool: return nameless(tokens.get(str(id), {}), actors, policies)):
			g.label = "Creatures"
	var shown := func(entry: String) -> bool:
		return groups.has(entry.substr(6)) if entry.begins_with("group:") else ids.has(entry)
	# the order, and whose turn it is in it
	var order: Array = out.get("order", []) if out.get("order") is Array else []
	var kept := []
	var place := {}
	for i in order.size():
		if shown.call(str(order[i])):
			place[i] = kept.size()
			kept.append(str(order[i]))
	if not order.is_empty():
		out.turn = int(place.get(int(out.get("turn", 0)), -1))
	out.order = kept
	if out.get("last") is Dictionary:
		var last: Dictionary = out.last
		last.erase("log")
		last.erase("pos")
		last.turn = int(place.get(int(last.get("turn", -1)), -1))
		if not shown.call(str(last.get("entry", ""))):
			last.entry = ""
	# the labels, the turn's notes, the skips: of what they see; where the rolls
	# are the DM's, no creature's initiative (nor a group of them's)
	var hide_rolls := rolls_hidden(policies)
	var labels: Dictionary = data.labels if data.get("labels") is Dictionary else {}
	for k in labels.keys():
		var key := str(k)
		if not shown.call(key):
			labels.erase(k)
		elif hide_rolls and (theirs.has(key) or (key.begins_with("group:") and (groups[key.substr(6)].tokens as Array).all(func(id: Variant) -> bool: return theirs.has(str(id))))):
			labels.erase(k)
	for part in ["notes", "skip"]:
		if data.get(part) is Dictionary:
			for k in (data[part] as Dictionary).keys():
				if not shown.call(str(k)):
					(data[part] as Dictionary).erase(k)
	# the counters, the focus and who held it, who may move
	var ref_shown := func(ref: String) -> bool:
		if ref.begins_with("token:"):
			return ids.has(ref.substr(6))
		if ref.begins_with("actor:"):
			var aid := ref.substr(6)
			if not unowned_actor(actors.get(aid, {})):
				return true
			for id in ids:
				if str(tokens.get(id, {}).get("actor", "")) == aid:
					return true
			return false
		return true
	if out.get("counters") is Dictionary:
		for ref in (out.counters as Dictionary).keys():
			if not ref_shown.call(str(ref)):
				(out.counters as Dictionary).erase(ref)
	if out.get("focus") is String and not ref_shown.call(str(out.focus)):
		out.focus = "gm"
	if out.get("history") is Array:
		out.history = (out.history as Array).filter(func(r: Variant) -> bool: return ref_shown.call(str(r)))
	if out.get("active") is Array:
		out.active = (out.active as Array).filter(func(id: Variant) -> bool: return ids.has(str(id)))
	return out


## Where a player's screen sent `turn` (its place in the order as they were
## sent it: player_turns), the place in the Table's own; -1 where it is in no
## order of theirs.
static func table_turn(turns: Dictionary, doc: Dictionary, policies: Array, seen: Variant, turn: int) -> int:
	var theirs: Array = player_turns(turns, doc, policies, seen).get("order", [])
	if turn < 0 or turn >= theirs.size():
		return -1
	return (turns.get("order", []) as Array).find(theirs[turn])


# --------------------------------------------------------------- actors --

## An actor's projection as a player is sent it (Views.project), for a
## creature no player owns: its hit point pool taken out unless shown exactly,
## and with nothing shown its dying and dead effects too; its other effects
## out where its conditions are kept; its name, where that is.
static func filter_actor(pa: Dictionary, a: Dictionary, policies: Array) -> void:
	var health_keys := {}
	for p in policies:
		for k in p.get("effects", []):
			health_keys[str(p.plugin) + "/" + str(k)] = true
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
	if not conditions_known(a, policies) and pa.get("effects") is Array:
		pa.effects = (pa.effects as Array).filter(func(fx: Dictionary) -> bool: return health_keys.has(str(fx.get("plugin", "")) + "/" + str(fx.get("key", ""))))
	if not name_known(a, policies):
		pa.name = UNKNOWN
		pa.unknown = true
		for tk in pa.get("tokens", []):
			if tk is Dictionary:
				tk.name = UNKNOWN
		if pa.get("token") is Dictionary:
			(pa.token as Dictionary).erase("name")
			(pa.token as Dictionary).erase("label")


# ---------------------------------------------------------------- words --

## Words about an actor, marked for the Table to put right for each screen:
## `aspect` "name" (its name) or "cond" (its conditions); `unknown` what a
## screen that doesn't know reads instead.
static func mark(aspect: String, actor_id: String, words: String, unknown := "") -> String:
	return ANCHOR + plain(words) + SEP + aspect + " " + actor_id + " " + plain(unknown) + END


## Text with its marks read as the DM reads them.
static func plain(text: String) -> String:
	return render(text, func(_aspect: String, _aid: String) -> bool: return true, true)


## Text cut to `n` characters as the DM reads it, its marks kept whole (one
## that would be cut goes, with what follows): a screen never reads half a name.
static func cut(text: String, n: int) -> String:
	if plain(text).length() <= n:
		return text
	var out := ""
	var shown := 0
	var at := 0
	for m in _MARK.search_all(text):
		var before := text.substr(at, m.get_start() - at)
		if shown + before.length() >= n:
			return out + before.left(n - shown)
		out += before
		shown += before.length()
		if shown + m.get_string(1).length() > n:
			return out
		out += m.get_string(0)
		shown += m.get_string(1).length()
		at = m.get_end()
	return out + text.substr(at).left(n - shown)


## Text as a screen that knows what `knows` says ((aspect, actor id) -> bool)
## reads it: each mark its words where it knows them, else what it reads
## instead — capitalised where it starts a sentence ("A creature hits Wren").
## A mark cut short is the DM's words to the DM (`gm`) and nothing to anyone
## else: a screen never reads half a name.
static func render(text: String, knows: Callable, gm := false) -> String:
	if not (text.contains(ANCHOR) or text.contains(SEP) or text.contains(END)):
		return text
	var out := ""
	var at := 0
	for m in _MARK.search_all(text):
		out += text.substr(at, m.get_start() - at)
		var said := _instead(m, knows, _starts_sentence(out))
		at = m.get_end()
		if said == "" and m.get_string(1) != "":
			# words read as nothing take their list's comma with them ("fails the save,
			# Frightened" is "fails the save" to a screen that doesn't see it)
			var cut := _unlist(out, text.substr(at, 2), text.length() - at <= 0)
			out = cut[0]
			at += int(cut[1])
		out += said
	out += text.substr(at)
	if out.contains(ANCHOR) or out.contains(SEP) or out.contains(END):
		out = _strays(out, gm)
	return out


## Words read as nothing between `before` and `after` (its next two
## characters): the separator they leave goes — ", " or "; " before them, else
## one after them; ": " before them where the clause ends with them. [before,
## how many characters of what follows to pass by].
static func _unlist(before: String, after: String, at_end: bool) -> Array:
	for sep in [", ", "; "]:
		if before.ends_with(sep):
			return [before.left(before.length() - sep.length()), 0]
	if after == ", " or after == "; ":
		return [before, 2]
	if before.ends_with(": ") and (at_end or after.begins_with(".") or after.begins_with(";") or after.begins_with(")") or after.begins_with("\"")):
		return [before.left(before.length() - 2), 0]
	return [before, 0]


## One mark as a screen reads it: its words, or what it reads instead
## (capitalised at a sentence's start).
static func _instead(m: RegExMatch, knows: Callable, start: bool) -> String:
	var note := m.get_string(2).split(" ", true, 2)
	var aid := note[1] if note.size() > 1 else ""
	if bool(knows.call(note[0], aid)):
		return m.get_string(1)
	var words := note[2] if note.size() > 2 else ""
	return words.left(1).to_upper() + words.substr(1) if start and words != "" else words


## Whether what comes after `before` starts a sentence: nothing before it, or
## a full stop (!, ?) and a space, or a new line.
static func _starts_sentence(before: String) -> bool:
	if before == "" or before.ends_with("\n"):
		return true
	var t := before.rstrip(" ")
	return t.length() < before.length() and (t.ends_with(".") or t.ends_with("!") or t.ends_with("?"))


## What is left of marks cut short: the DM's, their words; anyone else's,
## nothing from an anchor to its separator or end.
static func _strays(text: String, gm: bool) -> String:
	if gm:
		var i := text.find(SEP)
		while i >= 0:
			var j := text.find(END, i)
			text = text.substr(0, i) + (text.substr(j + 1) if j >= 0 else "")
			i = text.find(SEP)
		return text.replace(ANCHOR, "").replace(END, "")
	var out := ""
	var skipping := false
	for ch in text:
		if ch == ANCHOR or ch == SEP:
			skipping = true
		elif ch == END:
			skipping = false
		elif not skipping:
			out += ch
	return out


## A value (a dictionary, a list, a string) with every mark in it put right
## for a screen (render), dictionaries and lists in place; keys in `skip`
## (a view's schema, the actions: a ruleset's own, never marked) left alone.
static func render_value(v: Variant, knows: Callable, gm := false, skip: Dictionary = {}) -> Variant:
	if v is String:
		return render(v, knows, gm)
	if v is Dictionary:
		var d: Dictionary = v
		for k in d.keys():
			if skip.has(k):
				continue
			var x: Variant = d[k]
			if x is String or x is Dictionary or x is Array:
				d[k] = render_value(x, knows, gm, skip)
		return d
	if v is Array:
		var arr: Array = v
		for i in arr.size():
			var x: Variant = arr[i]
			if x is String or x is Dictionary or x is Array:
				arr[i] = render_value(x, knows, gm, skip)
		return arr
	return v


## A message as it goes on the wire (JSON text) put right for a screen: the
## marks in it as `knows` says. One cut short is put right in the parsed
## message instead, so the text stays JSON.
static func render_json(text: String, knows: Callable, gm := false) -> String:
	if not text.contains(ANCHOR) and not text.contains(SEP) and not text.contains(END):
		return text
	var out := ""
	var at := 0
	for m in _MARK.search_all(text):
		out += text.substr(at, m.get_start() - at)
		# (a string's first character, after its quote, starts a sentence; so does one
		# after a full stop and a space, or an escaped new line)
		var said := _instead(m, knows, out.ends_with("\"") or out.ends_with("\\n") or _starts_sentence(out))
		at = m.get_end()
		if said == "" and m.get_string(1) != "":
			# (a string's end is its closing quote)
			var cut := _unlist(out, text.substr(at, 2), text.substr(at, 1) == "\"")
			out = cut[0]
			at += int(cut[1])
		out += said
	out += text.substr(at)
	if out.contains(ANCHOR) or out.contains(SEP) or out.contains(END):
		var parsed: Variant = JSON.parse_string(out)
		if parsed == null:
			return out.replace(ANCHOR, "").replace(SEP, "").replace(END, "")
		return JSON.stringify(render_value(parsed, knows, gm))
	return out


## A view (Views.project's, or a part of one with a `log` or a
## `chat_history`) as a screen gets it, in place: every mark in it put right
## for that screen, and each roll naming who rolled and at whom as it knows
## them. The rulesets' own schemas and actions are never marked: passed by.
static func for_viewer(out: Dictionary, actors: Dictionary, policies: Array, gm: bool) -> Dictionary:
	var knows := knower(actors, policies, gm)
	# the DM's: whether the players know each creature's name, where names are kept
	if gm and names_hidden(policies) and out.get("actors") is Dictionary:
		for aid in out.actors:
			var a: Dictionary = actors.get(aid, {})
			if unowned_actor(a) and out.actors[aid] is Dictionary:
				out.actors[aid].name_known = name_known(a, policies)
	for key in ["log", "chat_history"]:
		if out.get(key) is Array:
			for entry in out[key]:
				if entry is Dictionary:
					name_roll(entry, actors, knows)
	for key in out.keys():
		if key in ["actions", "cards", "plugins"]:
			continue
		var x: Variant = out[key]
		if x is String or x is Dictionary or x is Array:
			out[key] = render_value(x, knows, gm, VIEW_SKIP)
	return out


## Keys of a view whose values are a ruleset's own data, never marked.
const VIEW_SKIP := {"schema": true}


## A roll's entry as a screen reads it: who rolled and at whom (`who`,
## `whom`), named as the screen knows them, from its `actor` and `target`.
## `actors` the encounter's.
static func name_roll(entry: Dictionary, actors: Dictionary, knows: Callable) -> void:
	if str(entry.get("kind", "")) != "roll":
		return
	for pair in [["actor", "who", UNKNOWN_START], ["target", "whom", UNKNOWN]]:
		var aid := str(entry.get(pair[0], ""))
		if aid == "" or not actors.has(aid):
			continue
		entry[pair[1]] = str(actors[aid].get("name", aid)) if bool(knows.call("name", aid)) else str(pair[2])
