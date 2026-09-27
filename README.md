# 🍕 PizzaMarket (PizzaByte)

**2D пиццемат-симулятор** — Godot 4.7.2 · GDScript · 1920×1080 Fullscreen

## Концепция

Игрок взаимодействует с торговым автоматом по продаже пиццы. UI полностью текстурный (Figma-стиль): каждая кнопка/панель — PNG-спрайт на каркасе `whole_body.png` (1614×1536).

### Стейт-машина заказа

```
IDLE → SELECT_MODE → SELECT_PARAMETERS → BUILDING_COMPOSITION → PROMO_CODE → PAYMENT → QUEUE → COOKING → DISPENSING → FINISH → IDLE
```

## Два режима

- **Game** (F1 выкл) — элементы материализуются в реальные Godot-ноды (TextureRect/Label), клики через gui_input
- **Designer** (F1 вкл) — оверлей _draw(), drag/resize/group элементов, панель свойств

## Файлы

```
scripts/main.gd            323L  — game logic, input, layout, click routing
scripts/designer.gd        1278L — визуальный конструктор (class Designer extends RefCounted)
scripts/autoload/game_data.gd    — синглтон: ингредиенты, размеры, тесто, пресеты, промокоды
scripts/data/order.gd            — класс Order (состав, цена, КБЖУ)
scripts/data/{ingredient,dough,pizza_size,preset_pizza,promo_code}_data.gd
scripts/managers/machine_controller.gd — стейт-машина (enum State, сигнал state_changed)
scripts/managers/order_manager.gd      — управление заказом, цена, КБЖУ
scripts/managers/queue_manager.gd      — очередь, готовка (таймер), выдача
assets/sprite_layout.json              — позиции элементов (F4 save, авто-load)
assets/TEXTURE_SPEC.md                 — спецификация всех 108 текстур
assets/textures/machine/whole_body.png — каркас 1614×1536
assets/textures/font/minecraft-rus-regular1.ttf
```

## Дерево сцены (main.tscn)

```
Main (Control, main.gd)
├── MachineController (Node)  — стейт-машина
├── OrderManager (Node)       — текущий заказ
├── QueueManager (Node)       — очередь + готовка
├── MachineBody (TextureRect) — whole_body.png
│   ├── OvenZone (Control)         → CookProgress, CookStatus, CookTimer
│   ├── ScreenZone (Control)       → ScreenContent → NextButton
│   ├── DispenseZone (Control)     → PizzaBox
│   ├── IngredientsZone (Control)  — СКРЫТА (visible=false), заменена дизайнером
│   ├── BottomBar (Control)
│   └── [Материализованные ноды — TextureRect/Label при Game mode]
├── DesignerOverlay (Control, mouse_filter=IGNORE) — _draw()
└── DesignerCanvas (CanvasLayer 100) → DesignerPanel
```

## Designer (designer.gd)

**class Designer extends RefCounted** — НЕ Node, создаётся в main.gd _ready().

### Типы элементов

| Тип | При материализации | Описание |
|-----|-------------------|----------|
| ZONE | Не создаётся (уже в сцене) | Привязка к OvenZone/ScreenZone/etc |
| SPRITE | TextureRect | PNG-текстура |
| TEXT | Label (шрифт minecraft) | Текст |
| GROUP | Control | Контейнер |

### Координатная система

- Все rect — **в пикселях текстуры** (1614×1536), НЕ экранных
- Дочерние координаты — **относительно родителя** (Figma-стиль)
- `abs_rect(id)` — абсолютные координаты (суммирует цепочку родителей)
- `_tex_to_body(rect)` — пересчёт текстурные → экранные
- `_tex_scale()` → `Vector2(body.size / body_w_h)`

### Материализация (ключевая идея)

```gdscript
materialize()                  # Создаёт реальные ноды из дерева элементов
dematerialize()                # Удаляет все материализованные ноды
update_materialized_positions() # Обновляет при зуме/ресайзе
set_click_callback(cb)         # Callable для кликов → main.gd
```

### Layout JSON (sprite_layout.json, V2)

```json
{"version":2, "elements":[{"id":"e1","type":0,"name":"OvenZone","node":"OvenZone",
  "x":144,"y":340,"w":756,"h":552,...}], "root_children":["e1","e2",...]}
```

F4 save / F5 load / автолоад при старте. Обратная совместимость с V1.

### Горячие клавиши

F1 — вкл/выкл дизайнер · F2 — лог · F3 — сброс зума · F4 — сохранить · F5 — загрузить
Delete — видимость · Drag — перемещение · Shift+Drag — ресайз · Колесо — зум · СКМ — пан


## Данные игры (GameData autoload)

- **3 размера:** Маленькая (22см $0), Средняя (26см $2), Большая (34см $4)
- **3 теста:** Классическое, Тонкое, Воздушное
- **15 ингредиентов:** Пепперони ($1.50), Моцарелла ($1.00), Грибы ($0.80)...
- **5 пресетов:** Маргарита, Пепперони, Мясная, Бургерная, Карбонара
- **4 промокода:** PIZZA2024 (15%), STUDENT (20%), FIRST (10%), MEGA50 (50%)

## Текстуры

**27 существующих PNG** в `assets/textures/`: machine/whole_body, indicator×3, pizza×4,
presets×8 (стрелки, размеры, тесто), ui×10 (кнопки selected/unselected, режимы).
**~81 недостающая** — см. `assets/TEXTURE_SPEC.md` (робот, печь, слои пиццы, иконки, 9-slice, эффекты).

## Решённые баги

