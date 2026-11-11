class_name BSPDungeonGenerator
extends RefCounted

const DungeonGraph = preload("res://core/dungeon_graph.gd")

## BSPDungeonGenerator: Prozedurale Dungeongenerierung mittels Binary Space Partitioning
## Erzeugt zusammenhängende Raum-Netzwerke mit Korridoren und garantiert
## über topologische Zuweisung die Lösbarkeit der Schlüssel-Schloss-Kette.

class BSPNode extends RefCounted:
	var rect: Rect2i
	var left: BSPNode = null
	var right: BSPNode = null
	var room_rect: Rect2i = Rect2i()
	var is_leaf: bool:
		get:
			return left == null and right == null

	func _init(p_rect: Rect2i):
		rect = p_rect

const MIN_NODE_SIZE = 16
const MIN_ROOM_SIZE = 8
const MAX_ROOM_PADDING = 2

static func generate(dungeon_width: int = 70, dungeon_height: int = 45, max_depth: int = 3, seed_val: int = 0) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	if seed_val != 0:
		rng.seed = seed_val
	else:
		rng.randomize()

	var root = BSPNode.new(Rect2i(0, 0, dungeon_width, dungeon_height))
	_split_node(root, 0, max_depth, rng)

	var leaves: Array[BSPNode] = []
	_collect_leaves(root, leaves)

	# 1. Erzeuge Räume in den Blattknoten
	var rooms_dict: Dictionary = {} # id -> DungeonRoom
	var leaf_rooms: Array[Rect2i] = []
	for i in range(leaves.size()):
		var leaf = leaves[i]
		var rw = rng.randi_range(MIN_ROOM_SIZE, maxi(MIN_ROOM_SIZE, leaf.rect.size.x - MAX_ROOM_PADDING * 2))
		var rh = rng.randi_range(MIN_ROOM_SIZE, maxi(MIN_ROOM_SIZE, leaf.rect.size.y - MAX_ROOM_PADDING * 2))
		var rx = leaf.rect.position.x + rng.randi_range(MAX_ROOM_PADDING, maxi(MAX_ROOM_PADDING, leaf.rect.size.x - rw - MAX_ROOM_PADDING))
		var ry = leaf.rect.position.y + rng.randi_range(MAX_ROOM_PADDING, maxi(MAX_ROOM_PADDING, leaf.rect.size.y - rh - MAX_ROOM_PADDING))
		leaf.room_rect = Rect2i(rx, ry, rw, rh)
		leaf_rooms.append(leaf.room_rect)

	# 2. Verbinde Räume hierarchisch über Korridore
	var corridors: Array[Array] = [] # Array of [Vector2i, Vector2i] (Start, End)
	_connect_nodes(root, corridors, rng)

	# 3. Baue den DungeonGraph auf
	var graph = DungeonGraph.new()
	for i in range(leaves.size()):
		var r_id = "Room_%d" % i
		var r_rect = leaves[i].room_rect
		var center = r_rect.position + r_rect.size / 2
		var room = DungeonGraph.DungeonRoom.new(r_id, DungeonGraph.RoomType.EMPTY, center)
		room.rect = r_rect
		graph.add_room(room)

	# Finde Raum-Nachbarschaften über Korridor-Endpunkte
	for corr in corridors:
		var p1: Vector2i = corr[0]
		var p2: Vector2i = corr[1]
		var r1_id = _find_closest_room(p1, graph)
		var r2_id = _find_closest_room(p2, graph)
		if not r1_id.is_empty() and not r2_id.is_empty() and r1_id != r2_id:
			if graph.get_door_between(r1_id, r2_id) == null:
				graph.add_door(r1_id, r2_id, DungeonGraph.DoorType.OPEN, "", true)

	# 4. Topologische Rollenzuweisung (Start, Key, Locked Door, Goal)
	_assign_topology_and_locks(graph, rng)

	return {
		"graph": graph,
		"corridors": corridors,
		"width": dungeon_width,
		"height": dungeon_height,
		"rooms": leaf_rooms
	}

static func _split_node(node: BSPNode, depth: int, max_depth: int, rng: RandomNumberGenerator) -> void:
	if depth >= max_depth:
		return

	var split_horizontally = rng.randf() > 0.5
	if node.rect.size.x > node.rect.size.y and float(node.rect.size.x) / float(node.rect.size.y) >= 1.25:
		split_horizontally = false
	elif node.rect.size.y > node.rect.size.x and float(node.rect.size.y) / float(node.rect.size.x) >= 1.25:
		split_horizontally = true

	var max_split = (node.rect.size.y if split_horizontally else node.rect.size.x) - MIN_NODE_SIZE
	if max_split <= MIN_NODE_SIZE:
		return # Zu klein zum Weiterteilen

	var split_pos = rng.randi_range(MIN_NODE_SIZE, max_split)

	if split_horizontally:
		node.left = BSPNode.new(Rect2i(node.rect.position.x, node.rect.position.y, node.rect.size.x, split_pos))
		node.right = BSPNode.new(Rect2i(node.rect.position.x, node.rect.position.y + split_pos, node.rect.size.x, node.rect.size.y - split_pos))
	else:
		node.left = BSPNode.new(Rect2i(node.rect.position.x, node.rect.position.y, split_pos, node.rect.size.y))
		node.right = BSPNode.new(Rect2i(node.rect.position.x + split_pos, node.rect.position.y, node.rect.size.x - split_pos, node.rect.size.y))

	_split_node(node.left, depth + 1, max_depth, rng)
	_split_node(node.right, depth + 1, max_depth, rng)

static func _collect_leaves(node: BSPNode, out_leaves: Array[BSPNode]) -> void:
	if node.is_leaf:
		out_leaves.append(node)
	else:
		if node.left: _collect_leaves(node.left, out_leaves)
		if node.right: _collect_leaves(node.right, out_leaves)

