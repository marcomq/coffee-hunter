extends SceneTree

const GameStateClass = preload("res://scripts/game_state.gd")
const InputResolverClass = preload("res://scripts/input_resolver.gd")
const LevelDataClass = preload("res://scripts/level_data.gd")
const GameAudioClass = preload("res://scripts/audio.gd")
const SaveDataClass = preload("res://scripts/save_data.gd")
var failures := 0


func _init() -> void:
	_test_scripts_compile()
	_test_arrow_key_bindings()
	_test_input_deadzone_and_hysteresis()
	_test_waits_for_start()
	_test_original_level_progression()
	_test_levels_never_run_out()
	_test_the_run_continues_past_the_last_authored_level()
	_test_level_layout_varies()
	_test_bean_count_and_score_rise_per_level()
	_test_ultra_chaser_stays_out_of_early_levels()
	_test_tea_pots_start_at_level_three()
	_test_enemy_kind_speeds()
	_test_randomized_placement_is_valid()
	_test_enemies_appear_gradually()
	_test_multiple_filters_fall()
	_test_fresh_tunnel_delays_filter()
	_test_move_and_dig()
	_test_collect_and_score()
	_test_extra_life_at_score_threshold()
	_test_bounds()
	_test_life_loss()
	_test_grazing_an_enemy_is_survivable()
	_test_walking_through_an_enemy_is_fatal()
	_test_a_walk_in_is_never_escapable()
	_test_walled_in_bean_rebuilds_the_level()
	_test_reachable_bean_never_rebuilds_the_level()
	_test_falling_filter_is_instantly_lethal()
	_test_respawn_is_briefly_invulnerable()
	_test_respawn_shield_lasts_several_seconds()
	_test_filter_landing_is_announced()
	_test_realtime_ticks_are_decoupled()
	_test_enemy_prefers_forward_motion()
	_test_falling_filter_kills_enemy()
	_test_squashed_enemies_stay_squashed_after_a_life_is_lost()
	_test_squashed_pods_come_back_from_the_nest()
	_test_a_chain_of_squashes_pays_more()
	_test_high_score_survives_a_restart()
	_test_every_sound_effect_exists()
	_test_menu_keys_are_bound()
	_test_filter_pushes_sideways_through_soil()
	_test_filter_push_blockers()
	_test_win()
	if failures == 0:
		print("PASS: all Coffee Hunter tests")
	quit(failures)


func _test_scripts_compile() -> void:
	# A compile error in a depended script otherwise leaves every check unrun and
	# the suite reporting PASS.
	_expect(GameStateClass.new() != null, "game_state.gd compiles")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _test_arrow_key_bindings() -> void:
	var left_bound := false
	var right_bound := false
	for event in InputMap.action_get_events("move_left"):
		left_bound = left_bound or (event is InputEventKey and event.keycode == KEY_LEFT)
	for event in InputMap.action_get_events("move_right"):
		right_bound = right_bound or (event is InputEventKey and event.keycode == KEY_RIGHT)
	_expect(left_bound and right_bound, "logical left and right arrow keys are bound")


func _test_enemy_kind_speeds() -> void:
	var game := _started_game()
	var player_time := game.player_step_time()
	_expect(is_equal_approx(game.enemy_step_time_for_kind(&"teapot"), player_time), "tea pot moves at player speed")
	_expect(game.enemy_step_time_for_kind(&"ultra") < player_time, "ultra ape moves faster than the player")
	_expect(game.enemy_step_time_for_kind(&"teapod") > player_time, "tea pod keeps its slower pace")


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
	var enemies_before := game.enemies.duplicate()
	var filters_before := game.falling_filters.duplicate()
	_expect(not game.move_player(Vector2i.RIGHT), "player waits for first input")
	_expect(not game.tick_enemy() and not game.tick_filter(), "world waits before start")
	_expect(game.player == player_before and game.enemies == enemies_before and game.falling_filters == filters_before, "ready world remains still")
	game.start_game()
	_expect(game.phase == GameStateClass.Phase.PLAYING, "first input starts game")


