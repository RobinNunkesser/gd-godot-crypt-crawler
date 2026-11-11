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
## Rendert Räume mit Wandöffnungen, Korridoren, Türen, Schlüsseln und Fog-of-War.

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
var rooms_container: Node2D = null
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
	# 1. Welt-Container
	world_container = Node2D.new()
	world_container.name = "WorldContainer"
	add_child(world_container)

	# 2. Räume-Container (wird ZUERST gerendert, also UNTER dem Spieler)
	rooms_container = Node2D.new()
	rooms_container.name = "RoomsContainer"
	world_container.add_child(rooms_container)

	# 3. Spieler instanziieren (über den Räumen)
	player = Player.new()
	player.name = "Player"
	player.z_index = 10
	world_container.add_child(player)

	# 4. Kamera an Spieler koppeln
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.zoom = Vector2(1.1, 1.1)
	player.add_child(camera)

	# 5. Fog of War
	fog_of_war = FogOfWar.new()
	fog_of_war.name = "FogOfWar"
	world_container.add_child(fog_of_war)

	# Signale des Spielers verknüpfen
	player.key_collected.connect(_on_player_key_collected)
	player.goal_reached.connect(_on_player_goal_reached)
	player.position_changed.connect(_on_player_position_changed)

	# 6. UI Layer
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	add_child(hud_layer)

	_setup_hud()

func _setup_hud() -> void:
	var top_panel = PanelContainer.new()
	top_panel.custom_minimum_size = Vector2(1240, 50)
	top_panel.position = Vector2(20, 15)
	hud_layer.add_child(top_panel)

	hud_label = Label.new()
	hud_label.text = "Crypt Crawler | [1] Zelda VGLC | [2] BSP Prozedural | [R] Seed neu | [M] Minimap | [F] Fackel | 🔑: 0"
	top_panel.add_child(hud_label)

	minimap_ui = MinimapOverlay.new()
	minimap_ui.custom_minimum_size = Vector2(300, 220)
	minimap_ui.size = Vector2(300, 220)
	minimap_ui.position = Vector2(950, 75)
	hud_layer.add_child(minimap_ui)

	# Victory Banner
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

	# Räume-Container vollständig leeren
	for child in rooms_container.get_children():
		rooms_container.remove_child(child)
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
	var room_w = 400.0
	var room_h = 280.0
	var room_spacing = 80.0
	var door_w = 64.0

	# 1. Ermittle für jeden Raum alle Türen und Richtungen
	var room_door_dirs: Dictionary = {} # room_id -> Array of Vector2i
	for r_id: String in graph.rooms.keys():
		room_door_dirs[r_id] = []
		var r: DungeonGraph.DungeonRoom = graph.rooms[r_id]
		for door in graph.get_doors_from(r_id):
			var target = graph.get_room(door.to_room)
			if target:
				var diff = target.grid_pos - r.grid_pos
				room_door_dirs[r_id].append(diff)

	# 2. Räume und Wände mit Durchgängen bauen
	for r_id: String in graph.rooms.keys():
		var r: DungeonGraph.DungeonRoom = graph.rooms[r_id]
		var origin = Vector2(r.grid_pos.x * (room_w + room_spacing), r.grid_pos.y * (room_h + room_spacing))
		var room_rect = Rect2(origin, Vector2(room_w, room_h))

		var room_node = Node2D.new()
		room_node.name = "Room_" + r_id
		rooms_container.add_child(room_node)

		var dirs: Array = room_door_dirs.get(r_id, [])
		var floor_visual = _create_room_visual(room_rect, r, dirs)
		room_node.add_child(floor_visual)

		# Wände mit Öffnungen
		_create_room_walls_with_doors(room_node, room_rect, dirs, door_w)

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

	# 3. Verbindende Korridore und Türen platzieren
	_build_doors_and_corridors_zelda(graph, room_w, room_h, room_spacing, door_w)

