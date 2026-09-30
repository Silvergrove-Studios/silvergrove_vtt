extends TestCase
## Creatures a spell makes (the owner: "things with hit points, familiars
## and summons and the like need to become full tokens with accessible stat
## blocks also controlled by the casting player or the DM"): an actor that
## names an effect goes with it, with everything of its own; a token whose
## sight is its own, not its player's view, until they look through it; a
## thing with statistics (an object that has an actor) is a target; and a
## token that takes its turns with another's, or right after it.


func _state() -> EncounterState:
	var st := EncounterState.new(Encounter.create("Summons"))
	st.encounter.doc.rng = {"seed": 7, "index": 0}
	st.encounter.doc.players = [{"id": "pl_1", "name": "Wren", "color": "#4f9cf6"}, {"id": "pl_2", "name": "Tam", "color": "#5bc86a"}]
	return st


func _scene() -> Dictionary:
	return {"id": "s_1", "name": "G", "map": "", "map_path": "", "level": "ground", "overrides": {}, "fog": {"enabled": false, "explored": []}, "tokens": []}


func _actor(id: String, name: String, owner := "", agi := 1, extra := {}) -> Dictionary:
	var a := {"id": id, "name": name, "owner": owner, "kind": "npc" if owner == "" else "pc", "ext": {"sample": {"level": 1, "stats": {"agi": agi, "str": 0, "wit": 0}}}}
	for k in extra:
		a[k] = extra[k]
	return a


## A kernel with the sample rules and an initiative strategy, a scene, and
## the hero (pl_1's, agility 3) and a goblin (agility 1) on it: [kernel].
func _kernel() -> RulesKernel:
	var k := RulesKernel.new(_state())
	SampleRules.new().install(k)
	k.turns.register("sample", {"shape": "ordered", "name": "Sample initiative", "initiative": "initiative", "tie_break": "highest", "budgets": {"actions": 1, "bonus": 1}})
	check(k.commit([{"t": "scene.add", "scene": _scene()},
		{"t": "actor.add", "actor": _actor("a_h", "Hero", "pl_1", 3)},
		{"t": "actor.add", "actor": _actor("a_g", "Goblin", "", 1)},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Hero", Vector2(1, 1), {"id": "t_h", "actor": "a_h", "owner": "pl_1"})},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Goblin", Vector2(6, 1), {"id": "t_g", "actor": "a_g"})}], "Setup") == "", "set up")
	return k


# ------------------------------------------------------- with the effect --

