class_name ScreenPanel
extends Node2D
## Панель экрана вендингового автомата.
## Координаты — в пикселях панели (PW × PH). Масштабируется через scale.
## Все элементы кликабельные через ClickableSprite + SelectorGroup.

signal next_pressed
signal mode_changed(mode: String)
signal preset_changed(index: int)
signal size_changed(index: int)
signal dough_changed(index: int)
signal height_changed(tall: bool)

const PW := 432.0
const PH := 924.0
const PAD := 16.0
const CW := 400.0
const PIZZA_CENTER := Vector2(216.0, 180.0)
const FONT_PATH := "res://assets/textures/font/minecraft-rus-regular1.ttf"

const TX := {
	"m_sel": "res://assets/textures/ui/manual_mode_selected.png",
	"m_un": "res://assets/textures/ui/manual_mode_unselected.png",
	"a_sel": "res://assets/textures/ui/auto_mode_selected.png",
	"a_un": "res://assets/textures/ui/auto_mode_unselected.png",
	"t_sel": "res://assets/textures/ui/tall_square_selected.png",
	"t_un": "res://assets/textures/ui/tall_square_unselected.png",
	"v_sel": "res://assets/textures/ui/versatile_square_selected.png",
	"v_un": "res://assets/textures/ui/versatile_square_unselected.png",
	"frame": "res://assets/textures/ui/pizza_selection.png",
	"al": "res://assets/textures/presets/arrow_left.png",
	"ar": "res://assets/textures/presets/arrow_right.png",
	"b_sel": "res://assets/textures/ui/button_selected.png",
	"b_un": "res://assets/textures/ui/button_unselected.png",
	"pp": "res://assets/textures/pizza/pepperoni_choice_panel.png",
	"pc": "res://assets/textures/pizza/carbonara_choice_panel.png",
	"pk": "res://assets/textures/pizza/chickenbombony_choice_panel.png",
	"pm": "res://assets/textures/pizza/margatita_choice_panel.png",
	"s0": "res://assets/textures/presets/pizza_small.png",
	"s1": "res://assets/textures/presets/pizza_medium.png",
	"s2": "res://assets/textures/presets/pizza_big.png",
	"d0": "res://assets/textures/presets/testo_classic.png",
	"d1": "res://assets/textures/presets/testo_tonkoe.png",
	"d2": "res://assets/textures/presets/testo_vozdushnoe.png",
}

var _t: Dictionary = {}
var _font: Font
var _mode := "manual"
var _pi := 0

func get_selected_pizza_index() -> int:
	return _pi

var sec_mode: Node2D
var sec_pizza: Node2D
var sec_size: Node2D
var sec_dough: Node2D
var sec_height: Node2D
var sec_next: Node2D

var _mg: SelectorGroup
var _al: ClickableSprite
var _ar_btn: ClickableSprite
var _al_base_pos := Vector2.ZERO
var _ar_base_pos := Vector2.ZERO
var _pspr: Sprite2D
var _pizza_base_scale := Vector2.ONE
var _pizza_tween: Tween
var _is_switching_pizza := false
var _anim_time: float = 0.0

var _pname: Label
var _pprice: Label
var _sg: SelectorGroup
var _dg: SelectorGroup
var _hg: SelectorGroup
var _bn: ClickableSprite
var _nl: Label
var _tl: Label
var _lbl_manual: Label
var _lbl_auto: Label

var _pdata: Array = []
var _slbl: Array = []
var _dlbl: Array = []

var _size_icons: Array[Sprite2D] = []
var _dough_icons: Array[Sprite2D] = []
var _height_icons: Array[Sprite2D] = []


func _ready() -> void:
	_load()
	_build()


func _load() -> void:
	for k in TX:
		var p: String = TX[k]
		if ResourceLoader.exists(p):
			_t[k] = load(p) as Texture2D
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	if not _font:
		_font = ThemeDB.fallback_font
	_pdata = [
		{"tk": "pp", "n": "Пепперони", "p": 12.90},
		{"tk": "pm", "n": "Маргарита", "p": 10.50},
		{"tk": "pc", "n": "Карбонара", "p": 14.00},
		{"tk": "pk", "n": "Чикен Бомбони", "p": 13.50},
	]
	_slbl = ["Маленькая\n(12 см)\n+0$", "Средняя\n(26 см)\n+2$", "Большая\n(34 см)\n+4$"]
	_dlbl = ["Классич.\n+0.50$", "Тонкое\n+0.50$", "Пышное\n+1.00$"]


