class_name PizzaCooker
extends Node2D
## Компонент вращающегося вала и приготовления пиццы в камере печи (OvenZone).
## 1. Вращающийся вал с тестом (кадры stove_platform_1..6 по часовой стрелке).
## 2. Изометрическая раскладка ингредиентов слоями из 4-х сопел диспенсеров.
## 3. 5-секундная фаза запекания (ТЭНы, золотистая корочка, пар).

signal cooking_layer_started(layer_name: String, dispenser_idx: int)
signal baking_started
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
var _platform_rect: TextureRect
var _completed_rect: TextureRect
var _platform_frames: Array[Texture2D] = []
var _completed_textures: Dictionary = {}

var _cur_frame := 0
var _frame_timer := 0.0
const FRAME_DURATION := 0.12

var _baking_heat_overlay: TextureRect
var _steam_container: Node2D

var _is_cooking := false
var _is_baking := false
var _skip_layers_requested := false
var _skip_baking_requested := false
var _rot_angle := 0.0
const ROT_SPEED := 0.55

var _current_pizza_name := ""
var _cook_time_elapsed := 0.0
var _active_tweens: Array[Tween] = []

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
	# 1. Вращающийся вал с пустым тестом
	_platform_rect = TextureRect.new()
	_platform_rect.name = "StovePlatform"
	_platform_rect.position = Vector2(PLATFORM_X, PLATFORM_START_Y)
	_platform_rect.size = Vector2(820, 400)
	_platform_rect.scale = Vector2(PLATFORM_SCALE, PLATFORM_SCALE)
	_platform_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_platform_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_platform_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_platform_rect.z_index = 5
	if _platform_frames.size() > 0:
		_platform_rect.texture = _platform_frames[0]
	add_child(_platform_rect)

	# 2. Оверлей готовой запеченной пиццы (проявляется на 14-й секунде)
	_completed_rect = TextureRect.new()
	_completed_rect.name = "StovePlatformCompleted"
	_completed_rect.position = Vector2(PLATFORM_X, PLATFORM_START_Y)
	_completed_rect.size = Vector2(820, 400)
	_completed_rect.scale = Vector2(PLATFORM_SCALE, PLATFORM_SCALE)
	_completed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_completed_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_completed_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_completed_rect.modulate.a = 0.0
	_completed_rect.z_index = 6
	add_child(_completed_rect)

	# 3. Мягкий градиентный жар от ТЭНов (строго над пиццей и под корпусом)
	_baking_heat_overlay = TextureRect.new()
	_baking_heat_overlay.name = "BakingHeat"
	_baking_heat_overlay.position = Vector2(PLATFORM_X, PLATFORM_START_Y - 20.0)
	_baking_heat_overlay.size = Vector2(PLATFORM_W, PLATFORM_H + 40.0)
	_baking_heat_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_baking_heat_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_baking_heat_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_baking_heat_overlay.z_index = 8
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.55, 0.1, 0.0))       # Верх: прозрачный
	grad.add_point(0.65, Color(1.0, 0.38, 0.05, 0.15))   # Середина: нежный золотистый отсвет
	grad.set_color(1, Color(1.0, 0.22, 0.02, 0.26))     # Низ ТЭНов: легкий теплый накал
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0.5, 0.0)
	grad_tex.fill_to = Vector2(0.5, 1.0)
	grad_tex.width = 128
	grad_tex.height = 128
	_baking_heat_overlay.texture = grad_tex
	_baking_heat_overlay.modulate.a = 0.0
	add_child(_baking_heat_overlay)

	# 4. Пар
	_steam_container = Node2D.new()
	_steam_container.name = "SteamContainer"
	_steam_container.z_index = 510
	add_child(_steam_container)

	visible = false


func setup_dispensers(dispensers: Array[DispenserUnit]) -> void:
	_dispensers = dispensers


