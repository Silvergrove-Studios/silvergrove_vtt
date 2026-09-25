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


func test_table_on_a_square_map() -> void:
	# The chapel's encounter gains a scene on the cellar (square cells):
	# tokens move and snap to square centres, the fog brush paints blocks,
	# the canvas draws it for the GM and a player.
	var ctx := _table_ctx()
	var st := ctx.state
	var cellar := HexMap.load_file(example("cellar.hexmap"))
	st.attach_map(cellar)
	var sc := Encounter.new_scene(cellar, "ground", "The cellar", "cellar.hexmap")
	check(ctx.commands.add_scene(sc) == "", "a scene on the cellar")
	ctx.set_scene(str(sc.id))
	var sid := ctx.scene_id
	check(sid == str(sc.id) and ctx.map().grid.is_square(), "the Table is on the square scene")
	var g := ctx.map().grid
	var ana: Dictionary = st.encounter.players[0]
	ctx.commands.add_token(sid, Encounter.new_token("Fighter", g.cell_center(Vector2i(7, 3)), {"owner": str(ana.id), "vision": {"radius": 5}}))
	var fighter: Dictionary = st.tokens(sid)[0]
	var fpos := Vision.token_pos(fighter)
	check(fpos == Vector2(7.5, 3.5), "placed at a square centre")
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var sel := TableTools.make("select", ctx) as TableTools.SelectTool
	sel.press(fpos, MOUSE_BUTTON_LEFT, mods)
	var to := Vector2(9.7, 5.2)
	sel.drag(to, MOUSE_BUTTON_LEFT, mods)
	sel.release(to, MOUSE_BUTTON_LEFT, mods)
	check(Vision.token_pos(st.token(sid, fighter.id)) == Vector2(9.5, 5.5), "released on a snapped square centre: %s" % [st.token(sid, fighter.id).pos])
	ctx.history.undo()
	var fog := TableTools.make("fog", ctx) as TableTools.FogTool
	ctx.fog_brush = 2
	fog.press(Vector2(4.5, 4.5), MOUSE_BUTTON_LEFT, mods)
	fog.release(Vector2(4.5, 4.5), MOUSE_BUTTON_LEFT, mods)
	var explored: Array = st.encounter.scene(sid).fog.explored
	check(explored.size() == 9 and explored.has("3,3") and explored.has("5,5"), "a brush of 2 reveals a 3×3 block (%d)" % explored.size())
	ctx.canvas.set_scene(st, sid)
	ctx.canvas.viewpoint = ""
	ctx.canvas.refresh()
	await tree.process_frame
	ctx.canvas.viewpoint = str(ana.id)
	ctx.canvas.refresh()
	await tree.process_frame
	check(ctx.canvas.fog_of(Vector2i(7, 3)) == 0 and ctx.canvas.fog_of(Vector2i(0, 13)) == 2, "the fighter sees its own square; the far corner is unseen")
	ctx.canvas.queue_free()
	await tree.process_frame


func test_table_window() -> void:
	var app := App.new("user://test_prefs_table_win.json")
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	check(win.view != null and win.dock != null and win._panes.size() == LayoutStore.TABLE_PANELS.size(), "table window builds with every pane: %d" % win._panes.size())
	var names := LayoutStore.names(win.dock.layout)
	for n in LayoutStore.TABLE_PANELS:
		check(names.has(n), "table layout holds the %s panel: %s" % [n, names])
	check(win.ctx.scene_id == "" and win.scene_select.item_count == 1 and win.scene_select.get_item_text(0).begins_with("No map yet"), "a new encounter has no map yet, and the drop-down says so")
	check(win.tool_buttons["token"].disabled and win.tool_buttons["fog"].disabled and not win.tool_buttons["select"].disabled, "the map tools wait for a map")
	check(win._menu("Scene").is_item_disabled(win._menu("Scene").get_item_index(win.S_FOG)) and win._menu("Turns").is_item_disabled(win._menu("Turns").get_item_index(win.T_START)), "so do fog and turns")
	check(win.turns._start.disabled, "and the Turns pane's Start")
	var sc := win.shortcut_lines()
	check("\n".join(sc).contains("Look up") and "\n".join(sc).contains("Mark a restore point") and "\n".join(sc).contains("Token"), "the shortcuts list is read from the menus: %d lines" % sc.size())
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
	check(win.view.tool is TableTools.TokenTool and win._opts_panel.visible and win._tools_row.visible, "T picks the token tool and shows the tools and its options, in the world too")
	ev.keycode = KEY_ESCAPE
	win._unhandled_key_input(ev)
	check(win.view.tool is TableTools.SelectTool and not win._opts_panel.visible and (win._tools_row.visible == (win.ctx.mode != "world")), "Esc back to select: in the world the tools go again")
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


