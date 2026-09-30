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

var sec_mode: Node2D
var sec_pizza: Node2D
var sec_size: Node2D
var sec_dough: Node2D
var sec_height: Node2D
var sec_next: Node2D

var _mg: SelectorGroup
var _al: ClickableSprite
var _ar_btn: ClickableSprite
var _pspr: Sprite2D
var _pname: Label
var _pprice: Label
var _sg: SelectorGroup
var _dg: SelectorGroup
var _hg: SelectorGroup
var _bn: ClickableSprite
var _nl: Label
var _tl: Label

var _pdata: Array = []
var _slbl: Array = []
var _dlbl: Array = []


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
		{"tk": "pk", "n": "Бургерная", "p": 13.50},
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
	var ba := ClickableSprite.make(_t.get("a_un"), _t.get("a_sel"), Vector2(mw, 55), Vector2(PAD + mw + 8, 8))
	_mg.add_opt(ba)
	_mg.select_quiet(0)
	_mg.option_selected.connect(_on_mode_sel)


func _build_pizza() -> void:
	sec_pizza = Node2D.new(); sec_pizza.name = "SecPizza"; add_child(sec_pizza)
	sec_pizza.add_child(_lbl("Выбери пиццу", 16, Color(0.7, 0.8, 0.9), Vector2(PAD, 72), Vector2(CW, 22)))
	var fr := Sprite2D.new(); fr.name = "Frame"; fr.centered = false
	if _t.has("frame"):
		fr.texture = _t["frame"]; fr.scale = Vector2(CW, 195) / fr.texture.get_size()
	fr.position = Vector2(PAD, 96)
	sec_pizza.add_child(fr)
	_al = ClickableSprite.make(_t.get("al"), null, Vector2(32, 32), Vector2(PAD + 4, 170))
	sec_pizza.add_child(_al); _al.clicked.connect(func(): _chg_preset(-1))
	_ar_btn = ClickableSprite.make(_t.get("ar"), null, Vector2(32, 32), Vector2(PAD + CW - 36, 170))
	sec_pizza.add_child(_ar_btn); _ar_btn.clicked.connect(func(): _chg_preset(1))
	_pspr = Sprite2D.new(); _pspr.centered = false; _pspr.z_index = 1
	_pspr.position = Vector2((PW - 140) / 2.0, 108)
	if _t.has("pp"):
		_pspr.texture = _t["pp"]; _pspr.scale = Vector2(140, 140) / _pspr.texture.get_size()
	sec_pizza.add_child(_pspr)
	_pname = _lbl("Пепперони", 16, Color.WHITE, Vector2(PAD, 255), Vector2(CW, 22))
	_pname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sec_pizza.add_child(_pname)
	_pprice = _lbl("12.90$", 16, Color(1.0, 0.85, 0.2), Vector2(PAD, 278), Vector2(CW, 22))
	_pprice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; sec_pizza.add_child(_pprice)


func _build_size() -> void:
	sec_size = Node2D.new(); sec_size.name = "SecSize"; add_child(sec_size)
	sec_size.add_child(_lbl("Размер", 16, Color(0.7, 0.8, 0.9), Vector2(PAD, 305), Vector2(CW, 22)))
	_sg = SelectorGroup.new(); _sg.name = "SizeGrp"; sec_size.add_child(_sg)
	var bw := (CW - 16) / 3.0
	for i in 3:
		var bx := PAD + i * (bw + 8)
		var btn := ClickableSprite.make(_t.get("v_un"), _t.get("v_sel"), Vector2(bw, 145), Vector2(bx, 330))
		_sg.add_opt(btn)
		var ik := "s%d" % i
		if _t.has(ik):
			var ic := Sprite2D.new(); ic.texture = _t[ik]; ic.centered = false
			ic.position = Vector2((bw - 68) / 2.0, 8)
			ic.scale = Vector2(68, 68) / ic.texture.get_size()
			ic.z_index = 1; btn.add_child(ic)
		var lb := _lbl(_slbl[i], 10, Color.WHITE, Vector2(0, 80), Vector2(bw, 65))
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lb.z_index = 1; btn.add_child(lb)
	_sg.select_quiet(1)
	_sg.option_selected.connect(func(i): size_changed.emit(i))


