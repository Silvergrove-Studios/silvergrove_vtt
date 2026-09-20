extends TestCase
## UI: theme, icons, layout, docks, palette, options.


## WCAG relative luminance contrast ratio.
static func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _lum(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)


func test_theme_builder() -> void:
	var required := ["bg", "bg_deep", "canvas", "surface", "surface_hover", "surface_pressed", "border", "border_strong",
		"text", "text_dim", "text_disabled", "accent", "accent_text", "shadow", "radius", "spacing", "font_size", "icon", "stroke", "label", "dark"]
	for name in ThemeBuilder.names():
		var t := ThemeBuilder.tokens(name)
		for k in required:
			check(t.has(k), "%s has token %s" % [name, k])
		var th := ThemeBuilder.build(name)
		check(th != null and th.default_font != null and th.default_font_size == int(t.font_size), "%s builds with a default font" % name)
		for variation in ["ToolButton", "AccentButton", "HeaderLabel", "DimLabel", "MonoLabel"]:
			check(th.get_type_variation_base(variation) != "", "%s defines variation %s" % [name, variation])
		for kind in ["Button", "OptionButton", "LineEdit", "Tree", "ItemList", "TabContainer", "PopupMenu", "MenuBar", "HSlider", "Window"]:
			check(th.get_stylebox_list(kind).size() > 0, "%s styles %s" % [name, kind])
		# Readability: body text and hints against the panel, accent against the panel.
		var bg := ThemeBuilder.c(t, "bg")
		check(_contrast(ThemeBuilder.c(t, "text"), bg) >= 7.0, "%s text/bg contrast %.1f ≥ 7" % [name, _contrast(ThemeBuilder.c(t, "text"), bg)])
		check(_contrast(ThemeBuilder.c(t, "text_dim"), bg) >= 4.5, "%s dim text/bg contrast %.1f ≥ 4.5" % [name, _contrast(ThemeBuilder.c(t, "text_dim"), bg)])
		check(_contrast(ThemeBuilder.c(t, "text"), ThemeBuilder.c(t, "surface")) >= 4.5, "%s text on buttons" % name)
		check(_contrast(ThemeBuilder.c(t, "accent"), bg) >= 3.0, "%s accent/bg contrast %.1f ≥ 3" % [name, _contrast(ThemeBuilder.c(t, "accent"), bg)])
		check(_contrast(ThemeBuilder.c(t, "accent_text"), ThemeBuilder.c(t, "accent")) >= 4.5, "%s accent button text" % name)
		check(_contrast(ThemeBuilder.c(t, "text"), ThemeBuilder.c(t, "bg_deep")) >= 7.0, "%s text in inputs" % name)
	check(ThemeBuilder.tokens("nope") == ThemeBuilder.tokens("slate"), "unknown theme falls back to slate")
	for f in ["Inter-Regular.ttf", "Inter-Medium.ttf", "Inter-SemiBold.ttf", "JetBrainsMono-Regular.ttf"]:
		var font := ThemeBuilder.font(f)
		check(font != null and font != ThemeDB.fallback_font, "font %s loads" % f)


