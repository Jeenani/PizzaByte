extends Control
# ═══════════════════════════════════════════════════════════
#  🍕 PIZZA MARKET — 2D пиццемат-симулятор
#  Каркас whole_body.png (1614×1536) на фоне улицы (2752×1536)
#  Панель заказа: ScreenPanel (Node2D + ClickableSprite)
#  Неоновая вывеска: NeonSign (шейдерное мерцание)
#  Камера: плавный зум от общего фона к автомату по скроллу
# ═══════════════════════════════════════════════════════════

const BODY_W := 1614.0
const BODY_H := 1536.0

const BG_W := 2752.0
const BG_H := 1536.0
const BG_CENTER := Vector2(1376.0, 768.0)

# Позиционирование автомата на фоне (человеческий размер у стены)
const MACHINE_POS := Vector2(130.0, 410.0)
const MACHINE_SCALE := 0.57
const MACHINE_W := BODY_W * MACHINE_SCALE # 919.98
const MACHINE_H := BODY_H * MACHINE_SCALE # 875.52
# Центр автомата в мировых координатах (с легким смещением в сторону сенсорного экрана)
const MACHINE_CENTER := Vector2(130.0 + MACHINE_W * 0.52, 410.0 + MACHINE_H * 0.48)
const MACHINE_FOCUS_CENTER := Vector2(130.0 + MACHINE_W * 0.54, 410.0 + MACHINE_H * 0.46)

const SCREEN_RECT := Rect2(1044, 220, 432, 924)
const OVEN_RECT := Rect2(100, 270, 820, 660)
const DISPENSE_RECT := Rect2(220, 1150, 580, 160)
const DISPENSE_SIGN_RECT := Rect2(240, 1016, 570, 54)
const BAR_RECT := Rect2(12, 1320, 640, 120)
const FURNACE_RECT := Rect2(1330, 1348, 124, 100)
const LOGO_RECT := Rect2(150, 76, 550, 170)

# Управление камерой (зум: 0.0 = максимальное отдаление фона, 1.0 = полный масштаб автомата во весь экран)
var _zoom_t: float = 0.0
var _target_zoom_t: float = 0.0
const ZOOM_STEP := 0.15

@onready var cam: Camera2D = $MainCamera
@onready var bg: TextureRect = $Background
@onready var bg_left: TextureRect = get_node_or_null("BackgroundLeft")
@onready var bg_right: TextureRect = get_node_or_null("BackgroundRight")
@onready var machine: MachineController = $MachineController
@onready var order_mgr: Node = $OrderManager
@onready var queue_mgr: Node = $QueueManager
@onready var body: TextureRect = $MachineBody
@onready var oven_zone: Control = $MachineBody/OvenZone
@onready var screen_zone: Control = $MachineBody/ScreenZone
@onready var dispense_zone: Control = $MachineBody/DispenseZone
@onready var bottom_bar: Control = $MachineBody/BottomBar
@onready var furnace_zone: Control = $MachineBody/FurnaceZone
@onready var furnace_indicator: TextureRect = $MachineBody/FurnaceZone/FurnaceIndicator
@onready var cook_progress: ProgressBar = $MachineBody/OvenZone/CookProgress
@onready var cook_status: Label = $MachineBody/OvenZone/CookStatus
@onready var cook_timer: Label = $MachineBody/OvenZone/CookTimer
@onready var screen_content: VBoxContainer = $MachineBody/ScreenZone/ScreenContent
@onready var next_button: Button = $MachineBody/ScreenZone/ScreenContent/NextButton
@onready var pizza_box: TextureRect = $MachineBody/DispenseZone/PizzaBox
@onready var oven_interior: TextureRect = $MachineBody/OvenZone/OvenInterior
@onready var ingredients_zone: Control = $MachineBody/IngredientsZone

var _game_data: Node
var _panel: ScreenPanel
var _neon: NeonSign
var _dispense_sign: DispenseSign
var _dispensers: Array[DispenserUnit] = []
const PizzaCookerScript := preload("res://scripts/components/pizza_cooker.gd")
const DispenseSignScript := preload("res://scripts/components/dispense_sign.gd")
var _cooker: Node2D
var _oven_heat_tween: Tween


