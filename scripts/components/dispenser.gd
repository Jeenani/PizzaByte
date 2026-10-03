class_name DispenserUnit
extends TextureRect
## Диспенсер ингредиентов в печи.
## Поддерживает состояния OFF, PREPARED, DISPENSING (быстрая смена state1-state6 с вытягиванием сверху вниз).

enum State {
	OFF,
	PREPARED,
	DISPENSING
}

var current_state: State = State.OFF

var _tex_off: Texture2D
var _tex_prepared: Texture2D
var _states: Array[Texture2D] = []

var _base_position := Vector2.ZERO
var _current_frame_idx: int = 0
var _frame_timer: float = 0.0
const FRAME_DURATION := 0.09 # Быстрое переключение кадров

var _shake_timer: float = 0.0


func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tex_off = preload("res://assets/textures/oven/dispenser_off.png")
	_tex_prepared = preload("res://assets/textures/oven/dispenser_on_prepared.png")
	_states.append(preload("res://assets/textures/oven/dispenser_state1.png"))
	_states.append(preload("res://assets/textures/oven/dispenser_state2.png"))
	_states.append(preload("res://assets/textures/oven/dispenser_state3.png"))
	_states.append(preload("res://assets/textures/oven/dispenser_state4.png"))
	_states.append(preload("res://assets/textures/oven/dispenser_state5.png"))
	_states.append(preload("res://assets/textures/oven/dispenser_state6.png"))

	texture = _tex_off


func setup(pos: Vector2, disp_size: Vector2) -> void:
	_base_position = pos
	position = pos
	size = disp_size
	# Точка трансформации сверху по центру, чтобы вытягивание происходило сверху вниз
	pivot_offset = Vector2(disp_size.x * 0.5, 0.0)


func set_dispenser_state(new_state: State) -> void:
	current_state = new_state
	match current_state:
		State.OFF:
			texture = _tex_off
			scale = Vector2.ONE
			position = _base_position
			modulate = Color(0.92, 0.92, 0.96) # Темный металл камеры
		State.PREPARED:
			texture = _tex_prepared
			scale = Vector2.ONE
			position = _base_position
			modulate = Color(0.94, 0.98, 1.05) # Холодный свет синей подсветки
		State.DISPENSING:
			_current_frame_idx = randi() % _states.size()
			texture = _states[_current_frame_idx]
			_frame_timer = 0.0
			_shake_timer = 0.0
			modulate = Color(1.05, 0.98, 0.92) # Теплый отблеск жара печи


func _process(delta: float) -> void:
	if current_state != State.DISPENSING:
		return

	# Быстрое переключение текстур 1..6
	_frame_timer += delta
	if _frame_timer >= FRAME_DURATION:
		_frame_timer = 0.0
		_current_frame_idx = (_current_frame_idx + 1) % _states.size()
		texture = _states[_current_frame_idx]

	# Эффект тряски и вытягивания сверху вниз
	_shake_timer += delta
	# Вытягивание по вертикали (scale.y растет до 1.07-1.10, с компенсацией по X)
	var stretch_y: float = 1.0 + sin(_shake_timer * 32.0) * 0.05 + randf_range(-0.01, 0.03)
	var stretch_x: float = 1.0 / sqrt(maxf(stretch_y, 0.8)) # Сохранение объема
	scale = Vector2(stretch_x, stretch_y)

	# Механическая дрожь поршня
	var jitter_x := randf_range(-0.8, 0.8)
	var jitter_y := randf_range(0.0, 1.8)
	position = _base_position + Vector2(jitter_x, jitter_y)



## Резкий импульс поршня в момент выброса порции ингредиента
func pulse_shoot() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale:y", 1.16, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "scale:x", 0.92, 0.06)
	tw.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
