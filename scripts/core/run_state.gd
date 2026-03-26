class_name RunState
extends RefCounted

const GameRulesScript = preload("res://scripts/core/game_rules.gd")
const BoardStateScript = preload("res://scripts/core/board_state.gd")
const CLEAR_PAUSE_DURATION := 0.2

var rules: RefCounted
var board: RefCounted
var rng := RandomNumberGenerator.new()
var queue: Array[String] = []
var hold_piece: String = ""
var can_hold := true
var score := 0
var cleared_rows_total := 0
var level := 1
var current_piece := {}
var game_over := false
var clear_pause_remaining := 0.0
var pending_clear_result := {
	"rows": [],
	"cells": []
}

var _bag: Array[String] = []


func _init(game_rules: RefCounted, seed: int = 0) -> void:
	rules = game_rules
	board = BoardStateScript.new(rules.board_size)
	if seed == 0:
		rng.randomize()
	else:
		rng.seed = seed
	reset()


func reset() -> void:
	board.reset()
	queue.clear()
	_bag.clear()
	hold_piece = ""
	can_hold = true
	score = 0
	cleared_rows_total = 0
	level = 1
	game_over = false
	current_piece = {}
	clear_pause_remaining = 0.0
	pending_clear_result = {
		"rows": [],
		"cells": []
	}
	_fill_queue()
	_spawn_next_piece()


func current_fall_interval() -> float:
	return rules.fall_interval(level)


func is_clearing() -> bool:
	return clear_pause_remaining > 0.0


func advance_clear(delta: float) -> bool:
	if not is_clearing():
		return false
	clear_pause_remaining = max(0.0, clear_pause_remaining - delta)
	if clear_pause_remaining > 0.0:
		return false
	_finalize_pending_clear()
	return true


func clear_pause_progress() -> float:
	if not is_clearing():
		return 1.0
	return 1.0 - (clear_pause_remaining / CLEAR_PAUSE_DURATION)


func pending_clear_cells() -> Array:
	return pending_clear_result.get("cells", [])


func move_active(delta: Vector3i) -> bool:
	if game_over or is_clearing() or current_piece.is_empty():
		return false
	var target: Vector3i = current_piece["origin"] + delta
	if board.can_place(current_piece["blocks"], target):
		current_piece["origin"] = target
		return true
	return false


func rotate_active(axis: String, direction: int) -> bool:
	if game_over or is_clearing() or current_piece.is_empty():
		return false
	var rotated := _rotate_blocks(current_piece["blocks"], axis, direction)
	for offset in rules.kick_offsets:
		var target: Vector3i = current_piece["origin"] + offset
		if board.can_place(rotated, target):
			current_piece["blocks"] = rotated
			current_piece["origin"] = target
			return true
	return false


func tick() -> bool:
	if game_over or is_clearing() or current_piece.is_empty():
		return false
	if move_active(Vector3i(0, -1, 0)):
		return true
	_lock_piece()
	return false


func soft_drop_step() -> bool:
	if is_clearing():
		return false
	var moved := move_active(Vector3i(0, -1, 0))
	if moved:
		score += 1
	else:
		_lock_piece()
	return moved


func hard_drop() -> int:
	if game_over or is_clearing() or current_piece.is_empty():
		return 0
	var landing_origin: Vector3i = landing_origin_for_active()
	var distance: int = current_piece["origin"].y - landing_origin.y
	current_piece["origin"] = landing_origin
	score += distance * 2
	_lock_piece()
	return distance


func hold_current() -> bool:
	if game_over or is_clearing() or current_piece.is_empty() or not can_hold:
		return false
	var outgoing: String = current_piece["name"]
	if hold_piece == "":
		hold_piece = outgoing
		_spawn_next_piece()
	else:
		var incoming := hold_piece
		hold_piece = outgoing
		current_piece = _create_piece(incoming)
		if not board.can_place(current_piece["blocks"], current_piece["origin"]):
			game_over = true
			current_piece = {}
			return false
	can_hold = false
	return true


