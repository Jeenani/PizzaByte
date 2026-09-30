class_name Designer
extends RefCounted
## Визуальный конструктор (Figma-like) для Pizza Machine
## Единое дерево элементов: zone | sprite | text | group
## Дочерние координаты — относительно родителя
## Tree-виджет в панели, drag-and-drop для группировки

const FONT_PATH := "res://assets/textures/font/minecraft-rus-regular1.ttf"
const LAYOUT_PATH := "res://assets/sprite_layout.json"
const PANEL_W := 300.0
const GRID_STEP := 64

## Типы элементов
enum EType { ZONE, SPRITE, TEXT, GROUP }

## Единый элемент дерева
## rect — ОТНОСИТЕЛЬНО родителя (если parent_id == "root" — относительно текстуры)
var _elements: Dictionary = {}  # id -> Dictionary
var _root_children: Array = []  # порядок корневых элементов (id)
var _next_id: int = 1

## Шрифт
var _font: Font = null

## Ссылки на UI
var _host: Control           # Main node
var _body: TextureRect       # каркас
var _overlay: Control        # рисование
var _panel: PanelContainer
var _tree: Tree
var _props: Dictionary = {}  # name -> Control
var _updating_props := false
var _add_text_btn: Button
var _add_group_btn: Button
var _text_input: LineEdit     # для ввода текста нового элемента

## Body size (текстура)
var body_w := 1614.0
var body_h := 1536.0

## Материализация — реальные ноды для интерактива
var _materialized_nodes: Dictionary = {}  # id -> Node
var _click_callback = null  # Callable, main.gd устанавливает

## Состояние
var active := false
var selected_id: String = ""
var dragging := false
var resizing := false
var drag_offset := Vector2.ZERO


# ═══════════════════════════════════════════════════════════
#  СОЗДАНИЕ ЭЛЕМЕНТА
# ═══════════════════════════════════════════════════════════

## Проверка фокуса на полях ввода панели
func has_focused_input() -> bool:
	if not active or _panel == null or _host == null:
		return false
	var fw = _host.get_viewport().gui_get_focus_owner()
	if fw == null:
		return false
	if fw is LineEdit or fw is SpinBox:
		var p = fw
		while p != null:
			if p == _panel:
				return true
			p = p.get_parent()
	return false


func _gen_id() -> String:
	var id := "e%d" % _next_id
	_next_id += 1
	return id


func add_element(data: Dictionary) -> String:
	var id := _gen_id()
	data["id"] = id
	if not data.has("parent_id"):
		data["parent_id"] = ""
	if not data.has("children"):
		data["children"] = []
	if not data.has("visible"):
		data["visible"] = true
	if not data.has("z_index"):
		data["z_index"] = 0
	_elements[id] = data
	# Добавить в children родителя или в root
	if data["parent_id"] == "" or not _elements.has(data["parent_id"]):
		data["parent_id"] = ""
		_root_children.append(id)
	else:
		_elements[data["parent_id"]]["children"].append(id)
	return id


func add_zone(name_str: String, rect: Rect2, color: Color, node_name: String) -> String:
	return add_element({
		"type": EType.ZONE, "name": name_str, "rect": rect,
		"color": color, "node": node_name,
	})


func add_sprite(name_str: String, res_path: String, tex: Texture2D, rect: Rect2) -> String:
	return add_element({
		"type": EType.SPRITE, "name": name_str, "path": res_path,
		"texture": tex, "rect": rect,
	})


func add_text(text: String, pos: Vector2, font_size: int = 24, font_color: Color = Color.WHITE, parent_id: String = "") -> String:
	var w := float(text.length() * font_size) * 0.65
	var h := float(font_size) * 1.3
	return add_element({
		"type": EType.TEXT, "name": "txt_" + text.left(12).strip_edges(),
		"rect": Rect2(pos.x, pos.y, w, h),
		"text": text, "font_size": font_size, "font_color": font_color,
		"parent_id": parent_id,
	})


func add_group(name_str: String, pos: Vector2 = Vector2.ZERO, sz: Vector2 = Vector2(200, 200), parent_id: String = "") -> String:
	return add_element({
		"type": EType.GROUP, "name": name_str,
		"rect": Rect2(pos.x, pos.y, sz.x, sz.y),
		"color": Color(0.5, 0.5, 1.0, 0.1),
		"parent_id": parent_id,
	})


# ═══════════════════════════════════════════════════════════
#  ДЕРЕВО: вычисление абсолютных координат
# ═══════════════════════════════════════════════════════════

## Абсолютный rect (суммируя rect'ы вверх по дереву)
func abs_rect(id: String) -> Rect2:
	var el = _elements.get(id)
	if el == null:
		return Rect2()
	var r: Rect2 = el["rect"]
	var pid: String = el["parent_id"]
	while pid != "" and _elements.has(pid):
		var p = _elements[pid]
		r.position += p["rect"].position
		pid = p["parent_id"]
	return r


