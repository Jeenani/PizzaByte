class_name NeonSign
extends TextureRect
## Неоновая вывеска вендингового аппарата с живым мерцанием и переключением на pizza_logo_off.png.
## Шейдер neon_sign.gdshader независимо управляет питанием 10 сегментов через vec4/vec2.

const SEGMENT_COUNT := 10
const SIGN_WIDTH := 550.0
const SIGN_HEIGHT := 170.0

var _powers: Array[float] = []
var _shader_mat: ShaderMaterial

# Тайминги общего состояния
var _time_until_flicker: float = 0.5
var _time_until_global_flicker: float = 3.0
var _is_flickering: bool = false
var _alive_timer: float = 0.0

# Режим «заболевшей» лампы (мигает чаще)
var _sick_segment: int = 3 # Например, первая буква 'Z' чуть нестабильна
var _sick_timer: float = 12.0


func _init() -> void:
	texture = preload("res://assets/textures/machine/pizza_logo_on.png")
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	custom_minimum_size = Vector2(SIGN_WIDTH, SIGN_HEIGHT)
	size = Vector2(SIGN_WIDTH, SIGN_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_powers.resize(SEGMENT_COUNT)
	for i in range(SEGMENT_COUNT):
		_powers[i] = 1.0

	var sh := preload("res://shaders/neon_sign.gdshader")
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = sh
	_shader_mat.set_shader_parameter("tex_off", preload("res://assets/textures/machine/pizza_logo_off.png"))
	_sync_shader_powers()
	material = _shader_mat


func _ready() -> void:
	_time_until_flicker = randf_range(0.8, 1.8)
	_time_until_global_flicker = randf_range(3.0, 5.5)


func _process(delta: float) -> void:
	_alive_timer += delta

	# Постоянное живое фоновое "гудение" неона (микро-колебания яркости)
	var hum := 0.98 + 0.025 * sin(_alive_timer * 45.0) + randf_range(-0.015, 0.015)
	if _shader_mat and not _is_flickering:
		_shader_mat.set_shader_parameter("global_power", hum)

	# Таймер "больной" лампы
	_sick_timer -= delta
	if _sick_timer <= 0.0:
		_sick_segment = randi() % SEGMENT_COUNT
		_sick_timer = randf_range(12.0, 20.0)

	# Таймер миганий
	if not _is_flickering:
		_time_until_global_flicker -= delta
		if _time_until_global_flicker <= 0.0:
			_start_global_flicker()
		else:
			_time_until_flicker -= delta
			if _time_until_flicker <= 0.0:
				_start_flicker_sequence()


func _sync_shader_powers() -> void:
	if not _shader_mat:
		return
	var p1 := Vector4(_powers[0], _powers[1], _powers[2], _powers[3])
	var p2 := Vector4(_powers[4], _powers[5], _powers[6], _powers[7])
	var p3 := Vector2(_powers[8], _powers[9])
	_shader_mat.set_shader_parameter("seg_p1", p1)
	_shader_mat.set_shader_parameter("seg_p2", p2)
	_shader_mat.set_shader_parameter("seg_p3", p3)


func _set_segment_power(seg: int, power: float) -> void:
	if seg >= 0 and seg < SEGMENT_COUNT:
		_powers[seg] = power
		_sync_shader_powers()


## Мигание всей вывески разом (кратковременный электрический сбой питания)
func _start_global_flicker() -> void:
	_is_flickering = true
	var drops := randi_range(2, 4)
	for d in range(drops):
		var off_p := randf_range(0.0, 0.2)
		if _shader_mat:
			_shader_mat.set_shader_parameter("global_power", off_p)
		await get_tree().create_timer(randf_range(0.04, 0.09)).timeout

		var on_p := randf_range(0.85, 1.05)
		if _shader_mat:
			_shader_mat.set_shader_parameter("global_power", on_p)
		if d < drops - 1:
			await get_tree().create_timer(randf_range(0.03, 0.08)).timeout

	if _shader_mat:
		_shader_mat.set_shader_parameter("global_power", 1.0)
	_is_flickering = false
	_time_until_global_flicker = randf_range(4.0, 7.5)


## Мигание отдельного сегмента (буквы или кусочка пиццы)
func _start_flicker_sequence() -> void:
	_is_flickering = true

	# Выбираем сегмент для мигания: больной (65%) или случайный (35%)
	var seg_idx: int = _sick_segment if randf() < 0.65 else (randi() % SEGMENT_COUNT)

	# Тип мигания: одиночный щелчок, серия из 2-3 дрожаний
	var bursts := 1
	var r := randf()
	if r < 0.25:
		bursts = 3
	elif r < 0.50:
		bursts = 2

	for b in range(bursts):
		# Падение в текстуру pizza_logo_off (питание 0.0 - 0.1)
		var off_val := randf_range(0.0, 0.1)
		_set_segment_power(seg_idx, off_val)
		await get_tree().create_timer(randf_range(0.05, 0.11)).timeout

		# Быстрое включение назад
		_set_segment_power(seg_idx, 1.0)
		if b < bursts - 1:
			await get_tree().create_timer(randf_range(0.04, 0.10)).timeout

	_set_segment_power(seg_idx, 1.0)
	_is_flickering = false
	# Следующее мигание скоро: через 0.8–2.2 сек!
	_time_until_flicker = randf_range(0.8, 2.2)