func _create_room_walls_with_doors(parent: Node2D, rect: Rect2, door_dirs: Array, door_w: float) -> void:
	var wall_thick = 12.0
	var body = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0

	var has_north = door_dirs.has(Vector2i(0, -1))
	var has_south = door_dirs.has(Vector2i(0, 1))
	var has_west = door_dirs.has(Vector2i(-1, 0))
	var has_east = door_dirs.has(Vector2i(1, 0))

	var cx = rect.position.x + rect.size.x * 0.5
	var cy = rect.position.y + rect.size.y * 0.5

	var add_box = func(seg: Rect2):
		var shape = CollisionShape2D.new()
		var rect_shape = RectangleShape2D.new()
		rect_shape.size = seg.size
		shape.shape = rect_shape
		shape.position = seg.position + seg.size * 0.5
		body.add_child(shape)

	# Nord-Wand
	if has_north:
		var half_w = (rect.size.x - door_w) * 0.5
		add_box.call(Rect2(rect.position.x, rect.position.y - wall_thick, half_w, wall_thick))
		add_box.call(Rect2(cx + door_w * 0.5, rect.position.y - wall_thick, half_w, wall_thick))
	else:
		add_box.call(Rect2(rect.position.x, rect.position.y - wall_thick, rect.size.x, wall_thick))

	# Süd-Wand
	if has_south:
		var half_w = (rect.size.x - door_w) * 0.5
		add_box.call(Rect2(rect.position.x, rect.position.y + rect.size.y, half_w, wall_thick))
		add_box.call(Rect2(cx + door_w * 0.5, rect.position.y + rect.size.y, half_w, wall_thick))
	else:
		add_box.call(Rect2(rect.position.x, rect.position.y + rect.size.y, rect.size.x, wall_thick))

	# West-Wand
	if has_west:
		var half_h = (rect.size.y - door_w) * 0.5
		add_box.call(Rect2(rect.position.x - wall_thick, rect.position.y, wall_thick, half_h))
		add_box.call(Rect2(rect.position.x - wall_thick, cy + door_w * 0.5, wall_thick, half_h))
	else:
		add_box.call(Rect2(rect.position.x - wall_thick, rect.position.y, wall_thick, rect.size.y))

	# Ost-Wand
	if has_east:
		var half_h = (rect.size.y - door_w) * 0.5
		add_box.call(Rect2(rect.position.x + rect.size.x, rect.position.y, wall_thick, half_h))
		add_box.call(Rect2(rect.position.x + rect.size.x, cy + door_w * 0.5, wall_thick, half_h))
	else:
		add_box.call(Rect2(rect.position.x + rect.size.x, rect.position.y, wall_thick, rect.size.y))

	parent.add_child(body)

func _build_doors_and_corridors_zelda(graph: DungeonGraph, room_w: float, room_h: float, room_spacing: float, door_w: float) -> void:
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

		var origin1 = Vector2(r1.grid_pos.x * (room_w + room_spacing), r1.grid_pos.y * (room_h + room_spacing))
		var origin2 = Vector2(r2.grid_pos.x * (room_w + room_spacing), r2.grid_pos.y * (room_h + room_spacing))
		var c1 = origin1 + Vector2(room_w * 0.5, room_h * 0.5)
		var c2 = origin2 + Vector2(room_w * 0.5, room_h * 0.5)
		var door_center = (c1 + c2) * 0.5

		# Korridor-Boden & Seitenwände im Spalt zwischen den Räumen bauen
		var corr_body = StaticBody2D.new()
		corr_body.collision_layer = 1
		corr_body.collision_mask = 0

		var diff = r2.grid_pos - r1.grid_pos
		var corr_visual = HallwayVisual.new()

		if diff.x == 0: # Vertikaler Korridor (Nord-Süd)
			var top_y = minf(origin1.y + room_h, origin2.y + room_h)
			var corr_rect = Rect2(c1.x - door_w * 0.5, top_y, door_w, room_spacing)
			corr_visual.r = corr_rect
			rooms_container.add_child(corr_visual)

			# Seitenwände des Flurs
			var left_wall = CollisionShape2D.new()
			var left_shape = RectangleShape2D.new()
			left_shape.size = Vector2(8, room_spacing)
			left_wall.shape = left_shape
			left_wall.position = Vector2(c1.x - door_w * 0.5 - 4, top_y + room_spacing * 0.5)
			corr_body.add_child(left_wall)

			var right_wall = CollisionShape2D.new()
			var right_shape = RectangleShape2D.new()
			right_shape.size = Vector2(8, room_spacing)
			right_wall.shape = right_shape
			right_wall.position = Vector2(c1.x + door_w * 0.5 + 4, top_y + room_spacing * 0.5)
			corr_body.add_child(right_wall)

		else: # Horizontaler Korridor (West-Ost)
			var left_x = minf(origin1.x + room_w, origin2.x + room_w)
			var corr_rect = Rect2(left_x, c1.y - door_w * 0.5, room_spacing, door_w)
			corr_visual.r = corr_rect
			rooms_container.add_child(corr_visual)

			# Seitenwände des horizontalen Flurs
			var top_wall = CollisionShape2D.new()
			var top_shape = RectangleShape2D.new()
			top_shape.size = Vector2(room_spacing, 8)
			top_wall.shape = top_shape
			top_wall.position = Vector2(left_x + room_spacing * 0.5, c1.y - door_w * 0.5 - 4)
			corr_body.add_child(top_wall)

			var bot_wall = CollisionShape2D.new()
			var bot_shape = RectangleShape2D.new()
			bot_shape.size = Vector2(room_spacing, 8)
			bot_wall.shape = bot_shape
			bot_wall.position = Vector2(left_x + room_spacing * 0.5, c1.y + door_w * 0.5 + 4)
			corr_body.add_child(bot_wall)

		rooms_container.add_child(corr_body)

		# Tür-Knoten platzieren
		var door_node = _create_door_node(door_center, door, diff.x == 0)
		rooms_container.add_child(door_node)
		door_nodes.append(door_node)

