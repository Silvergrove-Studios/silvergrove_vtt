@tool
extends EditorPlugin
## Registers the export plugin that puts the Hexmap NSD library into
## Android builds. The library itself is plugins/android/nsd, built with
## Gradle into bin/hexmap_nsd.aar (CI does it; `gradle assembleRelease`
## does it on a desk).

var _export := HexmapNsdExport.new()


func _enter_tree() -> void:
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)


class HexmapNsdExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "HexmapNsd"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["hexmap_nsd/bin/hexmap_nsd.aar"])
