extends TestCase
## The Table window and its tools.


func test_canvas_encounter_view() -> void:
	var ctx := _table_ctx()
	var canvas := ctx.canvas
	var st := ctx.state
	var sid := ctx.scene_id
	check(canvas.map != null and canvas.level().id == "ground" and canvas.gm_view(), "set_scene finds the map and level; GM by default")
	check(canvas.tokens_in_view().size() == 6, "the GM sees every token")
	var ana: Dictionary = st.encounter.players[0]
	canvas.viewpoint = str(ana.id)
	canvas.refresh()
	var seen := canvas.tokens_in_view()
	check(seen.size() == 2, "a player sees the unhidden party, not the hidden goblins (%d)" % seen.size())
	for t in seen:
		check(not bool(t.hidden), "seen tokens are not hidden")
	var g := canvas.map.grid
	var fighter: Dictionary = st.tokens_owned_by(sid, str(ana.id))[0]
	var own_cell := g.world_to_axial(Vision.token_pos(fighter))
	check(canvas.fog_of(own_cell) == 0 and canvas.point_seen(Vision.token_pos(fighter)), "own cell is in sight")
	var far := g.offset_to_axial(20, 14)
	check(canvas.fog_of(far) == 2 and not canvas.point_seen(g.cell_center(far)), "far corner is unseen")
	# The nave is behind a closed door: explored? no; seen? no. Open the door
	# and the fighter at the threshold sees in.
	var inside := g.offset_to_axial(7, 7)
	check(canvas.fog_of(inside) == 2, "the nave is unseen behind the closed door")
	var door := _door_of(ctx)
	st.apply({"t": "element.set", "scene": sid, "ref": "walls:" + door.id, "changes": {"state": "open"}})
	st.apply({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [g.cell_center(g.offset_to_axial(4, 7)).x, g.cell_center(g.offset_to_axial(4, 7)).y]}})
	canvas.refresh()
	check(canvas.fog_of(inside) == 0, "open door: the nave is in sight from the threshold")
	var eff := canvas.level()
	var open := false
	for w in eff.walls:
		if w.id == door.id:
			open = w.state == "open"
	check(open, "the canvas draws the effective (open) door")
	# Explored-but-out-of-sight: move away, the cell dims instead of vanishing.
	st.apply({"t": "fog.reveal", "scene": sid, "cells": [HexMap.cell_key(inside)]})
	st.apply({"t": "token.set", "scene": sid, "id": fighter.id, "changes": {"pos": [1.0, 1.0]}})
	canvas.refresh()
	check(canvas.fog_of(inside) == 1, "explored cell out of sight is dim (1)")
	canvas.viewpoint = ""
	canvas.refresh()
	check(canvas.fog_of(inside) == 0 and canvas.fog_of(far) == 2, "the GM gets clear for explored and a hint for never-seen")
	st.apply({"t": "fog.set", "scene": sid, "enabled": false})
	canvas.viewpoint = str(ana.id)
	canvas.refresh()
	check(canvas.fog_of(far) == 0 and canvas.point_seen(g.cell_center(far)), "fog off: everything is seen")
	check(canvas.tokens_in_view().size() == 2, "fog off still hides hidden tokens from players")
	# A hidden token revealed becomes visible to players; is_shown honours the viewpoint for GM-only props.
	var gob: Dictionary = st.tokens(sid)[2]
	st.apply({"t": "token.set", "scene": sid, "id": gob.id, "changes": {"hidden": false}})
	canvas.refresh()
	check(canvas.tokens_in_view().size() == 3, "revealed goblin now in view")
	canvas.show_hidden = true
	check(not canvas.is_shown("props", {"id": "x", "hidden": true}), "a player never sees GM-only props even with show_hidden")
	canvas.viewpoint = ""
	check(canvas.is_shown("props", {"id": "x", "hidden": true}), "the GM does")
	check(canvas.token_hit(gob, Vision.token_pos(gob) + Vector2(0.3, 0)) and not canvas.token_hit(gob, Vision.token_pos(gob) + Vector2(0.6, 0)), "token_hit within its disc")
	canvas.free()


