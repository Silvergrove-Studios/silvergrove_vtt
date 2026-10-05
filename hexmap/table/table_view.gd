class_name TableView
extends CanvasView
## The Table's canvas: a CanvasView wired to the TableContext with space+drag
## panning and a TableTools tool as the handler.

var ctx: TableContext
var _space := false

var tool: TableTools.Tool:
	get: return handler as TableTools.Tool


func _init(p_ctx: TableContext) -> void:
	super()
	ctx = p_ctx
	canvas.packs = ctx.art if ctx.art != null else ctx.app.packs
	ctx.canvas = canvas
	# the campaign's own art: a campaign draws with what it carries
	ctx.art_changed.connect(func() -> void:
		canvas.packs = ctx.art
		canvas.queue_redraw())
	# the table's shared marks, everyone's (the DM sees every one), over the map
	canvas.marks_layer.fn = func(c: Node2D) -> void:
		if ctx.state != null:
			MarkDraw.draw(c, canvas, ctx.marks.of_scene(ctx.scene_id), ctx.zoom, template_area, Time.get_ticks_msec(), func(id: String) -> int: return int(_born.get(id, 0)))
	ctx.marks.changed.connect(func(id: String) -> void:
		if not _born.has(id):
			_born[id] = Time.get_ticks_msec()
		canvas.marks_layer.queue_redraw())
	ctx.marks.removed.connect(func(id: String, _m: Dictionary) -> void:
		_born.erase(id)
		canvas.marks_layer.queue_redraw())


## When each mark was first drawn (a ping fades from then).
var _born: Dictionary = {}


## The cells a template mark covers and the creatures it would catch, as the
## rules' own templates do (MapQuery.template).
func template_area(m: Dictionary) -> Dictionary:
	if ctx.kernel == null:
		return {}
	return ctx.kernel.map.template(str(m.scene), Measure.template_spec(m))


func _process(delta: float) -> void:
	super(delta)
	# the marks' time passes here too, hosting or not (a ruler let go lingers, then goes)
	ctx.marks.tick()
	# a ping's rings move and fade
	if ctx.state != null and ctx.marks.of_scene(ctx.scene_id).any(func(m: Dictionary) -> bool: return str(m.kind) == "ping"):
		canvas.marks_layer.queue_redraw()


## What the canvas says when there is no scene to show (playtest 1).
var empty_hint: Label


func show_scene() -> void:
	canvas.set_scene(ctx.state, ctx.scene_id)
	zoom_to_fit.call_deferred()
	if empty_hint == null:
		empty_hint = Label.new()
		empty_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		empty_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		empty_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
		empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_hint.theme_type_variation = "DimLabel"
		empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_hint.text = "No scene yet.\nShow a map from the Maps pane (or the Scene drop-down) —\nthe players see what you show."
		add_child(empty_hint)
	empty_hint.visible = ctx.scene_id == "" or ctx.state == null or ctx.encounter().scene(ctx.scene_id).is_empty()


func _on_zoom(z: float) -> void:
	ctx.zoom = z
	super(z)


func _pan_modifier() -> bool:
	return _space


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE:
		_space = (event as InputEventKey).pressed
		if not _space:
			_panning = false


func set_tool(t: TableTools.Tool) -> void:
	set_handler(t)