## Все видимые элементы в порядке отрисовки (плоский обход DFS)
func _flatten_visible(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var el = _elements.get(id)
		if el == null:
			continue
		if not el["visible"]:
			continue
		out.append(id)
		if el["children"].size() > 0:
			out.append_array(_flatten_visible(el["children"]))
	return out


func all_visible_ordered() -> Array:
	return _flatten_visible(_root_children)


## Найти элемент по экранной точке (обратный порядок = верхний первым)
func pick_at(screen_pos: Vector2) -> String:
	var ordered := all_visible_ordered()
	for i in range(ordered.size() - 1, -1, -1):
		var id: String = ordered[i]
		var r := _tex_to_screen(abs_rect(id))
		if r.has_point(screen_pos):
			return id
	return ""


# ═══════════════════════════════════════════════════════════
#  REPARENT — перенос элемента в другого родителя
# ═══════════════════════════════════════════════════════════

func reparent(child_id: String, new_parent_id: String) -> void:
	var child = _elements.get(child_id)
	if child == null:
		return
	# Нельзя стать своим потомком
	if _is_descendant(new_parent_id, child_id):
		return
	# Абсолютная позиция до reparent
	var abs_before := abs_rect(child_id).position
	# Убрать из старого родителя
	var old_pid: String = child["parent_id"]
	if old_pid == "" or not _elements.has(old_pid):
		_root_children.erase(child_id)
	else:
		_elements[old_pid]["children"].erase(child_id)
	# Новый родитель
	if new_parent_id == "" or not _elements.has(new_parent_id):
		child["parent_id"] = ""
		_root_children.append(child_id)
	else:
		child["parent_id"] = new_parent_id
		_elements[new_parent_id]["children"].append(child_id)
	# Пересчитать relative rect чтобы abs позиция не изменилась
	var abs_new_parent := Vector2.ZERO
	if new_parent_id != "" and _elements.has(new_parent_id):
		abs_new_parent = abs_rect(new_parent_id).position
	child["rect"].position = abs_before - abs_new_parent


func _is_descendant(check_id: String, ancestor_id: String) -> bool:
	if check_id == "" or check_id == ancestor_id:
		return check_id == ancestor_id
	var el = _elements.get(check_id)
	if el == null:
		return false
	return _is_descendant(el["parent_id"], ancestor_id)


# ═══════════════════════════════════════════════════════════
#  КООРДИНАТНАЯ MATH
# ═══════════════════════════════════════════════════════════

func _tex_scale() -> Vector2:
	return Vector2(_body.size.x / body_w, _body.size.y / body_h)

func _tex_to_screen(r: Rect2) -> Rect2:
	var s := _tex_scale()
	return Rect2(_body.position + r.position * s, r.size * s)

func _screen_to_tex(p: Vector2) -> Vector2:
	var s := _tex_scale()
	if s.x < 0.001 or s.y < 0.001:
		return Vector2.ZERO
	return (p - _body.position) / s

func _tex_to_body(r: Rect2) -> Rect2:
	var s := _tex_scale()
	return Rect2(r.position * s, r.size * s)


# ═══════════════════════════════════════════════════════════
#  INIT
# ═══════════════════════════════════════════════════════════

func setup(host: Control, body_node: TextureRect, bw: float, bh: float) -> void:
	_host = host
	_body = body_node
	body_w = bw
	body_h = bh
	# Шрифт
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	if _font == null:
		_font = ThemeDB.fallback_font
	_create_overlay()
	_create_panel()
	_load_sprites()
	load_layout()


func _create_overlay() -> void:
	_overlay = Control.new()
	_overlay.name = "DesignerOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.add_child(_overlay)
	_overlay.draw.connect(_draw_all)


func _create_panel() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DesignerCanvas"
	canvas.layer = 100
	_host.add_child(canvas)

	_panel = PanelContainer.new()
	_panel.name = "DesignerPanel"
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	canvas.add_child(_panel)

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.06, 0.1, 0.95)
	ps.set_border_width_all(1)
	ps.border_color = Color(0.3, 1.0, 0.5, 0.5)
	ps.set_content_margin_all(6)
	_panel.add_theme_stylebox_override("panel", ps)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 3)
	_panel.add_child(root_vbox)

	# Заголовок
	var title := Label.new()
	title.text = "🔧 DESIGNER"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	# Подсказки
	var hints := Label.new()
	hints.text = "F2:Log F3:Reset F4:Save F5:Load\nDrag:move Shift+Drag:resize Del:toggle"
	hints.add_theme_font_size_override("font_size", 9)
	hints.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	root_vbox.add_child(hints)

	# ── Кнопки добавления ──
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 3)
	root_vbox.add_child(add_row)

	_add_text_btn = Button.new()
	_add_text_btn.text = "+ Текст"
	_add_text_btn.add_theme_font_size_override("font_size", 11)
	_add_text_btn.pressed.connect(_on_add_text)
	add_row.add_child(_add_text_btn)

	_add_group_btn = Button.new()
	_add_group_btn.text = "+ Группа"
	_add_group_btn.add_theme_font_size_override("font_size", 11)
	_add_group_btn.pressed.connect(_on_add_group)
	add_row.add_child(_add_group_btn)

	var reparent_btn := Button.new()
	reparent_btn.text = "↳ В родителя"
	reparent_btn.add_theme_font_size_override("font_size", 11)
	reparent_btn.tooltip_text = "Переместить выбранный элемент в ближайшую группу/зону под курсором"
	reparent_btn.pressed.connect(_on_reparent_to_selected_parent)
	add_row.add_child(reparent_btn)

	# Текстовый ввод для нового текста
	_text_input = LineEdit.new()
	_text_input.placeholder_text = "Текст для добавления..."
	_text_input.add_theme_font_size_override("font_size", 11)
	_text_input.custom_minimum_size = Vector2(0, 26)
	root_vbox.add_child(_text_input)

	# ── Свойства (ПЕРЕД деревом — чтобы всегда были видны) ──
	var props_lbl := Label.new()
	props_lbl.text = "━━ СВОЙСТВА ━━"
	props_lbl.add_theme_font_size_override("font_size", 10)
	props_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
	props_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(props_lbl)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	root_vbox.add_child(grid)

	_add_spin(grid, "X", -1000, 3000, 1)
	_add_spin(grid, "Y", -1000, 3000, 1)
	_add_spin(grid, "W", 8, 3000, 1)
	_add_spin(grid, "H", 8, 3000, 1)
	_add_spin(grid, "Z", 0, 100, 1)
	_add_spin(grid, "FontSz", 6, 120, 1)
	_add_check(grid, "Vis")

	# Редактор текста (содержимого выбранного текстового элемента)
	var text_edit_lbl := Label.new()
	text_edit_lbl.text = "Текст:"
	text_edit_lbl.add_theme_font_size_override("font_size", 11)
	text_edit_lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	grid.add_child(text_edit_lbl)
	var text_edit := LineEdit.new()
	text_edit.add_theme_font_size_override("font_size", 11)
	text_edit.custom_minimum_size = Vector2(100, 0)
	text_edit.placeholder_text = "(выберите текст)"
	text_edit.text_changed.connect(_on_text_edit_changed)
	grid.add_child(text_edit)
	_props["Text"] = text_edit

	# ── Дерево элементов (в ScrollContainer) ──
	var tree_lbl := Label.new()
	tree_lbl.text = "━━ ЭЛЕМЕНТЫ ━━"
	tree_lbl.add_theme_font_size_override("font_size", 10)
	tree_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
	tree_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(tree_lbl)

	var tree_scroll := ScrollContainer.new()
	tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_scroll.custom_minimum_size = Vector2(0, 200)
	root_vbox.add_child(tree_scroll)

	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(0, 400)
	_tree.add_theme_font_size_override("font_size", 11)
	_tree.hide_root = true
	_tree.columns = 1
	var tree_style := StyleBoxFlat.new()
	tree_style.bg_color = Color(0.04, 0.04, 0.07, 0.9)
	tree_style.set_content_margin_all(3)
	_tree.add_theme_stylebox_override("panel", tree_style)
	_tree.item_selected.connect(_on_tree_selected)
	tree_scroll.add_child(_tree)

	# Кнопка "Извлечь из родителя"
	var unparent_btn := Button.new()
	unparent_btn.text = "↑ Извлечь (корень)"
	unparent_btn.add_theme_font_size_override("font_size", 11)
	unparent_btn.pressed.connect(_on_unparent)
	root_vbox.add_child(unparent_btn)

	# ── Кнопки Save/Load/Log ──
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 3)
	root_vbox.add_child(btn_row)
	var sb := Button.new()
	sb.text = "💾Save"
	sb.add_theme_font_size_override("font_size", 11)
	sb.pressed.connect(save_layout)
	btn_row.add_child(sb)
	var lb := Button.new()
	lb.text = "📂Load"
	lb.add_theme_font_size_override("font_size", 11)
	lb.pressed.connect(func(): load_layout(); refresh())
	btn_row.add_child(lb)
	var lgb := Button.new()
	lgb.text = "📋Log"
	lgb.add_theme_font_size_override("font_size", 11)
	lgb.pressed.connect(log_all)
	btn_row.add_child(lgb)
	var del_btn := Button.new()
	del_btn.text = "🗑Del"
	del_btn.add_theme_font_size_override("font_size", 11)
	del_btn.pressed.connect(_on_delete_element)
	btn_row.add_child(del_btn)


