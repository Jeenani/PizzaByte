extends Control
# ═══════════════════════════════════════════════════════════
#  🍕 PIZZA MARKET — 2D пиццемат-симулятор
#  Текстурная архитектура: каркас + слои контента
#  Каркас machie_body.png (512×668) масштабируется keep-aspect
#
#  ДЕБАГ (F1): сетка, рамки зон, координаты, drag зон
#  ЗУМ: колёсико мыши
#  ПАН: средняя кнопка мыши (зажать + тянуть)
#
#  Все координаты зон — в пикселях ТЕКСТУРЫ (512×668).
#  Скрипт автоматически пересчитывает их в экранные.
# ═══════════════════════════════════════════════════════════

# ── Размер исходной текстуры каркаса ──
const BODY_W := 512.0
const BODY_H := 668.0

# ── Шаг координатной сетки (в пикселях текстуры) ──
const GRID_STEP := 32

# ── Зум ──
const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0
const ZOOM_STEP := 0.1
var _zoom := 1.0
var _pan := Vector2.ZERO       # смещение панорамы (экранные px)
var _panning := false           # средняя кнопка зажата
var _pan_start := Vector2.ZERO

# ═══════════════════════════════════════════════════════════
#  ЗОНЫ НА КАРКАСЕ (в пикселях текстуры 512×668)
#  Настраиваются через дебаг-режим (F1), потом значения
#  копируются сюда как финальные.
# ═══════════════════════════════════════════════════════════

# Каждая зона: { name, rect, color, node_path }
# rect — Rect2 в координатах текстуры
var _zones: Array[Dictionary] = [
	{
		"name": "OvenZone",
		"rect": Rect2(38, 115, 375, 300),
		"color": Color(1, 0.5, 0, 0.4),
		"node": "OvenZone",
	},
	{
		"name": "ScreenZone",
		"rect": Rect2(38, 115, 375, 445),
		"color": Color(0, 0.7, 1, 0.3),
		"node": "ScreenZone",
	},
	{
		"name": "DispenseZone",
		"rect": Rect2(38, 438, 375, 88),
		"color": Color(1, 0, 0.3, 0.4),
		"node": "DispenseZone",
	},
	{
		"name": "IngredientsZone",
		"rect": Rect2(420, 48, 88, 565),
		"color": Color(0, 1, 0.5, 0.3),
		"node": "IngredientsZone",
	},
	{
		"name": "BottomBar",
		"rect": Rect2(8, 572, 496, 58),
		"color": Color(1, 1, 0, 0.3),
		"node": "BottomBar",
	},
]

# ── Дебаг ──
var _debug_mode := false
var _debug_selected := -1       # индекс выделенной зоны
var _debug_dragging := false
var _debug_drag_offset := Vector2.ZERO
var _debug_overlay: Control     # нода для рисования поверх всего

# ── Менеджеры ──
@onready var machine: MachineController = $MachineController
@onready var order_mgr: Node = $OrderManager
@onready var queue_mgr: Node = $QueueManager

# ── Каркас ──
@onready var body: TextureRect = $MachineBody

# ── Зоны (ноды) ──
@onready var oven_zone: Control = $MachineBody/OvenZone
@onready var screen_zone: Control = $MachineBody/ScreenZone
@onready var ingredients_zone: Control = $MachineBody/IngredientsZone
@onready var dispense_zone: Control = $MachineBody/DispenseZone
@onready var bottom_bar: Control = $MachineBody/BottomBar

# ── Печь ──
@onready var cook_progress: ProgressBar = $MachineBody/OvenZone/CookProgress
@onready var cook_status: Label = $MachineBody/OvenZone/CookStatus
@onready var cook_timer: Label = $MachineBody/OvenZone/CookTimer

# ── Экран ──
@onready var screen_content: VBoxContainer = $MachineBody/ScreenZone/ScreenContent
@onready var next_button: Button = $MachineBody/ScreenZone/ScreenContent/NextButton