func _build_bsp_world(data: Dictionary) -> void:
	var tile_scale = 32.0
	var graph: DungeonGraph = data["graph"]
	var corridors: Array = data.get("corridors", [])

	for r: DungeonGraph.DungeonRoom in graph.rooms.values():
		var world_rect = Rect2(Vector2(r.rect.position) * tile_scale, Vector2(r.rect.size) * tile_scale)
		var room_node = Node2D.new()
		room_node.name = "Room_" + r.id
		rooms_container.add_child(room_node)

		var floor_visual = _create_room_visual(world_rect, r, [])
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

	for corr in corridors:
		var p1 = Vector2(corr[0]) * tile_scale
		var p2 = Vector2(corr[1]) * tile_scale
		var corr_visual = _create_corridor_visual(p1, p2, tile_scale)
		rooms_container.add_child(corr_visual)

	for door: DungeonGraph.DungeonDoor in graph.doors:
		if door.from_room > door.to_room:
			continue
		var r1 = graph.get_room(door.from_room)
		var r2 = graph.get_room(door.to_room)
		if r1 and r2:
			var c1 = Vector2(r1.rect.position + r1.rect.size / 2) * tile_scale
			var c2 = Vector2(r2.rect.position + r2.rect.size / 2) * tile_scale
			var door_pos = (c1 + c2) * 0.5
			var d_node = _create_door_node(door_pos, door, true)
			rooms_container.add_child(d_node)
			door_nodes.append(d_node)

