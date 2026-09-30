extends Control
# ═══════════════════════════════════════════════════════════
#  🍕 PIZZA MARKET — 2D пиццемат-симулятор
#  Каркас whole_body.png (1614×1536)
#  Панель заказа: ScreenPanel (Node2D + ClickableSprite + Area2D)
# ═══════════════════════════════════════════════════════════

const BODY_W := 1614.0
const BODY_H := 1536.0
const ZOOM_MIN := 0.3
const ZOOM_MAX := 3.0
const ZOOM_STEP := 0.1

const SCREEN_RECT := Rect2(1044, 220, 432, 924)
const OVEN_RECT := Rect2(144, 340, 756, 552)
const DISPENSE_RECT := Rect2(212, 1172, 620, 116)
const BAR_RECT := Rect2(12, 1320, 640, 120)

var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _pan_start := Vector2.ZERO

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
@onready var ingredients_zone: Control = $MachineBody/IngredientsZone

var _game_data: Node
var _panel: ScreenPanel
var _designer: Designer


func _ready() -> void:
	_game_data = get_node_or_null("/root/GameData")
	# Скрыть ВЕСЬ старый Godot UI — используем только ScreenPanel
	ingredients_zone.visible = false
	screen_content.visible = false
	next_button.visible = false
	pizza_box.visible = false
	# Скрыть стандартные текстовые ноды в OvenZone
	cook_status.visible = false
	cook_timer.visible = false
	cook_progress.visible = false
	# Убрать перехват ввода Control-нодами — клики идут к Area2D в ClickableSprite
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	oven_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dispense_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Создать панель на основе ClickableSprite компонентов
	_panel = ScreenPanel.new()
	_panel.name = "Panel"
	screen_zone.add_child(_panel)
	# Подключить сигналы панели
	_panel.next_pressed.connect(_on_next_pressed)
	_panel.mode_changed.connect(_on_mode_changed)
	_panel.preset_changed.connect(_on_preset_changed)
	_panel.size_changed.connect(_on_size_changed)
	_panel.dough_changed.connect(_on_dough_changed)
	_panel.height_changed.connect(_on_height_changed)
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
	call_deferred("_on_resized")


# ═══ ZOOM / PAN / RESIZE ═══

func _apply_zoom_pan() -> void:
	var vp := get_viewport().get_visible_rect().size
	var bh := vp.y * _zoom
	var bw := bh * (BODY_W / BODY_H)
	body.position = Vector2((vp.x - bw) / 2.0 + _pan.x, (vp.y - bh) / 2.0 + _pan.y)
	body.size = Vector2(bw, bh)
	_zone(oven_zone, OVEN_RECT)
	_zone(screen_zone, SCREEN_RECT)
	_zone(dispense_zone, DISPENSE_RECT)
	_zone(bottom_bar, BAR_RECT)
	if _panel:
		_panel.scale = screen_zone.size / Vector2(ScreenPanel.PW, ScreenPanel.PH)

func _zone(z: Control, r: Rect2) -> void:
	var s := Vector2(body.size.x / BODY_W, body.size.y / BODY_H)
	z.position = r.position * s
	z.size = r.size * s

func _on_resized() -> void:
	_apply_zoom_pan()

func _unhandled_input(event: InputEvent) -> void:
	# Zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX); _apply_zoom_pan()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX); _apply_zoom_pan()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			if _panning:
				_pan_start = event.position
	# Pan
	if event is InputEventMouseMotion and _panning:
		_pan += event.position - _pan_start
		_pan_start = event.position
		_apply_zoom_pan()
	# F3 reset zoom
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_zoom = 1.0; _pan = Vector2.ZERO; _apply_zoom_pan()
	# F1 — дебаг-дизайнер
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_toggle_designer()


# ═══ ДИЗАЙНЕР (F1) ═══

func _toggle_designer() -> void:
	if _designer == null:
		_designer = Designer.new()
		_designer.setup(self, body, BODY_W, BODY_H)
	_designer.toggle()


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


# ═══ НАВИГАЦИЯ ═══

func _on_next_pressed() -> void:
	match machine.current_state:
		MachineController.State.IDLE:
			order_mgr.create_new_order()
			# Сразу на панель параметров (ручной режим по умолчанию)
			machine.force_transition(MachineController.State.SELECT_PARAMETERS)
		MachineController.State.SELECT_PARAMETERS:
			# После выбора параметров — сразу оплата
			machine.force_transition(MachineController.State.PAYMENT)
		MachineController.State.PAYMENT:
			machine.force_transition(MachineController.State.QUEUE)
		MachineController.State.FINISH:
			machine.force_transition(MachineController.State.IDLE)


# ═══ FSM ═══

func _on_state_changed(_o: MachineController.State, ns: MachineController.State) -> void:
	_panel.show_state(ns)
	match ns:
		MachineController.State.DISPENSING:
			pizza_box.visible = true
		MachineController.State.FINISH:
			pass


# ═══ ГОТОВКА ═══

func _on_cook_start(order) -> void:
	cook_progress.value = 0
	if machine.current_state == MachineController.State.QUEUE:
		machine.force_transition(MachineController.State.COOKING)

func _on_cook_progress(progress: float, _time_left: float) -> void:
	cook_progress.value = progress * 100.0

func _on_cook_finish(_order) -> void:
	cook_progress.value = 100
	pizza_box.visible = true
	if machine.current_state == MachineController.State.COOKING:
		machine.force_transition(MachineController.State.DISPENSING)

func _on_dispense_finish(_order) -> void:
	if machine.current_state == MachineController.State.DISPENSING:
		machine.force_transition(MachineController.State.FINISH)
	await get_tree().create_timer(3.0).timeout
	pizza_box.visible = false
	cook_progress.value = 0
