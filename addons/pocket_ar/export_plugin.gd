@tool
extends EditorPlugin

var exporter: EditorExportPlugin

func _enter_tree() -> void:
	exporter = AndroidExporter.new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	remove_export_plugin(exporter)

class AndroidExporter extends EditorExportPlugin:
	func _get_name() -> String:
		return "PocketAR"
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid
	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["res://addons/pocket_ar/pocket-ar-release.aar"])
	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.google.ar:core:1.48.0", "com.google.mediapipe:tasks-vision:0.10.21"])