func _add_spin(parent: GridContainer, lbl: String, mn: float, mx: float, st: float) -> void:
	var l := Label.new()
	l.text = lbl + ":"
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	l.custom_minimum_size = Vector2(42, 0)
	parent.add_child(l)
	var s := SpinBox.new()
	s.min_value = mn; s.max_value = mx; s.step = st
	s.custom_minimum_size = Vector2(90, 0)
	s.add_theme_font_size_override("font_size", 11)
	s.value_changed.connect(_on_prop_changed.bind(lbl))
	s.editable = false
	parent.add_child(s)
	_props[lbl] = s


func _add_check(parent: GridContainer, lbl: String) -> void:
	var l := Label.new()
	l.text = lbl + ":"
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	parent.add_child(l)
	var cb := CheckBox.new()
	cb.text = "Да"
	cb.add_theme_font_size_override("font_size", 10)
	cb.toggled.connect(_on_vis_toggled)
	parent.add_child(cb)
	_props[lbl] = cb


# ═══════════════════════════════════════════════════════════
#  ЗАГРУЗКА СПРАЙТОВ
# ═══════════════════════════════════════════════════════════

func _load_sprites() -> void:
	_scan_dir("res://assets/textures/")
	print("[Designer] Загружено %d элементов" % _elements.size())


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var fp := path + f
		if dir.current_is_dir():
			_scan_dir(fp + "/")
		elif f.ends_with(".png") and f != "whole_body.png":
			var tex := load(fp) as Texture2D
			if tex:
				var tw := float(tex.get_width())
				var th := float(tex.get_height())
				var md := 200.0
				var sc := 1.0
				if tw > md or th > md:
					sc = md / maxf(tw, th)
				var x := (body_w - tw * sc) / 2.0
				var y := (body_h - th * sc) / 2.0 + _elements.size() * 20.0
				add_sprite(f.get_basename(), fp, tex, Rect2(x, y, tw * sc, th * sc))
		f = dir.get_next()
	dir.list_dir_end()


# ═══════════════════════════════════════════════════════════
#  TOGGLE / REFRESH
# ═══════════════════════════════════════════════════════════