# ── Ингредиенты ──
@onready var ing_grid: GridContainer = $MachineBody/IngredientsZone/IngredientsContent/IngredientsGrid
@onready var ing_header: Label = $MachineBody/IngredientsZone/IngredientsContent/IngredientsHeader

# ── Оплата ──
@onready var pay_button: Button = $MachineBody/IngredientsZone/PaymentContent/PayButton
@onready var promo_row: HBoxContainer = $MachineBody/IngredientsZone/PaymentContent/PromoRow
@onready var payment_methods: HBoxContainer = $MachineBody/IngredientsZone/PaymentContent/PaymentMethods
@onready var total_row: HBoxContainer = $MachineBody/IngredientsZone/PaymentContent/TotalRow

# ── Выдача ──
@onready var pizza_box: TextureRect = $MachineBody/DispenseZone/PizzaBox

# ── Данные ──
var _game_data: Node
var _ing_buttons: Dictionary = {}
var _total_label: Label
var _promo_input: LineEdit
var _promo_status: Label


# ═══════════════════════════════════════════════════════════
#  INIT
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_game_data = get_node_or_null("/root/GameData")

	# Создаём оверлей для дебаг-рисования (поверх всего)
	_debug_overlay = Control.new()
	_debug_overlay.name = "DebugOverlay"
	_debug_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_debug_overlay)
	_debug_overlay.draw.connect(_draw_debug)

	_connect_signals()
	_build_ingredients()
	_build_payment()
	_build_total()
	pizza_box.visible = false
	machine.force_transition(MachineController.State.IDLE)
	order_mgr.create_new_order()
	resized.connect(_on_resized)
	call_deferred("_on_resized")


# ═══════════════════════════════════════════════════════════
#  INPUT — зум, пан, дебаг, горячие клавиши
# ═══════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	# F1 — переключить дебаг
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_debug_mode = not _debug_mode
		_debug_selected = -1
		_debug_dragging = false
		_debug_overlay.queue_redraw()
		_log_zones()
		get_viewport().set_input_as_handled()
		return

	# F2 — вывести координаты всех зон в консоль
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_log_zones()
		get_viewport().set_input_as_handled()
		return

	# F3 — сброс зума и пана
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_zoom = 1.0
		_pan = Vector2.ZERO
		_on_resized()
		_debug_overlay.queue_redraw()
		get_viewport().set_input_as_handled()
		return

	# Зум колёсиком
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_on_resized()
			_debug_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_on_resized()
			_debug_overlay.queue_redraw()
			get_viewport().set_input_as_handled()

		# Средняя кнопка — пан
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_panning = true
				_pan_start = event.position - _pan
			else:
				_panning = false
			get_viewport().set_input_as_handled()

		# Дебаг: кликнуть по зоне для выделения / drag
		elif _debug_mode and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_debug_try_select(event.position)
			else:
				_debug_dragging = false
			get_viewport().set_input_as_handled()

	# Средняя кнопка — перемещение
	if event is InputEventMouseMotion:
		if _panning:
			_pan = event.position - _pan_start
			_on_resized()
			_debug_overlay.queue_redraw()
			get_viewport().set_input_as_handled()
		elif _debug_mode and _debug_dragging and _debug_selected >= 0:
			_debug_drag_zone(event.position)
			get_viewport().set_input_as_handled()


# ═══════════════════════════════════════════════════════════
#  LAYOUT — каркас + зоны
# ═══════════════════════════════════════════════════════════

func _on_resized() -> void:
	_fit_body()
	_apply_zones()
	_debug_overlay.queue_redraw()


## Вписать каркас: по высоте viewport * zoom, отцентрировать + pan
func _fit_body() -> void:
	var vp := size
	var aspect := BODY_W / BODY_H
	var draw_h := vp.y * _zoom
	var draw_w := draw_h * aspect
	if draw_w > vp.x * _zoom:
		draw_w = vp.x * _zoom
		draw_h = draw_w / aspect
	var offset_x := (vp.x - draw_w) / 2.0 + _pan.x
	var offset_y := (vp.y - draw_h) / 2.0 + _pan.y
	body.position = Vector2(offset_x, offset_y)
	body.size = Vector2(draw_w, draw_h)


