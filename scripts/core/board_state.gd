class_name BoardState
extends RefCounted

var size: Vector3i
var _cells := {}


func _init(board_size: Vector3i) -> void:
	size = board_size


func reset() -> void:
	_cells.clear()


func occupied_cells() -> Dictionary:
	return _cells.duplicate(true)


func can_place(blocks: Array, origin: Vector3i) -> bool:
	for block in blocks:
		var world: Vector3i = origin + block
		if not is_inside(world):
			return false
		if is_occupied(world):
			return false
	return true


func occupy(blocks: Array, origin: Vector3i, color: Color) -> void:
	for block in blocks:
		var world: Vector3i = origin + block
		_cells[_key(world)] = {
			"position": world,
			"color": color
		}


func project_down(blocks: Array, origin: Vector3i) -> Vector3i:
	var ghost := origin
	while can_place(blocks, ghost + Vector3i(0, -1, 0)):
		ghost += Vector3i(0, -1, 0)
	return ghost


func find_completed_rows() -> Dictionary:
	var row_keys := {}
	for y in range(size.y):
		for z in range(size.z):
			var x_row_full := true
			for x in range(size.x):
				if not is_occupied(Vector3i(x, y, z)):
					x_row_full = false
					break
			if x_row_full:
				row_keys["x:%s:%s" % [y, z]] = true
		for x in range(size.x):
			var z_row_full := true
			for z in range(size.z):
				if not is_occupied(Vector3i(x, y, z)):
					z_row_full = false
					break
			if z_row_full:
				row_keys["z:%s:%s" % [y, x]] = true

	if row_keys.is_empty():
		return {
			"rows": [],
			"cells": []
		}

	var cleared_cells := {}
	for row_key in row_keys.keys():
		var row_key_string: String = row_key
		var parts: PackedStringArray = row_key_string.split(":")
		var axis: String = parts[0]
		var y: int = int(parts[1])
		var fixed: int = int(parts[2])
		if axis == "x":
			for x in range(size.x):
				var position := Vector3i(x, y, fixed)
				cleared_cells[_key(position)] = position
		else:
			for z in range(size.z):
				var position := Vector3i(fixed, y, z)
				cleared_cells[_key(position)] = position

	return {
		"rows": row_keys.keys(),
		"cells": cleared_cells.values()
	}


func apply_clear_result(clear_result: Dictionary) -> Dictionary:
	var cleared_cells: Array = clear_result.get("cells", [])
	if cleared_cells.is_empty():
		return {
			"rows": [],
			"cells": []
		}

	for position in cleared_cells:
		_cells.erase(_key(position))

	var affected_columns := {}
	for position in cleared_cells:
		var column_key := "%s,%s" % [position.x, position.z]
		affected_columns[column_key] = Vector2i(position.x, position.z)

	for column in affected_columns.values():
		_compact_column(column.x, column.y)

	return {
		"rows": clear_result.get("rows", []),
		"cells": cleared_cells
	}


func clear_completed_rows() -> Dictionary:
	return apply_clear_result(find_completed_rows())


func is_inside(position: Vector3i) -> bool:
	return (
		position.x >= 0 and position.x < size.x
		and position.y >= 0 and position.y < size.y
		and position.z >= 0 and position.z < size.z
	)


func is_occupied(position: Vector3i) -> bool:
	return _cells.has(_key(position))


func _compact_column(x: int, z: int) -> void:
	var entries: Array[Dictionary] = []
	for y in range(size.y):
		var position := Vector3i(x, y, z)
		var cell_key := _key(position)
		if _cells.has(cell_key):
			entries.append(_cells[cell_key])
			_cells.erase(cell_key)

	for new_y in range(entries.size()):
		var entry := entries[new_y]
		var position := Vector3i(x, new_y, z)
		_cells[_key(position)] = {
			"position": position,
			"color": entry["color"]
		}


func _key(position: Vector3i) -> String:
	return "%s,%s,%s" % [position.x, position.y, position.z]
