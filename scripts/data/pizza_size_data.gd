# Ресурс: размер пиццы
class_name PizzaSizeData
extends Resource

## Название размера
@export var display_name: String = ""
## Диаметр в сантиметрах
@export var diameter_cm: int = 22
## Надбавка к цене ($)
@export var price_modifier: float = 0.0
## Множитель КБЖУ (больше пицца → больше калорий)
@export var kbju_multiplier: float = 1.0


func _to_string() -> String:
	return "%s (%d см)" % [display_name, diameter_cm]
