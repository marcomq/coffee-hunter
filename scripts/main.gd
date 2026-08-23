extends Node2D

const GameStateClass = preload("res://scripts/game_state.gd")
const InputResolverClass = preload("res://scripts/input_resolver.gd")
const LevelDataClass = preload("res://scripts/level_data.gd")
const GameAudioClass = preload("res://scripts/audio.gd")
const SaveDataClass = preload("res://scripts/save_data.gd")
const TILE := 48
const BOARD_ORIGIN := Vector2(12, 6)
const BOARD_SIZE := Vector2(GameStateClass.WIDTH * TILE, GameStateClass.HEIGHT * TILE)
const PLAYER_STEP_TIME := GameStateClass.PLAYER_STEP_TIME
const ENEMY_STEP_TIME := GameStateClass.ENEMY_STEP_TIME
const FILTER_STEP_TIME := GameStateClass.FILTER_STEP_TIME
const HERO_TEXTURE := "res://assets/art/source/hero-walk-sheet-v1.png"
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

enum UiMode { TITLE, PLAYING, PAUSED, GAME_OVER }

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
	board.add_child(actors)
	shield_node = _build_shield()
	actors.add_child(shield_node)
	_build_overlay()
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
	status_label = _label("", 16, Color("d9efb3"))
	status_label.position = Vector2(850, 252)
	status_label.size = Vector2(102, 130)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

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


func _show_title() -> void:
	ui_mode = UiMode.TITLE
	overlay.visible = true
	overlay_title.text = "COFFEE HUNTER"
	var record := "NO RUN RECORDED YET"
	if high_score > 0:
		record = "BEST  %d      FURTHEST  LEVEL %d" % [high_score, best_level + 1]
	overlay_body.text = "Grounds for Adventure\n\n%s\n\nWASD or ARROWS to dig, or drag the mouse to tilt\nShove a coffee filter onto a tea-pod to squash it\nCatch several pods in one drop and the payout doubles\n\nP pause      R restart      M mute      ESC title\n\nPRESS SPACE TO START" % record


func _show_game_over(is_record: bool) -> void:
	ui_mode = UiMode.GAME_OVER
	overlay.visible = true
	overlay_title.text = "FILTERED OUT"
	var record := "SCORE  %d      BEST  %d" % [state.score, high_score]
	if is_record:
		record = "NEW BEST  %d" % state.score
	overlay_body.text = "%s\nReached level %d\n\nSPACE or R for a new run      ESC for the title" % [record, state.level_index + 1]


func _set_paused(paused: bool) -> void:
	ui_mode = UiMode.PAUSED if paused else UiMode.PLAYING
	overlay.visible = paused
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


func _record_run() -> bool:
	var is_record := SaveDataClass.record_run(state.score, state.level_index)
	high_score = maxi(high_score, state.score)
	best_level = maxi(best_level, state.level_index)
	return is_record


# True while a menu owns the frame, which is also what freezes the simulation.
func _handle_ui_input() -> bool:
	if ui_mode == UiMode.TITLE:
		if Input.is_action_just_pressed("confirm"):
			_begin_run()
		return true
	if ui_mode == UiMode.GAME_OVER:
		if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("restart"):
			_begin_run()
		elif Input.is_action_just_pressed("to_title"):
			_show_title()
		return true
	if ui_mode == UiMode.PAUSED:
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("confirm"):
			_set_paused(false)
		elif Input.is_action_just_pressed("restart"):
			_begin_run()
		elif Input.is_action_just_pressed("to_title"):
			_show_title()
		return true
	if Input.is_action_just_pressed("pause"):
		_set_paused(true)
		return true
	if Input.is_action_just_pressed("to_title"):
		_show_title()
		return true
	if Input.is_action_just_pressed("restart"):
		_begin_run()
		return true
	return false


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
	queue_redraw()


func _physics_process(delta: float) -> void:
	elapsed += delta
	if Input.is_action_just_pressed("mute"):
		_toggle_mute()
	if _handle_ui_input():
		queue_redraw()
		return

	var direction := resolver.direction_from_vector(resolver.combined_vector(virtual_tilt))
	if state.phase == GameStateClass.Phase.WON and direction != Vector2i.ZERO:
		_record_run()
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
	_update_hero_frame()
	_move_actor(player_node, state.player, _player_step_time())

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

	score_label.text = "SCORE  %d" % state.score
	lives_label.text = "LIVES  %d" % state.lives
	beans_label.text = "BEANS  %d" % state.beans.size()
	best_label.text = "BEST  %d" % maxi(high_score, state.score)
	if audio and audio.muted:
		best_label.text += "   MUTED"
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
			status_label.text = "%s\nSPEED %.1f\n\nWASD / ARROWS\nDrag mouse to tilt\n\nP pause  R restart" % [level_line, LevelDataClass.speed(state.level_index)]


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
	_set_hero_frame(player_node, state.player_facing)


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
	for sprite in hero.get_children():
		if sprite is Sprite2D:
			sprite.region_rect = region
			sprite.flip_h = facing == Vector2i.RIGHT


func _animate_player() -> void:
	if not is_instance_valid(player_node) or not player_node.visible:
		return
	var moving := _actor_is_moving(player_node)
	if moving:
		var walk_cycle := [1, 2, 3, 2]
		var progress := _actor_move_progress(player_node)
		var frame_index := mini(int(progress * walk_cycle.size()), walk_cycle.size() - 1)
		_set_hero_frame(player_node, state.player_facing, walk_cycle[frame_index])
		player_node.scale = Vector2.ONE
		player_node.rotation = 0.0
	else:
		_set_hero_frame(player_node, state.player_facing)
		var breath := sin(elapsed * 3.2) * 0.012
		player_node.scale = Vector2(1.0 - breath * 0.5, 1.0 + breath)
		player_node.rotation = 0.0


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


func _on_game_event(kind: StringName, cell: Vector2i) -> void:
	if kind == &"life_lost":
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


# Grazing an enemy is survivable, so it gets a warning flash instead of a death.
func _play_close_call(cell: Vector2i) -> void:
	_spawn_impact_specks(cell, Color("ffd27a"))
	if is_instance_valid(player_node):
		var graze_tween := create_tween()
		graze_tween.tween_property(player_node, "modulate", Color("ffd27a"), 0.08)
		graze_tween.tween_property(player_node, "modulate", Color.WHITE, 0.2)


func _play_player_hit(cell: Vector2i) -> void:
	if is_instance_valid(player_node):
		player_node.visible = false
	var ghost := _hero_node()
	_set_hero_frame(ghost, state.player_facing)
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
		if is_instance_valid(player_node) and state.phase != GameStateClass.Phase.GAME_OVER:
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
	var invulnerable := state.is_invulnerable() and player_node.visible
	shield_node.visible = invulnerable
	if invulnerable:
		var left := state.invulnerability_left()
		var urgency := 1.0 - clampf(left / GameStateClass.RESPAWN_INVULNERABILITY, 0.0, 1.0)
		var blink := sin(elapsed * (15.0 + urgency * 30.0))
		player_node.modulate = Color("ffe6a8") if blink > 0.0 else Color(1, 1, 1, 0.2)
		shield_node.position = player_node.position
		var pulse := 1.0 + sin(elapsed * 7.0) * 0.09
		shield_node.scale = Vector2.ONE * pulse
		shield_node.modulate = Color(1, 1, 1, 0.35 + 0.45 * absf(blink))
	elif was_invulnerable:
		player_node.modulate = Color.WHITE
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
