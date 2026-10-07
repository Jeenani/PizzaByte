class_name DispenseSign
extends Control
## Неоновая вывеска над лотком выдачи автомата
## Текст «ЗАБЕРИ СВОЮ ПИЦЦУ» и два мигающих красных треугольника-стрелки ▼
## Расположена на скошенной планке каркаса: Rect2(240, 1016, 570, 54)

const SIGN_W := 570.0
const SIGN_H := 54.0

var _left_arrow: TextureRect
var _right_arrow: TextureRect
var _label: Label

var _is_active: bool = false
var _blink_time: float = 0.0
var _base_arrow_y: float = 11.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(SIGN_W, SIGN_H)
	visible = false
	modulate.a = 0.0


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# 1. Загрузка текстуры стрелки-треугольника
	var arrow_tex: Texture2D = null
	var arrow_path := "res://assets/textures/ui/dispenser_arrow.png"
	if ResourceLoader.exists(arrow_path):
		arrow_tex = load(arrow_path) as Texture2D

	# 2. Левая стрелка ▼
	_left_arrow = TextureRect.new()
	_left_arrow.name = "LeftArrow"
	_left_arrow.texture = arrow_tex
	_left_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_left_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_left_arrow.size = Vector2(36, 32)
	_left_arrow.position = Vector2(65, _base_arrow_y)
	_left_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left_arrow)

	# 3. Правая стрелка ▼
	_right_arrow = TextureRect.new()
	_right_arrow.name = "RightArrow"
	_right_arrow.texture = arrow_tex
	_right_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_right_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_right_arrow.size = Vector2(36, 32)
	_right_arrow.position = Vector2(469, _base_arrow_y)
	_right_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right_arrow)

	# 4. Текст «ЗАБЕРИ СВОЮ ПИЦЦУ»
	_label = Label.new()
	_label.name = "SignLabel"
	_label.text = "ЗАБЕРИ СВОЮ ПИЦЦУ"
	_label.size = Vector2(SIGN_W, SIGN_H)
	_label.position = Vector2.ZERO
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Шрифт Minecraft
	var font_path := "res://assets/textures/font/minecraft-rus-regular1.ttf"
	if ResourceLoader.exists(font_path):
		var custom_font := load(font_path) as Font
		_label.add_theme_font_override("font", custom_font)

	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.08, 0.95))
	_label.add_theme_constant_override("outline_size", 4)
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.add_theme_constant_override("shadow_offset_x", 0)

	add_child(_label)


func _process(delta: float) -> void:
	if not _is_active:
		return

	_blink_time += delta

	# Четкое сигнальное моргание табло выдачи (период 0.44 сек: 0.26 сек горит, 0.18 сек гаснет)
	var cycle := fmod(_blink_time, 0.44)
	var is_lit := cycle < 0.26

	if is_lit:
		modulate.a = 1.0
		# Легкий импульс стрелок вниз в такт свечению
		var bounce := sin((cycle / 0.26) * PI) * 2.5
		if _left_arrow:
			_left_arrow.position.y = _base_arrow_y + bounce
		if _right_arrow:
			_right_arrow.position.y = _base_arrow_y + bounce
	else:
		# При угасании остается слабое люминесцентное послесвечение
		modulate.a = 0.08
		if _left_arrow:
			_left_arrow.position.y = _base_arrow_y
		if _right_arrow:
			_right_arrow.position.y = _base_arrow_y


## Включить мигание табло выдачи
func start_blinking() -> void:
	_is_active = true
	_blink_time = 0.0
	visible = true
	modulate.a = 1.0
	if _left_arrow: _left_arrow.position.y = _base_arrow_y
	if _right_arrow: _right_arrow.position.y = _base_arrow_y


## Выключить табло выдачи
func stop_blinking() -> void:
	_is_active = false
	_blink_time = 0.0
	visible = false
	modulate.a = 0.0
	if _left_arrow: _left_arrow.position.y = _base_arrow_y
	if _right_arrow: _right_arrow.position.y = _base_arrow_y


func is_active() -> bool:
	return _is_active
