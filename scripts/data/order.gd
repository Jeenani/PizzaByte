# Данные заказа пиццы (объект в памяти, не ресурс на диске)
class_name Order
extends RefCounted

# --- Параметры заказа ---
var pizza_size = null          # PizzaSizeData
var dough = null               # DoughData
var height_tall: bool = false  # Обычная / Высокая
var ingredients: Array = []    # Array[IngredientData]
var promo_code = null          # PromoCodeData
var mode: String = "auto"      # "auto" / "manual"
var payment_method: String = "" # "cash" / "card" / "coins"

# --- Рассчитанные цены ---
var base_price: float = 0.0       # Базовая цена (пицца + соус)
var total_price: float = 0.0      # Итого до скидки
var discount_amount: float = 0.0  # Сумма скидки
var final_price: float = 0.0      # Итого к оплате

# --- КБЖУ ---
var total_calories: float = 0.0
var total_protein: float = 0.0
var total_fat: float = 0.0
var total_carbs: float = 0.0

# --- Приготовление ---
var cooking_time: float = 5.0   # Время готовки (сек)
var order_name: String = ""     # Имя в очереди

# --- Оплата наличными ---
var cash_given: float = 0.0     # Внесённая сумма
var change_amount: float = 0.0  # Сдача


## Строка КБЖУ для отображения
func get_kbju_string() -> String:
	return "%.0f ккал | Б: %.1f г | Ж: %.1f г | У: %.1f г" % [
		total_calories, total_protein, total_fat, total_carbs
	]


## Список названий ингредиентов
func get_ingredient_names() -> PackedStringArray:
	var names := PackedStringArray()
	for ing in ingredients:
		names.append(ing.display_name)
	return names


func _to_string() -> String:
	if order_name != "":
		return order_name
	var names := get_ingredient_names()
	if names.size() > 0:
		return ", ".join(names)
	return "Пустая пицца"
