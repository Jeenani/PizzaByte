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


## Камера печи (духовая камера) и система приготовления/выдачи

### 1. Текстуры камеры (assets/textures/machine/):
- `camera_pizzing_off.png` (820×660) — духовая камера выключена (состояние `IDLE`, ожидает клиента).
- `camera_pizzing_enabled.png` (820×660) — духовая камера включена и подсвечена мягким светом (состояния `SELECT_PARAMETERS`, `PAYMENT`, `QUEUE`).
- `camera_pizzing_cooking.png` (820×660) — идёт процесс выпекания (состояние `COOKING`, яркий жар и анимация нагрева).
- `camera_pizzing_completed.png` (820×660) — пицца готова (состояния `DISPENSING`, `FINISH`, готовая румяная пицца в духовке).
- `pizza_box.png` (580×160) — фирменная коробка автомата для зоны выдачи (`DispenseZone`).

### 2. Расположение и геометрия:
- `OVEN_RECT = Rect2(100, 270, 820, 660)` — точные координаты блока печи на каркасе `whole_body.png` (1614×1536). Текстуры 820×660 ложатся пиксель-в-пиксель без искажений.
- `DISPENSE_RECT = Rect2(220, 1150, 580, 160)` — лоток выдачи коробки пиццы.

### 3. Цикл приготовления и выдачи:
1. **14 секунд приготовления**: таймер настроен ровно на 14 секунд (`cooking_time = 14.0` в `Order` и `order_manager.gd`).
2. **Кнопка «СКИП >>»**: во время приготовления на тачпаде отображается кнопка «СКИП >>» и оставшиеся секунды (`ГОТОВИМ: X сек`). Нажатие немедленно завершает процесс выпекания.
3. **Выдача пиццы**: по истечении 14 секунд (или по нажатию СКИП) камера переключается на `camera_pizzing_completed.png`, а фирменная коробка с пиццей плавно выдвигается в лоток выдачи с помощью Tween-анимации.
4. **Забор пиццы**: игрок может кликнуть мышкой по коробке в лотке (или подождать таймер авто-забора 5 сек). Коробка плавно забирается, автомат возвращается в `IDLE`, камера печи переходит обратно в `camera_pizzing_off.png`.

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


## Индикаторы печи и режимы работы (Ручной / Автоматический)

### 1. Текст режимов на кнопках тачпада:
- **Кнопка ручного режима** (`manual_mode_btn`, 196×55): добавлена надпись **«Ручной»** (размер 13, шрифт Minecraft RUS), центрированная в правой части кнопки справа от контурной иконки руки.
- **Кнопка автоматического режима** (`auto_mode_btn`, 196×55): добавлена надпись **«Автоматический»** (размер 12, шрифт Minecraft RUS), центрированная в правой части кнопки справа от иконки шестерёнки.
- **Подсветка активности**: активный выбранный режим подсвечивается ярким белым цветом (`Color.WHITE`), неактивный — мягким серо-голубым оттенком (`Color(0.65, 0.72, 0.8)`).
- **События**: клики обрабатываются через `ClickableSprite` + `SelectorGroup`, надписи имеют `mouse_filter = MOUSE_FILTER_IGNORE` и не мешают нажатиям.

### 2. Индикатор состояния печи внизу корпуса автомата:
- Расположен в правом нижнем дисплее корпуса: `FURNACE_RECT = Rect2(1330, 1348, 124, 100)` на каркасе `whole_body.png` (1614×1536).
- **Состояние покоя / ожидания** (`IDLE`, `SELECT_PARAMETERS`, `PAYMENT`, `QUEUE`): отображается спокойный дисплей `indicator/furnace_indicator0.png`.
- **Процесс приготовления** (`COOKING`): каждую секунду индикатор совершает **3 тика** (каждые ~0.333 секунды), циклически меняя состояние от 0 до 2:
  - Тик 0 (0.00..0.33 с): спокойный дисплей `indicator/furnace_indicator0.png`.
  - Тик 1 (0.33..0.66 с): нагрев `indicator/furnace_indicator1.png` (жёлто-красный огонёк).
  - Тик 2 (0.66..1.00 с): раскалённые полосы печи `indicator/furnace_indicator2.png`.
  - Цикл непрерывно повторяется (0 → 1 → 2 → 0 → 1 → 2...) в течение всей готовки.
- **Готовность и выдача** (`DISPENSING`, `FINISH`): как только пицца приготовлена и готова к выдаче (или по нажатию кнопки «СКИП >>»), цикл останавливается и индикатор немедленно возвращается на `furnace_indicator0.png`.
- **Забор пиццы**: при заборе коробки игроком или по авто-таймеру индикатор остаётся в исходном состоянии `furnace_indicator0.png`.


## Неоновое табло выдачи и анимация спуска пиццы

