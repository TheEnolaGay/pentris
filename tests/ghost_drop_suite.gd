extends RefCounted

const GameRulesScript = preload("res://scripts/core/game_rules.gd")
const RunStateScript = preload("res://scripts/core/run_state.gd")
const BoardStateScript = preload("res://scripts/core/board_state.gd")


static func run(harness: RefCounted) -> void:
	harness.suite("Core")
	_test_board_size(harness)
	_test_row_clear(harness)
	_test_lock_without_clear_spawns_immediately(harness)
	_test_lock_with_clear_pauses_then_resolves(harness)
	_test_pivot_is_near_center_of_mass(harness)
	_test_rotation_keeps_pivot_still(harness)

	harness.suite("GhostDrop")
	_test_spawn_and_ghost(harness)
	_test_empty_board_parity(harness)
	_test_vertical_piece_floor_parity(harness)
	_test_wall_kick_rotation_parity(harness)
	_test_stack_ledge_parity(harness)
	_test_stack_kick_parity(harness)
	_test_post_row_clear_parity(harness)


static func _test_board_size(harness: RefCounted) -> void:
	harness.case("board size")
	var rules: RefCounted = GameRulesScript.new()
	harness.assert_equal(rules.board_size, Vector3i(10, 20, 10), "board size should be 10x20x10")


static func _test_spawn_and_ghost(harness: RefCounted) -> void:
	harness.case("spawn and ghost")
	var run: RefCounted = _new_run(42)
	harness.assert_true(not run.current_piece.is_empty(), "spawned piece should exist")
	var ghost: Vector3i = run.ghost_origin()
	harness.assert_true(ghost.y <= run.current_piece["origin"].y, "ghost piece should not be above active piece")
	harness.assert_equal(ghost, run.landing_origin_for_active(), "ghost origin should use the shared landing helper")


static func _test_row_clear(harness: RefCounted) -> void:
	harness.case("row clear compaction")
	var board: RefCounted = BoardStateScript.new(Vector3i(3, 4, 3))
	for x in range(3):
		board.occupy([Vector3i.ZERO], Vector3i(x, 0, 1), Color.WHITE)
	board.occupy([Vector3i.ZERO], Vector3i(1, 1, 1), Color.WHITE)
	board.occupy([Vector3i.ZERO], Vector3i(0, 1, 0), Color.WHITE)
	var cleared: Dictionary = board.clear_completed_rows()
	harness.assert_equal(cleared["rows"].size(), 1, "expected one completed row to clear")
	harness.assert_true(board.is_occupied(Vector3i(1, 0, 1)), "vertically aligned blocks should fall into the cleared row")
	harness.assert_true(board.is_occupied(Vector3i(0, 1, 0)), "blocks outside the cleared columns should stay in place")


static func _test_lock_without_clear_spawns_immediately(harness: RefCounted) -> void:
	harness.case("lock without clear spawns immediately")
	var run: RefCounted = _new_run()
	run.set_board_cells_for_test([])
	run.current_piece = {
		"name": "Dot",
		"blocks": [Vector3i.ZERO],
		"color": Color.WHITE,
		"origin": Vector3i(4, 5, 4)
	}

	run.hard_drop()

	harness.assert_true(not run.is_clearing(), "locking without a clear should not enter clear pause")
	harness.assert_true(not run.current_piece.is_empty(), "next piece should spawn immediately when nothing clears")
	harness.assert_true(run.board.is_occupied(Vector3i(4, 0, 4)), "locked block should remain on the board")