func _process(delta: float) -> void:
	if not _is_cooking:
		return

	# Анимация вращения вала по часовой стрелке
	if _platform_frames.size() > 0:
		_frame_timer += delta
		if _frame_timer >= FRAME_DURATION:
			_frame_timer = 0.0
			_cur_frame = (_cur_frame + 1) % _platform_frames.size()
			_platform_rect.texture = _platform_frames[_cur_frame]

	# Вращение ингредиентов по эллипсу
	_rot_angle += ROT_SPEED * delta
	for item in _landed_items:
		if not is_instance_valid(item.sprite):
			continue
		var a := item.base_angle + _rot_angle
		var px := ELLIPSE_CENTER.x + cos(a) * (item.r_frac * RX_MAX)
		var py := ELLIPSE_CENTER.y + sin(a) * (item.r_frac * RY_MAX)
		item.sprite.position = Vector2(px, py)
		item.sprite.scale.x = item.base_scale
		item.sprite.scale.y = item.base_scale * (0.60 + sin(a) * 0.05)
		item.sprite.z_index = 20 + int(py)

	if _is_baking:
		_cook_time_elapsed += delta
		var heat_pulse := 0.65 + 0.15 * sin(_cook_time_elapsed * 5.0)
		_baking_heat_overlay.modulate.a = clampf(heat_pulse, 0.0, 0.85)


func start_cooking(order: Order) -> void:
	_cleanup()
	visible = true
	_is_cooking = true
	_is_baking = false
	_skip_layers_requested = false
	_skip_baking_requested = false
	_cook_time_elapsed = 0.0
	_rot_angle = 0.0
	_cur_frame = 0

	_current_pizza_name = _detect_pizza_type(order)
	print("[PizzaCooker] Старт готовки: %s" % _current_pizza_name)
	_run_cooking_sequence(_current_pizza_name)


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


func _run_cooking_sequence(pizza_type: String) -> void:
	match pizza_type:
		"Карбонара": await _cook_carbonara()
		"Чикен Бомбони": await _cook_chicken_bomboni()
		"Маргарита": await _cook_margarita()
		"Пепперони": await _cook_pepperoni()
		_: await _cook_pepperoni()

	if not _is_cooking: return
	if _skip_baking_requested: return
	await _start_baking_phase()
	if _is_cooking and not _skip_baking_requested:
		cooking_completed.emit()


func _cook_carbonara() -> void:
	cooking_layer_started.emit("Соусная основа", 0)
	var cheese_paths := [
		"res://assets/textures/ingredients/carbonara/carbonara_cheese.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese2.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese3.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese2.png",
		"res://assets/textures/ingredients/carbonara/carbonara_cheese3.png"
	]
	await _drop_batch(0, cheese_paths, 2.8, "fan_center", 0.48)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Мясо", 1)
	var meat_paths: Array = []
	for r in range(2):
		for i in range(1, 7):
			var suffix := "" if i == 1 else str(i)
			meat_paths.append("res://assets/textures/ingredients/carbonara/carbonara_meat%s.png" % suffix)
	await _drop_batch(1, meat_paths, 2.8, "circle", 0.44)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Лук", 2)
	var onion_paths: Array = []
	for r in range(2):
		for i in range(1, 5):
			var suffix := "" if i == 1 else str(i)
			onion_paths.append("res://assets/textures/ingredients/carbonara/carbonara_onion%s.png" % suffix)
	await _drop_batch(2, onion_paths, 2.8, "scatter_mid", 0.38)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Сырная крошка", 3)
	var part_paths: Array = []
	for r in range(3):
		for i in range(1, 6):
			part_paths.append("res://assets/textures/ingredients/carbonara/carbonara_cheese_part%d.png" % i)
	await _drop_batch(3, part_paths, 2.8, "scatter_wide", 0.34)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Зелень", 0)
	var herb_paths: Array = []
	for r in range(2):
		for i in range(1, 5):
			var suffix := "" if i == 1 else str(i)
			herb_paths.append("res://assets/textures/ingredients/carbonara/carbonara_herbs%s.png" % suffix)
	await _drop_batch_dual(0, 1, herb_paths, 2.8, "rain", 0.38)


func _cook_chicken_bomboni() -> void:
	cooking_layer_started.emit("Соус", 0)
	var sauce_paths := [
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce2.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce2.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce.png",
		"res://assets/textures/ingredients/chickenbomb/chicken_bomboni_sauce2.png"
	]
	await _drop_batch(0, sauce_paths, 2.8, "center_spot", 0.52)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Лук", 1)
	var onion_paths: Array = []
	for r in range(3):
		for i in range(1, 4):
			var suffix := "" if i == 1 else str(i)
			onion_paths.append("res://assets/textures/ingredients/chickenbomb/chicken_bomboni_onion%s.png" % suffix)
	await _drop_batch(1, onion_paths, 2.8, "scatter_mid", 0.38)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Перец", 2)
	var pepper_paths: Array = []
	for r in range(2):
		for i in range(1, 9):
			var suffix := "" if i == 1 else str(i)
			pepper_paths.append("res://assets/textures/ingredients/chickenbomb/chicken_bomboni_pepper%s.png" % suffix)
	await _drop_batch(2, pepper_paths, 3.4, "burst_all", 0.32)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Куриные наггетсы", 3)
	var nugget_paths: Array = []
	for r in range(2):
		for i in range(1, 6):
			nugget_paths.append("res://assets/textures/ingredients/chickenbomb/chicken_bomboni_nugget%d.png" % i)
	await _drop_batch(3, nugget_paths, 5.0, "circle_bounce", 0.45)