func _build() -> void:
	_tl = _lbl("НАЧАТЬ ЗАКАЗ", 22, Color.WHITE, Vector2(PAD, 8), Vector2(CW, 36))
	_tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_tl)
	_build_mode()
	_build_pizza()
	_build_size()
	_build_dough()
	_build_height()
	_build_next()


func _build_mode() -> void:
	sec_mode = Node2D.new(); sec_mode.name = "SecMode"; add_child(sec_mode)
	var mw := (CW - 8) / 2.0
	_mg = SelectorGroup.new(); _mg.name = "ModeGrp"; sec_mode.add_child(_mg)
	var bm := ClickableSprite.make(_t.get("m_un"), _t.get("m_sel"), Vector2(mw, 55), Vector2(PAD, 8))
	_mg.add_opt(bm)
	_lbl_manual = _lbl("Ручной", 13, Color.WHITE, Vector2(46, 0), Vector2(mw - 50, 55))
	_lbl_manual.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_manual.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_manual.z_index = 1
	bm.add_child(_lbl_manual)

	var ba := ClickableSprite.make(_t.get("a_un"), _t.get("a_sel"), Vector2(mw, 55), Vector2(PAD + mw + 8, 8))
	_mg.add_opt(ba)
	_lbl_auto = _lbl("Автоматический", 12, Color.WHITE, Vector2(46, 0), Vector2(mw - 50, 55))
	_lbl_auto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_auto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_auto.z_index = 1
	ba.add_child(_lbl_auto)

	_mg.select_quiet(0)
	_update_mode_labels(0)
	_mg.option_selected.connect(_on_mode_sel)


func _build_pizza() -> void:
	sec_pizza = Node2D.new()
	sec_pizza.name = "SecPizza"
	add_child(sec_pizza)
	sec_pizza.add_child(_lbl("Выбери пиццу", 16, Color(0.7, 0.8, 0.9), Vector2(PAD, 72), Vector2(CW, 22)))

	var fr := Sprite2D.new()
	fr.name = "Frame"
	fr.centered = false
	if _t.has("frame"):
		fr.texture = _t["frame"]
		fr.scale = Vector2(CW, 195) / fr.texture.get_size()
	fr.position = Vector2(PAD, 96)
	sec_pizza.add_child(fr)

	# Стрелки влево и вправо
	_al_base_pos = Vector2(PAD + 6, 168)
	_al = ClickableSprite.make(_t.get("al"), null, Vector2(32, 32), _al_base_pos)
	sec_pizza.add_child(_al)
	_al.clicked.connect(func(): _chg_preset(-1))

	_ar_base_pos = Vector2(PAD + CW - 38, 168)
	_ar_btn = ClickableSprite.make(_t.get("ar"), null, Vector2(32, 32), _ar_base_pos)
	sec_pizza.add_child(_ar_btn)
	_ar_btn.clicked.connect(func(): _chg_preset(1))

	# Превью пиццы (центрированный для вращения и дыхания)
	_pspr = Sprite2D.new()
	_pspr.centered = true
	_pspr.z_index = 1
	_pspr.position = PIZZA_CENTER
	var p = _pdata[_pi]
	if _t.has(p["tk"]):
		_pspr.texture = _t[p["tk"]]
		_pizza_base_scale = Vector2(140, 140) / _pspr.texture.get_size()
		_pspr.scale = _pizza_base_scale
	sec_pizza.add_child(_pspr)

	_pname = _lbl("Пепперони", 16, Color.WHITE, Vector2(PAD, 252), Vector2(CW, 22))
	_pname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec_pizza.add_child(_pname)

	_pprice = _lbl("12.90$", 16, Color(1.0, 0.85, 0.2), Vector2(PAD, 274), Vector2(CW, 22))
	_pprice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sec_pizza.add_child(_pprice)