func _test_original_level_progression() -> void:
	_expect(LevelDataClass.FILTER_COUNT == 12, "original filter count is preserved")
	_expect(LevelDataClass.BEAN_VALUES == [40, 80, 120, 160], "bean tiers keep the original 40-per-step value ladder")
	for level_index in range(1, LevelDataClass.LEVEL_COUNT):
		var previous_speed := LevelDataClass.speed(level_index - 1)
		var speed := LevelDataClass.speed(level_index)
		_expect(speed > previous_speed, "speed rises at level %d" % (level_index + 1))
		_expect(speed / previous_speed < 1.15, "no level raises pace by more than 15%% (level %d)" % (level_index + 1))
		_expect(LevelDataClass.tea_pod_count(level_index) >= LevelDataClass.tea_pod_count(level_index - 1), "tea-pod count never drops (level %d)" % (level_index + 1))
		_expect(LevelDataClass.tea_pod_count(level_index) - LevelDataClass.tea_pod_count(level_index - 1) <= 1, "tea-pod count grows by at most one (level %d)" % (level_index + 1))
	_expect(LevelDataClass.tea_pod_count(0) == 2 and LevelDataClass.tea_pod_count(9) == 9, "tea-pod ramp is gentler than one extra pod per level")


func _test_bean_count_and_score_rise_per_level() -> void:
	_expect(LevelDataClass.coffee_count(0) == 6, "the first level holds only a handful of beans")
	for level_index in range(1, LevelDataClass.LEVEL_COUNT):
		_expect(LevelDataClass.coffee_count(level_index) > LevelDataClass.coffee_count(level_index - 1), "bean count rises at level %d" % (level_index + 1))
		_expect(LevelDataClass.level_score(level_index) > LevelDataClass.level_score(level_index - 1), "level score rises at level %d" % (level_index + 1))
	_expect(LevelDataClass.coffee_count(9) > LevelDataClass.coffee_count(0) * 2, "late levels hold far more beans than the first")
	var richest_tier := LevelDataClass.BEAN_VALUES.size() - 1
	_expect(LevelDataClass.bean_value(richest_tier) > LevelDataClass.bean_value(0), "bigger bean piles are worth more")
	# every tier used on a level must be reachable through bean_tier()
	for level_index in range(LevelDataClass.LEVEL_COUNT):
		var tier_totals := [0, 0, 0, 0]
		for bean_index in range(LevelDataClass.coffee_count(level_index)):
			tier_totals[LevelDataClass.bean_tier(level_index, bean_index)] += 1
		for tier in range(LevelDataClass.BEAN_COUNTS.size()):
			_expect(tier_totals[tier] == LevelDataClass.BEAN_COUNTS[tier][level_index], "bean_tier reproduces the configured tier mix (level %d tier %d)" % [level_index + 1, tier])


func _test_ultra_chaser_stays_out_of_early_levels() -> void:
	var game := GameStateClass.new()
	for enemy_index in range(game.enemies.size()):
		_expect(not game.is_ultra(enemy_index), "no relentless chaser exists in level 1")
	while game.level_index < LevelDataClass.ULTRA_FIRST_LEVEL:
		game.phase = GameStateClass.Phase.WON
		_expect(game.next_level(), "advancing to level %d" % (game.level_index + 2))
	var ultra_index := LevelDataClass.tea_pod_count(game.level_index) - 1
	_expect(game.is_ultra(ultra_index), "the relentless chaser joins from level %d" % (LevelDataClass.ULTRA_FIRST_LEVEL + 1))
	_expect(game.enemy_spawn_ticks[ultra_index] == LevelDataClass.ULTRA_SPAWN_TICK, "the chaser enters after a short fixed delay")
	_expect(game.enemy_spawn_ticks[ultra_index] > game.enemy_spawn_ticks[0], "the chaser enters after the ordinary pods")


func _test_tea_pots_start_at_level_three() -> void:
	var game := GameStateClass.new()
	for enemy_index in range(game.enemies.size()):
		_expect(game.enemy_kind(enemy_index) != &"teapot", "level 1 has no tea pots")
	game.phase = GameStateClass.Phase.WON
	game.next_level()
	for enemy_index in range(game.enemies.size()):
		_expect(game.enemy_kind(enemy_index) != &"teapot", "level 2 has no tea pots")
	game.phase = GameStateClass.Phase.WON
	game.next_level()
	_expect(game.enemy_kind(1) == &"teapot", "tea pots join in level 3")


func _test_randomized_placement_is_valid() -> void:
	var game := GameStateClass.new()
	_expect(game.beans.size() == LevelDataClass.coffee_count(0), "random placement preserves coffee count")
	var placed_score := 0
	for tier in game.beans.values():
		placed_score += LevelDataClass.bean_value(tier)
	_expect(placed_score == LevelDataClass.level_score(0), "placed beans are worth the level's configured score")
	_expect(game.falling_filters.size() == LevelDataClass.FILTER_COUNT, "random placement preserves filter count")
	for filter_cell in game.falling_filters:
		_expect(not game.beans.has(filter_cell) and not game.beans.has(filter_cell + Vector2i.DOWN), "random filter has clear soil below")


