extends Control

var landmarks: Array = []
var pinched := false
var show_reticle := false
var surface_ready := false
const CONNECTIONS := [[0,1],[1,2],[2,3],[3,4],[0,5],[5,6],[6,7],[7,8],[5,9],[9,10],[10,11],[11,12],[9,13],[13,14],[14,15],[15,16],[13,17],[0,17],[17,18],[18,19],[19,20]]

func _draw() -> void:
	if show_reticle:
		var center := size * 0.5
		var aim_color := Color("65e7d1") if surface_ready else Color("ffcf73")
		draw_arc(center, 19, 0, TAU, 32, aim_color, 3, true)
		draw_circle(center, 3, aim_color)
		draw_string(ThemeDB.fallback_font, center + Vector2(-58, 40), "Surface ready" if surface_ready else "Aim at a table", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, aim_color)
	if landmarks.size() != 21:
		return
	var color := Color("ffcf73") if pinched else Color("65e7d1")
	for edge in CONNECTIONS:
		draw_line(_point(edge[0]), _point(edge[1]), color, 2.0, true)
	for i in range(21):
		draw_circle(_point(i), 4, color)

func _point(index: int) -> Vector2:
	return Vector2(float(landmarks[index][0]), float(landmarks[index][1])) * size
