class_name MainLevel
extends Node2D

const DungeonGraph = preload("res://core/dungeon_graph.gd")
const VGLCDotParser = preload("res://core/vglc_dot_parser.gd")
const BSPDungeonGenerator = preload("res://core/bsp_dungeon_generator.gd")
const Player = preload("res://scripts/player.gd")
const FogOfWar = preload("res://scripts/fog_of_war.gd")
const MinimapOverlay = preload("res://scripts/minimap_overlay.gd")

## MainLevel: Zentraler Game Controller für Crypt Crawler
## Schaltet zwischen VGLC Zelda DOT Leveln und prozeduralem BSP Dungeon um.
## Rendert Räume, Türen, Schlüssel, Nebel des Krieges und Minimap.

enum DungeonMode {
	VGLC_ZELDA,
	PROCEDURAL_BSP
}

@export var current_mode: DungeonMode = DungeonMode.VGLC_ZELDA
@export var zelda_dot_path: String = "res://levels/zelda_eagle.dot"

var current_graph: DungeonGraph = null
var current_seed: int = 42

# Node Referenzen
var world_container: Node2D = null
var player: Player = null
var camera: Camera2D = null
var fog_of_war: FogOfWar = null
var hud_layer: CanvasLayer = null
var minimap_ui: MinimapOverlay = null
var hud_label: Label = null
var win_banner: Panel = null

# Raum- und Tür-Objekte
var door_nodes: Array[Node2D] = []
var key_items: Array[Node2D] = []
var goal_item: Node2D = null

func _ready() -> void:
	_setup_scene_structure()
	load_dungeon(current_mode)

func _setup_scene_structure() -> void:
	# 1. Welt-Container (für alle 2D-Objekte)
	world_container = Node2D.new()
	world_container.name = "WorldContainer"
	add_child(world_container)

	# 2. Spieler instanziieren
	player = Player.new()
	player.name = "Player"
	world_container.add_child(player)

	# 3. Kamera an Spieler koppeln
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.zoom = Vector2(1.2, 1.2)
	player.add_child(camera)

	# 4. Fog of War
	fog_of_war = FogOfWar.new()
	fog_of_war.name = "FogOfWar"
	world_container.add_child(fog_of_war)

	# Signale des Spielers verknüpfen
	player.key_collected.connect(_on_player_key_collected)
	player.goal_reached.connect(_on_player_goal_reached)
	player.position_changed.connect(_on_player_position_changed)

	# 5. UI Layer
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	add_child(hud_layer)

	_setup_hud()

func _setup_hud() -> void:
	# Oberes Info-Panel
	var top_panel = PanelContainer.new()
	top_panel.custom_minimum_size = Vector2(1240, 50)
	top_panel.position = Vector2(20, 15)
	hud_layer.add_child(top_panel)

	hud_label = Label.new()
	hud_label.text = "Crypt Crawler | [1] Zelda VGLC | [2] BSP Prozedural | [R] Seed neu | [M] Minimap | [F] Fackel | 🔑: 0"
	top_panel.add_child(hud_label)

	# Minimap Overlay
	minimap_ui = MinimapOverlay.new()
	minimap_ui.custom_minimum_size = Vector2(300, 220)
	minimap_ui.position = Vector2(950, 75)
	hud_layer.add_child(minimap_ui)

	# Victory Banner (initial versteckt)
	win_banner = Panel.new()
	win_banner.custom_minimum_size = Vector2(500, 160)
	win_banner.position = Vector2(390, 260)
	win_banner.visible = false

	var win_vbox = VBoxContainer.new()
	win_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 15)
	win_banner.add_child(win_vbox)

	var win_title = Label.new()
	win_title.text = "★ TRIFORCE GEFUNDEN! ★"
	win_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_title.add_theme_font_size_override("font_size", 24)
	win_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	win_vbox.add_child(win_title)

	var win_sub = Label.new()
	win_sub.text = "Dungeon topologisch erfolgreich gemeistert!\nDrücke [1] oder [2] für einen neuen Lauf."
	win_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_vbox.add_child(win_sub)

	hud_layer.add_child(win_banner)

func load_dungeon(mode: DungeonMode) -> void:
	current_mode = mode
	win_banner.visible = false
	player.has_won = false
	player.keys_count = 0

	# Bisherige Welt-Objekte bereinigen (außer Spieler und Fog)
	for child in world_container.get_children():
		if child != player and child != fog_of_war:
			child.queue_free()

	door_nodes.clear()
	key_items.clear()
	goal_item = null

	var dungeon_data: Dictionary = {}

	if mode == DungeonMode.VGLC_ZELDA:
		current_graph = VGLCDotParser.parse_file(zelda_dot_path)
		if current_graph == null:
			push_error("Fehler beim Laden von Zelda DOT")
			return
		_build_zelda_world(current_graph)
	else:
		current_seed = randi()
		dungeon_data = BSPDungeonGenerator.generate(70, 45, 3, current_seed)
		current_graph = dungeon_data["graph"]
		_build_bsp_world(dungeon_data)

	# Minimap initialisieren
	minimap_ui.set_graph(current_graph)
	minimap_ui.set_player_room(current_graph.start_room_id)

	# Spieler zum Startraum teleportieren
	var start_room = current_graph.get_room(current_graph.start_room_id)
	if start_room:
		var start_world_pos = _get_room_world_center(start_room)
		player.global_position = start_world_pos
		fog_of_war.follow_target(start_world_pos)

	_update_hud()

