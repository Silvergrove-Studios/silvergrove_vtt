class_name TableWindow
extends Control
## The Table: where a DM runs an encounter on one or more maps — tokens,
## doors, lights, fog, initiative. Desktop only (it docks panels like the
## editor). Not built yet; this is the mode's front door so the shell can
## route to it.

signal go_home

var app: App


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = app.build_theme()
	app.theme_changed.connect(func(_n: String) -> void: theme = app.build_theme())
	get_window().title = "Table — " + App.NAME
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	bg.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var l := Label.new()
	l.text = "Table"
	l.theme_type_variation = "HeaderLabel"
	column.add_child(l)
	var d := Label.new()
	d.text = "Encounters are not built yet."
	d.theme_type_variation = "DimLabel"
	column.add_child(d)
	var b := Button.new()
	b.text = "Home"
	b.pressed.connect(func() -> void: go_home.emit())
	column.add_child(b)


## Called by the shell with a document path from the command line or the
## home screen.
func open_argument(_path: String) -> void:
	pass


func request_quit() -> void:
	get_tree().quit()