# ── Текстуры камеры печи ──
var _cam_off: Texture2D
var _cam_enabled: Texture2D
var _cam_cooking: Texture2D
var _cam_completed: Texture2D

# ── Текстуры индикатора печи ──
var _furnace_ind0: Texture2D
var _furnace_ind1: Texture2D
var _furnace_ind2: Texture2D
var _cook_indicator_time: float = 0.0


func _ready() -> void:
	# Установить иконку окна приложения
	var app_icon_tex := load("res://app_ico.png") as Texture2D
	if app_icon_tex:
		var app_icon := app_icon_tex.get_image()
		if app_icon:
			DisplayServer.set_icon(app_icon)


	_game_data = get_node_or_null("/root/GameData")
	# Загрузить текстуры камеры печи
	_cam_off = load("res://assets/textures/machine/camera_pizzing_off.png")
	_cam_enabled = load("res://assets/textures/machine/camera_pizzing_enabled.png")
	_cam_cooking = load("res://assets/textures/machine/camera_pizzing_cooking.png")
	_cam_completed = load("res://assets/textures/machine/camera_pizzing_completed.png")
	# Загрузить текстуры индикатора печи
	_furnace_ind0 = load("res://assets/textures/indicator/furnace_indicator0.png")
	_furnace_ind1 = load("res://assets/textures/indicator/furnace_indicator1.png")
	_furnace_ind2 = load("res://assets/textures/indicator/furnace_indicator2.png")
	_set_furnace_indicator(_furnace_ind0)

	# Скрыть старый Godot UI — используем только ScreenPanel
	ingredients_zone.visible = false
	screen_content.visible = false
	next_button.visible = false
	pizza_box.visible = false
	pizza_box.mouse_filter = Control.MOUSE_FILTER_STOP
	pizza_box.gui_input.connect(_on_pizza_box_input)
	cook_status.visible = false
	cook_timer.visible = false
	cook_progress.visible = false

	# Убрать перехват ввода Control-нодами — клики идут к ClickableSprite
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oven_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dispense_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	furnace_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	furnace_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Первичная настройка геометрии автомата и компонентов
	_setup_machine_layout()

	# Подключить сигналы панели
	_panel.next_pressed.connect(_on_next_pressed)
	_panel.mode_changed.connect(_on_mode_changed)
	_panel.preset_changed.connect(_on_preset_changed)
	_panel.size_changed.connect(_on_size_changed)
	_panel.dough_changed.connect(_on_dough_changed)
	_panel.height_changed.connect(_on_height_changed)
	_panel.promo_code_submitted.connect(_on_promo_submitted)
	_panel.payment_method_changed.connect(_on_payment_method_changed)
	order_mgr.price_changed.connect(func(p):
		if _panel:
			_panel.set_payment_price(p)
	)

	# Подключить FSM
	machine.state_changed.connect(_on_state_changed)
	queue_mgr.connect("cooking_started", _on_cook_start)
	queue_mgr.connect("cooking_progress", _on_cook_progress)
	queue_mgr.connect("cooking_finished", _on_cook_finish)
	queue_mgr.connect("dispensing_finished", _on_dispense_finish)

	# Старт
	machine.force_transition(MachineController.State.IDLE)
	order_mgr.create_new_order()
	resized.connect(_on_resized)
	_update_camera()


