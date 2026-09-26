extends Control
# ═══════════════════════════════════════════════════════════
#  🍕 PIZZA MARKET — 2D пиццемат-симулятор
#  Единый каркас whole_body.png (1614×1536)
#  Визуальный конструктор: Designer (designer.gd)
#  Интерактивные элементы через материализацию
# ═══════════════════════════════════════════════════════════

const BODY_W := 1614.0
const BODY_H := 1536.0
const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0
const ZOOM_STEP := 0.1

var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _pan_start := Vector2.ZERO

## Дизайнер
var _designer: Designer

# ═══════════════════════════════════════════════════════════
#  НОДЫ СЦЕНЫ (только нужные для game logic)
# ═══════════════════════════════════════════════════════════
@onready var machine: MachineController = $MachineController
@onready var order_mgr: Node = $OrderManager
@onready var queue_mgr: Node = $QueueManager
@onready var body: TextureRect = $MachineBody
@onready var oven_zone: Control = $MachineBody/OvenZone
@onready var screen_zone: Control = $MachineBody/ScreenZone
@onready var dispense_zone: Control = $MachineBody/DispenseZone
@onready var bottom_bar: Control = $MachineBody/BottomBar
@onready var cook_progress: ProgressBar = $MachineBody/OvenZone/CookProgress
@onready var cook_status: Label = $MachineBody/OvenZone/CookStatus
@onready var cook_timer: Label = $MachineBody/OvenZone/CookTimer
@onready var screen_content: VBoxContainer = $MachineBody/ScreenZone/ScreenContent
@onready var next_button: Button = $MachineBody/ScreenZone/ScreenContent/NextButton
@onready var pizza_box: TextureRect = $MachineBody/DispenseZone/PizzaBox
# Скрываем дефолтные зоны — их заменит дизайнер
@onready var ingredients_zone: Control = $MachineBody/IngredientsZone

var _game_data: Node


# ═══════════════════════════════════════════════════════════
#  INIT
# ═══════════════════════════════════════════════════════════

func _ready() -> void:
	_game_data = get_node_or_null("/root/GameData")
	# Скрыть дефолтную панель ингредиентов — UI будет из дизайнера
	ingredients_zone.visible = false
	_init_designer()
	_connect_signals()
	pizza_box.visible = false
	machine.force_transition(MachineController.State.IDLE)
	order_mgr.create_new_order()
	resized.connect(_on_resized)
	call_deferred("_on_resized")


func _init_designer() -> void:
	_designer = Designer.new()
	# Зоны (привязаны к нодам сцены)
	_designer.add_zone("OvenZone", Rect2(56, 220, 590, 480), Color(1, 0.5, 0, 0.25), "OvenZone")
	_designer.add_zone("ScreenZone", Rect2(56, 220, 590, 820), Color(0, 0.7, 1, 0.2), "ScreenZone")
	_designer.add_zone("DispenseZone", Rect2(56, 880, 590, 180), Color(1, 0, 0.3, 0.25), "DispenseZone")
	_designer.add_zone("BottomBar", Rect2(12, 1280, 640, 120), Color(1, 1, 0, 0.2), "BottomBar")
	# setup загружает спрайты + layout
	_designer.setup(self, body, BODY_W, BODY_H)
	# Callback для кликов по материализованным элементам
	_designer.set_click_callback(_on_element_clicked)
	# Материализовать элементы (реальные ноды)
	_designer.materialize()


## Обработка клика по элементу дизайнера
func _on_element_clicked(element_id: String) -> void:
	var el = _designer._elements.get(element_id)
	if el == null:
		return
	var name_str: String = el.get("name", "")
	print("[UI] Клик: %s (%s)" % [name_str, element_id])
	# Здесь будет роутинг кликов к game logic
	# Например: if name_str == "btn_start": _on_next_pressed()


# ═══════════════════════════════════════════════════════════
#  INPUT
# ═══════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Не перехватывать клавиши если фокус на поле ввода дизайнера
		if _designer.has_focused_input():
			return
		match event.keycode:
			KEY_F1:
				_designer.toggle()
				# При выходе из дебага — заново материализовать
				if not _designer.active:
					_designer.materialize()
				else:
					_designer.dematerialize()
				get_viewport().set_input_as_handled()
				return
			KEY_F2:
				if _designer.active:
					_designer.log_all()
					get_viewport().set_input_as_handled()
					return
			KEY_F3:
				if _designer.active:
					_zoom = 1.0; _pan = Vector2.ZERO; _on_resized()
					get_viewport().set_input_as_handled()
					return
			KEY_F4:
				if _designer.active:
					_designer.save_layout()
					get_viewport().set_input_as_handled()
					return
			KEY_F5:
				if _designer.active:
					_designer.load_layout(); _on_resized(); _designer.refresh()
					get_viewport().set_input_as_handled()
					return
			KEY_DELETE:
				if _designer.active and _designer.selected_id != "":
					var el = _designer._elements.get(_designer.selected_id)
					if el:
						el["visible"] = not el["visible"]
					_designer.refresh()
					get_viewport().set_input_as_handled()
					return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_on_resized()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_on_resized()
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_panning = true
				_pan_start = event.position - _pan
			else:
				_panning = false
			get_viewport().set_input_as_handled()
			return
		if _designer.active and event.button_index == MOUSE_BUTTON_LEFT:
			if _designer.is_over_panel(event.position):
				return
			if event.pressed:
				_designer.try_select(event.position, event.shift_pressed)
			else:
				if _designer.dragging or _designer.resizing:
					_designer.stop_drag()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if _panning:
			_pan = event.position - _pan_start
			_on_resized()
			get_viewport().set_input_as_handled()
			return
		if _designer.active:
			if _designer.dragging:
				_designer.do_drag(event.position)
				get_viewport().set_input_as_handled()
				return
			elif _designer.resizing:
				_designer.do_resize(event.position)
				get_viewport().set_input_as_handled()
				return