func _build_zelda_world(graph: DungeonGraph) -> void:
	var room_w = 340.0
	var room_h = 240.0
	var room_spacing = 40.0

	for r_id: String in graph.rooms.keys():
		var r: DungeonGraph.DungeonRoom = graph.rooms[r_id]
		var room_origin = Vector2(r.grid_pos.x * (room_w + room_spacing), r.grid_pos.y * (room_h + room_spacing))
		var room_rect = Rect2(room_origin, Vector2(room_w, room_h))

		# Raum-Visualisierung
		var room_node = Node2D.new()
		room_node.name = "Room_" + r_id
		world_container.add_child(room_node)

		# Boden & Wände zeichnen
		var floor_visual = _create_room_visual(room_rect, r)
		room_node.add_child(floor_visual)

		# Raum-Wände kollidierbar machen (mit Durchgängen)
		_create_room_wall_colliders(room_node, room_rect, r, graph)

		# Schlüssel platzieren
		if r.has_key:
			var key_node = _create_key_pickup(room_rect.get_center(), r_id)
			room_node.add_child(key_node)
			key_items.append(key_node)

		# Triforce Ziel platzieren
		if r.has_goal:
			var goal = _create_goal_pickup(room_rect.get_center())
			room_node.add_child(goal)
			goal_item = goal

	# Türen zwischen Räumen platzieren
	_build_doors_from_graph(graph, room_w, room_h, room_spacing)

func _build_bsp_world(data: Dictionary) -> void:
	var tile_scale = 32.0
	var graph: DungeonGraph = data["graph"]
	var corridors: Array = data.get("corridors", [])

	# 1. Räume bauen
	for r: DungeonGraph.DungeonRoom in graph.rooms.values():
		var world_rect = Rect2(Vector2(r.rect.position) * tile_scale, Vector2(r.rect.size) * tile_scale)
		var room_node = Node2D.new()
		room_node.name = "Room_" + r.id
		world_container.add_child(room_node)

		var floor_visual = _create_room_visual(world_rect, r)
		room_node.add_child(floor_visual)
		_create_rect_wall_colliders(room_node, world_rect)

		if r.has_key:
			var key_node = _create_key_pickup(world_rect.get_center(), r.id)
			room_node.add_child(key_node)
			key_items.append(key_node)

		if r.has_goal:
			var goal = _create_goal_pickup(world_rect.get_center())
			room_node.add_child(goal)
			goal_item = goal

	# 2. Korridore als Böden zeichnen
	for corr in corridors:
		var p1 = Vector2(corr[0]) * tile_scale
		var p2 = Vector2(corr[1]) * tile_scale
		var corr_visual = _create_corridor_visual(p1, p2, tile_scale)
		world_container.add_child(corr_visual)

	# 3. Türen für Kanten im Graphen platzieren
	for door: DungeonGraph.DungeonDoor in graph.doors:
		if door.from_room > door.to_room:
			continue # Nicht doppelt erzeugen
		var r1 = graph.get_room(door.from_room)
		var r2 = graph.get_room(door.to_room)
		if r1 and r2:
			var c1 = Vector2(r1.rect.position + r1.rect.size / 2) * tile_scale
			var c2 = Vector2(r2.rect.position + r2.rect.size / 2) * tile_scale
			var door_pos = (c1 + c2) * 0.5
			var d_node = _create_door_node(door_pos, door)
			world_container.add_child(d_node)
			door_nodes.append(d_node)

# --- Spezifische Visualisierungs-Klassen für den Szenengraph ---
class RoomVisual extends Node2D:
	var r_rect: Rect2
	var r_type: int
	var r_label: String
	func _draw() -> void:
		var bg_color = Color(0.12, 0.14, 0.18)
		if r_type == DungeonGraph.RoomType.BOSS:
			bg_color = Color(0.2, 0.1, 0.22)
		elif r_type == DungeonGraph.RoomType.GOAL:
			bg_color = Color(0.25, 0.22, 0.1)
		draw_rect(r_rect, bg_color, true)
		draw_rect(r_rect, Color(0.25, 0.3, 0.4), false, 4.0)
		draw_string(ThemeDB.fallback_font, r_rect.position + Vector2(12, 24), r_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.7, 0.8))