| Проблема | Причина | Решение |
|----------|---------|---------|
| Клики не доходили до дизайнера | `_unhandled_input()` — Controls съедали | `_input()` + `set_input_as_handled()` |
| Текст вводился задом наперёд | `_rebuild_tree()` в onChange → сброс курсора | Убрать rebuild; не обновлять text если `has_focus()` |
| Поле «Текст:» не видно | Свойства ниже Tree (300px) без скролла | Свойства наверх, Tree в ScrollContainer |
| Шрифт выезжал из бокса | `r.y + r.h * 0.75` грубо | `_font.get_ascent(scaled_fs)` |
| Нельзя набирать в LineEdit | `_input()` крал Delete | `has_focused_input()` — пропускать при фокусе |
| Уродливые Godot-кнопки | `_build_ingredients()` | Убраны; `IngredientsZone.visible = false` |

**Стейл reload 43** — `script_patch` на designer.gd часто возвращает `GDScript reload error 43`.
Это НЕ парс-ошибка. Designer — RefCounted, горячий reload ненадёжен. Игра запускается с 0 ошибками. Игнорировать.

## Roadmap

1. ✅ Визуальный конструктор (Designer)
2. ✅ Материализация элементов → реальные ноды
3. ✅ Убрать дефолтный UI ингредиентов
4. 🔄 Расстановка спрайтов пользователем через дизайнер
5. ⬜ Роутинг кликов → game logic (навигация, выбор ингредиентов, оплата)
6. ⬜ Добавить ~81 текстуру (см. TEXTURE_SPEC.md)
7. ⬜ Запечь layout — перенести позиции в код, убрать debug-рендеринг
8. ⬜ Анимации — готовка, выкладка ингредиентов, неон, выдача
9. ⬜ Ручной режим — drag ингредиентов на пиццу
10. ⬜ Робот — эмоции, чат-бабл, подсказки

## Quick Start для нового агента

1. Единственная сцена `scenes/main.tscn`, запуск F5
2. F1 → дизайнер (расстановка текстур), F4 → сохранить позиции
3. `scripts/main.gd` = game logic, `scripts/designer.gd` = конструктор
4. Designer — `RefCounted`, НЕ Node. Создаётся в `_ready()`
5. Координаты элементов — **в пикселях текстуры** (1614×1536), не экранных
6. `sprite_layout.json` — авточтение при старте
7. Переходы: `machine.transition_to(MachineController.State.XXX)`
8. Не трогать `addons/` — Godot AI plugin

## fix
__Всё работает!__ Теперь на скриншоте SELECT_PARAMETERS видны ВСЕ спрайт-текстуры:

✅ Карусель пиццы: рамка, стрелки ← →, изображение пепперони, "Пепперони", "12.90$" ✅ Секция размер: 3 кнопки с иконками (маленькая/средняя/большая), средняя подсвечена ✅ Секция тесто: 3 кнопки с иконками (классич./тонкое/пышное), классическое подсвечено ✅ Кнопка "ДАЛЕЕ →" с жёлтой текстурой

__Причина бага__: `z_index = -1` на Sprite2D внутри ClickableSprite. Godot суммирует z_index по всей цепочке родителей (z_as_relative = true): спрайт получал effective z = -1, а whole_body.png рисовался на z = 0, поэтому спрайты уходили ЗА каркас автомата. Фикс — убрать отрицательный z_index, вместо этого полагаться на порядок дочерних нод (Spr создаётся первым → рисуется под иконками/лейблами автоматически).

Все файлы корректные:

clickable_sprite.gd: 6 функций, signal "clicked", _input с ручным хит-тестом
screen_panel.gd: 15 функций, 6 сигналов (next_pressed, mode_changed, preset_changed, size_changed, dough_changed, height_changed)
main.gd: 17 функций включая _toggle_designer, _on_height_changed
Итог — что было починено
Главная проблема: клики не проходили к кнопкам
Причина: Area2D.input_event внутри Node2D, вложенного в Control (TextureRect → Control → Node2D → Area2D), не работает в Godot 4 — viewport physics picking не учитывает Control-иерархию. Плюс Control-ноды (MachineBody TextureRect, ScreenZone) имели mouse_filter = STOP по умолчанию и перехватывали GUI input.

Решение (2 части):

mouse_filter = IGNORE на все Control-ноды (body, screen_zone, oven_zone, etc.) — чтоб не перехватывали GUI events
Заменён Area2D.input_event на _input() с ручным хит-тестом — ClickableSprite теперь использует _input(event) → проверяет Rect2(global_position, btn_size * global_scale).has_point(event.global_position) → set_input_as_handled(). Это работает надёжно внутри Control иерархии.
Что кликабельно:
Элемент	Текстуры selected/unselected	Механизм
РУЧНОЙ / АВТО режим	manual_mode_selected↔unselected, auto_mode_selected↔unselected	SelectorGroup
Стрелки ← → (карусель пиццы)	arrow_left, arrow_right	ClickableSprite.clicked
Размер (3 кнопки)	versatile_square_selected↔unselected	SelectorGroup
Тесто (3 кнопки)	tall_square_selected↔unselected	SelectorGroup
Высота (2 кнопки)	versatile_square_selected↔unselected	SelectorGroup
ДАЛЕЕ →	button_selected	ClickableSprite.clicked
F1 дебаг-дизайнер
Восстановлен: F1 → _toggle_designer() → Designer.new().setup(self, body, BODY_W, BODY_H) → toggle(). Позиции элементов загружаются из sprite_layout.json — они не сломались, просто после resize экрана могут выглядеть смещёнными до F3 reset.


