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
	canvas.packs = ctx.app.packs
	ctx.canvas = canvas


func show_scene() -> void:
	canvas.set_scene(ctx.state, ctx.scene_id)
	zoom_to_fit.call_deferred()


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
