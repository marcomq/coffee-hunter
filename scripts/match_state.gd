class_name MatchState
extends RefCounted

# A competitive two-player match: two plantations grown from one seed, joined by
# a portal. Each `GameState` still owns its own board and guards; this layer owns
# the players, moves them between worlds, and settles the race.

const GameStateClass = preload("res://scripts/game_state.gd")
const PlayerSlotClass = preload("res://scripts/player_slot.gd")
const LevelDataClass = preload("res://scripts/level_data.gd")

signal changed
signal event_emitted(kind: StringName, cell: Vector2i, world_index: int, player_index: int)
signal finished(winner_index: int)

const PLAYER_COUNT := 2
const COFFEE_CHARGE_TIME := 3.0
# A portal hop banks two of the three seconds, so raiding arrives nearly armed.
const PORTAL_CHARGE_BONUS := 2.0
const THROW_RANGE := 2
# Half, not all: a single throw should swing a match, not decide it outright.
const THROW_STEAL_FRACTION := 0.5
# The mug flies along the thrower's facing rather than hitting anyone within
# range, which makes lining a rival up an actual skill.
const THROW_DIRECTIONAL := true

var worlds: Array[GameState] = []
var players: Array[PlayerSlot] = []
# Which board each player currently stands on; differs from the home world only
# while raiding.
var world_of_player: Array[int] = []
var match_seed := 0
var is_over := false
var winner_index := -1


func _init(seed_value := 0) -> void:
	match_seed = seed_value
	for world_index in range(PLAYER_COUNT):
		var world: GameState = GameStateClass.new(match_seed)
		worlds.append(world)
		players.append(world.players[0])
		world_of_player.append(world_index)
		world.event_emitted.connect(_on_world_event.bind(world_index))
		world.changed.connect(_on_world_changed)


func _on_world_changed() -> void:
	changed.emit()


# Worlds speak in board-local player indices; the match speaks in global ones.
func _on_world_event(kind: StringName, cell: Vector2i, local_index: int, world_index: int) -> void:
	event_emitted.emit(kind, cell, world_index, _global_index(world_index, local_index))
	if kind == &"game_over":
		_check_finished()


func _global_index(world_index: int, local_index: int) -> int:
	var world: GameState = worlds[world_index]
	if local_index < 0 or local_index >= world.players.size():
		return -1
	return players.find(world.players[local_index])


func local_index(player_index: int) -> int:
	var world: GameState = worlds[world_of_player[player_index]]
	return world.players.find(players[player_index])


func world_for(player_index: int) -> GameState:
	return worlds[world_of_player[player_index]]


func start_game() -> void:
	for world in worlds:
		world.start_game()


func advance_time(delta: float) -> void:
	for world in worlds:
		world.advance_time(delta)
	# Charging is match-level because it must keep running while the world a
	# player is standing on ticks independently of their own.
	for slot in players:
		slot.coffee_charge = minf(slot.coffee_charge + delta, COFFEE_CHARGE_TIME)


func charge_ratio(player_index: int) -> float:
	return clampf(players[player_index].coffee_charge / COFFEE_CHARGE_TIME, 0.0, 1.0)


func is_armed(player_index: int) -> bool:
	return players[player_index].coffee_charge >= COFFEE_CHARGE_TIME


func move_player(player_index: int, direction: Vector2i) -> bool:
	if is_over:
		return false
	var slot: PlayerSlot = players[player_index]
	var world := world_for(player_index)
	var local := local_index(player_index)
	if local < 0:
		return false
	if not world.move_player(direction, local):
		return false
	# Walking is what stops you brewing - but a mug that is already full stays
	# full until it is thrown, so an armed player can go hunting for a target.
	if not is_armed(player_index):
		slot.coffee_charge = 0.0
	_try_portal(player_index)
	return true


# Stepping onto the portal cell drops the player onto the twin cell of the other
# board. Both worlds share a seed, so the destination is always carved.
func _try_portal(player_index: int) -> bool:
	var slot: PlayerSlot = players[player_index]
	var from_world := world_of_player[player_index]
	if slot.cell != worlds[from_world].portal_cell():
		return false
	var to_world := 1 - from_world
	worlds[from_world].players.erase(slot)
	worlds[to_world].players.append(slot)
	world_of_player[player_index] = to_world
	slot.cell = worlds[to_world].portal_cell()
	slot.prev = slot.cell
	slot.contact_since = -1.0
	slot.moved_at = worlds[to_world].world_time
	slot.arrives_at = worlds[to_world].world_time
	slot.coffee_charge = minf(slot.coffee_charge + PORTAL_CHARGE_BONUS, COFFEE_CHARGE_TIME)
	event_emitted.emit(&"portal", slot.cell, to_world, player_index)
	changed.emit()
	return true


func throw_coffee(player_index: int) -> bool:
	if is_over or not is_armed(player_index):
		return false
	var world := world_for(player_index)
	if world.phase != GameStateClass.Phase.PLAYING:
		return false
	var slot: PlayerSlot = players[player_index]
	slot.coffee_charge = 0.0
	event_emitted.emit(&"coffee_thrown", slot.cell, world_of_player[player_index], player_index)
	var victim := _throw_target(player_index)
	if victim >= 0:
		_land_throw(player_index, victim)
	changed.emit()
	return true


