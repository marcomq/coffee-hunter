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
# An enemy sharing the player's cell is only fatal if the player fails to slip
# away within this window, so a grazing pass is survivable.
const ENEMY_CONTACT_GRACE := 0.28
const RESPAWN_INVULNERABILITY := 3.0
const ENEMY_SQUASH_SCORE := 200
const EXTRA_LIFE_SCORE := 2000

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


func _init() -> void:
	new_game()


func new_game() -> void:
	level_index = 0
	score = 0
	lives = 3
	next_extra_life_score = EXTRA_LIFE_SCORE
	_load_level()


func next_level() -> bool:
	if phase != Phase.WON or level_index + 1 >= LevelDataClass.LEVEL_COUNT:
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
	tunnel_opened_at.clear()
	phase = Phase.READY
	_carve_initial_tunnels()
	_randomize_level_objects()
	_reset_actors(true)
	changed.emit()


func _carve_initial_tunnels() -> void:
	for x in range(1, WIDTH - 1):
		set_cell(Vector2i(x, 5), Cell.TUNNEL)
	for y in range(1, HEIGHT - 1):
		set_cell(Vector2i(8, y), Cell.TUNNEL)
	for y in range(2, 8):
		set_cell(Vector2i(12, y), Cell.TUNNEL)
	for x in range(8, 13):
		set_cell(Vector2i(x, 7), Cell.TUNNEL)


func _reset_actors(revive_enemies: bool) -> void:
	player = START_PLAYER
	player_facing = Vector2i.DOWN
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
	for enemy_index in range(pod_count):
		enemies.append(_enemy_start(enemy_index))
		enemy_directions.append([Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][enemy_index % 4])
		enemy_spawn_ticks.append(_enemy_spawn_tick(enemy_index))
	if not revive_enemies:
		enemy_alive.assign(survivors)
	falling_filters.assign(level_filter_starts)
	falling_filter_states.resize(level_filter_starts.size())
	falling_filter_states.fill(false)


func _enemy_spawn_tick(enemy_index: int) -> int:
	if is_ultra(enemy_index):
		return LevelDataClass.ULTRA_SPAWN_TICK
	return enemy_index * 2


func is_ultra(enemy_index: int) -> bool:
	return LevelDataClass.has_ultra(level_index) and enemy_index == LevelDataClass.tea_pod_count(level_index) - 1


func _randomize_level_objects() -> void:
	layout_random.randomize()
	var soil_cells: Array[Vector2i] = []
	for y in range(1, HEIGHT - 1):
		for x in range(1, WIDTH - 1):
			var cell := Vector2i(x, y)
			if get_cell(cell) == Cell.SOIL:
				soil_cells.append(cell)
	_shuffle_cells(soil_cells)
	for coffee_index in range(LevelDataClass.coffee_count(level_index)):
		beans[soil_cells[coffee_index]] = LevelDataClass.bean_tier(level_index, coffee_index)
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


func _enemy_start(enemy_index: int) -> Vector2i:
	var corridor := [Vector2i(8, 5), Vector2i(8, 4), Vector2i(8, 6), Vector2i(7, 5), Vector2i(9, 5), Vector2i(8, 3), Vector2i(8, 7), Vector2i(6, 5), Vector2i(10, 5), Vector2i(8, 2), Vector2i(8, 8), Vector2i(5, 5), Vector2i(11, 5), Vector2i(8, 1)]
	return corridor[enemy_index]


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
	var moved := _advance_filter()
	if moved:
		_resolve_contacts()
		changed.emit()
	return moved


# Contact grace is a real-time window, so it must be sampled every frame rather
# than only on the enemy's own tick.
func tick_contacts() -> void:
	if phase != Phase.PLAYING:
		return
	var lives_before := lives
	_resolve_contacts()
	if lives != lives_before:
		changed.emit()


func tick_enemy() -> bool:
	if phase != Phase.PLAYING:
		return false
	var moved := _advance_enemy()
	# Always resolve: a cornered player is touched by an enemy that cannot move.
	_resolve_contacts()
	if moved:
		changed.emit()
	return moved


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
			continue
		falling_filters[filter_index] = below
		moved = true
		var enemy_index := enemies.find(below)
		if enemy_index >= 0 and is_enemy_active(enemy_index):
			enemy_alive[enemy_index] = false
			_add_score(ENEMY_SQUASH_SCORE)
			event_emitted.emit(&"enemy_squashed", below)
	return moved


func _advance_enemy() -> bool:
	if phase != Phase.PLAYING:
		return false
	var moved := false
	enemy_tick += 1
	for enemy_index in range(enemies.size()):
		if not is_enemy_active(enemy_index):
			continue
		var should_chase := is_ultra(enemy_index) or enemy_random.randi_range(0, 12) == 1
		var direction := _choose_enemy_direction(enemy_index, should_chase)
		if direction == Vector2i.ZERO:
			continue
		enemy_directions[enemy_index] = direction
		enemies[enemy_index] += direction
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


func _resolve_contacts() -> void:
	if phase != Phase.PLAYING or world_time < invulnerable_until:
		return
	# A dropped filter is a telegraphed hazard and stays instantly lethal.
	if falling_filters.has(player):
		lose_life()
		return
	if _active_enemy_at(player) < 0:
		enemy_contact_since = -1.0
		return
	if enemy_contact_since < 0.0:
		enemy_contact_since = world_time
		event_emitted.emit(&"close_call", player)
		return
	if world_time - enemy_contact_since >= ENEMY_CONTACT_GRACE:
		lose_life()


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