func toggle() -> void:
	active = not active
	_panel.visible = active
	if active:
		refresh()
		_panel.size.y = _host.get_viewport().get_visible_rect().size.y
	else:
		selected_id = ""
		dragging = false
		resizing = false
	_overlay.queue_redraw()


func refresh() -> void:
	_rebuild_tree()
	_refresh_props()
	_overlay.queue_redraw()


func on_resized() -> void:
	_overlay.queue_redraw()
	if active and _panel:
		_panel.size.y = _host.get_viewport().get_visible_rect().size.y


# ═══════════════════════════════════════════════════════════
#  TREE WIDGET
# ═══════════════════════════════════════════════════════════

func _rebuild_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	_build_tree_branch(root, _root_children)
	# Раскрыть всё
	_expand_all(root)


func _build_tree_branch(parent_item: TreeItem, child_ids: Array) -> void:
	for id in child_ids:
		var el = _elements.get(id)
		if el == null:
			continue
		var item := _tree.create_item(parent_item)
		var icon := ""
		match el["type"]:
			EType.ZONE: icon = "🔲"
			EType.SPRITE: icon = "🖼" if el["visible"] else "🚫"
			EType.TEXT: icon = "📝"
			EType.GROUP: icon = "📁"
		item.set_text(0, "%s %s" % [icon, el["name"]])
		item.set_metadata(0, id)
		if id == selected_id:
			item.select(0)
		if el["children"].size() > 0:
			_build_tree_branch(item, el["children"])


func _expand_all(item: TreeItem) -> void:
	item.collapsed = false
	var child := item.get_first_child()
	while child:
		_expand_all(child)
		child = child.get_next()


func _on_tree_selected() -> void:
	var sel := _tree.get_selected()
	if sel:
		selected_id = sel.get_metadata(0)
	else:
		selected_id = ""
	_refresh_props()
	_overlay.queue_redraw()


# ═══════════════════════════════════════════════════════════
#  СВОЙСТВА
# ═══════════════════════════════════════════════════════════

func _refresh_props() -> void:
	_updating_props = true
	var has_sel := selected_id != "" and _elements.has(selected_id)
	for key in _props:
		var c = _props[key]
		if c is SpinBox:
			c.editable = has_sel
		elif c is CheckBox:
			c.disabled = not has_sel
		elif c is LineEdit:
			c.editable = has_sel
	if not has_sel:
		_updating_props = false
		return
	var el = _elements[selected_id]
	var r: Rect2 = el["rect"]
	_props["X"].value = r.position.x
	_props["Y"].value = r.position.y
	_props["W"].value = r.size.x
	_props["H"].value = r.size.y
	_props["Z"].value = el.get("z_index", 0)
	if el["type"] == EType.SPRITE and el.has("texture"):
		var tex: Texture2D = el["texture"]
		_props["FontSz"].value = r.size.x / maxf(float(tex.get_width()), 1.0) * 100.0
		_props["FontSz"].suffix = "%"
	elif el["type"] == EType.TEXT:
		_props["FontSz"].value = el.get("font_size", 24)
		_props["FontSz"].suffix = "px"
	else:
		_props["FontSz"].value = 0
		_props["FontSz"].suffix = ""
	_props["FontSz"].editable = (el["type"] == EType.TEXT or el["type"] == EType.SPRITE)
	_props["Vis"].set_pressed_no_signal(el["visible"])
	_props["Vis"].text = "Да" if el["visible"] else "Нет"
	# Текстовое поле — НЕ обновлять если пользователь сейчас в нём печатает
	var text_field: LineEdit = _props["Text"]
	if not text_field.has_focus():
		text_field.text = el.get("text", "")
	text_field.editable = (el["type"] == EType.TEXT)
	_updating_props = false


func _on_prop_changed(value: float, prop: String) -> void:
	if _updating_props or selected_id == "":
		return
	var el = _elements.get(selected_id)
	if el == null:
		return
	match prop:
		"X": el["rect"].position.x = value
		"Y": el["rect"].position.y = value
		"W":
			el["rect"].size.x = value
			if el["type"] == EType.SPRITE and el.has("texture"):
				var tex: Texture2D = el["texture"]
				var asp := float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
				el["rect"].size.y = value * asp
				_updating_props = true
				_props["H"].value = el["rect"].size.y
				_updating_props = false
		"H": el["rect"].size.y = value
		"Z": el["z_index"] = int(value)
		"FontSz":
			if el["type"] == EType.TEXT:
				el["font_size"] = int(value)
				# Пересчитать размер текста
				var txt: String = el.get("text", "")
				el["rect"].size.x = float(txt.length()) * value * 0.65
				el["rect"].size.y = value * 1.3
				_updating_props = true
				_props["W"].value = el["rect"].size.x
				_props["H"].value = el["rect"].size.y
				_updating_props = false
			elif el["type"] == EType.SPRITE and el.has("texture"):
				var tex: Texture2D = el["texture"]
				var sc := value / 100.0
				el["rect"].size.x = tex.get_width() * sc
				el["rect"].size.y = tex.get_height() * sc
				_updating_props = true
				_props["W"].value = el["rect"].size.x
				_props["H"].value = el["rect"].size.y
				_updating_props = false
	_overlay.queue_redraw()


func _on_vis_toggled(pressed: bool) -> void:
	if _updating_props or selected_id == "":
		return
	var el = _elements.get(selected_id)
	if el:
		el["visible"] = pressed
		_props["Vis"].text = "Да" if pressed else "Нет"
		_rebuild_tree()
		_overlay.queue_redraw()


