class_name ClickableSprite
extends Node2D
## Кликабельный спрайт-компонент для вендингового автомата.
## Sprite2D (фон) + ручной хит-тест через _input (работает внутри Control иерархии).
## Поддерживает анимации hover, тактильного нажатия (click bounce) и селекторы.
## Любые дочерние ноды (иконки, лейблы) рисуются ПОВЕРХ фона.

signal clicked

var tex_normal: Texture2D
var tex_selected: Texture2D
var btn_size := Vector2(100, 50)
var selected := false

var base_position := Vector2.ZERO
var _hovered := false
var _click_tween: Tween
var _hover_tween: Tween


func _ready() -> void:
	if base_position == Vector2.ZERO:
		base_position = position
	# Фон-спрайт (создаётся первым → рисуется под иконками/лейблами)
	var s := Sprite2D.new()
	s.name = "Spr"
	s.centered = false
	add_child(s)
	_refresh()


func set_base_position(pos: Vector2) -> void:
	base_position = pos
	position = pos


func _refresh() -> void:
	var s = get_node_or_null("Spr") as Sprite2D
	if s == null:
		return
	var t: Texture2D = tex_selected if selected and tex_selected else tex_normal
	if t:
		s.texture = t
		s.scale = btn_size / t.get_size()
	else:
		s.texture = null


func set_selected(v: bool) -> void:
	selected = v
	_refresh()


func set_texture(t: Texture2D) -> void:
	tex_normal = t
	if not selected:
		_refresh()


## Тактильная пружинящая анимация нажатия (кнопка сжимается к своему центру и отскакивает)
func play_click_anim() -> void:
	if _click_tween and _click_tween.is_valid():
		_click_tween.kill()
	_click_tween = create_tween()
	var half := btn_size * 0.5
	# Быстрое сжатие к центру кнопки
	_click_tween.tween_property(self, "scale", Vector2(0.92, 0.92), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_click_tween.parallel().tween_property(self, "position", base_position + half * 0.08, 0.05)
	# Пружинящий возврат в исходное состояние
	_click_tween.chain().tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_click_tween.parallel().tween_property(self, "position", base_position, 0.14)


## Хит-тест: проверяем попадание мыши в глобальный прямоугольник кнопки
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	var gp := global_position
	var gs := global_scale
	var rect := Rect2(gp, btn_size * gs)
	var mouse_pos := get_global_mouse_position()
	var is_in_rect := rect.has_point(mouse_pos)

	# Клик мышью
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_in_rect:
			play_click_anim()
			clicked.emit()
			get_viewport().set_input_as_handled()

	# Подсветка при наведении (hover)
	elif event is InputEventMouseMotion:
		if is_in_rect != _hovered:
			_hovered = is_in_rect
			if _hover_tween and _hover_tween.is_valid():
				_hover_tween.kill()
			_hover_tween = create_tween()
			var target_col := Color(1.15, 1.15, 1.15) if _hovered else Color.WHITE
			_hover_tween.tween_property(self, "modulate", target_col, 0.1)


## Фабрика: создать ClickableSprite с параметрами (до добавления в дерево)
static func make(tn: Texture2D, ts: Texture2D, sz: Vector2, pos: Vector2) -> ClickableSprite:
	var o := ClickableSprite.new()
	o.tex_normal = tn
	o.tex_selected = ts
	o.btn_size = sz
	o.position = pos
	o.base_position = pos
	return o