## The Table is campaign-first: the picker until a campaign opens, the
## campaign as the live document, edits between sessions saved and
## restored, the session ritual, close back to the picker.
func test_campaign_first() -> void:
	var dir := "user://table_campaign_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var app := App.new("user://test_prefs_table_campaign.json")
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	win.ctx.plugin_dirs = ["res://tests/plugins"]
	check(win._picker != null and win._picker.visible and win.ctx.campaign == null, "the picker shows until a campaign opens")
	# a campaign with a party, made and saved as the New… dialog would
	var c := Campaign.create("Table first")
	c.players.append({"id": "pl_1", "name": "Ana", "color": "#4f9cf6"})
	c.actors["a_h"] = {"id": "a_h", "kind": "pc", "name": "Hero", "owner": "pl_1", "ext": {"sample.ordered": {"level": 2, "stats": {"agi": 2, "str": 1, "wit": 0}}}}
	c.resources["actor:a_h"] = {"sample.ordered": {"hp": Resources.pool(9, 15, "rest")}}
	# the rulesets this campaign plays: only these are loaded, and only their content parsed
	c.plugins.append({"id": "sample.ordered"})
	c.plugins.append({"id": "sample.degrees"})
	check(c.save(dir.path_join("first.campaign")) == OK, "saved")
	win._open_path(dir.path_join("first.campaign"))
	await tree.process_frame
	var ctx := win.ctx
	check(not win._picker.visible and ctx.campaign != null and ctx.campaign.name == "Table first" and ctx.campaign_is_live(), "opened: the picker is gone and the campaign is the live document")
	# the phones' builds carry no Lua runtime: the rules-dependent checks are skipped there
	var rules := ctx.host != null and ctx.host.plugins.has("sample.ordered")
	check(ctx.encounter().actors.has("a_h"), "the hero is in the kernel, no session running")
	if rules:
		check(ctx.encounter().actor("a_h").derived.has("sample.ordered") and int(ctx.encounter().actor("a_h").derived["sample.ordered"].defence.total) == 12, "with a derived sheet")
	check(win.get_window().title.begins_with("Table first"), "the title is the campaign's")
	# the DM fixes the sheet between sessions and saves: the file has it
	check(ctx.kernel.commit([{"t": "actor.set", "id": "a_h", "changes": {"ext/sample.ordered/stats/agi": 3}}], "Fix") == "", "an edit with no session")
	check(ctx.campaign_dirty(), "dirty")
	win._save(false)
	check(not ctx.campaign_dirty(), "saved")
	var back := Campaign.load_file(dir.path_join("first.campaign"))
	check(back.actors.a_h.ext["sample.ordered"].stats.agi == 3 and not (back.doc.runtime as Dictionary).is_empty() and back.runtime_encounter().actors.has("a_h"), "the file keeps the edit and the runtime")
	# the Party pane: the hero, his sheet as the GM sees it, given to a player, a file brought in, retired
	var party := win.party
	check(party.actors() == ["a_h"] and win.npcs.actors().is_empty(), "the party lists the hero; the NPCs pane is empty")
	party.selected = "a_h"
	party._render_sheet()
	await tree.process_frame
	if rules:
		check(_find_label(party._sheet, "Defence") != null and _find_button(party._sheet, "Shove") != null, "the hero's sheet renders in the pane with its numbers and buttons")
	party._set_owner("")
	check(ctx.encounter().actor("a_h").owner == "" and ctx.history.undo_label().begins_with("Give"), "given to the DM, undoably")
	party._set_owner("pl_1")
	check(ctx.encounter().actor("a_h").owner == "pl_1", "and back to Ana")
	var cf := CharacterFile.make({"id": "a_new", "kind": "pc", "name": "Newcomer", "ext": {"sample.ordered": {"level": 1, "stats": {"agi": 1, "str": 1, "wit": 1}}}}, [{"id": "sample.ordered", "version": "0.1.0"}])
	check(CharacterFile.save(cf, dir.path_join("newcomer.character")) == "", "a character file to bring")
	check(party.import_file(dir.path_join("newcomer.character"), "pl_1") == "" and party.actors() == ["a_h", "a_new"], "brought into the party for Ana")
	check(party.import_file(dir.path_join("newcomer.character"), "pl_1") != "", "not twice")
	party.selected = "a_new"
	party._retire()
	check(party.actors() == ["a_h"] and not ctx.encounter().actors.has("a_new"), "retired")
	# the NPCs pane: a stat block from the compendium becomes an actor with no token
	var npcs := win.npcs
	if rules:
		npcs._search.text = "wolf"
		npcs._search_compendium()
		check(npcs._results.item_count >= 1, "the compendium answers the search: %d" % npcs._results.item_count)
		npcs._add_from_compendium(npcs._results.get_item_metadata(0))
		check(npcs.actors().size() == 1 and ctx.encounter().actor(npcs.actors()[0]).kind == "npc" and ctx.encounter().scenes.is_empty(), "a wolf in the roster, no token (no scene)")
		var wolf := str(npcs.actors()[0])
		check(bool(ctx.encounter().actor(wolf).get("persistent", false)), "kept by the campaign, not only by the running state")
		ctx.campaign.capture(ctx.encounter())
		check(ctx.campaign.actors.has(wolf), "so the campaign's own record has it: a copy or a package carries it")
		# looking things up: View → Look up… is the Reference pane's search, over every collection; a sheet's lookup intent opens the card there
		win._on_menu(win.V_LOOKUP)
		await tree.process_frame
		check(win.reference._search.has_focus(), "Look up… goes to the Reference pane's search")
		win.reference._search.text = "goblin skirm"
		win.reference.refresh_list()
		var hit := ""
		var stack: Array = [win.reference._tree.get_root()]
		while not stack.is_empty():
			var it: TreeItem = stack.pop_back()
			for child in it.get_children():
				if child.get_text(0).begins_with("Goblin skirmisher"):
					hit = str(child.get_metadata(0))
				stack.append(child)
		check(hit.begins_with("entry:creatures/"), "a search finds the goblin skirmisher: %s" % [win.reference.rows()])
		win.reference.open(hit)
		await tree.process_frame
		check(_find_label(win.reference, "Level 1 humanoid") != null, "and shows the ruleset's card")
		party._gm_intent({"kind": "lookup", "collection": "creatures", "id": "wolf"})
		await tree.process_frame
		check(win.reference.current == "entry:creatures/wolf" and win.reference._title.text == "Wolf", "a lookup intent from a sheet opens the entry in the Reference pane")
		# with the Reference pane put away, the popup instead
		win.dock.layout.set_tab_hidden("Reference", true)
		party._gm_intent({"kind": "lookup", "collection": "creatures", "id": "wolf"})
		await tree.process_frame
		check(win.lookup.visible and _find_label(win.lookup, "Wolf") != null, "and with no Reference pane, the popup")
		win.lookup.hide()
		win.dock.layout.set_tab_hidden("Reference", false)
	# the Notes pane: a note written ahead, handed out in the session, journaled once
	var notes := win.notes
	notes._title.text = "The stone"
	notes._text.text = "Runes glow faintly."
	notes._audience.select(1)   # everyone
	notes._tags.text = "runes, altar"
	var nid := notes.save()
	check(nid != "" and ctx.campaign.journal.size() == 1 and ctx.campaign.journal[0].tags == ["runes", "altar"] and ctx.campaign.journal[0].audience == "all", "a note saved to the journal ahead of the session")
	check(notes._list.item_count == 1 and str(notes._list.get_item_text(0)).begins_with("[N] The stone"), "listed")
	# the Maps pane: the chapel into the library, a prepared fight over it, launched and returned from
	var mp := win.maps
	check(mp.add_map(_example("ruined_chapel.hexmap")) == "" and ctx.campaign.maps.size() == 1 and ctx.campaign.maps[0].role == "battle", "the chapel is in the library")
	var mid := str(ctx.campaign.maps[0].id)
	var enc := mp.new_encounter("The chapel ambush", mid, "ground")
	check(ctx.campaign.encounter_entry(enc).name == "The chapel ambush" and ctx.campaign.encounter_entry(enc).map == mid, "a prepared encounter over it")
	if rules:
		mp._search.text = "goblin"
		mp._search_compendium()
		check(mp._results.item_count >= 1, "the compendium offers goblins")
		check(mp.add_creature(enc, mp._results.get_item_metadata(0), 2, "9,8", true) == "" and ctx.campaign.encounter_entry(enc).creatures.size() == 1, "two goblins at 9,8, hidden, in the recipe")
	# the party is somewhere first (with no scene at all, the first scene made is the active one)
	check(mp.show_map(mid) == "" and ctx.encounter().active_scene_id != "", "the chapel shown as the party's scene")
	var scenes_before := ctx.encounter().scenes.size()
	var actors_before := ctx.encounter().actors.size()
	# staged: the fight is built where only the Table looks; the players' scene stays
	var players_scene := ctx.encounter().active_scene_id
	check(mp.launch(enc, false) == "", "staged")
	var live: Dictionary = ctx.campaign.encounter_entry(enc).get("live", {})
	check(ctx.encounter().scenes.size() == scenes_before + 1 and ctx.encounter().active_scene_id == players_scene and ctx.scene_id == str(live.get("scene", "")) and bool(live.get("staged", false)),
		"the Table looks at the staged scene; the players' active scene is unchanged")
	mp._show_encounter()
	check(not mp._go.disabled and mp._launch.disabled and mp._stage.disabled, "Go is offered, Launch and Stage are not")
	check(mp.launch(enc) != "", "it cannot be launched twice")
	check(mp.go(enc) == "" and ctx.encounter().active_scene_id == str(live.scene) and ctx.scene_id == str(live.scene) and not bool(ctx.campaign.encounter_entry(enc).live.get("staged", true)), "Go: the players are brought to the fight")
	check(mp.go(enc) != "", "and not twice")
	mp._show_encounter()
	check(mp._go.disabled and not mp._return.disabled, "now only Return")
	if rules:
		check((live.actors as Array).size() == 2 and ctx.encounter().actors.size() == actors_before + 2, "two goblin actors were made")
		var placed := 0
		var cell9 := ctx.state.map_for(ctx.scene_id).grid.cell_center(ctx.state.map_for(ctx.scene_id).grid.offset_to_axial(9, 8))
		for tk in ctx.state.tokens(ctx.scene_id):
			if (live.actors as Array).has(str(tk.get("actor", ""))):
				placed += 1
				check(bool(tk.get("hidden", false)) and Vision.token_pos(tk).distance_to(cell9) < 2.5, "a goblin token, hidden, at or beside 9,8 (%s)" % [tk.pos])
		check(placed == 2, "both placed on the scene")
	check(ctx.campaign.encounter_entry(enc).played == [0], "played this (zeroth) session")
	check(mp.return_from(enc) == "", "returned")
	check(ctx.encounter().scenes.size() == scenes_before and ctx.encounter().actors.size() == actors_before and not ctx.campaign.encounter_entry(enc).has("live"), "the goblins and the scene are gone; the party stays")
	check(mp.show_map(mid) == "" and ctx.encounter().scenes.size() == 1, "Show makes a scene over a library map")
	# a regional map: the forest road, with a place that launches the chapel fight and the party marker
	check(mp.add_map(_example("forest_road.hexmap"), "regional") == "", "the forest road as a regional map")
	var rid := str(ctx.campaign.maps[1].id)
	check(mp.show_map(rid) == "" and str(ctx.scene().get("map", "")) == rid and not ctx.scene().fog.enabled, "shown, no fog on a regional map")
	await tree.process_frame
	check(mp._places_box.visible, "the places section shows on a regional map")
	check(mp.add_place("Chapel ruins", "encounter", enc, Vector2i(6, 4)) == "", "a place linking to the prepared encounter")
	var place: Dictionary = ctx.campaign.places[0]
	var ptk := ctx.state.token(ctx.scene_id, str(place.id))
	check(not ptk.is_empty() and bool(ptk.hidden) and (ptk.tags as Array).has("place") and place.map == rid and place.cell == "6,4", "a hidden marker token on the map, the record with its link")
	check(mp.set_party(Vector2i(3, 4)) == "" and ctx.campaign.doc.party.cell == "3,4" and ctx.state.tokens(ctx.scene_id).any(func(t: Dictionary) -> bool: return (t.tags as Array).has("party")), "the party marker")
	check(mp.set_party(Vector2i(4, 4)) == "" and ctx.campaign.doc.party.cell == "4,4" and ctx.state.tokens(ctx.scene_id).filter(func(t: Dictionary) -> bool: return (t.tags as Array).has("party")).size() == 1, "moved, not doubled")
	var regional_scene := ctx.scene_id
	# the markers are the campaign's: a scene made over the road afresh (a package started, a copy) shows them
	var road_id := str(mp.shown_map_entry().id)
	check(ctx.commands.remove_scene(regional_scene) == "" and mp.show_map(road_id) == "", "the road's scene gone, and shown again")
	var tags := {}
	for tk in ctx.state.tokens(ctx.scene_id):
		for tg in tk.get("tags", []):
			tags[str(tg)] = int(tags.get(str(tg), 0)) + 1
	check(int(tags.get("place", 0)) == 1 and int(tags.get("party", 0)) == 1 and ctx.state.token(ctx.scene_id, str(place.id)).get("hidden", false) == true,
		"its place (hidden) and the party are back where they were: %s" % [tags])
	regional_scene = ctx.scene_id
	check(mp.go_to_place(str(place.id)) == "" and ctx.scene_id != regional_scene and ctx.encounter().scenes.size() == 3, "Go launches the fight from the place")
	check(mp.return_from(enc) == "" and ctx.scene_id == regional_scene, "and Return comes back to the regional map")
	check(mp.remove_place(str(place.id)) == "" and ctx.campaign.places.is_empty() and ctx.state.token(regional_scene, str(place.id)).is_empty(), "the place removed with its marker")
	# a session: start and end from the pane's verbs
	check(ctx.start_session() == "", "started")
	notes.selected = nid
	check(notes.hand_out() == "" and ctx.encounter().log.any(func(x: Dictionary) -> bool: return x.get("kind", "") == "handout" and x.get("id", "") == nid), "handed out: a handout in the log under the note's id")
	check(int(ctx.campaign.journal[0].handed) == 1, "the note remembers the session it was handed out in")
	check(ctx.encounter().clock.session == 1 and ctx.encounter().checkpoints.size() == 1 and ctx.campaign.sessions.size() == 1, "session 1: the checkpoint and the entry")
	ctx.kernel.commit([{"t": "log.add", "entry": {"id": "r_1", "kind": "ruling", "text": "ruled", "audience": "gm"}}], "Ruling")
	var r := ctx.end_session("# recap")
	check(not r.has("error") and ctx.campaign.sessions[0].recap == "# recap" and ctx.campaign.journal.size() == 2 and ctx.campaign.journal[1].session == 1, "ended: the recap and the journal (the handout once, the ruling stamped), saved: %s" % [ctx.campaign.journal.map(func(j: Dictionary) -> String: return str(j.kind))])
	check(win.campaign_panel._campaign.text.contains("between sessions (1 played)"), "the pane says so: %s" % win.campaign_panel._campaign.text)
	check(win.campaign_panel._hosting.text.begins_with("Not hosting") and win.campaign_panel._clock.text.begins_with("Day 1"), "the Session pane shows hosting and the clock")
	win._set_hosting(true)
	check(win.campaign_panel._hosting.text.contains("Address") and win.campaign_panel._hosting.text.contains("Co-GM code"), "hosting: the address and the code, for the phones: %s" % win.campaign_panel._hosting.text.replace("\n", " | "))
	win._set_hosting(false)
	# autosave writes the campaign beside its file
	ctx.kernel.commit([{"t": "actor.set", "id": "a_h", "changes": {"name": "Hero the Bold"}}], "Rename")
	win._autosave_now()
	check(FileAccess.file_exists(dir.path_join("first.campaign.autosave")) and Campaign.load_file(dir.path_join("first.campaign.autosave")).actors.a_h.name == "Hero the Bold", "the autosave is a campaign file with the live state")
	DirAccess.remove_absolute(dir.path_join("first.campaign.autosave"))
	# close: back to the picker (the unsaved rename is discarded on purpose)
	ctx.encounter().dirty = false
	ctx.campaign.dirty = false
	win._close_campaign()
	check(win._picker.visible and ctx.campaign == null, "closed: the picker again")
	# an old encounter imports as a campaign of its own
	win._open_path(_example("chapel_ambush.encounter"))
	check(not win._picker.visible and ctx.campaign != null and ctx.campaign.path == "" and ctx.campaign.name == "Chapel Ambush" and ctx.campaign.players.size() == 2, "an encounter file becomes an unsaved campaign with its players")
	win.queue_free()
	for f in ["first.campaign"]:
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


