# Ресурс: промокод на скидку
class_name PromoCodeData
extends Resource

## Тип скидки
enum DiscountType { PERCENT, FIXED }

## Код (вводимый пользователем)
@export var code: String = ""
## Тип скидки: процент или фиксированная сумма
@export var discount_type: DiscountType = DiscountType.PERCENT
## Значение скидки (% или $)
@export var discount_value: float = 0.0
## Описание для UI
@export var description: String = ""


func _to_string() -> String:
	if discount_type == DiscountType.PERCENT:
		return "%s (-%.0f%%)" % [code, discount_value]
	else:
		return "%s (-$%.2f)" % [code, discount_value]
