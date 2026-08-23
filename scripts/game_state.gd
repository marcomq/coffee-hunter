class_name GameState
extends RefCounted

const LevelDataClass = preload("res://scripts/level_data.gd")

signal changed
signal event_emitted(kind: StringName, cell: Vector2i)

enum Cell { SOIL, TUNNEL }
enum Phase { READY, PLAYING, WON, GAME_OVER }

const WIDTH := 17
const HEIGHT := 11
const START_PLAYER := Vector2i(2, 5)
const START_ENEMY := Vector2i(8, 5)
const FRESH_TUNNEL_FALL_DELAY := 1.0
# Pace at speed 2.0; every clock scales with the level speed. The rules own these
# because contact timing is expressed in fractions of a step.
const PLAYER_STEP_TIME := 0.42
const ENEMY_STEP_TIME := 0.95
const FILTER_STEP_TIME := 0.68
# How much of its move an actor has to complete before it counts as present in the
# cell. Sprites overlap long before a step finishes, so this is well under 1.0;
# the exact value is tuned so being caught stays about as escapable as it was.
# Contact turns fatal at the later of the two arrivals, which is what makes a
# graze survivable and a walk-in deadly: escaping needs a whole step.
const CONTACT_TOUCH_FRACTION := 0.35
# Matches the enemy move tween in main.gd; the rules time contact against it.
const ENEMY_MOVE_FRACTION := 0.82
const RESPAWN_INVULNERABILITY := 3.0
const ENEMY_SQUASH_SCORE := 200
const EXTRA_LIFE_SCORE := 2000
# A bean walled in by unpushable filters must persist this long before the level
# is rebuilt, so a filter still settling does not trigger a rescue.
const DEADLOCK_CONFIRM_TIME := 2.0
# Squashed pods crawl back out of the nest after a long wait, as in the original
# (Monster.java: `wait = 800/parent.speed`). Deliberately slow and deliberately
# not speed-scaled: late levels are dense enough without a fast conveyor belt.
const ENEMY_RESPAWN_DELAY := 14.0
# A rock that catches several enemies in one drop is the Dig Dug reward; every
# further pod in the same fall doubles the payout.
const MULTI_SQUASH_MULTIPLIER := 2
# Where pods queue up around the nest. Offsets, because the cross moves per level.
const ENEMY_START_OFFSETS := [
	Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0),
	Vector2i(0, -3), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -4),
]

var cells: Array[int] = []
var beans: Dictionary = {}
var player := START_PLAYER
var player_facing := Vector2i.DOWN
var enemies: Array[Vector2i] = []
var enemy_alive: Array[bool] = []
var enemy_directions: Array[Vector2i] = []
var enemy_spawn_ticks: Array[int] = []
var enemy_tick := 0
var falling_filters: Array[Vector2i] = []
var falling_filter_states: Array[bool] = []
var level_filter_starts: Array[Vector2i] = []
var score := 0
var lives := 3
var phase := Phase.READY
var level_index := 0
var enemy_random := RandomNumberGenerator.new()
var layout_random := RandomNumberGenerator.new()
var world_time := 0.0
var tunnel_opened_at: Dictionary = {}
var enemy_contact_since := -1.0
var invulnerable_until := 0.0
var next_extra_life_score := EXTRA_LIFE_SCORE
var player_prev := START_PLAYER
var player_moved_at := -1.0
var player_arrives_at := 0.0
var enemy_prev: Array[Vector2i] = []
var enemy_arrives_at: Array[float] = []
var deadlock_since := -1.0
var corridor_y := START_PLAYER.y
var shaft_x := START_ENEMY.x
var branch_x := 12
var branch_y := 7
var player_start := START_PLAYER
var enemy_respawn_at: Array[float] = []
var filter_kill_streak: Array[int] = []
var last_squash_score := ENEMY_SQUASH_SCORE


func _init() -> void:
	new_game()


func new_game() -> void:
	level_index = 0
	score = 0
	lives = 3
	next_extra_life_score = EXTRA_LIFE_SCORE
	_load_level()


