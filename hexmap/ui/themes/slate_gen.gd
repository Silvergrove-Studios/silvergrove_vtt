@tool
extends ProgrammaticTheme
## ThemeGen sample: the Slate look written in ThemeGen's DSL. Generates
## hexmap/ui/themes/generated/slate_gen.tres. Compare with
## hexmap/ui/theme_builder.gd, which builds the same theme directly.
##
## Run: ./run.sh gen-theme   (or File → Run on this script in the editor)

const UPDATE_ON_SAVE = true

var bg: Color
var deep: Color
var surface: Color
var hover: Color
var pressed: Color
var border: Color
var border_strong: Color
var text: Color
var dim: Color
var disabled: Color
var accent: Color
var accent_soft: Color
var r := 6
var sp := 8


func setup() -> void:
	set_save_path("res://hexmap/ui/themes/generated/slate_gen.tres")
	bg = Color("#202124")
	deep = Color("#18191c")
	surface = Color("#2a2b30")
	hover = Color("#34363c")
	pressed = Color("#3d4048")
	border = Color("#33353b")
	border_strong = Color("#45484f")
	text = Color("#e6e6e9")
	dim = Color("#a2a5ad")
	disabled = Color("#5d6068")
	accent = Color("#5b9cf6")
	accent_soft = Color(accent, 0.22)


