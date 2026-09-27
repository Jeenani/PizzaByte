class_name ClickableSprite
extends Node2D
## Кликабельный спрайт-компонент для вендингового автомата.
## Sprite2D (фон) + ручной хит-тест через _input (работает внутри Control иерархии).
## Любые дочерние ноды (иконки, лейблы) рисуются ПОВЕРХ фона.

signal clicked

var tex_normal: Texture2D
var tex_selected: Texture2D
var btn_size := Vector2(100, 50)
var selected := false


func _ready() -> void:
	# Фон-спрайт (создаётся первым → рисуется под иконками/лейблами)
	var s := Sprite2D.new()
	s.name = "Spr"
	s.centered = false
	add_child(s)
	_refresh()


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


## Хит-тест: проверяем попадание мыши в глобальный прямоугольник кнопки
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var gp := global_position
		var gs := global_scale
		var rect := Rect2(gp, btn_size * gs)
		if rect.has_point(event.global_position):
			clicked.emit()
			get_viewport().set_input_as_handled()


## Фабрика: создать ClickableSprite с параметрами (до добавления в дерево)
static func make(tn: Texture2D, ts: Texture2D, sz: Vector2, pos: Vector2) -> ClickableSprite:
	var o := ClickableSprite.new()
	o.tex_normal = tn
	o.tex_selected = ts
	o.btn_size = sz
	o.position = pos
	return o
