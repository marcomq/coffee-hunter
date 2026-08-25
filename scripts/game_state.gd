class_name GameState
extends RefCounted

const LevelDataClass = preload("res://scripts/level_data.gd")
const PlayerSlotClass = preload("res://scripts/player_slot.gd")

signal changed
signal event_emitted(kind: StringName, cell: Vector2i, player_index: int)

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
# Contact begins before the full visual step has completed, so grazing a pod
# remains escapable even though its sprite now moves continuously between ticks.
const ENEMY_CONTACT_MOVE_FRACTION := 0.82
const RESPAWN_INVULNERABILITY := 3.0
const START_LIVES := 3
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
const ENEMY_DIG_INTERVAL := 20
# Seconds of standing still that brew one throw. The match layer scales its own
# clocks off these, so single player and a match arm a mug at the same pace.
const COFFEE_CHARGE_TIME := 5.0
# The opening seconds of a brew are just standing there. Pouring only starts once
# they are up, so a short pause never costs the hero his idle and walk animation.
const COFFEE_POUR_DELAY := 1.6
const THROW_RANGE := 2
# Where pods queue up around the nest. Offsets, because the cross moves per level.
const ENEMY_START_OFFSETS := [
	Vector2i(0, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0),
	Vector2i(0, -3), Vector2i(0, 3), Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -4),
]

var cells: Array[int] = []
var beans: Dictionary = {}
# Everyone standing on this board. Usually the world's own player; two while a
# rival is visiting through the portal.
var players: Array[PlayerSlot] = []
var enemies: Array[Vector2i] = []
var enemy_alive: Array[bool] = []
var enemy_directions: Array[Vector2i] = []
var enemy_spawn_ticks: Array[int] = []
var enemy_turns_since_dig: Array[int] = []
var enemy_tick := 0
var falling_filters: Array[Vector2i] = []
var falling_filter_states: Array[bool] = []
var filter_pushed_at: Array[float] = []
# Who last shoved each filter, so a squash pays the player who set it up rather
# than always the world's own resident.
var filter_pushed_by: Array[int] = []
var level_filter_starts: Array[Vector2i] = []
var phase := Phase.READY
var level_index := 0
var enemy_random := RandomNumberGenerator.new()
var layout_random := RandomNumberGenerator.new()
var world_time := 0.0
var tunnel_opened_at: Dictionary = {}
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
# Below zero keeps the historical behaviour: every world rolls its own layout.
# A match hands both boards the same seed so the race is run on equal ground.
var match_seed := -1

# Single-player views of the first slot. The whole game was written around one
# player, so these keep every existing call site and test working unchanged
# while the rules underneath moved to `players`.
var player: Vector2i:
	get: return players[0].cell
	set(value): players[0].cell = value
var player_facing: Vector2i:
	get: return players[0].facing
	set(value): players[0].facing = value
var player_prev: Vector2i:
	get: return players[0].prev
	set(value): players[0].prev = value
var player_moved_at: float:
	get: return players[0].moved_at
	set(value): players[0].moved_at = value
var player_arrives_at: float:
	get: return players[0].arrives_at
	set(value): players[0].arrives_at = value
var invulnerable_until: float:
	get: return players[0].invulnerable_until
	set(value): players[0].invulnerable_until = value
var enemy_contact_since: float:
	get: return players[0].contact_since
	set(value): players[0].contact_since = value
var lives: int:
	get: return players[0].lives
	set(value): players[0].lives = value
var next_extra_life_score: int:
	get: return players[0].next_extra_life_score
	set(value): players[0].next_extra_life_score = value
# Assigning a score outside a match is always a test or setup fixture, never a
# theft, so the earned tally follows along and the extra-life ladder stays sane.
var score: int:
	get: return players[0].score
	set(value):
		players[0].score = value
		players[0].earned_score = value


func _init(layout_seed := -1) -> void:
	match_seed = layout_seed
	players = [new_player_slot()]
	new_game()


func new_player_slot() -> PlayerSlot:
	var slot := PlayerSlotClass.new()
	slot.cell = player_start
	slot.prev = player_start
	slot.next_extra_life_score = EXTRA_LIFE_SCORE
	slot.lives = START_LIVES
	return slot


