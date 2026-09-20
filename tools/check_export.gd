extends SceneTree
## godot --headless -s tools/check_export.gd -- <file.pck>
## Mounts an exported pack and checks that the files the app reads at run
## time — the icons, the fonts, the main scene and scripts — are in it.
## Catches an export that would launch to a blank window before anyone
## installs it on a phone.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <file.pck>")
		quit(2)
		return
	var pck := args[0]
	if not pck.is_absolute_path():
		pck = ProjectSettings.globalize_path("res://").path_join(pck)
	# Mount beside the project's own res:// so paths collide the way they
	# will in the build; the pack's files win.
	if not ProjectSettings.load_resource_pack(pck, true):
		print("FAIL cannot load ", pck)
		quit(1)
		return
	var bad := 0
	# Scripts and scenes are stored compiled behind a remap: ask the loader.
	for p in ["res://hexmap/shell/main.tscn", "res://hexmap/shell/main.gd", "res://hexmap/player/player_window.gd", "res://hexmap/net/net_session.gd"]:
		if ResourceLoader.exists(p):
			print("ok   ", p)
		else:
			print("FAIL missing from the pack: ", p)
			bad += 1
	# Files the app reads itself must be there raw.
	for p in ["res://hexmap/ui/icons/eye.svg", "res://hexmap/ui/icons/hexagon.svg", "res://hexmap/ui/fonts/Inter-Regular.ttf", "res://hexmap/ui/fonts/JetBrainsMono-Regular.ttf"]:
		if FileAccess.file_exists(p) and FileAccess.get_file_as_bytes(p).size() > 100:
			print("ok   ", p)
		else:
			print("FAIL missing from the pack: ", p)
			bad += 1
	# The suite ships so a build can self-test; the placeholder packs do
	# not (they stream from a Table).
	if not ResourceLoader.exists("res://tests/test_suite.gd"):
		print("FAIL the test suite is missing from the pack")
		bad += 1
	if FileAccess.file_exists("res://packs/woodland/pack.json"):
		print("FAIL the packs should not be in the pack")
		bad += 1
	quit(1 if bad > 0 else 0)