func _setup_machine_layout() -> void:
	# Фоновый спрайт
	bg.position = Vector2.ZERO
	bg.size = Vector2(BG_W, BG_H)
	if bg_left:
		bg_left.position = Vector2(-BG_W, 0.0)
		bg_left.size = Vector2(BG_W, BG_H)
		bg_left.flip_h = true
		bg_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bg_right:
		bg_right.position = Vector2(BG_W, 0.0)
		bg_right.size = Vector2(BG_W, BG_H)
		bg_right.flip_h = true
		bg_right.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Автомат на фоне
	body.position = MACHINE_POS
	body.scale = Vector2(MACHINE_SCALE, MACHINE_SCALE)
	body.size = Vector2(BODY_W, BODY_H)

	# Зоны внутри автомата
	oven_zone.position = OVEN_RECT.position
	oven_zone.size = OVEN_RECT.size
	oven_zone.clip_contents = true
	oven_interior.position = Vector2.ZERO
	oven_interior.size = oven_zone.size

	screen_zone.position = SCREEN_RECT.position
	screen_zone.size = SCREEN_RECT.size

	dispense_zone.position = DISPENSE_RECT.position
	dispense_zone.size = DISPENSE_RECT.size
	pizza_box.position = Vector2.ZERO
	pizza_box.size = dispense_zone.size

	bottom_bar.position = BAR_RECT.position
	bottom_bar.size = BAR_RECT.size

	furnace_zone.position = FURNACE_RECT.position
	furnace_zone.size = FURNACE_RECT.size
	furnace_indicator.position = Vector2.ZERO
	furnace_indicator.size = furnace_zone.size

	# Диспенсеры ингредиентов внутри камеры печи (4 штуки под потолочной балкой)
	const DISPENSER_COUNT := 4
	const DISP_W := 132.0
	const DISP_H := 141.0
	const INNER_LEFT := 88.0
	const INNER_RIGHT := 732.0
	const POS_Y := 68.0
	var disp_spacing := (INNER_RIGHT - INNER_LEFT - DISPENSER_COUNT * DISP_W) / float(DISPENSER_COUNT - 1)
	for i in range(DISPENSER_COUNT):
		var d := DispenserUnit.new()
		d.name = "Dispenser_%d" % i
		d.z_index = 600
		var pos_x := INNER_LEFT + i * (DISP_W + disp_spacing)
		d.setup(Vector2(pos_x, POS_Y), Vector2(DISP_W, DISP_H))
		oven_zone.add_child(d)
		_dispensers.append(d)

	# Компонент вращающейся пиццы и физики выпадения ингредиентов
	_cooker = PizzaCookerScript.new()
	_cooker.name = "PizzaCooker"
	_cooker.z_index = 1
	oven_zone.add_child(_cooker)
	_cooker.setup_dispensers(_dispensers)
	_cooker.cooking_layer_started.connect(func(layer_name, _disp_idx):
		if _panel and machine.current_state == MachineController.State.COOKING:
			_panel.set_title("СЛОЙ: %s" % layer_name.to_upper())
	)
	_cooker.baking_started.connect(func():
		if _panel and machine.current_state == MachineController.State.COOKING:
			_panel.set_title("🔥 ЗАПЕКАНИЕ (5 сек)")
		_start_oven_heat()
	)
	_cooker.platform_lowering_started.connect(func():
		print("[Main] ⬇️ Пицца начинает спуск из печи!")
		_stop_oven_heat()
		_set_furnace_indicator(_furnace_ind0)
		if _dispense_sign:
			_dispense_sign.start_blinking()
		if _panel and machine.current_state == MachineController.State.COOKING:
			_panel.set_title("⬇️ ВЫДАЧА ПИЦЦЫ...")
	)
	_cooker.cooking_completed.connect(func():
		print("[Main] ✅ Пицца полностью опустилась под печь -> выдаем коробку!")
		_on_pizza_fully_cooked()
	)

	# Неоновое табло над лотком выдачи («ЗАБЕРИ СВОЮ ПИЦЦУ» + мигающие стрелочки ▼)
	_dispense_sign = DispenseSignScript.new()
	_dispense_sign.name = "DispenseSign"
	_dispense_sign.position = DISPENSE_SIGN_RECT.position
	_dispense_sign.size = DISPENSE_SIGN_RECT.size
	_dispense_sign.z_index = 500
	body.add_child(_dispense_sign)

	# Неоновая вывеска на верхней левой плашке
	_neon = NeonSign.new()
	_neon.name = "NeonSign"
	_neon.position = LOGO_RECT.position
	body.add_child(_neon)

	# Сенсорная панель заказа
	_panel = ScreenPanel.new()
	_panel.name = "Panel"
	screen_zone.add_child(_panel)


func _process(delta: float) -> void:
	# Плавное сглаживание зума камеры
	if not is_equal_approx(_zoom_t, _target_zoom_t):
		_zoom_t = lerpf(_zoom_t, _target_zoom_t, 9.0 * delta)
		if absf(_zoom_t - _target_zoom_t) < 0.001:
			_zoom_t = _target_zoom_t
		_update_camera()

	# Анимация индикатора печи во время готовки
	if machine and machine.current_state == MachineController.State.COOKING:
		_cook_indicator_time += delta
		var tick: int = int(_cook_indicator_time * 3.0) % 3
		match tick:
			0: _set_furnace_indicator(_furnace_ind0)
			1: _set_furnace_indicator(_furnace_ind1)
			2: _set_furnace_indicator(_furnace_ind2)


