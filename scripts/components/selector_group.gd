class_name SelectorGroup
extends Node2D
## Группа ClickableSprite с поведением "выбери один из N".
## При клике по элементу — он подсвечивается, остальные сбрасываются.

signal option_selected(index: int)

var opts: Array = []  # Array[ClickableSprite]
var sel_idx := 0


func add_opt(cs: ClickableSprite) -> void:
	var i := opts.size()
	opts.append(cs)
	add_child(cs)
	cs.clicked.connect(_on_click.bind(i))


func _ready() -> void:
	_apply()


func select(i: int) -> void:
	sel_idx = clampi(i, 0, maxi(opts.size() - 1, 0))
	_apply()
	if sel_idx < opts.size() and opts[sel_idx] is ClickableSprite:
		opts[sel_idx].play_click_anim()
	option_selected.emit(sel_idx)


func select_quiet(i: int) -> void:
	sel_idx = clampi(i, 0, maxi(opts.size() - 1, 0))
	_apply()


func get_selected_index() -> int:
	return sel_idx


func _on_click(i: int) -> void:
	select(i)


func _apply() -> void:
	for i in range(opts.size()):
		opts[i].set_selected(i == sel_idx)
