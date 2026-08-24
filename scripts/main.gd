extends Node2D

const GameStateClass = preload("res://scripts/game_state.gd")
const InputResolverClass = preload("res://scripts/input_resolver.gd")
const LevelDataClass = preload("res://scripts/level_data.gd")
const GameAudioClass = preload("res://scripts/audio.gd")
const SaveDataClass = preload("res://scripts/save_data.gd")
const MatchStateClass = preload("res://scripts/match_state.gd")
const NetLinkClass = preload("res://scripts/net_link.gd")
const TILE := 48
const BOARD_ORIGIN := Vector2(12, 6)
const BOARD_SIZE := Vector2(GameStateClass.WIDTH * TILE, GameStateClass.HEIGHT * TILE)
const PLAYER_STEP_TIME := GameStateClass.PLAYER_STEP_TIME
const ENEMY_STEP_TIME := GameStateClass.ENEMY_STEP_TIME
const FILTER_STEP_TIME := GameStateClass.FILTER_STEP_TIME
const HERO_TEXTURE := "res://assets/art/source/hero-walk-sheet-v1.png"
const HERO_COFFEE_CHARGE_TEXTURE := "res://assets/art/source/hero-coffee-charge-sheet-v1.png"
const HERO_COFFEE_THROW_TEXTURE := "res://assets/art/source/hero-coffee-throw-sheet-v1.png"
const COFFEE_THROW_TIME := 0.24
const TEAPOD_FALLBACK_TEXTURE := "res://assets/art/source/tea-filter-sheet-v2.png"
const BEAN_TEXTURES := [
	"res://assets/art/source/coffee-bean-single-v2.png",
	"res://assets/art/source/coffee-beans-three-v2.png",
	"res://assets/art/source/coffee-beans-five-v2.png",
	"res://assets/art/source/coffee-bean-giant-v2.png",
]
const BEAN_SIZES := [26.0, 32.0, 36.0, 44.0]
const ENEMY_TEXTURES := {
	&"teapod": "res://assets/art/source/tea-filter-walk-sheet-v3.png",
	&"teapot": "res://assets/art/source/tea-pot-sheet-v1.png",
	&"ultra": "res://assets/art/source/ultra-chimp-sheet-v1.png",
}
const ENEMY_SIZES := {&"teapod": 44.0, &"teapot": 50.0, &"ultra": 56.0}
const LEVEL_BACKGROUNDS := [
	"res://assets/art/source/level-tropical-background.png",
	"res://assets/art/source/level-canyon-background-v1.png",
	"res://assets/art/source/level-mist-marsh-background-v1.png",
	"res://assets/art/source/level-water-lagoon-background-v1.png",
	"res://assets/art/source/level-night-ruins-background-v1.png",
	"res://assets/art/source/level-cloud-temple-background-v1.png",
	"res://assets/art/source/level-canyon-background-v1.png",
	"res://assets/art/source/level-mist-marsh-background-v1.png",
	"res://assets/art/source/level-night-ruins-background-v1.png",
	"res://assets/art/source/level-cloud-temple-background-v1.png",
]
const LEVEL_BACKGROUND_TINTS := [
	Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE,
	Color("e6c7b8"), Color("bed4cd"), Color("c5bde8"), Color("ffd0aa"),
]
# Endless levels reuse the ten backdrops; each further lap gets its own wash so
# a repeat never reads as the same level.
const ENDLESS_TINTS := [Color("bcd0ff"), Color("ffc4bc"), Color("c4f0c0"), Color("edc6ff")]

enum UiMode { TITLE, LOBBY, PLAYING, PAUSED, GAME_OVER }

# The host simulates and ships state at this rate; the client only draws. Actor
# tweens already smooth between cells, so a faster stream would buy nothing.
const SNAPSHOT_INTERVAL := 1.0 / 15.0
# One colour per slot, so the figure on the board and the line in the side panel
# read as the same person. Slot 0 keeps the untinted hero.
const PLAYER_TINTS: Array[Color] = [Color.WHITE, Color("9ed6f0"), Color("a8e6a0"), Color("f0a8d8")]

var state: GameState
var resolver: InputResolver
var tile_layer: TileMapLayer
var board: Node2D
var backdrop: Sprite2D
var actors := Node2D.new()
var bean_nodes: Dictionary = {}
var player_node: Node2D
var enemy_nodes: Array[Node2D] = []
var filter_nodes: Array[Node2D] = []
var score_label: Label
var lives_label: Label
var beans_label: Label
var status_label: Label
var roster_label: RichTextLabel
var move_cooldown := 0.0
var enemy_cooldown := ENEMY_STEP_TIME
var teapot_cooldown := ENEMY_STEP_TIME
var ultra_cooldown := ENEMY_STEP_TIME
var filter_cooldown := FILTER_STEP_TIME
var virtual_tilt := Vector2.ZERO
var drag_origin := Vector2.ZERO
var dragging := false
var elapsed := 0.0
var snap_next_refresh := true
var player_hit_until := 0.0
var shake_strength := 0.0
var shield_node: Line2D
var was_invulnerable := false
var bean_glitter_idle_since := 0.0
var audio: GameAudio
var overlay: CanvasLayer
var overlay_dim: ColorRect
var overlay_title: Label
var overlay_body: Label
var best_label: Label
var ui_mode := UiMode.TITLE
var high_score := 0
var best_level := 0
# Null in single player. When set, `state` is a view onto one of its worlds.
var match_state: MatchState
var net: NetLink
var local_player := 0
var rival_nodes: Array[Node2D] = []
var charge_ring: Line2D
var coffee_throw_until: Dictionary[int, float] = {}
var shown_world := -1
var snapshot_countdown := 0.0
# Every guest ships its intent each frame. The host stores the latest one per
# player and walks it on its own step clock, otherwise one keypress would be one
# step per packet. Indexed by global player index; the local entry stays unused.
var remote_direction: Array[Vector2i] = []
var remote_throw: Array[bool] = []
var remote_move_cooldown: Array[float] = []
var portal_node: Node2D
# A rematch starts only once everybody has said yes.
var rematch_ready: Array[bool] = []
var lobby_address: LineEdit
var lobby_list: Label
var name_field: LineEdit


func _ready() -> void:
	state = GameStateClass.new()
	resolver = InputResolverClass.new()
	audio = GameAudioClass.new()
	add_child(audio)
	high_score = SaveDataClass.high_score()
	best_level = SaveDataClass.best_level()
	audio.set_muted(SaveDataClass.is_muted())
	_build_background()
	_build_tiles()
	_build_hud()
	portal_node = _build_portal()
	board.add_child(portal_node)
	board.add_child(actors)
	shield_node = _build_shield()
	actors.add_child(shield_node)
	charge_ring = _build_charge_ring()
	actors.add_child(charge_ring)
	_build_overlay()
	_build_net()
	state.changed.connect(_refresh)
	state.event_emitted.connect(_on_game_event)
	_refresh()
	_show_title()
	queue_redraw()


func _build_background() -> void:
	RenderingServer.set_default_clear_color(Color("17110f"))
	var panel := Polygon2D.new()
	panel.polygon = PackedVector2Array([
		Vector2(840, 0), Vector2(960, 0), Vector2(960, 540), Vector2(840, 540)
	])
	panel.color = Color("2c1b17")
	add_child(panel)


func _build_tiles() -> void:
	board = Node2D.new()
	add_child(board)
	backdrop = Sprite2D.new()
	_update_level_background()
	backdrop.position = BOARD_ORIGIN + BOARD_SIZE * 0.5
	board.add_child(backdrop)

	tile_layer = TileMapLayer.new()
	tile_layer.position = BOARD_ORIGIN
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/art/game/tunnel.png")
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(Vector2i.ZERO)
	tile_set.add_source(source, 0)
	tile_layer.tile_set = tile_set
	tile_layer.modulate = Color(1, 1, 1, 0.88)
	board.add_child(tile_layer)


func _build_hud() -> void:
	var title := _label("COFFEE\nHUNTER", 24, Color("ffd27a"))
	title.position = Vector2(850, 18)
	add_child(title)
	score_label = _label("", 18, Color.WHITE)
	score_label.position = Vector2(850, 112)
	score_label.size = Vector2(102, 28)
	add_child(score_label)
	lives_label = _label("", 18, Color("ff8f70"))
	lives_label.position = Vector2(850, 146)
	lives_label.size = Vector2(102, 28)
	add_child(lives_label)
	beans_label = _label("", 18, Color("c9a227"))
	beans_label.position = Vector2(850, 180)
	beans_label.size = Vector2(102, 28)
	add_child(beans_label)
	best_label = _label("", 14, Color("9ec9d6"))
	best_label.position = Vector2(850, 214)
	best_label.size = Vector2(102, 24)
	add_child(best_label)
	# Rich text, because every player is named in their own colour - the same one
	# their figure wears on the board.
	roster_label = _rich_label(13)
	roster_label.position = Vector2(850, 238)
	roster_label.size = Vector2(102, 150)
	roster_label.visible = false
	add_child(roster_label)
	status_label = _label("", 16, Color("d9efb3"))
	status_label.position = Vector2(850, 252)
	status_label.size = Vector2(102, 130)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

