class_name CanvasView
extends Control
## A MapCanvas under a Camera2D with pan and zoom: mouse wheel, middle
## drag, trackpad gestures, and two-finger touch. Everything else goes to
## the `handler` (a tool) in hex-unit coordinates: press/drag/release/move/
## double_click/key/draw_overlay/cursor, all optional. Shared by the Editor,
## the Table and the Player, so nothing here assumes a keyboard or a mouse.
##
## It owns its SubViewport rather than being a SubViewportContainer so the
## map renders at the screen's real pixels under a scaled window (Retina,
## a phone, a big UI size) while its 2D space stays in logical points.

signal cursor_moved(hex: Vector2)
signal zoom_changed(zoom: float)

const MIN_ZOOM := 0.02
const MAX_ZOOM := 8.0

var viewport: SubViewport
var camera: Camera2D
var canvas: MapCanvas
## The active tool: any object with the methods named above.
var handler: Object
var _bg: ColorRect
var _panning := false
var _pressed_button := 0
## Touch: index -> position, for pinch and two-finger pan.
var _touches: Dictionary = {}
var _pinch_dist := 0.0
var _pinch_center := Vector2.ZERO


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	# The texture is drawn 1:1 with the screen; nothing to smooth.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport = SubViewport.new()
	viewport.handle_input_locally = false
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	root.add_child(canvas)
	camera = Camera2D.new()
	camera.enabled = true
	root.add_child(camera)
	canvas.overlay.fn = func(c: Node2D) -> void:
		if handler != null and handler.has_method("draw_overlay"):
			handler.draw_overlay(c)


func _ready() -> void:
	_fit_viewport()
	zoom_to_fit.call_deferred()


## Render at the screen's pixels, lay out in logical points: the viewport
## is `size` × the window's content scale, and its 2D space is overridden
## back to `size` so the camera, the tools and input all keep their units.
func _fit_viewport() -> void:
	var factor := 1.0
	if is_inside_tree():
		factor = get_window().content_scale_factor
	var logical := Vector2i(size.round())
	if logical.x < 1 or logical.y < 1:
		return
	var want := Vector2i((size * factor).round())
	if viewport.size != want:
		viewport.size = want
	if viewport.size_2d_override != logical:
		viewport.size_2d_override = logical
	viewport.size_2d_override_stretch = true
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_viewport()


## The window's scale can change under us (the user picks a UI size).
func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	var want := Vector2i((size * get_window().content_scale_factor).round())
	if want.x >= 1 and want.y >= 1 and viewport.size != want:
		_fit_viewport()


func _draw() -> void:
	draw_texture_rect(viewport.get_texture(), Rect2(Vector2.ZERO, size), false)


func set_surround(color: Color, shadow: Color) -> void:
	_bg.color = color
	canvas.shadow_color = shadow
	canvas.queue_redraw()


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
	_on_zoom(z)


func _on_zoom(z: float) -> void:
	_update_texture_density()
	zoom_changed.emit(z)


func _update_texture_density() -> void:
	var want := PackLibrary.bucket_for(canvas.ppx * zoom())
	if want != PackLibrary.bucket_for(canvas.texture_ppx):
		canvas.texture_ppx = float(want)
		canvas.refresh()


func zoom_to_fit() -> void:
	if canvas.map == null or size.x < 2 or size.y < 2:
		return
	var map_px := canvas.map.grid.map_size() * canvas.ppx
	var z := minf(size.x / (map_px.x * 1.08), size.y / (map_px.y * 1.08))
	camera.zoom = Vector2(z, z)
	camera.position = map_px / 2.0
	_on_zoom(z)


## Screen (container-local) pixels -> canvas pixels.
func screen_to_world(p: Vector2) -> Vector2:
	return viewport.get_canvas_transform().affine_inverse() * p


func screen_to_hex(p: Vector2) -> Vector2:
	return screen_to_world(p) / canvas.ppx


func _mods(e: InputEvent) -> Dictionary:
	if e is InputEventWithModifiers:
		var m := e as InputEventWithModifiers
		return {"shift": m.shift_pressed, "ctrl": m.ctrl_pressed or m.meta_pressed, "alt": m.alt_pressed}
	return {"shift": false, "ctrl": false, "alt": false}


## Subclasses may claim a left drag as a pan (the editor's space+drag).
func _pan_modifier() -> bool:
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_input(event)
		return
	if _touches.size() >= 2:
		return   # a pinch in progress; ignore the emulated mouse
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
		if e.button_index == MOUSE_BUTTON_LEFT and _pan_modifier():
			_panning = e.pressed
			accept_event()
			return
		grab_focus()
		var hex := screen_to_hex(e.position)
		if e.pressed:
			if e.double_click and _call("double_click", [hex]):
				accept_event()
				return
			_pressed_button = e.button_index
			if _call("press", [hex, e.button_index, _mods(e)]):
				accept_event()
		else:
			_call("release", [hex, e.button_index, _mods(e)])
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
		if handler != null:
			if _pressed_button != 0 and (e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
				_call("drag", [hex, _pressed_button, _mods(e)])
			_call("move", [hex])
			if handler.has_method("cursor"):
				mouse_default_cursor_shape = handler.cursor()
	elif event is InputEventPanGesture:
		var e := event as InputEventPanGesture
		camera.position += e.delta * 12.0 / zoom()
		accept_event()
	elif event is InputEventMagnifyGesture:
		var e := event as InputEventMagnifyGesture
		set_zoom(zoom() * e.factor, e.position)
		accept_event()


## Two fingers pinch to zoom and drag to pan; one finger is the emulated
## mouse and reaches the handler as a press/drag/release.
func _touch_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		if _touches.size() == 2:
			var pts := _touches.values()
			_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
			_pinch_center = ((pts[0] as Vector2) + (pts[1] as Vector2)) / 2.0
			# The first finger's press already reached the handler; cancel it.
			if _pressed_button != 0:
				_call("release", [screen_to_hex(_pinch_center), _pressed_button, _mods(e)])
				_pressed_button = 0
			accept_event()
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		if not _touches.has(e.index):
			return
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var pts := _touches.values()
			var dist := (pts[0] as Vector2).distance_to(pts[1])
			var center := ((pts[0] as Vector2) + (pts[1] as Vector2)) / 2.0
			if _pinch_dist > 1.0:
				set_zoom(zoom() * dist / _pinch_dist, center)
			camera.position -= (center - _pinch_center) / zoom()
			_pinch_dist = dist
			_pinch_center = center
			accept_event()


func _call(method: String, args: Array) -> bool:
	if handler == null or not handler.has_method(method):
		return false
	var r = handler.callv(method, args)
	return r if r is bool else false


func set_handler(h: Object) -> void:
	if handler != null and handler.has_method("deactivate"):
		handler.deactivate()
	handler = h
	if handler != null:
		if handler.has_method("activate"):
			handler.activate()
		if handler.has_method("cursor"):
			mouse_default_cursor_shape = handler.cursor()
	canvas.overlay.queue_redraw()
