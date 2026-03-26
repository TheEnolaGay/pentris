class_name PieceLibrary
extends RefCounted

static func pentomino_defs() -> Dictionary:
	return {
		"F": _piece([
			Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 0, 2), Vector3i(2, 0, 2)
		], Color("#f87171")),
		"I": _piece([
			Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(4, 0, 0)
		], Color("#38bdf8")),
		"L": _piece([
			Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(3, 0, 1)
		], Color("#fb923c")),
		"P": _piece([
			Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(0, 0, 2)
		], Color("#fbbf24")),
		"N": _piece([
			Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(3, 0, 1)
		], Color("#22c55e")),
		"T": _piece([
			Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 0, 2)
		], Color("#c084fc")),
		"U": _piece([
			Vector3i(0, 0, 0), Vector3i(2, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(2, 0, 1)
		], Color("#14b8a6")),
		"V": _piece([
			Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 2), Vector3i(1, 0, 2), Vector3i(2, 0, 2)
		], Color("#f97316")),
		"W": _piece([
			Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(1, 0, 2), Vector3i(2, 0, 2)
		], Color("#a3e635")),
		"X": _piece([
			Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(1, 0, 2)
		], Color("#e879f9")),
		"Y": _piece([
			Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(1, 0, 1)
		], Color("#60a5fa")),
		"Z": _piece([
			Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 0, 2), Vector3i(2, 0, 2)
		], Color("#f43f5e"))
	}
static func _piece(blocks: Array, color: Color) -> Dictionary:
	return {
		"blocks": blocks,
		"color": color
	}