# The mug travels the thrower's facing and stops at undug soil, so a rival behind
# a wall is safe.
func _throw_target(player_index: int) -> int:
	var slot: PlayerSlot = players[player_index]
	var world := world_for(player_index)
	var cell := slot.cell
	for step in range(THROW_RANGE):
		cell += slot.facing
		if not world.is_inside(cell) or world.get_cell(cell) == GameStateClass.Cell.SOIL:
			return -1
		var hit := world.player_at(cell)
		if hit >= 0:
			var global_hit := _global_index(world_of_player[player_index], hit)
			if global_hit != player_index:
				return global_hit
	return -1


# Stolen points move between match standings only. `earned_score` is untouched on
# both sides, so the theft buys the thief no extra lives and costs the victim no
# progress toward their own.
func _land_throw(thief_index: int, victim_index: int) -> void:
	var victim_world := world_for(victim_index)
	var victim_local := local_index(victim_index)
	if victim_local < 0 or victim_world.is_invulnerable(victim_local):
		return
	var thief: PlayerSlot = players[thief_index]
	var victim: PlayerSlot = players[victim_index]
	var stolen := int(victim.score * THROW_STEAL_FRACTION)
	victim.score -= stolen
	thief.score += stolen
	event_emitted.emit(&"coffee_hit", victim.cell, world_of_player[victim_index], victim_index)
	victim_world.lose_life(victim_local)
	_check_finished()


# A cleared board sends its own resident on to the next level; a raider who
# stripped it gets the points but not the progress.
func next_level(player_index: int) -> bool:
	var world: GameState = worlds[player_index]
	if world.phase != GameStateClass.Phase.WON:
		return false
	if world.level_index + 1 >= LevelDataClass.MATCH_LEVELS:
		_check_finished()
		return false
	if not world.next_level():
		return false
	changed.emit()
	return true


func _check_finished() -> void:
	if is_over:
		return
	for player_index in range(PLAYER_COUNT):
		if players[player_index].lives <= 0:
			_finish(1 - player_index)
			return
	for world in worlds:
		var cleared: bool = world.level_index + 1 >= LevelDataClass.MATCH_LEVELS and world.phase == GameStateClass.Phase.WON
		if not cleared:
			return
	_finish(leader())


# -1 on a draw.
func leader() -> int:
	if players[0].score == players[1].score:
		return -1
	return 0 if players[0].score > players[1].score else 1


func _finish(winner: int) -> void:
	is_over = true
	winner_index = winner
	finished.emit(winner)


# --- network snapshots -------------------------------------------------------
# Players are serialised here rather than per world, because a slot belongs to
# the match and merely stands on a board. Only what a client has to DRAW travels.


func to_bytes() -> PackedByteArray:
	var payload: Array = []
	for world in worlds:
		payload.append(world.to_snapshot())
	var packed_players: Array = []
	for slot in players:
		packed_players.append([
			slot.cell.x, slot.cell.y, slot.facing.x, slot.facing.y,
			slot.score, slot.lives, slot.coffee_charge, slot.invulnerable_until,
		])
	payload.append(packed_players)
	payload.append(world_of_player.duplicate())
	payload.append(match_seed)
	payload.append(is_over)
	payload.append(winner_index)
	return var_to_bytes(payload)


func apply_bytes(payload: PackedByteArray) -> void:
	var snapshot: Variant = bytes_to_var(payload)
	if not (snapshot is Array) or (snapshot as Array).size() < PLAYER_COUNT + 5:
		return
	var parts: Array = snapshot
	var was_over := is_over
	for world_index in range(PLAYER_COUNT):
		worlds[world_index].apply_snapshot(parts[world_index])
	var packed_players: Array = parts[PLAYER_COUNT]
	world_of_player.assign(parts[PLAYER_COUNT + 1])
	match_seed = parts[PLAYER_COUNT + 2]
	is_over = parts[PLAYER_COUNT + 3]
	winner_index = parts[PLAYER_COUNT + 4]
	# Slots are rebuilt in place so the render layer keeps its references, then
	# re-seated on the boards the host says they are standing on.
	for world in worlds:
		world.players.clear()
	for player_index in range(mini(players.size(), packed_players.size())):
		var values: Array = packed_players[player_index]
		var slot: PlayerSlot = players[player_index]
		slot.cell = Vector2i(values[0], values[1])
		slot.facing = Vector2i(values[2], values[3])
		slot.score = values[4]
		slot.lives = values[5]
		slot.coffee_charge = values[6]
		slot.invulnerable_until = values[7]
		worlds[world_of_player[player_index]].players.append(slot)
	changed.emit()
	# A client never runs `_check_finished`, so the end of the match reaches it
	# only here - as the moment the host's snapshot first says it is over.
	if is_over and not was_over:
		finished.emit(winner_index)