## World, Fight, Prep (playtest 1: most of a session is talk, exploring and
## looking things up): the campaign opens in the World — the party, the
## map, the reference; a place on the map opens its card; its encounter
## launched is the Fight, and back is the World again.
func test_world_mode() -> void:
	# the three layouts: the World shows the party, the map and the reference; the rest wait
	var world := LayoutStore.table_world_layout()
	var fight := LayoutStore.table_fight_layout()
	var prep := LayoutStore.table_layout()
	for n in LayoutStore.TABLE_PANELS:
		check(LayoutStore.names(world).has(n) and LayoutStore.names(fight).has(n) and LayoutStore.names(prep).has(n), "every layout holds %s" % n)
		check(world.is_tab_hidden(n) != (n in ["Party", "Canvas", "Reference"]), "the World shows %s: %s" % [n, not world.is_tab_hidden(n)])
		check(fight.is_tab_hidden(n) != (n in ["Turns", "Tokens", "Canvas", "Reference", "Rules", "Inspector"]), "a Fight shows %s: %s" % [n, not fight.is_tab_hidden(n)])
		check(not prep.is_tab_hidden(n), "Prep shows %s" % n)
	check(LayoutStore.table_path("world") != LayoutStore.table_path("prep") and LayoutStore.table_path("prep") == LayoutStore.table_path(), "each mode keeps its own arrangement")
	var dir := "user://table_world_test"
	DirAccess.make_dir_recursive_absolute(dir)
	# (the windows of the tests before save their layouts as they leave)
	await tree.process_frame
	for m in LayoutStore.TABLE_MODES:
		DirAccess.remove_absolute(LayoutStore.table_path(m))
	var c := Campaign.create("World test")
	c.players.append({"id": "pl_1", "name": "Ana", "color": "#4f9cf6"})
	c.actors["a_h"] = {"id": "a_h", "kind": "pc", "name": "Hero", "owner": "pl_1", "ext": {"sample.ordered": {"level": 2, "stats": {"agi": 2, "str": 1, "wit": 0}}}}
	c.resources["actor:a_h"] = {"sample.ordered": {"hp": Resources.pool(9, 15, "rest")}}
	c.actors["a_hessa"] = {"id": "a_hessa", "kind": "npc", "name": "Mother Hessa", "persistent": true}
	c.plugins.append({"id": "sample.ordered"})
	c.plugins.append({"id": "sample.degrees"})
	check(c.save(dir.path_join("world.campaign")) == OK, "saved")
	var app := App.new("user://test_prefs_table_world.json")
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	win.ctx.plugin_dirs = ["res://tests/plugins"]
	check(not win._session_bar.visible and not win._tools_row.visible, "the picker alone: no session bar, no tools")
	win._open_path(dir.path_join("world.campaign"))
	await tree.process_frame
	var ctx := win.ctx
	var rules := ctx.host != null and ctx.host.plugins.has("sample.ordered")
	check(ctx.mode == "world" and win.dock.layout == win._layouts.world and win.mode_buttons.world.button_pressed, "a campaign opens in the World")
	check(win._session_bar.visible and not win._tools_row.visible and not win._opts_panel.visible, "the session bar, and no map tools")
	check(win._campaign_label.text == "World test" and win._session_button.text == "Start session 1" and win._session_label.text.begins_with("Day 1") and win._session_label.tooltip_text.begins_with("Between sessions"), "the campaign and its session: %s / %s" % [win._session_label.text, win._session_button.text])
	check(win._banner.visible and win._banner_label.text.begins_with("Put a map on screen") and win._banner_action.visible, "the banner says what is next: %s" % win._banner_label.text)
	# the World's map: the road, a region with places; the chapel, a fight over it
	var mp := win.maps
	check(mp.add_map(_example("forest_road.hexmap"), "regional") == "" and mp.add_map(_example("ruined_chapel.hexmap")) == "", "two maps in the library")
	var road := str(ctx.campaign.maps[0].id)
	var chapel := str(ctx.campaign.maps[1].id)
	check(win.scene_select.item_count == 2 and str(win.scene_select.get_item_metadata(0)) == "map:" + road, "On screen offers the campaign's maps: %d" % win.scene_select.item_count)
	win.scene_select.select(0)
	win.scene_select.item_selected.emit(0)
	check(str(ctx.scene().get("map", "")) == road and ctx.encounter().active_scene_id == ctx.scene_id, "choosing one puts it up, for the players too")
	check(win.scene_select.get_item_text(0).begins_with("●") and str(win.scene_select.get_item_metadata(1)) == "map:" + chapel, "the road is up (●), the chapel still offered")
	check(not win._banner_label.text.begins_with("Put a map"), "the banner moves on: %s" % win._banner_label.text)
	var enc := mp.new_encounter("The chapel ambush", chapel, "ground")
	check(mp.add_place("Thornwick", "place", "", Vector2i(2, 3)) == "" and mp.add_place("Chapel ruins", "encounter", enc, Vector2i(6, 4)) == "", "a village and the chapel on the road")
	var thornwick := str(ctx.campaign.places[0].id)
	var ruins := str(ctx.campaign.places[1].id)
	await tree.process_frame
	# a picture pack the campaign carries (an adventure's pictures of its places and people)
	var pics := dir.path_join("art/test_pics")
	DirAccess.make_dir_recursive_absolute(pics)
	var img := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.5, 0.2))
	img.save_png(pics.path_join("village.png"))
	var pf := FileAccess.open(pics.path_join("pack.json"), FileAccess.WRITE)
	pf.store_string(JsonDoc.stringify({"format": "silvergrove.pack", "version": 1, "id": "test_pics", "name": "Test pictures", "pack_version": "1", "license": "CC0",
		"pictures": [{"id": "village", "name": "The village", "texture": "village.png", "tags": ["place"]}]}))
	pf.close()
	ctx.refresh_art()
	check(ctx.art.picture("test_pics:village").name == "The village" and ctx.art.picture_texture("test_pics:village") != null and Array(ctx.art.picture_packs()) == ["test_pics"], "a pack's pictures: listed, drawn")
	# the Reference pane: the campaign's contents, by kind; places hold their people
	var ref := win.reference
	ref.refresh_list()
	var rows := Array(ref.rows()).map(func(r: String) -> String: return r.strip_edges())
	for want in ["The party", "Hero  · Ana", "People", "Mother Hessa", "Places", "Thornwick", "Chapel ruins", "Pictures", "The village", "Maps"]:
		check(rows.has(want), "the contents list %s: %s" % [want, rows])
	ref._search.text = "hessa"
	ref.refresh_list()
	check(ref.row_for("actor:a_hessa") != null and ref.row_for("place:" + thornwick) == null, "a search finds her, and only what matches")
	ref._search.text = ""
	ref.refresh_list()
	if rules:
		# the rules as a glossary: a collection opens to every entry
		var glossary := ""
		for r in ref.rows():
			if str(r).begins_with("Rules"):
				glossary = str(r)
		check(glossary == "Rules", "the rules are in the contents")
		var coll_row: TreeItem = null
		var stack: Array = [ref._tree.get_root()]
		while not stack.is_empty():
			var it: TreeItem = stack.pop_back()
			for child in it.get_children():
				if child.has_meta("collection") and str(child.get_meta("collection")) == "creatures":
					coll_row = child
				stack.append(child)
		check(coll_row != null and coll_row.get_text(0).begins_with("Creatures"), "each collection a chapter: %s" % (coll_row.get_text(0) if coll_row != null else "none"))
		if coll_row != null:
			coll_row.collapsed = false
			ref._on_collapsed(coll_row)
			check(ref.row_for("entry:creatures/wolf") != null, "opened: every creature, the wolf among them")
	# a place selected on the map opens its card
	ctx.select_token(thornwick)
	check(ref.current == "place:" + thornwick and ref._title.text == "Thornwick", "the village's marker opens its card")
	check(_find_button(ref, "Mark it on their map") != null and ref._card.find_child("ShowPlayers", true, false) != null, "which offers to mark it on the players' map, and to show it to them")
	check((ref._card.find_child("ShownTo", true, false) as Label).text == "Players see it: nothing yet", "nobody has been shown it yet")
	(_find_button(ref, "Mark it on their map") as Button).pressed.emit()
	await tree.process_frame
	check(not bool(ctx.state.token(ctx.scene_id, thornwick).hidden) and _find_button(ref, "Hide it from their map") != null, "marked: the players see it")
	var te := ref._card.find_child("Description", true, false) as TextEdit
	te.text = "Smoke over thatch. The Drowsy Ox is the only inn."
	te.focus_exited.emit()
	check(str(ref.place(thornwick).get("text", "")) == te.text and ctx.campaign.dirty, "its description is kept with the campaign")
	var secret := ref._card.find_child("Notes", true, false) as TextEdit
	secret.text = "The reeve sold the bell."
	secret.focus_exited.emit()
	check(str(ref.place(thornwick).get("notes", "")) == "The reeve sold the bell.", "and the DM's own notes on it, apart")
	# its picture, chosen from the campaign's
	(ref._card.find_child("PictureMenu", true, false) as MenuButton).get_popup().id_pressed.emit(0)
	var chooser: AcceptDialog = null
	for node in ref.get_children():
		if node is AcceptDialog and node.visible:
			chooser = node
	var plist := chooser.find_child("Pictures", true, false) as ItemList if chooser != null else null
	check(plist != null and plist.item_count == 1 and plist.get_item_text(0) == "The village", "the campaign's pictures to choose from")
	if plist != null:
		plist.item_selected.emit(0)
	check(str(ref.place(thornwick).get("image", "")) == "test_pics:village", "the village has its picture")
	await tree.process_frame
	check(ref._card.find_child("Picture", true, false) != null, "on its card")
	# shown to everyone: the picture and the description, on the phones
	check(ref.share_current("all").begins_with("Shown to everyone"), "shown to everyone")
	var shown: Array = ctx.encounter().log.filter(func(x: Dictionary) -> bool: return str(x.get("kind", "")) == "handout" and str(x.get("ref", "")) == "place:" + thornwick)
	check(shown.size() == 1 and str(shown[0].title) == "Thornwick" and str(shown[0].image) == "test_pics:village" and str(shown[0].text).begins_with("Smoke") and str(shown[0].audience) == "all",
		"a handout with the picture and the description, not the DM's notes: %s" % [shown])
	check(not str(shown[0].get("text", "")).contains("bell"), "the DM's notes stay the DM's")
	await tree.process_frame
	check((ref._card.find_child("ShownTo", true, false) as Label).text == "Players see it: everyone", "the card says who has seen it")
	(ref._card.find_child("ShowPlayers", true, false) as MenuButton).get_popup().id_pressed.emit(999)
	check(not ctx.encounter().log.any(func(x: Dictionary) -> bool: return str(x.get("ref", "")) == "place:" + thornwick), "taken back: gone from the phones")
	# to Ana alone
	await tree.process_frame
	check(ref.share_current("players:pl_1") == "Shown to Ana: Thornwick" and Sharing.shown_to(ctx, "place:" + thornwick) == "players:pl_1", "shown to Ana alone")
	check(Views.can_see("players:pl_1", "pl_1", Views.ROLE_PLAYER) and not Views.can_see("players:pl_1", "pl_2", Views.ROLE_PLAYER) and not Views.can_see("players:pl_1", "", Views.ROLE_DISPLAY), "only her phone may see it")
	ref.refresh_list()
	check(Array(ref.rows()).any(func(r: String) -> bool: return r.begins_with("Thornwick  → Ana")), "listed under Shown to the players")
	var hid := str(ctx.encounter().log.filter(func(x: Dictionary) -> bool: return str(x.get("ref", "")) == "place:" + thornwick)[0].id)
	ref.open("handout:" + hid)
	check(_find_button(ref, "Stop showing it") != null and _find_button(ref, "Open what it was shown from") != null, "its card: take it back, or go to the village")
	check(ref.stop_showing(hid) == "Taken back" and Sharing.shown_to(ctx, "place:" + thornwick) == "", "taken back from there too")
	check(ref.share_current("all") != "" and Sharing.share(ctx, "note:x", "Nothing", "", "", "all").begins_with("There is nothing"), "nothing to show is refused")
	# a picture of one's own, from a file: into the campaign's own pack, whose licence is not known
	var own := CampaignPictures.add_file(ctx, ProjectSettings.globalize_path(pics.path_join("village.png")), "My village")
	check(own.has("ref") and ctx.art.picture(str(own.ref)).name == "My village", "a picture from a file: %s" % [own])
	check(not PackLibrary.redistributable(ctx.art.manifest(PackLibrary.split_ref(str(own.get("ref", "x:y")))[0])).ok, "and not passed on in a package until its licence is said")
	# a person: where they are, what the players may know, what the DM knows
	ref.open("actor:a_hessa")
	var where := ref._card.find_child("Where", true, false) as OptionButton
	var at := -1
	for i in where.item_count:
		if str(where.get_item_metadata(i)) == thornwick:
			at = i
	where.select(at)
	where.item_selected.emit(at)
	check(str(ctx.encounter().actor("a_hessa").get("place", "")) == thornwick, "Hessa is in Thornwick")
	await tree.process_frame
	var nte := ref._card.find_child("Notes", true, false) as TextEdit
	nte.text = "Knows the chapel's crypt; wants her son back."
	nte.focus_exited.emit()
	check(str(ctx.encounter().actor("a_hessa").get("notes", "")) == nte.text and ctx.history.undo_label().begins_with("Notes on"), "the DM's notes on her, undoably")
	ref._search.text = "crypt"
	ref.refresh_list()
	check(ref.row_for("actor:a_hessa") != null, "and a search finds her by them")
	ref._search.text = ""
	ref.refresh_list()
	ref.back()
	check(ref.current.begins_with("handout:") or ref.current == "place:" + thornwick, "Back: the card before")
	ref.open("place:" + thornwick)
	await tree.process_frame
	check(_find_button(ref, "Mother Hessa") != null, "with Hessa among the people here")
	check(ref.row_for("place:" + thornwick) != null and ref.row_for("place:" + thornwick).get_children().any(func(row: TreeItem) -> bool: return str(row.get_metadata(0)) == "actor:a_hessa"), "and under the village in the contents")
	# the DM's own folders: made, named, nested; things filed in them; the sections renamed and moved
	var act := ref.new_folder("", "Act 1")
	var village := ref.new_folder("folder:" + act, "The village")
	ref.file("place:" + thornwick, village)
	ref.rename("section:places", "Locations")
	ref.refresh_list()
	var rows2 := Array(ref.rows()).map(func(r: String) -> String: return r.strip_edges())
	check(rows2.has("Act 1") and rows2.has("The village") and rows2.has("Locations") and not rows2.has("Places"), "a folder, a folder in it, and Places renamed Locations: %s" % [rows2])
	check(ref._container_of(ref.row_for("place:" + thornwick)) == "folder:" + village and ref._container_of(ref.row_for("place:" + ruins)) == "section:places", "Thornwick filed in The village; the chapel still in Locations")
	check(ref.folder_path(village) == "Act 1 / The village", "folders have paths")
	check(str(ref.drop_plan(ref.row_for("folder:" + act), 0, "place:" + ruins).get("op", "")) == "file", "a thing dropped on a folder is filed there")
	check(ref.drop_plan(ref.row_for("section:places"), 0, "place:" + thornwick) == {"op": "file", "ref": "place:" + thornwick, "folder": ""}, "and dropped on its own section goes back")
	check(ref.drop_plan(ref.row_for("section:people"), 0, "place:" + ruins).is_empty(), "but a place does not go among the people")
	check(ref.drop_plan(ref.row_for("folder:" + village), 0, "folder:" + act).is_empty(), "nor a folder inside its own")
	check(str(ref.drop_plan(ref.row_for("section:people"), 0, "folder:" + village).get("op", "")) == "nest", "a folder may go in a section")
	ref.apply_drop(ref.drop_plan(ref.row_for("section:maps"), -1, "folder:" + act))
	check(ref.top_order().find("folder:" + act) == ref.top_order().find("section:maps") - 1, "dropped above Maps, Act 1 is just above it: %s" % [ref.top_order()])
	ref.refresh_list()
	ref.apply_drop(ref.drop_plan(ref.row_for("section:party"), -1, "section:places"))
	check(ref.top_order().find("section:places") == ref.top_order().find("section:party") - 1, "and the sections can be put in another order: %s" % [ref.top_order()])
	if rules:
		ref.file("entry:creatures/wolf", act)
		ref.refresh_list()
		check(ref._container_of(ref.row_for("entry:creatures/wolf")) == "folder:" + act, "a rule pinned to a folder, for the table")
		ref.file("entry:creatures/wolf", "")
	# a folder's card renames it; a section's gives back its own name
	ref.open("folder:" + act)
	var rn := ref._card.find_child("Rename", true, false) as LineEdit
	rn.text = "Act One"
	rn.text_submitted.emit(rn.text)
	check(str(ref.folder(act).title) == "Act One", "renamed from its card")
	ref.open("place:" + ruins)
	await tree.process_frame
	var fold := ref._card.find_child("Folder", true, false) as OptionButton
	check(fold != null and fold.get_item_text(0) == "(its own section: Locations)" and fold.item_count == 3, "a thing's card says where it is filed, and offers the folders")
	if fold != null:
		for i in fold.item_count:
			if str(fold.get_item_metadata(i)) == act:
				fold.select(i)
				fold.item_selected.emit(i)
	check(str(ref.layout()["in"].get("place:" + ruins, "")) == act, "filed from its card")
	# deleting a folder: its folder moves up, what was in it goes back
	ref.delete_folder(act)
	check(ref.folder(act).is_empty() and str(ref.folder(village).parent) == "" and not ref.layout()["in"].has("place:" + ruins) and ref.layout()["in"].has("place:" + thornwick), "Act One deleted: The village moves to the top, the chapel goes back to Locations")
	ref.rename("section:places", "")
	check(ref.section_title("places") == "Places" and str(ctx.campaign.doc.contents.folders[0].title) == "The village", "names given back; the arrangement is the campaign's")
	ref.delete_folder(village)
	if rules:
		# the Party pane: the ruleset's party view; a name opens the sheet beside it
		await tree.process_frame
		var hero := _find_button(win.party_pane, "Hero")
		check(hero != null, "the party view shows Hero")
		if hero != null:
			hero.pressed.emit()
			check(ref.current == "actor:a_h" and _find_label(ref, "Defence") != null, "his name opens his sheet in the Reference")
		var who := _find_first(win.party_pane, "OptionButton") as OptionButton
		check(who != null and who.item_count == 2 and who.get_item_text(0) == "Everyone" and who.get_item_text(1) == "Hero", "a form's choices from the data: everyone, or Hero")
		check(GmIntents.run(ctx, {"kind": "show", "actor": "a_hessa"}) == "" and ref.current == "actor:a_hessa", "a show intent by an actor's id")
	# the chapel's card launches the fight: the Fight, then back to the World
	ref.open("place:" + ruins)
	check(_find_button(ref, "Run this encounter") != null, "the chapel's card offers its encounter")
	(_find_button(ref, "Run this encounter") as Button).pressed.emit()
	check(ctx.mode == "fight" and win.dock.layout == win._layouts.fight and win._tools_row.visible, "launched: the Fight, with the map tools")
	check(win._fight_button.visible and win.mode_buttons.fight.text == "Fight ●" and win.mode_buttons.fight.tooltip_text.begins_with("The chapel ambush is running"), "the bar says a fight is on, which, and how to end it")
	check(mp.return_from(enc) == "" and ctx.mode == "world" and str(ctx.scene().get("map", "")) == road and not win._fight_button.visible, "returned: the World and the road again")
	# a tool picked by its key in the World brings its row until Esc
	var ev := InputEventKey.new()
	ev.keycode = KEY_T
	ev.pressed = true
	win._unhandled_key_input(ev)
	check(win._tools_row.visible and win._opts_panel.visible, "T: the token tool and its options, in the World")
	ev.keycode = KEY_ESCAPE
	win._unhandled_key_input(ev)
	check(not win._tools_row.visible and not win._opts_panel.visible, "Esc: gone again")
	# Prep: every pane; the World again
	win.set_mode("prep")
	check(win.dock.layout == win._layouts.prep and win.dock.layout.hidden_tabs.is_empty() and win._tools_row.visible, "Prep: every pane, the tools: %s hidden" % [win.dock.layout.hidden_tabs.keys()])
	win.set_mode("world")
	check(win.dock.layout.is_tab_hidden("Maps"), "the World: the Maps pane put away")
	win._reveal_pane("Maps")
	check(not win.dock.layout.is_tab_hidden("Maps"), "brought out when asked for")
	var leaf := win.dock.layout.get_leaf_for_node(win._panes.filter(func(p: Node) -> bool: return str(p.name) == "Maps")[0])
	var tabs_shown := []
	for n in leaf.names:
		if not win.dock.layout.is_tab_hidden(n):
			tabs_shown.append(n)
	check(tabs_shown[leaf.current_tab] == "Maps", "and it is the tab in front: %s of %s" % [leaf.current_tab, tabs_shown])
	# the session from the bar
	win._toggle_session()
	check(int(ctx.encounter().clock.session) == 1 and win._session_button.text == "End session 1" and win._session_label.tooltip_text == "Session 1 is running", "Start session 1: %s" % win._session_button.text)
	win._banner_hidden = true
	win._update_banner()
	check(not win._banner.visible, "the hints can be put away")
	# a campaign saved mid-fight opens on the fight
	check(mp.launch(enc) == "" and ctx.mode == "fight", "fighting")
	check(ctx.save_campaign() == "", "saved mid-fight")
	win._close_campaign()
	win._open_path(dir.path_join("world.campaign"))
	await tree.process_frame
	check(ctx.mode == "fight" and win._fight_button.visible, "reopened on the fight")
	win.queue_free()
	await tree.process_frame
	PluginHost._rm_rf(dir)
	for m in LayoutStore.TABLE_MODES:
		DirAccess.remove_absolute(LayoutStore.table_path(m))


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


