# Главный контроллер состояний пиццемата
# Управляет переходами между экранами автомата
class_name MachineController
extends Node

## Все возможные состояния автомата
enum State {
	IDLE,                 # Ожидание — экран приветствия
	SELECT_MODE,          # Выбор режима: ручной / авто
	SELECT_PARAMETERS,    # Выбор размера, теста, высоты
	BUILDING_COMPOSITION, # Добавление ингредиентов / выбор пресета
	PROMO_CODE,           # Ввод промокода (можно пропустить)
	PAYMENT,              # Экран оплаты
	QUEUE,                # Заказ добавлен в очередь
	COOKING,              # Приготовление (прогрессбар + таймер)
	DISPENSING,           # Выдача пиццы
	FINISH,               # Готово — забери пиццу!
}

## Сигнал: состояние изменилось
signal state_changed(old_state: State, new_state: State)

## Текущее состояние автомата
var current_state: State = State.IDLE


## Названия состояний на русском (для UI и дебага)
static func state_name(state: State) -> String:
	match state:
		State.IDLE: return "Ожидание"
		State.SELECT_MODE: return "Выбор режима"
		State.SELECT_PARAMETERS: return "Параметры пиццы"
		State.BUILDING_COMPOSITION: return "Состав пиццы"
		State.PROMO_CODE: return "Промокод"
		State.PAYMENT: return "Оплата"
		State.QUEUE: return "В очереди"
		State.COOKING: return "Приготовление"
		State.DISPENSING: return "Выдача"
		State.FINISH: return "Готово"
	return "???"


## Проверка: можно ли перейти из текущего состояния в новое
func can_transition_to(new_state: State) -> bool:
	match current_state:
		State.IDLE:
			return new_state == State.SELECT_MODE
		State.SELECT_MODE:
			return new_state in [State.SELECT_PARAMETERS, State.IDLE]
		State.SELECT_PARAMETERS:
			return new_state in [State.BUILDING_COMPOSITION, State.SELECT_MODE]
		State.BUILDING_COMPOSITION:
			return new_state in [State.PROMO_CODE, State.SELECT_PARAMETERS]
		State.PROMO_CODE:
			return new_state in [State.PAYMENT, State.BUILDING_COMPOSITION]
		State.PAYMENT:
			return new_state in [State.QUEUE, State.PROMO_CODE]
		State.QUEUE:
			return new_state in [State.COOKING, State.IDLE]
		State.COOKING:
			return new_state == State.DISPENSING
		State.DISPENSING:
			return new_state == State.FINISH
		State.FINISH:
			return new_state in [State.IDLE, State.SELECT_MODE]
	return false


## Перейти в новое состояние (с валидацией)
func transition_to(new_state: State) -> bool:
	if not can_transition_to(new_state):
		push_warning("MachineController: переход %s → %s запрещён" % [
			state_name(current_state), state_name(new_state)
		])
		return false
	
	var old := current_state
	current_state = new_state
	state_changed.emit(old, new_state)
	print("[Автомат] %s → %s" % [state_name(old), state_name(new_state)])
	return true


## Принудительный переход (для внутренней логики: очередь → готовка)
func force_transition(new_state: State) -> void:
	var old := current_state
	current_state = new_state
	state_changed.emit(old, new_state)
	print("[Автомат] %s →→ %s (авто)" % [state_name(old), state_name(new_state)])


## Автомат сейчас в режиме оформления заказа?
func is_ordering() -> bool:
	return current_state in [
		State.SELECT_MODE, State.SELECT_PARAMETERS,
		State.BUILDING_COMPOSITION, State.PROMO_CODE, State.PAYMENT
	]


## Сброс в начальное состояние
func reset() -> void:
	force_transition(State.IDLE)