static func _test_lock_with_clear_pauses_then_resolves(harness: RefCounted) -> void:
	harness.case("lock with clear pauses then resolves")
	var run: RefCounted = _new_run()
	var cells := _cells([
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(4, 0, 0),
		Vector3i(5, 0, 0), Vector3i(6, 0, 0), Vector3i(7, 0, 0), Vector3i(8, 0, 0), Vector3i(0, 1, 0)
	])
	run.set_board_cells_for_test(cells)
	run.current_piece = {
		"name": "Dot",
		"blocks": [Vector3i.ZERO],
		"color": Color.WHITE,
		"origin": Vector3i(9, 5, 0)
	}

	run.hard_drop()

	harness.assert_true(run.is_clearing(), "locking into a completed row should enter clear pause")
	harness.assert_true(run.current_piece.is_empty(), "no next piece should spawn until the clear resolves")
	harness.assert_equal(run.pending_clear_cells().size(), 10, "the full completed row should be pending clear")
	harness.assert_true(run.board.is_occupied(Vector3i(9, 0, 0)), "cleared cells should remain visible during the pause")

	run.advance_clear(run.CLEAR_PAUSE_DURATION * 0.5)
	harness.assert_true(run.is_clearing(), "clear pause should persist until the full delay elapses")
	harness.assert_true(not run.tick(), "gameplay should stay frozen during the clear pause")

	run.advance_clear(run.CLEAR_PAUSE_DURATION)
	harness.assert_true(not run.is_clearing(), "clear pause should end after the delay")
	harness.assert_true(not run.current_piece.is_empty(), "next piece should spawn after the clear resolves")
	harness.assert_equal(run.cleared_rows_total, 1, "resolved clears should update the cleared row count")
	harness.assert_true(run.board.is_occupied(Vector3i(0, 0, 0)), "cells above the cleared row should compact after resolution")
	harness.assert_true(not run.board.is_occupied(Vector3i(9, 0, 0)), "the newly cleared cell should be removed after resolution")


static func _test_pivot_is_near_center_of_mass(harness: RefCounted) -> void:
	harness.case("pivot near center of mass")
	var run: RefCounted = _new_run(11)
	var blocks: Array = run.current_piece["blocks"]
	var centroid := Vector3.ZERO
	for block in blocks:
		centroid += Vector3(block.x, block.y, block.z)
	centroid /= float(blocks.size())
	var pivot_distance := (Vector3(blocks[0].x, blocks[0].y, blocks[0].z) - centroid).length_squared()
	for i in range(1, blocks.size()):
		var block: Vector3i = blocks[i]
		var distance := (Vector3(block.x, block.y, block.z) - centroid).length_squared()
		harness.assert_true(pivot_distance <= distance + 0.0001, "pivot should be the block closest to center of mass")


static func _test_rotation_keeps_pivot_still(harness: RefCounted) -> void:
	harness.case("rotation keeps pivot still")
	var run: RefCounted = _new_run()
	run.set_board_cells_for_test([])
	run.set_active_piece_for_test("F", Vector3i(4, 12, 4))

	var pivot_before: Vector3i = run.pivot_position()
	harness.assert_true(run.rotate_active("y", 1), "y rotation should succeed")
	harness.assert_equal(run.pivot_position(), pivot_before, "y rotation should not move pivot position")

	pivot_before = run.pivot_position()
	harness.assert_true(run.rotate_active("x", 1), "x rotation should succeed")
	harness.assert_equal(run.pivot_position(), pivot_before, "x rotation should not move pivot position")

	pivot_before = run.pivot_position()
	harness.assert_true(run.rotate_active("z", 1), "z rotation should succeed")
	harness.assert_equal(run.pivot_position(), pivot_before, "z rotation should not move pivot position")


static func _test_empty_board_parity(harness: RefCounted) -> void:
	harness.case("empty board parity")
	var run: RefCounted = _new_run()
	run.set_board_cells_for_test([])
	run.set_active_piece_for_test("T", Vector3i(4, 18, 4))
	_assert_ghost_matches_hard_drop(harness, run)


static func _test_vertical_piece_floor_parity(harness: RefCounted) -> void:
	harness.case("vertical piece floor parity")
	var run: RefCounted = _new_run()
	run.set_board_cells_for_test([])
	run.set_active_piece_for_test("I", Vector3i(4, 16, 4), [{"axis": "z", "direction": 1}])
	_assert_ghost_matches_hard_drop(harness, run)