func _on_text_edit_changed(new_text: String) -> void:
	if _updating_props or selected_id == "":
		return
	var el = _elements.get(selected_id)
	if el and el["type"] == EType.TEXT:
		el["text"] = new_text
		el["name"] = "txt_" + new_text.left(12).strip_edges()
		var fs: int = el.get("font_size", 24)
		el["rect"].size.x = float(new_text.length()) * fs * 0.65
		el["rect"].size.y = fs * 1.3
		_updating_props = true
		_props["W"].value = el["rect"].size.x
		_props["H"].value = el["rect"].size.y
		_updating_props = false
		# НЕ вызываем _rebuild_tree() — она сбрасывает курсор через
		# _on_tree_selected → _refresh_props → text = ...
		# Имя в дереве обновится при следующем refresh()
		_overlay.queue_redraw()


# ═══════════════════════════════════════════════════════════
#  ДОБАВЛЕНИЕ ЭЛЕМЕНТОВ (кнопки панели)
# ═══════════════════════════════════════════════════════════

func _on_add_text() -> void:
	var txt := _text_input.text.strip_edges()
	if txt.is_empty():
		txt = "Новый текст"
	var parent := ""
	var el = _elements.get(selected_id)
	if el and (el["type"] == EType.GROUP or el["type"] == EType.ZONE):
		parent = selected_id
	var pos := Vector2(body_w / 2.0 - 100, body_h / 2.0)
	var id := add_text(txt, pos, 24, Color.WHITE, parent)
	selected_id = id
	_text_input.text = ""
	refresh()


func _on_add_group() -> void:
	var parent := ""
	var el = _elements.get(selected_id)
	if el and (el["type"] == EType.GROUP or el["type"] == EType.ZONE):
		parent = selected_id
	var id := add_group("Group_%d" % _next_id, Vector2(100, 100), Vector2(300, 300), parent)
	selected_id = id
	refresh()


func _on_reparent_to_selected_parent() -> void:
	if selected_id == "":
		return
	# Найти ближайший подходящий контейнер
	for id in _root_children:
		var el = _elements.get(id)
		if el == null:
			continue
		if id == selected_id:
			continue
		if el["type"] == EType.GROUP or el["type"] == EType.ZONE:
			# Проверить: selected попадает внутрь abs_rect?
			var ar := abs_rect(id)
			var sr := abs_rect(selected_id)
			if ar.encloses(sr):
				reparent(selected_id, id)
				refresh()
				return
	# Если не нашли — поискать глубже
	var ordered := all_visible_ordered()
	for i in range(ordered.size() - 1, -1, -1):
		var id: String = ordered[i]
		if id == selected_id:
			continue
		var el = _elements.get(id)
		if el["type"] != EType.GROUP and el["type"] != EType.ZONE:
			continue
		var ar := abs_rect(id)
		var sr := abs_rect(selected_id)
		if ar.encloses(sr):
			reparent(selected_id, id)
			refresh()
			return


func _on_unparent() -> void:
	if selected_id == "":
		return
	reparent(selected_id, "")
	refresh()


func _on_delete_element() -> void:
	if selected_id == "":
		return
	var el = _elements.get(selected_id)
	if el == null:
		return
	# Нельзя удалять зоны
	if el["type"] == EType.ZONE:
		return
	# Дети переходят в корень
	for cid in el["children"].duplicate():
		reparent(cid, el["parent_id"])
	# Убрать из родителя
	if el["parent_id"] == "" or not _elements.has(el["parent_id"]):
		_root_children.erase(selected_id)
	else:
		_elements[el["parent_id"]]["children"].erase(selected_id)
	_elements.erase(selected_id)
	selected_id = ""
	refresh()


# ═══════════════════════════════════════════════════════════
#  DRAG / SELECT / RESIZE
# ═══════════════════════════════════════════════════════════

func try_select(screen_pos: Vector2, shift: bool) -> void:
	# Ручка ресайза
	if selected_id != "":
		var r := _tex_to_screen(abs_rect(selected_id))
		var hs := 14.0
		var handle := Rect2(r.end.x - hs, r.end.y - hs, hs, hs)
		if handle.has_point(screen_pos):
			resizing = true
			dragging = false
			return
	if shift and selected_id != "":
		resizing = true
		dragging = false
		return
	var id := pick_at(screen_pos)
	if id != "":
		selected_id = id
		dragging = true
		drag_offset = screen_pos - _tex_to_screen(abs_rect(id)).position
		refresh()
		return
	selected_id = ""
	dragging = false
	resizing = false
	refresh()


func do_drag(screen_pos: Vector2) -> void:
	if selected_id == "":
		return
	var el = _elements.get(selected_id)
	if el == null:
		return
	var new_screen := screen_pos - drag_offset
	var tex_pos := _screen_to_tex(new_screen)
	# Snap 4px
	tex_pos.x = roundf(tex_pos.x / 4.0) * 4.0
	tex_pos.y = roundf(tex_pos.y / 4.0) * 4.0
	# Вычесть абс позицию родителя
	if el["parent_id"] != "" and _elements.has(el["parent_id"]):
		tex_pos -= abs_rect(el["parent_id"]).position
	el["rect"].position = tex_pos
	_refresh_props()
	_overlay.queue_redraw()