class CorridorVisual extends Node2D:
	var start_pos: Vector2
	var end_pos: Vector2
	var corr_w: float
	func _draw() -> void:
		draw_line(start_pos, Vector2(end_pos.x, start_pos.y), Color(0.16, 0.18, 0.24), corr_w)
		draw_line(Vector2(end_pos.x, start_pos.y), end_pos, Color(0.16, 0.18, 0.24), corr_w)

class DoorVisual extends Node2D:
	var is_locked: bool = false
	var door_type: int = 0
	func _draw() -> void:
		var col = Color(0.4, 0.45, 0.55)
		if is_locked:
			col = Color(0.9, 0.25, 0.2)
		elif door_type == DungeonGraph.DoorType.SHUTTER:
			col = Color(0.2, 0.8, 0.9)
		elif door_type == DungeonGraph.DoorType.BOMB:
			col = Color(0.8, 0.5, 0.2)
		draw_rect(Rect2(-16, -16, 32, 32), col, true)
		draw_rect(Rect2(-16, -16, 32, 32), Color.WHITE, false, 2.0)
		if is_locked:
			draw_string(ThemeDB.fallback_font, Vector2(-6, 5), "🔒", HORIZONTAL_ALIGNMENT_CENTER, -1, 14)

class KeyVisual extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 10.0, Color(1.0, 0.85, 0.1))
		draw_circle(Vector2.ZERO, 7.0, Color(0.8, 0.65, 0.05))
		draw_string(ThemeDB.fallback_font, Vector2(-6, 5), "🔑", HORIZONTAL_ALIGNMENT_CENTER, -1, 14)

class GoalVisual extends Node2D:
	func _draw() -> void:
		var pts = PackedVector2Array([
			Vector2(0, -18),
			Vector2(16, 12),
			Vector2(-16, 12)
		])
		draw_colored_polygon(pts, Color(1.0, 0.9, 0.2))
		draw_polyline(pts, Color.WHITE, 2.0, true)
		draw_circle(Vector2.ZERO, 5.0, Color(1.0, 1.0, 0.6))

func _get_room_world_center(room: DungeonGraph.DungeonRoom) -> Vector2:
	if current_mode == DungeonMode.VGLC_ZELDA:
		var room_w = 340.0
		var room_h = 240.0
		var room_spacing = 40.0
		var origin = Vector2(room.grid_pos.x * (room_w + room_spacing), room.grid_pos.y * (room_h + room_spacing))
		return origin + Vector2(room_w * 0.5, room_h * 0.5)
	else:
		return Vector2(room.rect.position + room.rect.size / 2) * 32.0

func _create_room_visual(rect: Rect2, room: DungeonGraph.DungeonRoom) -> Node2D:
	var visual = RoomVisual.new()
	visual.r_rect = rect
	visual.r_type = room.room_type
	visual.r_label = room.id + (" [" + room.label_raw + "]" if not room.label_raw.is_empty() else "")
	return visual

func _create_corridor_visual(p1: Vector2, p2: Vector2, width: float) -> Node2D:
	var node = CorridorVisual.new()
	node.start_pos = p1
	node.end_pos = p2
	node.corr_w = width
	return node

func _create_room_wall_colliders(parent: Node2D, rect: Rect2, _room: DungeonGraph.DungeonRoom, _graph: DungeonGraph) -> void:
	_create_rect_wall_colliders(parent, rect)

func _create_rect_wall_colliders(parent: Node2D, rect: Rect2) -> void:
	var wall_thickness = 8.0
	var body = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0

	var segments = [
		Rect2(rect.position.x, rect.position.y - wall_thickness, rect.size.x, wall_thickness),
		Rect2(rect.position.x, rect.position.y + rect.size.y, rect.size.x, wall_thickness),
		Rect2(rect.position.x - wall_thickness, rect.position.y, wall_thickness, rect.size.y),
		Rect2(rect.position.x + rect.size.x, rect.position.y, wall_thickness, rect.size.y)
	]

	for seg in segments:
		var shape = CollisionShape2D.new()
		var rect_shape = RectangleShape2D.new()
		rect_shape.size = seg.size
		shape.shape = rect_shape
		shape.position = seg.position + seg.size * 0.5
		body.add_child(shape)

	parent.add_child(body)