func _test_enemies_appear_gradually() -> void:
	var game := _started_game()
	_expect(game.is_enemy_active(0) and not game.is_enemy_active(1), "only first tea-pod is initially active")
	game.tick_enemy()
	_expect(not game.is_enemy_active(1), "second tea-pod remains delayed after one tick")
	game.tick_enemy()
	_expect(game.is_enemy_active(1), "tea-pods activate one after another")


func _test_multiple_filters_fall() -> void:
	var game := _started_game()
	var before := game.falling_filters.duplicate()
	_expect(before.size() == 12, "level uses the original count of twelve falling filters")
	for filter_cell in before:
		game.set_cell(filter_cell + Vector2i.DOWN, GameStateClass.Cell.TUNNEL)
	game.tick_filter()
	for filter_index in range(before.size()):
		_expect(game.falling_filters[filter_index] == before[filter_index] + Vector2i.DOWN, "each exposed filter falls independently")


func _test_fresh_tunnel_delays_filter() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): true}
	game.enemies = [Vector2i(8, 5)]
	game.enemy_alive = [false]
	game.enemy_directions = [Vector2i.ZERO]
	game.enemy_spawn_ticks = [0]
	game.falling_filters = [Vector2i(12, 4)]
	game.falling_filter_states = [false]
	game.player = Vector2i(11, 5)
	game.set_cell(Vector2i(12, 5), GameStateClass.Cell.SOIL)
	game.move_player(Vector2i.RIGHT)
	game.move_player(Vector2i.LEFT)
	_expect(not game.tick_filter(), "filter cannot fall into a freshly dug tunnel")
	game.advance_time(GameStateClass.FRESH_TUNNEL_FALL_DELAY - 0.01)
	_expect(not game.tick_filter(), "fresh-tunnel grace period is independent of filter tick phase")
	game.advance_time(0.02)
	_expect(game.tick_filter(), "filter falls after the full grace period")


func _test_move_and_dig() -> void:
	var game := _started_game()
	game.falling_filters = []
	game.falling_filter_states = []
	game.player = Vector2i(2, 4)
	game.set_cell(Vector2i(3, 4), GameStateClass.Cell.SOIL)
	_expect(game.move_player(Vector2i.RIGHT), "valid move succeeds")
	_expect(game.player == Vector2i(3, 4), "player changes cell")
	_expect(game.get_cell(Vector2i(3, 4)) == GameStateClass.Cell.TUNNEL, "entered soil is dug")


func _test_collect_and_score() -> void:
	var game := _started_game()
	game.player = Vector2i(2, 5)
	game.enemy_alive.fill(false)
	game.beans = {Vector2i(3, 5): 2, Vector2i(15, 5): 0}
	game.falling_filters = [Vector2i(12, 9)]
	game.falling_filter_states = [false]
	game.move_player(Vector2i.RIGHT)
	_expect(not game.beans.has(Vector2i(3, 5)), "coffee is removed")
	_expect(game.score == LevelDataClass.bean_value(2), "coffee awards its tier value, not a flat rate")


func _test_extra_life_at_score_threshold() -> void:
	var game := _started_game()
	game.enemy_alive.fill(false)
	game.falling_filters = []
	game.falling_filter_states = []
	game.beans = {Vector2i(3, 5): 3, Vector2i(15, 9): 0}
	game.player = Vector2i(2, 5)
	game.score = GameStateClass.EXTRA_LIFE_SCORE - 1
	var lives_before := game.lives
	game.move_player(Vector2i.RIGHT)
	_expect(game.lives == lives_before + 1, "crossing the score threshold grants an extra life")
	_expect(game.next_extra_life_score == GameStateClass.EXTRA_LIFE_SCORE * 2, "the next extra life costs twice as much")


func _test_bounds() -> void:
	var game := _started_game()
	game.player = Vector2i.ZERO
	_expect(not game.move_player(Vector2i.LEFT), "cannot leave map")
	_expect(game.player == Vector2i.ZERO, "blocked move preserves position")


func _test_life_loss() -> void:
	var game := _started_game()
	game.player = Vector2i(7, 5)
	game.enemies = [Vector2i(8, 5)]
	game.enemy_prev = [Vector2i(8, 5)]
	game.enemy_alive = [true]
	game.enemy_directions = [Vector2i.RIGHT]
	game.enemy_spawn_ticks = [0]
	game.falling_filters = [Vector2i(12, 9)]
	game.falling_filter_states = [false]
	game.move_player(Vector2i.RIGHT)
	_expect(game.lives == 3, "the hit lands when the sprites meet, not on the key press")
	game.advance_time(game.player_touch_delay() + 0.01)
	game.tick_contacts()
	_expect(game.lives == 2, "walking into a tea-pod always costs a life")
	_expect(game.player == game.player_start, "player respawns")


