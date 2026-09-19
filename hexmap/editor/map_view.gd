class_name MapView
extends SubViewportContainer
## The centre of the window: a SubViewport holding a Camera2D and the
## MapCanvas. Handles pan/zoom itself and hands everything else to the
## active tool in hex-unit coordinates.

signal cursor_moved(hex: Vector2)
signal zoom_changed(zoom: float)

var ctx: EditorContext
var viewport: SubViewport
var camera: Camera2D
var canvas: MapCanvas
var tool: EditorTools.Tool
var _bg: ColorRect
var _panning := false
var _pressed_button := 0
var _space := false

const MIN_ZOOM := 0.02
const MAX_ZOOM := 8.0


func _init(p_ctx: EditorContext) -> void:
	ctx = p_ctx
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.handle_input_locally = false
	viewport.disable_3d = true
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(viewport)
	# Surround colour behind the map, fixed to the viewport (not the camera).
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	_bg = ColorRect.new()
	_bg.color = Color("#131416")
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(_bg)
	viewport.add_child(bg_layer)
	var root := Node2D.new()
	viewport.add_child(root)
	canvas = MapCanvas.new()
	canvas.map = ctx.map
	canvas.packs = ctx.packs
	canvas.ppx = float(ctx.map.reference_ppx)
	root.add_child(canvas)
	camera = Camera2D.new()
	camera.enabled = true
	root.add_child(camera)
	ctx.canvas = canvas
	canvas.overlay.fn = func(c: Node2D) -> void:
		if tool != null:
			tool.draw_overlay(c)


func _ready() -> void:
	zoom_to_fit.call_deferred()


func set_surround(color: Color, shadow: Color) -> void:
	_bg.color = color
	canvas.shadow_color = shadow
	canvas.queue_redraw()


func set_map(map: HexMap) -> void:
	canvas.map = map
	canvas.ppx = float(map.reference_ppx)
	canvas.level_index = ctx.level_index
	canvas.refresh()
	zoom_to_fit.call_deferred()


func zoom() -> float:
	return camera.zoom.x


func set_zoom(z: float, around_screen: Vector2 = Vector2(-1, -1)) -> void:
	z = clampf(z, MIN_ZOOM, MAX_ZOOM)
	if around_screen.x < 0:
		around_screen = size / 2.0
	var before := screen_to_world(around_screen)
	camera.zoom = Vector2(z, z)
	var after := screen_to_world(around_screen)
	camera.position += before - after
	_update_texture_density()
	zoom_changed.emit(z)


func _update_texture_density() -> void:
	var want := PackLibrary.bucket_for(canvas.ppx * zoom())
	if want != PackLibrary.bucket_for(canvas.texture_ppx):
		canvas.texture_ppx = float(want)
		canvas.refresh()


func zoom_to_fit() -> void:
	if ctx.map == null or size.x < 2:
		return
	var map_px := ctx.map.grid.map_size() * canvas.ppx
	var z := minf(size.x / (map_px.x * 1.08), size.y / (map_px.y * 1.08))
	camera.zoom = Vector2(z, z)
	camera.position = map_px / 2.0
	_update_texture_density()
	zoom_changed.emit(z)


## Screen (container-local) pixels -> canvas pixels.
func screen_to_world(p: Vector2) -> Vector2:
	return viewport.get_canvas_transform().affine_inverse() * p


func screen_to_hex(p: Vector2) -> Vector2:
	return screen_to_world(p) / canvas.ppx


func _mods(e: InputEventWithModifiers) -> Dictionary:
	return {"shift": e.shift_pressed, "ctrl": e.ctrl_pressed or e.meta_pressed, "alt": e.alt_pressed}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if e.pressed:
					set_zoom(zoom() * (1.15 if not e.ctrl_pressed else 1.4), e.position)
				accept_event()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					set_zoom(zoom() / (1.15 if not e.ctrl_pressed else 1.4), e.position)
				accept_event()
				return
			MOUSE_BUTTON_MIDDLE:
				_panning = e.pressed
				accept_event()
				return
		if e.button_index == MOUSE_BUTTON_LEFT and _space:
			_panning = e.pressed
			accept_event()
			return
		grab_focus()
		var hex := screen_to_hex(e.position)
		if e.pressed:
			if e.double_click and tool != null and tool.double_click(hex):
				accept_event()
				return
			_pressed_button = e.button_index
			if tool != null and tool.press(hex, e.button_index, _mods(e)):
				accept_event()
		else:
			if tool != null:
				tool.release(hex, e.button_index, _mods(e))
			_pressed_button = 0
		canvas.overlay.queue_redraw()
	elif event is InputEventMouseMotion:
		var e := event as InputEventMouseMotion
		if _panning:
			camera.position -= e.relative / zoom()
			accept_event()
			return
		var hex := screen_to_hex(e.position)
		cursor_moved.emit(hex)
		if tool != null:
			if _pressed_button != 0 and (e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
				tool.drag(hex, _pressed_button, _mods(e))
			tool.move(hex)
	elif event is InputEventPanGesture:
		var e := event as InputEventPanGesture
		camera.position += e.delta * 12.0 / zoom()
		accept_event()
	elif event is InputEventMagnifyGesture:
		var e := event as InputEventMagnifyGesture
		set_zoom(zoom() * e.factor, e.position)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE:
		_space = (event as InputEventKey).pressed
		if not _space:
			_panning = false


func set_tool(t: EditorTools.Tool) -> void:
	if tool != null:
		tool.deactivate()
	tool = t
	if tool != null:
		tool.activate()
	canvas.overlay.queue_redraw()