static func _test_wall_kick_rotation_parity(harness: RefCounted) -> void:
	harness.case("wall kick rotation parity")
	var run: RefCounted = _new_run()
	run.set_board_cells_for_test([])
	run.set_active_piece_for_test("L", Vector3i(6, 18, 8))
	harness.assert_true(run.rotate_active("y", 1), "rotation near wall should succeed with a kick")
	_assert_ghost_matches_hard_drop(harness, run)


static func _test_stack_ledge_parity(harness: RefCounted) -> void:
	harness.case("stack ledge parity")
	var run: RefCounted = _new_run()
	run.set_board_cells_for_test(_cells([
		Vector3i(4, 0, 4), Vector3i(4, 1, 4), Vector3i(5, 0, 4),
		Vector3i(6, 0, 4), Vector3i(6, 1, 4), Vector3i(6, 2, 4)
	]))
	run.set_active_piece_for_test("T", Vector3i(4, 12, 4))
	_assert_ghost_matches_hard_drop(harness, run)


static func _test_stack_kick_parity(harness: RefCounted) -> void:
	harness.case("stack kick parity")
	var run: RefCounted = _new_run()
	run.set_board_cells_for_test(_cells([
		Vector3i(4, 0, 5), Vector3i(4, 1, 5), Vector3i(5, 0, 5),
		Vector3i(6, 0, 5), Vector3i(6, 1, 5), Vector3i(7, 0, 5)
	]))
	run.set_active_piece_for_test("Y", Vector3i(4, 14, 5))
	harness.assert_true(run.rotate_active("z", 1), "rotation near stack should succeed with kick support")
	_assert_ghost_matches_hard_drop(harness, run)


static func _test_post_row_clear_parity(harness: RefCounted) -> void:
	harness.case("post row clear parity")
	var run: RefCounted = _new_run()
	run.set_board_cells_for_test(_cells([
		Vector3i(0, 0, 3), Vector3i(1, 0, 3), Vector3i(2, 0, 3), Vector3i(3, 0, 3),
		Vector3i(4, 0, 3), Vector3i(5, 0, 3), Vector3i(6, 0, 3), Vector3i(7, 0, 3),
		Vector3i(8, 0, 3), Vector3i(9, 0, 3), Vector3i(4, 1, 3), Vector3i(2, 2, 2)
	]))
	run.board.clear_completed_rows()
	run.set_active_piece_for_test("P", Vector3i(4, 14, 3))
	_assert_ghost_matches_hard_drop(harness, run)


static func _assert_ghost_matches_hard_drop(harness: RefCounted, configured_run: RefCounted) -> void:
	harness.assert_true(not configured_run.current_piece.is_empty(), "configured run should have an active piece")
	var expected_ghost: Vector3i = configured_run.ghost_origin()
	harness.assert_equal(expected_ghost, configured_run.landing_origin_for_active(), "ghost and landing helper should agree")

	var snapshot: Dictionary = configured_run.snapshot_for_test()
	var drop_run: RefCounted = _new_run()
	drop_run.load_snapshot_for_test(snapshot)

	var expected_blocks: Array = drop_run.current_piece["blocks"].duplicate(true)
	var expected_origin: Vector3i = drop_run.ghost_origin()
	drop_run.hard_drop()

	for block in expected_blocks:
		var block_position: Vector3i = expected_origin + block
		harness.assert_true(
			drop_run.board.is_occupied(block_position),
			"hard drop should occupy %s\n%s" % [str(block_position), _describe_run(drop_run, expected_origin, expected_blocks)]
		)


static func _new_run(seed: int = 1) -> RefCounted:
	return RunStateScript.new(GameRulesScript.new(), seed)


static func _cells(positions: Array[Vector3i], color: Color = Color.WHITE) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for position in positions:
		cells.append({
			"position": position,
			"color": color
		})
	return cells


static func _describe_run(run: RefCounted, expected_origin: Vector3i, expected_blocks: Array) -> String:
	return "piece=%s origin=%s expected_landing=%s blocks=%s occupied=%s" % [
		run.current_piece.get("name", "-"),
		var_to_str(run.current_piece.get("origin", Vector3i.ZERO)),
		var_to_str(expected_origin),
		var_to_str(expected_blocks),
		var_to_str(run.board.occupied_cells().values())
	]