# ═══ ДИНАМИЧЕСКАЯ КАМЕРА / ЗУМ ═══

func _calc_zoom_bounds() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	# Отдаление: весь фон 2752x1536 помещается на экране (максимальное отдаление при старте)
	var z_out := minf(vp.x / BG_W, vp.y / BG_H)
	# Максимальное приближение: автомат занимает ровно 100% высоты экрана с сохранением полного масштаба всего автомата
	var z_in := (vp.y * 1.0) / MACHINE_H
	return Vector2(z_out, z_in)


func _update_camera() -> void:
	if not cam:
		return
	var zb := _calc_zoom_bounds()
	var z := lerpf(zb.x, zb.y, _zoom_t)
	cam.zoom = Vector2(z, z)
	cam.position = BG_CENTER.lerp(MACHINE_CENTER, _zoom_t)


func _on_resized() -> void:
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	# Зум колесиком мыши (вперед — к автомату, назад — к общему виду фона)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom_t = clampf(_target_zoom_t + ZOOM_STEP, 0.0, 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom_t = clampf(_target_zoom_t - ZOOM_STEP, 0.0, 1.0)

	# F3 — сброс зума к общему фону
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_target_zoom_t = 0.0


# ═══ СИГНАЛЫ ПАНЕЛИ ═══

func _on_mode_changed(mode: String) -> void:
	order_mgr.set_mode(mode)
	print("[Game] Режим: %s" % mode)

func _on_preset_changed(index: int) -> void:
	if _game_data and index < _game_data.presets.size():
		order_mgr.apply_preset(_game_data.presets[index])
	print("[Game] Пресет: %d" % index)

func _on_size_changed(index: int) -> void:
	if _game_data and index < _game_data.sizes.size():
		order_mgr.set_size(_game_data.sizes[index])
	print("[Game] Размер: %d" % index)

func _on_dough_changed(index: int) -> void:
	if _game_data and index < _game_data.doughs.size():
		order_mgr.set_dough(_game_data.doughs[index])
	print("[Game] Тесто: %d" % index)

func _on_height_changed(tall: bool) -> void:
	order_mgr.set_height_tall(tall)
	print("[Game] Высота: %s" % ("высокая" if tall else "обычная"))


func _on_promo_submitted(code: String) -> void:
	if not order_mgr:
		return
	var ok: bool = order_mgr.apply_promo_code(code)
	if ok and order_mgr.current_order:
		var promo = order_mgr.current_order.promo_code
		var desc: String = promo.description if promo else "Скидка применена!"
		_panel.set_promo_result(true, desc)
		_panel.set_payment_price(order_mgr.current_order.final_price)
	else:
		_panel.set_promo_result(false, "Неверный код")


func _on_payment_method_changed(method_name: String) -> void:
	print("[Main] Выбран способ оплаты: %s" % method_name)


# ═══ НАВИГАЦИЯ ═══

func _on_next_pressed() -> void:
	match machine.current_state:
		MachineController.State.IDLE:
			order_mgr.create_new_order()
			if _panel and _game_data:
				var p_idx: int = _panel.get_selected_pizza_index()
				if p_idx < _game_data.presets.size():
					order_mgr.apply_preset(_game_data.presets[p_idx])
			# Сразу на панель параметров
			machine.force_transition(MachineController.State.SELECT_PARAMETERS)
		MachineController.State.SELECT_PARAMETERS:
			# После выбора параметров — сразу оплата
			machine.force_transition(MachineController.State.PAYMENT)
			if _panel and order_mgr.current_order:
				_panel.set_payment_price(order_mgr.current_order.final_price)
		MachineController.State.PAYMENT:
			AudioManager.play_payment_random()
			machine.force_transition(MachineController.State.QUEUE)
			queue_mgr.add_to_queue(order_mgr.current_order)
		MachineController.State.COOKING:
			# Кнопка СКИП: 1-й скип — до запекания, 2-й скип — до выдачи
			_handle_cooking_skip()
		MachineController.State.FINISH:
			_take_pizza()