func _test_grazing_an_enemy_is_survivable() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.falling_filters = []
	game.falling_filter_states = []
	var corridor := game.corridor_y
	game.enemies = [Vector2i(6, corridor)]
	game.enemy_prev = [Vector2i(6, corridor)]
	game.enemy_alive = [true]
	game.enemy_directions = [Vector2i.RIGHT]
	game.enemy_spawn_ticks = [0]
	game.player = Vector2i(7, corridor)
	game.tick_enemy()
	_expect(game.enemies[0] == Vector2i(7, corridor), "the tea-pod catches up with the player")
	_expect(game.lives == 3, "being caught from behind opens a grace window")
	game.advance_time(game.enemy_touch_delay() * 0.5)
	game.tick_contacts()
	_expect(game.lives == 3, "the pod's sprite has not arrived yet")
	game.move_player(Vector2i.UP)
	_expect(game.lives == 3, "slipping out sideways before it lands survives")
	game.advance_time(1.0)
	game.tick_contacts()
	_expect(game.lives == 3, "the grace window resets once contact is broken")


func _test_walking_through_an_enemy_is_fatal() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.falling_filters = []
	game.falling_filter_states = []
	var corridor := game.corridor_y
	game.enemies = [Vector2i(6, corridor)]
	game.enemy_prev = [Vector2i(6, corridor)]
	game.enemy_alive = [true]
	game.enemy_directions = [Vector2i.RIGHT]
	game.enemy_spawn_ticks = [0]
	game.player = Vector2i(7, corridor)
	game.tick_enemy()
	_expect(game.lives == 3, "the grace window opens when the pod arrives")
	game.move_player(Vector2i.LEFT)
	_expect(game.lives == 2, "swapping cells with a tea-pod is a head-on hit")


func _test_a_walk_in_is_never_escapable() -> void:
	var game := GameStateClass.new()
	for level_index in range(LevelDataClass.LEVEL_COUNT):
		game.level_index = level_index
		var latest_touch := maxf(game.player_touch_delay(), game.enemy_touch_delay())
		_expect(latest_touch < game.player_step_time(), "contact always lands before the player can step away again (level %d)" % (level_index + 1))


func _test_walled_in_bean_rebuilds_the_level() -> void:
	var game := _started_game()
	var bean := Vector2i(4, 2)
	game.beans = {bean: 0}
	game.falling_filters = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				game.falling_filters.append(bean + Vector2i(dx, dy))
	game.falling_filter_states.resize(game.falling_filters.size())
	game.falling_filter_states.fill(false)
	# The ring has to rest on solid ground, or the bottom row drops away into
	# whichever corridor this level happened to carve underneath it.
	for dx in range(-1, 2):
		game.set_cell(bean + Vector2i(dx, 2), GameStateClass.Cell.SOIL)
	_expect(not game.all_beans_reachable(), "a bean ringed by unpushable filters is unreachable")
	# GDScript lambdas capture by value, so the flag has to live in a reference type.
	var rebuilds: Array[Vector2i] = []
	game.event_emitted.connect(func(kind: StringName, cell: Vector2i) -> void:
		if kind == &"level_reshuffled":
			rebuilds.append(cell)
	)
	game.tick_filter()
	_expect(rebuilds.is_empty(), "one settled tick is not enough to rebuild the level")
	game.advance_time(GameStateClass.DEADLOCK_CONFIRM_TIME + 0.01)
	game.tick_filter()
	_expect(rebuilds.size() == 1, "a dead end that persists rebuilds the level")
	_expect(game.beans.size() == 1, "only the beans still owed are laid out again")
	_expect(game.all_beans_reachable(), "the rebuilt level is solvable")
	_expect(game.score == 0 and game.lives == 3, "the rescue costs neither score nor a life")
	_expect(game.falling_filters.size() == LevelDataClass.FILTER_COUNT, "the rebuilt level has a full set of filters")


func _test_reachable_bean_never_rebuilds_the_level() -> void:
	var game := _started_game()
	var beans_before := game.beans.size()
	for step in range(20):
		game.advance_time(GameStateClass.DEADLOCK_CONFIRM_TIME)
		game.tick_filter()
	_expect(game.beans.size() == beans_before, "an ordinary level is never rescued")


func _test_falling_filter_is_instantly_lethal() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.enemy_alive.fill(false)
	game.player = Vector2i(12, 5)
	game.set_cell(Vector2i(12, 5), GameStateClass.Cell.TUNNEL)
	game.falling_filters = [Vector2i(12, 4)]
	game.falling_filter_states = [false]
	game.tick_filter()
	_expect(game.lives == 2, "a dropped filter still kills on contact, with no grace")