# The run never ends: past the authored levels LevelData keeps extending the ramp.
func next_level() -> bool:
	if phase != Phase.WON:
		return false
	level_index += 1
	_load_level()
	return true


func _load_level() -> void:
	cells.resize(WIDTH * HEIGHT)
	cells.fill(Cell.SOIL)
	beans.clear()
	world_time = 0.0
	invulnerable_until = 0.0
	deadlock_since = -1.0
	tunnel_opened_at.clear()
	phase = Phase.READY
	_carve_initial_tunnels()
	_randomize_level_objects()
	_reset_actors(true)
	changed.emit()


# The original jittered the cross per level (LevelN's middleX/middleY); a fixed
# one made every board read the same. Anything that must sit on a corridor - the
# player start, the nest - is derived from these four numbers, never hardcoded.
func _carve_initial_tunnels() -> void:
	layout_random.randomize()
	corridor_y = layout_random.randi_range(4, 6)
	shaft_x = layout_random.randi_range(6, 10)
	branch_x = layout_random.randi_range(shaft_x + 3, WIDTH - 3)
	var branch_offset := 2 if layout_random.randi_range(0, 1) == 0 else -2
	branch_y = clampi(corridor_y + branch_offset, 1, HEIGHT - 2)
	player_start = Vector2i(2, corridor_y)
	for x in range(1, WIDTH - 1):
		set_cell(Vector2i(x, corridor_y), Cell.TUNNEL)
	for y in range(1, HEIGHT - 1):
		set_cell(Vector2i(shaft_x, y), Cell.TUNNEL)
	for x in range(mini(shaft_x, branch_x), maxi(shaft_x, branch_x) + 1):
		set_cell(Vector2i(x, branch_y), Cell.TUNNEL)
	for y in range(mini(corridor_y, branch_y), maxi(corridor_y, branch_y) + 1):
		set_cell(Vector2i(branch_x, y), Cell.TUNNEL)


func _reset_actors(revive_enemies: bool) -> void:
	player = player_start
	player_facing = Vector2i.DOWN
	player_prev = player_start
	player_moved_at = -1.0
	player_arrives_at = 0.0
	enemy_contact_since = -1.0
	var survivors := enemy_alive.duplicate()
	enemies.clear()
	enemy_directions.clear()
	enemy_spawn_ticks.clear()
	enemy_tick = 0
	enemy_random.seed = 0xC0FFEE + level_index
	var pod_count := LevelDataClass.tea_pod_count(level_index)
	if revive_enemies:
		enemy_alive.clear()
		enemy_alive.resize(pod_count)
		enemy_alive.fill(true)
		enemy_respawn_at.clear()
	for enemy_index in range(pod_count):
		enemies.append(_enemy_start(enemy_index))
		enemy_directions.append([Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][enemy_index % 4])
		enemy_spawn_ticks.append(_enemy_spawn_tick(enemy_index))
	if not revive_enemies:
		enemy_alive.assign(survivors)
	enemy_prev.assign(enemies)
	enemy_arrives_at.clear()
	enemy_arrives_at.resize(enemies.size())
	enemy_arrives_at.fill(0.0)
	falling_filters.assign(level_filter_starts)
	falling_filter_states.resize(level_filter_starts.size())
	falling_filter_states.fill(false)
	_sync_parallel_arrays()


func _enemy_spawn_tick(enemy_index: int) -> int:
	if is_ultra(enemy_index):
		return LevelDataClass.ULTRA_SPAWN_TICK
	return enemy_index * 2


func is_ultra(enemy_index: int) -> bool:
	return LevelDataClass.has_ultra(level_index) and enemy_index == LevelDataClass.tea_pod_count(level_index) - 1


func enemy_kind(enemy_index: int) -> StringName:
	if is_ultra(enemy_index):
		return &"ultra"
	var tea_pots_enabled := level_index >= LevelDataClass.TEAPOT_FIRST_LEVEL
	return &"teapot" if tea_pots_enabled and enemy_index % 3 == 1 else &"teapod"