func _rich_label(size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.add_theme_font_size_override("normal_font_size", size)
	label.add_theme_color_override("default_color", Color("f0e3d2"))
	return label


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 2
	add_child(overlay)
	overlay_dim = ColorRect.new()
	overlay_dim.color = Color(0.09, 0.06, 0.05, 0.86)
	overlay_dim.size = Vector2(960, 540)
	overlay.add_child(overlay_dim)
	overlay_title = _label("", 44, Color("ffd27a"))
	overlay_title.position = Vector2(0, 118)
	overlay_title.size = Vector2(960, 90)
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(overlay_title)
	overlay_body = _label("", 17, Color("f0e3d2"))
	overlay_body.position = Vector2(0, 226)
	overlay_body.size = Vector2(960, 280)
	overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(overlay_body)
	lobby_list = _label("", 16, Color("d9efb3"))
	lobby_list.position = Vector2(0, 330)
	lobby_list.size = Vector2(960, 120)
	lobby_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_list.visible = false
	overlay.add_child(lobby_list)
	lobby_address = LineEdit.new()
	lobby_address.position = Vector2(330, 452)
	lobby_address.size = Vector2(300, 34)
	lobby_address.placeholder_text = "Type an IP (e.g. 192.168.1.20)"
	lobby_address.alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_address.visible = false
	lobby_address.text_submitted.connect(_on_address_submitted)
	overlay.add_child(lobby_address)
	# Never focused on its own: a focused field swallows every shortcut, which is
	# exactly how the lobby once ate the H for hosting.
	name_field = LineEdit.new()
	name_field.position = Vector2(380, 490)
	name_field.size = Vector2(200, 34)
	name_field.max_length = SaveDataClass.NAME_LENGTH
	name_field.placeholder_text = "Your name"
	name_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_field.text = SaveDataClass.player_name()
	name_field.visible = false
	name_field.text_submitted.connect(_on_name_submitted)
	var name_hint := _label("YOUR NAME", 15, Color("9ec9d6"))
	name_hint.position = Vector2(150, 496)
	name_hint.size = Vector2(220, 24)
	name_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_field.visibility_changed.connect(func() -> void: name_hint.visible = name_field.visible)
	name_hint.visible = false
	overlay.add_child(name_hint)
	name_field.focus_exited.connect(_save_player_name)
	overlay.add_child(name_field)


func _build_net() -> void:
	net = NetLinkClass.new()
	net.name = "NetLink"
	add_child(net)
	net.lobby_changed.connect(_refresh_lobby_list)
	net.roster_changed.connect(_refresh_lobby_list)
	net.link_ready.connect(_on_link_ready)
	net.link_lost.connect(_on_link_lost)
	net.player_left.connect(_on_player_left)
	net.match_started.connect(_on_match_started)
	net.snapshot_received.connect(_on_snapshot_received)
	net.event_received.connect(_on_remote_event)
	net.input_received.connect(_on_remote_input)
	net.rematch_requested.connect(_on_rematch_requested)
	net.rematch_changed.connect(_on_rematch_changed)


func _show_lobby() -> void:
	ui_mode = UiMode.LOBBY
	overlay.visible = true
	name_field.visible = false
	overlay_title.text = "PLANTATION RACE"
	overlay_body.text = "Up to four plantations, linked in a ring by portals.\n\nH  host a game and wait for players\nESC  back to the title"
	lobby_list.visible = true
	lobby_address.visible = true
	net.start_browsing()
	_refresh_lobby_list()


func _hide_lobby_widgets() -> void:
	lobby_list.visible = false
	lobby_address.visible = false
	if net:
		net.stop_browsing()


# One label, two jobs: the games out on the network before joining, the players
# in the room afterwards.
func _refresh_lobby_list() -> void:
	if ui_mode != UiMode.LOBBY:
		return
	if net.is_online():
		_show_waiting_room()
		return
	if net.found_games.is_empty():
		lobby_list.text = "Searching the local network...\n(or click the field below, type an address, ENTER)"
		return
	var lines := "Games found - press a number key to join:\n"
	for index in range(mini(net.found_games.size(), 9)):
		var entry: Dictionary = net.found_games[index]
		lines += "%d)  %s   %s   (%d/%d)\n" % [
			index + 1, entry["name"], entry["address"],
			int(entry.get("players", 1)), NetLinkClass.MAX_PLAYERS,
		]
	lobby_list.text = lines


# Nobody drops into a race unannounced: the host waits until the room is as full
# as it is going to get and says when.
func _show_waiting_room() -> void:
	overlay_title.text = "WAITING ROOM"
	var lines := ""
	for entry in net.roster:
		var mark := "   (you)" if int(entry["index"]) == local_player else ""
		lines += "%d)  %s%s\n" % [int(entry["index"]) + 1, entry["name"], mark]
	lobby_list.text = lines
	if not net.is_host():
		overlay_body.text = "%s\n\nThe host starts the race.      ESC to cancel" % net.status_text
	elif net.roster.size() >= 2:
		overlay_body.text = "%d of %d players here.\n\nSPACE starts the race      ESC to cancel" % [
			net.roster.size(), NetLinkClass.MAX_PLAYERS,
		]
	else:
		overlay_body.text = "Waiting for players...\n\nESC to cancel"


func _on_address_submitted(address: String) -> void:
	if address.strip_edges() == "":
		return
	net.join(address, SaveDataClass.player_name())
	overlay_body.text = net.status_text


# Both sides land here once the link stands: the host right away, a guest the
# moment the roster hands it a slot - and again if a rematch renumbers the slots.
# Nobody starts a match here; the host does that from the waiting room.
func _on_link_ready(player_index: int) -> void:
	local_player = player_index
	lobby_address.visible = false
	_refresh_lobby_list()


func _on_match_started(seed_value: int, player_count: int) -> void:
	local_player = net.local_player_index()
	_begin_match(seed_value, player_count)


func _begin_match(seed_value: int, player_count: int) -> void:
	audio.play(&"start")
	coffee_throw_until.clear()
	ui_mode = UiMode.PLAYING
	overlay.visible = false
	_hide_lobby_widgets()
	# The room is shut for the duration: a latecomer would hold up the rematch.
	net.accepting = false
	match_state = MatchStateClass.new(seed_value, player_count)
	# A guest without a seat would index straight out of the player list.
	local_player = clampi(local_player, 0, match_state.player_count() - 1)
	match_state.event_emitted.connect(_on_match_event)
	match_state.finished.connect(_on_match_finished)
	match_state.start_game()
	shown_world = -1
	snapshot_countdown = 0.0
	var count := match_state.player_count()
	remote_direction.resize(count)
	remote_direction.fill(Vector2i.ZERO)
	remote_throw.resize(count)
	remote_throw.fill(false)
	remote_move_cooldown.resize(count)
	remote_move_cooldown.fill(0.0)
	rematch_ready.resize(count)
	rematch_ready.fill(false)
	_switch_to_world(match_state.world_of_player[local_player])


func _on_link_lost(reason: String) -> void:
	match_state = null
	_show_title()
	overlay_title.text = "VERBINDUNG WEG"
	overlay_body.text = "%s\n\nSPACE for a new run      ESC for the title" % reason


# A quitter only vacates their own plantation; the rest of the race carries on,
# and the match settles itself once too few are left.
func _on_player_left(player_index: int) -> void:
	if match_state == null:
		return
	match_state.eliminate(player_index)


func _on_snapshot_received(payload: PackedByteArray) -> void:
	if match_state == null:
		return
	match_state.apply_bytes(payload)
	var world_index: int = match_state.world_of_player[local_player]
	if world_index != shown_world:
		_switch_to_world(world_index)
	else:
		_refresh()


# Intent only: acting on it here would step that guest once per arriving packet,
# which is 60 steps a second. `_process_match` spends it on the step clock.
func _on_remote_input(player_index: int, direction: Vector2i, throw_pressed: bool) -> void:
	if match_state == null or not net.is_host() or player_index == local_player:
		return
	if player_index < 0 or player_index >= remote_direction.size():
		return
	remote_direction[player_index] = direction
	# Latched: the press lives for one client frame, the host consumes it on its
	# next tick.
	remote_throw[player_index] = remote_throw[player_index] or throw_pressed


func _on_remote_event(kind: StringName, cell: Vector2i, world_index: int, player_index: int) -> void:
	_on_match_event(kind, cell, world_index, player_index)


# Only what happens on the board being drawn may fire sound and particles; the
# other plantations tick away off-screen and must stay silent.
func _on_match_event(kind: StringName, cell: Vector2i, world_index: int, player_index: int) -> void:
	if net != null and net.is_host():
		net.broadcast_event(kind, cell, world_index, player_index)
	if world_index != shown_world:
		return
	_on_game_event(kind, cell, player_index)


func _on_match_finished(winner: int) -> void:
	if match_state == null:
		return
	ui_mode = UiMode.GAME_OVER
	overlay.visible = true
	rematch_ready.fill(false)
	if winner < 0:
		overlay_title.text = "DRAW"
	elif winner == local_player:
		overlay_title.text = "YOU WIN"
	else:
		overlay_title.text = "YOU LOSE"
	# The host stops simulating the moment the overlay is up, so the snapshot that
	# carries `is_over` has to go out now - the next scheduled one never comes, and
	# without it a guest keeps staring at a frozen board.
	if net != null and net.is_host():
		_send_snapshots()
	_show_match_result()


# Every guest gets exactly the plantation it is standing on. Four whole boards
# would not fit in one packet, and it would never draw the other three anyway.
func _send_snapshots() -> void:
	for entry in net.guests():
		var player_index := int(entry["index"])
		if player_index < 0 or player_index >= match_state.world_of_player.size():
			continue
		net.send_snapshot(int(entry["peer_id"]), match_state.to_bytes(match_state.world_of_player[player_index]))


func _player_name(player_index: int) -> String:
	if net != null and net.is_online():
		return net.name_of(player_index)
	return "PLAYER %d" % (player_index + 1)


func _show_match_result() -> void:
	if match_state == null:
		return
	var order := range(match_state.player_count())
	order.sort_custom(func(a: int, b: int) -> bool: return match_state.players[a].score > match_state.players[b].score)
	var lines := ""
	for place in range(order.size()):
		var player_index: int = order[place]
		var slot: PlayerSlot = match_state.players[player_index]
		var standing := "out" if slot.is_out else _lives_text(slot.lives)
		var mark := "   <- you" if player_index == local_player else ""
		lines += "%d.  %s   %d points   %s%s\n" % [place + 1, _player_name(player_index), slot.score, standing, mark]
	overlay_body.text = "%s\n%s" % [lines, _rematch_line()]


func _lives_text(lives: int) -> String:
	return "1 life" if lives == 1 else "%d lives" % lives


# Only whoever is still on the link can agree; a seat vacated mid-race must not
# hold the next one hostage.
func _rematch_pending() -> Array[String]:
	var waiting: Array[String] = []
	for entry in net.roster:
		var player_index := int(entry["index"])
		if player_index < rematch_ready.size() and not rematch_ready[player_index]:
			waiting.append(String(entry["name"]))
	return waiting


func _rematch_line() -> String:
	if net == null or not net.is_online():
		return "SPACE for a new run      ESC for the title"
	if net.roster.size() < 2:
		return "Nobody left to race.\n\nESC for the title"
	var waiting := _rematch_pending()
	if waiting.is_empty():
		return "REMATCH - everybody is ready!"
	return "REMATCH - press SPACE.  Still missing: %s\n\nESC for the title" % ", ".join(waiting)


# Announcing is all a guest can do; the tally and the seed belong to the host.
func _request_rematch() -> void:
	if net == null or not net.is_online():
		return
	if local_player < 0 or local_player >= rematch_ready.size() or rematch_ready[local_player]:
		return
	rematch_ready[local_player] = true
	_show_match_result()
	if net.is_host():
		_publish_rematch()
	else:
		net.send_rematch()


func _publish_rematch() -> void:
	var flags := PackedByteArray()
	for is_ready in rematch_ready:
		flags.append(1 if is_ready else 0)
	net.broadcast_rematch(flags)
	_start_rematch_if_agreed()


func _on_rematch_requested(player_index: int) -> void:
	if ui_mode != UiMode.GAME_OVER or match_state == null or not net.is_host():
		return
	if player_index < 0 or player_index >= rematch_ready.size():
		return
	rematch_ready[player_index] = true
	_show_match_result()
	_publish_rematch()


func _on_rematch_changed(flags: PackedByteArray) -> void:
	if match_state == null:
		return
	for player_index in range(mini(flags.size(), rematch_ready.size())):
		rematch_ready[player_index] = flags[player_index] != 0
	if ui_mode == UiMode.GAME_OVER:
		_show_match_result()


func _start_rematch_if_agreed() -> void:
	if not net.is_host() or net.roster.size() < 2 or not _rematch_pending().is_empty():
		return
	# Seats left empty by quitters are closed up first, so the next match can keep
	# counting its players 0..n-1.
	net.compact_slots()
	local_player = net.local_player_index()
	var seed_value := randi() & 0x7fffffff
	var count := net.roster.size()
	net.broadcast_match_start(seed_value, count)
	_begin_match(seed_value, count)


# The rendered world is swapped wholesale on a portal hop: every actor teleports,
# so nothing may tween across the board from its old position.
func _switch_to_world(world_index: int) -> void:
	if match_state == null:
		return
	if state != null:
		if state.changed.is_connected(_refresh):
			state.changed.disconnect(_refresh)
		if state.event_emitted.is_connected(_on_game_event):
			state.event_emitted.disconnect(_on_game_event)
	shown_world = world_index
	state = match_state.worlds[world_index]
	state.changed.connect(_refresh)
	_reset_level_view()


func _show_title() -> void:
	ui_mode = UiMode.TITLE
	overlay.visible = true
	name_field.visible = true
	overlay_title.text = "COFFEE HUNTER"
	overlay_body.text = "Grounds for Adventure\n\n%s\n\nWASD / ARROWS to dig  -  drag the mouse to tilt\nSPACE  single player    N  network race    P pause  R restart  M mute" % _high_score_lines()


# The five best runs. Only single-player runs land here: match scores carry stolen
# points and would not compare with them.
func _high_score_lines() -> String:
	var entries := SaveDataClass.scores()
	if entries.is_empty():
		return "NO RUN RECORDED YET"
	var lines: Array[String] = ["HIGH SCORES"]
	for place in range(entries.size()):
		var entry: Dictionary = entries[place]
		lines.append("%d.  %s   %d   Level %d" % [
			place + 1, entry.get("name", "?"), int(entry["score"]), int(entry.get("level", 0)) + 1,
		])
	return "\n".join(lines)


func _on_name_submitted(_text: String) -> void:
	_save_player_name()
	# Handing focus back is what lets SPACE and N work again.
	name_field.release_focus()


func _save_player_name() -> void:
	SaveDataClass.set_player_name(name_field.text)
	name_field.text = SaveDataClass.player_name()
	if ui_mode == UiMode.TITLE:
		_show_title()


func _show_game_over(is_record: bool) -> void:
	ui_mode = UiMode.GAME_OVER
	overlay.visible = true
	name_field.visible = false
	overlay_title.text = "FILTERED OUT"
	var record := "SCORE  %d      BEST  %d" % [state.score, high_score]
	if is_record:
		record = "NEW BEST  %d" % state.score
	overlay_body.text = "%s\nReached level %d\n\nSPACE or R for a new run      ESC for the title" % [record, state.level_index + 1]


func _set_paused(paused: bool) -> void:
	ui_mode = UiMode.PAUSED if paused else UiMode.PLAYING
	overlay.visible = paused
	name_field.visible = false
	audio.play(&"ui")
	if paused:
		overlay_title.text = "PAUSED"
		overlay_body.text = "LEVEL %d      SCORE %d\n\nP or SPACE to resume\nR for a new run      ESC for the title" % [state.level_index + 1, state.score]


func _begin_run() -> void:
	audio.play(&"start")
	ui_mode = UiMode.PLAYING
	overlay.visible = false
	snap_next_refresh = true
	state.new_game()
	_reset_level_view()


func _toggle_mute() -> void:
	audio.set_muted(not audio.muted)
	SaveDataClass.set_muted(audio.muted)
	if not audio.muted:
		audio.play(&"ui")


# A cleared level banks the progress but does not close the run - the table gets
# its line when the run actually ends, once.
func _record_progress() -> void:
	SaveDataClass.record_progress(state.score, state.level_index)
	_remember_best()


func _record_run() -> bool:
	var is_record := SaveDataClass.record_run(state.score, state.level_index, SaveDataClass.player_name())
	_remember_best()
	return is_record


func _remember_best() -> void:
	high_score = maxi(high_score, state.score)
	best_level = maxi(best_level, state.level_index)


# True while a menu owns the frame, which is also what freezes the simulation.
func _handle_ui_input() -> bool:
	if ui_mode == UiMode.TITLE:
		# A focused field swallows typing, so the shortcuts stand down while the
		# name is being edited.
		if name_field.has_focus():
			return true
		if Input.is_action_just_pressed("confirm"):
			_begin_run()
		elif Input.is_key_pressed(KEY_N):
			_show_lobby()
		return true
	if ui_mode == UiMode.LOBBY:
		_handle_lobby_input()
		return true
	if ui_mode == UiMode.GAME_OVER:
		if Input.is_action_just_pressed("to_title"):
			_leave_match()
			_show_title()
		elif Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("restart"):
			if match_state != null:
				_request_rematch()
			else:
				_begin_run()
		return true
	if ui_mode == UiMode.PAUSED:
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("confirm"):
			_set_paused(false)
		elif Input.is_action_just_pressed("restart"):
			_begin_run()
		elif Input.is_action_just_pressed("to_title"):
			_show_title()
		return true
	if Input.is_action_just_pressed("to_title"):
		_leave_match()
		_show_title()
		return true
	if match_state != null:
		return false
	if Input.is_action_just_pressed("pause"):
		_set_paused(true)
		return true
	if Input.is_action_just_pressed("restart"):
		_begin_run()
		return true
	return false


func _handle_lobby_input() -> void:
	if Input.is_action_just_pressed("to_title"):
		# Leaving the waiting room has to drop the link too, or the peer keeps
		# running behind the title screen.
		if net.is_online():
			net.disconnect_link()
		_hide_lobby_widgets()
		_show_title()
		return
	# The address field swallows typing, so the shortcuts only fire when it is
	# not the focused control - which is why the lobby opens with nothing focused
	# and the field only takes focus once it is clicked.
	if lobby_address.has_focus():
		return
	# Raw keys have no just_pressed helper: without this a held key would rebuild
	# the peer every frame.
	if net.is_online():
		# Only the host may call the start, and never on an empty room.
		if net.is_host() and net.roster.size() >= 2 and Input.is_action_just_pressed("confirm"):
			var seed_value := randi() & 0x7fffffff
			var count := net.roster.size()
			net.broadcast_match_start(seed_value, count)
			_begin_match(seed_value, count)
		return
	if Input.is_key_pressed(KEY_H):
		net.host(SaveDataClass.player_name())
		overlay_body.text = net.status_text
		return
	for slot in range(mini(net.found_games.size(), 9)):
		if Input.is_key_pressed(KEY_1 + slot):
			var entry: Dictionary = net.found_games[slot]
			net.join(String(entry["address"]), SaveDataClass.player_name())
			overlay_body.text = net.status_text
			return


func _leave_match() -> void:
	if net != null:
		net.accepting = true
		if net.is_online():
			net.disconnect_link()
	rematch_ready.clear()
	coffee_throw_until.clear()
	match_state = null
	shown_world = -1
	state = GameStateClass.new()
	state.changed.connect(_refresh)
	state.event_emitted.connect(_on_game_event)
	_reset_level_view()


func _process(delta: float) -> void:
	_animate_player()
	_animate_invulnerability()
	var player_moving := _actor_is_moving(player_node)
	if player_moving:
		bean_glitter_idle_since = elapsed
	var show_bean_glitter := state.phase == GameStateClass.Phase.PLAYING and state.beans.size() <= 3 and elapsed - bean_glitter_idle_since >= 0.35
	for cell in bean_nodes:
		var bean: Node2D = bean_nodes[cell]
		bean.position = _cell_position(cell) + Vector2(0, sin(elapsed * 4.0 + cell.x) * 2.0)
		_animate_bean_glitter(bean, cell, show_bean_glitter)
	for enemy_index in range(enemy_nodes.size()):
		var enemy_node := enemy_nodes[enemy_index]
		if is_instance_valid(enemy_node) and enemy_node.visible:
			_update_enemy_frame(enemy_node, enemy_index)
	_update_shake(delta)
	_animate_filters()
	_update_rival_nodes()
	_update_charge_ring()
	_animate_portal()
	queue_redraw()


func _physics_process(delta: float) -> void:
	elapsed += delta
	if Input.is_action_just_pressed("mute"):
		_toggle_mute()
	if _handle_ui_input():
		queue_redraw()
		return

	var direction := resolver.direction_from_vector(resolver.combined_vector(virtual_tilt))
	var throw_pressed := Input.is_action_just_pressed("throw")
	if match_state != null:
		_process_match(delta, direction, throw_pressed)
		queue_redraw()
		return

	if state.phase == GameStateClass.Phase.WON and direction != Vector2i.ZERO:
		_record_progress()
		if state.next_level():
			_reset_level_view()
			return
	if state.phase == GameStateClass.Phase.READY:
		if direction != Vector2i.ZERO:
			state.start_game()
		else:
			queue_redraw()
			return

	state.advance_time(delta)
	state.tick_contacts()
	move_cooldown -= delta
	enemy_cooldown -= delta
	teapot_cooldown -= delta
	ultra_cooldown -= delta
	filter_cooldown -= delta

	if move_cooldown <= 0.0 and elapsed >= player_hit_until:
		if state.move_player(direction):
			move_cooldown += _player_step_time()
		else:
			move_cooldown = 0.0

	if enemy_cooldown <= 0.0:
		state.tick_enemy(&"teapod")
		enemy_cooldown += _enemy_step_time()
	if teapot_cooldown <= 0.0:
		state.tick_enemy(&"teapot")
		teapot_cooldown += _enemy_step_time_for_kind(&"teapot")
	if ultra_cooldown <= 0.0:
		state.tick_enemy(&"ultra")
		ultra_cooldown += _enemy_step_time_for_kind(&"ultra")
	if filter_cooldown <= 0.0:
		state.tick_filter()
		filter_cooldown += _filter_step_time()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			drag_origin = event.position
		else:
			virtual_tilt = Vector2.ZERO
	if event is InputEventMouseMotion and dragging:
		virtual_tilt = ((event.position - drag_origin) / 90.0).limit_length(1.0)


func _refresh() -> void:
	_update_level_background()
	for y in range(GameStateClass.HEIGHT):
		for x in range(GameStateClass.WIDTH):
			var cell := Vector2i(x, y)
			if state.get_cell(cell) == GameStateClass.Cell.TUNNEL:
				tile_layer.set_cell(cell, 0, Vector2i.ZERO, 0)
			else:
				tile_layer.erase_cell(cell)

	for cell in bean_nodes.keys():
		if not state.beans.has(cell):
			bean_nodes[cell].queue_free()
			bean_nodes.erase(cell)
	for cell in state.beans:
		if not bean_nodes.has(cell):
			var variant := _bean_variant(state.beans[cell])
			var bean := _art_node(load(BEAN_TEXTURES[variant]), BEAN_SIZES[variant])
			bean.set_meta(&"tier", variant)
			bean.position = _cell_position(cell)
			actors.add_child(bean)
			bean_nodes[cell] = bean

	if not is_instance_valid(player_node):
		player_node = _hero_node()
		actors.add_child(player_node)
	player_node.modulate = _local_tint()
	# An eliminated player watches from where they fell; the figure stays gone.
	if match_state != null and match_state.players[local_player].is_out:
		player_node.visible = false
	_update_hero_frame()
	_move_actor(player_node, _local_slot().cell, _player_step_time())

	while enemy_nodes.size() < state.enemies.size():
		var enemy_node := _enemy_node(_enemy_kind(enemy_nodes.size()))
		actors.add_child(enemy_node)
		enemy_nodes.append(enemy_node)
	for enemy_index in range(state.enemies.size()):
		var enemy_node := enemy_nodes[enemy_index]
		if not is_instance_valid(enemy_node):
			enemy_node = _enemy_node(_enemy_kind(enemy_index))
			actors.add_child(enemy_node)
			enemy_nodes[enemy_index] = enemy_node
		var was_visible: bool = enemy_node.visible
		enemy_node.visible = state.is_enemy_active(enemy_index)
		if enemy_node.visible:
			if not was_visible:
				_snap_actor(enemy_node, state.enemies[enemy_index])
				_pop_in(enemy_node)
			var kind := state.enemy_kind(enemy_index)
			_move_actor(enemy_node, state.enemies[enemy_index], _enemy_step_time_for_kind(kind))

	while filter_nodes.size() < state.falling_filters.size():
		var filter_node := _art_node(load("res://assets/art/source/coffee-filter.png"), 44.0)
		actors.add_child(filter_node)
		filter_nodes.append(filter_node)
	for filter_index in range(state.falling_filters.size()):
		var filter_node := filter_nodes[filter_index]
		var filter_cell := state.falling_filters[filter_index]
		var filter_duration := _filter_step_time() * 0.72
		if filter_node.has_meta(&"target_cell"):
			var previous_cell: Vector2i = filter_node.get_meta(&"target_cell")
			if previous_cell.y == filter_cell.y:
				filter_duration = _player_step_time()
		_move_actor(filter_node, filter_cell, filter_duration)
	snap_next_refresh = false

	var shown_slot := _local_slot()
	score_label.text = "SCORE  %d" % shown_slot.score
	lives_label.text = "LIVES  %d" % shown_slot.lives
	beans_label.text = "BEANS  %d" % state.beans.size()
	best_label.text = "BEST  %d" % maxi(high_score, shown_slot.score)
	if audio and audio.muted:
		best_label.text += "   MUTED"
	# The field of players drops in above the controls, so the controls move down.
	roster_label.visible = match_state != null
	status_label.position.y = 392.0 if match_state != null else 252.0
	if match_state != null:
		roster_label.text = _roster_panel_text()
	match state.phase:
		GameStateClass.Phase.READY:
			status_label.text = "PRESS A DIRECTION\nTO START\n\nWASD / ARROWS\nor drag to tilt"
		GameStateClass.Phase.WON:
			if LevelDataClass.is_endless(state.level_index):
				status_label.text = "LEVEL CLEARED!\nPast the map now.\n\nPress a direction\nto keep going"
			else:
				status_label.text = "LEVEL CLEARED!\n\nPress a direction\nfor next level"
		GameStateClass.Phase.GAME_OVER:
			status_label.text = "FILTERED OUT.\n\nPress R"
		_:
			var level_line := "LEVEL %d" % (state.level_index + 1)
			if LevelDataClass.is_endless(state.level_index):
				level_line += "  ENDLESS"
			if match_state != null and match_state.players[local_player].is_out:
				status_label.text = "KNOCKED OUT\n\nWatching the\nothers race.\n\nESC  QUIT"
			elif match_state != null:
				status_label.text = "%s\n\nF  THROW\nCOFFEE\n\nESC  QUIT" % level_line
			else:
				status_label.text = "%s\nSPEED %.1f\n\nWASD / ARROWS\nDrag mouse to tilt\n\nP pause  R restart" % [level_line, LevelDataClass.speed(state.level_index)]


# Two lines per player - name, then standing - each in that player's own colour,
# the one their figure wears on the board.
func _roster_panel_text() -> String:
	var lines := ""
	for player_index in range(match_state.player_count()):
		var slot: PlayerSlot = match_state.players[player_index]
		var standing := "away"
		if slot.is_out:
			standing = "out"
		elif player_index == local_player:
			standing = "YOU"
		elif match_state.world_of_player[player_index] == shown_world:
			standing = "HERE!"
		lines += "[color=#%s]%s[/color]\n  %d  L%d  %s\n" % [
			_player_tint(player_index).to_html(false), _player_name(player_index),
			slot.score, slot.lives, standing,
		]
	return lines


func _player_tint(player_index: int) -> Color:
	return PLAYER_TINTS[player_index % PLAYER_TINTS.size()]


# The local hero wears its slot colour in a match, so the panel can name it.
func _local_tint() -> Color:
	if match_state == null:
		return Color.WHITE
	return _player_tint(local_player)


func _update_level_background() -> void:
	if not is_instance_valid(backdrop):
		return
	var index: int = maxi(state.level_index, 0) % LEVEL_BACKGROUNDS.size()
	var next_texture: Texture2D = load(LEVEL_BACKGROUNDS[index])
	if backdrop.texture != next_texture:
		backdrop.texture = next_texture
		backdrop.scale = BOARD_SIZE / next_texture.get_size()
	var tint: Color = LEVEL_BACKGROUND_TINTS[index]
	var lap: int = maxi(state.level_index, 0) / LEVEL_BACKGROUNDS.size()
	if lap > 0:
		tint *= ENDLESS_TINTS[(lap - 1) % ENDLESS_TINTS.size()]
	backdrop.modulate = tint


# The hero on screen is always the LOCAL player's slot. `state.player` is the
# shown board's first slot instead, which stops being the same thing the moment
# one side steps through the portal and both stand on one plantation.
func _local_slot() -> PlayerSlot:
	if match_state != null:
		return match_state.players[local_player]
	return state.players[0]


# Where that slot sits in the shown board's own player list. Falls back to 0 for
# the frame between a portal hop and the view swapping to the other plantation,
# when the slot is not on the drawn board at all.
func _local_board_index() -> int:
	if match_state == null:
		return 0
	return maxi(state.players.find(_local_slot()), 0)


func _player_step_time() -> float:
	return state.player_step_time()


func _enemy_step_time() -> float:
	return state.enemy_step_time()


func _enemy_step_time_for_kind(kind: StringName) -> float:
	return state.enemy_step_time_for_kind(kind)


func _filter_step_time() -> float:
	return state.filter_step_time()


func _reset_level_view() -> void:
	snap_next_refresh = true
	for node in bean_nodes.values():
		node.queue_free()
	bean_nodes.clear()
	for node in enemy_nodes:
		node.queue_free()
	enemy_nodes.clear()
	for node in filter_nodes:
		node.queue_free()
	filter_nodes.clear()
	if is_instance_valid(player_node):
		player_node.visible = true
		player_node.scale = Vector2.ONE
		player_node.rotation = 0.0
	player_hit_until = 0.0
	move_cooldown = 0.0
	remote_move_cooldown.fill(0.0)
	enemy_cooldown = _enemy_step_time()
	teapot_cooldown = _enemy_step_time_for_kind(&"teapot")
	ultra_cooldown = _enemy_step_time_for_kind(&"ultra")
	filter_cooldown = _filter_step_time()
	_refresh()


func _hero_node() -> Node2D:
	var texture: Texture2D = load(HERO_TEXTURE)
	var frame_size := texture.get_size() / 4.0
	return _art_node(texture, 52.0, Rect2(Vector2.ZERO, frame_size))


func _enemy_node(kind: StringName) -> Node2D:
	var texture: Texture2D = load(ENEMY_TEXTURES[kind])
	if not texture and kind == &"teapod":
		push_warning("Tea-pod walk sheet could not be loaded; using the previous sprite sheet")
		texture = load(TEAPOD_FALLBACK_TEXTURE)
	if not texture:
		push_error("Enemy texture could not be loaded for %s" % kind)
		return Node2D.new()
	var frame_size := texture.get_size() / 2.0
	var node := _art_node(texture, ENEMY_SIZES[kind], Rect2(Vector2.ZERO, frame_size))
	node.set_meta(&"enemy_kind", kind)
	return node


func _enemy_kind(enemy_index: int) -> StringName:
	return state.enemy_kind(enemy_index)


func _bean_variant(value: Variant) -> int:
	return clampi(value, 0, BEAN_TEXTURES.size() - 1) if value is int else 0


func _update_enemy_frame(enemy_node: Node2D, enemy_index: int) -> void:
	var kind: StringName = enemy_node.get_meta(&"enemy_kind", &"teapod")
	var texture: Texture2D = load(ENEMY_TEXTURES[kind])
	var frame_size := texture.get_size() / 2.0
	var frames := [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0)]
	if kind == &"teapod":
		frames = [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var frame := Vector2i.ZERO
	var progress := _actor_move_progress(enemy_node)
	if progress < 1.0:
		frame = frames[mini(int(progress * frames.size()), frames.size() - 1)]
	_set_enemy_frame(enemy_node, frame, frame_size)


func _set_enemy_frame(enemy_node: Node2D, frame: Vector2i, frame_size := Vector2.ZERO) -> void:
	if frame_size == Vector2.ZERO:
		var kind: StringName = enemy_node.get_meta(&"enemy_kind", &"teapod")
		var texture: Texture2D = load(ENEMY_TEXTURES[kind])
		frame_size = texture.get_size() / 2.0
	var region := Rect2(Vector2(frame) * frame_size, frame_size)
	for sprite in enemy_node.get_children():
		if sprite is Sprite2D:
			sprite.region_rect = region


func _update_hero_frame() -> void:
	_set_hero_frame(player_node, _local_slot().facing)


func _set_hero_frame(hero: Node2D, facing: Vector2i, walk_frame := 0) -> void:
	var texture: Texture2D = load(HERO_TEXTURE)
	var frame_size := texture.get_size() / 4.0
	var row := 0
	if facing == Vector2i.UP:
		row = 1
	elif facing == Vector2i.LEFT:
		row = 2
	elif facing == Vector2i.RIGHT:
		row = 2
	var frame := Vector2i(clampi(walk_frame, 0, 3), row)
	var region := Rect2(Vector2(frame) * frame_size, frame_size)
	_set_hero_texture(hero, texture, region, facing == Vector2i.RIGHT)


func _set_hero_action_frame(hero: Node2D, texture_path: String, facing: Vector2i, action_frame: int) -> void:
	var texture: Texture2D = load(texture_path)
	var frame_size := texture.get_size() / 4.0
	var row := 0
	if facing == Vector2i.UP:
		row = 1
	elif facing == Vector2i.LEFT:
		row = 2
	elif facing == Vector2i.RIGHT:
		row = 3
	var frame := Vector2i(clampi(action_frame, 0, 3), row)
	_set_hero_texture(hero, texture, Rect2(Vector2(frame) * frame_size, frame_size), false)


func _set_hero_texture(hero: Node2D, texture: Texture2D, region: Rect2, flip_h: bool) -> void:
	var scale_factor := 52.0 / maxf(region.size.x, region.size.y)
	for child in hero.get_children():
		if child is Sprite2D:
			child.texture = texture
			child.region_rect = region
			child.scale = Vector2.ONE * scale_factor
			child.flip_h = flip_h


func _animate_player() -> void:
	if not is_instance_valid(player_node) or not player_node.visible:
		return
	if _set_coffee_action_frame(player_node, local_player):
		player_node.scale = Vector2.ONE
		player_node.rotation = 0.0
		return
	var moving := _actor_is_moving(player_node)
	if moving:
		var walk_cycle := [1, 2, 3, 2]
		var progress := _actor_move_progress(player_node)
		var frame_index := mini(int(progress * walk_cycle.size()), walk_cycle.size() - 1)
		_set_hero_frame(player_node, _local_slot().facing, walk_cycle[frame_index])
		player_node.scale = Vector2.ONE
		player_node.rotation = 0.0
	else:
		_set_hero_frame(player_node, _local_slot().facing)
		var breath := sin(elapsed * 3.2) * 0.012
		player_node.scale = Vector2(1.0 - breath * 0.5, 1.0 + breath)
		player_node.rotation = 0.0


func _set_coffee_action_frame(hero: Node2D, player_index: int) -> bool:
	if match_state == null or player_index < 0 or player_index >= match_state.player_count():
		return false
	var slot: PlayerSlot = match_state.players[player_index]
	var throw_left := float(coffee_throw_until.get(player_index, 0.0)) - elapsed
	if throw_left > 0.0:
		var progress := 1.0 - throw_left / COFFEE_THROW_TIME
		_set_hero_action_frame(hero, HERO_COFFEE_THROW_TEXTURE, slot.facing, mini(int(progress * 4.0), 3))
		return true
	var ratio := match_state.charge_ratio(player_index)
	if ratio <= 0.01:
		return false
	_set_hero_action_frame(hero, HERO_COFFEE_CHARGE_TEXTURE, slot.facing, mini(int(ratio * 4.0), 3))
	return true


func _actor_is_moving(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not actor.has_meta(&"move_tween"):
		return false
	var move_tween: Tween = actor.get_meta(&"move_tween")
	return move_tween and move_tween.is_running()


func _animate_bean_glitter(bean: Node2D, cell: Vector2i, active: bool) -> void:
	var glitter: Node2D
	if bean.has_meta(&"glitter"):
		glitter = bean.get_meta(&"glitter")
	else:
		glitter = Node2D.new()
		glitter.z_index = 3
		for sparkle_index in range(2):
			var sparkle := Polygon2D.new()
			var radius := 5.0 if sparkle_index == 0 else 3.5
			sparkle.polygon = PackedVector2Array([
				Vector2(0, -radius), Vector2(radius * 0.28, -radius * 0.28),
				Vector2(radius, 0), Vector2(radius * 0.28, radius * 0.28),
				Vector2(0, radius), Vector2(-radius * 0.28, radius * 0.28),
				Vector2(-radius, 0), Vector2(-radius * 0.28, -radius * 0.28),
			])
			sparkle.color = Color("fff3a6")
			glitter.add_child(sparkle)
		bean.add_child(glitter)
		bean.set_meta(&"glitter", glitter)
	glitter.visible = active
	if not active:
		bean.scale = Vector2.ONE
		bean.modulate = Color.WHITE
		return
	var phase := elapsed * 5.5 + float(cell.x * 3 + cell.y)
	var pulse := (sin(phase) + 1.0) * 0.5
	bean.scale = Vector2.ONE * (1.0 + pulse * 0.045)
	bean.modulate = Color(1.0, 0.94 + pulse * 0.06, 0.72 + pulse * 0.28)
	glitter.rotation = phase * 0.22
	for sparkle_index in range(glitter.get_child_count()):
		var sparkle: Polygon2D = glitter.get_child(sparkle_index)
		var angle := phase + float(sparkle_index) * PI
		sparkle.position = Vector2(cos(angle), sin(angle)) * (15.0 + sparkle_index * 4.0)
		var sparkle_pulse := 0.25 + 0.75 * absf(sin(phase * 1.7 + sparkle_index * 1.9))
		sparkle.scale = Vector2.ONE * sparkle_pulse
		sparkle.modulate.a = sparkle_pulse
# Teleports (a pod climbing back out of the nest) must not be tweened across
# the board from wherever the sprite happened to be.
func _snap_actor(actor: Node2D, cell: Vector2i) -> void:
	if actor.has_meta(&"move_tween"):
		var previous_tween: Tween = actor.get_meta(&"move_tween")
		if previous_tween and previous_tween.is_valid():
			previous_tween.kill()
	actor.position = _cell_position(cell).round()
	actor.set_meta(&"target_cell", cell)


func _move_actor(actor: Node2D, cell: Vector2i, duration: float) -> void:
	var target := _cell_position(cell)
	if actor.has_meta(&"target_cell") and actor.get_meta(&"target_cell") == cell:
		return
	if actor.has_meta(&"move_tween"):
		var previous_tween: Tween = actor.get_meta(&"move_tween")
		if previous_tween and previous_tween.is_valid():
			previous_tween.kill()
	actor.set_meta(&"target_cell", cell)
	if snap_next_refresh or actor.position == Vector2.ZERO:
		actor.position = target.round()
		return
	if actor.position.is_equal_approx(target.round()):
		actor.position = target.round()
		return
	var tween := create_tween()
	actor.set_meta(&"move_tween", tween)
	actor.set_meta(&"move_started_at", elapsed)
	actor.set_meta(&"move_duration", duration)
	tween.tween_property(actor, "position", target.round(), duration).from_current().set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func() -> void:
		if is_instance_valid(actor) and actor.get_meta(&"target_cell") == cell:
			actor.position = target.round()
	)


func _actor_move_progress(actor: Node2D) -> float:
	if not actor.has_meta(&"move_started_at") or not actor.has_meta(&"move_duration"):
		return 1.0
	var duration: float = actor.get_meta(&"move_duration")
	if duration <= 0.0:
		return 1.0
	return clampf((elapsed - float(actor.get_meta(&"move_started_at"))) / duration, 0.0, 1.0)


func _art_node(texture: Texture2D, target_size: float, region := Rect2()) -> Node2D:
	var root := Node2D.new()
	var display_region := region
	if display_region.size == Vector2.ZERO:
		var used_rect := texture.get_image().get_used_rect()
		if used_rect.size != Vector2i.ZERO:
			display_region = Rect2(used_rect)
	var source_size := display_region.size if display_region.size != Vector2.ZERO else texture.get_size()
	var scale_factor := target_size / maxf(source_size.x, source_size.y)
	var shadow := Sprite2D.new()
	shadow.texture = texture
	shadow.region_enabled = display_region.size != Vector2.ZERO
	shadow.region_rect = display_region
	shadow.scale = Vector2.ONE * scale_factor
	shadow.position = Vector2(0, 5)
	shadow.modulate = Color(0.08, 0.04, 0.02, 0.48)
	root.add_child(shadow)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = display_region.size != Vector2.ZERO
	sprite.region_rect = display_region
	sprite.scale = Vector2.ONE * scale_factor
	root.add_child(sprite)
	return root


func _cell_position(cell: Vector2i) -> Vector2:
	return BOARD_ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


func _on_game_event(kind: StringName, cell: Vector2i, player_index: int) -> void:
	if kind == &"coffee_thrown":
		coffee_throw_until[player_index] = elapsed + COFFEE_THROW_TIME
		_play_coffee_throw(cell, player_index)
	elif kind == &"coffee_hit":
		_spawn_impact_specks(cell, Color("8b5a2b"))
		_shake(3.0)
	elif kind == &"life_lost":
		# A rival being filtered out on your board is their business: no ghost of
		# your own hero, no shake, and above all none of the freeze that a death
		# puts on your own steps.
		if match_state != null and player_index != local_player:
			_spawn_impact_specks(cell, Color("ff8a5c"))
			audio.play(&"life_lost", 0.85)
			return
		snap_next_refresh = true
		player_hit_until = elapsed + 0.7
		_play_player_hit(cell)
		_shake(9.0)
		audio.play(&"life_lost")
		modulate = Color("ff9a8b")
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color.WHITE, 0.22)
	elif kind == &"enemy_squashed":
		_play_enemy_squash(cell)
		# A drop that catches a second pod is the payoff moment, so it hits harder
		# and sounds a step higher than the first.
		var points := state.last_squash_score
		var chained := points > GameStateClass.ENEMY_SQUASH_SCORE
		_shake(8.0 if chained else 5.0)
		audio.play(&"squash", 1.25 if chained else 1.0)
		_pop_score(cell, points, Color("ffc857") if chained else Color("ffe6a8"))
	elif kind == &"enemy_respawned":
		audio.play(&"enemy_respawn")
		_spawn_impact_specks(cell, Color("d8c7a0"))
	elif kind == &"coffee":
		var tier := 0
		if bean_nodes.has(cell):
			var bean: Node2D = bean_nodes[cell]
			tier = bean.get_meta(&"tier", 0)
			bean_nodes.erase(cell)
			_pop_bean(bean)
		audio.play(&"coffee", 1.0 + tier * 0.11)
		_pop_score(cell, LevelDataClass.bean_value(tier), Color("ffd27a"))
	elif kind == &"dug":
		_spawn_dust(cell)
		# Every step digs, so the scrape is detuned a little to stop it droning.
		audio.play(&"dig", randf_range(0.88, 1.14))
	elif kind == &"filter_landed":
		_spawn_dust(cell)
		_shake(4.0)
		audio.play(&"filter_land", randf_range(0.92, 1.08))
	elif kind == &"won":
		_play_level_clear()
		audio.play(&"level_clear")
	elif kind == &"close_call":
		_play_close_call(cell)
		audio.play(&"close_call")
	elif kind == &"life_gained":
		audio.play(&"life_gained")
		_pop_score(cell, 0, Color("9ef0a0"), "EXTRA LIFE")
	elif kind == &"level_reshuffled":
		# Everything teleports, so the next refresh must snap instead of tween.
		snap_next_refresh = true
		_shake(11.0)
		audio.play(&"reshuffle")
		_pop_score(cell, 0, Color("9ed6f0"), "GROUND SHIFTS")
	elif kind == &"game_over":
		audio.play(&"life_lost", 0.72)
		# A match settles itself through MatchState, and one player being knocked
		# out neither ends the race nor belongs in the single-player table.
		if match_state == null:
			_show_game_over(_record_run())