static func _connect_nodes(node: BSPNode, out_corridors: Array[Array], rng: RandomNumberGenerator) -> void:
	if node.is_leaf or node.left == null or node.right == null:
		return

	var c1 = _get_room_center_in_subtree(node.left, rng)
	var c2 = _get_room_center_in_subtree(node.right, rng)

	# L-förmiger Korridor
	if rng.randf() > 0.5:
		var mid = Vector2i(c2.x, c1.y)
		out_corridors.append([c1, mid])
		out_corridors.append([mid, c2])
	else:
		var mid = Vector2i(c1.x, c2.y)
		out_corridors.append([c1, mid])
		out_corridors.append([mid, c2])

	_connect_nodes(node.left, out_corridors, rng)
	_connect_nodes(node.right, out_corridors, rng)

static func _get_room_center_in_subtree(node: BSPNode, rng: RandomNumberGenerator) -> Vector2i:
	if node.is_leaf:
		return node.room_rect.position + node.room_rect.size / 2
	var target = node.left if (node.right == null or rng.randf() > 0.5) else node.right
	return _get_room_center_in_subtree(target, rng)

static func _find_closest_room(point: Vector2i, graph: DungeonGraph) -> String:
	var best_id = ""
	var best_dist = 999999.0
	for r: DungeonGraph.DungeonRoom in graph.rooms.values():
		var d = point.distance_to(r.grid_pos)
		if d < best_dist:
			best_dist = d
			best_id = r.id
	return best_id

static func _assign_topology_and_locks(graph: DungeonGraph, rng: RandomNumberGenerator) -> void:
	var r_keys = graph.rooms.keys()
	if r_keys.size() < 2:
		return

	# Startraum = Index 0, Zielraum = am weitesten entfernt im Graphen
	var start_id = r_keys[0]
	var distances = _compute_bfs_distances(start_id, graph)

	var goal_id = start_id
	var max_d = -1
	for id in distances:
		if distances[id] > max_d:
			max_d = distances[id]
			goal_id = id

	graph.start_room_id = start_id
	graph.goal_room_id = goal_id

	var start_room: DungeonGraph.DungeonRoom = graph.rooms[start_id]
	start_room.room_type = DungeonGraph.RoomType.START

	var goal_room: DungeonGraph.DungeonRoom = graph.rooms[goal_id]
	goal_room.room_type = DungeonGraph.RoomType.GOAL
	goal_room.has_goal = true

	# Finde den kürzesten Pfad von Start zu Goal
	var path = _find_path(start_id, goal_id, graph)

	# Platziere eine verschlossene Tür auf dem Pfad zum Ziel (z. B. vor dem letzten Raum)
	if path.size() >= 3:
		var lock_from = path[path.size() - 2]
		var lock_to = path[path.size() - 1]
		var d1 = graph.get_door_between(lock_from, lock_to)
		var d2 = graph.get_door_between(lock_to, lock_from)
		if d1: d1.door_type = DungeonGraph.DoorType.LOCKED
		if d2: d2.door_type = DungeonGraph.DoorType.LOCKED

		# Platziere den Schlüssel in einem Seitenraum, der VOR der verschlossenen Tür liegt
		var valid_key_rooms: Array[String] = []
		for id in distances:
			if id != start_id and id != goal_id and id != lock_to:
				# Raum liegt nicht hinter der verschlossenen Tür
				valid_key_rooms.append(id)

		if not valid_key_rooms.is_empty():
			var key_room_id = valid_key_rooms[rng.randi() % valid_key_rooms.size()]
			var key_room: DungeonGraph.DungeonRoom = graph.rooms[key_room_id]
			key_room.has_key = true
			key_room.room_type = DungeonGraph.RoomType.KEY
		else:
			# Fallback: Schlüssel im Startraum
			start_room.has_key = true
	else:
		# Kurzer Pfad: Schlüssel in Startraum oder Nebenraum
		if r_keys.size() > 2:
			var side_id = r_keys[1] if r_keys[1] != goal_id else r_keys[2]
			graph.rooms[side_id].has_key = true
			graph.rooms[side_id].room_type = DungeonGraph.RoomType.KEY

	# Verbleibende Räume mit Gegnern ausstatten
	for id in graph.rooms:
		var rm: DungeonGraph.DungeonRoom = graph.rooms[id]
		if rm.room_type == DungeonGraph.RoomType.EMPTY:
			rm.room_type = DungeonGraph.RoomType.ENEMY
			rm.enemies_count = rng.randi_range(1, 3)

static func _compute_bfs_distances(start_id: String, graph: DungeonGraph) -> Dictionary:
	var dists = {start_id: 0}
	var q = [start_id]
	while not q.is_empty():
		var cur = q.pop_front()
		for d in graph.get_doors_from(cur):
			if not dists.has(d.to_room):
				dists[d.to_room] = dists[cur] + 1
				q.append(d.to_room)
	return dists

static func _find_path(start_id: String, goal_id: String, graph: DungeonGraph) -> Array[String]:
	var prev = {}
	var q = [start_id]
	var visited = {start_id: true}

	while not q.is_empty():
		var cur = q.pop_front()
		if cur == goal_id:
			break
		for d in graph.get_doors_from(cur):
			if not visited.has(d.to_room):
				visited[d.to_room] = true
				prev[d.to_room] = cur
				q.append(d.to_room)

	var path: Array[String] = []
	var curr = goal_id
	while prev.has(curr):
		path.push_front(curr)
		curr = prev[curr]
	if not path.is_empty() or start_id == goal_id:
		path.push_front(start_id)
	return path
