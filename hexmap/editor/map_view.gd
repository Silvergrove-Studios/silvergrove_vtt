class_name MapView
extends CanvasView
## The editor's canvas: a CanvasView wired to the EditorContext (map, packs,
## level, zoom for the tools' handle sizes) with space+drag panning and the
## editor's Tool as the handler.

var ctx: EditorContext
var _space := false

var tool: EditorTools.Tool:
	get: return handler as EditorTools.Tool


func _init(p_ctx: EditorContext) -> void:
	super()
	ctx = p_ctx
	canvas.map = ctx.map
	canvas.packs = ctx.packs
	canvas.ppx = float(ctx.map.reference_ppx)
	ctx.canvas = canvas


func set_map(map: HexMap) -> void:
	canvas.map = map
	canvas.ppx = float(map.reference_ppx)
	canvas.level_index = ctx.level_index
	canvas.refresh()
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


func set_tool(t: EditorTools.Tool) -> void:
	set_handler(t)
