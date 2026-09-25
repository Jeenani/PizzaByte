# Менеджер текущего заказа
# Управляет составом пиццы, пересчитывает цену и КБЖУ
extends Node

## Базовая цена пиццы с соусом ($)
const BASE_PRICE: float = 5.00
## Надбавка за высокую пиццу ($)
const HEIGHT_TALL_PRICE: float = 0.50

# --- Ссылка на GameData (через preload, автозагрузка) ---
var _game_data: Node = null

# --- Сигналы ---
signal order_updated()
signal price_changed(final_price: float)
signal kbju_changed(cal: float, prot: float, fat: float, carbs: float)
signal ingredient_added(ingredient: IngredientData)
signal ingredient_removed(index: int)

## Текущий заказ
var current_order: Order = null


func _ready() -> void:
	_game_data = get_node_or_null("/root/GameData")


## Создать новый пустой заказ с параметрами по умолчанию
func create_new_order() -> Order:
	current_order = Order.new()
	current_order.base_price = BASE_PRICE
	# Размер и тесто по умолчанию — первые из каталога
	if _game_data and _game_data.sizes.size() > 0:
		current_order.pizza_size = _game_data.sizes[0]
	if _game_data and _game_data.doughs.size() > 0:
		current_order.dough = _game_data.doughs[0]
	_recalculate()
	return current_order


## Установить режим (auto / manual)
func set_mode(mode: String) -> void:
	if current_order:
		current_order.mode = mode
		order_updated.emit()


## Установить размер пиццы
func set_size(size: PizzaSizeData) -> void:
	if current_order:
		current_order.pizza_size = size
		_recalculate()


## Установить тип теста
func set_dough(dough: DoughData) -> void:
	if current_order:
		current_order.dough = dough
		_recalculate()


## Установить высоту: true = высокая, false = обычная
func set_height_tall(tall: bool) -> void:
	if current_order:
		current_order.height_tall = tall
		_recalculate()


## Добавить ингредиент
func add_ingredient(ingredient: IngredientData) -> void:
	if current_order:
		current_order.ingredients.append(ingredient)
		ingredient_added.emit(ingredient)
		_recalculate()


## Убрать ингредиент по индексу
func remove_ingredient(index: int) -> void:
	if current_order and index >= 0 and index < current_order.ingredients.size():
		current_order.ingredients.remove_at(index)
		ingredient_removed.emit(index)
		_recalculate()


## Убрать ингредиент по объекту (первый найденный)
func remove_ingredient_by_data(ingredient: IngredientData) -> void:
	if not current_order:
		return
	for i in range(current_order.ingredients.size()):
		if current_order.ingredients[i] == ingredient:
			remove_ingredient(i)
			return


## Очистить все ингредиенты
func clear_ingredients() -> void:
	if current_order:
		current_order.ingredients.clear()
		_recalculate()


## Применить пресет (заменяет все ингредиенты)
func apply_preset(preset: PresetPizzaData) -> void:
	if not current_order or not _game_data:
		return
	current_order.ingredients.clear()
	for ing_name in preset.ingredient_names:
		var ingredient = _game_data.find_ingredient(ing_name)
		if ingredient:
			current_order.ingredients.append(ingredient)
	current_order.order_name = preset.display_name
	_recalculate()


## Применить промокод — возвращает true если валиден
func apply_promo_code(code_text: String) -> bool:
	if not current_order or not _game_data:
		return false
	var promo = _game_data.find_promo_code(code_text)
	if promo:
		current_order.promo_code = promo
		_recalculate()
		return true
	return false


## Убрать промокод
func clear_promo_code() -> void:
	if current_order:
		current_order.promo_code = null
		_recalculate()


## Установить метод оплаты
func set_payment_method(method: String) -> void:
	if current_order:
		current_order.payment_method = method


## Обработать оплату наличными
func process_cash_payment(amount: float) -> bool:
	if not current_order:
		return false
	if amount < current_order.final_price:
		return false
	current_order.cash_given = amount
	current_order.change_amount = amount - current_order.final_price
	return true


## Рассчитать время приготовления
func _calculate_cooking_time() -> float:
	if not current_order:
		return 5.0
	# Базовое время + по 0.5 сек за ингредиент + множитель размера
	var time := 3.0
	time += current_order.ingredients.size() * 0.5
	if current_order.pizza_size:
		time *= current_order.pizza_size.kbju_multiplier
	if current_order.height_tall:
		time += 1.0
	return time


## Главный пересчёт цены и КБЖУ
func _recalculate() -> void:
	if not current_order:
		return
	
	var order = current_order
	
	# --- Цена ---
	var price := BASE_PRICE
	
	# Надбавка за размер
	if order.pizza_size:
		price += order.pizza_size.price_modifier
	
	# Надбавка за тесто
	if order.dough:
		price += order.dough.price_modifier
	
	# Надбавка за высоту
	if order.height_tall:
		price += HEIGHT_TALL_PRICE
	
	# Ингредиенты
	var ing_price := 0.0
	for ing in order.ingredients:
		ing_price += ing.price
	
	order.total_price = price + ing_price
	
	# Скидка по промокоду
	order.discount_amount = 0.0
	if order.promo_code:
		if order.promo_code.discount_type == PromoCodeData.DiscountType.PERCENT:
			order.discount_amount = order.total_price * order.promo_code.discount_value / 100.0
		else:
			order.discount_amount = minf(order.promo_code.discount_value, order.total_price)
	
	order.final_price = maxf(order.total_price - order.discount_amount, 0.0)
	
	# --- КБЖУ ---
	var mult := 1.0
	if order.pizza_size:
		mult = order.pizza_size.kbju_multiplier
	
	# Базовое КБЖУ теста
	var cal := 0.0
	var prot := 0.0
	var fat := 0.0
	var carbs := 0.0
	
	if order.dough:
		cal += order.dough.calories
		prot += order.dough.protein
		fat += order.dough.fat
		carbs += order.dough.carbs
	
	# КБЖУ ингредиентов
	for ing in order.ingredients:
		cal += ing.calories
		prot += ing.protein
		fat += ing.fat
		carbs += ing.carbs
	
	# Применяем множитель размера
	order.total_calories = cal * mult
	order.total_protein = prot * mult
	order.total_fat = fat * mult
	order.total_carbs = carbs * mult
	
	# Время приготовления
	order.cooking_time = _calculate_cooking_time()
	
	# Сигналы
	price_changed.emit(order.final_price)
	kbju_changed.emit(order.total_calories, order.total_protein, order.total_fat, order.total_carbs)
	order_updated.emit()