func _build_dough() -> void:
	sec_dough = Node2D.new(); sec_dough.name = "SecDough"; add_child(sec_dough)
	sec_dough.add_child(_lbl("Тесто", 16, Color(0.7, 0.8, 0.9), Vector2(PAD, 482), Vector2(CW, 22)))
	_dg = SelectorGroup.new(); _dg.name = "DoughGrp"; sec_dough.add_child(_dg)
	var bw := (CW - 16) / 3.0
	for i in 3:
		var bx := PAD + i * (bw + 8)
		var btn := ClickableSprite.make(_t.get("t_un"), _t.get("t_sel"), Vector2(bw, 120), Vector2(bx, 508))
		_dg.add_opt(btn)
		var ik := "d%d" % i
		if _t.has(ik):
			var ic := Sprite2D.new(); ic.texture = _t[ik]; ic.centered = false
			ic.position = Vector2((bw - 56) / 2.0, 6)
			ic.scale = Vector2(56, 56) / ic.texture.get_size()
			ic.z_index = 1; btn.add_child(ic)
		var lb := _lbl(_dlbl[i], 10, Color.WHITE, Vector2(0, 66), Vector2(bw, 50))
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lb.z_index = 1; btn.add_child(lb)
	_dg.select_quiet(0)
	_dg.option_selected.connect(func(i): dough_changed.emit(i))


func _build_height() -> void:
	sec_height = Node2D.new(); sec_height.name = "SecHeight"; add_child(sec_height)
	sec_height.add_child(_lbl("Высота", 16, Color(0.7, 0.8, 0.9), Vector2(PAD, 636), Vector2(CW, 22)))
	_hg = SelectorGroup.new(); _hg.name = "HeightGrp"; sec_height.add_child(_hg)
	var hw := (CW - 8) / 2.0
	var h0 := ClickableSprite.make(_t.get("v_un"), _t.get("v_sel"), Vector2(hw, 120), Vector2(PAD, 662))
	_hg.add_opt(h0)
	if _t.has("d0"):
		var ic0 := Sprite2D.new(); ic0.texture = _t["d0"]; ic0.centered = false
		ic0.position = Vector2((hw - 56) / 2.0, 6)
		ic0.scale = Vector2(56, 56) / ic0.texture.get_size()
		ic0.z_index = 1; h0.add_child(ic0)
	var lh0 := _lbl("Обычная", 12, Color.WHITE, Vector2(0, 68), Vector2(hw, 48))
	lh0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lh0.z_index = 1; h0.add_child(lh0)
	var h1 := ClickableSprite.make(_t.get("v_un"), _t.get("v_sel"), Vector2(hw, 120), Vector2(PAD + hw + 8, 662))
	_hg.add_opt(h1)
	if _t.has("d2"):
		var ic1 := Sprite2D.new(); ic1.texture = _t["d2"]; ic1.centered = false
		ic1.position = Vector2((hw - 56) / 2.0, 6)
		ic1.scale = Vector2(56, 56) / ic1.texture.get_size()
		ic1.z_index = 1; h1.add_child(ic1)
	var lh1 := _lbl("Высокая\n+0.50$", 12, Color.WHITE, Vector2(0, 68), Vector2(hw, 48))
	lh1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lh1.z_index = 1; h1.add_child(lh1)
	_hg.select_quiet(0)
	_hg.option_selected.connect(func(i): height_changed.emit(i == 1))


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


func _on_mode_sel(i: int) -> void:
	_mode = "manual" if i == 0 else "auto"
	mode_changed.emit(_mode)

func _chg_preset(d: int) -> void:
	_pi = wrapi(_pi + d, 0, _pdata.size())
	var p = _pdata[_pi]
	if _t.has(p["tk"]):
		_pspr.texture = _t[p["tk"]]
		_pspr.scale = Vector2(140, 140) / _pspr.texture.get_size()
	_pname.text = p["n"]; _pprice.text = "%.2f$" % p["p"]
	preset_changed.emit(_pi)

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
			set_title("ГОТОВИМ..."); sec_next.visible = false
		8:  # DISPENSING
			_tl.visible = true
			set_title("ВЫДАЧА"); sec_next.visible = false
		9:  # FINISH
			_tl.visible = true
			set_title("ГОТОВО!")
			sec_next.visible = true; set_next_text("НОВЫЙ ЗАКАЗ")