func _build_size() -> void:
	sec_size = Node2D.new()
	sec_size.name = "SecSize"
	add_child(sec_size)
	sec_size.add_child(_lbl("Размер", 16, Color(0.7, 0.8, 0.9), Vector2(PAD, 305), Vector2(CW, 22)))
	_sg = SelectorGroup.new()
	_sg.name = "SizeGrp"
	sec_size.add_child(_sg)

	var bw := (CW - 16) / 3.0
	_size_icons.clear()
	for i in 3:
		var bx := PAD + i * (bw + 8)
		var btn := ClickableSprite.make(_t.get("v_un"), _t.get("v_sel"), Vector2(bw, 145), Vector2(bx, 330))
		_sg.add_opt(btn)
		var ik := "s%d" % i
		if _t.has(ik):
			var ic := Sprite2D.new()
			ic.texture = _t[ik]
			ic.centered = true
			ic.position = Vector2(bw * 0.5, 42)
			var base_sc := Vector2(68, 68) / ic.texture.get_size()
			ic.scale = base_sc
			ic.set_meta("base_s", base_sc)
			ic.z_index = 1
			btn.add_child(ic)
			_size_icons.append(ic)
		var lb := _lbl(_slbl[i], 10, Color.WHITE, Vector2(0, 80), Vector2(bw, 65))
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.z_index = 1
		btn.add_child(lb)

	_sg.select_quiet(1)
	_sg.option_selected.connect(func(i):
		size_changed.emit(i)
		if i < _size_icons.size():
			_pop_icon(_size_icons[i])
	)


func _build_dough() -> void:
	sec_dough = Node2D.new(); sec_dough.name = "SecDough"; add_child(sec_dough)
	sec_dough.add_child(_lbl("Тесто", 16, Color(0.7, 0.8, 0.9), Vector2(PAD, 482), Vector2(CW, 22)))
	_dg = SelectorGroup.new(); _dg.name = "DoughGrp"; sec_dough.add_child(_dg)
	var bw := (CW - 16) / 3.0
	_dough_icons.clear()
	for i in 3:
		var bx := PAD + i * (bw + 8)
		var btn := ClickableSprite.make(_t.get("t_un"), _t.get("t_sel"), Vector2(bw, 120), Vector2(bx, 508))
		_dg.add_opt(btn)
		var ik := "d%d" % i
		if _t.has(ik):
			var ic := Sprite2D.new(); ic.texture = _t[ik]; ic.centered = true
			ic.position = Vector2(bw * 0.5, 34)
			var base_sc := Vector2(56, 56) / ic.texture.get_size()
			ic.scale = base_sc
			ic.set_meta("base_s", base_sc)
			ic.z_index = 1; btn.add_child(ic)
			_dough_icons.append(ic)
		var lb := _lbl(_dlbl[i], 10, Color.WHITE, Vector2(0, 66), Vector2(bw, 50))
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lb.z_index = 1; btn.add_child(lb)
	_dg.select_quiet(0)
	_dg.option_selected.connect(func(i):
		dough_changed.emit(i)
		if i < _dough_icons.size():
			_pop_icon(_dough_icons[i])
	)


func _build_height() -> void:
	sec_height = Node2D.new(); sec_height.name = "SecHeight"; add_child(sec_height)
	sec_height.add_child(_lbl("Высота", 16, Color(0.7, 0.8, 0.9), Vector2(PAD, 636), Vector2(CW, 22)))
	_hg = SelectorGroup.new(); _hg.name = "HeightGrp"; sec_height.add_child(_hg)
	var hw := (CW - 8) / 2.0
	_height_icons.clear()
	var h0 := ClickableSprite.make(_t.get("v_un"), _t.get("v_sel"), Vector2(hw, 120), Vector2(PAD, 662))
	_hg.add_opt(h0)
	if _t.has("d0"):
		var ic0 := Sprite2D.new(); ic0.texture = _t["d0"]; ic0.centered = true
		ic0.position = Vector2(hw * 0.5, 34)
		var base_sc := Vector2(56, 56) / ic0.texture.get_size()
		ic0.scale = base_sc
		ic0.set_meta("base_s", base_sc)
		ic0.z_index = 1; h0.add_child(ic0)
		_height_icons.append(ic0)
	var lh0 := _lbl("Обычная", 12, Color.WHITE, Vector2(0, 68), Vector2(hw, 48))
	lh0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lh0.z_index = 1; h0.add_child(lh0)
	var h1 := ClickableSprite.make(_t.get("v_un"), _t.get("v_sel"), Vector2(hw, 120), Vector2(PAD + hw + 8, 662))
	_hg.add_opt(h1)
	if _t.has("d2"):
		var ic1 := Sprite2D.new(); ic1.texture = _t["d2"]; ic1.centered = true
		ic1.position = Vector2(hw * 0.5, 34)
		var base_sc := Vector2(56, 56) / ic1.texture.get_size()
		ic1.scale = base_sc
		ic1.set_meta("base_s", base_sc)
		ic1.z_index = 1; h1.add_child(ic1)
		_height_icons.append(ic1)
	var lh1 := _lbl("Высокая\n+0.50$", 12, Color.WHITE, Vector2(0, 68), Vector2(hw, 48))
	lh1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lh1.z_index = 1; h1.add_child(lh1)
	_hg.select_quiet(0)
	_hg.option_selected.connect(func(i):
		height_changed.emit(i == 1)
		if i < _height_icons.size():
			_pop_icon(_height_icons[i])
	)