func ghost_origin() -> Vector3i:
	if is_clearing() or current_piece.is_empty():
		return Vector3i.ZERO
	return landing_origin_for_active()


func landing_origin_for_active() -> Vector3i:
	if current_piece.is_empty():
		return Vector3i.ZERO
	return board.project_down(current_piece["blocks"], current_piece["origin"])


func active_cells(origin_override: Variant = null) -> Array[Dictionary]:
	if current_piece.is_empty():
		return []
	var origin: Vector3i = current_piece["origin"] if origin_override == null else origin_override
	var pivot_block: Vector3i = current_piece["blocks"][0]
	var cells: Array[Dictionary] = []
	for block in current_piece["blocks"]:
		cells.append({
			"position": origin + block,
			"color": current_piece["color"],
			"is_pivot": block == pivot_block
		})
	return cells


func pivot_position() -> Vector3i:
	if current_piece.is_empty():
		return Vector3i.ZERO
	return current_piece["origin"] + current_piece["blocks"][0]


func set_board_cells_for_test(cells: Array) -> void:
	board.reset()
	clear_pause_remaining = 0.0
	pending_clear_result = {
		"rows": [],
		"cells": []
	}
	for cell in cells:
		board.occupy([Vector3i.ZERO], cell["position"], cell.get("color", Color.WHITE))


func set_active_piece_for_test(name: String, origin: Vector3i, rotations: Array = []) -> void:
	current_piece = _create_piece(name)
	current_piece["origin"] = origin
	clear_pause_remaining = 0.0
	pending_clear_result = {
		"rows": [],
		"cells": []
	}
	for rotation in rotations:
		current_piece["blocks"] = _rotate_blocks(current_piece["blocks"], rotation["axis"], rotation["direction"])
	game_over = not board.can_place(current_piece["blocks"], current_piece["origin"])


func snapshot_for_test() -> Dictionary:
	return {
		"board_cells": board.occupied_cells().values(),
		"current_piece": current_piece.duplicate(true),
		"queue": queue.duplicate(),
		"hold_piece": hold_piece,
		"can_hold": can_hold,
		"score": score,
		"cleared_rows_total": cleared_rows_total,
		"level": level,
		"game_over": game_over,
		"clear_pause_remaining": clear_pause_remaining,
		"pending_clear_result": pending_clear_result.duplicate(true)
	}


func load_snapshot_for_test(snapshot: Dictionary) -> void:
	set_board_cells_for_test(snapshot["board_cells"])
	current_piece = snapshot["current_piece"].duplicate(true)
	queue = snapshot["queue"].duplicate()
	hold_piece = snapshot["hold_piece"]
	can_hold = snapshot["can_hold"]
	score = snapshot["score"]
	cleared_rows_total = snapshot["cleared_rows_total"]
	level = snapshot["level"]
	game_over = snapshot["game_over"]
	clear_pause_remaining = snapshot.get("clear_pause_remaining", 0.0)
	pending_clear_result = snapshot.get("pending_clear_result", {
		"rows": [],
		"cells": []
	}).duplicate(true)


func preview_queue() -> Array[String]:
	var slice: Array[String] = []
	for i in range(min(rules.visible_queue, queue.size())):
		slice.append(queue[i])
	return slice


func _lock_piece() -> void:
	board.occupy(current_piece["blocks"], current_piece["origin"], current_piece["color"])
	current_piece = {}
	var clear_result: Dictionary = board.find_completed_rows()
	if clear_result["rows"].is_empty():
		can_hold = true
		_spawn_next_piece()
		return
	pending_clear_result = clear_result
	clear_pause_remaining = CLEAR_PAUSE_DURATION


