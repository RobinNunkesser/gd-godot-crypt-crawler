class_name Player
extends CharacterBody2D

## Player: 2D Top-Down Charakter für den Crypt Crawler
## Handhabt 8-Wege-Bewegung, Schlüssel-Inventar und Interaktion mit Türen/Zielen.

signal key_collected(total_keys: int)
signal door_unlocked(from_room: String, to_room: String)
signal goal_reached()
signal position_changed(pos: Vector2)

@export var speed: float = 220.0
@export var acceleration: float = 1200.0
@export var friction: float = 1400.0

var keys_count: int = 0
var current_room_id: String = ""
var has_won: bool = false
var facing_direction: Vector2 = Vector2.DOWN

func _ready() -> void:
	# Sicherstellen, dass Kollisionslayer und -maske definiert sind
	collision_layer = 1
	collision_mask = 1 | 2 # Layer 1: Wände, Layer 2: Türen
	z_index = 10 # Immer über dem Boden und Objekten zeichnen

	var shape = CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circ = CircleShape2D.new()
	circ.radius = 12.0
	shape.shape = circ
	add_child(shape)

func _physics_process(delta: float) -> void:
	if has_won:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_vector = Vector2.ZERO
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	input_vector.y = Input.get_axis("ui_up", "ui_down")
	input_vector = input_vector.normalized()

	if input_vector != Vector2.ZERO:
		facing_direction = input_vector
		velocity = velocity.move_toward(input_vector * speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()
	position_changed.emit(global_position)
	queue_redraw()

func add_key(amount: int = 1) -> void:
	keys_count += amount
	key_collected.emit(keys_count)

func use_key() -> bool:
	if keys_count > 0:
		keys_count -= 1
		key_collected.emit(keys_count)
		return true
	return false

func trigger_goal() -> void:
	if not has_won:
		has_won = true
		goal_reached.emit()

func _draw() -> void:
	# Vektor-Darstellung des Spielers: Kreis mit Blickrichtungs-Indikator
	draw_circle(Vector2.ZERO, 12.0, Color(0.2, 0.7, 1.0))
	draw_circle(Vector2.ZERO, 10.0, Color(0.1, 0.45, 0.85))
	# Fackel/Schild
	var nose_pos = facing_direction * 12.0
	draw_circle(nose_pos, 4.0, Color(1.0, 0.85, 0.2))
	# Kontur
	draw_arc(Vector2.ZERO, 12.0, 0, TAU, 16, Color.WHITE, 1.5)

