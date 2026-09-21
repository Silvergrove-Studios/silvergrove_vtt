class_name PlayersPanel
extends VBoxContainer
## Who is at the table. A player owns tokens and, when they connect, sees
## the scene through them. The colour rings their tokens.

var ctx: TableContext
var list: ItemList
var _actions: Array = []
var _name_edit: LineEdit
var _color: ColorPickerButton
## Player ids connected over the network right now.
var online: Dictionary = {}
## What a co-GM types to join, while hosting ("" otherwise), and how
## many have.
var cogm_code := ""
var cogm_count := 0
var _cogm: Label


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_activated.connect(_rename)
	add_child(list)
	var row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Player name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: _add())
	row.add_child(_name_edit)
	_color = ColorPickerButton.new()
	_color.edit_alpha = false
	_color.color = Color("#4f9cf6")
	_color.custom_minimum_size = Vector2(36, 0)
	row.add_child(_color)
	var add := Button.new()
	add.set_meta("icon", "plus")
	add.tooltip_text = "Add this player"
	add.pressed.connect(_add)
	row.add_child(add)
	add_child(row)
	_cogm = Label.new()
	_cogm.theme_type_variation = "DimLabel"
	_cogm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cogm.visible = false
	add_child(_cogm)
	var remove := Button.new()
	remove.set_meta("icon", "trash")
	remove.tooltip_text = "Remove the selected player (their tokens become the DM's)"
	remove.theme_type_variation = "ToolButton"
	remove.pressed.connect(_remove)
	_actions = [remove]
	ctx.encounter_changed.connect(refresh)


func header_actions() -> Array:
	return _actions


func bind() -> void:
	ctx.encounter().changed.connect(func(what: String, _s: String) -> void:
		if what == "players":
			refresh())
	refresh()


func _add() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		return
	ctx.commands.add_player(Encounter.new_player(n, "#" + _color.color.to_html(false)))
	_name_edit.text = ""
	# Next player gets a different default colour.
	_color.color = Color.from_hsv(fmod(_color.color.h + 0.31, 1.0), 0.6, 0.9)


func _remove() -> void:
	var sel := list.get_selected_items()
	if sel.is_empty():
		return
	var id := str(list.get_item_metadata(sel[0]))
	ctx.commands.begin_group()
	for s in ctx.encounter().scenes:
		for t in ctx.state.tokens(str(s.id)):
			if t.get("owner", null) != null and str(t.owner) == id:
				ctx.commands.update_token(str(s.id), str(t.id), {"owner": null})
	ctx.commands.remove_player(id)
	ctx.commands.end_group("Remove player")


func _rename(i: int) -> void:
	var id := str(list.get_item_metadata(i))
	var p := ctx.encounter().player(id)
	var d := ConfirmationDialog.new()
	d.title = "Rename player"
	var le := LineEdit.new()
	le.text = str(p.get("name", ""))
	d.add_child(le)
	d.register_text_enter(le)
	d.confirmed.connect(func() -> void:
		if le.text.strip_edges() != "":
			ctx.commands.update_player(id, {"name": le.text.strip_edges()}))
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	d.close_requested.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	le.grab_focus()


func refresh() -> void:
	list.clear()
	if ctx.state == null:
		return
	_cogm.visible = cogm_code != ""
	_cogm.text = "Co-GM code: %s%s" % [cogm_code, ("  (%d joined)" % cogm_count) if cogm_count > 0 else ""]
	_cogm.tooltip_text = "A second device joins with this code as a co-GM: the whole table, the GM's controls"
	for p in ctx.encounter().players:
		var owned := 0
		for s in ctx.encounter().scenes:
			owned += ctx.state.tokens_owned_by(str(s.id), str(p.id)).size()
		var i := list.add_item("%s%s  (%d token%s)" % ["● " if online.has(str(p.id)) else "", str(p.get("name", "")), owned, "" if owned == 1 else "s"])
		if online.has(str(p.id)):
			list.set_item_tooltip(i, "Connected")
		list.set_item_metadata(i, str(p.id))
		list.set_item_custom_fg_color(i, Color(str(p.get("color", "#ffffff"))))