func test_table_context() -> void:
	var ctx := _table_ctx()
	var sid := ctx.scene_id
	check(sid == ctx.encounter().active_scene_id and ctx.map() != null and ctx.level().id == "ground", "context opens on the active scene with its map")
	var changes := []
	ctx.selection_changed.connect(func() -> void: changes.append("sel"))
	ctx.scene_changed.connect(func() -> void: changes.append("scene"))
	var tk: Dictionary = ctx.state.tokens(sid)[0]
	ctx.select_token(tk.id)
	check(ctx.is_token_selected(tk.id) and ctx.selected_token().id == tk.id and ctx.selected_token_ids() == [tk.id], "select_token")
	ctx.select_element("walls", _door_of(ctx).id)
	check(ctx.selected_token().is_empty() and ctx.selected_element().door == "door", "select_element gives the effective element")
	var other := str(ctx.encounter().scenes[1].id)
	ctx.set_scene(other)
	check(ctx.scene_id == other and ctx.selection.is_empty() and changes.has("scene") and ctx.level().id == "crypt", "set_scene switches level and clears selection")
	ctx.set_scene(sid)
	# Removing a selected token drops it from the selection.
	ctx.select_token(tk.id)
	ctx.commands.remove_tokens(sid, [tk.id])
	check(ctx.selection.is_empty(), "removed token leaves the selection")
	ctx.history.undo()
	# Removing the scene being looked at moves to the active one.
	ctx.set_scene(other)
	ctx.commands.remove_scene(other)
	check(ctx.scene_id == sid, "removing the viewed scene falls back to the active scene")
	ctx.history.undo()
	# new_token from the picks, uniquely named.
	ctx.token_name = "Goblin"
	ctx.token_owner = ""
	var nt := ctx.new_token(Vector2(1, 1))
	check(nt.name == "Goblin 5" and nt.label == "G5" and nt.hidden == ctx.token_hidden and not nt.has("owner"), "new_token numbers a repeated name: %s / %s" % [nt.name, nt.label])
	ctx.token_name = "Ogre"
	ctx.token_owner = str(ctx.encounter().players[1].id)
	nt = ctx.new_token(Vector2(1, 1))
	check(nt.name == "Ogre" and nt.label == "OG" and nt.owner == ctx.token_owner, "first of a name keeps its initials and the owner")
	check(ctx.snapped(Vector2(1.1, 1.1)) == ctx.map().grid.snap_to_center(Vector2(1.1, 1.1)), "snapped to hex centre")
	ctx.snap_tokens = false
	check(ctx.snapped(Vector2(1.1, 1.1)) == Vector2(1.1, 1.1), "snap off")
	ctx.history.clear()
	ctx.canvas.free()


