class_name DockPane
extends VBoxContainer
## A dock panel with a title bar: grip, title, and the pane's own action
## buttons. The title bar is the drag handle — dragging it hands the
## DockableContainer the same drag data its tabs produce, so a pane can be
## dropped onto another panel (to group) or onto an edge (to split) whether
## or not its tab bar is showing.

var title := ""
var content: Control
var header: PanelContainer
var _label: Label
var _grip: TextureRect
var _actions: HBoxContainer


func _init(p_title: String, p_content: Control, actions: Array = []) -> void:
	title = p_title
	name = p_title
	content = p_content
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	header = DockHeader.new()
	(header as DockHeader).pane = self
	header.theme_type_variation = "DockHeader"
	header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	header.tooltip_text = "Drag to move this panel: onto another panel to group, onto an edge to split"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_grip = TextureRect.new()
	_grip.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_grip)
	_label = Label.new()
	_label.text = p_title
	_label.theme_type_variation = "DockTitle"
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 2)
	for a in actions:
		_actions.add_child(a)
	row.add_child(_actions)
	header.add_child(row)
	add_child(header)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)


func restyle(t: Dictionary) -> void:
	_grip.texture = UiIcons.get_icon("grip-vertical", int(t.icon) - 4, Color(ThemeBuilder.c(t, "text_dim"), 0.8), float(t.stroke))
	for b in _actions.get_children():
		if b is Button and b.has_meta("icon"):
			(b as Button).icon = UiIcons.get_icon(str(b.get_meta("icon")), int(t.icon) - 2, ThemeBuilder.c(t, "text"), float(t.stroke))


## The DockableContainer this pane lives in, if any.
func dock() -> Node:
	var n := get_parent()
	while n != null and not (n is DockableContainer):
		n = n.get_parent()
	return n


## Drag data in the shape DockableContainer accepts from its own tabs:
## which tab of which panel is being moved. Panels hold reference controls
## pointing at the real child, so match on `reference_to`.
func drag_data() -> Variant:
	var d := dock()
	if d == null:
		return null
	for panel in d.find_children("*", "TabContainer", true, false):
		var tc := panel as TabContainer
		for i in tc.get_tab_count():
			var c := tc.get_tab_control(i)
			if c == self or (c != null and c.get("reference_to") == self):
				return {"type": "tabc_element", "tabc_element": i, "from_path": tc.get_path()}
	return null


class DockHeader extends PanelContainer:
	var pane: DockPane

	func _get_drag_data(_at: Vector2) -> Variant:
		var data = pane.drag_data()
		if data == null:
			return null
		var preview := Label.new()
		preview.text = pane.title
		preview.theme_type_variation = "DockTitle"
		var wrap := PanelContainer.new()
		wrap.theme_type_variation = "DockHeader"
		wrap.add_child(preview)
		wrap.modulate.a = 0.85
		set_drag_preview(wrap)
		return data
