class_name ThemeBuilder
extends RefCounted
## Builds the editor Theme from a small set of design tokens, so the whole UI
## shares one palette, one spacing scale and one set of radii, and so a new
## look is a new token set rather than a new theme file. Fonts are Inter and
## JetBrains Mono (OFL, hexmap/ui/fonts/), icons are Lucide (UiIcons).

const VARIANTS := {
	"slate": {
		"label": "Slate", "dark": true,
		"bg": "#202124", "bg_deep": "#18191c", "canvas": "#131416",
		"surface": "#2a2b30", "surface_hover": "#34363c", "surface_pressed": "#3d4048",
		"border": "#33353b", "border_strong": "#45484f",
		"text": "#e6e6e9", "text_dim": "#a2a5ad", "text_disabled": "#5d6068",
		"accent": "#5b9cf6", "accent_text": "#0b1730", "shadow": "#00000099",
		"radius": 6, "spacing": 8, "font_size": 13, "icon": 18, "stroke": 1.8,
	},
	"forge": {
		"label": "Forge", "dark": true,
		"bg": "#1a1614", "bg_deep": "#120f0d", "canvas": "#0d0b0a",
		"surface": "#26201c", "surface_hover": "#322a25", "surface_pressed": "#3d332c",
		"border": "#31292397", "border_strong": "#4a3e35",
		"text": "#eee4d6", "text_dim": "#a8998a", "text_disabled": "#5c5049",
		"accent": "#e0a040", "accent_text": "#1a1208", "shadow": "#000000bb",
		"radius": 8, "spacing": 8, "font_size": 13, "icon": 20, "stroke": 1.75,
	},
	"studio": {
		"label": "Studio", "dark": true,
		"bg": "#3a3a3a", "bg_deep": "#2d2d2d", "canvas": "#262626",
		"surface": "#474747", "surface_hover": "#525252", "surface_pressed": "#5c5c5c",
		"border": "#2a2a2a", "border_strong": "#5a5a5a",
		"text": "#f0f0f0", "text_dim": "#b8b8b8", "text_disabled": "#777777",
		"accent": "#3fb8af", "accent_text": "#06211f", "shadow": "#00000088",
		"radius": 3, "spacing": 6, "font_size": 12, "icon": 16, "stroke": 2.0,
	},
	"parchment": {
		"label": "Parchment", "dark": false,
		"bg": "#f1eadb", "bg_deep": "#e6dcc8", "canvas": "#d8cdb6",
		"surface": "#faf5ea", "surface_hover": "#ffffff", "surface_pressed": "#e9dfcc",
		"border": "#d3c6ad", "border_strong": "#b9a98c",
		"text": "#2b2620", "text_dim": "#5a4e42", "text_disabled": "#9a8d7c",
		"accent": "#a33a2f", "accent_text": "#fff7ee", "shadow": "#3a2a1a66",
		"radius": 5, "spacing": 8, "font_size": 13, "icon": 18, "stroke": 1.8,
	},
}

static var _fonts: Dictionary = {}


static func names() -> PackedStringArray:
	return PackedStringArray(VARIANTS.keys())


static func tokens(name: String) -> Dictionary:
	return VARIANTS.get(name, VARIANTS.slate)


static func font(file: String) -> Font:
	if _fonts.has(file):
		return _fonts[file]
	var path := ProjectSettings.globalize_path("res://hexmap/ui/fonts").path_join(file)
	var f := FontFile.new()
	if FileAccess.file_exists(path) and f.load_dynamic_font(path) == OK:
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		_fonts[file] = f
		return f
	_fonts[file] = ThemeDB.fallback_font
	return ThemeDB.fallback_font


static func c(t: Dictionary, key: String) -> Color:
	return Color(str(t[key]))