func new_game() -> void:
	level_index = 0
	for slot in players:
		slot.score = 0
		slot.earned_score = 0
		slot.lives = START_LIVES
		slot.next_extra_life_score = EXTRA_LIFE_SCORE
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
	for slot in players:
		slot.invulnerable_until = 0.0
	deadlock_since = -1.0
	tunnel_opened_at.clear()
	phase = Phase.READY
	_seed_layout_random()
	_carve_initial_tunnels()
	_randomize_level_objects()
	_reset_actors(true)
	changed.emit()


# Seeded only here, never inside the layout builders: reshuffle_level() rebuilds
# a board by calling them again, and reseeding there would hand back the very
# same walled-in level the rescue was trying to escape.
func _seed_layout_random() -> void:
	if match_seed < 0:
		layout_random.randomize()
	else:
		layout_random.seed = hash(Vector2i(match_seed, level_index))


# The portal sits on the branch corner: always carved, well away from both the
# player start and the nest.
func portal_cell() -> Vector2i:
	return Vector2i(branch_x, branch_y)


# The original jittered the cross per level (LevelN's middleX/middleY); a fixed
# one made every board read the same. Anything that must sit on a corridor - the
# player start, the nest - is derived from these four numbers, never hardcoded.
func _carve_initial_tunnels() -> void:
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
	for slot in players:
		_reset_player_slot(slot)
	var survivors := enemy_alive.duplicate()
	enemies.clear()
	enemy_directions.clear()
	enemy_spawn_ticks.clear()
	enemy_turns_since_dig.clear()
	enemy_tick = 0
	enemy_random.seed = 0xC0FFEE + level_index
	var pod_count := LevelDataClass.tea_pod_count(level_index)
	var enemy_count := pod_count + (1 if LevelDataClass.has_ultra(level_index) else 0)
	if revive_enemies:
		enemy_alive.clear()
		enemy_alive.resize(enemy_count)
		enemy_alive.fill(true)
		enemy_respawn_at.clear()
	for enemy_index in range(enemy_count):
		enemies.append(_enemy_start(enemy_index))
		enemy_directions.append([Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][enemy_index % 4])
		enemy_spawn_ticks.append(_enemy_spawn_tick(enemy_index))
		enemy_turns_since_dig.append(0)
	if not revive_enemies:
		enemy_alive.assign(survivors)
	enemy_prev.assign(enemies)
	enemy_arrives_at.clear()
	enemy_arrives_at.resize(enemies.size())
	enemy_arrives_at.fill(0.0)
	falling_filters.assign(level_filter_starts)
	falling_filter_states.resize(level_filter_starts.size())
	falling_filter_states.fill(false)
	filter_pushed_at.clear()
	filter_pushed_by.clear()
	_sync_parallel_arrays()


# Invulnerability is deliberately not touched here: `lose_life` grants it right
# after calling this, and a level load clears it separately.
func _reset_player_slot(slot: PlayerSlot) -> void:
	slot.cell = player_start
	slot.facing = Vector2i.DOWN
	slot.prev = player_start
	slot.moved_at = -1.0
	slot.arrives_at = 0.0
	slot.contact_since = -1.0


func _enemy_spawn_tick(enemy_index: int) -> int:
	if is_ultra(enemy_index):
		return LevelDataClass.ULTRA_SPAWN_TICK
	return enemy_index * 2


func is_ultra(enemy_index: int) -> bool:
	return LevelDataClass.has_ultra(level_index) and enemy_index == LevelDataClass.tea_pod_count(level_index)


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
	if enemy_turns_since_dig.size() != enemies.size():
		enemy_turns_since_dig.resize(enemies.size())
	if filter_kill_streak.size() != falling_filters.size():
		filter_kill_streak.resize(falling_filters.size())
	while filter_pushed_at.size() < falling_filters.size():
		filter_pushed_at.append(-1.0)
	filter_pushed_at.resize(falling_filters.size())
	while filter_pushed_by.size() < falling_filters.size():
		filter_pushed_by.append(0)
	filter_pushed_by.resize(falling_filters.size())


func start_game() -> void:
	if phase == Phase.READY:
		phase = Phase.PLAYING
		changed.emit()


func is_invulnerable(player_index := 0) -> bool:
	return phase == Phase.PLAYING and world_time < players[player_index].invulnerable_until


func invulnerability_left(player_index := 0) -> float:
	return maxf(players[player_index].invulnerable_until - world_time, 0.0)


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


