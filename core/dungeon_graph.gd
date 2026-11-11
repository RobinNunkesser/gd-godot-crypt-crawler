class_name DungeonGraph
extends RefCounted

## DungeonGraph: Topologische Graphen-Repräsentation von Dungeons
## Formalisiert Räume als Knoten (V) und Türen/Verbindungen als Kanten (E).
## Bietet mathematische Validierung der Schlüssel-Schloss-Kausalität (DAG).

enum DoorType {
	OPEN,
	LOCKED,
	SHUTTER,
	BOMB
}

enum RoomType {
	START,
	KEY,
	ENEMY,
	BOSS,
	GOAL,
	EMPTY
}

class DungeonDoor extends RefCounted:
	var from_room: String
	var to_room: String
	var door_type: int = DoorType.OPEN
	var is_opened: bool = false
	var key_id: String = ""

	func _init(p_from: String = "", p_to: String = "", p_type: int = DoorType.OPEN, p_key: String = ""):
		from_room = p_from
		to_room = p_to
		door_type = p_type
		key_id = p_key
		is_opened = (door_type == DoorType.OPEN)

	func is_locked() -> bool:
		return door_type == DoorType.LOCKED and not is_opened

class DungeonRoom extends RefCounted:
	var id: String
	var room_type: int = RoomType.EMPTY
	var grid_pos: Vector2i = Vector2i.ZERO
	var rect: Rect2i = Rect2i(0, 0, 16, 11)
	var has_key: bool = false
	var key_collected: bool = false
	var has_goal: bool = false # Triforce / Exit
	var enemies_count: int = 0
	var label_raw: String = ""

	func _init(p_id: String = "", p_type: int = RoomType.EMPTY, p_pos: Vector2i = Vector2i.ZERO):
		id = p_id
		room_type = p_type
		grid_pos = p_pos

var rooms: Dictionary = {} # id -> DungeonRoom
var doors: Array[DungeonDoor] = []
var start_room_id: String = ""
var goal_room_id: String = ""

func clear() -> void:
	rooms.clear()
	doors.clear()
	start_room_id = ""
	goal_room_id = ""

func add_room(room: DungeonRoom) -> void:
	rooms[room.id] = room
	if room.room_type == RoomType.START and start_room_id.is_empty():
		start_room_id = room.id
	elif room.room_type == RoomType.GOAL and goal_room_id.is_empty():
		goal_room_id = room.id

func add_door(from_id: String, to_id: String, type: int = DoorType.OPEN, key_id: String = "", bidirectional: bool = true) -> DungeonDoor:
	var door = DungeonDoor.new(from_id, to_id, type, key_id)
	doors.append(door)
	if bidirectional:
		var back_door = DungeonDoor.new(to_id, from_id, type, key_id)
		doors.append(back_door)
	return door

func get_room(id: String) -> DungeonRoom:
	return rooms.get(id, null)

func get_doors_from(room_id: String) -> Array[DungeonDoor]:
	var result: Array[DungeonDoor] = []
	for d in doors:
		if d.from_room == room_id:
			result.append(d)
	return result

func get_door_between(from_id: String, to_id: String) -> DungeonDoor:
	for d in doors:
		if d.from_room == from_id and d.to_room == to_id:
			return d
	return null

## Mathematische Lösbarkeitsprüfung über simulierte Traversierung:
## Sammelt erreichbare Schlüssel und entsperrt schrittweise Türen.
## Verifiziert die topologische Regel: Tiefe(Schlüssel) < Tiefe(Tür).
func validate_solvability() -> Dictionary:
	var report = {
		"solvable": false,
		"start_room": start_room_id,
		"goal_room": goal_room_id,
		"keys_available": 0,
		"keys_needed_for_goal": 0,
		"visited_rooms": [],
		"doors_unlocked": 0,
		"deadlocks": [],
		"error_message": ""
	}

	if not rooms.has(start_room_id):
		report["error_message"] = "Startraum '%s' existiert nicht im Graphen." % start_room_id
		return report
	if not rooms.has(goal_room_id):
		report["error_message"] = "Zielraum '%s' existiert nicht im Graphen." % goal_room_id
		return report

	var visited: Dictionary = {}
	var current_keys: int = 0
	var opened_doors: Dictionary = {} # door hash/ref -> bool
	var pending_locked_doors: Array[DungeonDoor] = []
	var room_queue: Array[String] = [start_room_id]
	visited[start_room_id] = true

	# Zähle alle im Dungeon vorhandenen Schlüssel
	for r: DungeonRoom in rooms.values():
		if r.has_key:
			report["keys_available"] += 1

	var progress_made = true
	while progress_made:
		progress_made = false

		# 1. Erkunde alle aktuell erreichbaren Räume
		while not room_queue.is_empty():
			var r_id = room_queue.pop_front()
			var room: DungeonRoom = rooms[r_id]

			if room.has_key and not room.key_collected:
				current_keys += 1
				progress_made = true

			for door in get_doors_from(r_id):
				var target_id = door.to_room
				if not rooms.has(target_id):
					continue

				if door.door_type == DoorType.OPEN or door.door_type == DoorType.SHUTTER or door.door_type == DoorType.BOMB or opened_doors.has(door):
					if not visited.has(target_id):
						visited[target_id] = true
						room_queue.append(target_id)
						progress_made = true
				elif door.door_type == DoorType.LOCKED:
					if not pending_locked_doors.has(door):
						pending_locked_doors.append(door)

		# 2. Prüfe, ob gesammelte Schlüssel aufgeschobene Türen öffnen können
		var i = 0
		while i < pending_locked_doors.size():
			var door = pending_locked_doors[i]
			if current_keys > 0 and visited.has(door.from_room):
				current_keys -= 1
				opened_doors[door] = true
				report["doors_unlocked"] += 1
				pending_locked_doors.remove_at(i)
				progress_made = true

				# Öffne auch die Gegentür
				var back_door = get_door_between(door.to_room, door.from_room)
				if back_door:
					opened_doors[back_door] = true

				if not visited.has(door.to_room):
					visited[door.to_room] = true
					room_queue.append(door.to_room)
			else:
				i += 1

	report["visited_rooms"] = visited.keys()
	report["solvable"] = visited.has(goal_room_id)

	if not report["solvable"]:
		for d in pending_locked_doors:
			report["deadlocks"].append({
				"from": d.from_room,
				"to": d.to_room,
				"reason": "Tür verschlossen, aber kein erreichbarer Schlüssel vorhanden."
			})
		report["error_message"] = "Zielraum nicht erreichbar! Kausale Schlüssel-Schloss-Blockade."

	return report