func _test_respawn_shield_lasts_several_seconds() -> void:
	# main.gd freezes input for 0.7 s while the hit animation plays, so the
	# shield has to outlast that by a clear margin or it protects nothing.
	_expect(GameStateClass.RESPAWN_INVULNERABILITY >= 2.0, "the respawn shield lasts a few seconds")
	_expect(GameStateClass.RESPAWN_INVULNERABILITY > 0.7 + 1.0, "the shield still protects after the hit animation releases input")
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.enemy_alive.fill(false)
	game.falling_filters = []
	game.falling_filter_states = []
	_expect(not game.is_invulnerable(), "an untouched player is not shielded")
	game.lose_life()
	_expect(game.is_invulnerable(), "losing a life raises the shield")
	game.advance_time(0.7)
	_expect(game.is_invulnerable(), "the shield is still up when input unfreezes")
	_expect(game.invulnerability_left() > 1.0, "over a second of shield remains once the player can move again")
	game.advance_time(GameStateClass.RESPAWN_INVULNERABILITY)
	_expect(not game.is_invulnerable(), "the shield expires")
	_expect(game.invulnerability_left() == 0.0, "expired shield reports no time left")


func _test_filter_landing_is_announced() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.enemy_alive.fill(false)
	var corridor := game.corridor_y
	game.player = Vector2i(2, corridor)
	game.falling_filters = [Vector2i(4, corridor - 2)]
	game.falling_filter_states = [false]
	game.set_cell(Vector2i(4, corridor - 1), GameStateClass.Cell.TUNNEL)
	game.set_cell(Vector2i(4, corridor + 1), GameStateClass.Cell.SOIL)
	var landings: Array[Vector2i] = []
	game.event_emitted.connect(func(kind: StringName, cell: Vector2i) -> void:
		if kind == &"filter_landed":
			landings.append(cell))
	game.tick_filter()
	_expect(game.falling_filters[0] == Vector2i(4, corridor - 1) and landings.is_empty(), "a filter in flight announces no landing")
	game.tick_filter()
	_expect(game.falling_filters[0] == Vector2i(4, corridor) and landings.is_empty(), "the filter keeps dropping through the corridor")
	game.tick_filter()
	_expect(landings.size() == 1 and landings[0] == Vector2i(4, corridor), "coming to rest announces exactly one landing")
	game.tick_filter()
	_expect(landings.size() == 1, "a resting filter does not re-announce every tick")


func _test_respawn_is_briefly_invulnerable() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.enemy_alive.fill(false)
	game.player = Vector2i(12, 5)
	game.set_cell(Vector2i(12, 5), GameStateClass.Cell.TUNNEL)
	game.falling_filters = [Vector2i(12, 4)]
	game.falling_filter_states = [false]
	game.tick_filter()
	_expect(game.lives == 2, "filter kills once")
	_expect(game.invulnerable_until > game.world_time, "respawn grants temporary invulnerability")
	game.falling_filters = [game.player_start]
	game.falling_filter_states = [false]
	game._resolve_contacts()
	_expect(game.lives == 2, "the respawn window absorbs an immediate second hit")
	game.advance_time(GameStateClass.RESPAWN_INVULNERABILITY + 0.01)
	game._resolve_contacts()
	_expect(game.lives == 1, "invulnerability expires")


func _test_realtime_ticks_are_decoupled() -> void:
	var game := _started_game()
	game.player = Vector2i(2, game.corridor_y)
	game.enemies = [game.nest_cell()]
	game.enemy_alive = [true]
	game.set_cell(Vector2i(3, 3), GameStateClass.Cell.TUNNEL)
	game.falling_filters = [Vector2i(3, 2)]
	game.falling_filter_states = [false]
	var enemy_before := game.enemies[0]
	var filter_before := game.falling_filters[0]
	game.move_player(Vector2i.RIGHT)
	_expect(game.enemies[0] == enemy_before, "player movement does not advance enemy")
	_expect(game.falling_filters[0] == filter_before, "player movement does not advance filter")
	game.tick_enemy()
	_expect(game.enemies[0] != enemy_before, "enemy advances on its own realtime tick")
	game.tick_filter()
	_expect(game.falling_filters[0] != filter_before, "filter advances on its own realtime tick")