# How close a filter is to dropping: 0 while it still rests on solid ground,
# 1 once the drop is committed. The view turns this into a warning wobble.
func filter_fall_pressure(filter_index: int) -> float:
	if filter_index < 0 or filter_index >= falling_filters.size() or filter_index >= falling_filter_states.size():
		return 0.0
	if falling_filter_states[filter_index]:
		return 1.0
	var cell: Vector2i = falling_filters[filter_index]
	var below := cell + Vector2i.DOWN
	if not is_inside(cell) or not is_inside(below):
		return 0.0
	if get_cell(below) != Cell.TUNNEL or falling_filters.has(below):
		return 0.0
	if not tunnel_opened_at.has(below):
		return 1.0
	return clampf((world_time - float(tunnel_opened_at[below])) / FRESH_TUNNEL_FALL_DELAY, 0.0, 1.0)


# Standing still brews the mug. A match brews at its own level instead, because a
# raider keeps charging on a board that ticks independently of their own.
func tick_charge(delta: float) -> void:
	if phase != Phase.PLAYING:
		return
	for slot in players:
		slot.coffee_charge = minf(slot.coffee_charge + delta, COFFEE_CHARGE_TIME)


func charge_ratio(player_index := 0) -> float:
	if player_index < 0 or player_index >= players.size():
		return 0.0
	return clampf(players[player_index].coffee_charge / COFFEE_CHARGE_TIME, 0.0, 1.0)


# How far along the visible pour is, which starts later than the charge itself.
# Static because the match layer owns its own charge but shows the same mug.
static func pour_progress(charge_value: float) -> float:
	var delay := COFFEE_POUR_DELAY / COFFEE_CHARGE_TIME
	return clampf((charge_value - delay) / maxf(1.0 - delay, 0.001), 0.0, 1.0)


func is_armed(player_index := 0) -> bool:
	return player_index >= 0 and player_index < players.size() and players[player_index].coffee_charge >= COFFEE_CHARGE_TIME


func throw_coffee(player_index := 0) -> bool:
	if phase != Phase.PLAYING or not is_armed(player_index):
		return false
	_sync_parallel_arrays()
	var slot := players[player_index]
	slot.coffee_charge = 0.0
	event_emitted.emit(&"coffee_thrown", slot.cell, player_index)
	var enemy_index := _throw_target(player_index)
	if enemy_index >= 0:
		_scald_enemy(enemy_index, player_index)
	changed.emit()
	return true


# The mug travels the thrower's facing and stops at undug soil, so a pod behind a
# wall is safe. Lining one up is the whole skill.
func _throw_target(player_index: int) -> int:
	var slot := players[player_index]
	var cell := slot.cell
	for step in range(THROW_RANGE):
		cell += slot.facing
		if not is_inside(cell) or get_cell(cell) == Cell.SOIL:
			return -1
		var enemy_index := _active_enemy_at(cell)
		if enemy_index >= 0:
			return enemy_index
	return -1


# A scalded pod leaves the board exactly as a filtered one does: same payout, same
# long crawl back out of the nest. No chain bonus - one mug catches one pod.
func _scald_enemy(enemy_index: int, player_index: int) -> void:
	var cell: Vector2i = enemies[enemy_index]
	enemy_alive[enemy_index] = false
	enemy_respawn_at[enemy_index] = world_time + ENEMY_RESPAWN_DELAY
	last_squash_score = ENEMY_SQUASH_SCORE
	_add_score(player_index, last_squash_score)
	event_emitted.emit(&"enemy_squashed", cell, player_index)


func player_touch_delay() -> float:
	return player_step_time() * CONTACT_TOUCH_FRACTION


func enemy_touch_delay(enemy_index: int = -1) -> float:
	var step_time := enemy_step_time()
	if enemy_index >= 0:
		step_time = enemy_step_time_for_kind(enemy_kind(enemy_index))
	return step_time * ENEMY_CONTACT_MOVE_FRACTION * CONTACT_TOUCH_FRACTION


func index(cell: Vector2i) -> int:
	return cell.y * WIDTH + cell.x


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < WIDTH and cell.y >= 0 and cell.y < HEIGHT


func get_cell(cell: Vector2i) -> int:
	return cells[index(cell)] if is_inside(cell) else Cell.SOIL


