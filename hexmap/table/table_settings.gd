class_name TableSettings
extends RefCounted
## How a table runs: the DM's choice, not the app's. A DM picks one of four
## levels — from the app as a shared sheet and tracker to the app running
## the rules — and then answers the table's questions: where fights happen,
## dice, what a roll does, what the app checks, what players know, what it
## asks and how long it waits, and the rules options. Every loaded
## ruleset's settings say which question they answer and what each level
## makes them (`x-question`, `x-levels`, `x-notice`, `x-next-fight` beside
## their JSON schema: docs/plugin-authoring.md "Table settings"); the
## table's own (`level`, `space`, `house_rules`) live in the campaign's
## `table` block (docs/campaign-format.md).
##
## `build` is the model the screens draw (the walkthrough, Table settings,
## the players' "How this table runs"), made from the plugins' manifests and
## the values in force. An instance over a TableContext changes them: a
## setting, a level (every setting the level names, as one undoable step), a
## section reset to the level, the table's own fields, the walkthrough's
## answers. Each write is one step of the Table's undo, kept in the
## campaign, with the rules loaded again so sheets and views follow it.
## Plugins go on reading their settings with `hm.settings.get`.
##
## A fight may run otherwise than the table (`x-per-fight` settings, the
## DM's for that fight alone, kept on the prepared fight; and, where the
## table leaves it to each fight, on a map or in the theatre of the mind),
## and in the theatre of the mind a setting may be what it must be there
## (`x-mind`: what can't be checked without positions — range, sight,
## movement — off). The rules load with the fight's own while it runs
## (TableContext.fight_rules); Table settings says what differs for it. A
## campaign started from a package may carry its author's suggestion of a
## level, where fights happen and answers (`recommended`, from the
## package's manifest): the walkthrough offers it, nothing more.

## The levels, least the app does first.
const LEVELS := ["bookkeeping", "rolling", "assisted", "automated"]
## A campaign from before levels has no `table.level`: it runs as this.
## (Its settings are what it always played with, so nothing changes.)
const EXISTING_LEVEL := "automated"
## What the walkthrough offers first, for the DM to confirm or change.
const NEW_LEVEL := "assisted"
## The questions a setting answers (`x-question`), in the order they are asked.
const QUESTIONS := ["space", "dice", "outcomes", "checks", "knowledge", "prompting", "rules", "table"]
## The questions a level answers: the walkthrough's third step.
const LEVEL_QUESTIONS := ["dice", "outcomes", "checks", "knowledge", "prompting"]
## Who notices a setting change (`x-notice`).
const NOTICES := ["dm", "players", "everyone"]
## Where fights happen (`table.space`).
const SPACES := ["maps", "mind", "per_fight"]
## Where one fight happens (a prepared fight's `space`, its `live.space`).
const FIGHT_SPACES := ["maps", "mind"]
## How long an author's note on their suggestion may be.
const NOTE_MAX := 400
## The setting types a screen can show (a choice, a switch, a number, words).
const TYPES := ["string", "boolean", "integer", "number"]
## The campaign's `table` fields and what each may hold.
const TABLE_FIELDS := ["level", "space", "house_rules", "setup"]
## How long house rules may be.
const HOUSE_RULES_MAX := 20000

const LEVEL_INFO := {
	"bookkeeping": {"title": "Bookkeeping", "tagline": "A shared sheet and tracker",
		"lines": ["Your sheet keeps count: you tick off what you spend.",
			"You roll, by hand or with a tap; nothing lands by itself.",
			"The DM types in damage and what it does."]},
	"rolling": {"title": "Rolling help", "tagline": "Actions roll; nothing is applied",
		"lines": ["An attack or a spell rolls when you tap it, every bonus counted.",
			"Nothing lands by itself: the DM applies the damage and the effects.",
			"Movement, reach and reactions are the table's to keep."]},
	"assisted": {"title": "Assisted", "tagline": "The app proposes; the DM approves",
		"lines": ["Your actions roll, and the app works out what they do.",
			"The DM approves each outcome before it lands.",
			"The rules are kept: movement, reach, reactions."]},
	"automated": {"title": "Automated", "tagline": "The app runs the rules",
		"lines": ["Your actions roll, and what they do lands at once.",
			"The rules are kept: movement, reach, reactions.",
			"The DM steps in when they choose to."]},
}

const QUESTION_INFO := {
	"space": {"title": "Where fights happen", "description": "On maps with tokens, in the theatre of the mind, or chosen for each fight."},
	"dice": {"title": "Dice", "description": "Who rolls what, and when."},
	"outcomes": {"title": "What a roll does", "description": "Whether damage and effects land by themselves, wait for the DM, or are the DM's to apply."},
	"checks": {"title": "Rules checks", "description": "What the app checks and refuses: movement, timing, what a character may do."},
	"knowledge": {"title": "What players know", "description": "What the players' screens show them of the creatures and the rolls."},
	"prompting": {"title": "Asking and waiting", "description": "What the app asks of the players and of the DM, and how long it waits for an answer."},
	"rules": {"title": "Rules options", "description": "The rules you play by: yours whatever the level."},
	"table": {"title": "This table", "description": "Your house rules, and the rest."},
}