func _test_enemy_prefers_forward_motion() -> void:
	var game := _started_game()
	var nest := game.nest_cell()
	game.enemies = [nest, Vector2i(15, 9)]
	game.enemy_alive = [true, false]
	game.enemy_directions = [Vector2i.RIGHT, Vector2i.ZERO]
	game.player = Vector2i(nest.x, nest.y - 3)
	_expect(game._choose_enemy_direction(0, false) == Vector2i.RIGHT, "normal tea-pod keeps moving forward instead of tracking player")
	_expect(game._choose_enemy_direction(0, true) == Vector2i.UP, "rare chase decision uses dominant axis toward player")


func _test_falling_filter_kills_enemy() -> void:
	var game := _started_game()
	game.player = Vector2i(2, 5)
	game.falling_filters = [Vector2i(12, 4)]
	game.falling_filter_states = [false]
	game.enemies = [Vector2i(12, 5)]
	game.enemy_alive = [true]
	game.set_cell(Vector2i(12, 5), GameStateClass.Cell.TUNNEL)
	game.tick_filter()
	_expect(not game.enemy_alive[0], "falling filter defeats enemy")
	_expect(game.score == GameStateClass.ENEMY_SQUASH_SCORE, "defeating enemy awards score")


func _test_squashed_enemies_stay_squashed_after_a_life_is_lost() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.enemy_alive[0] = false
	game.lose_life()
	_expect(not game.enemy_alive[0], "a squashed tea-pod is not revived by losing a life")
	_expect(game.enemy_alive.size() == LevelDataClass.tea_pod_count(0), "respawn keeps the level's tea-pod roster")
	game.phase = GameStateClass.Phase.WON
	game.next_level()
	_expect(game.enemy_alive.count(true) == game.enemy_alive.size(), "a fresh level revives every tea-pod")


# A filter is shoved sideways through the ground; undug soil is not a barrier,
# matching Level.isFobjectColliding in the original applet.
func _test_filter_pushes_sideways_through_soil() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.enemy_alive.fill(false)
	game.player = Vector2i(3, 1)
	game.set_cell(Vector2i(3, 1), GameStateClass.Cell.TUNNEL)
	game.set_cell(Vector2i(4, 1), GameStateClass.Cell.TUNNEL)
	game.falling_filters = [Vector2i(4, 1)]
	game.falling_filter_states = [false]
	_expect(game.get_cell(Vector2i(5, 1)) == GameStateClass.Cell.SOIL, "the push target is undug soil")
	_expect(game.move_player(Vector2i.RIGHT), "a filter can be shoved into undug soil")
	_expect(game.falling_filters[0] == Vector2i(5, 1), "the pushed filter moves on through the soil")
	_expect(game.player == Vector2i(4, 1), "the player takes the cell the filter left")


func _test_filter_push_blockers() -> void:
	var game := _started_game()
	game.beans = {Vector2i(6, 5): 0, Vector2i(15, 9): 0}
	game.enemy_alive.fill(false)
	game.player = Vector2i(4, 5)
	game.falling_filters = [Vector2i(5, 5)]
	game.falling_filter_states = [false]
	_expect(not game.move_player(Vector2i.RIGHT), "a bean blocks a filter push")

	var stacked := _started_game()
	stacked.beans = {Vector2i(15, 9): 0}
	stacked.enemy_alive.fill(false)
	stacked.player = Vector2i(4, 5)
	stacked.falling_filters = [Vector2i(5, 5), Vector2i(6, 5)]
	stacked.falling_filter_states = [false, false]
	_expect(not stacked.move_player(Vector2i.RIGHT), "another filter blocks a filter push")

	var edge := _started_game()
	edge.beans = {Vector2i(15, 9): 0}
	edge.enemy_alive.fill(false)
	edge.player = Vector2i(15, 5)
	edge.falling_filters = [Vector2i(GameStateClass.WIDTH - 1, 5)]
	edge.falling_filter_states = [false]
	_expect(not edge.move_player(Vector2i.RIGHT), "the map edge blocks a filter push")

	var vertical := _started_game()
	vertical.beans = {Vector2i(15, 9): 0}
	vertical.enemy_alive.fill(false)
	vertical.player = Vector2i(8, 4)
	vertical.falling_filters = [Vector2i(8, 5)]
	vertical.falling_filter_states = [false]
	_expect(not vertical.move_player(Vector2i.DOWN), "filters can never be pushed vertically")

	var live := _started_game()
	live.beans = {Vector2i(15, 9): 0}
	live.player = Vector2i(4, 5)
	live.falling_filters = [Vector2i(5, 5)]
	live.falling_filter_states = [false]
	live.enemies = [Vector2i(6, 5)]
	live.enemy_alive = [true]
	live.enemy_directions = [Vector2i.ZERO]
	live.enemy_spawn_ticks = [0]
	_expect(not live.move_player(Vector2i.RIGHT), "a live tea-pod blocks a filter push")

	var squashed := _started_game()
	squashed.beans = {Vector2i(15, 9): 0}
	squashed.player = Vector2i(4, 5)
	squashed.falling_filters = [Vector2i(5, 5)]
	squashed.falling_filter_states = [false]
	squashed.enemies = [Vector2i(6, 5)]
	squashed.enemy_alive = [false]
	squashed.enemy_directions = [Vector2i.ZERO]
	squashed.enemy_spawn_ticks = [0]
	_expect(squashed.move_player(Vector2i.RIGHT), "a squashed tea-pod no longer blocks a filter push")
	_expect(squashed.falling_filters[0] == Vector2i(6, 5), "the filter slides into the freed cell")