func set_cell(cell: Vector2i, value: int) -> void:
	if is_inside(cell):
		cells[index(cell)] = value


func move_player(direction: Vector2i, player_index := 0) -> bool:
	if phase != Phase.PLAYING or direction == Vector2i.ZERO:
		return false
	_sync_parallel_arrays()
	var slot := players[player_index]
	var target := slot.cell + direction
	if not is_inside(target):
		return false

	var filter_index := falling_filters.find(target)
	if filter_index >= 0:
		if direction.y != 0:
			return false
		if falling_filter_states[filter_index]:
			return false
		# A filter ploughs sideways through undug soil; only beans, other
		# filters, live tea-pods and the map edge stop it.
		var pushed_to := target + direction
		if not is_inside(pushed_to):
			return false
		if _active_enemy_at(pushed_to) >= 0 or beans.has(pushed_to) or falling_filters.has(pushed_to):
			return false
		falling_filters[filter_index] = pushed_to
		var below_pushed_filter := pushed_to + Vector2i.DOWN
		falling_filter_states[filter_index] = is_inside(below_pushed_filter) and get_cell(below_pushed_filter) == Cell.TUNNEL
		filter_pushed_at[filter_index] = world_time
		filter_pushed_by[filter_index] = player_index

	slot.prev = slot.cell
	slot.moved_at = world_time
	slot.arrives_at = world_time + player_touch_delay()
	slot.cell = target
	slot.facing = direction
	# Walking is what stops you brewing - but a mug that is already full stays full
	# until it is thrown, so an armed player can go hunting for a target.
	if not is_armed(player_index):
		slot.coffee_charge = 0.0
	if get_cell(slot.cell) == Cell.SOIL:
		set_cell(slot.cell, Cell.TUNNEL)
		tunnel_opened_at[slot.cell] = world_time
		event_emitted.emit(&"dug", slot.cell, player_index)
	_collect_at_player(player_index)
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
	var lives_before := _total_lives()
	_resolve_contacts()
	if _total_lives() != lives_before:
		changed.emit()


func _total_lives() -> int:
	var total := 0
	for slot in players:
		total += slot.lives
	return total


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
		if player_at(nest) >= 0 or falling_filters.has(nest) or _active_enemy_at(nest) >= 0:
			continue
		enemy_alive[enemy_index] = true
		enemy_respawn_at[enemy_index] = -1.0
		enemies[enemy_index] = nest
		enemy_prev[enemy_index] = nest
		enemy_arrives_at[enemy_index] = world_time
		enemy_directions[enemy_index] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN][enemy_index % 4]
		enemy_turns_since_dig[enemy_index] = 0
		event_emitted.emit(&"enemy_respawned", nest, -1)
		revived = true
	return revived


# -1 when nobody stands there. Board-wide events carry -1 as their player index.
func player_at(cell: Vector2i) -> int:
	for player_index in range(players.size()):
		if players[player_index].cell == cell:
			return player_index
	return -1


# Enemies hunt whoever is closest, so a raider walking into the neighbouring
# plantation draws its guards away from the player who lives there.
func _nearest_player(from: Vector2i) -> int:
	var best := -1
	var best_distance := 1 << 30
	for player_index in range(players.size()):
		var delta: Vector2i = players[player_index].cell - from
		var distance := absi(delta.x) + absi(delta.y)
		if distance < best_distance:
			best_distance = distance
			best = player_index
	return best


func _collect_at_player(player_index: int) -> void:
	var cell := players[player_index].cell
	if not beans.has(cell):
		return
	var tier: int = beans[cell]
	beans.erase(cell)
	_add_score(player_index, LevelDataClass.bean_value(tier))
	event_emitted.emit(&"coffee", cell, player_index)
	if beans.is_empty():
		phase = Phase.WON
		event_emitted.emit(&"won", cell, player_index)