### 1. Неоновое табло выдачи («ЗАБЕРИ СВОЮ ПИЦЦУ»):
- Расположено на скошенной планке каркаса автомата прямо над лотком выдачи: `DISPENSE_SIGN_RECT = Rect2(240, 1016, 570, 54)` на `whole_body.png`.
- **Стрелки-треугольники (▼)**: слева и справа размещены неоновые пиксельные треугольники (`assets/textures/ui/dispenser_arrow.png`, 36×32), направленные вершиной вниз к окну выдачи. Имеют градиент от жёлтого центра к рубиново-красному контуру и неоновый glow.
- **Текст**: по центру надпись **«ЗАБЕРИ СВОЮ ПИЦЦУ»** (шрифт Minecraft RUS, размер 24, цвет белый с тёмным контуром и мягкой тенью).
- **Анимация моргания**:
  - Включается в момент начала спуска готовой пиццы из печи под корпус и активно мигает всё время, пока коробка находится в лотке выдачи (фазы `DISPENSING` и `FINISH`).
  - Частота мигания: период 0.44 с (0.26 с горит + лёгкий импульс стрелок вниз, 0.18 с гаснет).
  - В покое (`IDLE`, `SELECT_PARAMETERS`, `PAYMENT`, `QUEUE`, `COOKING`) табло полностью выключено и невидимо (`visible = false`, `modulate.a = 0.0`).
  - При заборе коробки игроком табло мгновенно плавно гаснет.

### 2. Исправление бага и синхронизация спуска пиццы:
- **Проблема**: таймер `QueueManager` (14–16 сек) иногда срабатывал раньше физического окончания анимации в `PizzaCooker` и принудительно вызывал `_cooker.stop()`, обрывая анимацию спуска платформы, из-за чего коробка появлялась мгновенно без видимого опускания пиццы.
- **Решение**:
  - В `PizzaCooker` добавлен сигнал `platform_lowering_started` (испускается в момент окончания выпекания перед спуском) и флаг `_is_lowering`.
  - Время запекания оптимизировано до 5.0 с, время спуска платформы — 1.4 с (общее время 15.4 с, таймер очереди 16.0 с).
  - `main.gd` слушает `platform_lowering_started` → сразу запускает мигание табло выдачи, гасит ТЭНы печи и выводит статус `⬇️ ВЫДАЧА ПИЦЦЫ...`.
  - Сигнал `cooking_completed` испускается строго после полного ухода платформы под печь (`tw_exit.finished`) → только тогда переключается камера и плавно выдвигается коробка `_show_pizza_box()`.
  - `_on_cook_finish()` проверяет `is_lowering()` и никогда не прерывает активный спуск платформы.

### 3. Масштабирование и зум камеры:
- **Старт игры**: начинается с максимального отдаления (`_zoom_t = 0.0`), открывая полный панорамный вид ночной улицы и здания с автоматом у стены.
- **Максимальное приближение**: по скроллу мыши камера плавно приближается к автомату (`_zoom_t = 1.0`), где автомат занимает ровно 100% высоты экрана (`z_in = (vp.y * 1.0) / MACHINE_H`) с сохранением полного масштаба всего автомата — ни верхняя вывеска, ни нижние ножки не обрезаются, при этом все надписи сенсорной панели крупные и легко читаемые.
- **Сброс**: по клавише **F3** камера мгновенно возвращается к максимальному отдалению фона улицы (`_target_zoom_t = 0.0`).


## Сборка и автоматический релиз на GitHub

В проект добавлен скрипт автоматизации **`release.py`** для экспорта игры, создания установочного пакета и публикации на GitHub Releases.

### 📦 Использование `release.py`:

```bash
# Полный цикл: экспорт в .exe, упаковка в .zip, создание git тега и релиз на GitHub
py release.py --version 1.0.0

# Только локальная сборка без загрузки на GitHub (архив сохранится в корне проекта)
py release.py --build-only

# Создание черновика (draft) релиза на GitHub
py release.py --draft
```

### 🛠️ Что делает скрипт:
1. **Проверка окружения и шаблонов**: автоматически находит установленный Godot 4.7.2 и настраивает шаблоны экспорта Windows Desktop в `%APPDATA%/Godot/export_templates/4.7.2.stable`.
2. **Экспорт**: компилирует билд в `build/PizzaByte.exe` и `build/PizzaByte.pck`.
3. **Генерация установщика**:
   - `Установить_PizzaByte.bat` — скрипт автоматической установки в `%LOCALAPPDATA%\PizzaByte` с созданием ярлыков на **Рабочем столе** и в **меню Пуск**, а также генерацией деинсталлятора.
   - `Создать_ярлык_на_рабочий_стол.bat` — создание ярлыка для запуска игры из текущей папки без копирования.
   - `README.txt` — краткая инструкция по управлению для игроков.
4. **Упаковка**: сжимает дистрибутив в `PizzaByte_<версия>_Windows_x64.zip`.
5. **Публикация на GitHub Releases**:
   - Автоматически получает токен доступа через Git Credential Manager / окружение `GITHUB_TOKEN`.
   - Создаёт и отправляет Git-тег `v<версия>`.
   - Создаёт релиз на GitHub со списком изменений и загружает установочный архив в assets.

### 📥 Скачать релиз:
Свежий готовый билд доступен на странице [GitHub Releases](https://github.com/Jeenani/PizzaByte/releases).