func _randomize_level_objects() -> void:
	var bean_tiers: Array[int] = []
	for coffee_index in range(LevelDataClass.coffee_count(level_index)):
		bean_tiers.append(LevelDataClass.bean_tier(level_index, coffee_index))
	_place_objects(bean_tiers)


func _place_objects(bean_tiers: Array[int]) -> void:
	layout_random.randomize()
	var soil_cells: Array[Vector2i] = []
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			var cell := Vector2i(x, y)
			if get_cell(cell) == Cell.SOIL:
				soil_cells.append(cell)
	_shuffle_cells(soil_cells)
	for coffee_index in range(bean_tiers.size()):
		beans[soil_cells[coffee_index]] = bean_tiers[coffee_index]
	_shuffle_cells(soil_cells)
	level_filter_starts.clear()
	for cell in soil_cells:
		var below := cell + Vector2i.DOWN
		if beans.has(cell) or beans.has(below) or get_cell(below) != Cell.SOIL or level_filter_starts.has(below) or level_filter_starts.has(cell - Vector2i.DOWN):
			continue
		level_filter_starts.append(cell)
		if level_filter_starts.size() == LevelDataClass.FILTER_COUNT:
			break


func _shuffle_cells(cells_to_shuffle: Array[Vector2i]) -> void:
	for index_to_swap in range(cells_to_shuffle.size() - 1, 0, -1):
		var random_index := layout_random.randi_range(0, index_to_swap)
		var swap := cells_to_shuffle[index_to_swap]
		cells_to_shuffle[index_to_swap] = cells_to_shuffle[random_index]
		cells_to_shuffle[random_index] = swap


func nest_cell() -> Vector2i:
	return Vector2i(shaft_x, corridor_y)


func _enemy_start(enemy_index: int) -> Vector2i:
	var offset: Vector2i = ENEMY_START_OFFSETS[enemy_index % ENEMY_START_OFFSETS.size()]
	return (nest_cell() + offset).clamp(Vector2i.ONE, Vector2i(WIDTH - 2, HEIGHT - 2))


# Scenarios assign the actor arrays wholesale, so the parallel bookkeeping is
# brought back in step here instead of at every call site. New slots start
# neutral: no pending respawn, no kill streak.
func _sync_parallel_arrays() -> void:
	while enemy_respawn_at.size() < enemies.size():
		enemy_respawn_at.append(-1.0)
	enemy_respawn_at.resize(enemies.size())
	if enemy_arrives_at.size() != enemies.size():
		enemy_arrives_at.resize(enemies.size())
	if enemy_prev.size() != enemies.size():
		enemy_prev.assign(enemies)
	if filter_kill_streak.size() != falling_filters.size():
		filter_kill_streak.resize(falling_filters.size())


func start_game() -> void:
	if phase == Phase.READY:
		phase = Phase.PLAYING
		changed.emit()


func is_invulnerable() -> bool:
	return phase == Phase.PLAYING and world_time < invulnerable_until


func invulnerability_left() -> float:
	return maxf(invulnerable_until - world_time, 0.0)


func advance_time(delta: float) -> void:
	if phase == Phase.PLAYING:
		world_time += delta


func player_step_time() -> float:
	return PLAYER_STEP_TIME * 2.0 / LevelDataClass.speed(level_index)


func enemy_step_time() -> float:
	return ENEMY_STEP_TIME * 2.0 / LevelDataClass.speed(level_index)


func enemy_step_time_for_kind(kind: StringName) -> float:
	if kind == &"ultra":
		return player_step_time() * 0.8
	if kind == &"teapot":
		return player_step_time()
	return enemy_step_time()


func filter_step_time() -> float:
	return FILTER_STEP_TIME * 2.0 / LevelDataClass.speed(level_index)


func player_touch_delay() -> float:
	return player_step_time() * CONTACT_TOUCH_FRACTION


