class_name ScenesPanel
extends VBoxContainer
## The scenes of the encounter: one per map level in play. Click to look at
## one; "Show" makes it the one the players see. TableWindow adds scenes
## (it owns the file dialogs); this panel asks for it.

signal add_requested

var ctx: TableContext
var list: ItemList
var _actions: Array = []
var _show_btn: Button
var _remove_btn: Button


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(i: int) -> void: ctx.set_scene(str(list.get_item_metadata(i))))
	list.item_activated.connect(func(i: int) -> void: ctx.commands.activate_scene(str(list.get_item_metadata(i))))
	add_child(list)
	var row := HBoxContainer.new()
	_show_btn = Button.new()
	_show_btn.text = "Show to players"
	_show_btn.tooltip_text = "Make this the scene the players see"
	_show_btn.pressed.connect(func() -> void:
		if ctx.scene_id != "":
			ctx.commands.activate_scene(ctx.scene_id))
	row.add_child(_show_btn)
	add_child(row)
	var add := Button.new()
	add.set_meta("icon", "file-plus")
	add.tooltip_text = "Add a map level as a scene"
	add.theme_type_variation = "ToolButton"
	add.pressed.connect(func() -> void: add_requested.emit())
	_remove_btn = Button.new()
	_remove_btn.set_meta("icon", "trash")
	_remove_btn.tooltip_text = "Remove this scene"
	_remove_btn.theme_type_variation = "ToolButton"
	_remove_btn.pressed.connect(func() -> void:
		if ctx.scene_id != "":
			ctx.commands.remove_scene(ctx.scene_id))
	_actions = [add, _remove_btn]
	ctx.encounter_changed.connect(refresh)
	ctx.scene_changed.connect(refresh)


func header_actions() -> Array:
	return _actions


func bind() -> void:
	ctx.encounter().changed.connect(func(what: String, _s: String) -> void:
		if what == "scenes" or what == "active_scene":
			refresh())
	refresh()


func refresh() -> void:
	list.clear()
	if ctx.state == null:
		return
	var e := ctx.encounter()
	for s in e.scenes:
		var active := str(s.id) == e.active_scene_id
		var i := list.add_item(("● " if active else "   ") + str(s.get("name", s.id)))
		list.set_item_metadata(i, str(s.id))
		list.set_item_tooltip(i, "%s — %s%s" % [str(s.get("map_path", "")), str(s.get("level", "")), "\nThe players see this scene" if active else ""])
		if str(s.id) == ctx.scene_id:
			list.select(i)
	_show_btn.disabled = ctx.scene_id == "" or ctx.scene_id == e.active_scene_id
	_remove_btn.disabled = ctx.scene_id == ""