const SPACE_INFO := {
	"maps": {"title": "On maps", "words": "Fights are played on battle maps, with tokens."},
	"mind": {"title": "In the theatre of the mind", "words": "Fights are told, not drawn: no battle maps, the rolls all the same."},
	"per_fight": {"title": "Each fight decides", "words": "Some fights on a map, some in the mind: chosen as each one starts."},
}
## One fight's place, as the screens say it.
const FIGHT_SPACE_INFO := {
	"maps": {"title": "On its map", "words": "On its battle map, with tokens."},
	"mind": {"title": "In the theatre of the mind", "words": "No map: who's in the fight is a list, and range, sight and movement are yours to judge."},
}

const NOTICE_WORDS := {"dm": "You notice", "players": "Players notice", "everyone": "Everyone notices"}

var ctx: TableContext
## The changes made here, newest last, that the web screen's Undo can take
## back: {id, label, before}. (The Table's own undo is its Edit menu.)
var _changes: Array = []
var _seq := 0


func _init(p_ctx: TableContext = null) -> void:
	ctx = p_ctx


# ------------------------------------------------------------- the model --

## The campaign's `table` block as it stands ({} for a campaign from before).
static func table_of(c: Campaign) -> Dictionary:
	if c == null or not (c.doc.get("table") is Dictionary):
		return {}
	return c.doc.table


## The level a campaign runs at: its own, or EXISTING_LEVEL.
static func level_of(c: Campaign) -> String:
	var lv := str(table_of(c).get("level", ""))
	return lv if LEVELS.has(lv) else EXISTING_LEVEL


## A campaign just made (or started from a package) whose walkthrough is
## not done: the DM's screens offer it.
static func pending(c: Campaign) -> bool:
	return str(table_of(c).get("setup", "")) == "pending"


static func mark_pending(c: Campaign) -> void:
	if not (c.doc.get("table") is Dictionary):
		c.doc.table = {}
	c.doc.table.setup = "pending"


## The loaded plugins as `build` takes them: [{id, name, manifest, values}],
## the values being the settings in force (defaults, then the campaign's).
## With the campaign `c`, the table's own (defaults, then the campaign's),
## whatever a fight running now makes them (TableContext.fight_rules).
static func plugins_of(host: PluginHost, c: Campaign = null) -> Array:
	var out := []
	if host == null:
		return out
	var ids := host.plugins.keys()
	ids.sort()
	for pid in ids:
		var p: PluginHost.Plugin = host.plugins[pid]
		var values: Dictionary = p.settings
		if c != null:
			var dflt: Variant = p.manifest.get("settings", {}).get("defaults", {}) if p.manifest.get("settings") is Dictionary else {}
			values = JsonDoc.deep(dflt) if dflt is Dictionary else {}
			var own := c.plugin_settings(str(pid))
			for k in own:
				JsonDoc.set_at_path(values, str(k), own[k])
		out.append({"id": str(pid), "name": str(p.manifest.get("name", pid)), "manifest": p.manifest, "values": values})
	return out


## A manifest's settings properties ({} when it declares none).
static func properties_of(manifest: Dictionary) -> Dictionary:
	var settings: Variant = manifest.get("settings", {})
	var schema: Variant = settings.get("schema", {}) if settings is Dictionary else {}
	var props: Variant = schema.get("properties", {}) if schema is Dictionary else {}
	return props if props is Dictionary else {}


## Everything the screens draw: the level (its words, whether the campaign
## chose it, whether anything differs from it), where fights happen, the
## house rules, the questions, and every setting — its question, its words,
## its choices, the value in force, each level's value, whether it differs
## from the level's, who notices, whether it waits for the next fight.
static func build(plugins: Array, table: Dictionary) -> Dictionary:
	var level := str(table.get("level", ""))
	var level_set := LEVELS.has(level)
	if not level_set:
		level = EXISTING_LEVEL
	var space := str(table.get("space", "maps"))
	if not SPACES.has(space):
		space = "maps"
	var settings := []
	var names := []
	for p in plugins:
		var manifest: Dictionary = p.get("manifest", {})
		var props := properties_of(manifest)
		if props.is_empty():
			continue
		names.append({"id": str(p.id), "name": str(p.get("name", p.id))})
		var defaults: Variant = manifest.get("settings", {}).get("defaults", {}) if manifest.get("settings") is Dictionary else {}
		var values: Dictionary = p.get("values", {}) if p.get("values") is Dictionary else {}
		for key in props:
			var it := item_of(str(p.id), str(p.get("name", p.id)), str(key), props[key], defaults if defaults is Dictionary else {}, values)
			if it.is_empty():
				continue
			it.differs = (it.levels as Dictionary).has(level) and not JsonDoc.same(it.value, it.levels[level])
			if (it.levels as Dictionary).has(level):
				it.level_value = JsonDoc.deep(it.levels[level])
			settings.append(it)
	var differs := settings.filter(func(it: Dictionary) -> bool: return bool(it.differs)).size()
	var questions := []
	for q in QUESTIONS:
		var ids := []
		for it in settings:
			if str(it.question) == q:
				ids.append(str(it.id))
		questions.append({"id": q, "title": str(QUESTION_INFO[q].title), "description": str(QUESTION_INFO[q].description),
			"settings": ids, "level": LEVEL_QUESTIONS.has(q)})
	var levels := []
	for lv in LEVELS:
		levels.append({"id": lv, "title": str(LEVEL_INFO[lv].title), "tagline": str(LEVEL_INFO[lv].tagline), "lines": (LEVEL_INFO[lv].lines as Array).duplicate()})
	var spaces := []
	for s in SPACES:
		spaces.append({"id": s, "title": str(SPACE_INFO[s].title), "words": str(SPACE_INFO[s].words)})
	return {"level": level, "level_set": level_set, "customized": differs > 0, "differs": differs,
		"pending": str(table.get("setup", "")) == "pending",
		"space": space, "house_rules": str(table.get("house_rules", "")),
		"levels": levels, "spaces": spaces, "questions": questions, "settings": settings, "plugins": names,
		"new_level": NEW_LEVEL, "existing_level": EXISTING_LEVEL}


