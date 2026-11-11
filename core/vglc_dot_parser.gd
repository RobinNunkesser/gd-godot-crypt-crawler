class_name VGLCDotParser
extends RefCounted

const DungeonGraph = preload("res://core/dungeon_graph.gd")

## VGLCDotParser: Liest Graph-Repräsentationen im DOT-Format (Summerville et al., 2016)
## Parst Knoten (Räume mit Eigenschaften s, k, e, b, t) und Kanten (Türen: open, locked, bomb, shutter).

static func parse_dot_string(dot_content: String) -> DungeonGraph:
	var graph = DungeonGraph.new()
	var lines = dot_content.split("\n")

	for raw_line in lines:
		var line = raw_line.strip_edges()
		if line.is_empty() or line.begins_with("//") or line.begins_with("#"):
			continue
		if line.begins_with("digraph") or line.begins_with("graph") or line == "{" or line == "}":
			continue

		# Entferne Semikolons am Ende
		if line.ends_with(";"):
			line = line.substr(0, line.length() - 1).strip_edges()

		# Kanten prüfen: "A -> B" oder "A -- B"
		if "->" in line or "--" in line:
			_parse_edge(line, graph)
		elif "[" in line and "]" in line:
			_parse_node(line, graph)
		elif not line.is_empty() and not "{" in line and not "}" in line:
			# Einfacher Knotenname ohne Attribute
			var node_id = line.strip_edges()
			if not graph.rooms.has(node_id):
				var room = DungeonGraph.DungeonRoom.new(node_id, DungeonGraph.RoomType.EMPTY)
				graph.add_room(room)

	# Falls kein expliziter Start- oder Zielraum deklariert wurde, Fallbacks setzen
	if graph.start_room_id.is_empty() and graph.rooms.size() > 0:
		var first_id = graph.rooms.keys()[0]
		graph.start_room_id = first_id
		graph.rooms[first_id].room_type = DungeonGraph.RoomType.START

	if graph.goal_room_id.is_empty() and graph.rooms.size() > 1:
		var last_id = graph.rooms.keys()[graph.rooms.size() - 1]
		graph.goal_room_id = last_id
		graph.rooms[last_id].room_type = DungeonGraph.RoomType.GOAL
		graph.rooms[last_id].has_goal = true

	return graph

static func _parse_node(line: String, graph: DungeonGraph) -> void:
	var bracket_open = line.find("[")
	var bracket_close = line.rfind("]")
	if bracket_open == -1 or bracket_close == -1:
		return

	var node_id = line.substr(0, bracket_open).strip_edges()
	var attr_string = line.substr(bracket_open + 1, bracket_close - bracket_open - 1)
	var attrs = _parse_attributes(attr_string)

	var label = attrs.get("label", "").to_lower()
	var room_type = DungeonGraph.RoomType.EMPTY
	var has_key = false
	var has_goal = false

	# VGLC Klassifikation:
	# 's' = Start, 'k' = Key, 'e' = Enemy, 'b' / 'B' = Boss, 't' = Triforce / Goal
	if "s" in label or "start" in label:
		room_type = DungeonGraph.RoomType.START
	elif "t" in label or "triforce" in label or "goal" in label:
		room_type = DungeonGraph.RoomType.GOAL
		has_goal = true
	elif "b" in label or "boss" in label:
		room_type = DungeonGraph.RoomType.BOSS
	elif "k" in label or "key" in label:
		room_type = DungeonGraph.RoomType.KEY
		has_key = true
	elif "e" in label or "enemy" in label:
		room_type = DungeonGraph.RoomType.ENEMY

	# Gitter-Koordinaten ermitteln
	var grid_pos = Vector2i.ZERO
	if attrs.has("pos"):
		var parts = attrs["pos"].split(",")
		if parts.size() >= 2:
			grid_pos = Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))
	else:
		# Versuche Koordinaten aus ID wie "Room_3_5" zu parsen
		var p_idx = node_id.find("_")
		if p_idx != -1:
			var rest = node_id.substr(p_idx + 1)
			var subparts = rest.split("_")
			if subparts.size() >= 2:
				grid_pos = Vector2i(int(subparts[0]), int(subparts[1]))

	var room = DungeonGraph.DungeonRoom.new(node_id, room_type, grid_pos)
	room.has_key = has_key
	room.has_goal = has_goal
	room.label_raw = label
	graph.add_room(room)

static func _parse_edge(line: String, graph: DungeonGraph) -> void:
	var sep = "->" if "->" in line else "--"
	var bracket_open = line.find("[")
	var attr_string = ""
	var link_part = line

	if bracket_open != -1:
		var bracket_close = line.rfind("]")
		if bracket_close != -1:
			attr_string = line.substr(bracket_open + 1, bracket_close - bracket_open - 1)
		link_part = line.substr(0, bracket_open).strip_edges()

	var nodes = link_part.split(sep)
	if nodes.size() < 2:
		return

	var from_id = nodes[0].strip_edges()
	var to_id = nodes[1].strip_edges()
	var attrs = _parse_attributes(attr_string)
	var label = attrs.get("label", "").to_lower()

	var door_type = DungeonGraph.DoorType.OPEN
	if "locked" in label or label == "k" or "key" in label:
		door_type = DungeonGraph.DoorType.LOCKED
	elif "bomb" in label or label == "b":
		door_type = DungeonGraph.DoorType.BOMB
	elif "shutter" in label or label == "s":
		door_type = DungeonGraph.DoorType.SHUTTER

	# Falls die Räume noch nicht existieren, automatisch als EMPTY anlegen
	if not graph.rooms.has(from_id):
		graph.add_room(DungeonGraph.DungeonRoom.new(from_id, DungeonGraph.RoomType.EMPTY))
	if not graph.rooms.has(to_id):
		graph.add_room(DungeonGraph.DungeonRoom.new(to_id, DungeonGraph.RoomType.EMPTY))

	graph.add_door(from_id, to_id, door_type, "small_key", true)

static func _parse_attributes(attr_string: String) -> Dictionary:
	var result = {}
	if attr_string.is_empty():
		return result

	var current_key = ""
	var current_val = ""
	var in_quotes = false
	var in_value = false

	var i = 0
	while i < attr_string.length():
		var c = attr_string[i]
		if c == '"':
			in_quotes = not in_quotes
		elif c == '=' and not in_quotes and not in_value:
			in_value = true
			i += 1
			continue
		elif (c == ',' or c == ';') and not in_quotes:
			if not current_key.is_empty():
				result[current_key.strip_edges()] = current_val.strip_edges().trim_prefix('"').trim_suffix('"')
			current_key = ""
			current_val = ""
			in_value = false
			i += 1
			continue

		if in_value:
			current_val += c
		else:
			current_key += c
		i += 1

	if not current_key.is_empty():
		result[current_key.strip_edges()] = current_val.strip_edges().trim_prefix('"').trim_suffix('"')

	return result

static func parse_file(path: String) -> DungeonGraph:
	if not FileAccess.file_exists(path):
		push_error("VGLCDotParser: Datei nicht gefunden: %s" % path)
		return null
	var fa = FileAccess.open(path, FileAccess.READ)
	var content = fa.get_as_text()
	fa.close()
	return parse_dot_string(content)
