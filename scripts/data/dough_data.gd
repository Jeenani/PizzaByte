# Ресурс: тип теста
class_name DoughData
extends Resource

## Название типа теста
@export var display_name: String = ""
## Надбавка к цене ($)
@export var price_modifier: float = 0.0
## КБЖУ самого теста (базовые, до множителя размера)
@export var calories: float = 0.0
@export var protein: float = 0.0
@export var fat: float = 0.0
@export var carbs: float = 0.0


func _to_string() -> String:
	return "%s (+$%.2f)" % [display_name, price_modifier]
