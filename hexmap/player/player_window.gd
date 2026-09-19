class_name PlayerWindow
extends Control
## The Player: joins a table and shows the map from the player's tokens' eyes.
## Runs on every platform, so nothing here may assume a mouse, a keyboard, a
## file dialog or a menu bar. Not built yet; this is the mode's front door so
## the shell can route to it.

signal go_home

var app: App


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = app.build_theme()
	app.theme_changed.connect(func(_n: String) -> void: theme = app.build_theme())
	get_window().title = "Player — " + App.NAME
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	bg.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var l := Label.new()
	l.text = "Player"
	l.theme_type_variation = "HeaderLabel"
	column.add_child(l)
	var d := Label.new()
	d.text = "Joining a table is not built yet."
	d.theme_type_variation = "DimLabel"
	column.add_child(d)
	var b := Button.new()
	b.text = "Home"
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(func() -> void: go_home.emit())
	column.add_child(b)


## Called by the shell with a table address from the command line or the
## home screen.
func open_argument(_address: String) -> void:
	pass


func request_quit() -> void:
	get_tree().quit()
