# Ресурс: данные ингредиента пиццы
class_name IngredientData
extends Resource

## Отображаемое название
@export var display_name: String = ""
## Цена добавления ($)
@export var price: float = 0.0
## Калорийность (ккал на порцию)
@export var calories: float = 0.0
## Белки (г на порцию)
@export var protein: float = 0.0
## Жиры (г на порцию)
@export var fat: float = 0.0
## Углеводы (г на порцию)
@export var carbs: float = 0.0
## Категория: "meat" / "cheese" / "vegetable" / "other"
@export var category: String = "other"


## Фабричный метод для удобного создания из кода
func _to_string() -> String:
	return "%s ($%.2f)" % [display_name, price]
