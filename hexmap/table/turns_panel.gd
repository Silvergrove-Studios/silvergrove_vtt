class_name TurnsPanel
extends VBoxContainer
## Who may move, and in what order. Three modes: Free (anyone moves any
## token they can see), DM picks (tick the tokens whose players may move
## now), Ordered (a turn strategy — a ruleset plugin's, or plain "as
## listed" — runs the turns). A strategy has one of two shapes, and the
## panel draws whichever the encounter is in from its data: an ordered
## list stepped with Next, or a focus that the DM gives to a participant
## (the GM included) and that players ask for. The tokens that are "up"
## get a gold ring on the map.

var ctx: TableContext
var mode_select: OptionButton
var system_select: OptionButton
var list: Tree
var _round: Label
var _explain: Label
var _system_row: HBoxContainer
var _ordered_row: HBoxContainer
var _start: Button
var _next: Button
var _prev: Button
var _end: Button
var _actions: Array = []
var _items: Dictionary = {}
var _syncing := false

const MODES := ["free", "dm", "ordered"]
const MODE_LABELS := ["Free: anyone moves", "DM picks who moves", "Ordered turns"]
const EXPLAIN := {
	"free": "Players may move any token they can see. Good for exploration and roleplay.",
	"dm": "Tick the tokens whose players may move right now. Everyone else waits.",
	"ordered": "A turn strategy runs the turns; Next steps through them. Only the token whose turn it is may be moved by its player.",
	"focus": "No order: whoever holds the focus acts. Select a row and give it the focus; players may ask for it.",
}
const COL_NAME := 0
const COL_INFO := 1
const COL_CHECK := 2


func _init(p_ctx: TableContext) -> void:
	ctx = p_ctx
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mode_select = OptionButton.new()
	for l in MODE_LABELS:
		mode_select.add_item(l)
	mode_select.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			ctx.commands.set_turn_mode(MODES[i]))
	add_child(mode_select)
	_explain = Label.new()
	_explain.theme_type_variation = "DimLabel"
	_explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_explain)
	_system_row = HBoxContainer.new()
	var sl := Label.new()
	sl.text = "System"
	_system_row.add_child(sl)
	system_select = OptionButton.new()
	system_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	system_select.tooltip_text = "What decides the order: a game system plugin, or the list as you arrange it"
	system_select.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			ctx.commands.run({"t": "turns.set", "changes": {"system": str(system_select.get_item_metadata(i))}}, "Turn strategy"))
	_system_row.add_child(system_select)
	add_child(_system_row)
	_round = Label.new()
	_round.theme_type_variation = "DimLabel"
	add_child(_round)
	list = Tree.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.hide_root = true
	list.columns = 3
	list.set_column_expand(COL_NAME, true)
	list.set_column_expand(COL_INFO, false)
	list.set_column_expand(COL_CHECK, false)
	list.set_column_custom_minimum_width(COL_INFO, 60)
	list.set_column_custom_minimum_width(COL_CHECK, 28)
	list.item_selected.connect(func() -> void:
		var it := list.get_selected()
		if it != null and not _syncing:
			var id := str(it.get_metadata(COL_NAME))
			if not ctx.state.token(ctx.scene_id, id).is_empty():
				ctx.select_token(id))
	list.item_edited.connect(_on_check)
	add_child(list)
	_ordered_row = HBoxContainer.new()
	_start = Button.new()
	_start.text = "Start"
	_start.tooltip_text = "Order the tokens on this scene with the chosen system and begin"
	_start.pressed.connect(func() -> void: ctx.commands.start_turns(ctx.scene_id))
	_ordered_row.add_child(_start)
	_prev = Button.new()
	_prev.text = "Back"
	_prev.tooltip_text = "Previous turn"
	_prev.pressed.connect(func() -> void: ctx.commands.previous_turn())
	_ordered_row.add_child(_prev)
	_next = Button.new()
	_next.text = "Next turn"
	_next.theme_type_variation = "AccentButton"
	_next.pressed.connect(func() -> void:
		if _focus_shape():
			_give_focus()
		else:
			ctx.commands.next_turn())
	_ordered_row.add_child(_next)
	_end = Button.new()
	_end.text = "End"
	_end.pressed.connect(func() -> void: ctx.commands.stop_turns())
	_ordered_row.add_child(_end)
	add_child(_ordered_row)
	var earlier := Button.new()
	earlier.set_meta("icon", "chevron-up")
	earlier.tooltip_text = "Move the selected token earlier in the order"
	earlier.theme_type_variation = "ToolButton"
	earlier.pressed.connect(func() -> void: _shift(-1))
	var later := Button.new()
	later.set_meta("icon", "chevron-down")
	later.tooltip_text = "Move the selected token later in the order"
	later.theme_type_variation = "ToolButton"
	later.pressed.connect(func() -> void: _shift(1))
	_actions = [earlier, later]
	ctx.encounter_changed.connect(refresh)
	ctx.scene_changed.connect(refresh)


