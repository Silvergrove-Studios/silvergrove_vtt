class_name PdfWriter
extends RefCounted
## A small PDF 1.5 writer: pages, embedded images (Flate or JPEG, with alpha
## masks), vector paths, and Helvetica text. Enough for print-ready maps and
## nothing more — no fonts embedding, no forms, no incremental updates.
##
## Coordinates given to this class are in points (72 per inch) from the
## page's TOP-left, y down, like everything else in the app; the writer flips
## them into PDF space. Everything is buffered in memory until save().
##
## The PDF spec is open (ISO 32000-1) and this depends on nothing outside
## Godot, which is why it exists instead of a binding to a PDF library.

const PT_PER_INCH := 72.0
const PT_PER_MM := 72.0 / 25.4

## Paper sizes in points, portrait.
const PAPER := {
	"letter": Vector2(612, 792),
	"legal": Vector2(612, 1008),
	"tabloid": Vector2(792, 1224),
	"a4": Vector2(595.276, 841.89),
	"a3": Vector2(841.89, 1190.55),
	"a2": Vector2(1190.55, 1683.78),
}

var title := ""
var author := ""
var subject := ""
var creator := "Hexmap (Silvergrove Studios)"

## Object bodies, index i is object number i + 1. Objects 1..3 are reserved
## for the catalog, the page tree and the font and are filled in at save().
var _objects: Array[PackedByteArray] = []
var _pages: Array[Dictionary] = []
var _image_count := 0


func _init() -> void:
	_objects.resize(3)


# --------------------------------------------------------------------- pages --

## Add a page; returns its index. Width/height in points.
func add_page(width_pt: float, height_pt: float) -> int:
	_pages.append({"w": width_pt, "h": height_pt, "ops": [], "xobjects": {}})
	return _pages.size() - 1


func page_size(page: int) -> Vector2:
	return Vector2(_pages[page].w, _pages[page].h)


func _op(page: int, s: String) -> void:
	(_pages[page].ops as Array).append(s)


static func n(v: float) -> String:
	# Compact number formatting: 12, 12.5, 0.125 — never exponents.
	if v == floorf(v) and absf(v) < 1e9:
		return str(int(v))
	var s := "%.4f" % v
	s = s.rstrip("0").rstrip(".")
	return s if s != "" and s != "-" else "0"


func _y(page: int, y: float) -> float:
	return _pages[page].h - y


static func _rgb(c: Color, op: String) -> String:
	return "%s %s %s %s" % [n(c.r), n(c.g), n(c.b), op]


# ------------------------------------------------------------------- drawing --

func set_line(page: int, width_pt: float, color: Color, dash: PackedFloat32Array = PackedFloat32Array()) -> void:
	_op(page, "%s w %s" % [n(width_pt), _rgb(color, "RG")])
	if dash.is_empty():
		_op(page, "[] 0 d")
	else:
		var parts := PackedStringArray()
		for d in dash:
			parts.append(n(d))
		_op(page, "[%s] 0 d" % " ".join(parts))
	_op(page, "1 J 1 j")   # round caps and joins


func line(page: int, a: Vector2, b: Vector2) -> void:
	_op(page, "%s %s m %s %s l S" % [n(a.x), n(_y(page, a.y)), n(b.x), n(_y(page, b.y))])


func polyline(page: int, pts: PackedVector2Array, closed := false) -> void:
	if pts.size() < 2:
		return
	var s := "%s %s m" % [n(pts[0].x), n(_y(page, pts[0].y))]
	for i in range(1, pts.size()):
		s += " %s %s l" % [n(pts[i].x), n(_y(page, pts[i].y))]
	s += " h S" if closed else " S"
	_op(page, s)


