class_name HomeScreen
extends Control
## The first screen: pick a mode, or reopen something recent. Laid out for a
## finger as much as a mouse — big targets, one column, nothing that needs a
## hover or a right-click — because on a phone this is the Player's front
## door too.

signal open_mode(mode: String, arg: String)

const MODE_ICONS := {"editor": "pencil", "table": "hexagon", "player": "eye"}

var app: App
var _recent_box: VBoxContainer
var _column: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = app.build_theme()
	app.theme_changed.connect(func(_n: String) -> void: theme = app.build_theme(); _restyle())
	_build()
	_restyle()


func _build() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	bg.add_child(center)
	var column := VBoxContainer.new()
	_column = column
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	resized.connect(_fit)
	_fit()

	var title := Label.new()
	title.text = App.NAME
	title.theme_type_variation = "HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var sub := Label.new()
	sub.text = "version %s" % App.version()
	sub.theme_type_variation = "DimLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)

	for m in App.MODES:
		var b := Button.new()
		b.name = "Mode_" + m
		b.text = "%s\n%s" % [App.mode_label(m), App.mode_blurb(m)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 64)
		b.set_meta("icon", MODE_ICONS[m])
		b.disabled = not App.mode_available(m)
		b.pressed.connect(func() -> void: open_mode.emit(m, ""))
		column.add_child(b)

	var rec := app.recent()
	if not rec.is_empty():
		_recent_box = _file_list(column, "Recent", rec)
	# The examples that ship inside the app, for a fresh install.
	var examples := []
	var names := {}
	for p in rec:
		names[str(p).get_file()] = true
	for p in App.bundled(".encounter") + App.bundled(".hexmap"):
		if not names.has(str(p).get_file()):
			examples.append(p)
	if not examples.is_empty():
		_file_list(column, "Examples", examples)


func _file_list(column: VBoxContainer, title: String, paths: Array) -> VBoxContainer:
	var h := Label.new()
	h.text = title
	h.theme_type_variation = "DimLabel"
	column.add_child(h)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	column.add_child(box)
	for p in paths:
		var b := Button.new()
		b.text = str(p).get_file()
		b.tooltip_text = str(p)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "ToolButton"
		b.custom_minimum_size = Vector2(0, 40)
		var mode := "table" if str(p).ends_with(".encounter") else "editor"
		b.disabled = not App.mode_available(mode)
		b.pressed.connect(func() -> void: open_mode.emit(mode, str(p)))
		box.add_child(b)
	return box


## The column is 420 wide when there is room, and the window minus a
## gutter when there is not (a phone in portrait).
func _fit() -> void:
	if _column != null:
		_column.custom_minimum_size.x = minf(420.0, maxf(200.0, size.x - 32.0))


func _restyle() -> void:
	var t := ThemeBuilder.tokens(app.theme_name)
	var text := ThemeBuilder.c(t, "text")
	for b in find_children("*", "Button", true, false):
		if b.has_meta("icon"):
			(b as Button).icon = UiIcons.get_icon(str(b.get_meta("icon")), int(t.icon) + 6, text, t.stroke)