## One setting as the screens draw it, or {} for one they cannot (a
## property with no type a screen shows).
static func item_of(pid: String, pname: String, key: String, d: Variant, defaults: Dictionary, values: Dictionary) -> Dictionary:
	if not (d is Dictionary) or not TYPES.has(str(d.get("type", ""))):
		return {}
	var dflt: Variant = defaults.get(key, d.get("default"))
	var it := {"id": "%s/%s" % [pid, key], "plugin": pid, "plugin_name": pname, "key": key,
		"title": str(d.get("title", key)), "description": str(d.get("description", "")), "type": str(d.type),
		"value": JsonDoc.deep(values.get(key, dflt)), "default": JsonDoc.deep(dflt)}
	if d.get("enum") is Array:
		it.enum = JsonDoc.deep(d.enum)
		it.labels = JsonDoc.deep(d.enumNames) if d.get("enumNames") is Array and (d.enumNames as Array).size() == (d.enum as Array).size() else (d.enum as Array).map(func(v: Variant) -> String: return str(v))
	for bound in ["minimum", "maximum"]:
		if d.has(bound) and (d[bound] is float or d[bound] is int):
			it[bound] = int(d[bound]) if str(d.type) == "integer" else d[bound]
	var q := str(d.get("x-question", ""))
	it.question = q if QUESTIONS.has(q) else "rules"
	var notice := str(d.get("x-notice", ""))
	it.notice = notice if NOTICES.has(notice) else ""
	it.next_fight = d.get("x-next-fight") == true
	# the DM may set it for one fight alone; and what it is in the theatre of the mind
	it.per_fight = d.get("x-per-fight") == true
	if d.has("x-mind"):
		var rm := check_value(it, d["x-mind"])
		if str(rm[0]) == "":
			it.mind = rm[1]
	# each level's value, as the schema allows it (one it does not is left out)
	var levels := {}
	if d.get("x-levels") is Dictionary:
		for lv in LEVELS:
			if (d["x-levels"] as Dictionary).has(lv):
				var r := check_value(it, d["x-levels"][lv])
				if str(r[0]) == "":
					levels[lv] = r[1]
	it.levels = levels
	return it


## A value for a setting as its schema allows it: ["", the value made
## right (a whole number an int)] or [why not, null].
static func check_value(it: Dictionary, value: Variant) -> Array:
	var v: Variant = value
	var title := str(it.get("title", it.get("key", "")))
	match str(it.get("type", "")):
		"boolean":
			if not (v is bool):
				return ["%s: on or off" % title, null]
		"integer", "number":
			if not (v is float or v is int):
				return ["%s: a number" % title, null]
			if str(it.type) == "integer":
				if float(v) != floorf(float(v)):
					return ["%s: a whole number" % title, null]
				v = int(v)
			if it.has("minimum") and float(v) < float(it.minimum):
				return ["%s: at least %s" % [title, number_words(it.minimum)], null]
			if it.has("maximum") and float(v) > float(it.maximum):
				return ["%s: at most %s" % [title, number_words(it.maximum)], null]
		_:
			if not (v is String):
				return ["%s: words" % title, null]
	if it.get("enum") is Array and choice_index(it, v) < 0:
		return ["%s: not one of the choices" % title, null]
	return ["", v]


## Where a value is among a setting's choices (-1: not one of them).
static func choice_index(it: Dictionary, v: Variant) -> int:
	var choices: Array = it.get("enum", [])
	for i in choices.size():
		if JsonDoc.same(choices[i], v):
			return i
	return -1


## A number as words: 20, not 20.0.
static func number_words(n: Variant) -> String:
	if (n is float) and is_finite(n) and n == floorf(n):
		return str(int(n))
	return str(n)


## A value as the screens say it: a choice's label, On or Off, a number.
static func value_words(it: Dictionary, v: Variant) -> String:
	if it.get("enum") is Array:
		var i := choice_index(it, v)
		if i >= 0:
			return str((it.get("labels", it.enum) as Array)[i])
	match str(it.get("type", "")):
		"boolean":
			return "On" if v == true else "Off"
		"integer", "number":
			return number_words(v) if (v is float or v is int) else str(v)
	return str(v)