func test_table_tools() -> void:
	var ctx := _table_ctx()
	var sid := ctx.scene_id
	var st := ctx.state
	var g := ctx.map().grid
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var shift := {"shift": true, "ctrl": false, "alt": false}
	var sel := TableTools.make("select", ctx) as TableTools.SelectTool
	var fighter: Dictionary = st.tokens(sid)[0]
	var ranger: Dictionary = st.tokens(sid)[1]
	var fpos := Vision.token_pos(fighter)
	# Click selects; drag moves, snapped; one undo step including the fog reveal.
	check(sel.token_at(fpos).id == fighter.id and sel.token_at(Vector2(0.2, 0.2)).is_empty(), "token_at")
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	check(ctx.is_token_selected(fighter.id), "press selects the token")
	var to := g.cell_center(g.offset_to_axial(4, 8)) + Vector2(0.1, -0.1)
	sel.drag(to, MOUSE_BUTTON_LEFT, mods)
	var steps := ctx.history._undo.size()
	sel.release(to, MOUSE_BUTTON_LEFT, mods)
	var moved := st.token(sid, fighter.id)
	check(Vision.token_pos(moved) == g.cell_center(g.offset_to_axial(4, 8)), "released on a snapped centre: %s" % [moved.pos])
	check(ctx.history._undo.size() == steps + 1 and ctx.history.undo_label().begins_with("Move"), "move is one step")
	ctx.history.undo()
	check(Vision.token_pos(st.token(sid, fighter.id)) == fpos, "undo puts it back")
	# Shift: free placement, and shift-click extends the selection.
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	sel.drag(fpos + Vector2(0.37, 0.0), MOUSE_BUTTON_LEFT, shift)
	sel.release(fpos + Vector2(0.37, 0.0), MOUSE_BUTTON_LEFT, shift)
	check(near(Vision.token_pos(st.token(sid, fighter.id)).x, fpos.x + 0.37, 1e-6), "shift-drag places freely")
	ctx.history.undo()
	sel.press(Vision.token_pos(ranger), MOUSE_BUTTON_LEFT, shift)
	sel.release(Vision.token_pos(ranger), MOUSE_BUTTON_LEFT, shift)
	check(ctx.selected_token_ids().size() == 2, "shift-click adds to the selection")
	# Dragging two moves both.
	var rpos := Vision.token_pos(ranger)
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	sel.drag(fpos + Vector2(2, 0), MOUSE_BUTTON_LEFT, mods)
	sel.release(fpos + Vector2(2, 0), MOUSE_BUTTON_LEFT, mods)
	check(ctx.history.undo_label() == "Move 2 tokens" and Vision.token_pos(st.token(sid, ranger.id)) != rpos, "multi-move is one step and moves both")
	ctx.history.undo()
	# A tiny drag is a click, not a move.
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	sel.drag(fpos + Vector2(0.01, 0.0), MOUSE_BUTTON_LEFT, mods)
	steps = ctx.history._undo.size()
	sel.release(fpos + Vector2(0.01, 0.0), MOUSE_BUTTON_LEFT, mods)
	check(ctx.history._undo.size() == steps, "a jitter is not a move")
	# Box select on empty ground.
	ctx.clear_selection()
	sel.press(fpos + Vector2(-1.5, -1.5), MOUSE_BUTTON_LEFT, mods)
	sel.drag(fpos + Vector2(1.5, 2.0), MOUSE_BUTTON_LEFT, mods)
	sel.release(fpos + Vector2(1.5, 2.0), MOUSE_BUTTON_LEFT, mods)
	check(ctx.selected_token_ids().size() == 2, "box selects both party tokens (%d)" % ctx.selected_token_ids().size())
	# Doors toggle with a click; a locked one refuses and selects itself.
	var door := _door_of(ctx)
	var mid := (Vector2(door.points[0][0], door.points[0][1]) + Vector2(door.points[1][0], door.points[1][1])) / 2.0
	check(sel.door_at(mid).id == door.id and sel.door_at(mid + Vector2(1, 1)).is_empty(), "door_at")
	sel.press(mid, MOUSE_BUTTON_LEFT, mods)
	sel.release(mid, MOUSE_BUTTON_LEFT, mods)
	check(st.effective(sid, "walls", door).state == "open" and ctx.history.undo_label() == "Open door", "click opens the door")
	sel.press(mid, MOUSE_BUTTON_LEFT, mods)
	sel.release(mid, MOUSE_BUTTON_LEFT, mods)
	check(st.effective(sid, "walls", door).state == "closed", "click again closes it")
	ctx.commands.set_door(sid, door.id, "locked")
	steps = ctx.history._undo.size()
	sel.press(mid, MOUSE_BUTTON_LEFT, mods)
	check(ctx.history._undo.size() == steps and ctx.selected_element().state == "locked", "a locked door does not open on click; it gets selected")
	ctx.commands.set_door(sid, door.id, "closed")
	check(door.state == "closed" and ctx.map().to_json() == _chapel().to_json(), "the map is untouched by all that")
	# Lights toggle.
	var light: Dictionary = ctx.map().level_by_id("ground").lights[0]
	var lpos := Vector2(light.pos[0], light.pos[1])
	check(sel.light_at(lpos).id == light.id, "light_at")
	var was := bool(st.effective(sid, "lights", light).get("on", true))
	sel.press(lpos, MOUSE_BUTTON_LEFT, mods)
	check(bool(st.effective(sid, "lights", light).get("on", true)) != was, "click toggles the light")
	# Keys: H hides/reveals, Delete removes.
	ctx.select_token(fighter.id)
	var kh := InputEventKey.new()
	kh.keycode = KEY_H
	kh.pressed = true
	check(sel.key(kh) and st.token(sid, fighter.id).hidden == true, "H hides")
	sel.key(kh)
	check(st.token(sid, fighter.id).hidden == false, "H again reveals")
	var kd := InputEventKey.new()
	kd.keycode = KEY_DELETE
	kd.pressed = true
	check(sel.key(kd) and st.token(sid, fighter.id).is_empty() and ctx.selection.is_empty(), "Delete removes the selected token")
	ctx.history.undo()
	check(not st.token(sid, fighter.id).is_empty(), "undo brings it back")
	# Token tool places from the picks.
	var tt := TableTools.make("token", ctx) as TableTools.TokenTool
	ctx.token_name = "Wolf"
	ctx.token_hidden = false
	var spot := g.cell_center(g.offset_to_axial(8, 8))
	tt.move(spot + Vector2(0.2, 0.1))
	check(tt._at == spot, "ghost snaps to the hex centre")
	check(tt.press(spot + Vector2(0.2, 0.1), MOUSE_BUTTON_LEFT, mods), "token tool press")
	var wolf: Dictionary = st.tokens(sid)[-1]
	check(wolf.name == "Wolf" and Vision.token_pos(wolf) == spot and ctx.is_token_selected(wolf.id), "placed, snapped and selected")
	check(not tt.press(spot, MOUSE_BUTTON_RIGHT, mods), "right button does nothing")
	# Fog tool: a stroke reveals once per cell, one undo step; right button hides.
	var ft := TableTools.make("fog", ctx) as TableTools.FogTool
	ctx.fog_brush = 2
	var far := g.cell_center(g.offset_to_axial(18, 3))
	var before := st.explored(sid).size()
	ft.press(far, MOUSE_BUTTON_LEFT, mods)
	ft.drag(far + Vector2(0.3, 0), MOUSE_BUTTON_LEFT, mods)
	ft.drag(far + Vector2(1.0, 0), MOUSE_BUTTON_LEFT, mods)
	steps = ctx.history._undo.size()
	ft.release(far + Vector2(1.0, 0), MOUSE_BUTTON_LEFT, mods)
	var after := st.explored(sid).size()
	check(after > before + 6 and ctx.history._undo.size() == steps + 1 and ctx.history.undo_label() == "Reveal", "brush stroke revealed %d cells as one step" % (after - before))
	ft.press(far, MOUSE_BUTTON_RIGHT, mods)
	ft.release(far, MOUSE_BUTTON_RIGHT, mods)
	check(st.explored(sid).size() < after and ctx.history.undo_label() == "Hide", "right button hides")
	var kb := InputEventKey.new()
	kb.keycode = KEY_BRACKETLEFT
	kb.pressed = true
	ft.key(kb)
	check(ctx.fog_brush == 1, "[ shrinks the brush")
	# Fog tool on a scene without fog turns it on first.
	var crypt := str(ctx.encounter().scenes[1].id)
	st.apply({"t": "fog.set", "scene": crypt, "enabled": false})
	ctx.set_scene(crypt)
	ctx.canvas.set_scene(st, crypt)
	ft.press(g.cell_center(g.offset_to_axial(11, 8)), MOUSE_BUTTON_LEFT, mods)
	ft.release(g.cell_center(g.offset_to_axial(11, 8)), MOUSE_BUTTON_LEFT, mods)
	check(st.fog_enabled(crypt) and st.explored(crypt).size() == 1, "painting fog turns fog on")
	ctx.history.clear()
	ctx.canvas.free()