func enemy_touch_delay(enemy_index: int = -1) -> float:
	var step_time := enemy_step_time()
	if enemy_index >= 0:
		step_time = enemy_step_time_for_kind(enemy_kind(enemy_index))
	return step_time * ENEMY_MOVE_FRACTION * CONTACT_TOUCH_FRACTION


func index(cell: Vector2i) -> int:
	return cell.y * WIDTH + cell.x


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT


func get_cell(cell: Vector2i) -> int:
	return cells[index(cell)] if is_inside(cell) else Cell.SOIL


func set_cell(cell: Vector2i, value: int) -> void:
	if is_inside(cell):
		cells[index(cell)] = value


func move_player(direction: Vector2i) -> bool:
	if phase != Phase.PLAYING or direction == Vector2i.ZERO:
		return false
	_sync_parallel_arrays()
	var target := player + direction
	if not is_inside(target):
		return false

	var filter_index := falling_filters.find(target)
	if filter_index >= 0:
		if direction.y != 0:
			return false
		# A filter ploughs sideways through undug soil; only beans, other
		# filters, live tea-pods and the map edge stop it.
		var pushed_to := target + direction
		if not is_inside(pushed_to):
			return false
		if _active_enemy_at(pushed_to) >= 0 or beans.has(pushed_to) or falling_filters.has(pushed_to):
			return false
		falling_filters[filter_index] = pushed_to

	player_prev = player
	player_moved_at = world_time
	player_arrives_at = world_time + player_touch_delay()
	player = target
	player_facing = direction
	if get_cell(player) == Cell.SOIL:
		set_cell(player, Cell.TUNNEL)
		tunnel_opened_at[player] = world_time
		event_emitted.emit(&"dug", player)
	_collect_at_player()
	_resolve_contacts()
	changed.emit()
	return true


func tick_filter() -> bool:
	if phase != Phase.PLAYING:
		return false
	_sync_parallel_arrays()
	var moved := _advance_filter()
	if moved:
		_resolve_contacts()
		changed.emit()
		deadlock_since = -1.0
	else:
		# Nothing fell, so the board is settled and worth testing for a walled-in bean.
		_check_deadlock()
	return moved


# Contact grace is a real-time window, so it must be sampled every frame rather
# than only on the enemy's own tick.
func tick_contacts() -> void:
	if phase != Phase.PLAYING:
		return
	_sync_parallel_arrays()
	var lives_before := lives
	_resolve_contacts()
	if lives != lives_before:
		changed.emit()


func tick_enemy(kind: StringName = &"all") -> bool:
	if phase != Phase.PLAYING:
		return false
	_sync_parallel_arrays()
	var moved := _advance_enemy(kind)
	# Reviving after the advance leaves a returning pod standing at the nest for
	# one tick, so the player sees it arrive before it starts hunting.
	var revived := _revive_enemies()
	# Always resolve: a cornered player is touched by an enemy that cannot move.
	_resolve_contacts()
	if moved or revived:
		changed.emit()
	return moved


# Squashed pods come back at the nest once their long wait is over. The nest has
# to be clear first, or a pod would materialise straight on top of the player.
func _revive_enemies() -> bool:
	var revived := false
	for enemy_index in range(enemies.size()):
		if enemy_alive[enemy_index] or enemy_respawn_at[enemy_index] < 0.0:
			continue
		if world_time < enemy_respawn_at[enemy_index]:
			continue
		var nest := _enemy_start(enemy_index)
		if nest == player or falling_filters.has(nest) or _active_enemy_at(nest) >= 0:
			continue
		enemy_alive[enemy_index] = true
		enemy_respawn_at[enemy_index] = -1.0
		enemies[enemy_index] = nest
		enemy_prev[enemy_index] = nest
		enemy_arrives_at[enemy_index] = world_time
		enemy_directions[enemy_index] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][enemy_index % 4]
		event_emitted.emit(&"enemy_respawned", nest)
		revived = true
	return revived