func _advance_filter() -> bool:
	var moved := false
	for filter_index in range(falling_filters.size()):
		if not is_inside(falling_filters[filter_index]):
			continue
		if filter_pushed_at[filter_index] >= 0.0:
			if world_time - filter_pushed_at[filter_index] < player_step_time():
				continue
			var pushed_below := falling_filters[filter_index] + Vector2i.DOWN
			var pushed_tunnel_is_fresh := is_inside(pushed_below) and get_cell(pushed_below) == Cell.TUNNEL and tunnel_opened_at.has(pushed_below) and world_time - float(tunnel_opened_at[pushed_below]) < FRESH_TUNNEL_FALL_DELAY
			if pushed_tunnel_is_fresh:
				continue
			filter_pushed_at[filter_index] = -1.0
		var below := falling_filters[filter_index] + Vector2i.DOWN
		var support_is_mature := not tunnel_opened_at.has(below) or world_time - float(tunnel_opened_at[below]) >= FRESH_TUNNEL_FALL_DELAY
		var can_fall := is_inside(below) and get_cell(below) == Cell.TUNNEL and support_is_mature and not falling_filters.has(below)
		var was_falling: bool = falling_filter_states[filter_index]
		falling_filter_states[filter_index] = can_fall
		if not can_fall:
			if was_falling:
				event_emitted.emit(&"filter_landed", falling_filters[filter_index], -1)
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
			_add_score(filter_pushed_by[filter_index], last_squash_score)
			event_emitted.emit(&"enemy_squashed", below, filter_pushed_by[filter_index])
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
		enemy_turns_since_dig[enemy_index] += 1
		var should_chase := is_ultra(enemy_index) or enemy_random.randi_range(0, 12) == 1
		var direction := _choose_enemy_direction(enemy_index, should_chase)
		if direction == Vector2i.ZERO:
			continue
		enemy_directions[enemy_index] = direction
		var destination := enemies[enemy_index] + direction
		if get_cell(destination) == Cell.SOIL:
			set_cell(destination, Cell.TUNNEL)
			tunnel_opened_at[destination] = world_time
			enemy_turns_since_dig[enemy_index] = 0
			event_emitted.emit(&"dug", destination, -1)
		enemies[enemy_index] = destination
		enemy_arrives_at[enemy_index] = world_time + enemy_touch_delay(enemy_index)
		moved = true
	return moved


func is_enemy_active(enemy_index: int) -> bool:
	return enemy_alive[enemy_index] and enemy_tick >= enemy_spawn_ticks[enemy_index]


func _choose_enemy_direction(enemy_index: int, should_chase: bool) -> Vector2i:
	var forward := enemy_directions[enemy_index]
	# An empty board (its resident is away raiding) leaves nothing to hunt, so the
	# guards fall through to their patrol.
	var target_index := _nearest_player(enemies[enemy_index])
	if target_index >= 0:
		var target_cell: Vector2i = players[target_index].cell
		if is_ultra(enemy_index):
			var delta := target_cell - enemies[enemy_index]
			var direct_directions := _directions_toward(delta)
			for direction in direct_directions:
				if _enemy_can_dig(enemy_index, direction):
					return direction
			var path_direction := _shortest_tunnel_direction(enemy_index, target_cell)
			if path_direction != Vector2i.ZERO:
				return path_direction
		if should_chase:
			var delta := target_cell - enemies[enemy_index]
			var chase_direction := Vector2i(signi(delta.x), 0) if absi(delta.x) > absi(delta.y) else Vector2i(0, signi(delta.y))
			if _enemy_can_move(enemy_index, chase_direction):
				return chase_direction
	if _enemy_can_move(enemy_index, forward):
		return forward
	if enemy_kind(enemy_index) == &"teapot" and _enemy_can_dig(enemy_index, forward):
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


func _enemy_can_dig(enemy_index: int, direction: Vector2i) -> bool:
	if direction == Vector2i.ZERO or enemy_kind(enemy_index) not in [&"teapot", &"ultra"]:
		return false
	if enemy_turns_since_dig[enemy_index] < ENEMY_DIG_INTERVAL:
		return false
	var candidate := enemies[enemy_index] + direction
	if not is_inside(candidate) or get_cell(candidate) != Cell.SOIL:
		return false
	if beans.has(candidate) or falling_filters.has(candidate):
		return false
	return _active_enemy_at(candidate) < 0


func _directions_toward(delta: Vector2i) -> Array[Vector2i]:
	var directions: Array[Vector2i] = []
	if delta.x != 0:
		directions.append(Vector2i(signi(delta.x), 0))
	if delta.y != 0:
		directions.append(Vector2i(0, signi(delta.y)))
	return directions