func test_a_creature_goes_with_the_effect_it_names() -> void:
	var k := _kernel()
	var st := k.state
	# the hero's spell (its effect on the hero), and the owl it made: an actor naming the effect,
	# with a token, a pool, an effect on it, a spell of its own (a thing naming it, and an
	# effect on the goblin lasting as long as its concentration)
	check(k.commit([{"t": "effect.apply", "effect": {"id": "e_fam", "on": "actor:a_h", "key": "familiar", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "actor.add", "actor": _actor("a_owl", "Owl", "pl_1", 2, {"kind": "companion", "effect": "e_fam"})},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Owl", Vector2(2, 1), {"id": "t_owl", "actor": "a_owl"})},
		{"t": "resource.set", "ref": "actor:a_owl", "plugin": "sample", "name": "hp", "record": {"kind": "pool", "current": 1, "max": 1, "recharge": "rest"}},
		{"t": "effect.apply", "effect": {"id": "e_owl_blessed", "on": "token:t_owl", "key": "blessed", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "effect.apply", "effect": {"id": "e_owl_conc", "on": "actor:a_owl", "key": "concentrating", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "effect.apply", "effect": {"id": "e_gob_held", "on": "actor:a_g", "key": "held", "changes": [], "duration": {"kind": "linked", "to": "e_owl_conc"}}},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Mote", Vector2(3, 1), {"id": "t_mote", "tags": ["object"], "effect": "e_owl_conc"})},
		{"t": "actor.add", "actor": _actor("a_stays", "Pony", "pl_1", 1)},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Pony", Vector2(4, 1), {"id": "t_pony", "actor": "a_stays"})}], "The familiar") == "", "an owl that names the hero's spell, with a pool, effects, a spell of its own")
	check(st.actors_with_effect("e_fam") == ["a_owl"], "the actors that name it: %s" % [st.actors_with_effect("e_fam")])
	check(k.turns.start("s_1", "sample") == "", "a fight")
	check((st.encounter.turns.order as Array).has("t_owl"), "the owl has a turn")
	var depth := k.log.undo_depth()
	# the spell ends: the owl goes, and everything of its own
	check(k.commit(Effects.remove(st, "e_fam"), "Dismissed") == "", "the hero's spell ends")
	check(st.encounter.actor("a_owl").is_empty() and st.find_token("t_owl").is_empty(), "the owl and its token are gone")
	check(not st.encounter.resources.has("actor:a_owl"), "its pool too")
	check(not st.encounter.effects.has("e_owl_blessed") and not st.encounter.effects.has("e_owl_conc"), "the effects on it and its token")
	check(not st.encounter.effects.has("e_gob_held"), "an effect elsewhere that lasted as long as its concentration")
	check(st.find_token("t_mote").is_empty(), "the thing its own spell put on the map")
	check(not (st.encounter.turns.order as Array).has("t_owl") and (st.encounter.turns.order as Array).size() == 3, "its place in the order: %s" % [st.encounter.turns.order])
	check(not st.encounter.actor("a_stays").is_empty() and not st.find_token("t_pony").is_empty(), "a creature that names no effect stays")
	check(k.log.undo_depth() == depth + 1, "one step")
	k.log.undo()
	check(not st.encounter.actor("a_owl").is_empty() and not st.find_token("t_owl").is_empty() and st.encounter.effects.has("e_gob_held") and not st.find_token("t_mote").is_empty() and st.encounter.resources.has("actor:a_owl"), "undone: all of it back")
	# a ruleset taking the token off itself in the same batch: nothing twice, nothing refused
	var batch := [{"t": "effect.remove", "id": "e_owl_blessed"}, {"t": "token.remove", "scene": "s_1", "id": "t_owl"}]
	batch.append_array(Effects.remove(st, "e_fam"))
	check(k.commit(batch, "By hand") == "", "a batch that takes its token and an effect of its off itself is not refused")
	check(st.encounter.actor("a_owl").is_empty() and not st.encounter.effects.has("e_gob_held"), "and the rest goes")
	k.log.undo()
	# the effect expires (a timed spell): the same
	k.commit([{"t": "effect.set", "id": "e_fam", "changes": {"duration": {"kind": "rounds", "rounds": 1}}}], "A minute")
	check(k.commit(k.expire({"kind": "round"}), "Round") == "" and st.encounter.actor("a_owl").is_empty(), "an effect that runs out takes its creature")
	k.log.undo()
	# the caster taken off the table: its effects go, and the owl with them
	check(k.commit(st.encounter.removal_events(["a_h"]), "Retire the hero") == "" and st.encounter.actor("a_owl").is_empty() and st.find_token("t_owl").is_empty(), "the caster retired: the owl goes too")
	k.log.undo()
	# a summoned creature's summons (a simulacrum's own spell): gone with it
	check(k.commit([{"t": "effect.apply", "effect": {"id": "e_owl_spell", "on": "actor:a_owl", "key": "conjure", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "actor.add", "actor": _actor("a_wolf", "Wolf", "pl_1", 1, {"effect": "e_owl_spell"})},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Wolf", Vector2(5, 3), {"id": "t_wolf", "actor": "a_wolf"})}], "Its own") == "", "the owl's own summons")
	check(k.commit(Effects.remove(st, "e_fam"), "Dismissed") == "" and st.encounter.actor("a_wolf").is_empty() and st.find_token("t_wolf").is_empty(), "its own creature goes with it")
	# a log replayed from the start reproduces all of it
	var fresh := EncounterState.new(Encounter.create("Replay"))
	check(EventLog.replay(fresh, k.log.entries) == "" and fresh.encounter.actors.keys() == st.encounter.actors.keys(), "replayed from the log, the same: %s" % [fresh.encounter.actors.keys()])


# --------------------------------------------------------------- sight --

## A familiar's eyes: its own, not its player's view, until they look
## through them (the SRD 5.2.1's Find Familiar: "as a Bonus Action, you can
## see through the familiar's eyes and hear what it hears until the start of
## your next turn").
func test_a_token_whose_sight_is_its_own() -> void:
	var st := EncounterState.new(Encounter.load_file(example("chapel_ambush.encounter")))
	st.resolve_maps()
	var sid := st.encounter.active_scene_id
	var ana := "pl_fe0170c1"
	st.apply({"t": "fog.set", "scene": sid, "enabled": true})
	var far := Vector2(40.5, 40.5)
	var before := WebScene.build(st, sid, ana, false)
	st.apply({"t": "token.add", "scene": sid, "token": Encounter.new_token("Owl", far, {"id": "t_owl", "owner": ana, "size": 1, "vision": {"radius": 1, "dark_radius": 120, "units": "ft", "shared": false}})})
	check(not Vision.shares(st.token(sid, "t_owl")) and Vision.shares(st.token(sid, "t_01365979")), "Vision.shares: not the owl's, a character's yes")
	var mine := WebScene.build(st, sid, ana, false)
	check((mine.visible as Array).size() == (before.visible as Array).size(), "its sight isn't on Ana's screen")
	check((mine.tokens as Array).any(func(t: Dictionary) -> bool: return str(t.id) == "t_owl"), "though the owl is: hers")
	# the rules still ask what it sees
	var k := RulesKernel.new(st)
	check(bool(Vision.eyes(st.token(sid, "t_owl"), k.map.grid(sid)).sees), "it has eyes of its own for the rules")
	# the fog explored from its moves: nothing
	var cmds := EncounterCommands.new(st, k.log)
	cmds.kernel = k
	var explored := st.explored(sid).size()
	check(cmds.move_token(sid, "t_owl", far + Vector2(1, 0)) == "" and st.explored(sid).size() == explored, "where it goes, the party hasn't explored")
	# she looks through its eyes
	st.apply({"t": "token.set", "scene": sid, "id": "t_owl", "changes": {"vision": {"radius": 1, "dark_radius": 120, "units": "ft", "shared": true}}})
	var through := WebScene.build(st, sid, ana, false)
	check((through.visible as Array).size() > (before.visible as Array).size(), "looking through its eyes, she sees what it sees")
	check((WebScene.build(st, sid, "", true).visible as Array).size() > 0, "the DM's preview has it too")
	st.apply({"t": "token.set", "scene": sid, "id": "t_owl", "changes": {"vision": {"radius": 1, "dark_radius": 120, "units": "ft", "shared": false}}})
	check((WebScene.build(st, sid, ana, false).visible as Array).size() == (before.visible as Array).size(), "and not once she stops")


# ------------------------------------------------ a thing with statistics --

func test_a_thing_with_statistics_is_a_target() -> void:
	var k := _kernel()
	var st := k.state
	# an Arcane Hand: an object (it shares a space, takes no turn) with an actor (AC and hit points)
	check(k.commit([{"t": "actor.add", "actor": _actor("a_hand", "Arcane Hand", "pl_1", 0)},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Arcane Hand", Vector2(4, 3), {"id": "t_hand", "actor": "a_hand", "owner": "pl_1", "size": 2, "tags": ["object"]})},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Light", Vector2(8, 3), {"id": "t_light", "owner": "pl_1", "tags": ["object"]})}], "Things") == "", "a hand with statistics, and a light with none")
	check(Encounter.is_target(st.token("s_1", "t_hand")) and not Encounter.is_target(st.token("s_1", "t_light")) and Encounter.is_target(st.token("s_1", "t_g")), "is_target: the hand yes, the light no, a creature yes")
	check(PluginHost.check_target(st, "s_1", "token", "token:t_hand", false) == "", "a pick of the hand is taken")
	check(PluginHost.check_target(st, "s_1", "token", "token:t_light", false).contains("a thing, not a creature"), "the light's still refused")
	# (a tap on a map: the chapel's)
	var m := HexMap.load_file(example("ruined_chapel.hexmap"))
	st.attach_map(m)
	var sc := Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")
	var at := m.grid.cell_center(m.grid.offset_to_axial(5, 7))
	check(k.commit([{"t": "scene.add", "scene": sc}, {"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Arcane Hand", at, {"id": "t_hand2", "actor": "a_hand", "owner": "pl_1", "tags": ["object"]})}], "A map") == "", "the hand on a map")
	check(MapQuery.pick_target(st, str(sc.id), {"kind": "token"}, at, false) == "token:t_hand2", "a tap on the hand picks it")
	check(not (k.map.template("s_1", {"shape": "circle", "at": Vector2(4, 3), "radius": 2}).tokens as Array).has("t_hand"), "an area's creatures still leave it out (it isn't one)")
	check(k.turns.start("s_1", "sample") == "" and not (st.encounter.turns.order as Array).has("t_hand"), "it takes no turn")


# ------------------------------------------------------------ followers --

func test_tokens_that_take_their_turns_with_another() -> void:
	var k := _kernel()
	var st := k.state
	# an insect right after the hero (the 2024 Giant Insect: "shares your Initiative count, but it
	# takes its turn immediately after yours"), a simulacrum acting on his turn (the 2014 one:
	# "acting on your turn in combat"), and a steed with the goblin's (a controlled mount)
	check(k.commit([{"t": "actor.add", "actor": _actor("a_wasp", "Giant Wasp", "pl_1", 9)},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Giant Wasp", Vector2(2, 2), {"id": "t_wasp", "actor": "a_wasp", "turn_after": "t_h"})},
		{"t": "actor.add", "actor": _actor("a_sim", "Simulacrum", "pl_1", 0)},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Simulacrum", Vector2(2, 3), {"id": "t_sim", "actor": "a_sim", "turn_with": "t_h"})},
		{"t": "actor.add", "actor": _actor("a_wolf", "Wolf", "", 5)},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Wolf", Vector2(7, 2), {"id": "t_wolf", "actor": "a_wolf"})}], "Followers") == "", "a wasp after the hero, a simulacrum with him, a wolf of its own")
	check(k.turns.start("s_1", "sample") == "", "the fight starts")
	var t: Dictionary = st.encounter.turns
	# the wasp's own initiative (agility 9) would have put it first; the wolf's (5) comes before the hero's (3)
	check(t.order == ["t_wolf", "group:with_t_h", "t_wasp", "t_g"], "the order: the simulacrum in the hero's slot, the wasp right after it: %s" % [t.order])
	check(t.data.groups.with_t_h.tokens == ["t_h", "t_sim"] and str(t.data.groups.with_t_h.label) == "Hero and Simulacrum", "the hero's slot a group of the two, named for them: %s" % [t.data.groups])
	check(str(t.data.labels["group:with_t_h"]) != "" and str(t.data.labels.t_wasp) == str(t.data.labels["group:with_t_h"]) and str(t.data.labels.t_wasp) != str(t.data.labels.t_wolf), "the wasp's label is the hero's initiative, as the hero's slot's is: %s" % [t.data.labels])
	check(t.counters.has("token:t_sim") and t.counters.has("token:t_wasp"), "each has its budgets")
	check(k.turns.next() == "" and st.current_turn_tokens() == ["t_h", "t_sim"], "the hero's turn: the simulacrum's too")
	check(st.may_move(st.token("s_1", "t_sim"), "pl_1") or str(st.token("s_1", "t_sim").get("owner", "")) == "", "(its player moves it then)")
	check(k.turns.next() == "" and st.current_turn_tokens() == ["t_wasp"], "then the wasp's own")
	# two more after the hero share one slot right after him
	check(k.commit([{"t": "actor.add", "actor": _actor("a_obj", "Animated Object", "pl_1", 0)},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Animated Object", Vector2(3, 3), {"id": "t_obj", "actor": "a_obj", "turn_after": "t_h"})}], "Another") == "", "an object animated mid-fight")
	check(k.turns.insert("t_obj") == "", "put into the order (no index: where it follows)")
	t = st.encounter.turns
	check(t.order == ["t_wolf", "group:with_t_h", "group:after_t_h", "t_g"] and t.data.groups.after_t_h.tokens == ["t_wasp", "t_obj"], "those after the hero share one slot: %s %s" % [t.order, t.data.groups])
	check(st.current_turn_tokens() == ["t_wasp", "t_obj"] and t.counters.has("token:t_obj"), "the one up stays up, the newcomer among them, with its budgets")
	# a mount the goblin comes to ride: into its slot mid-fight
	k.commit([{"t": "token.set", "scene": "s_1", "id": "t_wolf", "changes": {"turn_with": "t_g"}}], "Mounted")
	check(k.turns.insert("t_wolf") == "", "the wolf into the goblin's slot")
	t = st.encounter.turns
	check(t.order == ["group:with_t_h", "group:after_t_h", "group:with_t_g"] and t.data.groups.with_t_g.tokens == ["t_g", "t_wolf"], "the goblin's slot its group: %s" % [t.order])
	check(st.current_turn_tokens() == ["t_wasp", "t_obj"], "(who was up still is)")
	# the leader gone: its followers keep their turns
	check(k.commit(st.encounter.removal_events(["a_h"]), "The hero falls") == "", "the hero off the table")
	t = st.encounter.turns
	check((t.order as Array).has("group:with_t_h") and t.data.groups.with_t_h.tokens == ["t_sim"], "the simulacrum keeps the slot: %s %s" % [t.order, t.data.groups])
	# a restart with no leader: they are placed by their own initiative
	k.turns.stop()
	check(k.turns.start("s_1", "sample") == "", "a new fight")
	var all := []
	for e in st.encounter.turns.order:
		all.append_array(EncounterState.turn_members(st.encounter.turns, str(e)))
	all.sort()
	check(all == ["t_g", "t_obj", "t_sim", "t_wasp", "t_wolf"], "every one of them in it, in the slots they shared: %s" % [st.encounter.turns.order])
	# a loop (each after the other) leaves them where they stood
	var groups := {}
	var labels := {}
	var order := TurnRunner.place_followers(["t_a", "t_b"], groups, labels, {"t_a": {"turn_after": "t_b"}, "t_b": {"turn_after": "t_a"}})
	check(order == ["t_a", "t_b"], "two that follow each other: as they were: %s" % [order])