func test_ui_icons() -> void:
	# Every icon named anywhere in the editor code exists and rasterises.
	if not FileAccess.file_exists("res://hexmap/editor/editor_window.gd") or FileAccess.get_file_as_string("res://hexmap/editor/editor_window.gd").is_empty():
		skip("script sources are compiled in this build; icon names cannot be scanned")
		var tex0 := UiIcons.get_icon("eye", 20, Color.RED)
		check(tex0 != null and tex0.get_width() == 20, "icons still rasterise from the pack")
		return
	var named := {}
	var re := RegEx.new()
	re.compile('get_icon\\("([a-z0-9-]+)"|set_meta\\("icon", "([a-z0-9-]+)"\\)|_button\\("([a-z0-9-]+)"')
	for path in ["res://hexmap/editor/editor_window.gd", "res://hexmap/shell/home.gd", "res://hexmap/ui/theme_builder.gd", "res://hexmap/editor/layers_panel.gd", "res://hexmap/editor/palette.gd"]:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			for g in [1, 2, 3]:
				if m.get_string(g) != "":
					named[m.get_string(g)] = true
	var main_src := FileAccess.get_file_as_string("res://hexmap/editor/editor_window.gd")
	var tools_re := RegEx.new()
	tools_re.compile('"[a-z]+": "([a-z0-9-]+)"')
	var start := main_src.find("TOOL_ICONS")
	for m in tools_re.search_all(main_src.substr(start, main_src.find("}", start) - start)):
		named[m.get_string(1)] = true
	for m in HomeScreen.MODE_ICONS:
		named[HomeScreen.MODE_ICONS[m]] = true
	check(named.size() >= 20, "found %d icon names in code" % named.size())
	var missing := []
	for n in named:
		if not FileAccess.file_exists(UiIcons.dir().path_join(n + ".svg")):
			missing.append(n)
	check(missing.is_empty(), "icons missing on disk: %s" % [missing])
	var tex := UiIcons.get_icon("eye", 20, Color.RED)
	check(tex.get_width() == 20 and tex.get_height() == 20, "icon rasterised at requested size")
	var img := tex.get_image()
	var red := 0
	for y in 20:
		for x in 20:
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.8 and c.g < 0.2:
				red += 1
	check(red > 20, "icon takes the requested colour (%d red px)" % red)
	check(UiIcons.get_icon("eye", 20, Color.RED) == tex, "icon cached")
	check(UiIcons.get_icon("no-such-icon", 16) != null, "missing icon gives a placeholder")


func test_layout_store() -> void:
	var d := LayoutStore.default_layout()
	var names := Array(LayoutStore.names(d))
	names.sort()
	var expected := LayoutStore.PANELS.duplicate()
	expected.sort()
	check(names == expected, "default layout names every panel once: %s" % [names])
	var path := "user://test_layout.tres"
	check(LayoutStore.save(d, path) == OK, "layout saves")
	var back := LayoutStore.load_or_default(path)
	var back_names := Array(LayoutStore.names(back))
	back_names.sort()
	check(back_names == expected, "layout round-trips: %s" % [back_names])
	check(back.root is DockableLayoutSplit and (back.root as DockableLayoutSplit).percent == 0.2, "split geometry preserved")
	check((back.root as DockableLayoutSplit).first is DockableLayoutSplit and ((back.root as DockableLayoutSplit).first as DockableLayoutSplit).direction == DockableLayoutSplit.Direction.VERTICAL, "nested vertical split preserved")
	# A saved layout from an older build lacks a panel: it is added back.
	var old := DockableLayout.new()
	var leaf := DockableLayoutPanel.new()
	leaf.names = PackedStringArray(["Palette", "Canvas"])
	old.root = leaf
	var repaired := LayoutStore.repair(old)
	var rn := Array(LayoutStore.names(repaired))
	rn.sort()
	check(rn == expected, "missing panels restored: %s" % [rn])
	check(LayoutStore.load_or_default("user://does_not_exist.tres").get_names().size() == LayoutStore.PANELS.size(), "no file → default")
	var f := FileAccess.open("user://broken.tres", FileAccess.WRITE)
	f.store_string("not a resource")
	f.close()
	check(LayoutStore.load_or_default("user://broken.tres").get_names().size() == LayoutStore.PANELS.size(), "unreadable file → default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://broken.tres"))


func test_native_menu_accelerators() -> void:
	var k := NativeMenuMirror._native_accel(KEY_S | KEY_MASK_CMD_OR_CTRL)
	check((k & KEY_MASK_CMD_OR_CTRL) == 0, "placeholder mask resolved")
	if OS.get_name() == "macOS":
		check((k & KEY_MASK_META) != 0 and (k & KEY_CODE_MASK) == KEY_S, "Cmd+S on macOS")
	else:
		check((k & KEY_MASK_CTRL) != 0 and (k & KEY_CODE_MASK) == KEY_S, "Ctrl+S elsewhere")
	check(NativeMenuMirror._native_accel(KEY_NONE) == KEY_NONE, "none stays none")
	check(NativeMenuMirror._native_accel(KEY_G) == KEY_G, "plain key untouched")