# --- Visuelle Komponenten ---
class RoomVisual extends Node2D:
	var r_rect: Rect2
	var r_type: int
	var r_label: String
	var door_dirs: Array = []
	var door_w: float = 64.0

	func _draw() -> void:
		# Boden
		var bg_color = Color(0.12, 0.14, 0.18)
		if r_type == DungeonGraph.RoomType.BOSS:
			bg_color = Color(0.22, 0.1, 0.24)
		elif r_type == DungeonGraph.RoomType.GOAL:
			bg_color = Color(0.26, 0.24, 0.1)
		elif r_type == DungeonGraph.RoomType.START:
			bg_color = Color(0.1, 0.18, 0.14)

		draw_rect(r_rect, bg_color, true)

		# Subtile Kachel-Musterung
		var step = 40.0
		var num_x = int(r_rect.size.x / step)
		var num_y = int(r_rect.size.y / step)
		for ix in range(num_x):
			for iy in range(num_y):
				var cell = Rect2(r_rect.position.x + ix * step, r_rect.position.y + iy * step, step, step)
				draw_rect(cell, Color(1, 1, 1, 0.02), false, 1.0)

		# Raum-Umrandung (Wände)
		var wall_col = Color(0.3, 0.38, 0.5)
		var cx = r_rect.position.x + r_rect.size.x * 0.5
		var cy = r_rect.position.y + r_rect.size.y * 0.5

		# Nord-Kante
		if door_dirs.has(Vector2i(0, -1)):
			draw_line(r_rect.position, Vector2(cx - door_w * 0.5, r_rect.position.y), wall_col, 4.0)
			draw_line(Vector2(cx + door_w * 0.5, r_rect.position.y), Vector2(r_rect.position.x + r_rect.size.x, r_rect.position.y), wall_col, 4.0)
		else:
			draw_line(r_rect.position, Vector2(r_rect.position.x + r_rect.size.x, r_rect.position.y), wall_col, 4.0)

		# Süd-Kante
		var bot_y = r_rect.position.y + r_rect.size.y
		if door_dirs.has(Vector2i(0, 1)):
			draw_line(Vector2(r_rect.position.x, bot_y), Vector2(cx - door_w * 0.5, bot_y), wall_col, 4.0)
			draw_line(Vector2(cx + door_w * 0.5, bot_y), Vector2(r_rect.position.x + r_rect.size.x, bot_y), wall_col, 4.0)
		else:
			draw_line(Vector2(r_rect.position.x, bot_y), Vector2(r_rect.position.x + r_rect.size.x, bot_y), wall_col, 4.0)

		# West-Kante
		if door_dirs.has(Vector2i(-1, 0)):
			draw_line(r_rect.position, Vector2(r_rect.position.x, cy - door_w * 0.5), wall_col, 4.0)
			draw_line(Vector2(r_rect.position.x, cy + door_w * 0.5), Vector2(r_rect.position.x, bot_y), wall_col, 4.0)
		else:
			draw_line(r_rect.position, Vector2(r_rect.position.x, bot_y), wall_col, 4.0)

		# Ost-Kante
		var right_x = r_rect.position.x + r_rect.size.x
		if door_dirs.has(Vector2i(1, 0)):
			draw_line(Vector2(right_x, r_rect.position.y), Vector2(right_x, cy - door_w * 0.5), wall_col, 4.0)
			draw_line(Vector2(right_x, cy + door_w * 0.5), Vector2(right_x, bot_y), wall_col, 4.0)
		else:
			draw_line(Vector2(right_x, r_rect.position.y), Vector2(right_x, bot_y), wall_col, 4.0)

		# Raumlabel
		draw_string(ThemeDB.fallback_font, r_rect.position + Vector2(16, 28), r_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.95))

class CorridorVisual extends Node2D:
	var start_pos: Vector2
	var end_pos: Vector2
	var corr_w: float
	func _draw() -> void:
		draw_line(start_pos, Vector2(end_pos.x, start_pos.y), Color(0.16, 0.18, 0.24), corr_w)
		draw_line(Vector2(end_pos.x, start_pos.y), end_pos, Color(0.16, 0.18, 0.24), corr_w)

class HallwayVisual extends Node2D:
	var r: Rect2
	func _draw() -> void:
		draw_rect(r, Color(0.14, 0.16, 0.22), true)
		draw_line(Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.position.y + r.size.y), Color(0.3, 0.35, 0.45), 3.0)
		draw_line(Vector2(r.position.x + r.size.x, r.position.y), Vector2(r.position.x + r.size.x, r.position.y + r.size.y), Color(0.3, 0.35, 0.45), 3.0)

class DoorVisual extends Node2D:
	var is_locked: bool = false
	var door_type: int = 0
	var is_vertical: bool = true

	func _draw() -> void:
		var size_vec = Vector2(48, 20) if is_vertical else Vector2(20, 48)
		var r = Rect2(-size_vec * 0.5, size_vec)

		if is_locked:
			draw_rect(r, Color(0.9, 0.25, 0.2), true)
			draw_rect(r, Color.WHITE, false, 2.0)
			draw_string(ThemeDB.fallback_font, Vector2(-6, 5), "🔒", HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		elif door_type == DungeonGraph.DoorType.SHUTTER:
			draw_rect(r, Color(0.2, 0.8, 0.9, 0.7), true)
			draw_rect(r, Color.WHITE, false, 2.0)
		elif door_type == DungeonGraph.DoorType.BOMB:
			draw_rect(r, Color(0.8, 0.5, 0.2, 0.7), true)
			draw_rect(r, Color.WHITE, false, 2.0)
		else:
			# Offene Tür: Dezenter Durchgangs-Rahmen
			draw_rect(r, Color(0.2, 0.6, 0.3, 0.4), true)
			draw_rect(r, Color(0.4, 0.8, 0.5, 0.6), false, 1.5)

class KeyVisual extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 16.0, Color(1.0, 0.85, 0.1, 0.3))
		draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.85, 0.1))
		draw_circle(Vector2.ZERO, 9.0, Color(0.8, 0.65, 0.05))
		draw_string(ThemeDB.fallback_font, Vector2(-7, 6), "🔑", HORIZONTAL_ALIGNMENT_CENTER, -1, 16)