## What switching to `level` changes, setting by setting: [{id, plugin,
## key, title, question, from, to, from_words, to_words, notice,
## next_fight}] (only settings whose value would change).
static func changes_for_level(reg: Dictionary, level: String) -> Array:
	var out := []
	for it in reg.get("settings", []):
		if not (it.levels as Dictionary).has(level):
			continue
		var to: Variant = it.levels[level]
		if JsonDoc.same(it.value, to):
			continue
		out.append({"id": str(it.id), "plugin": str(it.plugin), "key": str(it.key), "title": str(it.title), "question": str(it.question),
			"from": JsonDoc.deep(it.value), "to": JsonDoc.deep(to), "from_words": value_words(it, it.value), "to_words": value_words(it, to),
			"notice": str(it.notice), "next_fight": bool(it.next_fight)})
	return out


## The preview of a level switch, in a sentence: "3 settings change: …".
static func change_words(changes: Array) -> String:
	if changes.is_empty():
		return "Nothing changes: every setting already is as that level has it."
	var bits := PackedStringArray()
	for ch in changes:
		bits.append("%s (%s → %s)" % [str(ch.title), str(ch.from_words), str(ch.to_words)])
	return "%d setting%s change%s: %s." % [changes.size(), "" if changes.size() == 1 else "s", "s" if changes.size() == 1 else "", "; ".join(bits)]


## The settings of a question, in a line: "Title: value · Title: value",
## with `values` (id → value) over the ones in force (the walkthrough's).
static func question_line(reg: Dictionary, question: String, values: Dictionary = {}) -> String:
	var bits := PackedStringArray()
	for it in reg.get("settings", []):
		if str(it.question) == question:
			bits.append("%s: %s" % [str(it.title), value_words(it, values.get(str(it.id), it.value))])
	return " · ".join(bits)


## What the players are told of how this table runs: the level in plain
## words, where fights happen, the answers they notice, the house rules.
static func player_summary(reg: Dictionary) -> Dictionary:
	var level := str(reg.get("level", EXISTING_LEVEL))
	var info: Dictionary = LEVEL_INFO.get(level, LEVEL_INFO[EXISTING_LEVEL])
	var answers := []
	for q in QUESTIONS:
		var items := []
		for it in reg.get("settings", []):
			if str(it.question) == q and str(it.notice) in ["players", "everyone"]:
				items.append({"title": str(it.title), "value": value_words(it, it.value)})
		if not items.is_empty():
			answers.append({"question": q, "title": str(QUESTION_INFO[q].title), "items": items})
	var space := str(reg.get("space", "maps"))
	# what each player may choose for themselves at this table (PlayerPrefs): the
	# ones offered now; a player's screen reads its own choices off its record
	var prefs := []
	for it in reg.get("prefs", []):
		if bool(it.get("offered", false)):
			prefs.append(JsonDoc.deep(it))
	return {"level": level, "title": str(info.title), "tagline": str(info.tagline), "lines": (info.lines as Array).duplicate(),
		"set": bool(reg.get("level_set", false)), "space": space, "space_title": str(SPACE_INFO.get(space, SPACE_INFO.maps).title),
		"space_words": str(SPACE_INFO.get(space, SPACE_INFO.maps).words), "answers": answers, "house_rules": str(reg.get("house_rules", "")),
		"prefs": prefs}


## What is wrong with a manifest's table-settings metadata (the `x-*` keys
## beside each setting's schema), as sentences; [] when nothing is.
## `plugintest` reports these as failed checks.
static func check_manifest(manifest: Dictionary) -> Array:
	var out := []
	var props := properties_of(manifest)
	var defaults: Variant = manifest.get("settings", {}).get("defaults", {}) if manifest.get("settings") is Dictionary else {}
	for key in props:
		var d: Variant = props[key]
		if not (d is Dictionary):
			out.append("setting '%s' is not an object" % key)
			continue
		var it := item_of("p", "", str(key), d, defaults if defaults is Dictionary else {}, {})
		if d.has("x-question") and not QUESTIONS.has(str(d["x-question"])):
			out.append("setting '%s': x-question '%s' is not one of %s" % [key, str(d["x-question"]), ", ".join(PackedStringArray(QUESTIONS))])
		if d.has("x-notice") and not NOTICES.has(str(d["x-notice"])):
			out.append("setting '%s': x-notice '%s' is not one of %s" % [key, str(d["x-notice"]), ", ".join(PackedStringArray(NOTICES))])
		if d.has("x-next-fight") and not (d["x-next-fight"] is bool):
			out.append("setting '%s': x-next-fight is true or false" % key)
		if d.has("x-per-fight") and not (d["x-per-fight"] is bool):
			out.append("setting '%s': x-per-fight is true or false" % key)
		if d.has("x-per-fight") and d["x-per-fight"] == true and it.is_empty():
			out.append("setting '%s': x-per-fight on a setting no screen shows (type '%s')" % [key, str(d.get("type", ""))])
		if d.has("x-mind"):
			if it.is_empty():
				out.append("setting '%s': x-mind on a setting no screen shows (type '%s')" % [key, str(d.get("type", ""))])
			else:
				var rm := check_value(it, d["x-mind"])
				if str(rm[0]) != "":
					out.append("setting '%s': its x-mind value: %s" % [key, str(rm[0])])
		if d.has("x-levels"):
			if not (d["x-levels"] is Dictionary):
				out.append("setting '%s': x-levels is an object of level → value" % key)
			elif it.is_empty():
				out.append("setting '%s': x-levels on a setting no screen shows (type '%s')" % [key, str(d.get("type", ""))])
			else:
				for lv in d["x-levels"]:
					if not LEVELS.has(str(lv)):
						out.append("setting '%s': x-levels names '%s', not one of %s" % [key, str(lv), ", ".join(PackedStringArray(LEVELS))])
						continue
					var r := check_value(it, d["x-levels"][lv])
					if str(r[0]) != "":
						out.append("setting '%s': its %s value: %s" % [key, str(lv), str(r[0])])
	return out


