class_name Uploads
extends RefCounted
## Pictures the people at a table upload (the team, after the character
## maker: players want their own token pictures, and pictures in their
## journals): kept in the campaign's own `uploads/` folder, one WebP each,
## named for what is in it, and referred to as `upload:<id>` — a token's
## `art`, a note's `![…](upload:<id>)`. They are not listed anywhere: a
## picture's address is known to those who were shown it (a player's
## private note stays private), served at `/upload/<id>.webp`.
##
## What comes in is checked and made again here, whatever the phone sent:
## PNG, JPEG or WebP, decoded, a token's cut square, no larger than its
## kind allows, encoded as WebP (a photo's location and camera notes do not
## survive it).

const DIR := "uploads"
## The largest file taken (the phone shrinks a picture before it is sent).
const MAX_BYTES := 12 * 1024 * 1024
## How many a campaign keeps before it refuses more.
const MAX_FILES := 1000
## kind -> the longest side, and whether it is cut square
const KINDS := {"token": {"max": 512, "square": true}, "picture": {"max": 1600, "square": false}}
const PREFIX := "upload:"


## Whether a ref is an uploaded picture's.
static func is_ref(ref: String) -> bool:
	return ref.begins_with(PREFIX) and valid_id(ref.substr(PREFIX.length()))


static func valid_id(id: String) -> bool:
	if id.length() != 32:
		return false
	for ch in id:
		if not "0123456789abcdef".contains(ch):
			return false
	return true


## The folder a campaign keeps its uploads in ("" for one with no folder).
static func dir_of(campaign: Campaign) -> String:
	return campaign.base_dir().path_join(DIR) if campaign != null and campaign.path != "" else ""


## The file an uploaded picture is in, or "" for a ref that is not one.
static func path_of(dir: String, ref_or_id: String) -> String:
	var id := ref_or_id.substr(PREFIX.length()) if ref_or_id.begins_with(PREFIX) else ref_or_id
	if dir == "" or not valid_id(id):
		return ""
	return dir.path_join(id + ".webp")


## A picture's bytes by its id (the web side's /upload/<id>.webp), or empty.
static func read(dir: String, id: String) -> PackedByteArray:
	var p := path_of(dir, id)
	if p == "" or not FileAccess.file_exists(p):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(p)


## An image from the bytes a browser sent, by what they are (not what they
## claim to be): PNG, JPEG or WebP. null for anything else.
static func decode(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	return img


## Keep a picture: {ok, ref, id, why}. `kind` is "token" (cut square, 512
## across at most) or "picture" (1600 at most on its longer side).
static func store(dir: String, kind: String, bytes: PackedByteArray) -> Dictionary:
	var out := {"ok": false, "ref": "", "id": "", "why": ""}
	if not KINDS.has(kind):
		out.why = "a picture for what?"
		return out
	if dir == "":
		out.why = "this table keeps no pictures (its campaign has no folder)"
		return out
	if bytes.size() > MAX_BYTES:
		out.why = "that picture is too big (%d MB at most)" % (MAX_BYTES / (1024 * 1024))
		return out
	var img := decode(bytes)
	if img == null:
		out.why = "that is not a picture this table can read (PNG, JPEG or WebP)"
		return out
	if img.get_width() < 8 or img.get_height() < 8:
		out.why = "that picture is too small"
		return out
	var spec: Dictionary = KINDS[kind]
	if bool(spec.square) and img.get_width() != img.get_height():
		var side := mini(img.get_width(), img.get_height())
		img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	var longest := maxi(img.get_width(), img.get_height())
	if longest > int(spec.max):
		var k := float(spec.max) / float(longest)
		img.resize(maxi(1, roundi(img.get_width() * k)), maxi(1, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8 if img.detect_alpha() != Image.ALPHA_NONE else Image.FORMAT_RGB8)
	var webp := img.save_webp_to_buffer(true, 0.86)
	if webp.is_empty():
		out.why = "could not keep that picture"
		return out
	var id := _hash(webp)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(id + ".webp")
	if not FileAccess.file_exists(path):
		if count(dir) >= MAX_FILES:
			out.why = "this table keeps %d pictures at most: ask the DM to clear some" % MAX_FILES
			return out
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			out.why = "could not keep that picture: %s" % error_string(FileAccess.get_open_error())
			return out
		f.store_buffer(webp)
		f.close()
	out.ok = true
	out.id = id
	out.ref = PREFIX + id
	return out


static func count(dir: String) -> int:
	var da := DirAccess.open(dir)
	if da == null:
		return 0
	var n := 0
	for f in da.get_files():
		if f.ends_with(".webp"):
			n += 1
	return n


static func _hash(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode().substr(0, 32)