func _test_win() -> void:
	var game := _started_game()
	game.enemy_alive.fill(false)
	game.falling_filters = [Vector2i(12, 9)]
	game.falling_filter_states = [false]
	game.beans = {Vector2i(4, 5): true}
	game.player = Vector2i(3, 5)
	game.move_player(Vector2i.RIGHT)
	_expect(game.phase == GameStateClass.Phase.WON, "last coffee completes level")


# The authored ten levels are only the designed part of the curve; every level
# after them has to keep the same ramps going without ever breaking the board.
func _test_levels_never_run_out() -> void:
	_expect(LevelDataClass.is_endless(LevelDataClass.LEVEL_COUNT), "the first level past the authored set is endless")
	_expect(not LevelDataClass.is_endless(LevelDataClass.LEVEL_COUNT - 1), "the last authored level is not endless")
	var last_speed := LevelDataClass.speed(LevelDataClass.LEVEL_COUNT - 1)
	var last_beans := LevelDataClass.coffee_count(LevelDataClass.LEVEL_COUNT - 1)
	var last_pods := LevelDataClass.tea_pod_count(LevelDataClass.LEVEL_COUNT - 1)
	for level_index in range(LevelDataClass.LEVEL_COUNT, LevelDataClass.LEVEL_COUNT + 40):
		var speed := LevelDataClass.speed(level_index)
		var beans := LevelDataClass.coffee_count(level_index)
		var pods := LevelDataClass.tea_pod_count(level_index)
		_expect(speed >= last_speed and speed <= LevelDataClass.MAX_SPEED, "endless speed rises and stays capped (level %d)" % (level_index + 1))
		_expect(beans >= last_beans, "endless bean count never drops (level %d)" % (level_index + 1))
		_expect(pods >= last_pods and pods <= LevelDataClass.MAX_TEA_PODS, "endless pod count rises and stays capped (level %d)" % (level_index + 1))
		_expect(LevelDataClass.level_score(level_index) >= LevelDataClass.level_score(level_index - 1), "endless level score never drops (level %d)" % (level_index + 1))
		var tier_totals := [0, 0, 0, 0]
		for bean_index in range(beans):
			tier_totals[LevelDataClass.bean_tier(level_index, bean_index)] += 1
		for tier in range(LevelDataClass.BEAN_COUNTS.size()):
			_expect(tier_totals[tier] == LevelDataClass.bean_count(tier, level_index), "endless tier mix stays consistent (level %d tier %d)" % [level_index + 1, tier])
		last_speed = speed
		last_beans = beans
		last_pods = pods


func _test_the_run_continues_past_the_last_authored_level() -> void:
	var game := _started_game()
	game.level_index = LevelDataClass.LEVEL_COUNT - 1
	game.phase = GameStateClass.Phase.WON
	_expect(game.next_level(), "clearing the last authored level does not end the run")
	_expect(game.level_index == LevelDataClass.LEVEL_COUNT, "endless levels keep counting up")
	_expect(game.beans.size() == LevelDataClass.coffee_count(game.level_index), "an endless level is stocked like any other")
	_expect(game.falling_filters.size() == LevelDataClass.FILTER_COUNT, "an endless level keeps the full set of filters")


# The original jittered the cross per level. Nothing that has to stand on a
# corridor may therefore be hardcoded to the old fixed one.
func _test_level_layout_varies() -> void:
	var crosses := {}
	for attempt in range(40):
		var game := GameStateClass.new()
		crosses[game.nest_cell()] = true
		_expect(game.get_cell(game.player_start) == GameStateClass.Cell.TUNNEL, "the player always starts on a corridor")
		_expect(game.player == game.player_start, "a fresh level puts the player on its own start cell")
		_expect(game.get_cell(game.nest_cell()) == GameStateClass.Cell.TUNNEL, "the nest always sits on the cross")
		for enemy_index in range(game.enemies.size()):
			_expect(game.get_cell(game.enemies[enemy_index]) == GameStateClass.Cell.TUNNEL, "every tea-pod starts on a corridor")
			_expect(game.enemies.count(game.enemies[enemy_index]) == 1, "no two tea-pods share a start cell")
	_expect(crosses.size() > 1, "the corridor cross is not the same on every level")


