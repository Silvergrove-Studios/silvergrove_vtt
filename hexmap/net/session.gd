class_name Session
extends RefCounted
## What a Player client talks to: the encounter as this player is allowed
## to see it, and a way to ask for changes. The client never applies an
## event itself — it sends a request and the authority (the Table) decides,
## which is the same whether the authority is across the network or, as in
## LocalSession, a file on this device. Every Player UI is written against
## this so the network version drops in without touching it.

## The encounter changed (a relay of Encounter.changed).
signal changed(what: String, scene_id: String)
## Something the player should be told (a refused move, a reconnect).
signal status(text: String)
## The session ended: the host left, the file went away.
signal closed(reason: String)

## The client's projection of the rules (Views.project) changed.
signal view_changed

var state: EncounterState
## Who this client is. "" is the DM's own view.
var player_id := ""
## "player" or "display".
var role := "player"
## The rules as this client may see them: sheets, effects, tracks,
## prompts, the log. Empty until the table sends one.
var view: Dictionary = {}
var warnings: PackedStringArray = []


func player() -> Dictionary:
	return state.encounter.player(player_id) if state != null else {}


func player_name() -> String:
	return str(player().get("name", "")) if not player().is_empty() else "the DM"


## The scene the players are shown.
func scene_id() -> String:
	return state.encounter.active_scene_id if state != null else ""


func my_tokens() -> Array:
	return state.tokens_owned_by(scene_id(), player_id) if state != null else []


## Ask for an event. Returns "" when it went through, else why not.
func request(_ev: Dictionary) -> String:
	return "no session"


## Ask the table to do a rules thing: {kind: "action", plugin, action,
## ctx} | {kind: "answer", prompt, answer} | {kind: "focus", ref} |
## {kind: "contribute", roll, name, expr}. "" or why not (a refusal from
## the table arrives later through `status`).
func intent(_payload: Dictionary) -> String:
	return "no session"


## My actors in the view (the sheets I may act with).
func my_actors() -> Array:
	var out := []
	for id in view.get("actors", {}):
		if bool(view.actors[id].get("mine", false)):
			out.append(view.actors[id])
	return out


## Called regularly by the UI; transports use it to pump their sockets or
## watch their files.
func poll() -> void:
	pass


func leave() -> void:
	pass


## One line for the status bar: what the turn mode means for this player.
func turn_summary() -> String:
	if state == null:
		return ""
	var turns := state.encounter.turns
	match str(turns.get("mode", "free")):
		"free":
			return "Free movement"
		"dm":
			var mine := []
			for t in my_tokens():
				if (turns.get("active", []) as Array).has(str(t.id)):
					mine.append(str(t.get("name", "")))
			return "You may move: " + ", ".join(PackedStringArray(mine)) if not mine.is_empty() else "Waiting for the DM"
		"ordered":
			if not bool(turns.get("running", false)):
				return "Waiting to begin"
			var cur := state.current_turn_token()
			var tk := state.token(scene_id(), cur)
			if tk.is_empty():
				return "Round %d" % int(turns.get("round", 1))
			if tk.get("owner", null) != null and str(tk.owner) == player_id:
				return "Your turn: %s (round %d)" % [str(tk.get("name", "")), int(turns.get("round", 1))]
			return "%s's turn (round %d)" % [str(tk.get("name", "")), int(turns.get("round", 1))]
	return ""