## Масштаб текстура → экран
func _tex_scale() -> Vector2:
	return Vector2(body.size.x / BODY_W, body.size.y / BODY_H)


## Перевести Rect2 из координат текстуры в координаты внутри body
func _tex_to_body(r: Rect2) -> Rect2:
	var s := _tex_scale()
	return Rect2(r.position.x * s.x, r.position.y * s.y,
				 r.size.x * s.x, r.size.y * s.y)


## Перевести Rect2 из координат текстуры → глобальные экранные
func _tex_to_screen(r: Rect2) -> Rect2:
	var s := _tex_scale()
	return Rect2(
		body.position.x + r.position.x * s.x,
		body.position.y + r.position.y * s.y,
		r.size.x * s.x,
		r.size.y * s.y
	)


## Перевести экранную точку → координаты текстуры
func _screen_to_tex(p: Vector2) -> Vector2:
	var s := _tex_scale()
	return Vector2(
		(p.x - body.position.x) / s.x,
		(p.y - body.position.y) / s.y
	)


## Применить все зоны к их нодам (внутри body)
func _apply_zones() -> void:
	for z in _zones:
		var node: Control = body.get_node_or_null(z["node"])
		if node:
			var br := _tex_to_body(z["rect"])
			node.position = br.position
			node.size = br.size

	# Контент экрана
	screen_content.position = Vector2.ZERO
	screen_content.size = screen_zone.size

	# Прогресс/лейблы печи
	cook_progress.position = Vector2(8, 4)
	cook_progress.size = Vector2(oven_zone.size.x * 0.6, 14)
	cook_status.position = Vector2(8, 22)
	cook_timer.position = Vector2(oven_zone.size.x - 70, 4)


# ═══════════════════════════════════════════════════════════
#  ДЕБАГ — рисование сетки, зон, координат
# ═══════════════════════════════════════════════════════════

func _draw_debug() -> void:
	if not _debug_mode:
		return

	var ov := _debug_overlay
	var s := _tex_scale()

	# ── Сетка ──
	var grid_color := Color(1, 1, 1, 0.12)
	var grid_label_color := Color(1, 1, 1, 0.35)
	for gx in range(0, int(BODY_W) + 1, GRID_STEP):
		var sx := body.position.x + gx * s.x
		ov.draw_line(Vector2(sx, body.position.y),
					 Vector2(sx, body.position.y + body.size.y),
					 grid_color, 1.0)
		if gx % (GRID_STEP * 2) == 0:
			ov.draw_string(ThemeDB.fallback_font, Vector2(sx + 2, body.position.y + 12),
						   str(gx), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, grid_label_color)

	for gy in range(0, int(BODY_H) + 1, GRID_STEP):
		var sy := body.position.y + gy * s.y
		ov.draw_line(Vector2(body.position.x, sy),
					 Vector2(body.position.x + body.size.x, sy),
					 grid_color, 1.0)
		if gy % (GRID_STEP * 2) == 0:
			ov.draw_string(ThemeDB.fallback_font, Vector2(body.position.x + 2, sy + 12),
						   str(gy), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, grid_label_color)

	# ── Зоны ──
	for i in range(_zones.size()):
		var z := _zones[i]
		var r := _tex_to_screen(z["rect"])
		var col: Color = z["color"]
		var border_w := 2.0 if i == _debug_selected else 1.0
		var border_col := Color.WHITE if i == _debug_selected else col.lightened(0.3)

		# Заливка
		ov.draw_rect(r, col, true)
		# Рамка
		ov.draw_rect(r, border_col, false, border_w)

		# Название + координаты
		var label_text := "%s  [%d, %d, %d, %d]" % [
			z["name"],
			int(z["rect"].position.x), int(z["rect"].position.y),
			int(z["rect"].size.x), int(z["rect"].size.y)
		]
		ov.draw_string(ThemeDB.fallback_font,
					   Vector2(r.position.x + 4, r.position.y + 14),
					   label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					   Color.WHITE)

	# ── HUD дебага ──
	var hud_y := 16.0
	var hud_lines := [
		"[F1] Debug: ON   [F2] Log zones   [F3] Reset zoom",
		"Zoom: %.1fx   Pan: (%d, %d)   Body: %dx%d" % [
			_zoom, int(_pan.x), int(_pan.y), int(body.size.x), int(body.size.y)
		],
		"Scroll: zoom   Middle-drag: pan   Left-click: select zone",
	]
	if _debug_selected >= 0:
		hud_lines.append("Selected: %s — drag to move" % _zones[_debug_selected]["name"])

	for line in hud_lines:
		ov.draw_string(ThemeDB.fallback_font, Vector2(10, hud_y),
					   line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					   Color(0, 1, 0.5, 0.9))
		hud_y += 18