# ------------------------------------------------------------ the writes --

## The model over the open campaign and the rules loaded now, with whether
## a fight is running (a setting that waits for the next fight says so)
## and the change the web screen's Undo would take back. Its values are the
## table's; the fight in front of everybody, when one runs, is `this_fight`
## — {id, name, space, space_title, settings (its own), differs} — and each
## setting it makes otherwise says so (`fight_value`, `fight_words`,
## `fight_why`: "fight", its own for this fight, or "mind", the theatre of
## the mind's). An author's suggestion, for a campaign started from their
## package, is `recommended` (recommended_of).
func registry() -> Dictionary:
	if ctx == null or ctx.campaign == null:
		return {}
	var reg := build(plugins_of(ctx.host, ctx.campaign), table_of(ctx.campaign))
	reg.fight = _fight_running()
	reg.undo = str(_changes.back().label) if not _changes.is_empty() else ""
	var fr := ctx.fight_rules()
	if not fr.is_empty():
		reg.this_fight = _this_fight(reg, fr)
	var rec := recommended_of(ctx.campaign, reg)
	if not rec.is_empty():
		reg.recommended = rec
	reg.fight_spaces = FIGHT_SPACES.map(func(s: String) -> Dictionary: return {"id": s, "title": str(FIGHT_SPACE_INFO[s].title), "words": str(FIGHT_SPACE_INFO[s].words)})
	# what players may choose for themselves (PlayerPrefs), and each one's choices
	reg.prefs = PlayerPrefs.items(ctx.host)
	reg.players = PlayerPrefs.players(ctx.encounter(), ctx.host)
	return reg


## The fight running now, as Table settings says it: what it is, and each
## setting it makes otherwise than the table, marked on the setting.
func _this_fight(reg: Dictionary, fr: Dictionary) -> Dictionary:
	var e := ctx.campaign.encounter_entry(str(fr.get("id", "")))
	var own: Dictionary = fr.get("settings", {})
	var mind := str(fr.get("space", "")) == Encounter.SPACE_MIND
	var n := 0
	for it in reg.get("settings", []):
		var p: PluginHost.Plugin = ctx.host.plugins.get(str(it.plugin)) if ctx.host != null else null
		if p == null:
			continue
		var now: Variant = JsonDoc.at_path(p.settings, str(it.key)) if str(it.key).contains("/") else p.settings.get(str(it.key), it.value)
		if JsonDoc.same(now, it.value):
			continue
		it.fight_value = JsonDoc.deep(now)
		it.fight_words = value_words(it, now)
		it.fight_why = "mind" if mind and it.has("mind") and JsonDoc.same(it.mind, now) else "fight"
		n += 1
	var space := Encounter.SPACE_MIND if mind else "maps"
	return {"id": str(fr.get("id", "")), "name": str(e.get("name", "")), "space": space, "space_title": str(FIGHT_SPACE_INFO[space].title),
		"settings": JsonDoc.deep(own), "differs": n}


# ---------------------------------------------------------------- a fight --

## What Table settings says of the fight running now (`this_fight`): "This
## fight (On the bridge, in the theatre of the mind) runs otherwise: 2
## settings differ for it, and only while it runs." — or "" when none runs,
## or it runs as the table does.
static func this_fight_words(reg: Dictionary) -> String:
	var f: Variant = reg.get("this_fight", {})
	if not (f is Dictionary) or (f as Dictionary).is_empty():
		return ""
	var fname := str(f.get("name", "")) if str(f.get("name", "")) != "" else "the fight"
	var mind := str(f.get("space", "")) == Encounter.SPACE_MIND
	var n := int(f.get("differs", 0))
	if n == 0:
		return "This fight (%s) is in the theatre of the mind." % fname if mind else ""
	return "This fight (%s%s) runs otherwise: %d setting%s for it, and only while it runs." % [fname, ", in the theatre of the mind" if mind else "", n, " differs" if n == 1 else "s differ"]


## Why a setting is otherwise in this fight, in words ("" when it isn't).
static func fight_why_words(it: Dictionary) -> String:
	if not it.has("fight_value"):
		return ""
	return "this fight: %s (%s)" % [str(it.get("fight_words", "")), "the theatre of the mind: yours to judge" if str(it.get("fight_why", "")) == "mind" else "its own"]


## Where a prepared fight is fought: the table's place (on maps, or in the
## theatre of the mind), or — where the table leaves it to each fight —
## `asked` (the DM's choice as it starts), else the fight's own (`space`),
## else on its map when it has one.
static func fight_space(c: Campaign, e: Dictionary, asked := "") -> String:
	var table := str(table_of(c).get("space", "maps"))
	if table == "mind":
		return Encounter.SPACE_MIND
	if table != "per_fight":
		return "maps"
	if FIGHT_SPACES.has(asked):
		return asked
	var own := str(e.get("space", ""))
	if FIGHT_SPACES.has(own):
		return own
	return "maps" if str(e.get("map", "")) != "" else Encounter.SPACE_MIND


