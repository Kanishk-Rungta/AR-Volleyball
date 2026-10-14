extends SceneTree

func _initialize() -> void:
	var archive := ZIPReader.new()
	assert(archive.open("res://build/NeonVolleyAR.apk") == OK)
	var bytes := archive.read_file("assets/scripts/main.gdc")
	assert(bytes.slice(0, 4).get_string_from_ascii() == "GDSC")
	var tokens := bytes.slice(12).decompress(bytes.decode_u32(8), FileAccess.COMPRESSION_ZSTD)
	assert(not tokens.is_empty())
	var token_hex := tokens.hex_encode()
	# Android hand control is intentionally hits-only; palm movement is desktop-only.
	var forbidden := "phone_target_direction"
	var forbidden_bytes := PackedByteArray()
	for i in range(forbidden.length()):
		var code := PackedByteArray()
		code.resize(4)
		code.encode_u32(0, forbidden.unicode_at(i) ^ 0xb6b6b6b6)
		forbidden_bytes.append_array(code)
	if token_hex.contains(forbidden_bytes.hex_encode()):
		push_error("APK unexpectedly includes phone palm movement")
		quit(1)
		return
	for symbol in ["phone_fist_armed", "updateDisplayGeometry", "last_tracking_frame_time", "_upload_camera_yuv", "phone_hands_enabled", "cancelPlacement", "camera_safe_preview", "approximate_placement", "_place_approximately", "DOWN"]:
		# Godot's tokenizer stores identifiers as XOR-obfuscated UTF-32 codepoints.
		var encoded := PackedByteArray()
		encoded.resize(symbol.length() * 4)
		for i in range(symbol.length()):
			encoded.encode_u32(i * 4, symbol.unicode_at(i) ^ 0xb6b6b6b6)
		if not token_hex.contains(encoded.hex_encode()):
			push_error("APK is missing current gameplay: " + symbol)
			quit(1)
			return
	archive.close()
	print("PASS: APK includes raw YUV camera, optional hand hits, queued/cancelable placement and current AR controls")
	quit(0)