func header_actions() -> Array:
	return _actions


func bind() -> void:
	ctx.encounter().changed.connect(func(what: String, _s: String) -> void:
		if what == "turns" or what == "tokens":
			refresh())
	refresh()


func mode() -> String:
	return str(ctx.encounter().turns.get("mode", "free")) if ctx.state != null else "free"


func _focus_shape() -> bool:
	return ctx.state != null and str(ctx.encounter().turns.get("strategy", "ordered")) == "focus"


## Focus shape: the selected row gets the focus (the GM row included).
func _give_focus() -> void:
	var it := list.get_selected()
	if it == null or ctx.kernel == null:
		return
	var ref := str(it.get_metadata(COL_INFO))
	if ref == "":
		return
	var why := ctx.kernel.turns.set_focus(ref, "gm")
	if why != "":
		ctx.status.emit(why)


## The strategies the DM may pick: the kernel's (plugins and the list),
## or, without a kernel, the legacy turn systems.
func _strategies() -> Array:
	if ctx.kernel != null:
		var out := []
		for id in ctx.kernel.turns.strategies:
			var sp: Dictionary = ctx.kernel.turns.strategies[id]
			out.append({"id": str(id), "name": str(sp.get("name", id)), "description": str(sp.get("description", "")) + (" (focus)" if str(sp.get("shape", "")) == "focus" else "")})
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id if a.id != "list" and b.id != "list" else a.id == "list")
		return out
	var out := []
	for sys in TurnSystem.all_systems():
		out.append({"id": (sys as TurnSystem).id, "name": (sys as TurnSystem).name, "description": (sys as TurnSystem).description})
	return out


func _on_check() -> void:
	var it := list.get_edited()
	if it == null or list.get_edited_column() != COL_CHECK:
		return
	ctx.commands.toggle_active_token(str(it.get_metadata(COL_NAME)))


func _shift(by: int) -> void:
	var it := list.get_selected()
	if it == null:
		return
	var order: Array = (ctx.encounter().turns.get("order", []) as Array).duplicate()
	var i := order.find(str(it.get_metadata(COL_NAME)))
	var j := i + by
	if i < 0 or j < 0 or j >= order.size():
		return
	var tmp = order[i]
	order[i] = order[j]
	order[j] = tmp
	ctx.commands.set_turn_order(order)


func _holder_name(ref: String) -> String:
	if ref == "gm":
		return "the GM"
	if ref.begins_with("token:"):
		var tk := ctx.state.find_token(ref.substr(6))
		return str(tk.get("name", ref)) if not tk.is_empty() else ref
	if ref.begins_with("actor:"):
		return str(ctx.encounter().actor(ref.substr(6)).get("name", ref))
	return "nobody"


