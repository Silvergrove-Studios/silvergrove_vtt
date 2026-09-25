class_name HomeScreen
extends Control
## The first screen: what people come to do — carry on with their campaign,
## run a game, join one, draw maps — and what they had open. Laid out for a
## finger as much as a mouse — big targets, one column, nothing that needs a
## hover or a right-click — because on a phone this is the Player's front
## door too. (Playtest 1: "Editor / Table / Player" meant nothing to a DM
## who came to run a game.)

signal open_mode(mode: String, arg: String)

const MODE_ICONS := {"editor": "pencil", "table": "hexagon", "player": "eye"}
## What each mode is for, in the words of someone who wants it.
const MODE_TEXT := {
	"table": ["Run a game", "Start an adventure or open your campaign: the party, the people, the places and the maps, on your screen and your players' phones."],
	"player": ["Join a game", "Play from your phone or laptop: the DM's table on this network, your character, your view of the map."],
	"editor": ["Draw maps", "Terrain, props, walls and lights, for your games; export to other VTTs and print."],
}
## Most wanted first; what this device cannot do goes last.
const MODE_ORDER := ["table", "player", "editor"]

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

	# the name in the display face, what it is for beneath (playtest 2: one
	# font for both read as unfinished)
	var title := Label.new()
	title.name = "Title"
	title.text = App.NAME
	title.theme_type_variation = "DisplayLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var tagline := Label.new()
	tagline.text = "Maps and games for your table"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)
	var sub := Label.new()
	sub.text = App.build_stamp()
	sub.theme_type_variation = "DimLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	column.add_child(gap)

	# the campaign last opened, one press away (U3: pick up where we left off)
	var last := last_campaign(app.recent())
	if last != "" and App.mode_available("table"):
		var cont := card("Continue “%s”" % campaign_title(last), "The campaign you had open last", "folder-open", true)
		cont.name = "Continue"
		cont.tooltip_text = last
		cont.pressed.connect(func() -> void: open_mode.emit("table", last))
		column.add_child(cont)

	var order: Array = MODE_ORDER.filter(func(m: String) -> bool: return App.mode_available(m)) + MODE_ORDER.filter(func(m: String) -> bool: return not App.mode_available(m))
	for m in order:
		var b := card(MODE_TEXT[m][0], MODE_TEXT[m][1], MODE_ICONS[m])
		b.name = "Mode_" + m
		b.disabled = not App.mode_available(m)
		if b.disabled:
			b.tooltip_text = "Not on this device"
		b.pressed.connect(func() -> void: open_mode.emit(m, ""))
		column.add_child(b)

	column.add_child(_scale_row())
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
		_file_list(column, "Example maps", examples)


## A card to press: an icon, a title in the display face and a line of
## what it does. (A button's own text is one font; this is two.)
static func card(title: String, text: String, icon := "", accent := false, picture: Texture2D = null) -> Button:
	var b := Button.new()
	b.theme_type_variation = "AccentButton" if accent else ""
	b.custom_minimum_size = Vector2(0, 96 if picture != null else 72)
	b.set_meta("title", title)
	b.set_meta("text", text)
	if "accessibility_name" in b:
		b.set("accessibility_name", "%s. %s" % [title, text])
	var pad := MarginContainer.new()
	pad.name = "Card"
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	b.add_child(pad)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	pad.add_child(row)
	if picture != null:
		# a cover: cropped to a small landscape, not stretched
		var pic := TextureRect.new()
		pic.name = "Cover"
		pic.texture = picture
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(128, 76)
		pic.clip_contents = true
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
	elif icon != "":
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.set_meta("icon", icon)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.custom_minimum_size = Vector2(28, 0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
	var words := VBoxContainer.new()
	words.name = "Words"
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	var t := Label.new()
	t.name = "Title"
	t.text = title
	t.theme_type_variation = "CardTitle"
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(t)
	var d := Label.new()
	d.name = "Text"
	d.text = text
	d.theme_type_variation = "DimLabel"
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(d)
	# as tall as its words need, once they have wrapped at its width
	var least := b.custom_minimum_size.y
	pad.minimum_size_changed.connect(func() -> void:
		b.custom_minimum_size.y = maxf(least, pad.get_combined_minimum_size().y))
	return b


## A card's words, "title\ntext" (for tests and tooltips).
static func card_text(b: Button) -> String:
	return "%s\n%s" % [str(b.get_meta("title", b.text)), str(b.get_meta("text", ""))]


## The most recent campaign still on disk, or "".
static func last_campaign(recent: Array) -> String:
	for p in recent:
		if str(p).ends_with(".campaign"):
			return str(p)
	return ""


## "our_chapel.campaign" → "Our Chapel".
static func campaign_title(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ").capitalize()


## "UI size  −  100%  +": the same preference every mode's View menu has.
func _scale_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = "UI size"
	l.theme_type_variation = "DimLabel"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var minus := Button.new()
	minus.text = "−"
	minus.custom_minimum_size = Vector2(44, 40)
	minus.pressed.connect(func() -> void: app.step_ui_scale(false))
	row.add_child(minus)
	var value := Label.new()
	value.name = "ScaleValue"
	value.text = App.scale_label(app.ui_scale)
	value.custom_minimum_size.x = 48
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(44, 40)
	plus.pressed.connect(func() -> void: app.step_ui_scale(true))
	row.add_child(plus)
	app.ui_scale_changed.connect(func(s: float) -> void:
		if is_instance_valid(value):
			value.text = App.scale_label(s))
	return row


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
		b.text = campaign_title(str(p)) + "  (campaign)" if str(p).ends_with(".campaign") else str(p).get_file()
		b.tooltip_text = str(p)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.theme_type_variation = "ToolButton"
		b.custom_minimum_size = Vector2(0, 40)
		var mode := "table" if (str(p).ends_with(".encounter") or str(p).ends_with(".campaign")) else "editor"
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
	restyle_cards(self, t)


## Cards in the theme's colours: their icons, and on an accent card its
## words in the accent's ink.
static func restyle_cards(under: Node, t: Dictionary) -> void:
	for pad in under.find_children("Card", "MarginContainer", true, false):
		var b := pad.get_parent() as Button
		if b == null:
			continue
		var on_accent := b.theme_type_variation == "AccentButton"
		var ink := ThemeBuilder.c(t, "accent_text") if on_accent else ThemeBuilder.c(t, "text")
		for ic in pad.find_children("Icon", "TextureRect", true, false):
			(ic as TextureRect).texture = UiIcons.get_icon(str(ic.get_meta("icon")), int(t.icon) + 8, ink, t.stroke)
		if on_accent:
			for l in pad.find_children("*", "Label", true, false):
				(l as Label).add_theme_color_override("font_color", ink if l.name == "Title" else Color(ink, 0.8))