func _collect_at_player() -> void:
	if not beans.has(player):
		return
	var tier: int = beans[player]
	beans.erase(player)
	_add_score(LevelDataClass.bean_value(tier))
	event_emitted.emit(&"coffee", player)
	if beans.is_empty():
		phase = Phase.WON
		event_emitted.emit(&"won", player)


func _advance_filter() -> bool:
	var moved := false
	for filter_index in range(falling_filters.size()):
		var below := falling_filters[filter_index] + Vector2i.DOWN
		var support_is_mature := not tunnel_opened_at.has(below) or world_time - float(tunnel_opened_at[below]) >= FRESH_TUNNEL_FALL_DELAY
		var can_fall := is_inside(below) and get_cell(below) == Cell.TUNNEL and support_is_mature and not falling_filters.has(below)
		var was_falling: bool = falling_filter_states[filter_index]
		falling_filter_states[filter_index] = can_fall
		if not can_fall:
			if was_falling:
				event_emitted.emit(&"filter_landed", falling_filters[filter_index])
			filter_kill_streak[filter_index] = 0
			continue
		falling_filters[filter_index] = below
		moved = true
		var enemy_index := enemies.find(below)
		if enemy_index >= 0 and is_enemy_active(enemy_index):
			enemy_alive[enemy_index] = false
			enemy_respawn_at[enemy_index] = world_time + ENEMY_RESPAWN_DELAY
			last_squash_score = ENEMY_SQUASH_SCORE * int(pow(MULTI_SQUASH_MULTIPLIER, filter_kill_streak[filter_index]))
			filter_kill_streak[filter_index] += 1
			_add_score(last_squash_score)
			event_emitted.emit(&"enemy_squashed", below)
	return moved


func _advance_enemy(kind: StringName = &"all") -> bool:
	if phase != Phase.PLAYING:
		return false
	var moved := false
	if kind == &"all" or kind == &"teapod":
		enemy_tick += 1
	for enemy_index in range(enemies.size()):
		if kind != &"all" and enemy_kind(enemy_index) != kind:
			continue
		enemy_prev[enemy_index] = enemies[enemy_index]
		if not is_enemy_active(enemy_index):
			continue
		var should_chase := is_ultra(enemy_index) or enemy_random.randi_range(0, 12) == 1
		var direction := _choose_enemy_direction(enemy_index, should_chase)
		if direction == Vector2i.ZERO:
			continue
		enemy_directions[enemy_index] = direction
		enemies[enemy_index] += direction
		enemy_arrives_at[enemy_index] = world_time + enemy_touch_delay(enemy_index)
		moved = true
	return moved


func is_enemy_active(enemy_index: int) -> bool:
	return enemy_alive[enemy_index] and enemy_tick >= enemy_spawn_ticks[enemy_index]


func _choose_enemy_direction(enemy_index: int, should_chase: bool) -> Vector2i:
	var forward := enemy_directions[enemy_index]
	if should_chase:
		var delta := player - enemies[enemy_index]
		var chase_direction := Vector2i(signi(delta.x), 0) if absi(delta.x) > absi(delta.y) else Vector2i(0, signi(delta.y))
		if _enemy_can_move(enemy_index, chase_direction):
			return chase_direction
	if _enemy_can_move(enemy_index, forward):
		return forward
	var left := Vector2i(forward.y, -forward.x)
	var right := Vector2i(-forward.y, forward.x)
	if enemy_random.randi_range(0, 1) == 1:
		var swap := left
		left = right
		right = swap
	for direction in [left, right, -forward]:
		if _enemy_can_move(enemy_index, direction):
			return direction
	return Vector2i.ZERO


