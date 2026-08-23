extends Node2D

const GameStateClass = preload("res://scripts/game_state.gd")
const InputResolverClass = preload("res://scripts/input_resolver.gd")
const TILE := 48
const BOARD_ORIGIN := Vector2(12, 6)
const BOARD_SIZE := Vector2(GameStateClass.WIDTH * TILE, GameStateClass.HEIGHT * TILE)
const PLAYER_STEP_TIME := 0.42
const ENEMY_STEP_TIME := 0.95
const FILTER_STEP_TIME := 0.68

var state: GameState
var resolver: InputResolver
var tile_layer: TileMapLayer
var actors := Node2D.new()
var bean_nodes: Dictionary = {}
var player_node: Node2D
var enemy_node: Node2D
var filter_nodes: Array[Node2D] = []
var score_label: Label
var lives_label: Label
var status_label: Label
var move_cooldown := 0.0
var enemy_cooldown := ENEMY_STEP_TIME
var filter_cooldown := FILTER_STEP_TIME
var virtual_tilt := Vector2.ZERO
var drag_origin := Vector2.ZERO
var dragging := false
var elapsed := 0.0
var snap_next_refresh := true


func _ready() -> void:
	state = GameStateClass.new()
	resolver = InputResolverClass.new()
	_build_background()
	_build_tiles()
	_build_hud()
	add_child(actors)
	state.changed.connect(_refresh)
	state.event_emitted.connect(_on_game_event)
	_refresh()
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
	var backdrop := Sprite2D.new()
	backdrop.texture = load("res://assets/art/source/level-tropical-background.png")
	backdrop.position = BOARD_ORIGIN + BOARD_SIZE * 0.5
	backdrop.scale = BOARD_SIZE / backdrop.texture.get_size()
	add_child(backdrop)

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
	add_child(tile_layer)


func _build_hud() -> void:
	var title := _label("COFFEE\nHUNTER", 24, Color("ffd27a"))
	title.position = Vector2(850, 18)
	add_child(title)
	score_label = _label("", 18, Color.WHITE)
	score_label.position = Vector2(850, 112)
	add_child(score_label)
	lives_label = _label("", 18, Color("ff8f70"))
	lives_label.position = Vector2(850, 146)
	add_child(lives_label)
	status_label = _label("", 16, Color("d9efb3"))
	status_label.position = Vector2(850, 200)
	status_label.size = Vector2(102, 150)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)

	var teapot := _art_node(load("res://assets/art/source/teapot.png"), 82.0)
	teapot.position = Vector2(900, 410)
	add_child(teapot)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _process(delta: float) -> void:
	elapsed += delta
	if Input.is_action_just_pressed("restart"):
		snap_next_refresh = true
		state.new_game()
		enemy_cooldown = ENEMY_STEP_TIME
		filter_cooldown = FILTER_STEP_TIME
		move_cooldown = 0.0
		return

	var direction := resolver.direction_from_vector(resolver.combined_vector(virtual_tilt))
	if state.phase == GameStateClass.Phase.READY:
		if direction != Vector2i.ZERO:
			state.start_game()
		else:
			queue_redraw()
			return

	move_cooldown -= delta
	enemy_cooldown -= delta
	filter_cooldown -= delta

	if move_cooldown <= 0.0:
		if state.move_player(direction):
			move_cooldown = PLAYER_STEP_TIME

	if enemy_cooldown <= 0.0:
		state.tick_enemy()
		enemy_cooldown += ENEMY_STEP_TIME
	if filter_cooldown <= 0.0:
		state.tick_filter()
		filter_cooldown += FILTER_STEP_TIME

	for cell in bean_nodes:
		var bean: Node2D = bean_nodes[cell]
		bean.position = _cell_position(cell) + Vector2(0, sin(elapsed * 4.0 + cell.x) * 2.0)
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
			var bean := _art_node(load("res://assets/art/source/coffee-beans.png"), 34.0)
			bean.position = _cell_position(cell)
			actors.add_child(bean)
			bean_nodes[cell] = bean

	if not is_instance_valid(player_node):
		player_node = _hero_node()
		actors.add_child(player_node)
	_update_hero_frame()
	_move_actor(player_node, state.player, PLAYER_STEP_TIME)

	if state.enemy_alive:
		if not is_instance_valid(enemy_node):
			enemy_node = _art_node(load("res://assets/art/source/tea-filter.png"), 44.0)
			actors.add_child(enemy_node)
		_move_actor(enemy_node, state.enemy, ENEMY_STEP_TIME * 0.82)
	elif is_instance_valid(enemy_node):
		enemy_node.queue_free()
		enemy_node = null

	while filter_nodes.size() < state.falling_filters.size():
		var filter_node := _art_node(load("res://assets/art/source/coffee-filter.png"), 44.0)
		actors.add_child(filter_node)
		filter_nodes.append(filter_node)
	for filter_index in range(state.falling_filters.size()):
		var filter_node := filter_nodes[filter_index]
		_move_actor(filter_node, state.falling_filters[filter_index], FILTER_STEP_TIME * 0.72)
		filter_node.rotation = 0.08 if state.falling_filter_states[filter_index] else 0.0
	snap_next_refresh = false

	score_label.text = "SCORE\n%d" % state.score
	lives_label.text = "LIVES  %d" % state.lives
	match state.phase:
		GameStateClass.Phase.READY:
			status_label.text = "PRESS A DIRECTION\nTO START\n\nWASD / ARROWS\nor drag to tilt"
		GameStateClass.Phase.WON:
			status_label.text = "ALL BEANS!\nA serious victory.\n\nPress R"
		GameStateClass.Phase.GAME_OVER:
			status_label.text = "FILTERED OUT.\n\nPress R"
		_:
			status_label.text = "WASD / ARROWS\n\nDrag mouse to tilt\n\nR to restart"