func _shortest_tunnel_direction(enemy_index: int, target_cell: Vector2i) -> Vector2i:
	var start := enemies[enemy_index]
	var queue: Array[Vector2i] = [start]
	var first_step := {start: Vector2i.ZERO}
	var queue_index := 0
	while queue_index < queue.size():
		var current := queue[queue_index]
		queue_index += 1
		var directions := _directions_toward(target_cell - current)
		for cardinal in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not directions.has(cardinal):
				directions.append(cardinal)
		for direction: Vector2i in directions:
			var candidate: Vector2i = current + direction
			if first_step.has(candidate) or not is_inside(candidate) or get_cell(candidate) != Cell.TUNNEL or falling_filters.has(candidate):
				continue
			if candidate != target_cell and _active_enemy_at(candidate) >= 0:
				continue
			var initial_direction: Vector2i = direction if current == start else first_step[current]
			if candidate == target_cell:
				return initial_direction
			first_step[candidate] = initial_direction
			queue.append(candidate)
	return Vector2i.ZERO


func _active_enemy_at(cell: Vector2i) -> int:
	for enemy_index in range(enemies.size()):
		if is_enemy_active(enemy_index) and enemies[enemy_index] == cell:
			return enemy_index
	return -1


# The ladder reads `earned_score`, never `score`, so points taken off a rival
# raise the match standing without also handing out lives.
func _add_score(player_index: int, points: int) -> void:
	var slot := players[player_index]
	slot.score += points
	slot.earned_score += points
	while slot.earned_score >= slot.next_extra_life_score:
		slot.lives += 1
		slot.next_extra_life_score *= 2
		event_emitted.emit(&"life_gained", slot.cell, player_index)


# Sharing a cell only kills once both sprites have really met there. Walking into
# a tea-pod is therefore always fatal - the player cannot leave before his own
# arrival - while a pod that steps onto him leaves a window to slip away.
func _resolve_contacts() -> void:
	if phase != Phase.PLAYING:
		return
	# A fatal contact can take its slot off the board, so walk a copy and look the
	# index up again: the live list shrinks underneath this loop.
	for slot in players.duplicate():
		var player_index := players.find(slot)
		if player_index >= 0:
			_resolve_contacts_for(player_index)


func _resolve_contacts_for(player_index: int) -> void:
	var slot := players[player_index]
	if world_time < slot.invulnerable_until:
		return
	# A dropped filter is a telegraphed hazard and stays instantly lethal.
	if falling_filters.has(slot.cell):
		lose_life(player_index)
		return
	# Swapping cells with a tea-pod is a head-on pass-through, not a graze: the
	# two sprites cross in mid-corridor, so there is nothing left to wait for.
	if _crossing_enemy(player_index) >= 0:
		lose_life(player_index)
		return
	var enemy_index := _active_enemy_at(slot.cell)
	if enemy_index < 0:
		slot.contact_since = -1.0
		return
	if slot.contact_since < 0.0:
		slot.contact_since = world_time
		event_emitted.emit(&"close_call", slot.cell, player_index)
	if world_time >= maxf(slot.arrives_at, enemy_arrives_at[enemy_index]):
		lose_life(player_index)


func _crossing_enemy(player_index := 0) -> int:
	var slot := players[player_index]
	if slot.moved_at < 0.0 or world_time - slot.moved_at > player_step_time():
		return -1
	for enemy_index in range(enemies.size()):
		if not is_enemy_active(enemy_index):
			continue
		if enemies[enemy_index] == slot.prev and enemy_prev[enemy_index] == slot.cell:
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
		event_emitted.emit(&"level_reshuffled", players[0].cell if not players.is_empty() else nest_cell(), -1)
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


# Reachability is judged from whoever actually stands on this board; with the
# owner away through the portal there is no vantage point and nothing to rescue.
func all_beans_reachable() -> bool:
	if players.is_empty():
		return true
	var reached := {}
	var frontier: Array[Vector2i] = []
	for slot in players:
		reached[slot.cell] = true
		frontier.append(slot.cell)
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


