class_name PizzaCooker
extends Node2D
## Компонент вращающегося вала и приготовления пиццы в камере печи (OvenZone).
## 1. Вращающийся вал с тестом (кадры stove_platform_1..6 по часовой стрелке).
## 2. Изометрическая раскладка ингредиентов слоями из 4-х сопел диспенсеров.
## 3. 5-секундная фаза запекания (ТЭНы, золотистая корочка, пар).

signal cooking_layer_started(layer_name: String, dispenser_idx: int)
signal baking_started
signal platform_lowering_started
signal cooking_completed

const PLATFORM_SCALE := 0.77
const PLATFORM_W := 820.0 * PLATFORM_SCALE # ~631.4
const PLATFORM_H := 400.0 * PLATFORM_SCALE # ~308.0
const PLATFORM_X := (820.0 - PLATFORM_W) * 0.5 # ~94.3 — строго по центру между рамками
const PLATFORM_START_Y := 265.0
const PLATFORM_EXIT_Y := 690.0 # Спуск глубоко под печь к выходу

const ELLIPSE_CENTER := Vector2(410.0, 265.0 + 120.0 * PLATFORM_SCALE) # ~357.4
const RX_MAX := 245.0 * PLATFORM_SCALE # ~188.6
const RY_MAX := 74.0 * PLATFORM_SCALE # ~57.0

var _dispensers: Array[DispenserUnit] = []
var _crust_rim_rect: TextureRect
var _platform_rect: TextureRect
var _completed_rect: TextureRect
var _crust_material: ShaderMaterial
var _bake_material: ShaderMaterial
var _platform_frames: Array[Texture2D] = []
var _completed_textures: Dictionary = {}

# Динамические параметры размера и теста текущего заказа
var _current_platform_scale: float = 0.73
var _current_radius_scale: float = 1.0
var _current_count_factor: float = 1.0
var _current_dough_thickness: float = 1.0
var _current_crust_offset_y: float = 4.5
var _current_dough_aspect_y: float = 1.0
var _current_dough_tint: Color = Color.WHITE

var _cur_frame := 0
var _frame_timer := 0.0
const FRAME_DURATION := 0.12

var _is_cooking := false
var _is_baking := false
var _is_lowering := false
var _skip_layers_requested := false
var _skip_baking_requested := false
var _rot_angle := 0.0
const ROT_SPEED := 0.55

var _current_pizza_name := ""
var _cook_time_elapsed := 0.0
var _active_tweens: Array[Tween] = []
var _cook_session_id: int = 0
var _ingredients_container: Node2D

class LandedItem:
	var sprite: Sprite2D
	var r_frac: float
	var base_angle: float
	var base_scale: float

var _landed_items: Array[LandedItem] = []


func _init() -> void:
	for i in range(1, 7):
		var p := "res://assets/textures/oven/stove_platform_%d.png" % i
		if ResourceLoader.exists(p):
			_platform_frames.append(load(p) as Texture2D)

	# Текстуры готовых пицц для наложения при запекании
	var completed_files := {
		"Карбонара": "res://assets/textures/oven/stove_platform_carbonara_completed.png",
		"Чикен Бомбони": "res://assets/textures/oven/stove_platform_chickenbomb_completed.png",
		"Маргарита": "res://assets/textures/oven/stove_platform_margarita_completed.png",
		"Пепперони": "res://assets/textures/oven/stove_platform_pepperoni_completed.png"
	}
	for k in completed_files:
		var p: String = completed_files[k]
		if ResourceLoader.exists(p):
			_completed_textures[k] = load(p) as Texture2D


func _ready() -> void:
	# 0. Подложка объемного борта (Crust Underlayer) для псевдо-3D толщины теста
	_crust_rim_rect = TextureRect.new()
	_crust_rim_rect.name = "StovePlatformCrustRim"
	_crust_rim_rect.size = Vector2(820, 400)
	_crust_rim_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crust_rim_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crust_rim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crust_rim_rect.modulate = Color(0.68, 0.46, 0.26, 0.95)
	_crust_rim_rect.z_index = 4
	if _platform_frames.size() > 0:
		_crust_rim_rect.texture = _platform_frames[0]
	add_child(_crust_rim_rect)

	# 1. Вращающийся вал с пустым тестом
	_platform_rect = TextureRect.new()
	_platform_rect.name = "StovePlatform"
	_platform_rect.size = Vector2(820, 400)
	_platform_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_platform_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_platform_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_platform_rect.z_index = 5
	if _platform_frames.size() > 0:
		_platform_rect.texture = _platform_frames[0]

	var crust_sh := load("res://shaders/crust_style.gdshader") as Shader
	if crust_sh:
		_crust_material = ShaderMaterial.new()
		_crust_material.shader = crust_sh
		_platform_rect.material = _crust_material
	add_child(_platform_rect)

	# 2. Оверлей готовой запеченной пиццы с шейдером трансформации
	_completed_rect = TextureRect.new()
	_completed_rect.name = "StovePlatformCompleted"
	_completed_rect.size = Vector2(820, 400)
	_completed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_completed_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_completed_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_completed_rect.z_index = 6
	var shader := load("res://shaders/pizza_bake_dissolve.gdshader") as Shader
	if shader:
		_bake_material = ShaderMaterial.new()
		_bake_material.shader = shader
		_completed_rect.material = _bake_material
		_bake_material.set_shader_parameter("progress", 0.0)
	add_child(_completed_rect)

	# 3. Контейнер для всех кусочков начинки (всегда чистится атомарно)
	_ingredients_container = Node2D.new()
	_ingredients_container.name = "IngredientsContainer"
	_ingredients_container.z_index = 20
	add_child(_ingredients_container)

	# Выставляем правильные центрированные координаты и масштабы
	_update_platform_transforms()
	visible = false