func test_table_window() -> void:
	var app := App.new("user://test_prefs_table_win.json")
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	check(win.view != null and win.dock != null and win._panes.size() == 9, "table window builds with nine panes")
	var names := LayoutStore.names(win.dock.layout)
	for n in LayoutStore.TABLE_PANELS:
		check(names.has(n), "table layout holds the %s panel: %s" % [n, names])
	check(win.scene_select.disabled and win.ctx.scene_id == "", "a new encounter has no scene yet")
	win._open_path(_example("chapel_ambush.encounter"))
	var ctx := win.ctx
	check(ctx.encounter().name == "Chapel Ambush" and ctx.state.maps.size() == 1, "opens the example and resolves its map")
	check(win.scene_select.item_count == 2 and win.scene_select.get_item_text(win.scene_select.selected).begins_with("●"), "scene dropdown lists both, active marked")
	check(win.scenes.list.item_count == 2 and win.tokens.tree.get_root().get_child_count() == 6, "scenes and tokens panels filled")
	check(win.turns.list.get_root().get_child_count() == 6 and win.turns.mode() == "ordered" and win.players.list.item_count == 2, "turns and players panels filled")
	check(win.viewpoint_select.item_count == 3, "viewpoints: the DM and two players")
	check(win.view.canvas.map != null and win.view.canvas.scene_id == ctx.scene_id, "the canvas shows the scene")
	check(app.recent().size() == 1, "opening notes the file as recent")
	# See as Ana, then back.
	var ana: Dictionary = ctx.encounter().players[0]
	win._set_viewpoint(str(ana.id))
	check(win.view.canvas.viewpoint == str(ana.id) and win.viewpoint_select.selected == 1, "viewpoint set")
	win._set_viewpoint("")
	# Inspector follows the selection and edits through commands.
	var tk: Dictionary = ctx.state.tokens(ctx.scene_id)[0]
	ctx.select_token(tk.id)
	check(win.inspector._title.text == tk.name and win.inspector._form.control("name") != null, "inspector shows the token")
	win.inspector._on_value("name", "Renamed")
	check(ctx.state.token(ctx.scene_id, tk.id).name == "Renamed" and ctx.history.undo_label() != "", "inspector edit is a command")
	win.inspector._on_value("owner", "(the DM)")
	check(not ctx.state.token(ctx.scene_id, tk.id).has("owner"), "owner (the DM) clears the owner")
	win.inspector._on_value("owner", "Ben")
	check(ctx.state.token(ctx.scene_id, tk.id).owner == ctx.encounter().players[1].id, "owner by name")
	win.inspector._on_value("tags", "prone, marked")
	check(ctx.state.token(ctx.scene_id, tk.id).tags == ["prone", "marked"], "tags parsed")
	var door := _door_of(win.ctx)
	ctx.select_element("walls", door.id)
	check(win.inspector._title.text.begins_with("Door") and win.inspector._form.control("state") != null, "inspector shows a door")
	win.inspector._on_value("state", "locked")
	check(ctx.state.effective(ctx.scene_id, "walls", door).state == "locked", "door state from the inspector")
	check(win.inspector._buttons.get_child_count() == 1, "an overridden element offers 'As drawn'")
	(win.inspector._buttons.get_child(0) as Button).pressed.emit()
	check(ctx.state.override_of(ctx.scene_id, "walls:" + door.id).is_empty(), "'As drawn' resets it")
	# Menus: scene switch, fog toggle, initiative.
	win._on_menu(win.S_FOG)
	check(not ctx.state.fog_enabled(ctx.scene_id), "Scene → Fog toggles")
	win._on_menu(win.S_FOG)
	win._on_menu(win.T_START)
	win._on_menu(win.T_NEXT)
	check(ctx.encounter().turns.running and ctx.encounter().turns.turn == 1, "Turns menu")
	win._on_menu(win.T_DM)
	check(win.turns.mode() == "dm" and win.turns.list.get_root().get_child_count() == 6 and win.turns.list.get_root().get_first_child().get_cell_mode(2) == TreeItem.CELL_MODE_CHECK, "DM-picks mode lists tokens with a tick")
	win._on_menu(win.T_FREE)
	check(win.turns.mode() == "free" and win.turns.list.get_root().get_child_count() == 0 and not win.turns._ordered_row.visible, "free mode has nothing to arrange")
	win._on_menu(win.T_ORDERED)
	win.scene_select.select(1)
	win.scene_select.item_selected.emit(1)
	check(ctx.level().id == "crypt" and win.view.canvas.level().id == "crypt", "scene dropdown switches the canvas")
	win._on_menu(win.M_SELECT_ALL)
	check(ctx.selected_token_ids().size() == 1, "select all tokens on the crypt")
	# Tool switching by key and the token options row.
	var ev := InputEventKey.new()
	ev.keycode = KEY_T
	ev.pressed = true
	win._unhandled_key_input(ev)
	check(win.view.tool is TableTools.TokenTool and win.tool_options.visible, "T picks the token tool and shows its options")
	ev.keycode = KEY_ESCAPE
	win._unhandled_key_input(ev)
	check(win.view.tool is TableTools.SelectTool and not win.tool_options.visible, "Esc back to select")
	# Save to a temp path, reload, same document.
	var path := ProjectSettings.globalize_path("user://test_table_save.encounter")
	win._save_to(path)
	check(FileAccess.file_exists(path) and not ctx.encounter().dirty, "saved")
	var back := Encounter.load_file(path)
	check(back != null and back.scene(ctx.scene_id).tokens.size() == 1, "reloads")
	DirAccess.remove_absolute(path)
	# Adding a scene through the same path the dialog uses.
	var m := _chapel()
	var scene := Encounter.new_scene(m, "ground", "Again", "ruined_chapel.hexmap")
	ctx.state.attach_map(m)
	ctx.commands.add_scene(scene, false)
	ctx.set_scene(str(scene.id))
	check(win.scene_select.item_count == 3 and win.scenes.list.item_count == 3 and win.view.canvas.level().id == "ground", "added scene shows everywhere")
	win.queue_free()
	await tree.process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_prefs_table_win.json"))