## What an author suggests for a campaign started from their package (its
## manifest's `recommended`, kept in the campaign's `package` block): {level,
## space, answers ({"<plugin>/<key>": value}), note, by (the package), words
## ("The author suggests Assisted, on maps.")} with only what this table
## knows and each setting's schema allows; {} when it suggests nothing.
static func recommended_of(c: Campaign, reg: Dictionary) -> Dictionary:
	var pkg: Variant = c.doc.get("package", {}) if c != null else {}
	if not (pkg is Dictionary):
		return {}
	var rec: Variant = pkg.get("recommended", {})
	if not (rec is Dictionary) or (rec as Dictionary).is_empty():
		return {}
	var out := {}
	if LEVELS.has(str(rec.get("level", ""))):
		out.level = str(rec.level)
	if SPACES.has(str(rec.get("space", ""))):
		out.space = str(rec.space)
	var answers := {}
	if rec.get("answers") is Dictionary:
		var items := {}
		for it in reg.get("settings", []):
			items[str(it.id)] = it
		for id in rec.answers:
			if items.has(str(id)):
				var r := check_value(items[str(id)], rec.answers[id])
				if str(r[0]) == "":
					answers[str(id)] = r[1]
	if not out.has("level") and not out.has("space") and answers.is_empty():
		return {}
	out.answers = answers
	out.note = str(rec.get("note", "")).strip_edges().left(NOTE_MAX)
	out.by = str(pkg.get("name", ""))
	out.words = suggestion_words(out)
	return out


## An author's suggestion in a sentence: "The author suggests Assisted, on
## maps." (with "and N settings of their own" when it answers some).
static func suggestion_words(rec: Dictionary) -> String:
	var bits := PackedStringArray()
	if rec.has("level") and LEVEL_INFO.has(str(rec.level)):
		bits.append(str(LEVEL_INFO[rec.level].title))
	if rec.has("space") and SPACE_INFO.has(str(rec.space)):
		var t := str(SPACE_INFO[rec.space].title)
		bits.append(t.left(1).to_lower() + t.substr(1))
	var n := (rec.get("answers", {}) as Dictionary).size() if rec.get("answers") is Dictionary else 0
	var said := "The author suggests " + ", ".join(bits) if not bits.is_empty() else "The author suggests"
	if n > 0:
		said += ("," if not bits.is_empty() else "") + " %d setting%s of their own" % [n, "" if n == 1 else "s"]
	return said + "."


## What the players are told, for the open campaign ({} with none), with
## its id (a browser remembers having shown it, campaign by campaign).
func players_summary() -> Dictionary:
	var reg := registry()
	if reg.is_empty():
		return {}
	var out := player_summary(reg)
	out.campaign = ctx.campaign.id
	return out


func _fight_running() -> bool:
	for enc in ctx.campaign.encounters:
		if enc is Dictionary and enc.get("live") is Dictionary and not (enc.live as Dictionary).is_empty():
			return true
	return false


## One setting. "" or why not.
func set_setting(pid: String, key: String, value: Variant) -> String:
	var it := _item(pid, key)
	if not it.has("id"):
		return str(it.get("why", "no such setting"))
	var r := check_value(it, value)
	if str(r[0]) != "":
		return str(r[0])
	return _write([{"plugin": pid, "key": key, "value": r[1]}], {}, "%s: %s" % [str(it.title), value_words(it, r[1])])


## A level: every setting it names takes its value, and the campaign runs
## at it — one undoable step. "" or why not.
func set_level(level: String) -> String:
	if not LEVELS.has(level):
		return "which level? %s" % ", ".join(PackedStringArray(LEVELS))
	var writes := []
	for it in registry().get("settings", []):
		if (it.levels as Dictionary).has(level):
			writes.append({"plugin": str(it.plugin), "key": str(it.key), "value": it.levels[level]})
	return _write(writes, {"level": level}, "Table level: %s" % str(LEVEL_INFO[level].title))


## A question's settings back to what the level makes them. "" or why not.
func reset_question(question: String) -> String:
	if not QUESTIONS.has(question):
		return "which section?"
	var reg := registry()
	var level := str(reg.get("level", EXISTING_LEVEL))
	var writes := []
	for it in reg.get("settings", []):
		if str(it.question) == question and (it.levels as Dictionary).has(level):
			writes.append({"plugin": str(it.plugin), "key": str(it.key), "value": it.levels[level]})
	if writes.is_empty():
		return "nothing in %s follows the level" % str(QUESTION_INFO[question].title)
	return _write(writes, {}, "%s back to %s" % [str(QUESTION_INFO[question].title), str(LEVEL_INFO[level].title)])


## A player's preference, as the DM sets it (whatever the table offers them
## now: the DM can change anything), one step of the Table's undo. "" or
## why not.
func set_pref(pid: String, plugin: String, key: String, value: Variant) -> String:
	if ctx == null or ctx.campaign == null:
		return "no campaign is open"
	var why := PlayerPrefs.change(ctx.encounter(), ctx.host, pid, plugin, key, value, "",
		func(events: Array, label: String, reason: Dictionary) -> String: return ctx.commands.run_all(events, label, reason))
	if why == "":
		ctx.campaign.touch()
		ctx.campaign_changed.emit()
	return why