func test_dock_pane_drag() -> void:
	# A pane's title bar produces the drag data the DockableContainer accepts
	# from its own tabs, pointing at the panel that currently holds the pane.
	var dock := DockableContainer.new()
	dock.size = Vector2(800, 600)
	root.add_child(dock)
	var a := DockPane.new("Palette", Control.new())
	var b := DockPane.new("Canvas", Control.new())
	dock.add_child(a)
	dock.add_child(b)
	dock.layout = LayoutStore.default_layout()
	dock.notification(Container.NOTIFICATION_SORT_CHILDREN)
	check(a.dock() == dock, "pane finds its dock")
	var data = a.drag_data()
	check(data is Dictionary and data.get("type") == "tabc_element", "drag data has the tab type: %s" % [data])
	if data is Dictionary:
		var panel := root.get_node(data.from_path) as TabContainer
		check(panel != null, "from_path resolves to a panel")
		if panel != null:
			var tab := panel.get_tab_control(int(data.tabc_element))
			check(tab == a or (tab != null and tab.get("reference_to") == a), "tab index points at this pane")
		check(dock._can_drop_data(Vector2.ZERO, data), "dock accepts the drag")
	check(b.drag_data() != null and b.drag_data().from_path != data.from_path, "second pane is in a different panel")
	var stray := DockPane.new("Loose", Control.new())
	root.add_child(stray)
	check(stray.drag_data() == null, "a pane outside a dock has no drag data")
	stray.free()
	dock.free()