func setup_dispensers(dispensers: Array[DispenserUnit]) -> void:
	_dispensers = dispensers


func _process(delta: float) -> void:
	if not _is_cooking:
		return

	# На этапе запекания и спуска платформа ОСТАНОВЛЕНА
	if _is_baking:
		return

	# Анимация вращения вала по часовой стрелке
	if _platform_frames.size() > 0:
		_frame_timer += delta
		if _frame_timer >= FRAME_DURATION:
			_frame_timer = 0.0
			_cur_frame = (_cur_frame + 1) % _platform_frames.size()
			_platform_rect.texture = _platform_frames[_cur_frame]
			if _crust_rim_rect:
				_crust_rim_rect.texture = _platform_frames[_cur_frame]

	# Вращение ингредиентов по динамическому эллипсу размера пиццы
	_rot_angle += ROT_SPEED * delta
	var cur_rx := RX_MAX * _current_radius_scale
	var cur_ry := RY_MAX * _current_radius_scale * _current_dough_aspect_y
	for item in _landed_items:
		if not is_instance_valid(item.sprite):
			continue
		var a := item.base_angle + _rot_angle
		var px := ELLIPSE_CENTER.x + cos(a) * (item.r_frac * cur_rx)
		var py := ELLIPSE_CENTER.y + sin(a) * (item.r_frac * cur_ry)
		item.sprite.position = Vector2(px, py)
		item.sprite.scale.x = item.base_scale
		item.sprite.scale.y = item.base_scale * (0.60 + sin(a) * 0.05)
		item.sprite.z_index = 20 + int(py)


## Применение параметров размера, толщины теста и бортиков из заказа
func _apply_order_style(order: Order) -> void:
	_current_platform_scale = 0.73
	_current_radius_scale = 1.0
	_current_count_factor = 1.0
	_current_dough_thickness = 1.0
	_current_crust_offset_y = 4.5
	_current_dough_aspect_y = 1.0
	_current_dough_tint = Color.WHITE

	if not order:
		_update_platform_transforms()
		return

	# 1. Размер пиццы (масштаб платформы строго в пределах проема печи 88..732 px)
	var sz_str := ""
	if order.pizza_size:
		sz_str = order.pizza_size.display_name.to_lower()
	if "маленьк" in sz_str:
		_current_platform_scale = 0.67 # ширина 549 px, отступы до стенок по 47 px
		_current_radius_scale = 0.82
		_current_count_factor = 0.70   # меньше порций ингредиентов
	elif "больш" in sz_str:
		_current_platform_scale = 0.762 # ширина 625 px, красивый безопасный зазор ровно 9.6 px
		_current_radius_scale = 1.18
		_current_count_factor = 1.40   # больше порций ингредиентов
	else:
		_current_platform_scale = 0.73  # ширина 598 px, зазор 22.7 px
		_current_radius_scale = 1.00
		_current_count_factor = 1.00   # средний размер и количество

	# 2. Тип теста (тонкое / классическое / пышное)
	var dg_str := ""
	if order.dough:
		dg_str = order.dough.display_name.to_lower()
	if "тонк" in dg_str:
		_current_dough_thickness = 0.68
		_current_crust_offset_y = 1.5
		_current_dough_aspect_y = 0.93
		_current_dough_tint = Color(1.04, 0.98, 0.92) # золотисто-хрустящее
	elif "пышн" in dg_str or "воздушн" in dg_str:
		_current_dough_thickness = 1.45
		_current_crust_offset_y = 7.5
		_current_dough_aspect_y = 1.08
		_current_dough_tint = Color(1.0, 0.96, 0.90) # пышное нежное тесто
	else:
		_current_dough_thickness = 1.00
		_current_crust_offset_y = 4.5
		_current_dough_aspect_y = 1.00
		_current_dough_tint = Color.WHITE

	# 3. Высота бортиков
	if order.height_tall:
		_current_dough_thickness *= 1.22
		_current_crust_offset_y += 3.0
		_current_dough_aspect_y *= 1.05

	_update_platform_transforms()

	if _crust_material:
		_crust_material.set_shader_parameter("thickness", _current_dough_thickness)
		_crust_material.set_shader_parameter("dough_modulate", _current_dough_tint)
	if _bake_material:
		_bake_material.set_shader_parameter("thickness", _current_dough_thickness)
		_bake_material.set_shader_parameter("dough_modulate", _current_dough_tint)