## The table's own: where fights happen, the house rules. "" or why not.
func set_table(changes: Dictionary) -> String:
	var t := {}
	for k in changes:
		if not ["space", "house_rules"].has(str(k)):
			return "the table has no '%s'" % str(k)
		t[str(k)] = changes[k]
	if t.is_empty():
		return "nothing to change"
	var label := "Where fights happen" if t.has("space") else "House rules"
	return _write([], t, label)


## A prepared fight's own, as one step of the Table's undo: where it is
## fought (`space`: "maps", "mind", or "" for what the table says; it is
## read as the fight starts) and its settings for that fight alone
## (`settings`: {"<plugin>/<key>": value, or null to take one back} — only a
## setting that says a fight may have its own: x-per-fight). The rules
## follow at once when it is the fight running. "" or why not.
func set_fight(enc_id: String, changes: Dictionary) -> String:
	if ctx == null or ctx.campaign == null:
		return "no campaign is open"
	var e := ctx.campaign.encounter_entry(enc_id)
	if e.is_empty():
		return "no such fight"
	var before := _fight_snapshot(e)
	var after: Dictionary = JsonDoc.deep(before)
	var label := ""
	if changes.has("space"):
		var sp: Variant = changes.space
		if sp == null or str(sp) == "":
			after.space = null
		elif FIGHT_SPACES.has(str(sp)):
			after.space = str(sp)
		else:
			return "on its map, or in the theatre of the mind"
		label = "%s: %s" % [str(e.get("name", "The fight")), str(FIGHT_SPACE_INFO[str(sp)].title) if FIGHT_SPACES.has(str(sp)) else "as the table says"]
	if changes.has("settings"):
		if not (changes.settings is Dictionary):
			return "which settings?"
		var items := {}
		for it in registry().get("settings", []):
			items[str(it.id)] = it
		var said := PackedStringArray()
		for id in changes.settings:
			var it: Dictionary = items.get(str(id), {})
			if it.is_empty():
				return "no setting '%s' here" % str(id)
			if not bool(it.get("per_fight", false)):
				return "%s is the table's, not one fight's" % str(it.title)
			var v: Variant = changes.settings[id]
			if v == null:
				(after.settings as Dictionary).erase(str(id))
				said.append("%s as the table has it" % str(it.title))
				continue
			var r := check_value(it, v)
			if str(r[0]) != "":
				return str(r[0])
			after.settings[str(id)] = r[1]
			said.append("%s: %s" % [str(it.title), value_words(it, r[1])])
		label = "%s, this fight: %s" % [str(e.get("name", "The fight")), "; ".join(said)]
	if label == "":
		return "nothing to change"
	if JsonDoc.same(before, after):
		return ""
	var me: WeakRef = weakref(self)
	ctx.history.commit(label,
		func() -> void:
			var s: TableSettings = me.get_ref()
			if s != null:
				s._put_fight(enc_id, after),
		func() -> void:
			var s: TableSettings = me.get_ref()
			if s != null:
				s._put_fight(enc_id, before))
	return ""


func _fight_snapshot(e: Dictionary) -> Dictionary:
	return {"space": str(e.space) if FIGHT_SPACES.has(str(e.get("space", ""))) else null,
		"settings": JsonDoc.deep(e.settings) if e.get("settings") is Dictionary else {}}


## Make a prepared fight hold `state` (a _fight_snapshot), and the rules
## follow when it is the one running.
func _put_fight(enc_id: String, state: Dictionary) -> void:
	var e := ctx.campaign.encounter_entry(enc_id) if ctx.campaign != null else {}
	if e.is_empty():
		return
	if state.space == null:
		e.erase("space")
	else:
		e.space = str(state.space)
	if (state.settings as Dictionary).is_empty():
		e.erase("settings")
	else:
		e.settings = JsonDoc.deep(state.settings)
	ctx.campaign.touch()
	ctx.sync_fight_rules()
	ctx.campaign_changed.emit()


## The walkthrough's answers, as one step: {space, level, settings
## ({"<plugin>/<key>": value}, over the level's values), house_rules}. The
## campaign is set up after it. "" or why not.
func finish_setup(answers: Dictionary) -> String:
	var level := str(answers.get("level", NEW_LEVEL))
	if not LEVELS.has(level):
		return "which level? %s" % ", ".join(PackedStringArray(LEVELS))
	var values := {}
	var reg := registry()
	for it in reg.get("settings", []):
		if (it.levels as Dictionary).has(level):
			values[str(it.id)] = it.levels[level]
	var own: Variant = answers.get("settings", {})
	if own is Dictionary:
		for id in own:
			values[str(id)] = own[id]
	var writes := []
	for id in values:
		var at := str(id).rfind("/")
		if at <= 0:
			return "'%s' is not a setting" % str(id)
		writes.append({"plugin": str(id).substr(0, at), "key": str(id).substr(at + 1), "value": values[id]})
	var t := {"level": level, "setup": null}
	if answers.has("space"):
		t.space = answers.space
	if answers.has("house_rules"):
		t.house_rules = answers.house_rules
	return _write(writes, t, "Set up the table: %s" % str(LEVEL_INFO[level].title))


