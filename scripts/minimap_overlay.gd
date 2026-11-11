class_name MinimapOverlay
extends Control

const DungeonGraph = preload("res://core/dungeon_graph.gd")

## MinimapOverlay: Didaktische Visualisierung des topologischen Dungeongraphen.
## Zeichnet Knoten (Räume), Kanten (Türen) und hebt den aktuellen Spielerstandort hervor.

var graph: DungeonGraph = null
@export var current_room_id: String = ""
@export var is_full_screen: bool = false
@export var node_radius: float = 14.0

var visited_rooms: Dictionary = {} # room_id -> bool
var solvability_report: Dictionary = {}

func set_graph(p_graph: DungeonGraph) -> void:
	graph = p_graph
	visited_rooms.clear()
	if graph and not graph.start_room_id.is_empty():
		visited_rooms[graph.start_room_id] = true
	if graph:
		solvability_report = graph.validate_solvability()
	queue_redraw()

func set_player_room(room_id: String) -> void:
	current_room_id = room_id
	visited_rooms[room_id] = true
	queue_redraw()

func toggle_mode() -> void:
	is_full_screen = not is_full_screen
	queue_redraw()

func _draw() -> void:
	if graph == null or graph.rooms.is_empty():
		return

	# Hintergrund-Panel
	var panel_rect = Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, Color(0.05, 0.07, 0.1, 0.85), true)
	draw_rect(panel_rect, Color(0.2, 0.4, 0.6, 0.7), false, 2.0)

	# Bounding Box der Raumkoordinaten berechnen
	var min_grid = Vector2i(9999, 9999)
	var max_grid = Vector2i(-9999, -9999)
	for r: DungeonGraph.DungeonRoom in graph.rooms.values():
		min_grid.x = mini(min_grid.x, r.grid_pos.x)
		min_grid.y = mini(min_grid.y, r.grid_pos.y)
		max_grid.x = maxi(max_grid.x, r.grid_pos.x)
		max_grid.y = maxi(max_grid.y, r.grid_pos.y)

	var span_x = maxi(1, max_grid.x - min_grid.x)
	var span_y = maxi(1, max_grid.y - min_grid.y)

	var pad = 40.0
	var avail_w = size.x - pad * 2.0
	var avail_h = size.y - pad * 2.0 - 40.0 # Platz für Header
	var scale_factor = minf(avail_w / float(span_x), avail_h / float(span_y))
	if scale_factor > 80.0:
		scale_factor = 80.0 # Nicht übertrieben groß

	var offset = Vector2(pad, pad + 30.0)
	var get_screen_pos = func(grid_pos: Vector2i) -> Vector2:
		var norm_x = float(grid_pos.x - min_grid.x)
		var norm_y = float(grid_pos.y - min_grid.y)
		return offset + Vector2(norm_x * scale_factor, norm_y * scale_factor)

	# 1. Kanten (Türen) zeichnen
	var drawn_edges: Dictionary = {}
	for door: DungeonGraph.DungeonDoor in graph.doors:
		var r1 = graph.get_room(door.from_room)
		var r2 = graph.get_room(door.to_room)
		if r1 == null or r2 == null:
			continue

		var edge_key = door.from_room + "_" + door.to_room if door.from_room < door.to_room else door.to_room + "_" + door.from_room
		if drawn_edges.has(edge_key):
			continue
		drawn_edges[edge_key] = true

		var p1 = get_screen_pos.call(r1.grid_pos)
		var p2 = get_screen_pos.call(r2.grid_pos)

		var edge_color = Color(0.4, 0.45, 0.55, 0.6)
		var edge_width = 2.0

		if door.door_type == DungeonGraph.DoorType.LOCKED:
			edge_color = Color(0.95, 0.3, 0.2, 0.9) if not door.is_opened else Color(0.3, 0.8, 0.4, 0.8)
			edge_width = 3.0
		elif door.door_type == DungeonGraph.DoorType.SHUTTER:
			edge_color = Color(0.2, 0.85, 0.95, 0.8)
			edge_width = 2.5
		elif door.door_type == DungeonGraph.DoorType.BOMB:
			edge_color = Color(0.8, 0.5, 0.2, 0.8)

		draw_line(p1, p2, edge_color, edge_width)

	# 2. Knoten (Räume) zeichnen
	for r: DungeonGraph.DungeonRoom in graph.rooms.values():
		var pos = get_screen_pos.call(r.grid_pos)
		var is_visited = visited_rooms.has(r.id)
		var is_current = (r.id == current_room_id)

		var fill_color = Color(0.2, 0.25, 0.35)
		var border_color = Color(0.5, 0.6, 0.7)

		match r.room_type:
			DungeonGraph.RoomType.START:
				fill_color = Color(0.15, 0.6, 0.25)
				border_color = Color(0.3, 0.9, 0.4)
			DungeonGraph.RoomType.KEY:
				fill_color = Color(0.85, 0.7, 0.15) if not r.key_collected else Color(0.4, 0.35, 0.2)
				border_color = Color(1.0, 0.9, 0.3)
			DungeonGraph.RoomType.ENEMY:
				fill_color = Color(0.65, 0.25, 0.25)
				border_color = Color(0.9, 0.4, 0.4)
			DungeonGraph.RoomType.BOSS:
				fill_color = Color(0.55, 0.15, 0.65)
				border_color = Color(0.8, 0.3, 0.9)
			DungeonGraph.RoomType.GOAL:
				fill_color = Color(1.0, 0.8, 0.0)
				border_color = Color(1.0, 1.0, 0.4)

		if not is_visited:
			fill_color = fill_color.darkened(0.5)

		draw_circle(pos, node_radius, fill_color)
		draw_arc(pos, node_radius, 0, TAU, 24, border_color, 2.0)

		# Markierung für aktuellen Spielerstandort
		if is_current:
			draw_arc(pos, node_radius + 4.0, 0, TAU, 24, Color.WHITE, 2.5)

		# Kleines Icon/Kürzel
		var label_str = ""
		match r.room_type:
			DungeonGraph.RoomType.START: label_str = "S"
			DungeonGraph.RoomType.KEY: label_str = "K" if not r.key_collected else "✓"
			DungeonGraph.RoomType.GOAL: label_str = "★"
			DungeonGraph.RoomType.BOSS: label_str = "B"
			DungeonGraph.RoomType.ENEMY: label_str = "E"

		if not label_str.is_empty():
			draw_string(ThemeDB.fallback_font, pos + Vector2(-4, 4), label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color.WHITE)

	# 3. Header & Lösbarkeits-Status
	var status_text = "Topologie: "
	var status_color = Color.GREEN
	if solvability_report.get("solvable", false):
		status_text += "LÖSBAR (DAG Gültig - Tiefe(Key) < Tiefe(Tür))"
		status_color = Color(0.3, 0.95, 0.4)
	else:
		status_text += "DEADLOCK! (Kausalitätsbruch im Graphen)"
		status_color = Color(1.0, 0.3, 0.3)

	draw_string(ThemeDB.fallback_font, Vector2(12, 20), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, status_color)
