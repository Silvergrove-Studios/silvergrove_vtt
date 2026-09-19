class_name UiIcons
extends RefCounted
## Lucide icons (ISC licence, hexmap/ui/icons/) rasterised at the size and
## colour the theme asks for. SVGs are loaded off disk at run time like pack
## art, so adding an icon is dropping a file in the folder.

static var _cache: Dictionary = {}


## A res:// path on purpose: it reads the same from the editor and from
## inside an exported build's pack (the export preset includes the SVGs).
static func dir() -> String:
	return "res://hexmap/ui/icons"


## `name` is the Lucide file name without extension ("eye-off").
static func get_icon(name: String, size: int = 18, color: Color = Color.WHITE, stroke_width: float = 2.0) -> Texture2D:
	var key := "%s|%d|%s|%s" % [name, size, color.to_html(), stroke_width]
	if _cache.has(key):
		return _cache[key]
	var path := dir().path_join(name + ".svg")
	var tex: Texture2D
	if FileAccess.file_exists(path):
		var svg := FileAccess.get_file_as_string(path)
		svg = svg.replace("currentColor", "#" + color.to_html(false))
		svg = svg.replace('stroke-width="2"', 'stroke-width="%s"' % PdfWriter.n(stroke_width))
		if color.a < 1.0:
			var i := svg.find("<svg")
			svg = svg.substr(0, i) + '<svg opacity="%s"' % PdfWriter.n(color.a) + svg.substr(i + 4)
		var img := Image.new()
		# Lucide icons are 24×24; rasterise at the device pixel size.
		if img.load_svg_from_string(svg, float(size) / 24.0) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(color, 0.3))
		tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func clear_cache() -> void:
	_cache.clear()
