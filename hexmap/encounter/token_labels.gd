class_name TokenLabels
extends RefCounted
## What each token on a scene says on the map, worked out over all of them —
## the hidden ones too, so the DM's screen and every player's number alike
## (a player whose view hides GW1 still sees GW2, as the DM calls it out).
##
## A creature (an actor's token with no owner) whose label is empty or its
## name's first letter says its name's initials, the trailing number left
## off, up to three words: Goblin Warrior 2 is GW, Bandit Captain BC. A stem
## with company on the scene is numbered — GW1, GW2, GW3, by the names'
## own numbers where they have them — and a lone one stays as it is. Other
## tokens keep their labels: a player's "GA", a place's marker. A stem that
## would read like another's, or like a label kept, takes the next letter
## of its last word (a Giant Ape beside a player's GA is GAP). In a playtest
## every goblin was "G": a Minion and a Warrior were both G1, the Bandit
## Captain and a Bandit both B1.

## Words an initial is not taken from ("Swarm of Bats" is SB), unless a name
## has no other.
const LINKS := ["of", "the", "and", "a", "an", "in", "on", "to", "from", "with"]
static var _NUMBER := RegEx.create_from_string("\\s+(\\d+)$")


## {token id: label} for a scene's tokens, in its order. With `state`, a
## token is a party member's through its actor's owner too.
static func of_scene(tokens: Array, state: EncounterState = null) -> Dictionary:
	var out := {}
	var kept := {}
	var names := {}
	var creatures := []
	for tk in tokens:
		var id := str(tk.get("id", ""))
		var label := str(tk.get("label", "")) if tk.get("label") != null else ""
		var name := str(tk.get("name", "")) if tk.get("name") != null else ""
		var bare := _NUMBER.sub(name, "").strip_edges()
		if not _creature(tk, state) or (label != "" and label.to_upper() != name.left(1).to_upper()) or bare == "":
			out[id] = label
			if label != "":
				kept[label] = true
			continue
		names[id] = bare
		creatures.append(tk)
	# a stem for each name, the later one giving way on a clash
	var stems := {}
	var taken := kept.duplicate()
	for tk in creatures:
		var bare: String = names[str(tk.id)]
		if stems.has(bare):
			continue
		var stem := _stem(bare, taken)
		stems[bare] = stem
		taken[stem] = true
	# numbered where a stem has company: the names' own numbers first
	var groups := {}
	for tk in creatures:
		var stem: String = stems[names[str(tk.id)]]
		if not groups.has(stem):
			groups[stem] = []
		groups[stem].append(tk)
	for stem in groups:
		var members: Array = groups[stem]
		if members.size() == 1:
			out[str(members[0].id)] = stem
			continue
		var claimed := {}
		var rest := []
		for tk in members:
			var m := _NUMBER.search(str(tk.get("name", "")))
			var n := int(m.get_string(1)) if m != null else 0
			if n > 0 and not claimed.has(n):
				claimed[n] = true
				out[str(tk.id)] = "%s%d" % [stem, n]
			else:
				rest.append(tk)
		var next := 1
		for tk in rest:
			while claimed.has(next):
				next += 1
			claimed[next] = true
			out[str(tk.id)] = "%s%d" % [stem, next]
	return out


## A creature's own token: an actor's, with no player's name on it.
static func _creature(tk: Dictionary, state: EncounterState) -> bool:
	var actor := str(tk.get("actor", "")) if tk.get("actor") != null else ""
	if actor == "" or (tk.get("owner") != null and str(tk.owner) != ""):
		return false
	return state == null or str(state.encounter.actor(actor).get("owner", "")) == ""


## Initials of up to three words (the linking ones left out), and — while
## they read like one `taken` — the next letter of the last word.
static func _stem(bare: String, taken: Dictionary) -> String:
	var words := []
	for w in bare.split(" ", false):
		if not LINKS.has(w.to_lower()):
			words.append(w)
	if words.is_empty():
		words = Array(bare.split(" ", false))
	words = words.slice(0, 3)
	var stem := ""
	for w in words:
		stem += str(w).left(1).to_upper()
	var last := str(words.back())
	var i := 1
	while taken.has(stem) and i < last.length():
		stem += last.substr(i, 1).to_upper()
		i += 1
	return stem