func _pop_score(cell: Vector2i, points: int, color: Color, text := "") -> void:
	var popup := _label(text if text != "" else "+%d" % points, 17, color)
	popup.position = _cell_position(cell) + Vector2(-24, -30)
	popup.z_index = 10
	actors.add_child(popup)
	var popup_tween := create_tween()
	popup_tween.set_parallel(true)
	popup_tween.tween_property(popup, "position", popup.position + Vector2(0, -26), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	popup_tween.tween_property(popup, "modulate", Color(1, 1, 1, 0), 0.7).set_delay(0.25)
	popup_tween.chain().tween_callback(popup.queue_free)


func _play_coffee_throw(cell: Vector2i, player_index: int) -> void:
	if match_state == null or player_index < 0 or player_index >= match_state.player_count():
		return
	var slot: PlayerSlot = match_state.players[player_index]
	var facing := slot.facing
	var landing := cell
	for step in range(MatchStateClass.THROW_RANGE):
		var next := landing + facing
		if not state.is_inside(next) or state.get_cell(next) == GameStateClass.Cell.SOIL:
			break
		landing = next
	var texture: Texture2D = load(HERO_COFFEE_THROW_TEXTURE)
	# The release frame contains a detached mug on transparent pixels. Cropping it
	# here keeps the generated cup art while avoiding another runtime sheet.
	var cup := _art_node(texture, 21.0, Rect2(785, 198, 105, 92))
	cup.position = _cell_position(cell) + Vector2(facing) * 14.0
	cup.z_index = 8
	actors.add_child(cup)
	var flight := create_tween()
	flight.set_parallel(true)
	flight.tween_property(cup, "position", _cell_position(landing), COFFEE_THROW_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flight.tween_property(cup, "rotation", TAU * 0.8, COFFEE_THROW_TIME)
	flight.tween_property(cup, "scale", Vector2(0.82, 0.82), COFFEE_THROW_TIME)
	flight.chain().tween_callback(cup.queue_free)


# Grazing an enemy is survivable, so it gets a warning flash instead of a death.
func _play_close_call(cell: Vector2i) -> void:
	_spawn_impact_specks(cell, Color("ffd27a"))
	if is_instance_valid(player_node):
		var graze_tween := create_tween()
		graze_tween.tween_property(player_node, "modulate", Color("ffd27a"), 0.08)
		graze_tween.tween_property(player_node, "modulate", _local_tint(), 0.2)


func _play_player_hit(cell: Vector2i) -> void:
	if is_instance_valid(player_node):
		player_node.visible = false
	var ghost := _hero_node()
	_set_hero_frame(ghost, _local_slot().facing)
	ghost.position = _cell_position(cell)
	ghost.modulate = Color("ffb09f")
	actors.add_child(ghost)
	_spawn_impact_specks(cell, Color("ff8a5c"))
	var hit_tween := create_tween()
	hit_tween.set_parallel(true)
	hit_tween.tween_property(ghost, "position", ghost.position + Vector2(0, -34), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(ghost, "rotation", PI * 1.25, 0.55).set_trans(Tween.TRANS_QUAD)
	hit_tween.tween_property(ghost, "scale", Vector2(0.45, 1.35), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hit_tween.tween_property(ghost, "modulate", Color(1, 0.35, 0.25, 0), 0.55).set_delay(0.12)
	hit_tween.chain().tween_callback(ghost.queue_free)
	var reveal_tween := create_tween()
	reveal_tween.tween_interval(0.7)
	reveal_tween.tween_callback(func() -> void:
		if is_instance_valid(player_node) and state.phase != GameStateClass.Phase.GAME_OVER and not _local_slot().is_out:
			player_node.visible = true
	)


func _play_enemy_squash(cell: Vector2i) -> void:
	var kind := &"teapod"
	for enemy_index in range(state.enemies.size()):
		if state.enemies[enemy_index] == cell:
			kind = _enemy_kind(enemy_index)
			break
	var ghost := _enemy_node(kind)
	if kind == &"teapod":
		_update_enemy_frame(ghost, 0)
	else:
		_set_enemy_frame(ghost, Vector2i(1, 1))
	ghost.position = _cell_position(cell)
	actors.add_child(ghost)
	_spawn_impact_specks(cell, Color("a77b36"))
	var squash_tween := create_tween()
	squash_tween.tween_property(ghost, "scale", Vector2(1.45, 0.18), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	squash_tween.parallel().tween_property(ghost, "position", ghost.position + Vector2(0, 12), 0.16)
	squash_tween.tween_property(ghost, "scale", Vector2(1.7, 0.06), 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	squash_tween.parallel().tween_property(ghost, "modulate", Color(0.55, 0.38, 0.15, 0), 0.24)
	squash_tween.tween_callback(ghost.queue_free)


func _spawn_impact_specks(cell: Vector2i, color: Color) -> void:
	for speck_index in range(6):
		var speck := Polygon2D.new()
		speck.polygon = PackedVector2Array([Vector2(-2, 0), Vector2(0, -2), Vector2(2, 0), Vector2(0, 2)])
		speck.color = color
		speck.position = _cell_position(cell)
		actors.add_child(speck)
		var angle := TAU * float(speck_index) / 6.0
		var target := speck.position + Vector2(cos(angle), sin(angle)) * 22.0
		var speck_tween := create_tween()
		speck_tween.set_parallel(true)
		speck_tween.tween_property(speck, "position", target, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		speck_tween.tween_property(speck, "rotation", PI, 0.38)
		speck_tween.tween_property(speck, "modulate", Color(1, 1, 1, 0), 0.38).set_delay(0.12)
		speck_tween.chain().tween_callback(speck.queue_free)


func _draw() -> void:
	if dragging:
		draw_circle(drag_origin, 36.0, Color(1, 1, 1, 0.12))
		draw_circle(drag_origin + virtual_tilt * 36.0, 12.0, Color("ffd27a"))
	var border := Rect2(BOARD_ORIGIN - Vector2.ONE, BOARD_SIZE + Vector2.ONE * 2.0)
	draw_rect(border, Color("5e3726"), false, 2.0)


# There is no art for the portal, so it is drawn: a translucent disc under two
# counter-turning rings. Only a match has one, hence hidden by default.
func _build_portal() -> Node2D:
	var node := Node2D.new()
	node.visible = false
	var disc := Polygon2D.new()
	disc.polygon = _ring_points(19.0)
	disc.color = Color(0.42, 0.78, 0.98, 0.22)
	node.add_child(disc)
	var outer := Line2D.new()
	outer.points = _ring_points(20.0)
	outer.closed = true
	outer.width = 3.0
	outer.default_color = Color("7fd8ff")
	node.add_child(outer)
	var inner := Line2D.new()
	inner.points = _ring_points(12.0)
	inner.closed = true
	inner.width = 2.0
	inner.default_color = Color("c9a8ff")
	node.add_child(inner)
	return node


func _ring_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in range(16):
		var angle := TAU * float(step) / 16.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _animate_portal() -> void:
	portal_node.visible = match_state != null and state != null
	if not portal_node.visible:
		return
	# Both boards grow from one seed, so the shown world always has the twin cell.
	portal_node.position = _cell_position(state.portal_cell())
	portal_node.get_child(0).scale = Vector2.ONE * (1.0 + sin(elapsed * 2.6) * 0.08)
	portal_node.get_child(1).rotation = elapsed * 0.9
	portal_node.get_child(2).rotation = -elapsed * 1.4


# Deliberately an arc rather than a bar: it reads at a glance how much of the
# throw is brewed without pulling the eye off the board.
func _build_charge_ring() -> Line2D:
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Color("c9a227")
	ring.visible = false
	ring.z_index = 4
	return ring


func _update_charge_ring() -> void:
	# Kept as a fallback node, but the quieter pouring pose is the default.
	charge_ring.visible = false


# A rival only exists on screen while standing on the board being drawn. The list
# is indexed by player, so the slot belonging to the local hero simply stays
# hidden.
func _update_rival_nodes() -> void:
	if match_state == null:
		for node in rival_nodes:
			if is_instance_valid(node):
				node.visible = false
		return
	while rival_nodes.size() < match_state.player_count():
		var hero := _hero_node()
		hero.modulate = _player_tint(rival_nodes.size())
		hero.visible = false
		actors.add_child(hero)
		rival_nodes.append(hero)
	for player_index in range(match_state.player_count()):
		var node: Node2D = rival_nodes[player_index]
		if not is_instance_valid(node):
			continue
		var rival: PlayerSlot = match_state.players[player_index]
		var here := not rival.is_out and match_state.world_of_player[player_index] == shown_world
		node.visible = here and player_index != local_player
		if not node.visible:
			continue
		if not _set_coffee_action_frame(node, player_index):
			_set_hero_frame(node, rival.facing)
		_move_actor(node, rival.cell, _player_step_time())


func _build_shield() -> Line2D:
	var ring := Line2D.new()
	var points := PackedVector2Array()
	for step in range(25):
		var angle := TAU * float(step) / 24.0
		points.append(Vector2(cos(angle), sin(angle)) * 30.0)
	ring.points = points
	ring.width = 3.0
	ring.default_color = Color("ffd27a")
	ring.visible = false
	return ring


# The respawn shield must be unmistakable: the hero blinks inside a pulsing ring
# that flickers faster as the protection runs out.
func _animate_invulnerability() -> void:
	if not is_instance_valid(player_node):
		return
	var invulnerable := state.is_invulnerable(_local_board_index()) and player_node.visible
	shield_node.visible = invulnerable
	if invulnerable:
		var left := state.invulnerability_left(_local_board_index())
		var urgency := 1.0 - clampf(left / GameStateClass.RESPAWN_INVULNERABILITY, 0.0, 1.0)
		var blink := sin(elapsed * (15.0 + urgency * 30.0))
		player_node.modulate = Color("ffe6a8") if blink > 0.0 else Color(_local_tint(), 0.2)
		shield_node.position = player_node.position
		var pulse := 1.0 + sin(elapsed * 7.0) * 0.09
		shield_node.scale = Vector2.ONE * pulse
		shield_node.modulate = Color(1, 1, 1, 0.35 + 0.45 * absf(blink))
	elif was_invulnerable:
		player_node.modulate = _local_tint()
	was_invulnerable = invulnerable


func _shake(amount: float) -> void:
	shake_strength = maxf(shake_strength, amount)


func _update_shake(delta: float) -> void:
	if shake_strength <= 0.01:
		board.position = Vector2.ZERO
		return
	shake_strength = maxf(shake_strength - delta * 24.0, 0.0)
	board.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_strength


# A filter that will drop on the next tick shivers, so the hazard is readable.
func _animate_filters() -> void:
	for filter_index in range(mini(filter_nodes.size(), state.falling_filter_states.size())):
		var filter_node := filter_nodes[filter_index]
		if state.falling_filter_states[filter_index]:
			filter_node.rotation = sin(elapsed * 44.0 + float(filter_index)) * 0.13
			filter_node.scale = Vector2(1.07, 0.93)
		else:
			filter_node.rotation = 0.0
			filter_node.scale = Vector2.ONE


func _pop_in(node: Node2D) -> void:
	node.scale = Vector2(0.15, 0.15)
	var pop_tween := create_tween()
	pop_tween.tween_property(node, "scale", Vector2.ONE, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pop_bean(bean: Node2D) -> void:
	var pop_tween := create_tween()
	pop_tween.set_parallel(true)
	pop_tween.tween_property(bean, "scale", Vector2(1.7, 1.7), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(bean, "position", bean.position + Vector2(0, -16), 0.28).set_trans(Tween.TRANS_QUAD)
	pop_tween.tween_property(bean, "modulate", Color(1, 1, 1, 0), 0.28).set_delay(0.06)
	pop_tween.chain().tween_callback(bean.queue_free)


func _spawn_dust(cell: Vector2i) -> void:
	for mote_index in range(4):
		var mote := Polygon2D.new()
		mote.polygon = PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)])
		mote.color = Color("6b4429")
		mote.position = _cell_position(cell)
		actors.add_child(mote)
		var angle := TAU * (float(mote_index) + randf()) / 4.0
		var target := mote.position + Vector2(cos(angle), sin(angle)) * randf_range(13.0, 25.0)
		var dust_tween := create_tween()
		dust_tween.set_parallel(true)
		dust_tween.tween_property(mote, "position", target, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		dust_tween.tween_property(mote, "scale", Vector2(0.2, 0.2), 0.36)
		dust_tween.tween_property(mote, "modulate", Color(1, 1, 1, 0), 0.36).set_delay(0.08)
		dust_tween.chain().tween_callback(mote.queue_free)


func _play_level_clear() -> void:
	_shake(6.0)
	for burst_index in range(14):
		var cell := Vector2i(randi_range(1, GameStateClass.WIDTH - 2), randi_range(1, GameStateClass.HEIGHT - 2))
		var delay := float(burst_index) * 0.06
		var burst_tween := create_tween()
		burst_tween.tween_interval(delay)
		burst_tween.tween_callback(_spawn_impact_specks.bind(cell, Color("ffd27a")))


# A client never simulates. It posts its intent and draws whatever the host sends
# back, which is what keeps the two screens telling the same story.
func _process_match(delta: float, direction: Vector2i, throw_pressed: bool) -> void:
	if not net.is_host():
		net.send_input(direction, throw_pressed)
		return

	if throw_pressed:
		match_state.throw_coffee(local_player)
	match_state.advance_time(delta)
	for world in match_state.worlds:
		world.tick_contacts()

	move_cooldown -= delta
	for player_index in range(remote_move_cooldown.size()):
		remote_move_cooldown[player_index] -= delta
	enemy_cooldown -= delta
	teapot_cooldown -= delta
	ultra_cooldown -= delta
	filter_cooldown -= delta

	if move_cooldown <= 0.0 and elapsed >= player_hit_until:
		if match_state.move_player(local_player, direction):
			move_cooldown += _player_step_time()
			var world_index: int = match_state.world_of_player[local_player]
			if world_index != shown_world:
				_switch_to_world(world_index)
		else:
			move_cooldown = 0.0

	# Every guest walks on the same clock as the host, just from stored intent.
	for player_index in range(match_state.player_count()):
		if player_index == local_player:
			continue
		if remote_throw[player_index]:
			remote_throw[player_index] = false
			match_state.throw_coffee(player_index)
		if remote_move_cooldown[player_index] <= 0.0:
			if match_state.move_player(player_index, remote_direction[player_index]):
				remote_move_cooldown[player_index] += _player_step_time()
			else:
				remote_move_cooldown[player_index] = 0.0

	# Both plantations keep running, so a raider cannot freeze the board they left.
	if enemy_cooldown <= 0.0:
		for world in match_state.worlds:
			world.tick_enemy(&"teapod")
		enemy_cooldown += _enemy_step_time()
	if teapot_cooldown <= 0.0:
		for world in match_state.worlds:
			world.tick_enemy(&"teapot")
		teapot_cooldown += _enemy_step_time_for_kind(&"teapot")
	if ultra_cooldown <= 0.0:
		for world in match_state.worlds:
			world.tick_enemy(&"ultra")
		ultra_cooldown += _enemy_step_time_for_kind(&"ultra")
	if filter_cooldown <= 0.0:
		for world in match_state.worlds:
			world.tick_filter()
		filter_cooldown += _filter_step_time()

	for world_index in range(match_state.worlds.size()):
		if match_state.worlds[world_index].phase == GameStateClass.Phase.WON:
			match_state.next_level(world_index)

	snapshot_countdown -= delta
	if snapshot_countdown <= 0.0:
		snapshot_countdown += SNAPSHOT_INTERVAL
		_send_snapshots()