func refresh() -> void:
	if ctx.state == null:
		return
	_syncing = true
	var turns := ctx.encounter().turns
	var m := mode()
	mode_select.select(MODES.find(m))
	_explain.text = EXPLAIN[m]
	_system_row.visible = m == "ordered"
	_ordered_row.visible = m == "ordered"
	for a in _actions:
		(a as Button).visible = m == "ordered"
	system_select.clear()
	var i := 0
	for sp in _strategies():
		system_select.add_item(str(sp.name))
		system_select.set_item_metadata(i, str(sp.id))
		system_select.set_item_tooltip(i, str(sp.description))
		if str(sp.id) == str(turns.get("system", "list")):
			system_select.select(i)
		i += 1
	list.clear()
	_items.clear()
	var root := list.create_item()
	var running := bool(turns.get("running", false))
	var current := ctx.state.current_turn_token()
	match m:
		"free":
			_round.text = ""
		"dm":
			_round.text = "Ticked tokens may be moved by their players"
			var active: Array = turns.get("active", [])
			for tk in ctx.state.tokens(ctx.scene_id):
				var it := list.create_item(root)
				it.set_text(COL_NAME, str(tk.get("name", "")))
				it.set_metadata(COL_NAME, str(tk.id))
				var owner := ""
				if tk.get("owner", null) != null:
					owner = str(ctx.encounter().player(str(tk.owner)).get("name", ""))
				it.set_text(COL_INFO, owner)
				it.set_cell_mode(COL_CHECK, TreeItem.CELL_MODE_CHECK)
				it.set_editable(COL_CHECK, true)
				it.set_checked(COL_CHECK, active.has(str(tk.id)))
				_items[str(tk.id)] = it
		"ordered" when _focus_shape() and running:
			_explain.text = EXPLAIN["focus"]
			var focus := str(turns.get("focus", ""))
			var requests := {}
			for r in turns.get("requests", []):
				requests[str(r.get("ref", ""))] = str(ctx.encounter().player(str(r.get("player", ""))).get("name", "someone"))
			_round.text = "Focus: " + _holder_name(focus)
			var gm := list.create_item(root)
			gm.set_text(COL_NAME, ("▶ " if focus == "gm" else "   ") + "The GM")
			gm.set_metadata(COL_NAME, "")
			gm.set_metadata(COL_INFO, "gm")
			for tk in ctx.state.tokens(ctx.scene_id):
				var ref := "token:" + str(tk.id)
				var it := list.create_item(root)
				it.set_text(COL_NAME, ("▶ " if focus == ref else "   ") + str(tk.get("name", "")))
				it.set_metadata(COL_NAME, str(tk.id))
				it.set_metadata(COL_INFO, ref)
				it.set_text(COL_INFO, "asks" if requests.has(ref) else "")
				if requests.has(ref):
					it.set_tooltip_text(COL_INFO, "%s asks for the focus" % requests[ref])
				if bool(tk.get("hidden", false)):
					it.set_custom_color(COL_NAME, Color(0.6, 0.6, 0.6))
				_items[str(tk.id)] = it
			_next.text = "Give focus"
			_next.disabled = false
			_prev.visible = false
			_end.disabled = false
			_start.text = "Restart"
		"ordered":
			_next.text = "Next turn"
			_prev.visible = true
			var order: Array = turns.get("order", [])
			_round.text = "Round %d" % int(turns.get("round", 1)) if running else ("Press Start to order the tokens" if order.is_empty() else "Paused")
			for id in order:
				var tk := ctx.state.token(ctx.scene_id, str(id))
				var it := list.create_item(root)
				var p_name := str(tk.get("name", "")) if not tk.is_empty() else "(on another scene)"
				it.set_text(COL_NAME, ("▶ " if str(id) == current else "   ") + p_name)
				it.set_metadata(COL_NAME, str(id))
				it.set_text(COL_INFO, str(turns.get("data", {}).get("labels", {}).get(str(id), "")))
				if not tk.is_empty() and bool(tk.get("hidden", false)):
					it.set_custom_color(COL_NAME, Color(0.6, 0.6, 0.6))
				_items[str(id)] = it
			_next.disabled = order.is_empty()
			_prev.disabled = order.is_empty() or not running
			_end.disabled = not running
			_start.text = "Restart" if not order.is_empty() else "Start"
	_syncing = false