func _hero_node() -> Node2D:
	var texture: Texture2D = load("res://assets/art/source/hero-sheet.png")
	var frame_size := Vector2(texture.get_width() / 2.0, texture.get_height() / 2.0)
	return _art_node(texture, 52.0, Rect2(Vector2.ZERO, frame_size))


func _update_hero_frame() -> void:
	var texture: Texture2D = load("res://assets/art/source/hero-sheet.png")
	var frame_size := Vector2(texture.get_width() / 2.0, texture.get_height() / 2.0)
	var frame := Vector2i.ZERO
	if state.player_facing == Vector2i.UP:
		frame = Vector2i(1, 0)
	elif state.player_facing == Vector2i.LEFT:
		frame = Vector2i(0, 1)
	elif state.player_facing == Vector2i.RIGHT:
		frame = Vector2i(1, 1)
	var region := Rect2(Vector2(frame) * frame_size, frame_size)
	for sprite in player_node.get_children():
		if sprite is Sprite2D:
			sprite.region_rect = region


func _move_actor(actor: Node2D, cell: Vector2i, duration: float) -> void:
	var target := _cell_position(cell)
	if snap_next_refresh or actor.position == Vector2.ZERO:
		actor.position = target
		return
	if actor.position.is_equal_approx(target):
		return
	var tween := create_tween()
	tween.tween_property(actor, "position", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _art_node(texture: Texture2D, target_size: float, region := Rect2()) -> Node2D:
	var root := Node2D.new()
	var source_size := region.size if region.size != Vector2.ZERO else texture.get_size()
	var scale_factor := target_size / maxf(source_size.x, source_size.y)
	var shadow := Sprite2D.new()
	shadow.texture = texture
	shadow.region_enabled = region.size != Vector2.ZERO
	shadow.region_rect = region
	shadow.scale = Vector2.ONE * scale_factor
	shadow.position = Vector2(0, 5)
	shadow.modulate = Color(0.08, 0.04, 0.02, 0.48)
	root.add_child(shadow)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = region.size != Vector2.ZERO
	sprite.region_rect = region
	sprite.scale = Vector2.ONE * scale_factor
	root.add_child(sprite)
	return root


func _cell_position(cell: Vector2i) -> Vector2:
	return BOARD_ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


func _on_game_event(kind: StringName, _cell: Vector2i) -> void:
	if kind == &"life_lost":
		snap_next_refresh = true
		modulate = Color("ff9a8b")
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color.WHITE, 0.22)


func _draw() -> void:
	if dragging:
		draw_circle(drag_origin, 36.0, Color(1, 1, 1, 0.12))
		draw_circle(drag_origin + virtual_tilt * 36.0, 12.0, Color("ffd27a"))
	var border := Rect2(BOARD_ORIGIN - Vector2.ONE, BOARD_SIZE + Vector2.ONE * 2.0)
	draw_rect(border, Color("5e3726"), false, 2.0)
