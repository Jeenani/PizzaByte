# Менеджер очереди заказов
# Управляет очередью, приготовлением и выдачей
extends Node

# --- Сигналы ---
signal queue_changed()
signal cooking_started(order: Order)
signal cooking_progress(progress: float, time_left: float)
signal cooking_finished(order: Order)
signal dispensing_finished(order: Order)

## Очередь заказов
var queue: Array = []  # Array[Order]
## Текущий готовящийся заказ
var current_cooking: Order = null
## Идёт ли приготовление
var is_cooking: bool = false

## Таймер готовки
var _cook_elapsed: float = 0.0
var _cook_total: float = 0.0

## Время "выдачи" (анимация)
const DISPENSE_TIME: float = 2.0
var _dispense_elapsed: float = 0.0
var _is_dispensing: bool = false


func _process(delta: float) -> void:
	# Обработка готовки
	if is_cooking and current_cooking:
		_cook_elapsed += delta
		var progress := clampf(_cook_elapsed / _cook_total, 0.0, 1.0)
		var time_left := maxf(_cook_total - _cook_elapsed, 0.0)
		cooking_progress.emit(progress, time_left)
		
		if _cook_elapsed >= _cook_total:
			_finish_cooking()
	
	# Обработка выдачи
	if _is_dispensing:
		_dispense_elapsed += delta
		if _dispense_elapsed >= DISPENSE_TIME:
			_finish_dispensing()


## Добавить заказ в очередь
func add_to_queue(order: Order) -> void:
	queue.append(order)
	queue_changed.emit()
	print("[Очередь] Добавлен заказ: %s (всего в очереди: %d)" % [order, queue.size()])
	
	# Если ничего не готовится — начать сразу
	if not is_cooking and not _is_dispensing:
		_start_next()


## Пропустить приготовление текущей пиццы
func skip_cooking() -> void:
	if is_cooking and current_cooking:
		print("[Очередь] Приготовление пропущено: %s" % current_cooking)
		_finish_cooking()


## Завершить приготовление по сигналу готовности кукера
func complete_cooking() -> void:
	if is_cooking and current_cooking:
		_cook_elapsed = _cook_total
		_finish_cooking()


## Перемотать приготовление к фазе запекания
func skip_to_baking() -> void:
	if is_cooking and current_cooking:
		_cook_elapsed = maxf(_cook_elapsed, 9.0)
		var progress := clampf(_cook_elapsed / _cook_total, 0.0, 1.0)
		var time_left := maxf(_cook_total - _cook_elapsed, 0.0)
		cooking_progress.emit(progress, time_left)


## Получить размер очереди (включая текущий готовящийся)
func get_total_count() -> int:
	var count := queue.size()
	if is_cooking or _is_dispensing:
		count += 1
	return count


## Получить информацию об очереди для UI
func get_queue_info() -> Array:
	var info := []
	# Первый — текущий
	if current_cooking:
		info.append({
			"order": current_cooking,
			"status": "dispensing" if _is_dispensing else "cooking",
			"progress": clampf(_cook_elapsed / _cook_total, 0.0, 1.0) if is_cooking else 1.0,
			"time_left": maxf(_cook_total - _cook_elapsed, 0.0) if is_cooking else 0.0,
		})
	# Остальные в очереди
	for i in range(queue.size()):
		info.append({
			"order": queue[i],
			"status": "waiting",
			"progress": 0.0,
			"time_left": queue[i].cooking_time,
		})
	return info


## Начать готовить следующий заказ из очереди
func _start_next() -> void:
	if queue.is_empty():
		current_cooking = null
		return
	
	current_cooking = queue.pop_front()
	is_cooking = true
	_cook_elapsed = 0.0
	_cook_total = current_cooking.cooking_time
	
	cooking_started.emit(current_cooking)
	queue_changed.emit()
	print("[Очередь] Начинаем готовить: %s (%.1f сек)" % [current_cooking, _cook_total])


## Завершить приготовление
func _finish_cooking() -> void:
	is_cooking = false
	var order := current_cooking
	cooking_finished.emit(order)
	print("[Очередь] Приготовлено: %s" % order)
	
	# Переходим к выдаче
	_is_dispensing = true
	_dispense_elapsed = 0.0


## Завершить выдачу
func _finish_dispensing() -> void:
	_is_dispensing = false
	var order := current_cooking
	current_cooking = null
	dispensing_finished.emit(order)
	queue_changed.emit()
	print("[Очередь] Выдано: %s" % order)
	
	# Начинаем следующий, если есть
	_start_next()
