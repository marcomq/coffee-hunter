class_name GameState
extends RefCounted

signal changed
signal event_emitted(kind: StringName, cell: Vector2i)

enum Cell { SOIL, TUNNEL }
enum Phase { READY, PLAYING, WON, GAME_OVER }

const WIDTH := 17
const HEIGHT := 11
const START_PLAYER := Vector2i(2, 5)
const START_ENEMY := Vector2i(8, 5)
const START_FILTERS: Array[Vector2i] = [Vector2i(3, 4), Vector2i(12, 2), Vector2i(13, 4)]
const BEAN_SCORE := 40

var cells: Array[int] = []
var beans: Dictionary = {}
var player := START_PLAYER
var player_facing := Vector2i.DOWN
var enemy := START_ENEMY
var falling_filters: Array[Vector2i] = []
var falling_filter_states: Array[bool] = []
var enemy_alive := true
var score := 0
var lives := 3
var phase := Phase.READY


func _init() -> void:
	new_game()


func new_game() -> void:
	cells.resize(WIDTH * HEIGHT)
	cells.fill(Cell.SOIL)
	beans = {
		Vector2i(4, 5): true,
		Vector2i(6, 5): true,
		Vector2i(8, 2): true,
		Vector2i(10, 7): true,
		Vector2i(14, 5): true,
	}
	score = 0
	lives = 3
	phase = Phase.READY
	_carve_initial_tunnels()
	_reset_actors()
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


func _reset_actors() -> void:
	player = START_PLAYER
	player_facing = Vector2i.DOWN
	enemy = START_ENEMY
	falling_filters.assign(START_FILTERS)
	falling_filter_states.resize(START_FILTERS.size())
	falling_filter_states.fill(false)
	enemy_alive = true


func start_game() -> void:
	if phase == Phase.READY:
		phase = Phase.PLAYING
		changed.emit()


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
		var pushed_to := target + direction
		if not is_inside(pushed_to) or pushed_to == enemy or beans.has(pushed_to) or falling_filters.has(pushed_to):
			return false
		falling_filters[filter_index] = pushed_to

	player = target
	player_facing = direction
	if get_cell(player) == Cell.SOIL:
		set_cell(player, Cell.TUNNEL)
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


func tick_enemy() -> bool:
	if phase != Phase.PLAYING:
		return false
	var moved := _advance_enemy()
	if moved:
		_resolve_contacts()
		changed.emit()
	return moved


func _collect_at_player() -> void:
	if not beans.has(player):
		return
	beans.erase(player)
	score += BEAN_SCORE
	event_emitted.emit(&"coffee", player)
	if beans.is_empty():
		phase = Phase.WON
		event_emitted.emit(&"won", player)


func _advance_filter() -> bool:
	var moved := false
	for filter_index in range(falling_filters.size()):
		var below := falling_filters[filter_index] + Vector2i.DOWN
		var can_fall := is_inside(below) and get_cell(below) == Cell.TUNNEL and not falling_filters.has(below)
		falling_filter_states[filter_index] = can_fall
		if not can_fall:
			continue
		falling_filters[filter_index] = below
		moved = true
		if enemy_alive and below == enemy:
			enemy_alive = false
			score += 200
			event_emitted.emit(&"enemy_squashed", enemy)
	return moved


func _advance_enemy() -> bool:
	if not enemy_alive or phase != Phase.PLAYING:
		return false
	var candidates: Array[Vector2i] = []
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate: Vector2i = enemy + direction
		if is_inside(candidate) and get_cell(candidate) == Cell.TUNNEL and not falling_filters.has(candidate):
			candidates.append(candidate)
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(player) < b.distance_squared_to(player)
	)
	enemy = candidates[0]
	return true


func _resolve_contacts() -> void:
	if falling_filters.has(player) or (enemy_alive and enemy == player):
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
		_reset_actors()