func _enemy_can_move(enemy_index: int, direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO:
		return false
	var candidate := enemies[enemy_index] + direction
	if not is_inside(candidate) or get_cell(candidate) != Cell.TUNNEL or falling_filters.has(candidate):
		return false
	for other_index in range(enemies.size()):
		if other_index != enemy_index and is_enemy_active(other_index) and enemies[other_index] == candidate:
			return false
	return true


func _active_enemy_at(cell: Vector2i) -> int:
	for enemy_index in range(enemies.size()):
		if is_enemy_active(enemy_index) and enemies[enemy_index] == cell:
			return enemy_index
	return -1


func _add_score(points: int) -> void:
	score += points
	while score >= next_extra_life_score:
		lives += 1
		next_extra_life_score *= 2
		event_emitted.emit(&"life_gained", player)


# Sharing a cell only kills once both sprites have really met there. Walking into
# a tea-pod is therefore always fatal - the player cannot leave before his own
# arrival - while a pod that steps onto him leaves a window to slip away.
func _resolve_contacts() -> void:
	if phase != Phase.PLAYING or world_time < invulnerable_until:
		return
	# A dropped filter is a telegraphed hazard and stays instantly lethal.
	if falling_filters.has(player):
		lose_life()
		return
	# Swapping cells with a tea-pod is a head-on pass-through, not a graze: the
	# two sprites cross in mid-corridor, so there is nothing left to wait for.
	if _crossing_enemy() >= 0:
		lose_life()
		return
	var enemy_index := _active_enemy_at(player)
	if enemy_index < 0:
		enemy_contact_since = -1.0
		return
	if enemy_contact_since < 0.0:
		enemy_contact_since = world_time
		event_emitted.emit(&"close_call", player)
	if world_time >= maxf(player_arrives_at, enemy_arrives_at[enemy_index]):
		lose_life()


func _crossing_enemy() -> int:
	if player_moved_at < 0.0 or world_time - player_moved_at > player_step_time():
		return -1
	for enemy_index in range(enemies.size()):
		if not is_enemy_active(enemy_index):
			continue
		if enemies[enemy_index] == player_prev and enemy_prev[enemy_index] == player:
			return enemy_index
	return -1


func _check_deadlock() -> void:
	if phase != Phase.PLAYING or beans.is_empty() or all_beans_reachable():
		deadlock_since = -1.0
		return
	if deadlock_since < 0.0:
		deadlock_since = world_time
		return
	if world_time - deadlock_since >= DEADLOCK_CONFIRM_TIME:
		event_emitted.emit(&"level_reshuffled", player)
		reshuffle_level()
		changed.emit()


# The original applet rebuilt the level from scratch on every restart. Here it is
# the rescue for beans that filters have walled in; the beans still owed are kept.
func reshuffle_level() -> void:
	var remaining_tiers: Array[int] = []
	for cell in beans:
		remaining_tiers.append(beans[cell])
	cells.fill(Cell.SOIL)
	beans.clear()
	tunnel_opened_at.clear()
	deadlock_since = -1.0
	_carve_initial_tunnels()
	_place_objects(remaining_tiers)
	_reset_actors(false)


func all_beans_reachable() -> bool:
	var reached := {player: true}
	var frontier: Array[Vector2i] = [player]
	var found := 0
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		if beans.has(cell):
			found += 1
			if found == beans.size():
				return true
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + direction
			if not is_inside(next) or reached.has(next) or not _can_step_into(next, direction):
				continue
			reached[next] = true
			frontier.append(next)
	return false


# Soil is diggable, so only filters obstruct - and only when they cannot be shoved
# aside. Live tea-pods are ignored here because they never stay put.
func _can_step_into(target: Vector2i, direction: Vector2i) -> bool:
	if not falling_filters.has(target):
		return true
	if direction.y != 0:
		return false
	var pushed_to := target + direction
	return is_inside(pushed_to) and not beans.has(pushed_to) and not falling_filters.has(pushed_to)


func lose_life() -> void:
	if phase != Phase.PLAYING:
		return
	lives -= 1
	event_emitted.emit(&"life_lost", player)
	if lives <= 0:
		phase = Phase.GAME_OVER
		event_emitted.emit(&"game_over", player)
	else:
		_reset_actors(false)
		invulnerable_until = world_time + RESPAWN_INVULNERABILITY