func test_select_gizmos() -> void:
	var ctx := _ctx()
	ctx.zoom = 1.0
	var mods := {"shift": false, "ctrl": false, "alt": false}
	var shift := {"shift": true, "ctrl": false, "alt": false}
	ctx.prop_ref = "dungeons_and_castles:table"    # 1.4 x 0.8 hex, anchor centre
	var prop := ctx.new_prop(Vector2(4.0, 4.0))
	ctx.commands.add_object(0, "props", prop)
	ctx.select_one("props", prop.id)
	var sel := EditorTools.make("select", ctx) as EditorTools.SelectTool
	var hs := sel.handles()
	check(hs.has("tl") and hs.has("br") and hs.has("rotate"), "prop has corner and rotate handles: %s" % [hs.keys()])
	check(near(hs["tl"].x, 4.0 - 0.7, 1e-3) and near(hs["tl"].y, 4.0 - 0.4, 1e-3), "top-left corner at the unrotated bounds: %s" % hs["tl"])
	check(hs["rotate"].y < hs["tl"].y, "rotate handle sits above the top edge")
	check(sel.handle_at(hs["br"] + Vector2(0.01, 0.01)) == "br", "handle hit within tolerance")
	check(sel.handle_at(Vector2(4.0, 4.0)) == "", "no handle at the centre")
	# Scale: drag the bottom-right corner outward, doubling its distance.
	var br: Vector2 = hs["br"]
	sel.press(br, MOUSE_BUTTON_LEFT, mods)
	sel.drag(Vector2(4.0, 4.0) + (br - Vector2(4.0, 4.0)) * 2.0, MOUSE_BUTTON_LEFT, mods)
	sel.release(br, MOUSE_BUTTON_LEFT, mods)
	check(near(float(ctx.level().props[0].scale), 2.0, 1e-3), "corner drag doubled the scale: %s" % ctx.level().props[0].scale)
	check(ctx.level().props[0].pos == [4.0, 4.0], "scaling keeps the anchor put")
	ctx.history.undo()
	check(near(float(ctx.level().props[0].get("scale", 1.0)), 1.0), "scale undone in one step")
	# Rotate: drag the rotate handle a quarter turn clockwise; Shift snaps to 15°.
	hs = sel.handles()
	var rh: Vector2 = hs["rotate"]
	sel.press(rh, MOUSE_BUTTON_LEFT, mods)
	var a0 := (rh - Vector2(4.0, 4.0)).angle()
	var target := Vector2(4.0, 4.0) + Vector2(cos(a0 + PI / 2.0 + 0.05), sin(a0 + PI / 2.0 + 0.05)) * (rh - Vector2(4.0, 4.0)).length()
	sel.drag(target, MOUSE_BUTTON_LEFT, shift)
	sel.release(target, MOUSE_BUTTON_LEFT, shift)
	check(near(float(ctx.level().props[0].rot), 90.0, 1e-3), "rotate handle with Shift snapped to 90°: %s" % ctx.level().props[0].rot)
	hs = sel.handles()
	check(near(hs["rotate"].x, 4.0 + 0.4 + sel.handle_hex(28.0), 1e-3), "rotated gizmo follows the prop: rotate handle now on the right (%s)" % hs["rotate"])
	# Hover state drives the cursor.
	sel.move(Vector2(4.0, 4.0))
	check(sel.cursor() == Control.CURSOR_MOVE, "hovering the prop body: move cursor")
	sel.move(hs["rotate"])
	check(sel.cursor() == Control.CURSOR_POINTING_HAND, "hovering the rotate handle: hand cursor")
	sel.move(Vector2(0.5, 0.5))
	check(sel.cursor() == Control.CURSOR_ARROW, "hovering nothing: arrow")
	check(EditorTools.make("terrain", ctx).cursor() == Control.CURSOR_CROSS, "paint tool uses a crosshair")
	# Handles scale with zoom: zooming in shrinks them in hex units.
	ctx.zoom = 4.0
	check(near(sel.handle_hex(), 7.0 / (256.0 * 4.0)), "handle size is constant on screen")
	ctx.zoom = 1.0
	# Light radius handles.
	ctx.light_preset = {"bright": 1.0, "dim": 2.0, "color": "#ffffff"}
	var l := ctx.new_light(Vector2(6.0, 6.0))
	ctx.commands.add_object(0, "lights", l)
	ctx.select_one("lights", l.id)
	hs = sel.handles()
	check(hs.has("dim") and near(hs["dim"].x, 8.0) and hs.has("bright"), "light has ring handles: %s" % [hs])
	sel.press(hs["dim"], MOUSE_BUTTON_LEFT, mods)
	sel.drag(Vector2(9.0, 6.0), MOUSE_BUTTON_LEFT, mods)
	sel.release(Vector2(9.0, 6.0), MOUSE_BUTTON_LEFT, mods)
	check(near(float(ctx.level().lights[0].dim), 3.0), "dragging the dim ring sets dim = 3: %s" % ctx.level().lights[0].dim)
	hs = sel.handles()
	sel.press(hs["bright"], MOUSE_BUTTON_LEFT, mods)
	sel.drag(Vector2(6.0, 6.0) + Vector2(3.5, 0.0), MOUSE_BUTTON_LEFT, mods)
	sel.release(Vector2.ZERO, MOUSE_BUTTON_LEFT, mods)
	check(near(float(ctx.level().lights[0].bright), 3.5) and near(float(ctx.level().lights[0].dim), 3.5), "bright pushed past dim drags dim along")
	ctx.canvas.free()