func _update_platform_transforms() -> void:
	var final_sx := _current_platform_scale
	var final_sy := _current_platform_scale * _current_dough_aspect_y
	var sc := Vector2(final_sx, final_sy)

	# Идеальное центрирование между левой и правой стенками печи при любом масштабе
	var px := (820.0 - 820.0 * final_sx) * 0.5
	var py := ELLIPSE_CENTER.y - 120.0 * final_sy

	if _platform_rect:
		_platform_rect.scale = sc
		_platform_rect.position = Vector2(px, py)
	if _completed_rect:
		_completed_rect.scale = sc
		_completed_rect.position = Vector2(px, py)
	if _crust_rim_rect:
		_crust_rim_rect.scale = sc
		_crust_rim_rect.position = Vector2(px, py + _current_crust_offset_y)
		_crust_rim_rect.modulate = Color(0.68, 0.46, 0.26, 0.95 if _current_crust_offset_y > 2.0 else 0.4)


## Вспомогательная функция масштабирования порций ингредиентов
func _scale_recipe_paths(base_paths: Array, factor: float) -> Array:
	var target_count := int(round(float(base_paths.size()) * factor))
	target_count = maxi(target_count, 3)
	var res: Array = []
	for i in range(target_count):
		res.append(base_paths[i % base_paths.size()])
	return res


func start_cooking(order: Order) -> void:
	_cleanup()
	_cook_session_id += 1
	var session := _cook_session_id
	visible = true
	_is_cooking = true
	_is_baking = false
	_skip_layers_requested = false
	_skip_baking_requested = false
	_cook_time_elapsed = 0.0
	_rot_angle = 0.0
	_cur_frame = 0

	_apply_order_style(order)

	_current_pizza_name = _detect_pizza_type(order)
	print("[PizzaCooker] Старт готовки (сессия #%d): %s | Размер: %.2fx (начинки: %.2fx) | Тесто: толщина %.2f, бортик +%.1fpx" % [
		session, _current_pizza_name, _current_platform_scale, _current_count_factor, _current_dough_thickness, _current_crust_offset_y
	])
	AudioManager.play_cooking_groove()

	_run_cooking_sequence(_current_pizza_name, session)


func _detect_pizza_type(order: Order) -> String:
	if not order: return "Пепперони"
	if order.order_name != "":
		var n := order.order_name.to_lower()
		if "карб" in n: return "Карбонара"
		if "чик" in n or "бомб" in n or "бург" in n: return "Чикен Бомбони"
		if "марг" in n: return "Маргарита"
		if "пепп" in n: return "Пепперони"
	var ings := order.get_ingredient_names()
	for ing in ings:
		var lower := ing.to_lower()
		if "куриц" in lower: return "Чикен Бомбони"
		if "бекон" in lower or "ветчин" in lower: return "Карбонара"
	return "Пепперони"


func _run_cooking_sequence(pizza_type: String, session: int) -> void:
	match pizza_type:
		"Карбонара": await _cook_carbonara(session)
		"Чикен Бомбони": await _cook_chicken_bomboni(session)
		"Маргарита": await _cook_margarita(session)
		"Пепперони": await _cook_pepperoni(session)
		_: await _cook_pepperoni(session)

	if session != _cook_session_id or not _is_cooking: return
	if _skip_baking_requested: return
	await _start_baking_phase(session)
	if session == _cook_session_id and _is_cooking and not _skip_baking_requested:
		cooking_completed.emit()