func _handle_cooking_skip() -> void:
	if not _cooker:
		queue_mgr.skip_cooking()
		return

	if not _cooker.is_in_baking_phase():
		print("[Main] ⏭️ Скип 1/2: Раскладка завершена, переходим к запеканию!")
		_cooker.skip_to_baking()
		queue_mgr.skip_to_baking()
		if _panel:
			_panel.set_title("🔥 ЗАПЕКАНИЕ")
	else:
		print("[Main] ⏭️ Скип 2/2: Запекание завершено, переходим к выдаче!")
		_stop_oven_heat()
		_cooker.skip_to_finish()
		_on_pizza_fully_cooked()


# ═══ FSM ═══

func _on_state_changed(_o: MachineController.State, ns: MachineController.State) -> void:
	_panel.show_state(ns)
	_update_oven_camera(ns)


## Переключение текстуры камеры печи и диспенсеров по состоянию автомата
func _update_oven_camera(state: MachineController.State) -> void:
	match state:
		MachineController.State.IDLE:
			_set_camera(_cam_off)
			_set_furnace_indicator(_furnace_ind0)
			pizza_box.visible = false
			if _dispense_sign:
				_dispense_sign.stop_blinking()
			_set_dispensers_state(DispenserUnit.State.OFF)
		MachineController.State.SELECT_MODE, MachineController.State.SELECT_PARAMETERS, \
		MachineController.State.BUILDING_COMPOSITION, MachineController.State.PROMO_CODE, \
		MachineController.State.PAYMENT, MachineController.State.QUEUE:
			_set_camera(_cam_enabled)
			_set_furnace_indicator(_furnace_ind0)
			if _dispense_sign:
				_dispense_sign.stop_blinking()
			_set_dispensers_state(DispenserUnit.State.PREPARED)
		MachineController.State.COOKING:
			_set_camera(_cam_cooking)
			_set_dispensers_state(DispenserUnit.State.DISPENSING)
		MachineController.State.DISPENSING, MachineController.State.FINISH:
			_cook_indicator_time = 0.0
			_set_camera(_cam_completed)
			_set_furnace_indicator(_furnace_ind0)
			if _dispense_sign:
				_dispense_sign.start_blinking()
			_set_dispensers_state(DispenserUnit.State.PREPARED)


func _set_dispensers_state(st: DispenserUnit.State) -> void:
	for d in _dispensers:
		d.set_dispenser_state(st)


func _set_camera(tex: Texture2D) -> void:
	if oven_interior and tex:
		oven_interior.texture = tex


func _set_furnace_indicator(tex: Texture2D) -> void:
	if furnace_indicator and tex and furnace_indicator.texture != tex:
		furnace_indicator.texture = tex


# ═══ ГОТОВКА И ВЫДАЧА ═══

func _on_cook_start(order) -> void:
	cook_progress.value = 0
	_cook_indicator_time = 0.0
	_set_camera(_cam_cooking)
	_set_furnace_indicator(_furnace_ind0)
	if _dispense_sign:
		_dispense_sign.stop_blinking()
	machine.force_transition(MachineController.State.COOKING)
	if _cooker:
		_cooker.start_cooking(order)
	print("[Game] Начало готовки: %s" % order)

func _on_cook_progress(progress: float, time_left: float) -> void:
	cook_progress.value = progress * 100.0
	if machine.current_state == MachineController.State.COOKING:
		if _panel:
			if _cooker and _cooker.is_lowering():
				_panel.set_title("⬇️ ВЫДАЧА ПИЦЦЫ...")
			elif (_cooker and _cooker.is_in_baking_phase()) or time_left <= 6.0:
				_panel.set_title("🔥 ЗАПЕКАНИЕ: %d сек" % ceil(time_left))
			else:
				_panel.set_title("РАСКЛАДКА: %d сек" % ceil(maxf(time_left - 6.0, 1.0)))