func _finalize_pending_clear() -> void:
	var applied_result: Dictionary = board.apply_clear_result(pending_clear_result)
	var row_count: int = applied_result["rows"].size()
	cleared_rows_total += row_count
	score += rules.score_for_clears(row_count, level)
	level = 1 + int(cleared_rows_total / 10)
	clear_pause_remaining = 0.0
	pending_clear_result = {
		"rows": [],
		"cells": []
	}
	can_hold = true
	_spawn_next_piece()


func _spawn_next_piece() -> void:
	_fill_queue()
	var next_name: String = queue.pop_front()
	current_piece = _create_piece(next_name)
	if not board.can_place(current_piece["blocks"], current_piece["origin"]):
		game_over = true
		current_piece = {}
	can_hold = true
	_fill_queue()


func _fill_queue() -> void:
	while queue.size() < rules.visible_queue + 1:
		if _bag.is_empty():
			_bag.assign(Array(rules.piece_names()))
			_shuffle(_bag)
		queue.append(_bag.pop_back())


func _shuffle(values: Array[String]) -> void:
	for i in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, i)
		var temp := values[i]
		values[i] = values[swap_index]
		values[swap_index] = temp


func _create_piece(name: String) -> Dictionary:
	var definition: Dictionary = rules.piece_defs()[name]
	var blocks: Array = _blocks_with_central_pivot(definition["blocks"].duplicate())
	var spawn_origin := _spawn_origin(blocks)
	return {
		"name": name,
		"blocks": blocks,
		"color": definition["color"],
		"origin": spawn_origin
	}


func _spawn_origin(blocks: Array) -> Vector3i:
	var bounds := _bounds(blocks)
	var min_bounds: Vector3i = bounds["min"]
	var max_bounds: Vector3i = bounds["max"]
	var span_x: int = max_bounds.x - min_bounds.x + 1
	var span_z: int = max_bounds.z - min_bounds.z + 1
	var origin_x := int(floor((rules.board_size.x - span_x) / 2.0)) - min_bounds.x
	var origin_z := int(floor((rules.board_size.z - span_z) / 2.0)) - min_bounds.z
	var origin_y: int = rules.board_size.y - 1 - max_bounds.y
	return Vector3i(origin_x, origin_y, origin_z)


func _rotate_blocks(blocks: Array, axis: String, direction: int) -> Array:
	var pivot: Vector3i = blocks[0]
	var rotated: Array = []
	for block in blocks:
		var local: Vector3i = block - pivot
		var next_local := local
		match axis:
			"x":
				next_local = Vector3i(local.x, -direction * local.z, direction * local.y)
			"y":
				next_local = Vector3i(direction * local.z, local.y, -direction * local.x)
			"z":
				next_local = Vector3i(-direction * local.y, direction * local.x, local.z)
		rotated.append(pivot + next_local)
	return rotated


func _bounds(blocks: Array) -> Dictionary:
	var min_block: Vector3i = blocks[0]
	var max_block: Vector3i = blocks[0]
	for block in blocks:
		min_block = Vector3i(min(min_block.x, block.x), min(min_block.y, block.y), min(min_block.z, block.z))
		max_block = Vector3i(max(max_block.x, block.x), max(max_block.y, block.y), max(max_block.z, block.z))
	return {
		"min": min_block,
		"max": max_block
	}


func _blocks_with_central_pivot(blocks: Array) -> Array:
	var centroid := Vector3.ZERO
	for block in blocks:
		centroid += Vector3(block.x, block.y, block.z)
	centroid /= float(blocks.size())

	var pivot_index := 0
	var best_distance := INF
	for i in range(blocks.size()):
		var block: Vector3i = blocks[i]
		var offset := Vector3(block.x, block.y, block.z) - centroid
		var distance := offset.length_squared()
		if distance < best_distance:
			best_distance = distance
			pivot_index = i

	if pivot_index == 0:
		return blocks

	var reordered: Array = [blocks[pivot_index]]
	for i in range(blocks.size()):
		if i != pivot_index:
			reordered.append(blocks[i])
	return reordered