func _test_squashed_pods_come_back_from_the_nest() -> void:
	_expect(GameStateClass.ENEMY_RESPAWN_DELAY >= 10.0, "the respawn wait is deliberately long")
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.player = Vector2i(2, game.corridor_y)
	game.enemies = [Vector2i(12, 4)]
	game.enemy_alive = [true]
	game.enemy_directions = [Vector2i.RIGHT]
	game.enemy_spawn_ticks = [0]
	game.set_cell(Vector2i(12, 4), GameStateClass.Cell.TUNNEL)
	game.falling_filters = [Vector2i(12, 3)]
	game.falling_filter_states = [false]
	game.tick_filter()
	_expect(not game.enemy_alive[0], "the filter squashes the pod")
	game.advance_time(GameStateClass.ENEMY_RESPAWN_DELAY - 1.0)
	game.tick_enemy()
	_expect(not game.enemy_alive[0], "the pod stays out of play for a long while")
	game.advance_time(2.0)
	game.tick_enemy()
	_expect(game.enemy_alive[0], "the pod climbs back out once the wait is over")
	_expect(game.enemies[0] == game.nest_cell(), "it returns to the nest, not to where it died")


func _test_a_chain_of_squashes_pays_more() -> void:
	var game := _started_game()
	game.beans = {Vector2i(15, 9): 0}
	game.player = Vector2i(2, game.corridor_y)
	var column := 3
	for y in range(2, 6):
		game.set_cell(Vector2i(column, y), GameStateClass.Cell.TUNNEL)
	game.enemies = [Vector2i(column, 3), Vector2i(column, 4)]
	game.enemy_alive = [true, true]
	game.enemy_directions = [Vector2i.ZERO, Vector2i.ZERO]
	game.enemy_spawn_ticks = [0, 0]
	game.falling_filters = [Vector2i(column, 2)]
	game.falling_filter_states = [false]
	game.tick_filter()
	_expect(not game.enemy_alive[0], "the dropped filter squashes the first pod")
	_expect(game.score == GameStateClass.ENEMY_SQUASH_SCORE, "the first pod in a drop pays the base score")
	game.tick_filter()
	_expect(not game.enemy_alive[1], "the same filter keeps falling onto the next pod")
	_expect(game.last_squash_score == GameStateClass.ENEMY_SQUASH_SCORE * 2, "the second pod in the same drop pays double")
	_expect(game.score == GameStateClass.ENEMY_SQUASH_SCORE * 3, "the chain is added to the running score")


func _test_high_score_survives_a_restart() -> void:
	var real_path: String = SaveDataClass.path
	SaveDataClass.path = "user://coffee-hunter-test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveDataClass.path))
	_expect(SaveDataClass.high_score() == 0, "a fresh install starts without a high score")
	_expect(SaveDataClass.record_run(1200, 3), "the first run is a record")
	_expect(SaveDataClass.high_score() == 1200 and SaveDataClass.best_level() == 3, "the run is written to disk")
	_expect(not SaveDataClass.record_run(900, 1), "a worse run is not a record")
	_expect(SaveDataClass.high_score() == 1200 and SaveDataClass.best_level() == 3, "a worse run leaves the record alone")
	_expect(SaveDataClass.record_run(2400, 11), "beating the score is a record")
	_expect(SaveDataClass.high_score() == 2400 and SaveDataClass.best_level() == 11, "the new record replaces the old")
	SaveDataClass.set_muted(true)
	_expect(SaveDataClass.is_muted(), "the mute setting is remembered")
	_expect(SaveDataClass.high_score() == 2400, "saving a setting does not clobber the score")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveDataClass.path))
	SaveDataClass.path = real_path


func _test_every_sound_effect_exists() -> void:
	for clip_name in GameAudioClass.CLIPS:
		var path: String = GameAudioClass.CLIP_DIR + String(clip_name) + ".wav"
		_expect(ResourceLoader.exists(path), "sound effect %s is present" % clip_name)
		_expect(GameAudioClass.CLIP_VOLUME.has(clip_name), "sound effect %s has a mix level" % clip_name)


func _test_menu_keys_are_bound() -> void:
	for action in ["restart", "pause", "confirm", "mute", "to_title"]:
		_expect(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "%s is bound to a key" % action)