## Выделить зону кликом
func _debug_try_select(screen_pos: Vector2) -> void:
	_debug_selected = -1
	_debug_dragging = false
	# Ищем в обратном порядке (верхние зоны приоритетнее)
	for i in range(_zones.size() - 1, -1, -1):
		var r := _tex_to_screen(_zones[i]["rect"])
		if r.has_point(screen_pos):
			_debug_selected = i
			_debug_dragging = true
			_debug_drag_offset = screen_pos - r.position
			break
	_debug_overlay.queue_redraw()


## Перетащить зону
func _debug_drag_zone(screen_pos: Vector2) -> void:
	var new_screen_pos := screen_pos - _debug_drag_offset
	var tex_pos := _screen_to_tex(new_screen_pos)
	# Привязка к сетке (snap)
	tex_pos.x = roundf(tex_pos.x / 4.0) * 4.0
	tex_pos.y = roundf(tex_pos.y / 4.0) * 4.0
	tex_pos.x = clampf(tex_pos.x, 0, BODY_W - _zones[_debug_selected]["rect"].size.x)
	tex_pos.y = clampf(tex_pos.y, 0, BODY_H - _zones[_debug_selected]["rect"].size.y)
	_zones[_debug_selected]["rect"].position = tex_pos
	_apply_zones()
	_debug_overlay.queue_redraw()


## Вывести все координаты зон в консоль (для копирования в код)
func _log_zones() -> void:
	print("")
	print("═══ ZONE COORDINATES (tex px %dx%d) ═══" % [int(BODY_W), int(BODY_H)])
	for z in _zones:
		var r: Rect2 = z["rect"]
		print('  { "name": "%s", "rect": Rect2(%d, %d, %d, %d) },' % [
			z["name"], int(r.position.x), int(r.position.y),
			int(r.size.x), int(r.size.y)
		])
	print("═══════════════════════════════════════")
	print("")


# ═══════════════════════════════════════════════════════════
#  СИГНАЛЫ
# ═══════════════════════════════════════════════════════════

func _connect_signals() -> void:
	machine.state_changed.connect(_on_state_changed)
	order_mgr.order_updated.connect(_on_order_updated)
	queue_mgr.cooking_started.connect(_on_cook_start)
	queue_mgr.cooking_progress.connect(_on_cook_progress)
	queue_mgr.cooking_finished.connect(_on_cook_finish)
	queue_mgr.dispensing_finished.connect(_on_dispense_finish)
	next_button.pressed.connect(_on_next_pressed)
	pay_button.pressed.connect(_on_pay_pressed)


# ═══════════════════════════════════════════════════════════
#  ИНГРЕДИЕНТЫ (пока стоковые — будут заменены на спрайты)
# ═══════════════════════════════════════════════════════════