func _build_next() -> void:
	sec_next = Node2D.new(); sec_next.name = "SecNext"; add_child(sec_next)
	_bn = ClickableSprite.make(_t.get("b_sel"), null, Vector2(CW, 58), Vector2(PAD, 800))
	sec_next.add_child(_bn); _bn.clicked.connect(func(): next_pressed.emit())
	_nl = _lbl("ДАЛЕЕ →", 22, Color(0.12, 0.08, 0.02), Vector2(PAD, 800), Vector2(CW, 58))
	_nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_nl.z_index = 1; _nl.mouse_filter = Control.MOUSE_FILTER_PASS; sec_next.add_child(_nl)


func _lbl(text: String, fs: int, c: Color, pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new(); l.text = text
	if _font: l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.position = pos; l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	_anim_time += delta

	# 1. Живое медитативное покачивание и дыхание пиццы в покое
	if not _is_switching_pizza and _pspr and sec_pizza and sec_pizza.visible:
		_pspr.rotation = sin(_anim_time * 1.8) * 0.035
		var pulse := 1.0 + sin(_anim_time * 2.5) * 0.02
		_pspr.scale = _pizza_base_scale * pulse

	# 2. Подсказывающее легкое покачивание стрелок карусели
	if _al and _ar_btn and sec_pizza and sec_pizza.visible:
		var wave := sin(_anim_time * 3.5) * 2.5
		_al.position.x = _al_base_pos.x + wave
		_al.base_position.x = _al.position.x
		_ar_btn.position.x = _ar_base_pos.x - wave
		_ar_btn.base_position.x = _ar_btn.position.x

	# 3. Пульсация свечения для кнопки НАЧАТЬ / ДАЛЕЕ
	if _bn and sec_next and sec_next.visible:
		var glow := 1.0 + sin(_anim_time * 4.0) * 0.08
		_bn.modulate = Color(glow, glow * 0.95, 1.0)


func _on_mode_sel(i: int) -> void:
	_mode = "manual" if i == 0 else "auto"
	_update_mode_labels(i)
	_animate_label_pop(_lbl_manual, "Ручной")
	_animate_label_pop(_lbl_auto, "Автоматический")
	mode_changed.emit(_mode)


func _update_mode_labels(sel_idx: int) -> void:
	if _lbl_manual:
		_lbl_manual.add_theme_color_override("font_color", Color.WHITE if sel_idx == 0 else Color(0.65, 0.72, 0.8))
	if _lbl_auto:
		_lbl_auto.add_theme_color_override("font_color", Color.WHITE if sel_idx == 1 else Color(0.65, 0.72, 0.8))


## Импульс отскока для стрелочек
func _anim_arrow(btn: ClickableSprite, dir_x: float) -> void:
	var tw := create_tween()
	var orig_p := btn.base_position
	tw.tween_property(btn, "position", orig_p + Vector2(dir_x * 8.0, 0.0), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "scale", Vector2(0.85, 0.85), 0.06)
	tw.chain().tween_property(btn, "position", orig_p, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(btn, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Тактильный отскок иконки внутри кнопки параметра
func _pop_icon(ic: Sprite2D) -> void:
	if not ic:
		return
	var base_s: Vector2 = ic.get_meta("base_s", ic.scale)
	var tw := create_tween()
	tw.tween_property(ic, "scale", base_s * 1.25, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ic, "scale", base_s, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Анимация pop для текстовых меток
func _animate_label_pop(lbl: Label, new_text: String) -> void:
	if not lbl:
		return
	lbl.pivot_offset = lbl.size * 0.5
	var tw := create_tween()
	tw.tween_property(lbl, "scale", Vector2(0.85, 0.85), 0.05)
	tw.parallel().tween_property(lbl, "modulate:a", 0.4, 0.05)
	tw.tween_callback(func(): lbl.text = new_text)
	tw.tween_property(lbl, "scale", Vector2(1.12, 1.12), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.09)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Анимация смены пиццы (вылет в сторону, прилет новой с пружинящим овершутом)
func _chg_preset(d: int) -> void:
	_pi = wrapi(_pi + d, 0, _pdata.size())
	var p = _pdata[_pi]

	# Анимация нажатой стрелки
	if d < 0:
		_anim_arrow(_al, -1.0)
	else:
		_anim_arrow(_ar_btn, 1.0)

	# Анимация смены пиццы
	_animate_pizza_switch(d, p)

	# Анимация названий и цен
	_animate_label_pop(_pname, p["n"])
	_animate_label_pop(_pprice, "%.2f$" % p["p"])

	preset_changed.emit(_pi)


func _animate_pizza_switch(dir: int, p: Dictionary) -> void:
	if _pizza_tween and _pizza_tween.is_valid():
		_pizza_tween.kill()
	_is_switching_pizza = true
	_pizza_tween = create_tween()

	var center_pos := PIZZA_CENTER
	var exit_offset := -50.0 * float(dir)
	var enter_offset := 50.0 * float(dir)

	# 1) Вылет текущей пиццы
	_pizza_tween.tween_property(_pspr, "position:x", center_pos.x + exit_offset, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_pizza_tween.parallel().tween_property(_pspr, "modulate:a", 0.0, 0.09)
	_pizza_tween.parallel().tween_property(_pspr, "scale", _pizza_base_scale * 0.7, 0.09)
	_pizza_tween.parallel().tween_property(_pspr, "rotation", -0.18 * float(dir), 0.09)

	# 2) Переключение текстуры
	_pizza_tween.tween_callback(func():
		if _t.has(p["tk"]):
			_pspr.texture = _t[p["tk"]]
			_pizza_base_scale = Vector2(140.0, 140.0) / _pspr.texture.get_size()
		_pspr.position = Vector2(center_pos.x + enter_offset, center_pos.y)
		_pspr.scale = _pizza_base_scale * 0.7
		_pspr.rotation = 0.18 * float(dir)
		_pspr.modulate.a = 0.0
	)

	# 3) Влет новой пиццы с овершутом
	_pizza_tween.tween_property(_pspr, "position:x", center_pos.x, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pizza_tween.parallel().tween_property(_pspr, "modulate:a", 1.0, 0.15)
	_pizza_tween.parallel().tween_property(_pspr, "scale", _pizza_base_scale, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pizza_tween.parallel().tween_property(_pspr, "rotation", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_pizza_tween.tween_callback(func():
		_is_switching_pizza = false
		_pspr.position = center_pos
	)

func set_title(t: String) -> void: _tl.text = t
func set_next_text(t: String) -> void: _nl.text = t


## Плавное появление секций (Tween fade-in)
func _anim_show(nodes: Array, delay_step := 0.06) -> void:
	for i in nodes.size():
		var n: CanvasItem = nodes[i]
		n.visible = true
		n.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(n, "modulate:a", 1.0, 0.2).set_delay(i * delay_step).set_ease(Tween.EASE_OUT)


func show_state(st: int) -> void:
	# Скрыть всё
	_tl.visible = false; _tl.modulate.a = 1.0
	sec_mode.visible = false; sec_pizza.visible = false
	sec_size.visible = false; sec_dough.visible = false
	sec_height.visible = false; sec_next.visible = false
	match st:
		0:  # IDLE
			_tl.visible = true
			set_title("НАЧАТЬ ЗАКАЗ")
			sec_next.visible = true; set_next_text("НАЧАТЬ →")
		2:  # SELECT_PARAMETERS — полная панель
			_anim_show([sec_mode, sec_pizza, sec_size, sec_dough, sec_height])
			sec_next.visible = true; set_next_text("ДАЛЕЕ →")
		5:  # PAYMENT (оплата — пока заглушка для будущих кнопок)
			_tl.visible = true
			set_title("ОПЛАТА")
			sec_next.visible = true; set_next_text("ОПЛАТИТЬ")
		6:  # QUEUE
			_tl.visible = true
			set_title("В ОЧЕРЕДИ"); sec_next.visible = false
		7:  # COOKING
			_tl.visible = true
			set_title("ГОТОВИМ...")
			sec_next.visible = true
			set_next_text("СКИП >>")
		8:  # DISPENSING
			_tl.visible = true
			set_title("ВЫДАЧА...")
			sec_next.visible = false
		9:  # FINISH
			_tl.visible = true
			set_title("ГОТОВО! ЗАБЕРИТЕ")
			sec_next.visible = true
			set_next_text("НОВЫЙ ЗАКАЗ →")