func _cook_margarita() -> void:
	cooking_layer_started.emit("Томатный соус", 0)
	var sauce_paths := [
		"res://assets/textures/ingredients/margarita/margarita_sauce.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce2.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce3.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce2.png",
		"res://assets/textures/ingredients/margarita/margarita_sauce3.png"
	]
	await _drop_batch(0, sauce_paths, 3.0, "fan_center", 0.52)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Сыр Моцарелла", 1)
	var cheese_paths := [
		"res://assets/textures/ingredients/margarita/margarita_cheese.png",
		"res://assets/textures/ingredients/margarita/margarita_cheese2.png",
		"res://assets/textures/ingredients/margarita/margarita_cheese.png",
		"res://assets/textures/ingredients/margarita/margarita_cheese2.png",
		"res://assets/textures/ingredients/margarita/margarita_cheese.png",
		"res://assets/textures/ingredients/margarita/margarita_cheese2.png"
	]
	await _drop_batch(1, cheese_paths, 3.0, "center_spot", 0.46)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Оливковое масло", 2)
	var oil_paths: Array = []
	for r in range(2):
		for i in range(1, 5):
			var suffix := "" if i == 1 else str(i)
			oil_paths.append("res://assets/textures/ingredients/margarita/margarita_oil%s.png" % suffix)
	await _drop_batch(2, oil_paths, 4.0, "scatter_wide", 0.36)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Базилик", 3)
	var bazilik_paths: Array = []
	for r in range(2):
		for i in range(1, 5):
			var suffix := "" if i == 1 else str(i)
			bazilik_paths.append("res://assets/textures/ingredients/margarita/margarita_bazilik%s.png" % suffix)
	await _drop_batch(3, bazilik_paths, 4.0, "spin_leaf", 0.40)


func _cook_pepperoni() -> void:
	cooking_layer_started.emit("Томатный соус", 0)
	var sauce_paths := [
		"res://assets/textures/ingredients/pepperoni/margarita_sauce.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce2.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce3.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce2.png",
		"res://assets/textures/ingredients/pepperoni/margarita_sauce3.png"
	]
	await _drop_batch(0, sauce_paths, 2.5, "fan_center", 0.50)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Сырная основа", 1)
	var cheese_paths: Array = []
	for r in range(2):
		for i in range(1, 6):
			cheese_paths.append("res://assets/textures/ingredients/pepperoni/carbonara_cheese_part%d.png" % i)
	await _drop_batch(1, cheese_paths, 2.5, "scatter_wide", 0.36)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Лук", 2)
	var onion_paths: Array = []
	for r in range(2):
		onion_paths.append("res://assets/textures/ingredients/pepperoni/pepperoni_onion.png")
		onion_paths.append("res://assets/textures/ingredients/pepperoni/carbonara_onion2.png")
		onion_paths.append("res://assets/textures/ingredients/pepperoni/carbonara_onion3.png")
		onion_paths.append("res://assets/textures/ingredients/pepperoni/carbonara_onion4.png")
	await _drop_batch(2, onion_paths, 2.5, "scatter_mid", 0.38)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Пряный перец", 3)
	var pepper_paths: Array = []
	for r in range(2):
		for i in range(1, 7):
			var suffix := "" if i == 1 else str(i)
			pepper_paths.append("res://assets/textures/ingredients/pepperoni/pepperoni_pepper%s.png" % suffix)
		for i in range(1, 4):
			var suffix := "" if i == 1 else str(i)
			pepper_paths.append("res://assets/textures/ingredients/pepperoni/chicken_bomboni_pepper%s.png" % suffix)
	await _drop_batch(3, pepper_paths, 3.0, "burst_all", 0.32)
	if not _is_cooking or _skip_layers_requested: return

	cooking_layer_started.emit("Пепперони", 0)
	var meat_paths: Array = []
	# 11 кругляшей пепперони (1 в центре, 4 внутренний круг, 6 внешний круг)
	for i in range(1, 6):
		meat_paths.append("res://assets/textures/ingredients/pepperoni/pepperoni_meat%d.png" % i)
	for i in range(1, 7):
		var idx := ((i - 1) % 5) + 1
		meat_paths.append("res://assets/textures/ingredients/pepperoni/pepperoni_meat%d.png" % idx)
	await _drop_batch_dual(0, 3, meat_paths, 3.5, "circle_bounce", 0.46)