func _build_ingredients() -> void:
	if not _game_data:
		return
	for ing in _game_data.ingredients:
		var btn := Button.new()
		btn.text = "%s\n+%.2f$" % [ing.display_name, ing.price]
		btn.custom_minimum_size = Vector2(90, 48)
		btn.toggle_mode = true
		btn.pressed.connect(_on_ingredient_toggled.bind(ing, btn))
		ing_grid.add_child(btn)
		_ing_buttons[ing] = btn


func _on_ingredient_toggled(ing: IngredientData, btn: Button) -> void:
	if not order_mgr.current_order:
		return
	if btn.button_pressed:
		order_mgr.add_ingredient(ing)
	else:
		order_mgr.remove_ingredient_by_data(ing)


# ═══════════════════════════════════════════════════════════
#  ОПЛАТА (пока стоковые — будут заменены на спрайты)
# ═══════════════════════════════════════════════════════════

func _build_payment() -> void:
	_promo_input = LineEdit.new()
	_promo_input.placeholder_text = "Введи код"
	_promo_input.custom_minimum_size = Vector2(100, 28)
	promo_row.add_child(_promo_input)

	var apply_btn := Button.new()
	apply_btn.text = "Применить"
	apply_btn.pressed.connect(_on_promo_apply)
	promo_row.add_child(apply_btn)

	_promo_status = Label.new()
	_promo_status.text = ""
	promo_row.add_child(_promo_status)

	for method in ["НАЛИЧНЫЕ", "КАРТОЙ", "МОНЕТЫ"]:
		var mbtn := Button.new()
		mbtn.text = method
		mbtn.toggle_mode = true
		mbtn.custom_minimum_size = Vector2(80, 30)
		mbtn.pressed.connect(_on_payment_method.bind(method, mbtn))
		payment_methods.add_child(mbtn)


func _build_total() -> void:
	var lbl := Label.new()
	lbl.text = "Итого:"
	total_row.add_child(lbl)

	_total_label = Label.new()
	_total_label.text = "$0.00"
	_total_label.add_theme_font_size_override("font_size", 18)
	_total_label.add_theme_color_override("font_color", Color("#ffc040"))
	total_row.add_child(_total_label)


func _on_promo_apply() -> void:
	if not _promo_input:
		return
	var code := _promo_input.text.strip_edges()
	if code.is_empty():
		return
	var ok: bool = order_mgr.apply_promo_code(code)
	if ok:
		_promo_status.text = "✅ Применён"
		_promo_status.add_theme_color_override("font_color", Color.GREEN)
	else:
		_promo_status.text = "❌ Неверный"
		_promo_status.add_theme_color_override("font_color", Color.RED)


func _on_payment_method(method: String, btn: Button) -> void:
	for child in payment_methods.get_children():
		if child is Button and child != btn:
			child.button_pressed = false
	order_mgr.set_payment_method(method)


# ═══════════════════════════════════════════════════════════
#  НАВИГАЦИЯ
# ═══════════════════════════════════════════════════════════

func _on_next_pressed() -> void:
	match machine.current_state:
		MachineController.State.IDLE:
			order_mgr.create_new_order()
			machine.transition_to(MachineController.State.SELECT_MODE)
		MachineController.State.SELECT_MODE:
			machine.transition_to(MachineController.State.SELECT_PARAMETERS)
		MachineController.State.SELECT_PARAMETERS:
			machine.transition_to(MachineController.State.BUILDING_COMPOSITION)
		MachineController.State.BUILDING_COMPOSITION:
			machine.transition_to(MachineController.State.PROMO_CODE)
		MachineController.State.PROMO_CODE:
			machine.transition_to(MachineController.State.PAYMENT)
		MachineController.State.FINISH:
			machine.transition_to(MachineController.State.IDLE)


func _on_pay_pressed() -> void:
	if machine.current_state != MachineController.State.PAYMENT:
		return
	if not order_mgr.current_order:
		return
	queue_mgr.add_to_queue(order_mgr.current_order)
	machine.transition_to(MachineController.State.QUEUE)
	order_mgr.create_new_order()


