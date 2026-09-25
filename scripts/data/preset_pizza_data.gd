# Ресурс: пресет (готовый набор) пиццы
class_name PresetPizzaData
extends Resource

## Название пресета (Мясная, Сырная и т.д.)
@export var display_name: String = ""
## Список названий ингредиентов (должны совпадать с display_name в IngredientData)
@export var ingredient_names: PackedStringArray = []
## Краткое описание
@export var description: String = ""


func _to_string() -> String:
	return display_name