func _start_baking_phase() -> void:
	_is_baking = true
	baking_started.emit()
	print("[PizzaCooker] 🔥 ЗАПЕКАНИЕ: ТЭНы активированы!")

	for d in _dispensers:
		d.set_dispenser_state(DispenserUnit.State.PREPARED)

	# Накладываем текстуру готовой пиццы и запускаем мягкий переход
	var comp_tex: Texture2D = _completed_textures.get(_current_pizza_name, _completed_textures.get("Пепперони", null))
	if comp_tex and _completed_rect:
		_completed_rect.texture = comp_tex
		var tw_fade := create_tween()
		_active_tweens.append(tw_fade)
		tw_fade.tween_property(_completed_rect, "modulate:a", 1.0, 3.0).set_trans(Tween.TRANS_SINE)
		for item in _landed_items:
			if is_instance_valid(item.sprite):
				tw_fade.parallel().tween_property(item.sprite, "modulate:a", 0.0, 2.6)

	if _baking_heat_overlay:
		var tw_heat := create_tween()
		_active_tweens.append(tw_heat)
		tw_heat.tween_property(_baking_heat_overlay, "modulate:a", 0.70, 0.8)

	_spawn_steam_particles()

	var bake_timer := 4.0
	while bake_timer > 0.0 and _is_cooking and not _skip_baking_requested:
		await get_tree().create_timer(0.2).timeout
		bake_timer -= 0.2

	if _skip_baking_requested or not _is_cooking:
		return

	if _baking_heat_overlay:
		var tw_cool := create_tween()
		tw_cool.tween_property(_baking_heat_overlay, "modulate:a", 0.0, 0.6)
		_active_tweens.append(tw_cool)

	_is_baking = false
	print("[PizzaCooker] Запекание завершено! ⬇️ Спуск платформы под печь к выходу для упаковки...")

	# Очищаем отдельные кусочки, так как готовая текстура уже полностью проявилась
	for item in _landed_items:
		if is_instance_valid(item.sprite):
			item.sprite.queue_free()
	_landed_items.clear()

	if not _is_cooking or _skip_baking_requested:
		return

	# Плавный спуск платформы с готовой пиццей вниз под печь
	var tw_exit := create_tween()
	_active_tweens.append(tw_exit)
	tw_exit.set_parallel(true)
	tw_exit.tween_property(_platform_rect, "position:y", PLATFORM_EXIT_Y, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_exit.tween_property(_completed_rect, "position:y", PLATFORM_EXIT_Y, 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw_exit.finished
	print("[PizzaCooker] Платформа спущена под печь!")


func _spawn_steam_particles() -> void:
	for i in range(12):
		if not _is_cooking or not _is_baking: break
		var steam_dot := ColorRect.new()
		steam_dot.size = Vector2(randf_range(8, 16), randf_range(8, 16))
		steam_dot.color = Color(1.0, 1.0, 1.0, 0.28)
		steam_dot.position = ELLIPSE_CENTER + Vector2(randf_range(-120, 120), randf_range(-40, 40))
		_steam_container.add_child(steam_dot)

		var tw := create_tween()
		tw.tween_property(steam_dot, "position:y", steam_dot.position.y - randf_range(60, 120), 1.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(steam_dot, "color:a", 0.0, 1.8)
		tw.parallel().tween_property(steam_dot, "scale", Vector2(2.5, 2.5), 1.8)
		tw.tween_callback(steam_dot.queue_free)
		_active_tweens.append(tw)

		await get_tree().create_timer(randf_range(0.3, 0.45)).timeout


func _drop_batch(disp_idx: int, tex_paths: Array, total_time: float, pattern: String, item_scale: float) -> void:
	var disp: DispenserUnit = _dispensers[disp_idx] if disp_idx < _dispensers.size() else null
	if disp:
		disp.set_dispenser_state(DispenserUnit.State.DISPENSING)

	var count := tex_paths.size()
	if count == 0:
		return
	var interval := clampf((total_time * 0.85) / float(count), 0.08, 0.30)

	for i in range(count):
		if not _is_cooking or _skip_layers_requested: break
		if disp: disp.pulse_shoot()
		var p: String = str(tex_paths[i])
		var tex: Texture2D = load(p) as Texture2D if ResourceLoader.exists(p) else null
		if tex:
			_spawn_ingredient(disp_idx, tex, pattern, i, count, item_scale)
		await get_tree().create_timer(randf_range(interval * 0.85, interval * 1.15)).timeout

	if _skip_layers_requested:
		if disp and not _is_baking: disp.set_dispenser_state(DispenserUnit.State.PREPARED)
		return

	var remain := total_time - (interval * count)
	if remain > 0.05 and _is_cooking and not _skip_layers_requested:
		await get_tree().create_timer(remain).timeout
	if disp and _is_cooking and not _is_baking:
		disp.set_dispenser_state(DispenserUnit.State.PREPARED)


func _drop_batch_dual(disp1_idx: int, disp2_idx: int, tex_paths: Array, total_time: float, pattern: String, item_scale: float) -> void:
	var d1: DispenserUnit = _dispensers[disp1_idx] if disp1_idx < _dispensers.size() else null
	var d2: DispenserUnit = _dispensers[disp2_idx] if disp2_idx < _dispensers.size() else null
	if d1: d1.set_dispenser_state(DispenserUnit.State.DISPENSING)
	if d2: d2.set_dispenser_state(DispenserUnit.State.DISPENSING)

	var count := tex_paths.size()
	var interval := clampf((total_time * 0.85) / float(maxi(count, 1)), 0.08, 0.30)

	for i in range(count):
		if not _is_cooking or _skip_layers_requested: break
		var active_idx := disp1_idx if (i % 2 == 0) else disp2_idx
		var active_disp := d1 if (i % 2 == 0) else d2
		if active_disp: active_disp.pulse_shoot()
		var p: String = str(tex_paths[i])
		var tex: Texture2D = load(p) as Texture2D if ResourceLoader.exists(p) else null
		if tex:
			_spawn_ingredient(active_idx, tex, pattern, i, count, item_scale)
		await get_tree().create_timer(randf_range(interval * 0.85, interval * 1.15)).timeout

	if _skip_layers_requested:
		if d1 and not _is_baking: d1.set_dispenser_state(DispenserUnit.State.PREPARED)
		if d2 and not _is_baking: d2.set_dispenser_state(DispenserUnit.State.PREPARED)
		return

	if d1 and _is_cooking: d1.set_dispenser_state(DispenserUnit.State.PREPARED)
	if d2 and _is_cooking: d2.set_dispenser_state(DispenserUnit.State.PREPARED)


func _spawn_ingredient(disp_idx: int, tex: Texture2D, pattern: String, idx: int, total: int, final_scale: float) -> void:
	final_scale *= PLATFORM_SCALE
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
	spr.scale = Vector2(0.22 * PLATFORM_SCALE, 0.22 * 0.6 * PLATFORM_SCALE)
	spr.modulate = Color(1, 1, 1, 0.0)
	spr.rotation = randf_range(-PI, PI)
	spr.z_index = 450
	add_child(spr)

	var flight_duration := randf_range(0.32, 0.40)
	var tw := create_tween()
	_active_tweens.append(tw)

	tw.tween_property(spr, "modulate:a", 1.0, 0.08)

	var future_angle := base_ang + _rot_angle + ROT_SPEED * flight_duration
	var target_x := ELLIPSE_CENTER.x + cos(future_angle) * (r_frac * RX_MAX)
	var target_y := ELLIPSE_CENTER.y + sin(future_angle) * (r_frac * RY_MAX)

	tw.parallel().tween_property(spr, "position:x", target_x, flight_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spr, "position:y", target_y, flight_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var bounce_scale := Vector2(final_scale * 1.25, final_scale * 0.75)
	tw.parallel().tween_property(spr, "scale", bounce_scale, flight_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if pattern == "spin_leaf":
		tw.parallel().tween_property(spr, "rotation", spr.rotation + randf_range(1.5, 3.5), flight_duration)

	tw.tween_callback(func():
		if not is_instance_valid(spr) or not _is_cooking: return
		var tw_b := create_tween()
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
		"fan_center":
			# Веер соуса вокруг центра
			angle = (float(idx) / float(maxi(total, 1))) * TAU + randf_range(-0.15, 0.15)
			r = randf_range(0.12, 0.32)
		"center_spot":
			# Пятно соуса в центре
			if idx == 0:
				angle = 0.0
				r = randf_range(0.0, 0.10)
			else:
				angle = (float(idx) / float(maxi(total, 1))) * TAU
				r = randf_range(0.20, 0.35)
		"circle":
			# Мясо по ровному кругу
			angle = (float(idx) / float(maxi(total, 1))) * TAU + randf_range(-0.08, 0.08)
			r = randf_range(0.52, 0.65)
		"circle_bounce":
			# Пепперони/наггетсы: 1 в центре + внутреннее кольцо (4 шт) + внешнее кольцо (6 шт)
			if idx == 0:
				angle = 0.0
				r = randf_range(0.0, 0.08)
			elif idx <= 4:
				angle = (float(idx - 1) / 4.0) * TAU + randf_range(-0.1, 0.1)
				r = randf_range(0.38, 0.50)
			else:
				angle = (float(idx - 5) / float(maxi(total - 5, 1))) * TAU + 0.35 + randf_range(-0.1, 0.1)
				r = randf_range(0.66, 0.82)
		"scatter_mid":
			# Кольца лука
			angle = (float(idx) / float(maxi(total, 1))) * TAU + randf_range(-0.3, 0.3)
			r = randf_range(0.30, 0.65)
		"scatter_wide":
			# Сырная крошка / сыр по всей площади
			angle = randf_range(0.0, TAU)
			r = randf_range(0.15, 0.82)
		"burst_all":
			# Перец: россыпь по всей площади
			angle = (float(idx) / float(maxi(total, 1))) * TAU + randf_range(-0.25, 0.25)
			r = randf_range(0.18, 0.84)
		"rain":
			# Зелень сверху
			angle = (float(idx) / float(maxi(total, 1))) * TAU + randf_range(-0.2, 0.2)
			r = randf_range(0.25, 0.75)
		"spin_leaf":
			# Листики базилика
			angle = (float(idx) / float(maxi(total, 1))) * TAU + 0.35 + randf_range(-0.1, 0.1)
			r = randf_range(0.42, 0.68)
		_:
			angle = randf_range(0.0, TAU)
			r = randf_range(0.20, 0.70)
	return Vector2(r, angle)



func is_in_baking_phase() -> bool:
	return _is_baking or _skip_layers_requested


func skip_to_baking() -> void:
	if _is_baking or not _is_cooking:
		return
	print("[PizzaCooker] ⏭️ Скип раскладки -> переход к запеканию!")
	_skip_layers_requested = true
	for tw in _active_tweens:
		if is_instance_valid(tw): tw.kill()
	_active_tweens.clear()


func skip_to_finish() -> void:
	if not _is_cooking:
		return
	print("[PizzaCooker] ⏭️ Скип запекания -> моментальная выдача!")
	_skip_baking_requested = true
	for tw in _active_tweens:
		if is_instance_valid(tw): tw.kill()
	_active_tweens.clear()
	var comp_tex: Texture2D = _completed_textures.get(_current_pizza_name, _completed_textures.get("Пепперони", null))
	if comp_tex and _completed_rect:
		_completed_rect.texture = comp_tex
		_completed_rect.modulate.a = 1.0
	for item in _landed_items:
		if is_instance_valid(item.sprite):
			item.sprite.queue_free()
	_landed_items.clear()
	if _baking_heat_overlay:
		_baking_heat_overlay.modulate.a = 0.0
	if _platform_rect:
		_platform_rect.position.y = PLATFORM_EXIT_Y
	if _completed_rect:
		_completed_rect.position.y = PLATFORM_EXIT_Y
	_is_baking = false
	cooking_completed.emit()

func stop() -> void:
	_cleanup()
	visible = false


func _cleanup() -> void:
	_is_cooking = false
	_is_baking = false
	_skip_layers_requested = false
	_skip_baking_requested = false
	for tw in _active_tweens:
		if is_instance_valid(tw): tw.kill()
	_active_tweens.clear()
	for item in _landed_items:
		if is_instance_valid(item.sprite):
			item.sprite.queue_free()
	_landed_items.clear()
	if _steam_container:
		for child in _steam_container.get_children():
			child.queue_free()
	if _baking_heat_overlay:
		_baking_heat_overlay.modulate.a = 0.0
	if _platform_rect:
		_platform_rect.position = Vector2(PLATFORM_X, PLATFORM_START_Y)
	if _completed_rect:
		_completed_rect.position = Vector2(PLATFORM_X, PLATFORM_START_Y)
		_completed_rect.modulate.a = 0.0
	for d in _dispensers:
		d.set_dispenser_state(DispenserUnit.State.PREPARED)
