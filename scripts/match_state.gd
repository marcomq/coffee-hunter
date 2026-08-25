class_name MatchState
extends RefCounted

# A competitive match: one plantation per player, all grown from the same seed and
# joined by portals into a ring. Each `GameState` still owns its own board and
# guards; this layer owns the players, moves them between worlds, and settles the
# race.

const GameStateClass = preload("res://scripts/game_state.gd")
const PlayerSlotClass = preload("res://scripts/player_slot.gd")
const LevelDataClass = preload("res://scripts/level_data.gd")

signal changed
signal event_emitted(kind: StringName, cell: Vector2i, world_index: int, player_index: int)
signal finished(winner_index: int)

const MAX_PLAYERS := 4
const COFFEE_CHARGE_TIME := GameStateClass.COFFEE_CHARGE_TIME
# A portal hop banks most of the brew, so raiding arrives nearly armed.
const PORTAL_CHARGE_BONUS := COFFEE_CHARGE_TIME * 2.0 / 3.0
const THROW_RANGE := GameStateClass.THROW_RANGE
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


func _init(seed_value := 0, player_count := 2) -> void:
	match_seed = seed_value
	for world_index in range(clampi(player_count, 2, MAX_PLAYERS)):
		var world: GameState = GameStateClass.new(match_seed)
		worlds.append(world)
		players.append(world.players[0])
		world_of_player.append(world_index)
		world.event_emitted.connect(_on_world_event.bind(world_index))
		world.changed.connect(_on_world_changed)


func player_count() -> int:
	return players.size()


func _on_world_changed() -> void:
	changed.emit()


# Worlds speak in board-local player indices; the match speaks in global ones.
func _on_world_event(kind: StringName, cell: Vector2i, local_index: int, world_index: int) -> void:
	var player_index := _global_index(world_index, local_index)
	event_emitted.emit(kind, cell, world_index, player_index)
	if kind == &"game_over":
		eliminate(player_index)


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


# Out of lives, or gone from the link. The slot leaves its board, so everything
# underneath - enemy targeting, throws, the deadlock rescue - stops seeing it
# without a single extra check, and the others race on.
func eliminate(player_index: int) -> void:
	if player_index < 0 or player_index >= players.size():
		return
	var slot: PlayerSlot = players[player_index]
	if slot.is_out:
		return
	slot.is_out = true
	worlds[world_of_player[player_index]].players.erase(slot)
	changed.emit()
	_check_finished()


func active_players() -> Array[int]:
	var active: Array[int] = []
	for player_index in range(players.size()):
		if not players[player_index].is_out:
			active.append(player_index)
	return active


func move_player(player_index: int, direction: Vector2i) -> bool:
	if is_over:
		return false
	var slot: PlayerSlot = players[player_index]
	var world := world_for(player_index)
	var local := local_index(player_index)
	# -1 covers an eliminated slot too: it stands on no board at all.
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


# Stepping onto the portal cell drops the player onto the twin cell of the next
# board in the ring. Every world shares a seed, so the destination is always
# carved - and a full lap brings a raider home.
func _try_portal(player_index: int) -> bool:
	var slot: PlayerSlot = players[player_index]
	var from_world := world_of_player[player_index]
	if slot.cell != worlds[from_world].portal_cell():
		return false
	var to_world := (from_world + 1) % worlds.size()
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
	if is_over or not is_armed(player_index) or players[player_index].is_out:
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


# Survival first: whoever is left when everyone else is out wins the race no
# matter what the scores say. Only a match that runs its full length is settled
# on points.
func _check_finished() -> void:
	if is_over:
		return
	var active := active_players()
	if active.size() <= 1:
		_finish(active[0] if not active.is_empty() else -1)
		return
	for player_index in active:
		var world: GameState = worlds[player_index]
		var cleared: bool = world.level_index + 1 >= LevelDataClass.MATCH_LEVELS and world.phase == GameStateClass.Phase.WON
		if not cleared:
			return
	_finish(leader())


# -1 on a tie at the top.
func leader() -> int:
	var best := -1
	var tied := false
	for player_index in range(players.size()):
		if best < 0 or players[player_index].score > players[best].score:
			best = player_index
			tied = false
		elif players[player_index].score == players[best].score:
			tied = true
	return -1 if tied else best


func _finish(winner: int) -> void:
	is_over = true
	winner_index = winner
	finished.emit(winner)


# --- network snapshots -------------------------------------------------------
# A client only ever draws the one board it is standing on, so only that board
# travels - sending every plantation would burst the MTU that `to_snapshot` packs
# so carefully for as soon as a third player joins. The players are serialised
# here rather than per world, because a slot belongs to the match and merely
# stands on a board.

const SLOT_INTS := 6
const SLOT_TIMERS := 2


func to_bytes(world_index: int) -> PackedByteArray:
	var packed_players := PackedInt32Array()
	var packed_timers := PackedFloat32Array()
	for slot in players:
		packed_players.append(slot.cell.y * GameStateClass.WIDTH + slot.cell.x)
		packed_players.append(slot.facing.x)
		packed_players.append(slot.facing.y)
		packed_players.append(slot.score)
		packed_players.append(slot.lives)
		packed_players.append(1 if slot.is_out else 0)
		packed_timers.append(slot.coffee_charge)
		packed_timers.append(slot.invulnerable_until)
	return var_to_bytes([
		world_index,
		worlds[world_index].to_snapshot(),
		packed_players,
		packed_timers,
		world_of_player.duplicate(),
		match_seed,
		is_over,
		winner_index,
	])


func apply_bytes(payload: PackedByteArray) -> void:
	var snapshot: Variant = bytes_to_var(payload)
	if not (snapshot is Array) or (snapshot as Array).size() < 8:
		return
	var parts: Array = snapshot
	var world_index: int = parts[0]
	if world_index < 0 or world_index >= worlds.size():
		return
	var was_over := is_over
	worlds[world_index].apply_snapshot(parts[1])
	var packed_players: PackedInt32Array = parts[2]
	var packed_timers: PackedFloat32Array = parts[3]
	world_of_player.assign(parts[4])
	match_seed = parts[5]
	is_over = parts[6]
	winner_index = parts[7]
	# Slots are rebuilt in place so the render layer keeps its references, then
	# re-seated on the board that travelled. The other plantations keep whatever
	# they last held; a client never draws them.
	worlds[world_index].players.clear()
	var count := mini(players.size(), packed_players.size() / SLOT_INTS)
	for player_index in range(count):
		var base := player_index * SLOT_INTS
		var slot: PlayerSlot = players[player_index]
		slot.cell = worlds[world_index].cell_of(packed_players[base])
		slot.facing = Vector2i(packed_players[base + 1], packed_players[base + 2])
		slot.score = packed_players[base + 3]
		slot.lives = packed_players[base + 4]
		slot.is_out = packed_players[base + 5] != 0
		slot.coffee_charge = packed_timers[player_index * SLOT_TIMERS]
		slot.invulnerable_until = packed_timers[player_index * SLOT_TIMERS + 1]
		if not slot.is_out and world_of_player[player_index] == world_index:
			worlds[world_index].players.append(slot)
	changed.emit()
	# A client never runs `_check_finished`, so the end of the match reaches it
	# only here - as the moment the host's snapshot first says it is over.
	if is_over and not was_over:
		finished.emit(winner_index)