func define_theme() -> void:
	define_default_font(load("res://hexmap/ui/fonts/Inter-Regular.ttf") if ResourceLoader.exists("res://hexmap/ui/fonts/Inter-Regular.ttf") else ThemeDB.fallback_font)
	define_default_font_size(13)

	# Reusable style fragments. `inherit` chains them; `content_margins` etc.
	# are ThemeGen helpers that expand to the four StyleBoxFlat properties.
	var flat: Dictionary = stylebox_flat({corner_radius_ = corner_radius(r), anti_aliasing = true, corner_detail = 6})
	var padded: Dictionary = inherit(flat, {content_margins_ = content_margins(sp * 1.25, sp * 0.6)})
	var raised: Dictionary = inherit(padded, {bg_color = surface, border_width_ = border_width(1), border_color = border})
	var raised_hover: Dictionary = inherit(raised, {bg_color = hover, border_color = border_strong})
	var raised_pressed: Dictionary = inherit(raised, {bg_color = accent_soft, border_color = accent})
	var input: Dictionary = inherit(flat, {bg_color = deep, border_width_ = border_width(1), border_color = border, content_margins_ = content_margins(sp, sp * 0.55)})

	define_style("Panel", {panel = stylebox_flat({bg_color = bg})})
	define_style("PanelContainer", {panel = stylebox_flat({bg_color = bg})})
	define_style("Label", {font_color = text})
	define_variant_style("HeaderLabel", "Label", {font_size = 15, font_color = text})
	define_variant_style("DimLabel", "Label", {font_size = 11, font_color = dim})
	define_variant_style("MonoLabel", "Label", {font_size = 12, font_color = dim})

	define_style("Button", {
		normal = raised, hover = raised_hover, pressed = raised_pressed, hover_pressed = raised_pressed,
		disabled = inherit(raised, {bg_color = Color(surface, 0.5)}), focus = stylebox_empty({}),
		font_color = text, font_hover_color = text, font_pressed_color = text, font_disabled_color = disabled,
		icon_normal_color = text, icon_pressed_color = accent, icon_hover_pressed_color = accent,
	})
	define_variant_style("ToolButton", "Button", {
		normal = inherit(flat, {bg_color = Color(0, 0, 0, 0), content_margins_ = content_margins(sp * 0.75, sp * 0.6)}),
		hover = inherit(flat, {bg_color = hover, content_margins_ = content_margins(sp * 0.75, sp * 0.6)}),
		pressed = inherit(flat, {bg_color = accent_soft, border_width_ = border_width(1), border_color = accent, content_margins_ = content_margins(sp * 0.75, sp * 0.6)}),
	})
	for kind in ["OptionButton", "MenuButton", "ColorPickerButton"]:
		define_style(kind, {normal = raised, hover = raised_hover, pressed = inherit(raised, {bg_color = pressed}), focus = stylebox_empty({}),
			font_color = text, font_hover_color = text, font_pressed_color = text})
	define_style("LineEdit", {normal = input, focus = inherit(input, {border_color = accent}), font_color = text, font_placeholder_color = disabled, caret_color = accent, selection_color = accent_soft})
	define_style("TextEdit", {normal = input, focus = inherit(input, {border_color = accent}), font_color = text, caret_color = accent, selection_color = accent_soft})
	define_style("CheckBox", {font_color = text, font_hover_color = text, font_pressed_color = text})

	var tab_pad: Dictionary = content_margins(sp * 1.25, sp * 0.7)
	define_style("TabContainer", {
		tab_selected = stylebox_flat({bg_color = surface, corner_radius_ = corner_radius(r, r, 0, 0), border_width_ = border_width(0, 0, 0, 2), border_color = accent, content_margins_ = tab_pad}),
		tab_unselected = stylebox_flat({bg_color = Color(0, 0, 0, 0), content_margins_ = tab_pad}),
		tab_hovered = stylebox_flat({bg_color = hover, corner_radius_ = corner_radius(r, r, 0, 0), content_margins_ = tab_pad}),
		panel = stylebox_flat({bg_color = bg, content_margins_ = content_margins(sp * 0.5)}),
		tabbar_background = stylebox_flat({bg_color = deep}),
		font_selected_color = text, font_unselected_color = dim, font_hovered_color = text,
	})
	var list_panel: Dictionary = inherit(flat, {bg_color = deep, border_width_ = border_width(1), border_color = border, content_margins_ = content_margins(sp * 0.5)})
	var selected: Dictionary = stylebox_flat({bg_color = accent_soft, corner_radius_ = corner_radius(4)})
	var hovered: Dictionary = stylebox_flat({bg_color = hover, corner_radius_ = corner_radius(4)})
	define_style("ItemList", {panel = list_panel, selected = selected, selected_focus = selected, hovered = hovered, focus = stylebox_empty({}),
		font_color = text, font_selected_color = text, font_hovered_color = text, guide_color = Color(0, 0, 0, 0), v_separation = 6})
	define_style("Tree", {panel = list_panel, selected = selected, selected_focus = selected, hovered = hovered, focus = stylebox_empty({}),
		font_color = text, font_selected_color = text, font_hovered_color = text, guide_color = Color(border_strong, 0.5),
		relationship_line_color = Color(border_strong, 0.7), draw_relationship_lines = 1, draw_guides = 0, v_separation = 4, item_margin = 12})
	define_style("MenuBar", {normal = stylebox_empty({content_margins_ = content_margins(sp, sp * 0.5)}),
		hover = stylebox_flat({bg_color = hover, corner_radius_ = corner_radius(r), content_margins_ = content_margins(sp, sp * 0.5)}),
		pressed = stylebox_flat({bg_color = pressed, corner_radius_ = corner_radius(r), content_margins_ = content_margins(sp, sp * 0.5)}),
		font_color = text, font_hover_color = text, font_pressed_color = text})
	define_style("PopupMenu", {panel = inherit(flat, {bg_color = surface, border_width_ = border_width(1), border_color = border_strong, content_margins_ = content_margins(sp * 0.5)}),
		hover = stylebox_flat({bg_color = accent_soft, corner_radius_ = corner_radius(4)}),
		separator = stylebox_line({color = Color(border_strong, 0.8), thickness = 1, content_margins_ = content_margins(0, sp * 0.5)}),
		font_color = text, font_hover_color = text, font_disabled_color = disabled, font_accelerator_color = dim, v_separation = 4, item_start_padding = sp, item_end_padding = sp})
	define_style("Window", {embedded_border = inherit(flat, {bg_color = bg, border_width_ = border_width(1), border_color = border_strong, corner_radius_ = corner_radius(9), content_margins_ = content_margins(sp)}), title_color = text})
	define_style("AcceptDialog", {panel = inherit(flat, {bg_color = bg, border_width_ = border_width(1), border_color = border_strong, corner_radius_ = corner_radius(9), content_margins_ = content_margins(sp * 2)})})
	for kind in ["HSplitContainer", "VSplitContainer"]:
		define_style(kind, {separation = 6, minimum_grab_thickness = 8, autohide = 1})
	for kind in ["VScrollBar", "HScrollBar"]:
		define_style(kind, {scroll = stylebox_empty({content_margins_ = content_margins(2)}), grabber = stylebox_flat({bg_color = Color(border_strong, 0.8), corner_radius_ = corner_radius(4)}),
			grabber_highlight = stylebox_flat({bg_color = dim, corner_radius_ = corner_radius(4)}), grabber_pressed = stylebox_flat({bg_color = accent, corner_radius_ = corner_radius(4)})})
	define_style("TooltipPanel", {panel = inherit(flat, {bg_color = deep.lightened(0.06), border_width_ = border_width(1), border_color = border_strong, content_margins_ = content_margins(sp, sp * 0.6)})})
	define_style("TooltipLabel", {font_color = text, font_size = 12})