# ═══════════════════════════════════════════════════════════
#  LAYOUT
# ═══════════════════════════════════════════════════════════

func _on_resized() -> void:
	_fit_body()
	_apply_zones()
	_designer.on_resized()
	# Обновить позиции материализованных нод
	if not _designer.active:
		_designer.update_materialized_positions()


func _fit_body() -> void:
	var vp := size
	var aspect := BODY_W / BODY_H
	var draw_h := vp.y * _zoom
	var draw_w := draw_h * aspect
	if draw_w > vp.x * _zoom:
		draw_w = vp.x * _zoom
		draw_h = draw_w / aspect
	body.position = Vector2((vp.x - draw_w) / 2.0 + _pan.x, (vp.y - draw_h) / 2.0 + _pan.y)
	body.size = Vector2(draw_w, draw_h)


func _apply_zones() -> void:
	_designer.apply_zones_to_nodes()
	screen_content.position = Vector2.ZERO
	screen_content.size = screen_zone.size
	cook_progress.position = Vector2(8, 4)
	cook_progress.size = Vector2(oven_zone.size.x * 0.6, 14)
	cook_status.position = Vector2(8, 22)
	cook_timer.position = Vector2(oven_zone.size.x - 70, 4)


# ═══════════════════════════════════════════════════════════
#  СИГНАЛЫ
# ═══════════════════════════════════════════════════════════

func _connect_signals() -> void:
	machine.state_changed.connect(_on_state_changed)
	queue_mgr.cooking_started.connect(_on_cook_start)
	queue_mgr.cooking_progress.connect(_on_cook_progress)
	queue_mgr.cooking_finished.connect(_on_cook_finish)
	queue_mgr.dispensing_finished.connect(_on_dispense_finish)
	next_button.pressed.connect(_on_next_pressed)


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
		MachineController.State.PAYMENT:
			machine.transition_to(MachineController.State.QUEUE)
		MachineController.State.FINISH:
			machine.transition_to(MachineController.State.IDLE)


# ═══════════════════════════════════════════════════════════
#  СОСТОЯНИЯ
# ═══════════════════════════════════════════════════════════

func _on_state_changed(_old: MachineController.State, new_state: MachineController.State) -> void:
	_update_ui_for_state(new_state)


func _update_ui_for_state(state: MachineController.State) -> void:
	screen_zone.visible = true
	dispense_zone.visible = true
	next_button.visible = true
	match state:
		MachineController.State.IDLE:
			next_button.text = "🍕 НАЧАТЬ ЗАКАЗ"; cook_status.text = "Ожидание..."
		MachineController.State.SELECT_MODE:
			next_button.text = "ДАЛЕЕ →"
		MachineController.State.SELECT_PARAMETERS:
			next_button.text = "ДАЛЕЕ →"
		MachineController.State.BUILDING_COMPOSITION:
			next_button.text = "ДАЛЕЕ →"
		MachineController.State.PROMO_CODE:
			next_button.text = "К ОПЛАТЕ →"
		MachineController.State.PAYMENT:
			next_button.text = "💳 ОПЛАТИТЬ"
		MachineController.State.QUEUE:
			next_button.text = "🍕 НОВЫЙ ЗАКАЗ"
		MachineController.State.COOKING:
			cook_status.text = "Готовим твою пиццу..."
		MachineController.State.DISPENSING:
			cook_status.text = "Выдаём..."; pizza_box.visible = true
		MachineController.State.FINISH:
			cook_status.text = "Готово! Забери пиццу"; next_button.text = "🍕 НОВЫЙ ЗАКАЗ"


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
	var tl := int(time_left)
	@warning_ignore("INTEGER_DIVISION")
	cook_timer.text = "%02d:%02d" % [tl / 60, tl % 60]


func _on_cook_finish(order) -> void:
	cook_status.text = "✅ Готово: %s" % str(order)
	cook_progress.value = 100; cook_timer.text = "00:00"
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