func fill_polygon(page: int, pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 3:
		return
	var s := "%s %s %s m" % [_rgb(color, "rg"), n(pts[0].x), n(_y(page, pts[0].y))]
	for i in range(1, pts.size()):
		s += " %s %s l" % [n(pts[i].x), n(_y(page, pts[i].y))]
	_op(page, s + " h f")


func fill_rect(page: int, r: Rect2, color: Color) -> void:
	_op(page, "%s %s %s %s %s re f" % [_rgb(color, "rg"), n(r.position.x), n(_y(page, r.position.y + r.size.y)), n(r.size.x), n(r.size.y)])


func stroke_rect(page: int, r: Rect2) -> void:
	_op(page, "%s %s %s %s re S" % [n(r.position.x), n(_y(page, r.position.y + r.size.y)), n(r.size.x), n(r.size.y)])


## Clip subsequent drawing (until pop_clip) to a rectangle.
func push_clip(page: int, r: Rect2) -> void:
	_op(page, "q %s %s %s %s re W n" % [n(r.position.x), n(_y(page, r.position.y + r.size.y)), n(r.size.x), n(r.size.y)])


func pop_clip(page: int) -> void:
	_op(page, "Q")


## Helvetica text with its baseline at `pos`. `align` 0 left, 1 centre, 2 right.
func text(page: int, s: String, pos: Vector2, size_pt: float, color: Color, align := 0) -> void:
	var x := pos.x
	if align > 0:
		var w := text_width(s, size_pt)
		x -= w if align == 2 else w / 2.0
	_op(page, "BT %s /F1 %s Tf %s %s Td (%s) Tj ET" % [_rgb(color, "rg"), n(size_pt), n(x), n(_y(page, pos.y)), _escape(s)])


## Approximate Helvetica advance widths; good enough to centre a label.
static func text_width(s: String, size_pt: float) -> float:
	var w := 0.0
	for ch in s:
		var c: String = ch
		if c in "il.,:;'|!I":
			w += 0.28
		elif c in "mwMW":
			w += 0.83
		elif c == " ":
			w += 0.28
		elif c == c.to_upper() and c != c.to_lower():
			w += 0.67
		elif c.is_valid_int():
			w += 0.556
		else:
			w += 0.53
	return w * size_pt


## WinAnsi code points for the non-Latin-1 characters we actually use.
const WINANSI := {0x2014: 0x97, 0x2013: 0x96, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93, 0x201D: 0x94, 0x2026: 0x85, 0x2022: 0x95, 0x20AC: 0x80, 0x2122: 0x99}


## Encode a string for a PDF literal in WinAnsiEncoding.
static func _escape(s: String) -> String:
	var out := ""
	for i in s.length():
		var cp := s.unicode_at(i)
		if cp >= 128:
			if WINANSI.has(cp):
				cp = WINANSI[cp]
			elif cp > 255:
				cp = 0x3F   # '?'
		if cp == 0x28 or cp == 0x29 or cp == 0x5c:
			out += "\\" + char(cp)
		elif cp < 32 or cp > 126:
			out += "\\%03o" % cp
		else:
			out += char(cp)
	return out


# -------------------------------------------------------------------- images --

## Embed an image as an XObject and return its resource name. Flate (lossless)
## when jpeg_quality < 0, otherwise JPEG at that quality (0..1). Alpha, if
## present, becomes a soft mask in either case.
func add_image(img: Image, jpeg_quality := -1.0) -> String:
	var src := img
	if src.is_compressed():
		src = img.duplicate()
		src.decompress()
	var has_alpha := src.detect_alpha() != Image.ALPHA_NONE
	var w := src.get_width()
	var h := src.get_height()
	var smask_ref := ""
	if has_alpha:
		var rgba := src.duplicate()
		rgba.convert(Image.FORMAT_RGBA8)
		var data: PackedByteArray = rgba.get_data()
		var alpha := PackedByteArray()
		alpha.resize(w * h)
		for i in w * h:
			alpha[i] = data[i * 4 + 3]
		var mask := _add_stream(
			"/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode" % [w, h],
			alpha.compress(FileAccess.COMPRESSION_DEFLATE))
		smask_ref = " /SMask %d 0 R" % mask
	var rgb := src.duplicate()
	rgb.convert(Image.FORMAT_RGB8)
	var obj: int
	if jpeg_quality >= 0.0:
		obj = _add_stream(
			"/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode%s" % [w, h, smask_ref],
			rgb.save_jpg_to_buffer(clampf(jpeg_quality, 0.01, 1.0)))
	else:
		obj = _add_stream(
			"/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode%s" % [w, h, smask_ref],
			rgb.get_data().compress(FileAccess.COMPRESSION_DEFLATE))
	_image_count += 1
	var name := "Im%d" % _image_count
	_image_objects[name] = obj
	return name

var _image_objects: Dictionary = {}


## Draw an embedded image into a rectangle (points, top-left origin).
func image(page: int, name: String, r: Rect2) -> void:
	(_pages[page].xobjects as Dictionary)[name] = _image_objects[name]
	_op(page, "q %s 0 0 %s %s %s cm /%s Do Q" % [n(r.size.x), n(r.size.y), n(r.position.x), n(_y(page, r.position.y + r.size.y)), name])


# ---------------------------------------------------------------------- save --

func _add_object(body: String) -> int:
	_objects.append(body.to_utf8_buffer())
	return _objects.size()


func _add_stream(dict_entries: String, data: PackedByteArray) -> int:
	var head := ("<< %s /Length %d >>\nstream\n" % [dict_entries, data.size()]).to_utf8_buffer()
	var body := head
	body.append_array(data)
	body.append_array("\nendstream".to_utf8_buffer())
	_objects.append(body)
	return _objects.size()


func to_bytes() -> PackedByteArray:
	# Work on a copy so to_bytes() can be called more than once.
	var kept := _objects.duplicate()
	# Page objects and their content streams.
	var page_refs := PackedStringArray()
	for p in _pages:
		var ops: PackedStringArray = PackedStringArray(p.ops as Array)
		var content := "\n".join(ops).to_utf8_buffer()
		var stream := _add_stream("/Filter /FlateDecode", content.compress(FileAccess.COMPRESSION_DEFLATE))
		var xo := ""
		for name in p.xobjects:
			xo += "/%s %d 0 R " % [name, p.xobjects[name]]
		var page := _add_object("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] /Contents %d 0 R /Resources << /Font << /F1 3 0 R >> /XObject << %s>> >> >>" % [n(p.w), n(p.h), stream, xo])
		page_refs.append("%d 0 R" % page)
	_objects[0] = "<< /Type /Catalog /Pages 2 0 R >>".to_utf8_buffer()
	_objects[1] = ("<< /Type /Pages /Kids [%s] /Count %d >>" % [" ".join(page_refs), _pages.size()]).to_utf8_buffer()
	_objects[2] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>".to_utf8_buffer()
	var info := _add_object("<< /Title (%s) /Author (%s) /Subject (%s) /Creator (%s) /Producer (%s) /CreationDate (D:%s) >>" % [
		_escape(title), _escape(author), _escape(subject), _escape(creator), _escape(creator), _pdf_date()])

	var out := PackedByteArray()
	out.append_array("%PDF-1.5\n".to_utf8_buffer())
	out.append_array(PackedByteArray([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))  # binary marker
	var offsets := PackedInt64Array()
	for i in _objects.size():
		offsets.append(out.size())
		out.append_array(("%d 0 obj\n" % (i + 1)).to_utf8_buffer())
		out.append_array(_objects[i])
		out.append_array("\nendobj\n".to_utf8_buffer())
	var xref := out.size()
	var t := "xref\n0 %d\n0000000000 65535 f \n" % (_objects.size() + 1)
	for o in offsets:
		t += "%010d 00000 n \n" % o
	t += "trailer\n<< /Size %d /Root 1 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [_objects.size() + 1, info, xref]
	out.append_array(t.to_utf8_buffer())
	_objects = kept
	return out


func save(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(to_bytes())
	f.close()
	return OK


static func _pdf_date() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	return "%04d%02d%02d%02d%02d%02dZ" % [d.year, d.month, d.day, d.hour, d.minute, d.second]
