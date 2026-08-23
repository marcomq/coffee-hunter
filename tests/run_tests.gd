extends SceneTree

const GameStateClass = preload("res://scripts/game_state.gd")
const InputResolverClass = preload("res://scripts/input_resolver.gd")
var failures := 0


func _init() -> void:
	_test_input_deadzone_and_hysteresis()
	_test_waits_for_start()
	_test_multiple_filters_fall()
	_test_move_and_dig()
	_test_collect_and_score()
	_test_bounds()
	_test_life_loss()
	_test_realtime_ticks_are_decoupled()
	_test_falling_filter_kills_enemy()
	_test_win()
	if failures == 0:
		print("PASS: all Coffee Hunter tests")
	quit(failures)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _test_input_deadzone_and_hysteresis() -> void:
	var input := InputResolverClass.new()
	_expect(input.direction_from_vector(Vector2(0.1, 0.0)) == Vector2i.ZERO, "deadzone suppresses noise")
	_expect(input.direction_from_vector(Vector2(0.8, 0.2)) == Vector2i.RIGHT, "dominant horizontal tilt")
	_expect(input.direction_from_vector(Vector2(0.25, 0.0)) == Vector2i.RIGHT, "hysteresis retains direction")
	_expect(input.direction_from_vector(Vector2(0.1, 0.0)) == Vector2i.ZERO, "release zone clears direction")


func _started_game() -> GameState:
	var game := GameStateClass.new()
	game.start_game()
	return game


func _test_waits_for_start() -> void:
	var game := GameStateClass.new()
	var player_before := game.player
	var enemy_before := game.enemy
	var filters_before := game.falling_filters.duplicate()
	_expect(not game.move_player(Vector2i.RIGHT), "player waits for first input")
	_expect(not game.tick_enemy() and not game.tick_filter(), "world waits before start")
	_expect(game.player == player_before and game.enemy == enemy_before and game.falling_filters == filters_before, "ready world remains still")
	game.start_game()
	_expect(game.phase == GameStateClass.Phase.PLAYING, "first input starts game")


func _test_multiple_filters_fall() -> void:
	var game := _started_game()
	var before := game.falling_filters.duplicate()
	_expect(before.size() == 3, "level contains several falling filters")
	game.tick_filter()
	for filter_index in range(before.size()):
		_expect(game.falling_filters[filter_index] == before[filter_index] + Vector2i.DOWN, "each exposed filter falls independently")


func _test_move_and_dig() -> void:
	var game := _started_game()
	game.player = Vector2i(2, 4)
	game.set_cell(Vector2i(3, 4), GameStateClass.Cell.SOIL)
	_expect(game.move_player(Vector2i.RIGHT), "valid move succeeds")
	_expect(game.player == Vector2i(3, 4), "player changes cell")
	_expect(game.get_cell(Vector2i(3, 4)) == GameStateClass.Cell.TUNNEL, "entered soil is dug")


func _test_collect_and_score() -> void:
	var game := _started_game()
	game.player = Vector2i(3, 5)
	game.enemy_alive = false
	game.falling_filters = [Vector2i(12, 9)]
	game.falling_filter_states = [false]
	game.move_player(Vector2i.RIGHT)
	_expect(not game.beans.has(Vector2i(4, 5)), "coffee is removed")
	_expect(game.score == GameStateClass.BEAN_SCORE, "coffee awards score")


func _test_bounds() -> void:
	var game := _started_game()
	game.player = Vector2i.ZERO
	_expect(not game.move_player(Vector2i.LEFT), "cannot leave map")
	_expect(game.player == Vector2i.ZERO, "blocked move preserves position")


func _test_life_loss() -> void:
	var game := _started_game()
	game.player = Vector2i(7, 5)
	game.enemy = Vector2i(8, 5)
	game.falling_filters = [Vector2i(12, 9)]
	game.falling_filter_states = [false]
	game.move_player(Vector2i.RIGHT)
	_expect(game.lives == 2, "enemy contact costs one life")
	_expect(game.player == GameStateClass.START_PLAYER, "player respawns")


func _test_realtime_ticks_are_decoupled() -> void:
	var game := _started_game()
	game.player = Vector2i(2, 5)
	game.enemy = Vector2i(8, 5)
	game.falling_filters = [Vector2i(12, 2)]
	game.falling_filter_states = [false]
	var enemy_before := game.enemy
	var filter_before := game.falling_filters[0]
	game.move_player(Vector2i.RIGHT)
	_expect(game.enemy == enemy_before, "player movement does not advance enemy")
	_expect(game.falling_filters[0] == filter_before, "player movement does not advance filter")
	game.tick_enemy()
	_expect(game.enemy != enemy_before, "enemy advances on its own realtime tick")
	game.tick_filter()
	_expect(game.falling_filters[0] != filter_before, "filter advances on its own realtime tick")


func _test_falling_filter_kills_enemy() -> void:
	var game := _started_game()
	game.player = Vector2i(2, 5)
	game.falling_filters = [Vector2i(12, 4)]
	game.falling_filter_states = [false]
	game.enemy = Vector2i(12, 5)
	game.set_cell(Vector2i(12, 5), GameStateClass.Cell.TUNNEL)
	game.tick_filter()
	_expect(not game.enemy_alive, "falling filter defeats enemy")
	_expect(game.score == 200, "defeating enemy awards score")


func _test_win() -> void:
	var game := _started_game()
	game.enemy_alive = false
	game.falling_filters = [Vector2i(12, 9)]
	game.falling_filter_states = [false]
	game.beans = {Vector2i(4, 5): true}
	game.player = Vector2i(3, 5)
	game.move_player(Vector2i.RIGHT)
	_expect(game.phase == GameStateClass.Phase.WON, "last coffee completes level")