func do_resize(screen_pos: Vector2) -> void:
	if selected_id == "":
		return
	var el = _elements.get(selected_id)
	if el == null:
		return
	var abs_pos := abs_rect(selected_id).position
	var tex_pos := _screen_to_tex(screen_pos)
	var new_w := maxf(tex_pos.x - abs_pos.x, 16.0)
	var new_h := maxf(tex_pos.y - abs_pos.y, 16.0)
	new_w = roundf(new_w / 4.0) * 4.0
	new_h = roundf(new_h / 4.0) * 4.0
	if el["type"] == EType.SPRITE and el.has("texture"):
		var tex: Texture2D = el["texture"]
		var asp := float(tex.get_height()) / maxf(float(tex.get_width()), 1.0)
		el["rect"].size = Vector2(new_w, new_w * asp)
	else:
		el["rect"].size = Vector2(new_w, new_h)
	_refresh_props()
	_overlay.queue_redraw()


func stop_drag() -> void:
	dragging = false
	resizing = false
	_refresh_props()

func is_over_panel(pos: Vector2) -> bool:
	return active and _panel and _panel.visible and pos.x < PANEL_W + 10


# ═══════════════════════════════════════════════════════════
#  ОТРИСОВКА
# ═══════════════════════════════════════════════════════════

func _draw_all() -> void:
	if not active:
		return
	var ov := _overlay
	var s := _tex_scale()

	# Сетка
	var gc := Color(1, 1, 1, 0.05)
	var glc := Color(1, 1, 1, 0.18)
	for gx in range(0, int(body_w) + 1, GRID_STEP):
		var sx := _body.position.x + gx * s.x
		ov.draw_line(Vector2(sx, _body.position.y), Vector2(sx, _body.position.y + _body.size.y), gc)
		if gx % (GRID_STEP * 4) == 0:
			ov.draw_string(ThemeDB.fallback_font, Vector2(sx + 2, _body.position.y + 11), str(gx), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, glc)
	for gy in range(0, int(body_h) + 1, GRID_STEP):
		var sy := _body.position.y + gy * s.y
		ov.draw_line(Vector2(_body.position.x, sy), Vector2(_body.position.x + _body.size.x, sy), gc)
		if gy % (GRID_STEP * 4) == 0:
			ov.draw_string(ThemeDB.fallback_font, Vector2(_body.position.x + 2, sy + 11), str(gy), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, glc)

	# Контур
	ov.draw_rect(Rect2(_body.position, _body.size), Color(1, 1, 1, 0.25), false, 2.0)

	# Элементы
	var ordered := all_visible_ordered()
	for id in ordered:
		_draw_element(ov, id)


func _draw_element(ov: Control, id: String) -> void:
	var el = _elements[id]
	var r := _tex_to_screen(abs_rect(id))
	var sel := (id == selected_id)
	var s := _tex_scale()

	match el["type"]:
		EType.ZONE:
			var col: Color = el.get("color", Color(0.5, 0.5, 0.5, 0.2))
			ov.draw_rect(r, col, true)
			ov.draw_rect(r, Color.YELLOW if sel else col.lightened(0.3), false, 3.0 if sel else 1.0)

		EType.SPRITE:
			var tex: Texture2D = el.get("texture")
			if tex:
				ov.draw_texture_rect(tex, r, false, Color(1, 1, 1, 1.0 if sel else 0.8))
			ov.draw_rect(r, Color.CYAN if sel else Color(1, 1, 1, 0.25), false, 3.0 if sel else 1.0)

		EType.TEXT:
			var txt: String = el.get("text", "")
			var fs: int = el.get("font_size", 24)
			var fc: Color = el.get("font_color", Color.WHITE)
			var scaled_fs := int(fs * s.y)
			if scaled_fs < 4:
				scaled_fs = 4
			# Фон текста
			ov.draw_rect(r, Color(0, 0, 0, 0.3) if not sel else Color(0, 0, 0, 0.5), true)
			# Текст — baseline = позиция + ascent шрифта
			if _font:
				var ascent := _font.get_ascent(scaled_fs)
				ov.draw_string(_font, Vector2(r.position.x + 2, r.position.y + ascent), txt, HORIZONTAL_ALIGNMENT_LEFT, int(r.size.x), scaled_fs, fc)
			ov.draw_rect(r, Color(1, 0.8, 0) if sel else Color(1, 1, 1, 0.3), false, 2.0 if sel else 1.0)

		EType.GROUP:
			var col: Color = el.get("color", Color(0.5, 0.5, 1, 0.1))
			ov.draw_rect(r, col, true)
			# Пунктирная рамка (рисуем обычную тонкую)
			ov.draw_rect(r, Color(0.6, 0.6, 1, 0.6) if sel else Color(0.6, 0.6, 1, 0.3), false, 2.0 if sel else 1.0)

	# Лейбл
	var lbl_rect: Rect2 = el["rect"]
	var lbl := "%s [%d,%d %dx%d]" % [el["name"], int(lbl_rect.position.x), int(lbl_rect.position.y), int(lbl_rect.size.x), int(lbl_rect.size.y)]
	var lbl_col := Color.WHITE
	if el["type"] == EType.SPRITE:
		lbl_col = Color.CYAN if sel else Color(1, 1, 1, 0.5)
	elif el["type"] == EType.TEXT:
		lbl_col = Color(1, 0.8, 0) if sel else Color(1, 0.9, 0.5, 0.6)
	elif el["type"] == EType.GROUP:
		lbl_col = Color(0.6, 0.6, 1)
	ov.draw_string(ThemeDB.fallback_font, Vector2(r.position.x + 2, r.position.y - 3), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lbl_col)

	# Ручка ресайза
	if sel:
		var hs := 8.0
		var handle := Rect2(r.end.x - hs, r.end.y - hs, hs, hs)
		ov.draw_rect(handle, Color.YELLOW, true)
		ov.draw_rect(handle, Color.WHITE, false, 1.0)