func _find_label(root: Node, text: String) -> Label:
	if root is Label and str((root as Label).text).begins_with(text):
		return root
	for c in root.get_children():
		var l := _find_label(c, text)
		if l != null:
			return l
	return null


func _find_button(root: Node, text: String) -> Button:
	if root is Button and str((root as Button).text).begins_with(text):
		return root
	for c in root.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


## A package is a campaign someone assembled: it stays a template, and
## starting it gives the DM a campaign of their own to play and import
## into. Exporting one from a campaign is how a DM becomes an author.
func test_campaign_packages() -> void:
	var home := "user://test_packages"
	if DirAccess.dir_exists_absolute(home):
		PluginHost._rm_rf(home)
	DirAccess.make_dir_recursive_absolute(home.path_join("source"))
	# a campaign an author put together: a map, a pack of its own, a prepared fight, some play behind it
	var author := Campaign.create("The Sunken Reach")
	author.plugins.append({"id": "sample.degrees", "version": "0.1.0"})
	author.players.append({"id": "pl_a", "name": "Ana", "color": "#4f9cf6"})
	author.actors["a_pc"] = {"id": "a_pc", "kind": "pc", "name": "Ana's ranger", "owner": "pl_a"}
	author.actors["a_npc"] = {"id": "a_npc", "kind": "npc", "name": "The harbourmaster"}
	author.journal.append({"id": "j_1", "kind": "note", "title": "Ana's secret", "text": "…", "session": 1})
	author.journal.append({"id": "j_shown", "kind": "handout", "title": "The harbour", "text": "Gulls.", "audience": "all", "ref": "place:pl_x"})
	author.journal.append({"id": "j_prepared", "kind": "handout", "title": "A letter", "text": "Come quickly.", "audience": "gm"})
	author.doc.player_notes = [{"id": "pn_a", "owner": "pl_a", "title": "My theory", "text": "The harbourmaster did it.", "share": []}]
	author.doc.sessions.append({"n": 1, "recap": "# Session 1"})
	author.doc.runtime = {"scenes": []}
	check(ContentImport.write_pack(home.path_join("source/packs/reach"), {"id": "reach", "name": "Reach content", "plugin": "sample.degrees"},
		{"creatures": [{"id": "reach-eel", "name": "Reach eel", "level": 2, "kind": "animal", "stats": {"might": 1, "agility": 2, "mind": 0}, "ac_base": 12, "hp": 9}]}) == "", "a pack of its own")
	author.packs.append({"id": "reach", "path": "packs/reach", "version": "1"})
	check(author.save(home.path_join("source/reach.campaign")) == OK, "the author's campaign saved")
	# the author adds a map from wherever it was drawn: the campaign takes a copy, and the art it is drawn with
	var app0 := App.new("user://test_prefs_packages_author.json")
	var authoring := TableWindow.new()
	authoring.app = app0
	root.add_child(authoring)
	authoring.ctx.plugin_dirs = ["res://tests/plugins"]
	authoring._open_campaign_path(home.path_join("source/reach.campaign"))
	# the phones' builds ship no art library of their own (a phone is sent the Table's art),
	# so there is nothing for a map to bring along: the art checks are skipped there
	var has_art := Array(app0.packs.pack_ids()).has("woodland") and Array(app0.packs.pack_ids()).has("dungeons_and_castles")
	var said_add := authoring.maps.add_map(_example("ruined_chapel.hexmap"))
	check(FileAccess.get_file_as_bytes(home.path_join("source/maps/ruined_chapel.hexmap")).size() == FileAccess.get_file_as_bytes(_example("ruined_chapel.hexmap")).size(),
		"the copy is whole, even from inside the app's own package (a phone's res://)")
	check(said_add == "", "the chapel added: %s" % said_add)
	var chapel_entry: Dictionary = authoring.ctx.campaign.maps[0] if not authoring.ctx.campaign.maps.is_empty() else {}
	check(str(chapel_entry.get("path", "")) == "maps/ruined_chapel.hexmap" and FileAccess.file_exists(home.path_join("source/maps/ruined_chapel.hexmap")), "copied into the campaign's maps/: %s" % [chapel_entry])
	check(str(chapel_entry.get("source", "")) != "", "remembering where it came from")
	if has_art:
		check(FileAccess.file_exists(home.path_join("source/art/dungeons_and_castles/pack.json")) and FileAccess.file_exists(home.path_join("source/art/woodland/pack.json")), "its art came with it")
	if has_art:
		check(Array(authoring.ctx.art.pack_ids()) == ["dungeons_and_castles", "woodland"], "and is the art this campaign draws with: %s" % [authoring.ctx.art.pack_ids()])
	authoring.ctx.campaign.encounters.append({"id": "enc", "name": "The ambush", "map": str(chapel_entry.get("id", "")), "level": "ground", "creatures": [], "played": [1]})
	for k in ["players", "actors", "journal"]:
		authoring.ctx.campaign.doc[k] = author.doc[k]
	authoring.ctx.campaign.doc.sessions = author.doc.sessions
	check(authoring.ctx.save_campaign(home.path_join("source/reach.campaign")) == "", "saved")
	author = Campaign.load_file(home.path_join("source/reach.campaign"), [])
	root.remove_child(authoring)
	authoring.free()
	# exported as a package: the adventure, not the play
	var pkg := home.path_join("sunken_reach.campaignpkg")
	var ex := CampaignPackage.export_from(author, pkg, {"id": "sunken-reach", "package_version": "1.2.0", "description": "A drowned coast.",
		"plugin_dirs": ["res://tests/plugins"]})
	check(ex.ok and int(ex.files) >= 5, "exported: %d files%s" % [int(ex.files), "" if ex.ok else " — " + str(ex.why)])
	var info := CampaignPackage.read(pkg)
	check(info.ok and info.id == "sunken-reach" and info.name == "The Sunken Reach" and str(info.package_version) == "1.2.0", "the package says what it is: %s" % [info.why])
	check(info.bundles_rules, "it carries the ruleset it plays")
	if has_art:
		check((info.manifest.art as Dictionary).has("woodland") and (info.manifest.art as Dictionary).has("dungeons_and_castles"), "and the art its maps are drawn with, licences listed: %s" % [info.manifest.get("art", {})])
	check(CampaignPackage.unmet(info, {}, App.version()).is_empty(), "so a table that has installed nothing can start it")
	check(str(info.requires.app) == ">=%s" % CampaignPackage._minor_floor(App.version()) and not CampaignPackage.unmet(info, {}, "2.0.0").is_empty(),
		"it asks for the app it was made with, to the minor version (%s): an older one is told" % str(info.requires.app))
	check(CampaignPackage.unmet({"requires": {"app": ">=9.0.0"}}, {}, "2.0.0").size() == 1, "an older app is still told")
	# whole, and what is inside it under which terms, before a DM starts it
	var whole := CampaignPackage.verify(pkg)
	check(whole.ok and int(whole.checked) >= 5 and str(info.manifest.digest).length() == 64, "every file checks out against its SHA-256 (%d files): %s" % [int(whole.checked), str(whole.why)])
	var inside := CampaignPackage.contents(pkg)
	var kinds := {}
	for item in inside:
		kinds[str(item.kind)] = true
	check(kinds.has("campaign") and kinds.has("ruleset") and kinds.has("content") and (kinds.has("art") or not has_art), "the contents name the campaign, its rules, its art and its content: %s" % [kinds.keys()])
	if has_art:
		check(inside.any(func(i: Dictionary) -> bool: return str(i.kind) == "art" and str(i.license).begins_with("MIT")), "with each one's licence")
	var summary := TableWindow.package_summary(pkg, whole)
	check(summary.contains("Rules: ") and (summary.contains("Art: ") or not has_art) and summary.contains("all %d files are as the author made them" % int(whole.checked)), "the DM reads it before starting")
	# a package damaged on the way is not started
	var damaged := home.path_join("damaged.campaignpkg")
	var zr := ZIPReader.new()
	zr.open(pkg)
	var zw := ZIPPacker.new()
	zw.open(damaged)
	for n in zr.get_files():
		if n.ends_with("/"):
			continue
		var bytes := zr.read_file(n)
		if n == "packs/reach/creatures.json":
			bytes = bytes.get_string_from_utf8().replace("Reach eel", "Reach EEL").to_utf8_buffer()
		zw.start_file(n)
		zw.write_file(bytes)
		zw.close_file()
	zw.close()
	zr.close()
	var bad := CampaignPackage.verify(damaged)
	check(not bad.ok and str(bad.why).contains("packs/reach/creatures.json"), "a changed file is caught, by name: %s" % str(bad.why))
	check(not CampaignPackage.instance(damaged, home.path_join("never"), "Never").ok and not DirAccess.dir_exists_absolute(home.path_join("never")), "and it is not started")
	check(CampaignPackage.unmet({"requires": {"plugins": [{"id": "srd5e"}]}}, {}, "2.0.0").size() == 1, "and a package from before, carrying none, says what it wants")
	var no_rules := CampaignPackage.export_from(author, home.path_join("bare.campaignpkg"), {"plugin_dirs": []})
	check(not no_rules.ok and str(no_rules.why).contains("not here to put in the package"), "a ruleset that is not on this machine stops the export: %s" % str(no_rules.why))
	# a DM starts it: their own campaign, the package untouched
	var before := FileAccess.get_file_as_bytes(pkg).size()
	var inst := CampaignPackage.instance(pkg, home.path_join("mine"), "Ana's Reach")
	check(inst.ok, "started: %s" % str(inst.why))
	check(FileAccess.get_file_as_bytes(pkg).size() == before, "the package is untouched")
	var err := []
	var mine := Campaign.load_file(str(inst.path), err)
	check(mine != null and mine.name == "Ana's Reach" and mine.id != author.id, "the copy is the DM's own, with its own id")
	check(str(mine.doc.package.id) == "sunken-reach" and str(mine.doc.package.version) == "1.2.0", "it remembers the package it came from")
	check(mine.doc.runtime.is_empty() and (mine.doc.sessions as Array).is_empty() and int(mine.clock.session) == 0, "with none of the author's play")
	check((mine.doc.players as Array).is_empty() and not mine.actors.has("a_pc") and mine.actors.has("a_npc"), "no other table's party; the NPCs stay")
	var kept_journal: Array = mine.journal.map(func(j: Dictionary) -> String: return str(j.id))
	check(mine.player_notes.is_empty() and not kept_journal.has("j_1") and not kept_journal.has("j_shown") and kept_journal.has("j_prepared"),
		"no player's notes and nothing the author's players were shown or banked; the author's prepared handout stays: %s" % [kept_journal])
	check(mine.encounters.size() == 1 and mine.maps.size() == 1 and mine.packs.size() == 1, "the adventure came whole")
	check((mine.encounters[0].played as Array).is_empty() and not mine.doc.has("source_of"), "none of it marked played by the author's table, and not the author's working copy")
	check(FileAccess.file_exists(home.path_join("mine/maps/ruined_chapel.hexmap")) and FileAccess.file_exists(home.path_join("mine/packs/reach/pack.json")), "its maps and content are in the DM's folder")
	if has_art:
		check(FileAccess.file_exists(home.path_join("mine/art/woodland/pack.json")), "and its art")
	# and it plays: the ruleset loads, the campaign's own pack with it
	var app := App.new("user://test_prefs_packages.json")
	var win := TableWindow.new()
	win.app = app
	root.add_child(win)
	# nothing installed on this table: the campaign runs the ruleset the package brought
	win.ctx.plugin_dirs = []
	check(win.campaign_panel.steps({}).size() == 4, "the Getting started list has its four steps")
	win._open_campaign_path(str(inst.path))
	check(win.ctx.encounter().scenes.size() == 1 and win.ctx.scene_id != "", "a campaign with no scene opens on its map (playtest 1: 'the package had no scenes')")
	var first_steps := win.campaign_panel.steps({})
	check(bool(first_steps[0].done) and not bool(first_steps[3].done), "Getting started: the map step is done, the session is not")
	check(win.campaign_panel._start_box.visible, "and the list shows while steps remain")
	check(not win.tool_buttons["token"].disabled, "the map tools are there once a map is")
	check(FileAccess.file_exists(home.path_join("mine/rules/sample.degrees/manifest.json")), "the ruleset came with it")
	# never started over a campaign already there; the dialog offers a free name
	var again := CampaignPackage.instance(pkg, home.path_join("mine"), "Mine again")
	check(not again.ok and str(again.why).contains("already a campaign") and Campaign.load_file(str(inst.path), err).name == "Ana's Reach", "a package is never started over a campaign: %s" % str(again.why))
	check(TableWindow.free_campaign_name(home, "mine") == "mine 2" and TableWindow.free_campaign_name(home, "nowhere") == "nowhere", "a free name for the next start")
	# the first screen finds the adventures in the library and in Downloads, the newest of each once
	var found := TableWindow.found_packages([home, home.path_join("nowhere"), ""])
	check(found.size() == 1 and str(found[0].id) == "sunken-reach", "found in the folders it looks in: %s" % [found.map(func(f: Dictionary) -> String: return str(f.path).get_file())])
	# the start dialog: the pitch first, the name inline, what is inside folded away
	var dlg := win._package_dialog(pkg, info, whole)
	var pitch := _find_first(dlg, "RichTextLabel") as RichTextLabel
	check(pitch != null and pitch.get_parsed_text().begins_with("The Sunken Reach  1.2.0") and pitch.get_parsed_text().contains("A drowned coast."), "the start dialog leads with the adventure: %s" % (pitch.get_parsed_text() if pitch != null else ""))
	var cname := dlg.find_child("CampaignName", true, false) as LineEdit
	check(cname != null and cname.text == "The Sunken Reach", "and asks what to call it, inline")
	var inside_text := dlg.find_child("InsideText", true, false) as Label
	check(inside_text != null and not inside_text.visible and inside_text.text.contains("Rules: "), "what is inside and the licences are there, folded away")
	(dlg.find_child("Inside", true, false) as Button).pressed.emit()
	check(inside_text.visible, "a press away")
	dlg.hide()
	dlg.queue_free()
	# a package path opens that dialog (a file opened from Home or the command line)
	win.ctx.encounter().dirty = false
	win.ctx.campaign.dirty = false
	win._open_path(pkg)
	var opened_dlg: ConfirmationDialog = null
	for c in win.get_children():
		if c is ConfirmationDialog and (c as ConfirmationDialog).title == "Start “The Sunken Reach”" and not c.is_queued_for_deletion():
			opened_dlg = c
	check(opened_dlg != null and opened_dlg.visible, "a package opened is offered to start")
	if opened_dlg != null:
		opened_dlg.hide()
		opened_dlg.queue_free()
	if has_art:
		check(Array(win.ctx.art.pack_ids()) == ["dungeons_and_castles", "woodland"] and not win.ctx.art.terrain("woodland:grass").is_empty(), "the Table draws with the art the campaign carries: %s" % [win.ctx.art.pack_ids()])
	check(win.view.canvas.packs == win.ctx.art, "the map canvas uses it")
	if PluginHost.available():
		check(win.ctx.host != null and win.ctx.host.plugins.has("sample.degrees"), "and loads from the campaign, with nothing installed: %s" % [win.ctx.plugin_log])
		check(win.ctx.kernel.comp.get_entry("creatures", "reach-eel").name == "Reach eel", "the package's own content too")
		check(win.ctx.kernel.comp.count("creatures") == 7, "with the ruleset's own (%d)" % win.ctx.kernel.comp.count("creatures"))
	# duplicated for a second group
	var dup := Campaign.duplicate_to(mine, home.path_join("second"), "Ben's Reach", true)
	check(dup.ok, "duplicated: %s" % str(dup.why))
	var copy := Campaign.load_file(str(dup.path), err)
	check(copy != null and copy.name == "Ben's Reach" and copy.id != mine.id and copy.maps.size() == 1, "the copy stands alone")
	check(copy.encounters.size() == 1 and (copy.encounters[0].played as Array).is_empty() and (copy.doc.journal as Array).is_empty(), "as a fresh start: nothing played, no journal")
	check(FileAccess.file_exists(home.path_join("second/packs/reach/pack.json")), "with its own copy of the content")
	check(not Campaign.duplicate_to(mine, home.path_join("second"), "Again").ok, "a folder that exists is not overwritten")
	# the author's loop: the campaign becomes the package's working copy, each release a version
	var src_c := Campaign.load_file(home.path_join("source/reach.campaign"), err)
	var rel1 := CampaignPackage.release(src_c, "First release.", {"path": home.path_join("reach_release.campaignpkg"), "plugin_dirs": ["res://tests/plugins"]})
	check(rel1.ok and str(rel1.version) == "1.0.0" and str(src_c.doc.source_of.id) == "the_sunken_reach", "the first release is 1.0.0 and the campaign is now its source: %s" % [rel1])
	var rel2 := CampaignPackage.release(src_c, "The harbour map is bigger.", {"plugin_dirs": ["res://tests/plugins"]})
	check(rel2.ok and str(rel2.version) == "1.0.1" and str(rel2.path) == home.path_join("reach_release.campaignpkg"), "the next release bumps the patch and goes to the same file")
	var info2 := CampaignPackage.read(str(rel2.path))
	check(str(info2.package_version) == "1.0.1" and (info2.manifest.changelog as Array).size() == 2 and str(info2.manifest.changelog[1].notes) == "The harbour map is bigger.", "carrying its changelog")
	check(CampaignPackage.bump("1.4.9", "minor") == "1.5.0" and CampaignPackage.bump("1.4.9", "major") == "2.0.0" and CampaignPackage.bump("0.1.0") == "0.1.1", "versions bump by part")
	# a DM's campaign started from 1.2.0 sees 1.3.0 in the library — and nothing moves until they say so
	var lib := home.path_join("library")
	DirAccess.make_dir_recursive_absolute(lib)
	var author2 := Campaign.load_file(home.path_join("source/reach.campaign"), err)
	author2.encounters.append({"id": "enc_harbour", "name": "Trouble at the harbour", "map": str(author2.maps[0].id), "level": "ground", "creatures": [], "played": []})
	check(ContentImport.write_pack(home.path_join("source/packs/reach"), {"id": "reach", "name": "Reach content", "plugin": "sample.degrees", "pack_version": "2"},
		{"creatures": [{"id": "reach-eel", "name": "Reach eel", "level": 3, "kind": "animal", "stats": {"might": 1, "agility": 2, "mind": 0}, "ac_base": 12, "hp": 12}]}) == "", "the author changes the content")
	author2.doc.source_of = {}
	author2.save()
	var v13 := CampaignPackage.export_from(author2, lib.path_join("reach_1_3.campaignpkg"), {"id": "sunken-reach", "package_version": "1.3.0", "plugin_dirs": ["res://tests/plugins"],
		"changelog": [{"version": "1.3.0", "date": "2026-09-23", "notes": "A harbour fight; tougher eels."}]})
	check(v13.ok, "1.3.0 is in the DM's library")
	var mine2 := Campaign.load_file(str(inst.path), err)
	var newer := CampaignPackage.newer_for(mine2, lib)
	check(str(newer.get("package_version", "")) == "1.3.0", "the Table notices the newer version")
	var rep := CampaignPackage.update_report(mine2, str(newer.path))
	check(str(rep.from) == "1.2.0" and str(rep.to) == "1.3.0" and (rep.changelog as Array).size() == 1, "the report says from where to where, and why: %s" % [rep.changelog])
	check((rep.packs.changed as Array).has("reach") and (rep.encounters.added as Array).has("Trouble at the harbour"), "what changes: the content, a new encounter (%s)" % [rep])
	var summary2 := TableWindow.update_summary(rep)
	check(summary2.contains("1.2.0 → 1.3.0") and summary2.contains("A harbour fight") and summary2.contains("Content changed: reach"), "the DM reads it first")
	check(str(mine2.doc.package.version) == "1.2.0" and mine2.encounters.size() == 1, "and until they choose, nothing has moved")
	var applied := CampaignPackage.apply_update(mine2, str(newer.path), true, false)
	check(applied.ok and str(mine2.doc.package.version) == "1.3.0" and mine2.encounters.size() == 2, "taking it brings the new encounter in: %s" % [applied.applied])
	check(FileAccess.get_file_as_string(home.path_join("mine/packs/reach/creatures.json")).contains("\"hp\": 12"), "and the new content")
	check(mine2.encounter_entry("enc").played.is_empty() and (mine2.doc.package_updates as Array).size() == 1, "leaving the campaign's own play as it was, and noting the update")
	# art its makers do not let be passed on stops the export, by name
	DirAccess.make_dir_recursive_absolute(home.path_join("mine/art/secret"))
	var sf := FileAccess.open(home.path_join("mine/art/secret/pack.json"), FileAccess.WRITE)
	sf.store_string(JsonDoc.stringify({"format": "silvergrove.pack", "version": 1, "id": "secret", "name": "Bought art", "license": "Proprietary — personal use only"}))
	sf.close()
	var blocked := CampaignPackage.export_from(mine, home.path_join("blocked.campaignpkg"), {"plugin_dirs": ["res://tests/plugins"]})
	check(not blocked.ok and str(blocked.why).contains("'secret'") and str(blocked.why).contains("personal use"), "art that may not be redistributed is refused: %s" % str(blocked.why))
	check(not FileAccess.file_exists(home.path_join("blocked.campaignpkg")), "and no package is left behind")
	check(PackLibrary.redistributable({"license": "CC-BY-4.0"}).ok and PackLibrary.redistributable({"license": "Proprietary", "redistributable": true}).ok and not PackLibrary.redistributable({}).ok, "licences that allow it, an explicit yes, and silence is no")
	root.remove_child(win)
	win.free()
	PluginHost._rm_rf(home)


func _find_first(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var f := _find_first(c, cls)
		if f != null:
			return f
	return null
