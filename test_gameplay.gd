extends SceneTree

const DungeonGraph = preload("res://core/dungeon_graph.gd")
const VGLCDotParser = preload("res://core/vglc_dot_parser.gd")
const BSPDungeonGenerator = preload("res://core/bsp_dungeon_generator.gd")
const Player = preload("res://scripts/player.gd")

## Headless Testsuite für Crypt Crawler
## Überprüft VGLC-Parsing, BSP-Generierung, Kausalitätsprüfung (DAG) und Spielerlogik.

func _init() -> void:
	print("==================================================")
	print("🧪 STARTE TESTS: Crypt Crawler (VGLC & BSP Graph)")
	print("==================================================")

	var failed = false

	if not test_vglc_parser():
		print("❌ TEST 1 FEHLGESCHLAGEN: VGLC DOT Parser")
		failed = true
	else:
		print("✅ TEST 1 BESTANDEN: VGLC DOT Parser")

	if not test_zelda_eagle_solvability():
		print("❌ TEST 2 FEHLGESCHLAGEN: Zelda Eagle Lösbarkeitsprüfung")
		failed = true
	else:
		print("✅ TEST 2 BESTANDEN: Zelda Eagle Lösbarkeitsprüfung")

	if not test_deadlock_detection():
		print("❌ TEST 3 FEHLGESCHLAGEN: Deadlock-Erkennung (Kausalitätsbruch)")
		failed = true
	else:
		print("✅ TEST 3 BESTANDEN: Deadlock-Erkennung (Kausalitätsbruch)")

	if not test_bsp_generator():
		print("❌ TEST 4 FEHLGESCHLAGEN: BSP Dungeongenerator & Topologie")
		failed = true
	else:
		print("✅ TEST 4 BESTANDEN: BSP Dungeongenerator & Topologie")

	if not test_player_and_inventory():
		print("❌ TEST 5 FEHLGESCHLAGEN: Spieler- & Inventarlogik")
		failed = true
	else:
		print("✅ TEST 5 BESTANDEN: Spieler- & Inventarlogik")

	if not test_scene_initialization():
		print("❌ TEST 6 FEHLGESCHLAGEN: Main-Szene Initialisierung")
		failed = true
	else:
		print("✅ TEST 6 BESTANDEN: Main-Szene Initialisierung")

	print("==================================================")
	if failed:
		print("❌ EINIGE TESTS SIND FEHLGESCHLAGEN!")
		quit(1)
	else:
		print("🎉 ALLE TESTS ERFOLGREICH ABGESCHLOSSEN!")
		quit(0)

func test_vglc_parser() -> bool:
	var dot_path = "res://levels/zelda_eagle.dot"
	var graph = VGLCDotParser.parse_file(dot_path)
	if graph == null:
		print("  -> Konnte DOT-Datei nicht parsen!")
		return false

	if graph.rooms.size() < 10:
		print("  -> Zu wenige Räume geparst: ", graph.rooms.size())
		return false

	if graph.start_room_id != "Entrance":
		print("  -> Unerwarteter Startraum: ", graph.start_room_id)
		return false

	if graph.goal_room_id != "TriforceRoom_0_3":
		print("  -> Unerwarteter Zielraum: ", graph.goal_room_id)
		return false

	print("  -> Gepolsterte Räume: %d, Türen: %d" % [graph.rooms.size(), graph.doors.size()])
	return true

func test_zelda_eagle_solvability() -> bool:
	var graph = VGLCDotParser.parse_file("res://levels/zelda_eagle.dot")
	var report = graph.validate_solvability()

	if not report["solvable"]:
		print("  -> Zelda Eagle wurde als unlösbar eingestuft! Fehler: ", report.get("error_message", ""))
		return false

	if report["doors_unlocked"] <= 0:
		print("  -> Keine Türen während der Simulation aufgeschlossen!")
		return false

	print("  -> Solvability Report: Lösbar=true, Entsperrte Türen=%d, Erreichbare Räume=%d" % [
		report["doors_unlocked"], report["visited_rooms"].size()
	])
	return true

func test_deadlock_detection() -> bool:
	# Erzeuge künstlichen Graph mit nicht auflösbarem Deadlock:
	# Start -> Locked Door -> Key Room -> Goal
	# Der Schlüssel liegt HINTER der verschlossenen Tür!
	var graph = DungeonGraph.new()
	var r_start = DungeonGraph.DungeonRoom.new("Start", DungeonGraph.RoomType.START)
	var r_locked = DungeonGraph.DungeonRoom.new("LockedRoom", DungeonGraph.RoomType.KEY)
	r_locked.has_key = true
	var r_goal = DungeonGraph.DungeonRoom.new("Goal", DungeonGraph.RoomType.GOAL)
	r_goal.has_goal = true

	graph.add_room(r_start)
	graph.add_room(r_locked)
	graph.add_room(r_goal)

	# Start führt über verschlossene Tür zu LockedRoom
	graph.add_door("Start", "LockedRoom", DungeonGraph.DoorType.LOCKED, "key_1", true)
	graph.add_door("LockedRoom", "Goal", DungeonGraph.DoorType.OPEN, "", true)

	var report = graph.validate_solvability()
	if report["solvable"]:
		print("  -> Deadlock-Graph wurde fälschlicherweise als lösbar deklariert!")
		return false

	if report["deadlocks"].is_empty():
		print("  -> Deadlock wurde nicht protokolliert!")
		return false

	print("  -> Deadlock erfolgreich erkannt: ", report["deadlocks"][0]["reason"])
	return true

func test_bsp_generator() -> bool:
	var data = BSPDungeonGenerator.generate(70, 45, 3, 12345)
	var graph: DungeonGraph = data["graph"]
	var corridors: Array = data["corridors"]

	if graph == null or graph.rooms.size() < 4:
		print("  -> Zu wenige BSP Räume: ", graph.rooms.size() if graph else 0)
		return false

	if corridors.is_empty():
		print("  -> Keine Korridore generiert!")
		return false

	var report = graph.validate_solvability()
	if not report["solvable"]:
		print("  -> Generierter BSP Dungeon ist unlösbar!")
		return false

	print("  -> BSP Dungeon erzeugt: %d Räume, %d Korridore, Lösbar=%s" % [
		graph.rooms.size(), corridors.size(), str(report["solvable"])
	])
	return true

func test_player_and_inventory() -> bool:
	var player = Player.new()

	if player.keys_count != 0:
		return false

	player.add_key(2)
	if player.keys_count != 2:
		return false

	var success = player.use_key()
	if not success or player.keys_count != 1:
		return false

	player.trigger_goal()
	if not player.has_won:
		return false

	player.free()
	return true

func test_scene_initialization() -> bool:
	var scene_resource = load("res://scenes/main.tscn")
	if scene_resource == null:
		print("  -> Konnte main.tscn nicht laden!")
		return false
	var scene = scene_resource.instantiate()
	if scene == null:
		print("  -> Konnte main.tscn nicht instanziieren!")
		return false

	root.add_child(scene)
	if not scene.is_node_ready():
		scene._ready()
	if scene.player == null or scene.current_graph == null:
		print("  -> Spieler oder Graph in Main-Szene nicht initialisiert! player: ", scene.player, " graph: ", scene.current_graph)
		scene.free()
		return false

	# Teste Wechsel auf BSP
	scene.load_dungeon(scene.DungeonMode.PROCEDURAL_BSP)
	if scene.current_graph == null or scene.current_graph.rooms.is_empty():
		print("  -> Wechsel auf BSP fehlgeschlagen!")
		scene.free()
		return false

	scene.free()
	return true