# ═══════════════════════════════════════════════════════════
#  SAVE / LOAD
# ═══════════════════════════════════════════════════════════

func save_layout() -> void:
	var data := {"version": 2, "elements": [], "root_children": _root_children.duplicate()}
	for id in _elements:
		var el = _elements[id]
		var d: Dictionary = {
			"id": el["id"], "type": el["type"], "name": el["name"],
			"x": el["rect"].position.x, "y": el["rect"].position.y,
			"w": el["rect"].size.x, "h": el["rect"].size.y,
			"parent_id": el.get("parent_id", ""),
			"children": el.get("children", []).duplicate(),
			"visible": el["visible"], "z_index": el.get("z_index", 0),
		}
		if el.has("color"):
			d["color"] = el["color"].to_html()
		if el.has("node"):
			d["node"] = el["node"]
		if el.has("path"):
			d["path"] = el["path"]
		if el.has("text"):
			d["text"] = el["text"]
		if el.has("font_size"):
			d["font_size"] = el["font_size"]
		if el.has("font_color"):
			d["font_color"] = el["font_color"].to_html()
		data["elements"].append(d)
	var json_str := JSON.stringify(data, "\t")
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(json_str)
		f.close()
		print("[Designer] ✅ Layout V2 сохранён: %d элементов" % _elements.size())
	else:
		push_error("[Designer] Не удалось сохранить")


func load_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if not f:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return
	f.close()
	var d = json.data
	if not d is Dictionary:
		return
	var version: int = d.get("version", 1)
	if version >= 2:
		_load_v2(d)
	else:
		_load_v1(d)
	print("[Designer] ✅ Layout загружен (V%d)" % version)


func _load_v2(d: Dictionary) -> void:
	# Восстанавливаем элементы по ID
	for saved in d.get("elements", []):
		var id: String = saved.get("id", "")
		if id == "" or not _elements.has(id):
			# Ищем по path (спрайты) или node (зоны) или создаём новые
			var found_id := _find_element_by_save(saved)
			if found_id == "":
				# Пересоздать элементы, которых нет в _elements
				var st: int = saved.get("type", -1)
				if st == EType.TEXT:
					found_id = add_text(saved.get("text", ""), Vector2(saved.get("x", 0), saved.get("y", 0)), saved.get("font_size", 24), Color.html(saved.get("font_color", "#ffffff")))
				elif st == EType.GROUP:
					found_id = add_group(saved.get("name", "Group"), Vector2(saved.get("x", 0), saved.get("y", 0)), Vector2(saved.get("w", 200), saved.get("h", 200)))
				elif st == EType.ZONE:
					found_id = add_zone(saved.get("name", "Zone"), Rect2(saved.get("x", 0), saved.get("y", 0), saved.get("w", 100), saved.get("h", 100)), Color.html(saved.get("color", "ffffff33")), saved.get("node", ""))
				if found_id == "":
					continue
			id = found_id
		var el = _elements[id]
		el["rect"] = Rect2(saved.get("x", 0), saved.get("y", 0), saved.get("w", 100), saved.get("h", 100))
		el["visible"] = saved.get("visible", true)
		el["z_index"] = saved.get("z_index", 0)
		if saved.has("text"):
			el["text"] = saved["text"]
		if saved.has("font_size"):
			el["font_size"] = saved["font_size"]
		if saved.has("font_color"):
			el["font_color"] = Color.html(saved["font_color"])
	# Восстановить дерево parent/children
	_reconstruct_tree(d)


func _load_v1(d: Dictionary) -> void:
	# Старый формат — просто позиции
	if d.has("sprites"):
		for saved in d["sprites"]:
			for id in _elements:
				var el = _elements[id]
				if el.get("path", "") == saved.get("path", ""):
					el["rect"] = Rect2(saved.get("x", 0), saved.get("y", 0), saved.get("w", 100), saved.get("h", 100))
					el["visible"] = saved.get("visible", true)
					break
	if d.has("zones"):
		for saved in d["zones"]:
			for id in _elements:
				var el = _elements[id]
				if el.get("node", "") == saved.get("name", ""):
					el["rect"] = Rect2(saved.get("x", 0), saved.get("y", 0), saved.get("w", 100), saved.get("h", 100))
					break


func _find_element_by_save(saved: Dictionary) -> String:
	if saved.has("path"):
		for id in _elements:
			if _elements[id].get("path", "") == saved["path"]:
				return id
	if saved.has("node"):
		for id in _elements:
			if _elements[id].get("node", "") == saved["node"]:
				return id
	if saved.has("name"):
		for id in _elements:
			if _elements[id].get("name", "") == saved["name"]:
				return id
	return ""


