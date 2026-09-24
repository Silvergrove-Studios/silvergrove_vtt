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
