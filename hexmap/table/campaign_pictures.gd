class_name CampaignPictures
extends RefCounted
## The pictures a campaign can show its players: the `pictures` of the art
## packs it carries (an adventure's own), and the ones the DM adds from a
## file, kept in a pack of the campaign's own in its `art/` (so they go
## where the campaign goes, and reach the phones as its other art does).

const LICENSE_UNKNOWN := "unknown: pictures you added; say under what licence they may be shared before you give this campaign to anyone"


## The id of the campaign's own picture pack.
static func pack_id(campaign: Campaign) -> String:
	var s := campaign.id.to_lower()
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return "pictures_" + out.left(12)


## Every picture the campaign carries: [{ref, name, pack, tags}], by name.
static func all(ctx: TableContext) -> Array:
	var out := []
	if ctx.art == null:
		return out
	for p in ctx.art.all("pictures"):
		out.append({"ref": str(p._ref), "name": str(p.get("name", p.get("id", ""))), "pack": str(p._pack), "tags": p.get("tags", [])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


## A picture file into the campaign's own pack. {ref} or {why}.
static func add_file(ctx: TableContext, path: String, p_name := "") -> Dictionary:
	if ctx.campaign == null or ctx.campaign.path == "":
		return {"why": "save the campaign first: its pictures live in its folder"}
	var ext := path.get_extension().to_lower()
	if not ["png", "jpg", "jpeg", "webp", "svg"].has(ext):
		return {"why": "a picture is a PNG, JPEG, WebP or SVG file"}
	if not FileAccess.file_exists(path):
		return {"why": "no file %s" % path}
	var pid := pack_id(ctx.campaign)
	var dir := ctx.campaign.base_dir().path_join("art").path_join(pid)
	DirAccess.make_dir_recursive_absolute(dir.path_join("pictures"))
	var manifest_path := dir.path_join("pack.json")
	var m := {}
	if FileAccess.file_exists(manifest_path):
		m = JsonDoc.parse(FileAccess.get_file_as_string(manifest_path), [])
	if m.is_empty():
		m = {"format": "silvergrove.pack", "version": 1, "id": pid, "name": "%s: pictures" % ctx.campaign.name, "pack_version": "0",
			"license": LICENSE_UNKNOWN, "description": "Pictures this campaign's DM added to show the players.", "pictures": []}
	var base := _slug(path.get_file().get_basename())
	var aid := base
	var taken := {}
	for p in m.get("pictures", []):
		taken[str(p.get("id", ""))] = true
	var n := 1
	while taken.has(aid):
		n += 1
		aid = "%s_%d" % [base, n]
	var file := "pictures/%s.%s" % [aid, ext]
	if JsonDoc.copy_file(path, dir.path_join(file)) != OK:
		return {"why": "could not copy %s" % path.get_file()}
	(m.pictures as Array).append({"id": aid, "name": p_name if p_name != "" else path.get_file().get_basename().replace("_", " ").capitalize(), "texture": file})
	# a new version, so the phones fetch the new file
	m.pack_version = str(int(str(m.get("pack_version", "0"))) + 1)
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f == null:
		return {"why": "could not write %s" % manifest_path}
	f.store_string(JsonDoc.stringify(m))
	f.close()
	ctx.refresh_art()
	return {"ref": "%s:%s" % [pid, aid]}


static func _slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if out != "" else "picture"
