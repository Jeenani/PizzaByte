# Автозагрузка: все данные игры (ингредиенты, размеры, тесто, пресеты, промокоды)
# Синглтон — доступен из любого скрипта как GameData
extends Node

# --- Каталоги данных ---
var sizes: Array = []        # Array[PizzaSizeData]
var doughs: Array = []       # Array[DoughData]
var ingredients: Array = []  # Array[IngredientData]
var presets: Array = []      # Array[PresetPizzaData]
var promo_codes: Array = []  # Array[PromoCodeData]


func _ready() -> void:
	_init_sizes()
	_init_doughs()
	_init_ingredients()
	_init_presets()
	_init_promo_codes()
	print("[GameData] Загружено: %d размеров, %d тест, %d ингредиентов, %d пресетов, %d промокодов" % [
		sizes.size(), doughs.size(), ingredients.size(), presets.size(), promo_codes.size()
	])


# ========== Размеры пиццы ==========
func _init_sizes() -> void:
	sizes = [
		_size("Маленькая", 22, 0.00, 0.8),
		_size("Средняя", 26, 2.00, 1.0),
		_size("Большая", 34, 4.00, 1.4),
	]


func _size(p_name: String, diam: int, price: float, mult: float) -> PizzaSizeData:
	var d := PizzaSizeData.new()
	d.display_name = p_name
	d.diameter_cm = diam
	d.price_modifier = price
	d.kbju_multiplier = mult
	return d


# ========== Типы теста ==========
func _init_doughs() -> void:
	#                    Название       Цена   Ккал   Б     Ж     У
	doughs = [
		_dough("Классическое", 0.50, 250.0, 8.0, 3.0, 48.0),
		_dough("Тонкое",       0.50, 180.0, 6.0, 2.0, 35.0),
		_dough("Пышное",       1.00, 320.0, 9.0, 5.0, 58.0),
	]


func _dough(p_name: String, price: float, cal: float, prot: float, fat: float, carbs: float) -> DoughData:
	var d := DoughData.new()
	d.display_name = p_name
	d.price_modifier = price
	d.calories = cal
	d.protein = prot
	d.fat = fat
	d.carbs = carbs
	return d


# ========== Ингредиенты ==========
func _init_ingredients() -> void:
	#                     Название         Цена  Ккал   Б     Ж     У     Категория
	ingredients = [
		# Мясо
		_ing("Пепперони",    1.50, 130.0,  6.0, 11.0,  1.0, "meat"),
		_ing("Ветчина",      2.00,  45.0,  5.0,  2.5,  0.5, "meat"),
		_ing("Бекон",        2.00, 110.0,  4.0, 10.0,  0.5, "meat"),
		_ing("Курица",       1.50,  55.0,  9.0,  2.0,  0.0, "meat"),
		_ing("Говядина",     2.50,  80.0,  8.0,  5.0,  0.0, "meat"),
		# Овощи и грибы
		_ing("Шампиньоны",   1.00,  10.0,  1.5,  0.2,  1.0, "vegetable"),
		_ing("Оливки",       1.00,  35.0,  0.3,  3.0,  1.0, "vegetable"),
		_ing("Перец",        1.00,  10.0,  0.4,  0.1,  2.0, "vegetable"),
		_ing("Лук",          0.50,  12.0,  0.3,  0.0,  3.0, "vegetable"),
		_ing("Томаты",       1.00,   8.0,  0.4,  0.1,  1.5, "vegetable"),
		_ing("Ананас",       1.50,  20.0,  0.2,  0.0,  5.0, "vegetable"),
		_ing("Зелень",       0.50,   5.0,  0.5,  0.1,  1.0, "vegetable"),
		# Сыры
		_ing("Сыр",          1.50, 100.0,  7.0,  8.0,  0.5, "cheese"),
		_ing("Моцарелла",    1.50,  85.0,  6.0,  6.0,  1.0, "cheese"),
		_ing("Сыр Чеддер",   1.50, 110.0,  7.0,  9.0,  0.5, "cheese"),
	]


func _ing(p_name: String, price: float, cal: float, prot: float, fat: float, carbs: float, cat: String) -> IngredientData:
	var d := IngredientData.new()
	d.display_name = p_name
	d.price = price
	d.calories = cal
	d.protein = prot
	d.fat = fat
	d.carbs = carbs
	d.category = cat
	return d


# ========== Пресеты готовых пицц ==========
func _init_presets() -> void:
	presets = [
		_preset("Пепперони", ["Пепперони", "Моцарелла", "Сыр"],
			"Классика с пепперони и сыром"),
		_preset("Мясная", ["Пепперони", "Ветчина", "Бекон", "Говядина", "Моцарелла"],
			"Для любителей мяса"),
		_preset("Сырная", ["Моцарелла", "Сыр Чеддер", "Сыр", "Зелень"],
			"Четыре сыра с зеленью"),
		_preset("Бургерная", ["Говядина", "Бекон", "Лук", "Томаты", "Сыр Чеддер"],
			"Вкус бургера в пицце"),
	]


func _preset(p_name: String, ings: Array, desc: String) -> PresetPizzaData:
	var d := PresetPizzaData.new()
	d.display_name = p_name
	d.ingredient_names = PackedStringArray(ings)
	d.description = desc
	return d


# ========== Промокоды ==========
func _init_promo_codes() -> void:
	promo_codes = [
		_promo("PIZZA10", PromoCodeData.DiscountType.PERCENT, 10.0, "Скидка 10%"),
		_promo("PIZZA20", PromoCodeData.DiscountType.PERCENT, 20.0, "Скидка 20%"),
		_promo("WELCOME", PromoCodeData.DiscountType.FIXED,    2.00, "Скидка $2"),
		_promo("STUDENT", PromoCodeData.DiscountType.PERCENT, 15.0, "Студенческая скидка 15%"),
	]


func _promo(p_code: String, p_type: PromoCodeData.DiscountType, val: float, desc: String) -> PromoCodeData:
	var d := PromoCodeData.new()
	d.code = p_code
	d.discount_type = p_type
	d.discount_value = val
	d.description = desc
	return d


# ========== Поиск ==========

## Найти ингредиент по имени
func find_ingredient(ingredient_name: String) -> IngredientData:
	for ing in ingredients:
		if ing.display_name == ingredient_name:
			return ing
	push_warning("GameData: ингредиент '%s' не найден" % ingredient_name)
	return null


## Найти промокод по введённому коду (регистронезависимо)
func find_promo_code(code_text: String) -> PromoCodeData:
	var upper := code_text.to_upper().strip_edges()
	for promo in promo_codes:
		if promo.code.to_upper() == upper:
			return promo
	return null


## Получить ингредиенты по категории
func get_ingredients_by_category(category: String) -> Array:
	var result := []
	for ing in ingredients:
		if ing.category == category:
			result.append(ing)
	return result


## Получить случайный набор ингредиентов (3–6 штук)
func get_random_ingredients() -> Array:
	var count := randi_range(3, 6)
	var shuffled := ingredients.duplicate()
	shuffled.shuffle()
	return shuffled.slice(0, count)