func test_canvas_view_touch() -> void:
	var view := CanvasView.new()
	view.size = Vector2(800, 600)
	root.add_child(view)
	var m := HexMap.create("T", HexGrid.new())
	view.canvas.map = m
	view.canvas.packs = PackLibrary.new()
	view.set_zoom(1.0)
	var presses := []
	var handler := RefCounted.new()
	handler.set_meta("x", 1)
	# A handler with only press/release; the view must cope with missing methods.
	var h := TouchProbe.new()
	view.set_handler(h)
	var t1 := InputEventScreenTouch.new()
	t1.index = 0
	t1.pressed = true
	t1.position = Vector2(300, 300)
	view._gui_input(t1)
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.pressed = true
	t2.position = Vector2(500, 300)
	view._gui_input(t2)
	var z0 := view.zoom()
	var d := InputEventScreenDrag.new()
	d.index = 1
	d.position = Vector2(700, 300)
	d.relative = Vector2(200, 0)
	view._gui_input(d)
	check(view.zoom() > z0 * 1.5, "spreading two fingers zooms in (%.2f → %.2f)" % [z0, view.zoom()])
	var cam := view.camera.position
	var d0 := InputEventScreenDrag.new()
	d0.index = 0
	d0.position = Vector2(350, 350)
	d0.relative = Vector2(50, 50)
	var d1 := InputEventScreenDrag.new()
	d1.index = 1
	d1.position = Vector2(750, 350)
	d1.relative = Vector2(50, 50)
	view._gui_input(d0)
	view._gui_input(d1)
	check(view.camera.position != cam, "two fingers moving together pan")
	# A mouse event during a pinch is ignored.
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(400, 300)
	view._gui_input(mb)
	check(h.presses == 0, "mouse ignored while pinching")
	t1.pressed = false
	t2.pressed = false
	view._gui_input(t1)
	view._gui_input(t2)
	view._gui_input(mb)
	check(h.presses == 1, "after the pinch, presses reach the handler")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(400, 300)
	var z1 := view.zoom()
	view._gui_input(wheel)
	check(view.zoom() > z1, "wheel zooms")
	view.queue_free()
	await tree.process_frame