class GoalVisual extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 28.0, Color(1.0, 0.85, 0.1, 0.25))
		var pts = PackedVector2Array([
			Vector2(0, -22),
			Vector2(20, 14),
			Vector2(-20, 14)
		])
		draw_colored_polygon(pts, Color(1.0, 0.9, 0.2))
		draw_polyline(pts, Color.WHITE, 2.5, true)
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 1.0, 0.8))

func _get_room_world_center(room: DungeonGraph.DungeonRoom) -> Vector2:
	if current_mode == DungeonMode.VGLC_ZELDA:
		var room_w = 400.0
		var room_h = 280.0
		var room_spacing = 80.0
		var origin = Vector2(room.grid_pos.x * (room_w + room_spacing), room.grid_pos.y * (room_h + room_spacing))
		return origin + Vector2(room_w * 0.5, room_h * 0.5)
	else:
		return Vector2(room.rect.position + room.rect.size / 2) * 32.0

func _create_room_visual(rect: Rect2, room: DungeonGraph.DungeonRoom, dirs: Array) -> Node2D:
	var visual = RoomVisual.new()
	visual.r_rect = rect
	visual.r_type = room.room_type
	visual.r_label = room.id + (" [" + room.label_raw + "]" if not room.label_raw.is_empty() else "")
	visual.door_dirs = dirs
	return visual

func _create_corridor_visual(p1: Vector2, p2: Vector2, width: float) -> Node2D:
	var node = CorridorVisual.new()
	node.start_pos = p1
	node.end_pos = p2
	node.corr_w = width
	return node

func _create_rect_wall_colliders(parent: Node2D, rect: Rect2) -> void:
	var wall_thickness = 10.0
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

func _create_door_node(pos: Vector2, door: DungeonGraph.DungeonDoor, is_vert: bool) -> Node2D:
	var door_root = Node2D.new()
	door_root.global_position = pos

	# Interaktions-Trigger
	var area = Area2D.new()
	area.collision_layer = 2
	area.collision_mask = 1
	var trigger_shape = CollisionShape2D.new()
	var circ = CircleShape2D.new()
	circ.radius = 36.0
	trigger_shape.shape = circ
	area.add_child(trigger_shape)
	door_root.add_child(area)

	# Physischer Sperr-Kollisionskörper (falls abgeschlossen)
	var blocker = StaticBody2D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var blocker_col = CollisionShape2D.new()
	var blocker_shape = RectangleShape2D.new()
	blocker_shape.size = Vector2(48, 16) if is_vert else Vector2(16, 48)
	blocker_col.shape = blocker_shape
	blocker.add_child(blocker_col)
	door_root.add_child(blocker)

	var visual = DoorVisual.new()
	visual.is_locked = door.is_locked()
	visual.door_type = door.door_type
	visual.is_vertical = is_vert
	door_root.add_child(visual)

	if not door.is_locked():
		blocker_col.disabled = true

	area.body_entered.connect(func(body: Node2D):
		if body is Player:
			if door.is_locked():
				if body.use_key():
					door.is_opened = true
					visual.is_locked = false
					blocker_col.set_deferred("disabled", true)
					visual.queue_redraw()
					minimap_ui.queue_redraw()
					_update_hud()
	)

	return door_root

func _create_key_pickup(pos: Vector2, room_id: String) -> Area2D:
	var key_area = Area2D.new()
	key_area.global_position = pos
	key_area.collision_layer = 4
	key_area.collision_mask = 1

	var shape = CollisionShape2D.new()
	var circ = CircleShape2D.new()
	circ.radius = 20.0
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
	circ.radius = 28.0
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