func _cook_carbonara(session: int) -> void:
	if session != _cook_session_id or not _is_cooking: return
	cooking_layer_started.emit("Соусная основа", 0)
	var cheese_paths := [
		"res://assets/textures/ingredients/carbonara/carbonara_cheese.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese2.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese3.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese2.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese3.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese2.png"
	]
	await _drop_batch(0, _scale_recipe_paths(cheese_paths, _current_count_factor), 1.8, "sauce_spiral", 0.50, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Мясо", 1)
	var meat_paths: Array = []
	for r in range(2):
		for i in range(1, 7):
			var suffix := "" if i == 1 else str(i)
			meat_paths.append("res://assets/textures/ingredients/carbonara/carbonara_meat%s.png" % suffix)
	await _drop_batch(1, _scale_recipe_paths(meat_paths, _current_count_factor), 1.8, "bacon_ring", 0.44, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Лук", 2)
	var onion_paths: Array = []
	for r in range(2):
		for i in range(1, 5):
			var suffix := "" if i == 1 else str(i)
			onion_paths.append("res://assets/textures/ingredients/carbonara/carbonara_onion%s.png" % suffix)
	await _drop_batch(2, _scale_recipe_paths(onion_paths, _current_count_factor), 1.8, "onion_rings", 0.38, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Сырная крошка", 3)
	var part_paths: Array = []
	for r in range(3):
		for i in range(1, 7):
			var idx := ((i - 1) % 5) + 1
			part_paths.append("res://assets/textures/ingredients/carbonara/carbonara_cheese_part%d.png" % idx)
	await _drop_batch(3, _scale_recipe_paths(part_paths, _current_count_factor), 1.8, "cheese_layer", 0.34, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Зелень", 0)
	var herb_paths: Array = []
	for r in range(2):
		for i in range(1, 5):
			var suffix := "" if i == 1 else str(i)
			herb_paths.append("res://assets/textures/ingredients/carbonara/carbonara_herbs%s.png" % suffix)
	await _drop_batch_dual(0, 1, _scale_recipe_paths(herb_paths, _current_count_factor), 1.8, "herbs_top", 0.40, session)


func _cook_chicken_bomboni(session: int) -> void:
	if session != _cook_session_id or not _is_cooking: return
	cooking_layer_started.emit("Соус", 0)
	var sauce_paths := [
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce2.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce2.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce2.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce2.png"
	]
	await _drop_batch(0, _scale_recipe_paths(sauce_paths, _current_count_factor), 2.25, "sauce_spiral", 0.52, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Лук", 1)
	var onion_paths: Array = []
	for r in range(2):
		for i in range(1, 5):
			var suffix := "" if i == 1 else str(i)
			onion_paths.append("res://assets/textures/ingredients/carbonara/carbonara_onion%s.png" % suffix)
	await _drop_batch(1, _scale_recipe_paths(onion_paths, _current_count_factor), 2.25, "onion_rings", 0.38, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Перец", 2)
	var pepper_paths: Array = []
	for r in range(2):
		for i in range(1, 10):
			var idx := ((i - 1) % 8) + 1
			var suffix := "" if idx == 1 else str(idx)
			pepper_paths.append("res://assets/textures/ingredients/chickenbomb/chicken_bomboni_pepper%s.png" % suffix)
	await _drop_batch(2, _scale_recipe_paths(pepper_paths, _current_count_factor), 2.25, "pepper_scatter", 0.32, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Куриные наггетсы", 3)
	var nugget_paths: Array = []
	for r in range(2):
		for i in range(1, 7):
			var idx := ((i - 1) % 5) + 1
			nugget_paths.append("res://assets/textures/ingredients/chickenbomb/chicken_bomboni_nugget%d.png" % idx)
	await _drop_batch(3, _scale_recipe_paths(nugget_paths, _current_count_factor), 2.25, "chicken_pieces", 0.45, session)




func _cook_margarita(session: int) -> void:
	if session != _cook_session_id or not _is_cooking: return
	cooking_layer_started.emit("Томатный соус", 0)
	var sauce_paths := [
		"res://assets/textures/ingredients/margarita/margarita_sauce.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce2.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce3.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce2.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce3.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce2.png"
	]
	await _drop_batch(0, _scale_recipe_paths(sauce_paths, _current_count_factor), 2.25, "sauce_spiral", 0.52, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Сыр Моцарелла", 1)
	var cheese_paths: Array = []
	for r in range(4):
		cheese_paths.append("res://assets/textures/ingredients/margarita/margarita_cheese.png")
		cheese_paths.append("res://assets/textures/ingredients/margarita/margarita_cheese2.png")
	await _drop_batch(1, _scale_recipe_paths(cheese_paths, _current_count_factor), 2.25, "margarita_cheese", 0.46, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Оливковое масло", 2)
	var oil_paths: Array = []
	for r in range(2):
		for i in range(1, 6):
			var idx := ((i - 1) % 4) + 1
			var suffix := "" if idx == 1 else str(idx)
			oil_paths.append("res://assets/textures/ingredients/margarita/margarita_oil%s.png" % suffix)
	await _drop_batch(2, _scale_recipe_paths(oil_paths, _current_count_factor), 2.25, "scatter_mid", 0.36, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Базилик", 3)
	var bazilik_paths: Array = []
	for r in range(2):
		for i in range(1, 5):
			var suffix := "" if i == 1 else str(i)
			bazilik_paths.append("res://assets/textures/ingredients/margarita/margarita_bazilik%s.png" % suffix)
	await _drop_batch(3, _scale_recipe_paths(bazilik_paths, _current_count_factor), 2.25, "herbs_top", 0.42, session)


func _cook_pepperoni(session: int) -> void:
	if session != _cook_session_id or not _is_cooking: return
	cooking_layer_started.emit("Томатный соус", 0)
	var sauce_paths := [
		"res://assets/textures/ingredients/pepperoni/margarita_sauce.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce2.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce3.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce2.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce3.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce2.png"
	]
	await _drop_batch(0, _scale_recipe_paths(sauce_paths, _current_count_factor), 1.8, "sauce_spiral", 0.50, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Сырная основа", 1)
	var cheese_paths: Array = []
	for r in range(3):
		for i in range(1, 7):
			var idx := ((i - 1) % 5) + 1
			cheese_paths.append("res://assets/textures/ingredients/pepperoni/carbonara_cheese_part%d.png" % idx)
	await _drop_batch(1, _scale_recipe_paths(cheese_paths, _current_count_factor), 1.8, "cheese_layer", 0.36, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Лук", 2)
	var onion_paths: Array = []
	for r in range(2):
		onion_paths.append("res://assets/textures/ingredients/pepperoni/pepperoni_onion.png")
		onion_paths.append("res://assets/textures/ingredients/pepperoni/carbonara_onion2.png")
		onion_paths.append("res://assets/textures/ingredients/pepperoni/carbonara_onion3.png")
		onion_paths.append("res://assets/textures/ingredients/pepperoni/carbonara_onion4.png")
	await _drop_batch(2, _scale_recipe_paths(onion_paths, _current_count_factor), 1.8, "onion_rings", 0.38, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Пряный перец", 3)
	var pepper_paths: Array = []
	for r in range(2):
		for i in range(1, 7):
			var suffix := "" if i == 1 else str(i)
			pepper_paths.append("res://assets/textures/ingredients/pepperoni/pepperoni_pepper%s.png" % suffix)
		for i in range(1, 4):
			var suffix := "" if i == 1 else str(i)
			pepper_paths.append("res://assets/textures/ingredients/pepperoni/chicken_bomboni_pepper%s.png" % suffix)
	await _drop_batch(3, _scale_recipe_paths(pepper_paths, _current_count_factor), 1.8, "pepper_scatter", 0.32, session)
	if session != _cook_session_id or not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Пепперони", 0)
	var meat_count := int(round(14.0 * _current_count_factor))
	var meat_paths: Array = []
	for i in range(1, meat_count + 1):
		var idx := ((i - 1) % 5) + 1
		meat_paths.append("res://assets/textures/ingredients/pepperoni/pepperoni_meat%d.png" % idx)
	await _drop_batch_dual(0, 3, meat_paths, 1.8, "pepperoni_rings", 0.46, session)


func _start_baking_phase(session_id: int) -> void:
	if session_id != _cook_session_id or not _is_cooking:
		return
	_is_baking = true
	baking_started.emit()
	AudioManager.play_oven_baking()
	print("[PizzaCooker] 🔥 ЗАПЕКАНИЕ (6 сек): Платформа остановлена! Плавное вплавление ингредиентов...")

	# 1. ОСТАНАВЛИВАЕМ ВАЛ ровно на кадре 0 (stove_platform_1.png).
	_cur_frame = 0
	if _platform_frames.size() > 0:
		_platform_rect.texture = _platform_frames[0]
		if _crust_rim_rect:
			_crust_rim_rect.texture = _platform_frames[0]

	for d in _dispensers:
		d.set_dispenser_state(DispenserUnit.State.PREPARED)

	# 2. Шейдерная трансформация пиццы (огненная волна запекания) + пышность теста
	var comp_tex: Texture2D = _completed_textures.get(_current_pizza_name, _completed_textures.get("Пепперони", null))
	if comp_tex and _completed_rect:
		_completed_rect.texture = comp_tex
		_completed_rect.modulate = Color.WHITE
		if _bake_material:
			_bake_material.set_shader_parameter("progress", 0.0)

		var tw_dissolve := create_tween()
		_active_tweens.append(tw_dissolve)
		tw_dissolve.set_parallel(true)

		# Огненная волна запекания от центра пиццы к краям (растянута на 4.0 сек)
		if _bake_material:
			tw_dissolve.tween_method(
				func(v: float): _bake_material.set_shader_parameter("progress", v),
				0.0, 1.0, 4.00
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			tw_dissolve.tween_property(_completed_rect, "modulate:a", 1.0, 3.5).set_trans(Tween.TRANS_QUAD)

		# Плавное подрумянивание и вплавление ВСЕХ сырых ингредиентов (4.0 сек)
		if _ingredients_container:
			for child in _ingredients_container.get_children():
				if child is Sprite2D and is_instance_valid(child):
					tw_dissolve.tween_property(child, "modulate", Color(1.2, 0.95, 0.7, 0.85), 1.8).set_trans(Tween.TRANS_SINE)
					tw_dissolve.tween_property(child, "modulate", Color(1.35, 1.1, 0.8, 0.0), 2.2).set_delay(1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

		# Плавное "дыхание" теста от жара печи: поднимается 2.0 сек и оседает 2.0 сек
		var base_sc := Vector2(_current_platform_scale, _current_platform_scale * _current_dough_aspect_y)
		var rise_sc := base_sc * 1.025
		tw_dissolve.tween_property(_platform_rect, "scale", rise_sc, 2.0).set_trans(Tween.TRANS_SINE)
		tw_dissolve.tween_property(_completed_rect, "scale", rise_sc, 2.0).set_trans(Tween.TRANS_SINE)
		if _crust_rim_rect:
			tw_dissolve.tween_property(_crust_rim_rect, "scale", rise_sc, 2.0).set_trans(Tween.TRANS_SINE)
		tw_dissolve.chain().tween_property(_platform_rect, "scale", base_sc, 2.0).set_trans(Tween.TRANS_SINE)
		tw_dissolve.parallel().tween_property(_completed_rect, "scale", base_sc, 2.0).set_trans(Tween.TRANS_SINE)
		if _crust_rim_rect:
			tw_dissolve.parallel().tween_property(_crust_rim_rect, "scale", base_sc, 2.0).set_trans(Tween.TRANS_SINE)

	var bake_timer := 5.0
	while bake_timer > 0.0 and _is_cooking and not _skip_baking_requested and session_id == _cook_session_id:
		await get_tree().create_timer(0.2).timeout
		bake_timer -= 0.2

	AudioManager.stop_oven_baking()

	if _skip_baking_requested or not _is_cooking or session_id != _cook_session_id:
		return

	_is_baking = false
	print("[PizzaCooker] Запекание завершено! ⬇️ Остановленная платформа спускается под печь...")

	# Очищаем все отдельные кусочки в контейнере
	if _ingredients_container:
		for child in _ingredients_container.get_children():
			child.queue_free()
	_landed_items.clear()

	if not _is_cooking or _skip_baking_requested or session_id != _cook_session_id:
		return

	_is_lowering = true
	platform_lowering_started.emit()

	# Плавный спуск ОСТАНОВЛЕННОЙ платформы с готовой пиццей вниз под печь (1.4 сек)
	var tw_exit := create_tween()
	_active_tweens.append(tw_exit)
	tw_exit.set_parallel(true)
	tw_exit.tween_property(_platform_rect, "position:y", PLATFORM_EXIT_Y, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_exit.tween_property(_completed_rect, "position:y", PLATFORM_EXIT_Y, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _crust_rim_rect:
		tw_exit.tween_property(_crust_rim_rect, "position:y", PLATFORM_EXIT_Y + _current_crust_offset_y, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw_exit.finished
	_is_lowering = false
	print("[PizzaCooker] Платформа спущена под печь!")


func _drop_batch(disp_idx: int, tex_paths: Array, total_time: float, pattern: String, item_scale: float, session_id: int) -> void:
	var disp: DispenserUnit = _dispensers[disp_idx] if disp_idx < _dispensers.size() else null
	if disp:
		disp.set_dispenser_state(DispenserUnit.State.DISPENSING)

	var count := tex_paths.size()
	if count == 0:
		return
	var interval := clampf((total_time * 0.85) / float(count), 0.08, 0.30)

	for i in range(count):
		if session_id != _cook_session_id or not _is_cooking or _skip_layers_requested or _is_baking:
			break
		if disp: disp.pulse_shoot()
		var p: String = str(tex_paths[i])
		var tex: Texture2D = load(p) as Texture2D if ResourceLoader.exists(p) else null
		if tex:
			_spawn_ingredient(disp_idx, tex, pattern, i, count, item_scale, session_id)
		await get_tree().create_timer(randf_range(interval * 0.85, interval * 1.15)).timeout
		if session_id != _cook_session_id or not _is_cooking or _skip_layers_requested or _is_baking:
			break

	if session_id != _cook_session_id or _skip_layers_requested or _is_baking:
		if disp and not _is_baking: disp.set_dispenser_state(DispenserUnit.State.PREPARED)
		return

	var remain := total_time - (interval * count)
	if remain > 0.05 and _is_cooking and not _skip_layers_requested and not _is_baking and session_id == _cook_session_id:
		await get_tree().create_timer(remain).timeout
	if disp and _is_cooking and not _is_baking and session_id == _cook_session_id:
		disp.set_dispenser_state(DispenserUnit.State.PREPARED)


func _drop_batch_dual(disp1_idx: int, disp2_idx: int, tex_paths: Array, total_time: float, pattern: String, item_scale: float, session_id: int) -> void:
	var d1: DispenserUnit = _dispensers[disp1_idx] if disp1_idx < _dispensers.size() else null
	var d2: DispenserUnit = _dispensers[disp2_idx] if disp2_idx < _dispensers.size() else null
	if d1: d1.set_dispenser_state(DispenserUnit.State.DISPENSING)
	if d2: d2.set_dispenser_state(DispenserUnit.State.DISPENSING)

	var count := tex_paths.size()
	var interval := clampf((total_time * 0.85) / float(maxi(count, 1)), 0.08, 0.30)

	for i in range(count):
		if session_id != _cook_session_id or not _is_cooking or _skip_layers_requested or _is_baking:
			break
		var active_idx := disp1_idx if (i % 2 == 0) else disp2_idx
		var active_disp := d1 if (i % 2 == 0) else d2
		if active_disp: active_disp.pulse_shoot()
		var p: String = str(tex_paths[i])
		var tex: Texture2D = load(p) as Texture2D if ResourceLoader.exists(p) else null
		if tex:
			_spawn_ingredient(active_idx, tex, pattern, i, count, item_scale, session_id)
		await get_tree().create_timer(randf_range(interval * 0.85, interval * 1.15)).timeout
		if session_id != _cook_session_id or not _is_cooking or _skip_layers_requested or _is_baking:
			break

	if session_id != _cook_session_id or _skip_layers_requested or _is_baking:
		if d1 and not _is_baking: d1.set_dispenser_state(DispenserUnit.State.PREPARED)
		if d2 and not _is_baking: d2.set_dispenser_state(DispenserUnit.State.PREPARED)
		return

	if d1 and _is_cooking and not _is_baking and session_id == _cook_session_id:
		d1.set_dispenser_state(DispenserUnit.State.PREPARED)
	if d2 and _is_cooking and not _is_baking and session_id == _cook_session_id:
		d2.set_dispenser_state(DispenserUnit.State.PREPARED)


func _spawn_ingredient(disp_idx: int, tex: Texture2D, pattern: String, idx: int, total: int, final_scale: float, session_id: int) -> void:
	if session_id != _cook_session_id or not _is_cooking or _is_baking or _skip_layers_requested:
		return
	if not _ingredients_container:
		return

	var size_adj := 0.92 if _current_radius_scale < 0.9 else (1.08 if _current_radius_scale > 1.1 else 1.0)
	final_scale *= _current_platform_scale * size_adj
	var start_pos := Vector2(ELLIPSE_CENTER.x, 209.0)
	if disp_idx < _dispensers.size():
		var d := _dispensers[disp_idx]
		start_pos = Vector2(d.position.x + d.size.x * 0.5 + randf_range(-14.0, 14.0), d.position.y + d.size.y + 2.0)

	var polar := _calculate_pattern_polar(pattern, idx, total)
	var r_frac: float = polar.x
	var base_ang: float = polar.y - _rot_angle

	var spr := Sprite2D.new()
	spr.texture = tex
	spr.position = start_pos
	spr.scale = Vector2(0.22 * _current_platform_scale, 0.22 * 0.6 * _current_platform_scale)
	spr.modulate = Color(1, 1, 1, 0.0)
	spr.rotation = randf_range(-PI, PI)
	spr.z_index = 450
	_ingredients_container.add_child(spr)

	var flight_duration := randf_range(0.32, 0.40)
	var tw := create_tween()
	_active_tweens.append(tw)
	tw.set_parallel(true)

	tw.tween_property(spr, "modulate:a", 1.0, 0.08)

	var cur_rx := RX_MAX * _current_radius_scale
	var cur_ry := RY_MAX * _current_radius_scale * _current_dough_aspect_y
	var future_angle := base_ang + _rot_angle + ROT_SPEED * flight_duration
	var target_x := ELLIPSE_CENTER.x + cos(future_angle) * (r_frac * cur_rx)
	var target_y := ELLIPSE_CENTER.y + sin(future_angle) * (r_frac * cur_ry)

	tw.tween_property(spr, "position:x", target_x, flight_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "position:y", target_y, flight_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var bounce_scale := Vector2(final_scale * 1.25, final_scale * 0.75)
	tw.tween_property(spr, "scale", bounce_scale, flight_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if pattern == "spin_leaf":
		tw.tween_property(spr, "rotation", spr.rotation + randf_range(1.5, 3.5), flight_duration)

	tw.chain().tween_callback(func():
		if session_id != _cook_session_id or not is_instance_valid(spr) or not _is_cooking:
			return
		var tw_b := create_tween()
		_active_tweens.append(tw_b)
		tw_b.tween_property(spr, "scale", Vector2(final_scale * 1.20, final_scale * 0.50), 0.05).set_trans(Tween.TRANS_QUAD)
		tw_b.tween_property(spr, "scale", Vector2(final_scale, final_scale * 0.60), 0.12).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

		var item := LandedItem.new()
		item.sprite = spr
		item.r_frac = r_frac
		item.base_angle = base_ang
		item.base_scale = final_scale
		_landed_items.append(item)
	)



func _calculate_pattern_polar(pattern: String, idx: int, total: int) -> Vector2:
	var angle := 0.0
	var r := 0.0
	match pattern:
		"sauce_spiral":
			# Соус наносится спиралью от центра к краям по вращающемуся диску
			if idx == 0:
				angle = 0.0
				r = randf_range(0.0, 0.06)
			else:
				var t := float(idx) / float(maxi(total - 1, 1))
				r = lerpf(0.14, 0.52, t)
				angle = float(idx) * 1.95 + randf_range(-0.08, 0.08)

		"cheese_layer":
			# Сыр равномерно покрывает всю пиццу по 3 концентрическим кольцам
			var ring := idx % 3
			match ring:
				0: r = randf_range(0.16, 0.34)
				1: r = randf_range(0.36, 0.54)
				2: r = randf_range(0.56, 0.72)
			angle = (float(idx) / float(maxi(total, 1))) * TAU + randf_range(-0.15, 0.15)

		"pepperoni_rings":
			if idx == 0:
				angle = 0.0
				r = randf_range(0.0, 0.05)
			elif total <= 11:
				# Маленькая пицца (~10 шт): 1 центр + 3 средний + 6 внешний
				if idx <= 3:
					angle = (float(idx - 1) / 3.0) * TAU + randf_range(-0.06, 0.06)
					r = randf_range(0.34, 0.43)
				else:
					angle = (float(idx - 4) / float(maxi(total - 4, 1))) * TAU + 0.30 + randf_range(-0.06, 0.06)
					r = randf_range(0.62, 0.72)
			elif total >= 18:
				# Большая пицца (~20 шт): 1 центр + 6 средний + 13 внешний
				if idx <= 6:
					angle = (float(idx - 1) / 6.0) * TAU + randf_range(-0.06, 0.06)
					r = randf_range(0.35, 0.45)
				else:
					angle = (float(idx - 7) / float(maxi(total - 7, 1))) * TAU + 0.25 + randf_range(-0.06, 0.06)
					r = randf_range(0.64, 0.75)
			else:
				# Средняя пицца (14 шт): 1 центр + 5 средний + 8 внешний
				if idx <= 5:
					angle = (float(idx - 1) / 5.0) * TAU + randf_range(-0.06, 0.06)
					r = randf_range(0.36, 0.44)
				else:
					angle = (float(idx - 6) / float(maxi(total - 6, 1))) * TAU + 0.32 + randf_range(-0.06, 0.06)
					r = randf_range(0.63, 0.73)

		"margarita_cheese":
			# Моцарелла: 1 в центре + 7 ровным венком вокруг
			if idx == 0:
				angle = 0.0
				r = randf_range(0.0, 0.05)
			else:
				angle = (float(idx - 1) / float(maxi(total - 1, 1))) * TAU + randf_range(-0.08, 0.08)
				r = randf_range(0.44, 0.54)

		"bacon_ring":
			# Бекон: 4 во внутреннем кольце + 8 во внешнем кольце
			if idx < 4:
				angle = (float(idx) / 4.0) * TAU + randf_range(-0.1, 0.1)
				r = randf_range(0.34, 0.45)
			else:
				angle = (float(idx - 4) / float(maxi(total - 4, 1))) * TAU + 0.35 + randf_range(-0.1, 0.1)
				r = randf_range(0.58, 0.70)

		"chicken_pieces":
			# Курица/наггетсы: 1 в центре + 4 внутренний круг + 7 внешний круг
			if idx == 0:
				angle = 0.0
				r = randf_range(0.0, 0.05)
			elif idx <= 4:
				angle = (float(idx - 1) / 4.0) * TAU + randf_range(-0.08, 0.08)
				r = randf_range(0.35, 0.46)
			else:
				angle = (float(idx - 5) / float(maxi(total - 5, 1))) * TAU + 0.30 + randf_range(-0.08, 0.08)
				r = randf_range(0.60, 0.72)

		"onion_rings":
			# Кольца лука: венок по среднему радиусу
			angle = (float(idx) / float(maxi(total, 1))) * TAU + randf_range(-0.2, 0.2)
			r = randf_range(0.32, 0.60)

		"pepper_scatter":
			# Болгарский перец: разноцветная россыпь по всей пицце
			angle = (float(idx) / float(maxi(total, 1))) * TAU + randf_range(-0.25, 0.25)
			r = randf_range(0.20, 0.72)

		"herbs_top":
			# Листики базилика и зелени: сверху поверх начинки
			angle = (float(idx) / float(maxi(total, 1))) * TAU + 0.25 + randf_range(-0.12, 0.12)
			r = randf_range(0.36, 0.64)

		_:
			angle = randf_range(0.0, TAU)
			r = randf_range(0.20, 0.68)
	return Vector2(r, angle)



func is_in_baking_phase() -> bool:
	return _is_baking or _skip_layers_requested


func is_lowering() -> bool:
	return _is_lowering


func skip_to_baking() -> void:
	if _is_baking or not _is_cooking:
		return
	print("[PizzaCooker] ⏭️ Скип раскладки -> переход к запеканию!")
	AudioManager.stop_cooking_groove()
	_skip_layers_requested = true
	for tw in _active_tweens:
		if is_instance_valid(tw): tw.kill()
	_active_tweens.clear()
	# При скипе: любые кусочки, не успевшие приземлиться на пиццу (в воздухе), сразу удаляются
	if _ingredients_container:
		for child in _ingredients_container.get_children():
			if child is Sprite2D and is_instance_valid(child):
				var landed := false
				for it in _landed_items:
					if it.sprite == child:
						landed = true
						break
				if not landed:
					child.queue_free()


func skip_to_finish() -> void:
	if not _is_cooking:
		return
	print("[PizzaCooker] ⏭️ Скип запекания -> моментальная выдача!")
	_cook_session_id += 1
	AudioManager.stop_cooking_groove()
	AudioManager.stop_oven_baking()
	_skip_baking_requested = true
	for tw in _active_tweens:
		if is_instance_valid(tw): tw.kill()
	_active_tweens.clear()
	var comp_tex: Texture2D = _completed_textures.get(_current_pizza_name, _completed_textures.get("Пепперони", null))
	if comp_tex and _completed_rect:
		_completed_rect.texture = comp_tex
		_completed_rect.modulate = Color.WHITE
		if _bake_material:
			_bake_material.set_shader_parameter("progress", 1.0)
	if _ingredients_container:
		for child in _ingredients_container.get_children():
			child.queue_free()
	_landed_items.clear()
	var final_sc := Vector2(_current_platform_scale, _current_platform_scale * _current_dough_aspect_y)
	if _platform_rect:
		_platform_rect.scale = final_sc
		_platform_rect.position.y = PLATFORM_EXIT_Y
	if _completed_rect:
		_completed_rect.scale = final_sc
		_completed_rect.position.y = PLATFORM_EXIT_Y
	if _crust_rim_rect:
		_crust_rim_rect.scale = final_sc
		_crust_rim_rect.position.y = PLATFORM_EXIT_Y + _current_crust_offset_y
	_is_baking = false
	_is_lowering = false
	cooking_completed.emit()

func stop() -> void:
	_cleanup()
	visible = false


func _cleanup() -> void:
	_cook_session_id += 1
	_is_cooking = false
	_is_baking = false
	_is_lowering = false
	_skip_layers_requested = false
	_skip_baking_requested = false
	AudioManager.stop_cooking_groove()
	AudioManager.stop_oven_baking()
	for tw in _active_tweens:
		if is_instance_valid(tw): tw.kill()
	_active_tweens.clear()
	if _ingredients_container:
		for child in _ingredients_container.get_children():
			child.queue_free()
	_landed_items.clear()
	if _bake_material:
		_bake_material.set_shader_parameter("progress", 0.0)
	_update_platform_transforms()
	if _completed_rect:
		_completed_rect.modulate = Color.WHITE
	for d in _dispensers:
		d.set_dispenser_state(DispenserUnit.State.PREPARED)
