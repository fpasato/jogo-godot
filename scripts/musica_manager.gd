extends Node

enum Estado { NENHUM, MENU, ARCADE }

var _estado_atual: Estado = Estado.NENHUM
var _player: AudioStreamPlayer
var _tween: Tween

# Músicas do Menu
const MUSICAS_MENU: Array[String] = [
	"res://assets/audio/menu/Dark Ambient 1.mp3",
	"res://assets/audio/menu/Dark Ambient 2.mp3",
	"res://assets/audio/menu/Dark Ambient 3.mp3",
	"res://assets/audio/menu/Dark Ambient 4.mp3",
	"res://assets/audio/menu/Dark Ambient 5.mp3",
]

# Músicas do Arcade
const MUSICAS_ARCADE: Array[String] = [
	"res://assets/audio/arcade/Action 1.mp3",
	"res://assets/audio/arcade/Action 2.mp3",
	"res://assets/audio/arcade/Action 3.mp3",
	"res://assets/audio/arcade/Action 4.mp3",
	"res://assets/audio/arcade/Action 5.mp3",
]

var _fila_menu: Array[String] = []
var _fila_arcade: Array[String] = []
var _volume_padrao_db: float = -6.0

func _ready() -> void:
	# Continua tocando mesmo se o jogo for pausado
	process_mode = Node.PROCESS_MODE_ALWAYS

	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = _volume_padrao_db
	_player.finished.connect(_on_musica_terminou)
	add_child(_player)

func tocar_menu() -> void:
	if _estado_atual == Estado.MENU and _player.playing:
		return # Já está tocando a música do menu
	_estado_atual = Estado.MENU
	_transicionar_para_proxima()

# De 0.0 (mudo) até 1.0 (volume máximo)
var volume: float = 0.5:
	set(novo_volume):
		volume = clampf(novo_volume, 0.0, 1.0)
		_volume_padrao_db = linear_to_db(volume) if volume > 0.001 else -80.0
		if _player:
			_player.volume_db = _volume_padrao_db


func tocar_arcade() -> void:
	if _estado_atual == Estado.ARCADE and _player.playing:
		return # Já está tocando a música do arcade
	_estado_atual = Estado.ARCADE
	_transicionar_para_proxima()

func parar(duracao_fade: float = 1.0) -> void:
	_estado_atual = Estado.NENHUM
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", -80.0, duracao_fade)
	_tween.tween_callback(_player.stop)

func _transicionar_para_proxima() -> void:
	var proxima_faixa := _obter_proxima_faixa()
	if proxima_faixa.is_empty():
		return

	var stream = load(proxima_faixa) as AudioStream
	if stream == null:
		return

	# Se já estiver tocando algo, faz fade-out antes de trocar
	if _player.playing:
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(_player, "volume_db", -80.0, 0.8)
		_tween.tween_callback(func():
			_iniciar_faixa(stream)
		)
	else:
		_iniciar_faixa(stream)

func _iniciar_faixa(stream: AudioStream) -> void:
	_player.stream = stream
	_player.volume_db = -80.0
	_player.play()

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", _volume_padrao_db, 0.8)

func _on_musica_terminou() -> void:
	# Quando uma música acaba, toca automaticamente a próxima da playlist
	if _estado_atual != Estado.NENHUM:
		_transicionar_para_proxima()

func _obter_proxima_faixa() -> String:
	if _estado_atual == Estado.MENU:
		if _fila_menu.is_empty():
			_fila_menu = MUSICAS_MENU.duplicate()
			_fila_menu.shuffle()
		return _fila_menu.pop_back()
	elif _estado_atual == Estado.ARCADE:
		if _fila_arcade.is_empty():
			_fila_arcade = MUSICAS_ARCADE.duplicate()
			_fila_arcade.shuffle()
		return _fila_arcade.pop_back()
	return ""