func lose_life(player_index := 0) -> void:
	if phase != Phase.PLAYING:
		return
	var slot := players[player_index]
	slot.lives -= 1
	event_emitted.emit(&"life_lost", slot.cell, player_index)
	if slot.lives <= 0:
		# A board with company keeps running: the match layer takes the dead slot
		# off it and the others race on. Alone - every single-player run - the
		# board itself is over, exactly as before.
		if players.size() <= 1:
			phase = Phase.GAME_OVER
		event_emitted.emit(&"game_over", slot.cell, player_index)
	else:
		# The full reset also drags every other slot back to the start cell, which
		# would punish a raider for a death that was not theirs.
		if players.size() <= 1:
			_reset_actors(false)
		else:
			_reset_player_slot(slot)
		slot.invulnerable_until = world_time + RESPAWN_INVULNERABILITY


# --- network snapshots -------------------------------------------------------
# The host owns the simulation; a client never simulates, it only draws. So this
# carries a RENDER model, not a full copy of the state: arrival times, contact
# timers and the extra-life ladder stay host-side.
#
# Everything is positional and bit-packed to keep a whole match inside ENet's
# 1392-byte MTU. Crossing it would fragment the unreliable snapshot stream and
# cost far more in dropped packets than the packing saves in effort.


func to_snapshot() -> Array:
	var packed_cells := PackedByteArray()
	packed_cells.resize((cells.size() + 7) / 8)
	for index in range(cells.size()):
		if cells[index] == Cell.TUNNEL:
			packed_cells[index / 8] |= 1 << (index % 8)
	var packed_beans := PackedInt32Array()
	for cell: Vector2i in beans:
		packed_beans.append(index(cell))
		packed_beans.append(beans[cell])
	var packed_enemies := PackedInt32Array()
	var packed_alive := PackedByteArray()
	for enemy_index in range(enemies.size()):
		packed_enemies.append(index(enemies[enemy_index]))
		packed_alive.append(1 if is_enemy_active(enemy_index) else 0)
	var packed_filters := PackedInt32Array()
	var packed_filter_states := PackedByteArray()
	for filter_index in range(falling_filters.size()):
		packed_filters.append(index(falling_filters[filter_index]))
		packed_filter_states.append(1 if falling_filter_states[filter_index] else 0)
	return [
		packed_cells, packed_beans, packed_enemies, packed_alive,
		packed_filters, packed_filter_states,
		phase, level_index, world_time,
		corridor_y, shaft_x, branch_x, branch_y, index(player_start),
	]


func apply_snapshot(snapshot: Array) -> void:
	var packed_cells: PackedByteArray = snapshot[0]
	cells.resize(WIDTH * HEIGHT)
	for cell_index in range(cells.size()):
		var bit: int = packed_cells[cell_index / 8] & (1 << (cell_index % 8))
		cells[cell_index] = Cell.TUNNEL if bit != 0 else Cell.SOIL
	beans.clear()
	var packed_beans: PackedInt32Array = snapshot[1]
	for pair in range(0, packed_beans.size(), 2):
		beans[cell_of(packed_beans[pair])] = packed_beans[pair + 1]
	var packed_enemies: PackedInt32Array = snapshot[2]
	var packed_alive: PackedByteArray = snapshot[3]
	enemies.clear()
	enemy_alive.clear()
	for enemy_index in range(packed_enemies.size()):
		enemies.append(cell_of(packed_enemies[enemy_index]))
		enemy_alive.append(packed_alive[enemy_index] != 0)
	# A client draws whoever the host says is on the board, so every listed pod is
	# already past its spawn tick.
	enemy_spawn_ticks.clear()
	enemy_spawn_ticks.resize(enemies.size())
	enemy_spawn_ticks.fill(0)
	enemy_tick = 1
	var packed_filters: PackedInt32Array = snapshot[4]
	var packed_filter_states: PackedByteArray = snapshot[5]
	falling_filters.clear()
	falling_filter_states.clear()
	for filter_index in range(packed_filters.size()):
		falling_filters.append(cell_of(packed_filters[filter_index]))
		falling_filter_states.append(packed_filter_states[filter_index] != 0)
	phase = snapshot[6]
	level_index = snapshot[7]
	world_time = snapshot[8]
	corridor_y = snapshot[9]
	shaft_x = snapshot[10]
	branch_x = snapshot[11]
	branch_y = snapshot[12]
	player_start = cell_of(snapshot[13])
	_sync_parallel_arrays()


func cell_of(cell_index: int) -> Vector2i:
	return Vector2i(cell_index % WIDTH, cell_index / WIDTH)