func _on_cook_finish(_order) -> void:
	cook_progress.value = 100
	_cook_indicator_time = 0.0
	_stop_oven_heat()
	_set_furnace_indicator(_furnace_ind0)
	# Если кукер еще в процессе выпекания или спуска платформы — ждем естественного окончания
	if _cooker and (_cooker.is_lowering() or _cooker.is_in_baking_phase()):
		print("[Game] Ждём завершения спуска платформы перед показом коробки...")
		return
	_on_pizza_fully_cooked()


func _on_pizza_fully_cooked() -> void:
	cook_progress.value = 100
	_cook_indicator_time = 0.0
	_stop_oven_heat()
	_set_camera(_cam_completed)
	_set_furnace_indicator(_furnace_ind0)
	if machine.current_state in [MachineController.State.COOKING, MachineController.State.DISPENSING]:
		machine.force_transition(MachineController.State.DISPENSING)
	_show_pizza_box()
	if _dispense_sign:
		_dispense_sign.start_blinking()
	if queue_mgr and queue_mgr.is_cooking:
		queue_mgr.complete_cooking()
	print("[Game] Готовка завершена! Пицца готова.")


func _start_oven_heat() -> void:
	if not oven_interior:
		return
	if is_instance_valid(_oven_heat_tween):
		_oven_heat_tween.kill()
	_oven_heat_tween = create_tween()
	# Плавное нарастание глубокого красного жара ТЭНов внутри печи
	_oven_heat_tween.tween_property(oven_interior, "modulate", Color(1.40, 0.60, 0.40), 1.2).set_trans(Tween.TRANS_SINE)
	# Живое дыхание раскаленной печи
	_oven_heat_tween.tween_property(oven_interior, "modulate", Color(1.50, 0.65, 0.35), 0.8).set_trans(Tween.TRANS_SINE)
	_oven_heat_tween.tween_property(oven_interior, "modulate", Color(1.35, 0.55, 0.40), 0.8).set_trans(Tween.TRANS_SINE)


func _stop_oven_heat() -> void:
	if not oven_interior:
		return
	if is_instance_valid(_oven_heat_tween):
		_oven_heat_tween.kill()
	_oven_heat_tween = create_tween()
	_oven_heat_tween.tween_property(oven_interior, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)

func _on_dispense_finish(_order) -> void:
	if machine.current_state == MachineController.State.DISPENSING:
		machine.force_transition(MachineController.State.FINISH)
	print("[Game] Выдача завершена. Ждём пока игрок заберёт пиццу.")
	_start_auto_finish_timer()


## Плавное появление коробки в зоне выдачи
func _show_pizza_box() -> void:
	pizza_box.visible = true
	pizza_box.modulate.a = 0.0
	pizza_box.position = Vector2(0, -20)
	AudioManager.play_pizza_completed()
	var tw := create_tween()
	tw.tween_property(pizza_box, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(pizza_box, "position", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Игрок забирает пиццу (клик или авто-таймер)
func _take_pizza() -> void:
	if not pizza_box.visible:
		if machine.current_state in [MachineController.State.FINISH, MachineController.State.DISPENSING]:
			machine.force_transition(MachineController.State.IDLE)
		return
	print("[Game] Игрок забирает пиццу!")
	if _dispense_sign:
		_dispense_sign.stop_blinking()
	AudioManager.play_pickup_random()
	var tw := create_tween()
	tw.tween_property(pizza_box, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(pizza_box, "position", Vector2(0, -25), 0.35)
	await tw.finished
	pizza_box.visible = false
	pizza_box.position = Vector2.ZERO
	pizza_box.modulate.a = 1.0
	_cook_indicator_time = 0.0
	_set_camera(_cam_off)
	_set_furnace_indicator(_furnace_ind0)
	if _cooker:
		_cooker.stop()

	cook_progress.value = 0
	if machine.current_state in [MachineController.State.FINISH, MachineController.State.DISPENSING]:
		machine.force_transition(MachineController.State.IDLE)


## Авто-забор через 5 секунд, если игрок не кликнул сам
func _start_auto_finish_timer() -> void:
	await get_tree().create_timer(5.0).timeout
	if machine.current_state == MachineController.State.FINISH and pizza_box.visible:
		print("[Game] Авто-забор пиццы по таймеру.")
		_take_pizza()


## Клик мышкой по коробке с пиццей
func _on_pizza_box_input(event: InputEvent) -> void:
	if not pizza_box.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_take_pizza()
