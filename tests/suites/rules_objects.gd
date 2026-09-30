extends TestCase
## Objects on the map: a token tagged "object" is a thing, not a creature —
## a spell's light, a floating hand, a torch set down. It shares a space
## with anything, is never a target, gives no cover, takes no turn and sees
## nothing unless given vision; its owner moves it as they move their
## character; it goes when the effect it names goes; and a region may be
## attached to a token and move with it. (The owner: "dancing lights should
## be able to split up the lights, and they should be able to be on the
## same square as a player".)


## The chapel with a kernel: [kernel, scene id]. The hero (pl_1's) at the
## west door (3,7), a goblin inside (9,7), both with actors of the fixture.
func _chapel_kernel() -> Array:
	var m := HexMap.load_file(example("ruined_chapel.hexmap"))
	var st := EncounterState.new(Encounter.create("Objects"))
	st.encounter.doc.rng = {"seed": 7, "index": 0}
	st.encounter.doc.players = [{"id": "pl_1", "name": "Wren", "color": "#4f9cf6"}, {"id": "pl_2", "name": "Tam", "color": "#5bc86a"}]
	st.attach_map(m)
	var k := RulesKernel.new(st)
	var rules := SampleRules.new()
	rules.install(k)
	var sc := Encounter.new_scene(m, "ground", "Ground", "ruined_chapel.hexmap")
	var g := m.grid
	k.commit([{"t": "scene.add", "scene": sc},
		{"t": "actor.add", "actor": {"id": "a_h", "name": "Hero", "owner": "pl_1", "ext": {"sample": {"level": 1, "stats": {"agi": 2, "str": 1, "wit": 0}}}}},
		{"t": "actor.add", "actor": {"id": "a_g", "name": "Goblin", "ext": {"sample": {"level": 1, "stats": {"agi": 1, "str": 0, "wit": 0}}}}},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Hero", g.cell_center(g.offset_to_axial(3, 7)), {"id": "t_h", "actor": "a_h", "owner": "pl_1", "vision": {"radius": 6}})},
		{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Goblin", g.cell_center(g.offset_to_axial(9, 7)), {"id": "t_g", "actor": "a_g"})}], "Setup")
	return [k, str(sc.id), rules]


## A light of the hero's: a Tiny object owned by pl_1, shedding dim light.
func _light(id: String, at: Vector2, extra := {}) -> Dictionary:
	var t := Encounter.new_token("Light", at, {"id": id, "owner": "pl_1", "size": 0.5, "tags": ["object"], "light": {"bright": 0, "dim": 10, "units": "ft", "color": "#ffe7a3"}, "vision": null})
	for key in extra:
		t[key] = extra[key]
	return t


func test_objects_share_spaces_and_move_like_characters() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var g := k.map.grid(sid)
	var hero_at := Vision.token_pos(st.token(sid, "t_h"))
	check(k.commit([{"t": "token.add", "scene": sid, "token": _light("t_l1", g.cell_center(g.offset_to_axial(5, 7)))}], "Lights") == "", "a light put on the map")
	check(Encounter.is_object(st.token(sid, "t_l1")) and not Encounter.is_object(st.token(sid, "t_h")), "tagged object: a thing, not a creature")
	# moved as its owner moves their character: in a fight, on their turn
	st.encounter.doc.turns = {"mode": "ordered", "running": true, "order": ["t_h", "t_g"], "turn": 0, "round": 1, "strategy": "ordered", "active": []}
	var light := st.token(sid, "t_l1")
	check(st.may_move(light, "pl_1"), "on the hero's turn, Wren may move her light")
	check(not st.may_move(light, "pl_2"), "Tam may not: it isn't his")
	st.encounter.doc.turns.turn = 1
	check(not st.may_move(light, "pl_1") and st.refusal({"t": "token.set", "scene": sid, "id": "t_l1", "changes": {"pos": [1, 1]}}, "pl_1").contains("not your turn"), "on the goblin's turn, not: it says whose turn it is")
	st.encounter.doc.turns = {"mode": "dm", "running": false, "order": [], "active": ["t_h"], "turn": 0, "round": 1}
	check(st.may_move(st.token(sid, "t_l1"), "pl_1"), "the DM giving the hero the move gives it to her things too")
	st.encounter.doc.turns = {"mode": "free", "running": false, "order": [], "active": [], "turn": 0, "round": 1}
	# token_moved and after_move fire for it, with no actor
	var seen := []
	k.hooks.on("token_moved", func(p: Dictionary) -> Dictionary:
		seen.append(["moved", p.token, p.actor, p.by])
		return p, "test")
	k.hooks.on("after_move", func(p: Dictionary) -> Dictionary:
		seen.append(["after", p.token, p.actor])
		return p, "test")
	check(k.move_token(sid, "t_l1", hero_at, "pl_1") == "", "Wren moves her light onto her own hero's space")
	check(Vision.token_pos(st.token(sid, "t_l1")) == hero_at and Vision.token_pos(st.token(sid, "t_h")) == hero_at, "both are there")
	check(seen.has(["moved", "t_l1", "", "pl_1"]) and seen.has(["after", "t_l1", ""]), "token_moved and after_move fired for it, with no actor: %s" % [seen])
	# and a creature onto a thing's space
	check(k.commit([{"t": "token.add", "scene": sid, "token": _light("t_l2", g.cell_center(g.offset_to_axial(4, 7)))}], "Another") == "", "a second light, a space east")
	check(k.move_token(sid, "t_h", g.cell_center(g.offset_to_axial(4, 7)), "pl_1") == "" and Vision.token_pos(st.token(sid, "t_h")) == Vision.token_pos(st.token(sid, "t_l2")), "the hero moves onto the other light's space")
	k.hooks.off("test")
	# takes no turn
	check(k.turns.start(sid, "list") == "" and not (st.encounter.turns.order as Array).has("t_l1") and not (st.encounter.turns.order as Array).has("t_l2") and (st.encounter.turns.order as Array).has("t_h"), "the turn order leaves the things out: %s" % [st.encounter.turns.order])
	k.turns.stop()


func test_objects_are_never_targets_nor_cover() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var mq := k.map
	var g := mq.grid(sid)
	# a light between the hero and a creature two spaces west of him, outside the chapel
	var at := func(c: int, r: int) -> Vector2: return g.cell_center(g.offset_to_axial(c, r))
	k.commit([{"t": "actor.add", "actor": {"id": "a_b", "name": "Bandit", "ext": {"sample": {"level": 1, "stats": {"agi": 1, "str": 0, "wit": 0}}}}},
		{"t": "token.add", "scene": sid, "token": Encounter.new_token("Bandit", at.call(1, 7), {"id": "t_b", "actor": "a_b"})},
		{"t": "token.add", "scene": sid, "token": _light("t_l1", at.call(2, 7), {"size": 1})}], "Between")
	var los := mq.line_of_sight(sid, "token:t_h", "token:t_b")
	check(los.clear and los.cover == "none" and not (los.blocked_by as Array).has("t_l1"), "a thing in the way gives no cover: %s" % [los])
	k.commit([{"t": "token.set", "scene": sid, "id": "t_l1", "changes": {"tags": []}}], "A creature now")
	check((mq.line_of_sight(sid, "token:t_h", "token:t_b").blocked_by as Array).has("t_l1"), "(a creature there would)")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_l1", "changes": {"tags": ["object"]}}], "A thing again")
	# never a target: not the Table's pick, not the host's check, not in an area or a reach
	var on_light := Vision.token_pos(st.token(sid, "t_l1"))
	check(MapQuery.pick_target(st, sid, {"kind": "token"}, on_light, true) == null, "a tap on a thing alone picks nothing")
	k.commit([{"t": "token.set", "scene": sid, "id": "t_l1", "changes": {"pos": [Vision.token_pos(st.token(sid, "t_b")).x, Vision.token_pos(st.token(sid, "t_b")).y]}}], "Onto the bandit")
	check(MapQuery.pick_target(st, sid, {"kind": "token"}, Vision.token_pos(st.token(sid, "t_b")), true) == "token:t_b", "on a creature's space, the creature: whatever lies over it")
	var why := PluginHost.check_target(st, sid, "token", "token:t_l1", true)
	check(why.contains("a thing, not a creature"), "a pick of the thing is refused, saying so: %s" % why)
	check(PluginHost.check_target(st, sid, "area", {"at": "token:t_l1", "direction": 0}, false) == "", "an area may start at one (something its caster moves)")
	var ring := mq.template(sid, {"shape": "circle", "at": "token:t_h", "radius": 3})
	check((ring.tokens as Array).has("t_b") and not (ring.tokens as Array).has("t_l1"), "an area's creatures leave it out: %s" % [ring.tokens])
	check((mq.template(sid, {"shape": "circle", "at": "token:t_h", "radius": 3, "objects": true}).tokens as Array).has("t_l1"), "unless asked for (objects: true)")
	check(mq.within(sid, "token:t_h", 3).has("t_b") and not mq.within(sid, "token:t_h", 3).has("t_l1"), "nor in a reach")


func test_objects_see_nothing_unless_given_vision() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var g := k.map.grid(sid)
	k.commit([{"t": "token.add", "scene": sid, "token": _light("t_l1", g.cell_center(g.offset_to_axial(6, 3)))},
		{"t": "token.add", "scene": sid, "token": _light("t_eye", g.cell_center(g.offset_to_axial(8, 3)), {"vision": {"radius": 1, "dark_radius": 30, "units": "ft"}, "light": null, "name": "Arcane Eye"})}], "Things")
	var light := st.token(sid, "t_l1")
	check(float(light.vision.radius) == 0.0 and not bool(Vision.eyes(light, g).sees), "a thing given no vision sees nothing")
	check((Vision.of(st, sid, [light]).cells as Array).is_empty(), "nothing at all")
	check(not (Vision.of(st, sid, [st.token(sid, "t_eye")]).cells as Array).is_empty(), "one given vision (an Arcane Eye) sees")
	var cmds := EncounterCommands.new(st, k.log)
	cmds.kernel = k
	check(cmds.move_token(sid, "t_eye", g.cell_center(g.offset_to_axial(8, 5))) == "", "the eye moved")


## A web player's screen: her own things wherever they are, drawn with their
## light; another player's only in her sight; and what her eye sees she sees.
func test_objects_on_the_web_screens() -> void:
	var st := EncounterState.new(Encounter.load_file(example("chapel_ambush.encounter")))
	st.resolve_maps()
	var sid := st.encounter.active_scene_id
	var ana := "pl_fe0170c1"
	var ben := "pl_393eb25a"
	var far := Vector2(40.5, 40.5)
	st.apply({"t": "token.add", "scene": sid, "token": Encounter.new_token("Light", far, {"id": "t_ana_light", "owner": ana, "size": 0.5, "tags": ["object"], "light": {"dim": 10, "units": "ft", "color": "#ffe7a3"}})})
	var ids := func(pid: String) -> Array: return (WebScene.build(st, sid, pid, false).tokens as Array).map(func(t: Dictionary) -> String: return str(t.id))
	check((ids.call(ana) as Array).has("t_ana_light"), "Ana's light, far out of her sight, is on her map: hers")
	check(not (ids.call(ben) as Array).has("t_ana_light"), "not on Ben's: a thing isn't the party, and he can't see it there")
	var mine: Dictionary = (WebScene.build(st, sid, ana, false).tokens as Array).filter(func(t: Dictionary) -> bool: return str(t.id) == "t_ana_light")[0]
	check(mine.get("light") is Dictionary and str(mine.light.color) == "#ffe7a3" and (mine.tags as Array).has("object"), "sent with its light, to be drawn glowing: %s" % [mine])
	var ben_at := Vision.token_pos(st.token(sid, "t_01365979"))
	st.apply({"t": "token.set", "scene": sid, "id": "t_ana_light", "changes": {"pos": [ben_at.x + 1.0, ben_at.y]}})
	check((ids.call(ben) as Array).has("t_ana_light"), "beside Ben's ranger, he sees it")
	# her things see nothing (her sight is her fighter's alone), unless one has eyes
	var before := (WebScene.build(st, sid, ana, false).visible as Array).size()
	st.apply({"t": "token.set", "scene": sid, "id": "t_ana_light", "changes": {"pos": [far.x, far.y]}})
	check((WebScene.build(st, sid, ana, false).visible as Array).size() == before, "a light of hers sees nothing for her")
	st.apply({"t": "token.set", "scene": sid, "id": "t_ana_light", "changes": {"vision": {"radius": 1}}})
	check((WebScene.build(st, sid, ana, false).visible as Array).size() > before, "given vision (an eye), she sees through it as through her own token")
	# a thing only its owner sees (an unseen servant): beside Ben, still not his to see
	st.apply({"t": "token.add", "scene": sid, "token": Encounter.new_token("Unseen Servant", ben_at + Vector2(1, 0), {"id": "t_servant", "owner": ana, "tags": ["object"], "audience": "owner"})})
	check((ids.call(ana) as Array).has("t_servant") and not (ids.call(ben) as Array).has("t_servant"), "an owner-only thing: on Ana's map, never on Ben's though it stands beside him")
	check((WebScene.build(st, sid, "", true).tokens as Array).any(func(t: Dictionary) -> bool: return str(t.id) == "t_servant"), "the DM sees it")
	check(str(WebScene.unseen(st, sid, ben).get("t_servant", "")) == "hidden", "and the DM's See as says Ben can't: hidden")


func test_things_go_with_their_effect() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var g := k.map.grid(sid)
	var at := g.cell_center(g.offset_to_axial(5, 7))
	# the hero's spell: its effect, and linked to it the lights and the area under one
	check(k.commit([{"t": "effect.apply", "effect": {"id": "e_conc", "on": "actor:a_h", "key": "concentrating", "changes": [], "duration": {"kind": "until_cleared"}}},
		{"t": "effect.apply", "effect": {"id": "e_lights", "on": "actor:a_h", "key": "dancing-lights", "changes": [], "duration": {"kind": "linked", "to": "e_conc"}}},
		{"t": "effect.apply", "effect": {"id": "e_other", "on": "actor:a_h", "key": "mage-hand", "changes": [], "duration": {"kind": "rounds", "rounds": 1}}}], "Spells") == "", "the spells' effects")
	check(k.commit([{"t": "token.add", "scene": sid, "token": _light("t_l1", at, {"effect": "e_lights"})},
		{"t": "token.add", "scene": sid, "token": _light("t_l2", at + Vector2(1, 0), {"effect": "e_lights"})},
		{"t": "token.add", "scene": sid, "token": _light("t_hand", at + Vector2(2, 0), {"effect": "e_other", "light": null})},
		{"t": "region.add", "scene": sid, "region": MapQuery.region("r_glow", [HexMap.cell_key(g.world_to_axial(at))], ["lit"], {"effect": "e_lights"})}], "Things") == "", "two lights, a hand and a region, each naming its effect")
	var depth := k.log.undo_depth()
	# concentration broken: the spell's effect goes (linked), and its things with it, in the same step
	check(k.commit(Effects.remove(st, "e_conc"), "Concentration broken") == "", "concentration broken")
	check(st.token(sid, "t_l1").is_empty() and st.token(sid, "t_l2").is_empty() and not st.encounter.scene(sid).regions.has("r_glow"), "the lights and their area are gone")
	check(not st.token(sid, "t_hand").is_empty(), "the other spell's hand stays")
	check(k.log.undo_depth() == depth + 1, "one step")
	k.log.undo()
	check(not st.token(sid, "t_l1").is_empty() and not st.token(sid, "t_l2").is_empty() and st.encounter.scene(sid).regions.has("r_glow") and st.encounter.effects.has("e_lights"), "undone: all of it back")
	# expired: the round ends the hand's spell, and the hand
	check(k.commit(k.expire({"kind": "round"}), "Round") == "" and st.token(sid, "t_hand").is_empty() and not st.encounter.effects.has("e_other"), "an effect that expires takes its thing")
	# the Table's own hand (the DM clears an effect): the same
	var cmds := EncounterCommands.new(st, k.log)
	cmds.kernel = k
	check(cmds.run({"t": "effect.remove", "id": "e_lights"}, "Clear") == "" and st.token(sid, "t_l1").is_empty() and not st.encounter.scene(sid).regions.has("r_glow"), "an effect cleared by hand takes its things too")
	k.log.undo()
	check(not st.token(sid, "t_l1").is_empty() and st.encounter.effects.has("e_lights"), "(undone as one)")
	# a ruleset tidying its own things in the same batch: nothing twice, nothing refused
	check(k.commit([{"t": "token.remove", "scene": sid, "id": "t_l1"}, {"t": "effect.remove", "id": "e_lights"}], "Ended by hand") == "", "a batch that takes a thing off itself is not refused")
	check(st.token(sid, "t_l2").is_empty() and not st.encounter.scene(sid).regions.has("r_glow"), "and the rest go with the effect")
	# a log replayed from the start reproduces all of it
	var fresh := EncounterState.new(Encounter.create("Replay"))
	fresh.attach_map(st.map_for(sid))
	var ids := func(s: EncounterState) -> Array: return s.tokens(sid).map(func(t: Dictionary) -> String: return str(t.id))
	check(EventLog.replay(fresh, k.log.entries) == "" and ids.call(fresh) == ids.call(st) and ids.call(st) == ["t_h", "t_g"], "replayed from the log, the same: %s" % [ids.call(fresh)])


func test_regions_attached_to_tokens_move_with_them() -> void:
	var parts := _chapel_kernel()
	var k: RulesKernel = parts[0]
	var sid: String = parts[1]
	var st := k.state
	var mq := k.map
	var g := mq.grid(sid)
	var cell := func(c: int, r: int) -> Vector2: return g.cell_center(g.offset_to_axial(c, r))
	# an emanation round the hero (its area kept as a template), and a mark under him (cells alone)
	var aura := mq.template(sid, {"shape": "circle", "at": "token:t_h", "radius": 2})
	var under := [HexMap.cell_key(g.world_to_axial(Vision.token_pos(st.token(sid, "t_h"))))]
	check(k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_aura", aura.cells, ["emanation"], {"attached_to": "t_h", "area": {"shape": "circle", "radius": 2}})},
		{"t": "region.add", "scene": sid, "region": MapQuery.region("r_mark", under, ["mark"], {"attached_to": "t_h"})},
		{"t": "region.add", "scene": sid, "region": MapQuery.region("r_still", [HexMap.cell_key(g.offset_to_axial(5, 7))], ["pool"])}], "Regions") == "", "regions attached to the hero")
	var seen := []
	k.hooks.on("region_left", func(p: Dictionary) -> Dictionary: seen.append(["left", p.region]); return p, "test")
	k.hooks.on("region_entered", func(p: Dictionary) -> Dictionary: seen.append(["entered", p.region]); return p, "test")
	var depth := k.log.undo_depth()
	check(k.move_token(sid, "t_h", cell.call(5, 7), "pl_1") == "", "the hero moves two spaces east, into a pool")
	var regions: Dictionary = st.encounter.scene(sid).regions
	var want: Array = mq.template(sid, {"shape": "circle", "at": "token:t_h", "radius": 2}).cells
	var got: Array = regions.r_aura.cells.duplicate()
	got.sort()
	want.sort()
	check(got == want, "the emanation lies round him where he stands now (%d cells)" % got.size())
	check(regions.r_mark.cells == [HexMap.cell_key(g.offset_to_axial(5, 7))], "the mark under him, moved as far as he moved: %s" % [regions.r_mark.cells])
	check(seen == [["entered", "r_still"]], "he entered the pool, and neither left nor entered his own areas: %s" % [seen])
	check(k.log.undo_depth() == depth + 1, "one step, the regions with the move")
	k.log.undo()
	check(st.encounter.scene(sid).regions.r_mark.cells == under and Vision.token_pos(st.token(sid, "t_h")) == cell.call(3, 7), "undone: back where they were")
	k.hooks.off("test")
	# an area laid round a token's middle (size 0), as round a point
	k.commit([{"t": "region.add", "scene": sid, "region": MapQuery.region("r_point", [], ["point"], {"attached_to": "t_h", "area": {"shape": "circle", "radius": 1, "size": 0}})}], "Round the middle")
	check(k.move_token(sid, "t_h", cell.call(4, 7), "pl_1") == "", "the hero steps east")
	var mid: Array = st.encounter.scene(sid).regions.r_point.cells.duplicate()
	mid.sort()
	var round_point: Array = mq.template(sid, {"shape": "circle", "at": cell.call(4, 7), "radius": 1}).cells
	round_point.sort()
	check(mid == round_point and mid.size() == 7, "its area (size 0) round his middle, as round a point: %d cells" % mid.size())
	k.log.undo()
	k.log.undo()
	# a region on a thing: a beam's area moves with the beam; a torch carried takes its light's area along
	check(k.commit([{"t": "token.add", "scene": sid, "token": _light("t_beam", cell.call(8, 3), {"size": 1, "owner": "pl_1"})},
		{"t": "region.add", "scene": sid, "region": MapQuery.region("r_beam", mq.template(sid, {"shape": "circle", "at": "token:t_beam", "radius": 1, "include_self": true}).cells, ["moonlight"], {"attached_to": "t_beam", "area": {"shape": "circle", "radius": 1}})},
		{"t": "token.add", "scene": sid, "token": _light("t_torch", cell.call(3, 7), {"attached_to": "t_h"})},
		{"t": "region.add", "scene": sid, "region": MapQuery.region("r_torch", [HexMap.cell_key(g.offset_to_axial(3, 7))], ["lit"], {"attached_to": "t_torch"})}], "Things") == "", "a beam with its area, and a torch the hero carries with its own")
	check(k.move_token(sid, "t_beam", cell.call(8, 5), "pl_1") == "", "the beam moved two spaces")
	var beam: Array = st.encounter.scene(sid).regions.r_beam.cells.duplicate()
	beam.sort()
	var round_beam: Array = mq.template(sid, {"shape": "circle", "at": "token:t_beam", "radius": 1, "include_self": true}).cells
	round_beam.sort()
	check(beam == round_beam and beam.has(HexMap.cell_key(g.offset_to_axial(8, 5))), "its area with it")
	check(k.move_token(sid, "t_h", cell.call(4, 7), "pl_1") == "" and Vision.token_pos(st.token(sid, "t_torch")) == cell.call(4, 7), "the hero moves, the torch he carries with him")
	check(st.encounter.scene(sid).regions.r_torch.cells == [HexMap.cell_key(g.offset_to_axial(4, 7))], "and the torch's area with the torch")
	# the players' screens see where it is now
	var snap := WebScene.build(st, sid, "pl_1", false)
	check((snap.regions.r_beam.cells as Array).has(HexMap.cell_key(g.offset_to_axial(8, 5))), "a player's screen has the beam's area where it went")
	# hm.map.move (a ruleset's own moves: a cloud's drift) brings the region too
	var mv := mq.move(sid, "t_beam", cell.call(8, 7))
	check((mv.events as Array).any(func(e: Dictionary) -> bool: return str(e.t) == "region.set" and str(e.id) == "r_beam"), "a ruleset's move's events carry the area along")
