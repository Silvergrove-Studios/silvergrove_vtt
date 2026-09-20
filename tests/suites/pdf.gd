extends TestCase
## The PDF writer.


## Bytes as a same-length string, binary replaced by '.', so offsets line up.
static func _printable(b: PackedByteArray) -> String:
	var chars := PackedByteArray()
	chars.resize(b.size())
	for i in b.size():
		var c := b[i]
		chars[i] = c if (c >= 32 and c < 127) or c == 10 else 46
	return chars.get_string_from_ascii()


func test_pdf_writer_structure() -> void:
	var pdf := PdfWriter.new()
	pdf.title = "Test (map)"
	var p := pdf.add_page(612, 792)
	pdf.set_line(p, 2.0, Color.BLACK)
	pdf.polyline(p, PackedVector2Array([Vector2(72, 72), Vector2(200, 72), Vector2(200, 200)]), true)
	pdf.fill_rect(p, Rect2(300, 300, 100, 50), Color.RED)
	pdf.text(p, "Hello (world) \\ done", Vector2(72, 400), 12, Color.BLACK)
	var img := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.8, 0.5))
	var name := pdf.add_image(img)
	pdf.image(p, name, Rect2(72, 500, 160, 80))
	var jn := pdf.add_image(img, 0.9)
	pdf.image(p, jn, Rect2(300, 500, 160, 80))
	pdf.add_page(842, 595)
	var bytes := pdf.to_bytes()
	var s := _printable(bytes)
	check(s.begins_with("%PDF-1.5"), "header")
	check(s.ends_with("%%EOF\n"), "trailer end")
	check(s.contains("/Type /Catalog"), "catalog")
	check(s.contains("/Count 2"), "two pages")
	check(s.contains("/SMask"), "alpha became a soft mask")
	check(s.contains("/DCTDecode"), "jpeg image")
	check(s.contains("/FlateDecode"), "flate streams")
	# xref offsets must point at "N 0 obj".
	var xref_at := int(s.substr(s.rfind("startxref") + 10).strip_edges().split("\n")[0])
	check(s.substr(xref_at, 4) == "xref", "startxref points at xref table")
	var lines := s.substr(xref_at).split("\n")
	var count := int(lines[1].split(" ")[1])
	for i in range(1, count):
		var off := int(lines[2 + i].substr(0, 10))
		check(s.substr(off).begins_with("%d 0 obj" % i), "xref entry %d points at object" % i)
	# Deflate output is zlib-wrapped (FlateDecode needs the 0x78 header).
	var z := "hello hello hello".to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	check(z.size() > 0 and z[0] == 0x78, "COMPRESSION_DEFLATE is zlib format")
	check(PdfWriter.n(12.0) == "12" and PdfWriter.n(0.125) == "0.125" and PdfWriter.n(-2.5) == "-2.5", "number formatting")
	# Write it out so an external validator (pdfinfo / gs) can be run by hand or CI.
	check(pdf.save(out_dir().path_join("test_writer.pdf")) == OK, "saved")