func _reconstruct_tree(d: Dictionary) -> void:
	var saved_elements = d.get("elements", [])
	var saved_root = d.get("root_children", [])
	# Построить карту old_id -> new_id
	var id_map: Dictionary = {}
	for saved in saved_elements:
		var old_id: String = saved.get("id", "")
		var found := _find_element_by_save(saved)
		if found != "":
			id_map[old_id] = found
	# Убрать все из root_children и children
	_root_children.clear()
	for id in _elements:
		_elements[id]["children"] = []
		_elements[id]["parent_id"] = ""
	# Восстановить дерево
	for old_id in saved_root:
		var new_id: String = id_map.get(old_id, "")
		if new_id != "":
			_root_children.append(new_id)
	for saved in saved_elements:
		var old_id: String = saved.get("id", "")
		var new_id: String = id_map.get(old_id, "")
		if new_id == "":
			continue
		var old_children = saved.get("children", [])
		for old_child in old_children:
			var new_child: String = id_map.get(old_child, "")
			if new_child != "":
				_elements[new_id]["children"].append(new_child)
				_elements[new_child]["parent_id"] = new_id
	# Элементы не попавшие ни в какой children — в root
	for id in _elements:
		if not _root_children.has(id):
			var found := false
			for pid in _elements:
				if _elements[pid]["children"].has(id):
					found = true
					break
			if not found:
				_root_children.append(id)


# ═══════════════════════════════════════════════════════════
#  LOG
# ═══════════════════════════════════════════════════════════

func log_all() -> void:
	print("\n═══ DESIGNER TREE (tex %dx%d) ═══" % [int(body_w), int(body_h)])
	_log_branch(_root_children, 0)
	print("═══════════════════════════════════════\n")


func _log_branch(ids: Array, depth: int) -> void:
	var indent := "  ".repeat(depth)
	for id in ids:
		var el = _elements.get(id)
		if el == null:
			continue
		var type_str := ""
		match el["type"]:
			EType.ZONE: type_str = "ZONE"
			EType.SPRITE: type_str = "SPRITE"
			EType.TEXT: type_str = "TEXT"
			EType.GROUP: type_str = "GROUP"
		var r: Rect2 = el["rect"]
		var extra := ""
		if el["type"] == EType.TEXT:
			extra = ' text="%s" fs=%d' % [el.get("text", ""), el.get("font_size", 24)]
		elif el["type"] == EType.SPRITE:
			extra = " path=%s" % el.get("path", "")
		print('%s[%s] %s "%s": Rect2(%d,%d,%d,%d) vis=%s%s' % [
			indent, type_str, id, el["name"],
			int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y),
			str(el["visible"]), extra])
		if el["children"].size() > 0:
			_log_branch(el["children"], depth + 1)


## Применить зоны к нодам сцены (вызывается из main.gd)
func apply_zones_to_nodes() -> void:
	for id in _elements:
		var el = _elements[id]
		if el["type"] != EType.ZONE:
			continue
		var node_name: String = el.get("node", "")
		if node_name == "":
			continue
		var node: Control = _body.get_node_or_null(node_name)
		if node:
			var br := _tex_to_body(abs_rect(id))
			node.position = br.position
			node.size = br.size


# ═══════════════════════════════════════════════════════════
#  МАТЕРИАЛИЗАЦИЯ — создание реальных Godot-нод из элементов
#  В дебаг-режиме — оверлей рисует. Без дебага — настоящие ноды
#  Спрайт → TextureRect (+ gui_input если interactive)
#  Текст → Label (шрифт minecraft)
#  Группа → Control (контейнер)
#  Зона → пропускается (уже есть как ноды сцены)
# ═══════════════════════════════════════════════════════════

func set_click_callback(cb: Callable) -> void:
	_click_callback = cb


func materialize() -> void:
	dematerialize()
	var ordered := all_visible_ordered()
	for id in ordered:
		var el = _elements[id]
		if el["type"] == EType.ZONE:
			continue  # зоны — уже ноды сцены
		var ar := abs_rect(id)
		var br := _tex_to_body(ar)
		var node: Control = null
		match el["type"]:
			EType.SPRITE:
				var tex: Texture2D = el.get("texture")
				if tex:
					var tr := TextureRect.new()
					tr.texture = tex
					tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
					tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
					tr.mouse_filter = Control.MOUSE_FILTER_STOP
					tr.gui_input.connect(_on_materialized_input.bind(id))
					node = tr
			EType.TEXT:
				var lbl := Label.new()
				lbl.text = el.get("text", "")
				if _font:
					lbl.add_theme_font_override("font", _font)
				var fs: int = el.get("font_size", 24)
				var s := _tex_scale()
				lbl.add_theme_font_size_override("font_size", int(fs * s.y))
				var fc: Color = el.get("font_color", Color.WHITE)
				lbl.add_theme_color_override("font_color", fc)
				lbl.mouse_filter = Control.MOUSE_FILTER_STOP
				lbl.gui_input.connect(_on_materialized_input.bind(id))
				node = lbl
			EType.GROUP:
				node = Control.new()
				node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if node:
			node.name = id
			node.position = br.position
			node.size = br.size
			_body.add_child(node)
			_materialized_nodes[id] = node


func dematerialize() -> void:
	for id in _materialized_nodes:
		var node = _materialized_nodes[id]
		if is_instance_valid(node):
			node.queue_free()
	_materialized_nodes.clear()


func update_materialized_positions() -> void:
	for id in _materialized_nodes:
		var node = _materialized_nodes[id]
		if not is_instance_valid(node):
			continue
		var el = _elements.get(id)
		if el == null:
			continue
		var br := _tex_to_body(abs_rect(id))
		node.position = br.position
		node.size = br.size
		# Обновить размер шрифта при зуме
		if el["type"] == EType.TEXT and node is Label:
			var fs: int = el.get("font_size", 24)
			var s := _tex_scale()
			node.add_theme_font_size_override("font_size", int(fs * s.y))


func _on_materialized_input(event: InputEvent, id: String) -> void:
	if active:
		return  # в дебаг-режиме клики обрабатывает оверлей
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _click_callback != null:
			_click_callback.call(id)
