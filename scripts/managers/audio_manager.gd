extends Node
## Менеджер музыки и звуковых эффектов для PizzaMarket.

var _bgm_player: AudioStreamPlayer
var _cooking_player: AudioStreamPlayer
var _oven_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE := 8

# Аудиодорожки
var snd_bgm: AudioStream
var snd_click_dizzy: AudioStream
var snd_click_fine: AudioStream
var snd_comedy_pop: AudioStream
var snd_applepay: AudioStream
var snd_chaching: AudioStream
var snd_melstroi: AudioStream
var snd_oven_baking: AudioStream
var snd_pizza_completed: AudioStream
var snd_steam_achievement: AudioStream
var snd_nom_nom: AudioStream

var _bgm_tween: Tween
const BGM_BASE_VOLUME := -14.0 # Приглушенно, но отчетливо слышно


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_players()
	_load_sounds()
	start_bgm()


func _init_players() -> void:
	# Фоновая музыка
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = "Master"
	_bgm_player.volume_db = -80.0
	add_child(_bgm_player)

	# Музыка наложения ингредиентов (Мелстрой)
	_cooking_player = AudioStreamPlayer.new()
	_cooking_player.name = "CookingPlayer"
	_cooking_player.bus = "Master"
	_cooking_player.volume_db = -4.0
	add_child(_cooking_player)

	# Звук запекания в печи
	_oven_player = AudioStreamPlayer.new()
	_oven_player.name = "OvenPlayer"
	_oven_player.bus = "Master"
	_oven_player.volume_db = -2.0
	add_child(_oven_player)

	# Пул для звуковых эффектов
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)


func _load_sounds() -> void:
	snd_bgm = load("res://assets/sounds/background/background.mp3")
	snd_click_dizzy = load("res://assets/sounds/ui/synthetic-click_dizzy.wav")
	snd_click_fine = load("res://assets/sounds/ui/synthetic-click_fine.wav")
	snd_comedy_pop = load("res://assets/sounds/ui/comedy_pop_finger_in_mouth_001.mp3")
	snd_applepay = load("res://assets/sounds/payment/applepay.mp3")
	snd_chaching = load("res://assets/sounds/payment/cha-ching-money.mp3")
	snd_melstroi = load("res://assets/sounds/oven/melstroi-pam-pam-pam.mp3")
	snd_oven_baking = load("res://assets/sounds/oven/oven_baking.mp3")
	snd_pizza_completed = load("res://assets/sounds/background/pizza_completed.mp3")
	snd_steam_achievement = load("res://assets/sounds/background/steam-achievement.mp3")
	snd_nom_nom = load("res://assets/sounds/background/nom-nom-nom_gPJiWn4.mp3")


func _play_sfx(stream: AudioStream, vol_db := 0.0, pitch_rnd := 0.0) -> void:
	if not stream:
		return
	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = vol_db
			if pitch_rnd > 0.0:
				p.pitch_scale = randf_range(1.0 - pitch_rnd, 1.0 + pitch_rnd)
			else:
				p.pitch_scale = 1.0
			p.play()
			return
	# Если все заняты — берем первый
	var fallback: AudioStreamPlayer = _sfx_players[0]
	fallback.stream = stream
	fallback.volume_db = vol_db
	fallback.pitch_scale = 1.0
	fallback.play()


## 1. Фоновая Lo-Fi музыка (плавное нарастание при запуске)
func start_bgm() -> void:
	if not snd_bgm:
		return
	_bgm_player.stream = snd_bgm
	_bgm_player.volume_db = -60.0
	_bgm_player.play()
	if not _bgm_player.finished.is_connected(start_bgm):
		_bgm_player.finished.connect(start_bgm)

	if is_instance_valid(_bgm_tween):
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm_player, "volume_db", BGM_BASE_VOLUME, 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func duck_bgm(duck: bool) -> void:
	if not _bgm_player or not _bgm_player.playing:
		return
	var target_db := (BGM_BASE_VOLUME - 8.0) if duck else BGM_BASE_VOLUME
	var tw := create_tween()
	tw.tween_property(_bgm_player, "volume_db", target_db, 0.5)


## 2. Кнопки на панели
func play_click_dizzy() -> void:
	_play_sfx(snd_click_dizzy, -3.0, 0.05)


## 3. Кнопка внизу (НАЧАТЬ / ДАЛЕЕ / ОПЛАТИТЬ / СКИП)
func play_click_fine() -> void:
	_play_sfx(snd_click_fine, 0.0, 0.03)


## 4. Стрелки выбора пиццы
func play_comedy_pop() -> void:
	_play_sfx(snd_comedy_pop, -2.0, 0.08)


## 5. Оплата (рандомно один из двух звуков)
func play_payment_random() -> void:
	var s: AudioStream = snd_applepay if randf() > 0.5 else snd_chaching
	_play_sfx(s, 2.0)


## 6. Наложение ингредиентов (Мелстрой пам-пам-пам на 9 секунд)
func play_cooking_groove() -> void:
	if not snd_melstroi:
		return
	duck_bgm(true)
	_cooking_player.stream = snd_melstroi
	_cooking_player.volume_db = -2.0
	_cooking_player.play()


func stop_cooking_groove() -> void:
	if _cooking_player and _cooking_player.playing:
		var tw := create_tween()
		tw.tween_property(_cooking_player, "volume_db", -40.0, 0.3)
		tw.tween_callback(func():
			_cooking_player.stop()
			_cooking_player.volume_db = -2.0
		)


## 7. Запекание в печи (oven_baking на 6 секунд)
func play_oven_baking() -> void:
	if not snd_oven_baking:
		return
	stop_cooking_groove()
	_oven_player.stream = snd_oven_baking
	_oven_player.volume_db = 0.0
	_oven_player.play()


func stop_oven_baking() -> void:
	if _oven_player and _oven_player.playing:
		var tw := create_tween()
		tw.tween_property(_oven_player, "volume_db", -40.0, 0.3)
		tw.tween_callback(func():
			_oven_player.stop()
			_oven_player.volume_db = 0.0
			duck_bgm(false)
		)


## 8. Готовность пиццы (pizza_completed)
func play_pizza_completed() -> void:
	stop_oven_baking()
	duck_bgm(false)
	_play_sfx(snd_pizza_completed, 2.0)


## 9. Забираем пиццу (рандомно steam-achievement или nom-nom-nom)
func play_pickup_random() -> void:
	var s: AudioStream = snd_steam_achievement if randf() > 0.5 else snd_nom_nom
	_play_sfx(s, 3.0)