func test_palette_model() -> void:
	var lib := PackLibrary.new()
	lib.reload()
	var props := lib.all("props")
	check(PaletteModel.matches(props[0], ""), "empty query matches everything")
	var torch := PaletteModel.count(props, "torch")
	check(torch >= 1, "search finds the torch sconce: %d" % torch)
	check(PaletteModel.count(props, "TORCH") == torch, "search is case-insensitive")
	check(PaletteModel.count(props, "dungeons tree") == 0 and PaletteModel.count(props, "woodland tree") >= 3, "all words must match (pack + tag): %d" % PaletteModel.count(props, "woodland tree"))
	check(PaletteModel.count(props, "swamp:mangrove") == 1, "search by ref")
	var names := {"woodland": "Woodland", "swamp": "Swamp", "dungeons_and_castles": "Dungeons & Castles"}
	var secs := PaletteModel.sections(props, "", ["woodland:oak"], ["swamp:mangrove", "woodland:oak"], names)
	check(secs[0].id == "favorites" and secs[0].items.size() == 1 and secs[0].items[0]._ref == "woodland:oak", "favourites first")
	check(secs[1].id == "recent" and secs[1].items.size() == 1 and secs[1].items[0]._ref == "swamp:mangrove", "recent skips favourites")
	check(secs.size() == 5 and secs[2].title == "Dungeons & Castles", "one section per pack, named: %s" % [secs.map(func(s): return s.title)])
	var filtered := PaletteModel.sections(props, "oak", ["woodland:oak"], [], names)
	check(filtered.size() == 2 and filtered[1].id == "pack:woodland" and filtered[1].items.size() == 2, "filter empties other packs: %s" % [filtered.map(func(s): return "%s:%d" % [s.id, s.items.size()])])
	var r := PaletteModel.push_recent([], "a")
	r = PaletteModel.push_recent(r, "b")
	r = PaletteModel.push_recent(r, "a")
	check(r == ["a", "b"], "recent is most-recent-first and deduplicated: %s" % [r])
	for i in 20:
		r = PaletteModel.push_recent(r, "x%d" % i)
	check(r.size() == PaletteModel.RECENT_MAX, "recent capped at %d" % PaletteModel.RECENT_MAX)
	check(PaletteModel.toggle(["a"], "a") == [] and PaletteModel.toggle([], "a") == ["a"], "toggle favourite")
	var st := PaletteModel.default_state()
	st.favorites.props = ["woodland:oak"]
	st.recent.terrain = ["woodland:grass"]
	st.collapsed["props/pack:swamp"] = true
	check(PaletteModel.save_state(st, "user://test_palette.json") == OK, "state saves")
	var back := PaletteModel.load_state("user://test_palette.json")
	check(back.favorites.props == ["woodland:oak"] and back.recent.terrain == ["woodland:grass"] and back.collapsed["props/pack:swamp"] == true, "state round-trips")
	var f := FileAccess.open("user://test_palette.json", FileAccess.WRITE)
	f.store_string("[1,2]")
	f.close()
	check(PaletteModel.load_state("user://test_palette.json").favorites.props == [], "garbage file → defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_palette.json"))


func test_tool_options() -> void:
	var ctx := _ctx()
	var opts := ToolOptions.new(ctx)
	root.add_child(opts)
	opts.show_for("prop")
	check(opts._controls.has("snap") and opts._controls.has("rot") and opts._controls.has("scale") and opts._controls.has("flip"), "prop tool options")
	(opts._controls.rot as SpinBox).value = 45.0
	check(near(ctx.prop_rotation, 45.0), "rotation spin writes to the context")
	ctx.prop_scale = 1.5
	opts.sync()
	check(near((opts._controls.scale as SpinBox).value, 1.5), "sync pulls context values back")
	(opts._controls.snap as OptionButton).item_selected.emit(2)
	check(ctx.snap == EditorContext.Snap.CORNER, "snap option writes to the context")
	opts.show_for("terrain")
	check(opts._controls.has("brush") and opts._controls.has("variant"), "terrain tool options")
	ctx.terrain_ref = "woodland:grass"
	opts.sync()
	check((opts._controls.variant as OptionButton).item_count == 4, "variant list follows the picked terrain (random + 3)")
	opts.show_for("wall")
	(opts._controls.type as OptionButton).item_selected.emit(1)
	check(ctx.wall_preset == "door", "wall type writes to the context: %s" % ctx.wall_preset)
	opts.show_for("light")
	(opts._controls.dim as SpinBox).value = 4.5
	check(ctx.light_preset.dim == 4.5, "light dim writes to the preset")
	opts.show_for("erase")
	check(opts._controls.is_empty() and opts.get_child_count() == 1, "erase shows only a hint")
	opts.free()
	ctx.canvas.free()
