class_name GameRules
extends RefCounted

const PieceLibraryScript = preload("res://scripts/core/piece_library.gd")

var board_size: Vector3i
var visible_queue: int = 4
var kick_offsets: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 1), Vector3i(-1, 0, 1),
	Vector3i(1, 0, -1), Vector3i(-1, 0, -1)
]
var score_table := {
	0: 0,
	1: 100,
	2: 300,
	3: 500,
	4: 800,
	5: 1200
}


func _init() -> void:
	board_size = Vector3i(10, 20, 10)


func piece_names() -> PackedStringArray:
	return PackedStringArray(PieceLibraryScript.pentomino_defs().keys())


func piece_defs() -> Dictionary:
	return PieceLibraryScript.pentomino_defs()


func score_for_clears(clear_count: int, level: int) -> int:
	return score_table.get(clear_count, 1200 + max(0, clear_count - 5) * 400) * level


func fall_interval(level: int) -> float:
	return max(0.08, 0.85 - (level - 1) * 0.06)