func _build_doors_from_graph(graph: DungeonGraph, room_w: float, room_h: float, room_spacing: float) -> void:
	var handled_pairs: Dictionary = {}

	for door: DungeonGraph.DungeonDoor in graph.doors:
		var pair_key = door.from_room + "__" + door.to_room if door.from_room < door.to_room else door.to_room + "__" + door.from_room
		if handled_pairs.has(pair_key):
			continue
		handled_pairs[pair_key] = true

		var r1 = graph.get_room(door.from_room)
		var r2 = graph.get_room(door.to_room)
		if r1 == null or r2 == null:
			continue

		var c1 = Vector2(r1.grid_pos.x * (room_w + room_spacing) + room_w * 0.5, r1.grid_pos.y * (room_h + room_spacing) + room_h * 0.5)
		var c2 = Vector2(r2.grid_pos.x * (room_w + room_spacing) + room_w * 0.5, r2.grid_pos.y * (room_h + room_spacing) + room_h * 0.5)
		var door_center = (c1 + c2) * 0.5

		var door_node = _create_door_node(door_center, door)
		world_container.add_child(door_node)
		door_nodes.append(door_node)

func _create_door_node(pos: Vector2, door: DungeonGraph.DungeonDoor) -> Node2D:
	var door_node = Area2D.new()
	door_node.global_position = pos
	door_node.collision_layer = 2
	door_node.collision_mask = 1

	var shape = CollisionShape2D.new()
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = Vector2(36, 36)
	shape.shape = rect_shape
	door_node.add_child(shape)

	var visual = DoorVisual.new()
	visual.is_locked = door.is_locked()
	visual.door_type = door.door_type
	door_node.add_child(visual)

	door_node.body_entered.connect(func(body: Node2D):
		if body is Player:
			if door.is_locked():
				if body.use_key():
					door.is_opened = true
					visual.is_locked = false
					visual.queue_redraw()
					minimap_ui.queue_redraw()
					_update_hud()
	)

	return door_node

func _create_key_pickup(pos: Vector2, room_id: String) -> Area2D:
	var key_area = Area2D.new()
	key_area.global_position = pos
	key_area.collision_layer = 4
	key_area.collision_mask = 1

	var shape = CollisionShape2D.new()
	var circ = CircleShape2D.new()
	circ.radius = 16.0
	shape.shape = circ
	key_area.add_child(shape)

	var visual = KeyVisual.new()
	key_area.add_child(visual)

	key_area.body_entered.connect(func(body: Node2D):
		if body is Player:
			body.add_key(1)
			var r = current_graph.get_room(room_id)
			if r:
				r.key_collected = true
			minimap_ui.queue_redraw()
			key_area.queue_free()
	)

	return key_area

func _create_goal_pickup(pos: Vector2) -> Area2D:
	var goal_area = Area2D.new()
	goal_area.global_position = pos
	goal_area.collision_layer = 4
	goal_area.collision_mask = 1

	var shape = CollisionShape2D.new()
	var circ = CircleShape2D.new()
	circ.radius = 20.0
	shape.shape = circ
	goal_area.add_child(shape)

	var visual = GoalVisual.new()
	goal_area.add_child(visual)

	goal_area.body_entered.connect(func(body: Node2D):
		if body is Player:
			body.trigger_goal()
	)

	return goal_area

func _on_player_position_changed(pos: Vector2) -> void:
	fog_of_war.follow_target(pos)
	_update_current_room_from_player(pos)

func _update_current_room_from_player(pos: Vector2) -> void:
	if current_graph == null:
		return

	# Finde Raum, in dem sich der Spieler befindet
	var closest_room: DungeonGraph.DungeonRoom = null
	var min_dist = 999999.0

	for r: DungeonGraph.DungeonRoom in current_graph.rooms.values():
		var center = _get_room_world_center(r)
		var d = pos.distance_to(center)
		if d < min_dist:
			min_dist = d
			closest_room = r

	if closest_room and closest_room.id != minimap_ui.current_room_id:
		minimap_ui.set_player_room(closest_room.id)

func _on_player_key_collected(_keys: int) -> void:
	_update_hud()

func _on_player_goal_reached() -> void:
	win_banner.visible = true

func _update_hud() -> void:
	var mode_name = "Zelda VGLC Level 1 (The Eagle)" if current_mode == DungeonMode.VGLC_ZELDA else "BSP Prozedural (Seed: %d)" % current_seed
	var solv_text = "Gültig (DAG)" if (current_graph and current_graph.validate_solvability()["solvable"]) else "DEADLOCK"
	hud_label.text = "Crypt Crawler | Modus: %s | Lösbarkeit: %s | 🔑: %d | [1/2]: Modus | [R]: Seed | [M]: Minimap | [F]: Fackel" % [
		mode_name, solv_text, player.keys_count if player else 0
	]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				load_dungeon(DungeonMode.VGLC_ZELDA)
			KEY_2:
				load_dungeon(DungeonMode.PROCEDURAL_BSP)
			KEY_R:
				if current_mode == DungeonMode.PROCEDURAL_BSP:
					load_dungeon(DungeonMode.PROCEDURAL_BSP)
			KEY_M:
				minimap_ui.visible = not minimap_ui.visible
			KEY_F:
				fog_of_war.toggle_fog()