static func box(fill: Color, radius: float, border := Color(0, 0, 0, 0), border_w := 0, pad := Vector2(8, 4)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(int(radius))
	s.corner_detail = 6
	s.anti_aliasing = true
	if border_w > 0:
		s.set_border_width_all(border_w)
		s.border_color = border
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s


static func empty(pad := Vector2.ZERO) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s


static func build(name: String) -> Theme:
	var t := tokens(name)
	var th := Theme.new()
	var r: float = t.radius
	var sp: float = t.spacing
	var fs: int = t.font_size
	var bg := c(t, "bg")
	var deep := c(t, "bg_deep")
	var surface := c(t, "surface")
	var hover := c(t, "surface_hover")
	var pressed := c(t, "surface_pressed")
	var border := c(t, "border")
	var border_strong := c(t, "border_strong")
	var text := c(t, "text")
	var dim := c(t, "text_dim")
	var disabled := c(t, "text_disabled")
	var accent := c(t, "accent")
	var accent_text := c(t, "accent_text")
	var accent_soft := Color(accent, 0.22)

	th.default_font = font("Inter-Regular.ttf")
	th.default_font_size = fs
	var medium := font("Inter-Medium.ttf")
	var semibold := font("Inter-SemiBold.ttf")
	var mono := font("JetBrainsMono-Regular.ttf")

	# --- Panels ------------------------------------------------------------
	th.set_stylebox("panel", "Panel", box(bg, 0))
	th.set_stylebox("panel", "PanelContainer", box(bg, 0))
	th.set_stylebox("panel", "PopupPanel", box(surface, r, border_strong, 1, Vector2(sp, sp)))
	th.set_stylebox("panel", "TooltipPanel", box(deep.lightened(0.06) if t.dark else Color("#2b2620"), r, border_strong, 1, Vector2(sp, sp * 0.6)))
	th.set_color("font_color", "TooltipLabel", text if t.dark else Color("#f1eadb"))
	th.set_font_size("font_size", "TooltipLabel", fs - 1)

	# --- Labels ------------------------------------------------------------
	th.set_color("font_color", "Label", text)
	th.set_font("font", "HeaderLabel", semibold)
	th.set_font_size("font_size", "HeaderLabel", fs + 2)
	th.set_color("font_color", "HeaderLabel", text)
	th.set_type_variation("HeaderLabel", "Label")
	th.set_font("font", "DimLabel", th.default_font)
	th.set_font_size("font_size", "DimLabel", fs - 2)
	th.set_color("font_color", "DimLabel", dim)
	th.set_type_variation("DimLabel", "Label")
	th.set_font("font", "MonoLabel", mono)
	th.set_font_size("font_size", "MonoLabel", fs - 1)
	th.set_color("font_color", "MonoLabel", dim)
	th.set_type_variation("MonoLabel", "Label")

	# --- Buttons -----------------------------------------------------------
	var pad := Vector2(sp * 1.25, sp * 0.6)
	th.set_stylebox("normal", "Button", box(surface, r, border, 1, pad))
	th.set_stylebox("hover", "Button", box(hover, r, border_strong, 1, pad))
	th.set_stylebox("pressed", "Button", box(accent_soft, r, accent, 1, pad))
	th.set_stylebox("hover_pressed", "Button", box(Color(accent, 0.3), r, accent, 1, pad))
	th.set_stylebox("disabled", "Button", box(Color(surface, 0.5), r, Color(border, 0.5), 1, pad))
	th.set_stylebox("focus", "Button", empty())
	th.set_color("font_color", "Button", text)
	th.set_color("font_hover_color", "Button", text)
	th.set_color("font_pressed_color", "Button", text)
	th.set_color("font_hover_pressed_color", "Button", text)
	th.set_color("font_disabled_color", "Button", disabled)
	th.set_color("icon_normal_color", "Button", text)
	th.set_color("icon_hover_color", "Button", text)
	th.set_color("icon_pressed_color", "Button", accent if t.dark else accent)
	th.set_color("icon_hover_pressed_color", "Button", accent)
	th.set_color("icon_disabled_color", "Button", disabled)
	th.set_constant("h_separation", "Button", int(sp * 0.75))
	# Flat tool/icon buttons
	th.set_type_variation("ToolButton", "Button")
	th.set_stylebox("normal", "ToolButton", box(Color(surface, 0.0), r, Color(0, 0, 0, 0), 0, Vector2(sp * 0.75, sp * 0.6)))
	th.set_stylebox("hover", "ToolButton", box(hover, r, Color(0, 0, 0, 0), 0, Vector2(sp * 0.75, sp * 0.6)))
	th.set_stylebox("pressed", "ToolButton", box(accent_soft, r, accent, 1, Vector2(sp * 0.75, sp * 0.6)))
	th.set_stylebox("hover_pressed", "ToolButton", box(Color(accent, 0.3), r, accent, 1, Vector2(sp * 0.75, sp * 0.6)))
	th.set_stylebox("disabled", "ToolButton", empty(Vector2(sp * 0.75, sp * 0.6)))
	# Primary (accent) button
	th.set_type_variation("AccentButton", "Button")
	th.set_stylebox("normal", "AccentButton", box(accent, r, accent, 1, pad))
	th.set_stylebox("hover", "AccentButton", box(accent.lightened(0.1), r, accent, 1, pad))
	th.set_stylebox("pressed", "AccentButton", box(accent.darkened(0.1), r, accent, 1, pad))
	th.set_color("font_color", "AccentButton", accent_text)
	th.set_color("font_hover_color", "AccentButton", accent_text)
	th.set_color("font_pressed_color", "AccentButton", accent_text)

	for kind in ["OptionButton", "MenuButton", "ColorPickerButton"]:
		th.set_stylebox("normal", kind, box(surface, r, border, 1, pad))
		th.set_stylebox("hover", kind, box(hover, r, border_strong, 1, pad))
		th.set_stylebox("pressed", kind, box(pressed, r, border_strong, 1, pad))
		th.set_stylebox("disabled", kind, box(Color(surface, 0.5), r, Color(border, 0.5), 1, pad))
		th.set_stylebox("focus", kind, empty())
		th.set_color("font_color", kind, text)
		th.set_color("font_hover_color", kind, text)
		th.set_color("font_pressed_color", kind, text)
		th.set_color("font_disabled_color", kind, disabled)
	th.set_icon("arrow", "OptionButton", UiIcons.get_icon("chevron-down", t.icon - 4, dim, t.stroke))
	th.set_constant("arrow_margin", "OptionButton", int(sp * 0.75))

	# CheckBox / CheckButton
	var check_on := UiIcons.get_icon("check", t.icon, accent_text, 2.6)
	var box_on := _check_box(t.icon, accent, accent, r * 0.5, check_on)
	var box_off := _check_box(t.icon, Color(surface, 1.0), border_strong, r * 0.5, null)
	th.set_icon("checked", "CheckBox", box_on)
	th.set_icon("unchecked", "CheckBox", box_off)
	th.set_icon("checked_disabled", "CheckBox", box_on)
	th.set_icon("unchecked_disabled", "CheckBox", box_off)
	th.set_stylebox("normal", "CheckBox", empty(Vector2(2, 2)))
	th.set_stylebox("hover", "CheckBox", empty(Vector2(2, 2)))
	th.set_stylebox("pressed", "CheckBox", empty(Vector2(2, 2)))
	th.set_stylebox("hover_pressed", "CheckBox", empty(Vector2(2, 2)))
	th.set_stylebox("disabled", "CheckBox", empty(Vector2(2, 2)))
	th.set_stylebox("focus", "CheckBox", empty())
	th.set_color("font_color", "CheckBox", text)
	th.set_color("font_hover_color", "CheckBox", text)
	th.set_color("font_pressed_color", "CheckBox", text)
	th.set_color("font_hover_pressed_color", "CheckBox", text)

	# --- Inputs ------------------------------------------------------------
	var in_pad := Vector2(sp, sp * 0.55)
	for kind in ["LineEdit", "TextEdit"]:
		th.set_stylebox("normal", kind, box(deep, r, border, 1, in_pad))
		th.set_stylebox("focus", kind, box(deep, r, accent, 1, in_pad))
		th.set_stylebox("read_only", kind, box(Color(deep, 0.6), r, border, 1, in_pad))
		th.set_color("font_color", kind, text)
		th.set_color("font_placeholder_color", kind, disabled)
		th.set_color("caret_color", kind, accent)
		th.set_color("selection_color", kind, accent_soft)
	th.set_color("font_uneditable_color", "LineEdit", dim)
	th.set_color("font_readonly_color", "TextEdit", dim)
	th.set_color("clear_button_color", "LineEdit", dim)
	th.set_icon("clear", "LineEdit", UiIcons.get_icon("x", t.icon - 4, dim, t.stroke))
	th.set_icon("updown", "SpinBox", UiIcons.get_icon("chevron-down", t.icon - 6, dim, t.stroke))
	th.set_stylebox("up_background", "SpinBox", empty())
	th.set_stylebox("down_background", "SpinBox", empty())
	th.set_stylebox("up_background_hovered", "SpinBox", box(hover, r * 0.5))
	th.set_stylebox("down_background_hovered", "SpinBox", box(hover, r * 0.5))
	th.set_stylebox("up_background_pressed", "SpinBox", box(pressed, r * 0.5))
	th.set_stylebox("down_background_pressed", "SpinBox", box(pressed, r * 0.5))
	th.set_stylebox("field_and_buttons_separator", "SpinBox", empty())
	th.set_stylebox("up_down_buttons_separator", "SpinBox", empty())
	th.set_icon("up", "SpinBox", UiIcons.get_icon("plus", t.icon - 6, dim, t.stroke))
	th.set_icon("down", "SpinBox", UiIcons.get_icon("minus", t.icon - 6, dim, t.stroke))
	th.set_icon("up_hover", "SpinBox", UiIcons.get_icon("plus", t.icon - 6, text, t.stroke))
	th.set_icon("down_hover", "SpinBox", UiIcons.get_icon("minus", t.icon - 6, text, t.stroke))
	th.set_icon("up_pressed", "SpinBox", UiIcons.get_icon("plus", t.icon - 6, accent, t.stroke))
	th.set_icon("down_pressed", "SpinBox", UiIcons.get_icon("minus", t.icon - 6, accent, t.stroke))
	th.set_icon("up_disabled", "SpinBox", UiIcons.get_icon("plus", t.icon - 6, disabled, t.stroke))
	th.set_icon("down_disabled", "SpinBox", UiIcons.get_icon("minus", t.icon - 6, disabled, t.stroke))
	th.set_constant("buttons_width", "SpinBox", int(t.icon))

	# Sliders
	th.set_stylebox("slider", "HSlider", box(deep, r, border, 1, Vector2(0, 0)))
	th.set_stylebox("grabber_area", "HSlider", box(accent, r))
	th.set_stylebox("grabber_area_highlight", "HSlider", box(accent.lightened(0.1), r))
	th.set_icon("grabber", "HSlider", _dot(14, accent, surface))
	th.set_icon("grabber_highlight", "HSlider", _dot(16, accent.lightened(0.15), surface))
	th.set_icon("grabber_disabled", "HSlider", _dot(14, disabled, surface))
	th.set_constant("center_grabber", "HSlider", 0)
	th.set_constant("grabber_offset", "HSlider", 0)

	# --- Tabs / lists / tree -----------------------------------------------
	var tab_pad := Vector2(sp * 1.25, sp * 0.7)
	th.set_stylebox("tab_selected", "TabContainer", _tab(surface, r, accent, tab_pad))
	th.set_stylebox("tab_unselected", "TabContainer", _tab(Color(surface, 0.0), r, Color(0, 0, 0, 0), tab_pad))
	th.set_stylebox("tab_hovered", "TabContainer", _tab(hover, r, Color(0, 0, 0, 0), tab_pad))
	th.set_stylebox("tab_disabled", "TabContainer", _tab(Color(surface, 0.0), r, Color(0, 0, 0, 0), tab_pad))
	th.set_stylebox("tab_focus", "TabContainer", empty())
	th.set_stylebox("panel", "TabContainer", box(bg, 0, border, 0, Vector2(sp * 0.5, sp * 0.5)))
	th.set_stylebox("tabbar_background", "TabContainer", box(deep, 0))
	th.set_color("font_selected_color", "TabContainer", text)
	th.set_color("font_unselected_color", "TabContainer", dim)
	th.set_color("font_hovered_color", "TabContainer", text)
	th.set_color("font_disabled_color", "TabContainer", disabled)
	th.set_font("font", "TabContainer", medium)
	th.set_icon("increment", "TabContainer", UiIcons.get_icon("chevron-right", t.icon - 4, dim, t.stroke))
	th.set_icon("decrement", "TabContainer", UiIcons.get_icon("chevron-down", t.icon - 4, dim, t.stroke))

	th.set_stylebox("panel", "ItemList", box(deep, r, border, 1, Vector2(sp * 0.5, sp * 0.5)))
	th.set_stylebox("focus", "ItemList", empty())
	th.set_stylebox("selected", "ItemList", box(accent_soft, r * 0.75, accent, 1))
	th.set_stylebox("selected_focus", "ItemList", box(accent_soft, r * 0.75, accent, 1))
	th.set_stylebox("hovered", "ItemList", box(hover, r * 0.75))
	th.set_stylebox("hovered_selected", "ItemList", box(Color(accent, 0.3), r * 0.75, accent, 1))
	th.set_stylebox("hovered_selected_focus", "ItemList", box(Color(accent, 0.3), r * 0.75, accent, 1))
	th.set_stylebox("cursor", "ItemList", empty())
	th.set_stylebox("cursor_unfocused", "ItemList", empty())
	th.set_color("font_color", "ItemList", text)
	th.set_color("font_hovered_color", "ItemList", text)
	th.set_color("font_selected_color", "ItemList", text)
	th.set_color("font_hovered_selected_color", "ItemList", text)
	th.set_color("guide_color", "ItemList", Color(0, 0, 0, 0))
	th.set_font_size("font_size", "ItemList", fs - 1)
	th.set_constant("v_separation", "ItemList", int(sp * 0.75))
	th.set_constant("h_separation", "ItemList", int(sp * 0.5))
	th.set_constant("icon_margin", "ItemList", int(sp * 0.5))

	th.set_stylebox("panel", "Tree", box(deep, r, border, 1, Vector2(sp * 0.5, sp * 0.5)))
	th.set_stylebox("focus", "Tree", empty())
	th.set_stylebox("selected", "Tree", box(accent_soft, r * 0.75))
	th.set_stylebox("selected_focus", "Tree", box(accent_soft, r * 0.75))
	th.set_stylebox("hovered", "Tree", box(hover, r * 0.75))
	th.set_stylebox("hovered_dimmed", "Tree", box(Color(hover, 0.5), r * 0.75))
	th.set_stylebox("hovered_selected", "Tree", box(Color(accent, 0.3), r * 0.75))
	th.set_stylebox("hovered_selected_focus", "Tree", box(Color(accent, 0.3), r * 0.75))
	th.set_stylebox("cursor", "Tree", empty())
	th.set_stylebox("cursor_unfocused", "Tree", empty())
	th.set_stylebox("title_button_normal", "Tree", box(surface, 0, border, 1, Vector2(sp * 0.5, sp * 0.4)))
	th.set_stylebox("title_button_hover", "Tree", box(hover, 0, border, 1, Vector2(sp * 0.5, sp * 0.4)))
	th.set_stylebox("title_button_pressed", "Tree", box(pressed, 0, border, 1, Vector2(sp * 0.5, sp * 0.4)))
	th.set_stylebox("button_pressed", "Tree", box(accent_soft, r * 0.5))
	th.set_stylebox("custom_button", "Tree", empty())
	th.set_stylebox("custom_button_hover", "Tree", box(hover, r * 0.5))
	th.set_stylebox("custom_button_pressed", "Tree", box(pressed, r * 0.5))
	th.set_color("font_color", "Tree", text)
	th.set_color("font_hovered_color", "Tree", text)
	th.set_color("font_selected_color", "Tree", text)
	th.set_color("font_hovered_dimmed_color", "Tree", text)
	th.set_color("font_hovered_selected_color", "Tree", text)
	th.set_color("font_disabled_color", "Tree", disabled)
	th.set_color("title_button_color", "Tree", dim)
	th.set_color("guide_color", "Tree", Color(border_strong, 0.5))
	th.set_color("relationship_line_color", "Tree", Color(border_strong, 0.7))
	th.set_color("parent_hl_line_color", "Tree", Color(border_strong, 0.7))
	th.set_color("children_hl_line_color", "Tree", Color(border_strong, 0.5))
	th.set_color("drop_position_color", "Tree", accent)
	th.set_constant("draw_relationship_lines", "Tree", 1)
	th.set_constant("relationship_line_width", "Tree", 1)
	th.set_constant("parent_hl_line_width", "Tree", 1)
	th.set_constant("children_hl_line_width", "Tree", 1)
	th.set_constant("draw_guides", "Tree", 0)
	th.set_constant("v_separation", "Tree", int(sp * 0.5))
	th.set_constant("h_separation", "Tree", int(sp * 0.5))
	th.set_constant("item_margin", "Tree", int(sp * 1.5))
	th.set_constant("button_margin", "Tree", int(sp * 0.5))
	th.set_icon("arrow", "Tree", UiIcons.get_icon("chevron-down", t.icon - 4, dim, t.stroke))
	th.set_icon("arrow_collapsed", "Tree", UiIcons.get_icon("chevron-right", t.icon - 4, dim, t.stroke))
	th.set_icon("arrow_collapsed_mirrored", "Tree", UiIcons.get_icon("chevron-down", t.icon - 4, dim, t.stroke))
	th.set_icon("checked", "Tree", box_on)
	th.set_icon("unchecked", "Tree", box_off)
	th.set_icon("checked_disabled", "Tree", box_on)
	th.set_icon("unchecked_disabled", "Tree", box_off)

	# --- Menus -------------------------------------------------------------
	th.set_stylebox("normal", "MenuBar", empty(Vector2(sp, sp * 0.5)))
	th.set_stylebox("hover", "MenuBar", box(hover, r, Color(0, 0, 0, 0), 0, Vector2(sp, sp * 0.5)))
	th.set_stylebox("pressed", "MenuBar", box(pressed, r, Color(0, 0, 0, 0), 0, Vector2(sp, sp * 0.5)))
	th.set_stylebox("disabled", "MenuBar", empty(Vector2(sp, sp * 0.5)))
	th.set_stylebox("focus", "MenuBar", empty())
	th.set_color("font_color", "MenuBar", text)
	th.set_color("font_hover_color", "MenuBar", text)
	th.set_color("font_pressed_color", "MenuBar", text)
	th.set_color("font_hover_pressed_color", "MenuBar", text)
	th.set_color("font_disabled_color", "MenuBar", disabled)
	th.set_constant("h_separation", "MenuBar", int(sp * 0.5))
	th.set_stylebox("panel", "PopupMenu", box(surface, r, border_strong, 1, Vector2(sp * 0.5, sp * 0.5)))
	th.set_stylebox("hover", "PopupMenu", box(accent_soft, r * 0.75))
	th.set_stylebox("separator", "PopupMenu", _separator(Color(border_strong, 0.8), sp * 0.5))
	th.set_stylebox("labeled_separator_left", "PopupMenu", _separator(Color(border_strong, 0.8), sp * 0.5))
	th.set_stylebox("labeled_separator_right", "PopupMenu", _separator(Color(border_strong, 0.8), sp * 0.5))
	th.set_color("font_color", "PopupMenu", text)
	th.set_color("font_hover_color", "PopupMenu", text)
	th.set_color("font_disabled_color", "PopupMenu", disabled)
	th.set_color("font_accelerator_color", "PopupMenu", dim)
	th.set_color("font_separator_color", "PopupMenu", dim)
	th.set_constant("v_separation", "PopupMenu", int(sp * 0.5))
	th.set_constant("h_separation", "PopupMenu", int(sp * 1.5))
	th.set_constant("item_start_padding", "PopupMenu", int(sp))
	th.set_constant("item_end_padding", "PopupMenu", int(sp))
	th.set_icon("checked", "PopupMenu", box_on)
	th.set_icon("unchecked", "PopupMenu", box_off)
	th.set_icon("radio_checked", "PopupMenu", _dot(t.icon - 2, accent, surface))
	th.set_icon("radio_unchecked", "PopupMenu", _dot(t.icon - 2, Color(border_strong, 1.0), surface))
	th.set_icon("submenu", "PopupMenu", UiIcons.get_icon("chevron-right", t.icon - 4, dim, t.stroke))

	# --- Splits, scrollbars, separators, windows ---------------------------
	for kind in ["HSplitContainer", "VSplitContainer"]:
		th.set_constant("separation", kind, int(sp * 0.75))
		th.set_constant("minimum_grab_thickness", kind, int(sp))
		th.set_constant("autohide", kind, 1)
		th.set_stylebox("split_bar_background", kind, box(Color(0, 0, 0, 0), 0))
	th.set_icon("grabber", "HSplitContainer", _blank(1))
	th.set_icon("grabber", "VSplitContainer", _blank(1))
	th.set_stylebox("separator", "VSeparator", _separator(Color(border_strong, 0.8), sp * 0.5, true))
	th.set_stylebox("separator", "HSeparator", _separator(Color(border_strong, 0.8), sp * 0.5))
	for kind in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", kind, box(Color(deep, 0.0), 0, Color(0, 0, 0, 0), 0, Vector2(2, 2)))
		th.set_stylebox("scroll_focus", kind, empty())
		th.set_stylebox("grabber", kind, box(Color(border_strong, 0.8), 4))
		th.set_stylebox("grabber_highlight", kind, box(dim, 4))
		th.set_stylebox("grabber_pressed", kind, box(accent, 4))
		th.set_icon("increment", kind, _blank(1))
		th.set_icon("decrement", kind, _blank(1))
		th.set_icon("increment_highlight", kind, _blank(1))
		th.set_icon("decrement_highlight", kind, _blank(1))
		th.set_icon("increment_pressed", kind, _blank(1))
		th.set_icon("decrement_pressed", kind, _blank(1))
	th.set_stylebox("embedded_border", "Window", box(bg, r * 1.5, border_strong, 1, Vector2(sp, sp)))
	th.set_stylebox("embedded_unfocused_border", "Window", box(bg, r * 1.5, border, 1, Vector2(sp, sp)))
	th.set_color("title_color", "Window", text)
	th.set_font("title_font", "Window", semibold)
	th.set_font_size("title_font_size", "Window", fs + 1)
	th.set_constant("title_height", "Window", int(fs * 2.4))
	th.set_stylebox("panel", "AcceptDialog", box(bg, r * 1.5, border_strong, 1, Vector2(sp * 2, sp * 2)))
	th.set_constant("buttons_separation", "AcceptDialog", int(sp))
	th.set_stylebox("panel", "ScrollContainer", empty())
	th.set_constant("separation", "BoxContainer", int(sp * 0.5))
	th.set_constant("separation", "HBoxContainer", int(sp * 0.5))
	th.set_constant("separation", "VBoxContainer", int(sp * 0.5))
	th.set_constant("h_separation", "GridContainer", int(sp))
	th.set_constant("v_separation", "GridContainer", int(sp * 0.5))
	return th


static func _tab(fill: Color, r: float, underline: Color, pad: Vector2) -> StyleBoxFlat:
	var s := box(fill, r, Color(0, 0, 0, 0), 0, pad)
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	if underline.a > 0.0:
		s.border_width_bottom = 2
		s.border_color = underline
	return s


static func _separator(color: Color, margin: float, vertical := false) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = color
	s.thickness = 1
	s.vertical = vertical
	s.grow_begin = -margin * 0.5
	s.grow_end = -margin * 0.5
	if vertical:
		s.content_margin_left = margin
		s.content_margin_right = margin
	else:
		s.content_margin_top = margin
		s.content_margin_bottom = margin
	return s


static func _check_box(size: int, fill: Color, border: Color, radius: float, mark: Texture2D) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rr := int(radius)
	for y in size:
		for x in size:
			var inside := _in_round_rect(x, y, size, size, rr)
			if not inside:
				continue
			var edge := not _in_round_rect(x, y, size, size, rr, 1)
			img.set_pixel(x, y, border if edge else fill)
	if mark != null:
		var m := mark.get_image()
		var mi := m.duplicate()
		mi.convert(Image.FORMAT_RGBA8)
		var inner := int(size * 0.7)
		mi.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
		img.blend_rect(mi, Rect2i(Vector2i.ZERO, mi.get_size()), Vector2i((size - inner) / 2, (size - inner) / 2))
	return ImageTexture.create_from_image(img)


static func _in_round_rect(x: int, y: int, w: int, h: int, r: int, inset := 0) -> bool:
	var px := x + 0.5
	var py := y + 0.5
	if px < inset or py < inset or px > w - inset or py > h - inset:
		return false
	var rr := maxf(r - inset, 0.0)
	var cx := clampf(px, inset + rr, w - inset - rr)
	var cy := clampf(py, inset + rr, h - inset - rr)
	return Vector2(px - cx, py - cy).length() <= rr + 0.01


static func _dot(size: int, fill: Color, ring: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size / 2.0, size / 2.0)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= size / 2.0 - 0.5:
				img.set_pixel(x, y, ring if d > size / 2.0 - 2.5 else fill)
	return ImageTexture.create_from_image(img)


static func _blank(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
