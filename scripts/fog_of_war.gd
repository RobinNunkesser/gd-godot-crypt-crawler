class_name FogOfWar
extends Node2D

## FogOfWar: Verwaltet dynamisches 2D-Licht und Fackel-Sichtbarkeit
## Nutzt CanvasModulate für Dunkelheit und PointLight2D für Sichtfeldradius.

@export var is_enabled: bool = true
@export var ambient_darkness: Color = Color(0.25, 0.28, 0.35, 1.0)
@export var ambient_bright: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var light_energy: float = 1.4
@export var light_texture_size: int = 768

var modulate_node: CanvasModulate = null
var torch_light: PointLight2D = null

func _ready() -> void:
	modulate_node = CanvasModulate.new()
	modulate_node.color = ambient_darkness if is_enabled else ambient_bright
	add_child(modulate_node)

	torch_light = PointLight2D.new()
	torch_light.energy = light_energy
	torch_light.texture = _create_radial_gradient_texture(light_texture_size)
	torch_light.texture_scale = 1.0
	torch_light.enabled = is_enabled
	add_child(torch_light)

func follow_target(target_pos: Vector2) -> void:
	if torch_light:
		torch_light.global_position = target_pos

func set_fog_enabled(enabled: bool) -> void:
	is_enabled = enabled
	if modulate_node:
		modulate_node.color = ambient_darkness if is_enabled else ambient_bright
	if torch_light:
		torch_light.enabled = is_enabled

func toggle_fog() -> bool:
	set_fog_enabled(not is_enabled)
	return is_enabled

func _create_radial_gradient_texture(size: int) -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(0, 0, 0, 0))
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size
	texture.height = size
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