# ═══════════════════════════════════════════════════════════
#  ОБРАБОТЧИКИ СОСТОЯНИЙ
# ═══════════════════════════════════════════════════════════

func _on_state_changed(_old: MachineController.State, new_state: MachineController.State) -> void:
	_update_ui_for_state(new_state)


func _update_ui_for_state(state: MachineController.State) -> void:
	var is_ordering := machine.is_ordering()
	screen_zone.visible = true
	dispense_zone.visible = true
	next_button.visible = true
	if ingredients_zone.size.x > 10:
		ingredients_zone.visible = is_ordering

	match state:
		MachineController.State.IDLE:
			next_button.text = "🍕 НАЧАТЬ ЗАКАЗ"
			cook_status.text = "Ожидание..."
			pay_button.visible = false
		MachineController.State.SELECT_MODE:
			next_button.text = "ДАЛЕЕ →"
			pay_button.visible = false
		MachineController.State.SELECT_PARAMETERS:
			next_button.text = "ДАЛЕЕ →"
			pay_button.visible = false
		MachineController.State.BUILDING_COMPOSITION:
			next_button.text = "ДАЛЕЕ →"
			pay_button.visible = false
		MachineController.State.PROMO_CODE:
			next_button.text = "К ОПЛАТЕ →"
			pay_button.visible = false
		MachineController.State.PAYMENT:
			next_button.visible = false
			pay_button.visible = true
		MachineController.State.QUEUE:
			next_button.text = "🍕 НОВЫЙ ЗАКАЗ"
			pay_button.visible = false
		MachineController.State.COOKING:
			cook_status.text = "Готовим твою пиццу..."
		MachineController.State.DISPENSING:
			cook_status.text = "Выдаём..."
			pizza_box.visible = true
		MachineController.State.FINISH:
			cook_status.text = "Готово! Забери пиццу"
			next_button.text = "🍕 НОВЫЙ ЗАКАЗ"


# ═══════════════════════════════════════════════════════════
#  ОБНОВЛЕНИЕ ДАННЫХ
# ═══════════════════════════════════════════════════════════

func _on_order_updated() -> void:
	if not order_mgr.current_order:
		return
	var o = order_mgr.current_order
	if _total_label:
		_total_label.text = "$%.2f" % o.final_price
	_sync_ing_buttons()


func _sync_ing_buttons() -> void:
	if not order_mgr.current_order:
		return
	var ings = order_mgr.current_order.ingredients
	for ing_key in _ing_buttons:
		var btn: Button = _ing_buttons[ing_key]
		btn.set_pressed_no_signal(ing_key in ings)


# ═══════════════════════════════════════════════════════════
#  ГОТОВКА / ВЫДАЧА
# ═══════════════════════════════════════════════════════════

func _on_cook_start(order) -> void:
	cook_status.text = "🔥 Готовим: %s" % str(order)
	cook_progress.value = 0
	if machine.current_state == MachineController.State.QUEUE:
		machine.force_transition(MachineController.State.COOKING)


func _on_cook_progress(progress: float, time_left: float) -> void:
	cook_progress.value = progress * 100.0
	cook_timer.text = "%02d:%02d" % [int(time_left) / 60, int(time_left) % 60]


func _on_cook_finish(order) -> void:
	cook_status.text = "✅ Готово: %s" % str(order)
	cook_progress.value = 100
	cook_timer.text = "00:00"
	pizza_box.visible = true
	if machine.current_state == MachineController.State.COOKING:
		machine.force_transition(MachineController.State.DISPENSING)


func _on_dispense_finish(order) -> void:
	cook_status.text = "📦 Забери: %s" % str(order)
	if machine.current_state == MachineController.State.DISPENSING:
		machine.force_transition(MachineController.State.FINISH)
	await get_tree().create_timer(3.0).timeout
	pizza_box.visible = false
	cook_status.text = "Ожидание..."
	cook_progress.value = 0