## The web screen's Undo: the newest change here taken back, as a step of
## its own. "" or why not.
func undo_last() -> String:
	if _changes.is_empty():
		return "nothing to undo"
	var last: Dictionary = _changes.pop_back()
	var now := _snapshot(last.before)
	var me: WeakRef = weakref(self)
	var before: Dictionary = last.before
	ctx.history.commit("Undo " + str(last.label),
		func() -> void:
			var s: TableSettings = me.get_ref()
			if s != null:
				s._put(before),
		func() -> void:
			var s: TableSettings = me.get_ref()
			if s != null:
				s._put(now))
	return ""


func _item(pid: String, key: String) -> Dictionary:
	if ctx == null or ctx.campaign == null:
		return {"why": "no campaign is open"}
	if ctx.host == null or not ctx.host.plugins.has(pid):
		return {"why": "no ruleset '%s' here" % pid}
	for it in registry().get("settings", []):
		if str(it.plugin) == pid and str(it.key) == key:
			return it
	return {"why": "'%s' has no setting '%s'" % [pid, key]}


## Settings ([{plugin, key, value}]) and the table's own fields (a null
## value takes one away), checked, then kept as one step of the Table's
## undo. "" or why not (nothing is changed then).
func _write(writes: Array, table_changes: Dictionary, label: String) -> String:
	if ctx == null or ctx.campaign == null:
		return "no campaign is open"
	var after := {"settings": {}, "table": {}}
	var items := {}
	for it in registry().get("settings", []):
		items[str(it.id)] = it
	for w in writes:
		var id := "%s/%s" % [str(w.plugin), str(w.key)]
		if not items.has(id):
			return "no setting '%s' here" % id
		var r := check_value(items[id], w.value)
		if str(r[0]) != "":
			return str(r[0])
		after.settings[id] = {"plugin": str(w.plugin), "key": str(w.key), "has": true, "value": r[1]}
	for k in table_changes:
		var v: Variant = table_changes[k]
		match str(k):
			"level":
				if not LEVELS.has(str(v)):
					return "which level?"
			"space":
				if not SPACES.has(str(v)):
					return "maps, the theatre of the mind, or each fight's own"
			"house_rules":
				if not (v is String):
					return "house rules are words"
				if (v as String).length() > HOUSE_RULES_MAX:
					return "house rules: at most %d characters" % HOUSE_RULES_MAX
			"setup":
				if v != null and str(v) != "pending":
					return "set up or not"
			_:
				return "the table has no '%s'" % str(k)
		after.table[str(k)] = {"has": v != null, "value": JsonDoc.deep(v)}
	var before := _snapshot(after)
	if JsonDoc.same(before, after):
		return ""
	# (a walkthrough done stays done: undoing it puts the settings back, not the walkthrough)
	if (before.table as Dictionary).has("setup"):
		before.table.setup = {"has": false, "value": null}
	_seq += 1
	var change := {"id": _seq, "label": label, "before": before}
	var me: WeakRef = weakref(self)
	# (the closures live on the Table's undo stack: they hold this weakly)
	ctx.history.commit(label,
		func() -> void:
			var s: TableSettings = me.get_ref()
			if s == null:
				return
			s._put(after)
			if not s._changes.has(change):
				s._changes.append(change),
		func() -> void:
			var s: TableSettings = me.get_ref()
			if s == null:
				return
			s._put(before)
			s._changes.erase(change))
	return ""


## The campaign's stored values for the same settings and fields as `of`.
func _snapshot(of: Dictionary) -> Dictionary:
	var c := ctx.campaign
	var out := {"settings": {}, "table": {}}
	for id in of.settings:
		var s: Dictionary = of.settings[id]
		var stored := c.plugin_settings(str(s.plugin))
		out.settings[id] = {"plugin": str(s.plugin), "key": str(s.key), "has": stored.has(str(s.key)), "value": JsonDoc.deep(stored.get(str(s.key)))}
	var t := table_of(c)
	for k in of.table:
		out.table[k] = {"has": t.has(k), "value": JsonDoc.deep(t.get(k))}
	return out


## Make the campaign hold `state` (a snapshot's shape), then load the rules
## again with it when a setting changed, so sheets and views follow.
func _put(state: Dictionary) -> void:
	var c := ctx.campaign
	if c == null:
		return
	# a campaign that names no rulesets plays every one installed; once one
	# carries settings the list is what loads, so all of them are named first
	if c.plugin_order().is_empty() and ctx.host != null and not (state.settings as Dictionary).is_empty():
		for pid in ctx.host.plugins:
			c.plugins.append({"id": str(pid)})
	for id in state.settings:
		var s: Dictionary = state.settings[id]
		if bool(s.has):
			c.set_plugin_setting(str(s.plugin), str(s.key), JsonDoc.deep(s.value))
		else:
			c.clear_plugin_setting(str(s.plugin), str(s.key))
	if not (state.table as Dictionary).is_empty():
		if not (c.doc.get("table") is Dictionary):
			c.doc.table = {}
		for k in state.table:
			if bool(state.table[k].has):
				c.doc.table[k] = JsonDoc.deep(state.table[k].value)
			else:
				c.doc.table.erase(k)
	c.touch()
	if not (state.settings as Dictionary).is_empty():
		ctx.reload_plugins()
	ctx.campaign_changed.emit()