class TouchProbe extends RefCounted:
	var presses := 0
	func press(_p: Vector2, _b: int, _m: Dictionary) -> bool:
		presses += 1
		return true


func test_turn_system_plugin() -> void:
	# A game system registers its own ordering; the encounter stores its
	# state without understanding it, and forgets nothing if it is missing.
	var sys := RollSystem.new()
	TurnSystem.register(sys)
	check(TurnSystem.get_system("roll") == sys and TurnSystem.all_systems().size() == 2 and TurnSystem.all_systems()[0].id == "list", "registered; the list system stays first")
	var parts := _small_encounter()
	var st: EncounterState = parts[0]
	var sid: String = parts[1]
	var c := EncounterCommands.new(st, EventLog.new(st))
	c.start_turns(sid, "roll")
	var turns := st.encounter.turns
	check(turns.system == "roll" and turns.order.size() == 2 and turns.data.has("rolls"), "the plugin ordered the tokens and kept its rolls")
	check(turns.order[0] == parts[3] and turns.order[1] == parts[2], "ordered by the plugin's rule (goblin first)")
	check(sys.label(turns, parts[3]) == "20" and sys.label(turns, parts[2]) == "5", "labels come from the plugin's data")
	c.next_turn()
	check(turns.turn == 1 and turns.data.stepped == 1, "next goes through the plugin")
	var text := st.encounter.to_json()
	TurnSystem.unregister("roll")
	var back := Encounter.from_json(text)
	check(back.turns.system == "roll" and back.turns.data.rolls.size() == 2, "the plugin's state survives without the plugin")
	var st2 := EncounterState.new(back)
	check(EncounterCommands.new(st2, EventLog.new(st2)).next_turn() == "" and back.turns.turn == 0 and back.turns.round == 2, "without the plugin, the list system steps the stored order")
	check(TurnSystem.get_system("roll").label(back.turns, parts[3]) == "20", "labels are data, so a client without the plugin still shows them")
	c.history.clear()


class RollSystem extends TurnSystem:
	func _init() -> void:
		id = "roll"
		name = "Roll test"
	func build_order(state: EncounterState, scene_id: String) -> Dictionary:
		var rolls := {}
		var order := []
		for t in state.tokens(scene_id):
			rolls[str(t.id)] = 20 if str(t.name) == "Goblin" else 5
			order.append(str(t.id))
		order.sort_custom(func(a, b) -> bool: return rolls[a] > rolls[b])
		var labels := {}
		for id in rolls:
			labels[id] = str(rolls[id])
		return {"order": order, "data": {"rolls": rolls, "labels": labels, "stepped": 0}}
	func next(turns: Dictionary) -> Dictionary:
		var ch := super(turns)
		var data: Dictionary = (turns.get("data", {}) as Dictionary).duplicate(true)
		data.stepped = int(data.get("stepped", 0)) + 1
		ch["data"] = data
		return ch
