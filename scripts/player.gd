extends CharacterBody2D

signal souls_changed(total)
signal hp_changed(current, maximum)
signal level_changed(level)

@export var speed := 300.0
@export var max_hp := 100
@export var explosion_radius := 200.0
@export var explosion_damage := 10
@export var explosion_cooldown := 1.5
@export var lightning_length := 600.0
@export var lightning_width := 40.0
@export var lightning_damage := 15
@export var lightning_cooldown := 0.6


@onready var aim = $Aim
@onready var body_sprite: AnimatedSprite2D = $AnimatedSprite2D

var explosion_fx = preload("res://scenes/ExplosionFx.tscn")
var lightning_fx = preload("res://scenes/LightningFx.tscn")
var explosion_audio: AudioStream = preload("res://assets/audio/explosao.mp3")
var lightning_audio: AudioStream = preload("res://assets/audio/raio.mp3")
var pickup_audio: AudioStream = preload("res://assets/audio/coleta_de_almas.mp3")
var audio_players: Array[AudioStreamPlayer] = []

var hp := 100
var souls := 0
var level := 1
var next_level_souls := 10
var dead := false
var can_explode := true
var can_lightning := true
var aim_dir := Vector2.RIGHT
var facing := "down"
var last_horizontal := true
var storm_scene: PackedScene = preload("res://scenes/lightning_storm.tscn")
var storm_level := 1
var storm_cooldown := 8.0
var storm_timer := 0.0
var storm_range := 450.0                      # distância máxima que dá pra mirar

func _process(delta):
	storm_timer = maxf(storm_timer - delta, 0.0)
	if Input.is_action_just_pressed("storm") and storm_timer <= 0.0:
		cast_storm()

func cast_storm():
	if storm_scene == null:
		push_error("Cena da tempestade de raios não foi carregada.")
		return
	var target: Vector2 = get_global_mouse_position()
	var off: Vector2 = target - global_position
	if off.length() > storm_range:
		target = global_position + off.normalized() * storm_range

	var s = storm_scene.instantiate()
	s.bolt_count = 1 + storm_level            # nível 1 = 2 raios, nível 2 = 3...
	s.radius = 170.0 + storm_level * 10.0     # opcional: área cresce com o nível
	get_tree().current_scene.add_child(s)
	s.global_position = target
	storm_timer = storm_cooldown
	
func _ready():
	add_to_group("player")
	for i in 8:
		var audio_player := AudioStreamPlayer.new()
		audio_player.name = "SfxPlayer%d" % i
		add_child(audio_player)
		audio_players.append(audio_player)
	build_frames()
	body_sprite.play("idle_down")

func build_frames():
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for state in ["idle", "run"]:
		for d in ["down", "up", "left", "right"]:
			var anim_name := "%s_%s" % [state, d]
			sf.add_animation(anim_name)
			sf.set_animation_speed(anim_name, 10.0)
			sf.set_animation_loop(anim_name, true)
			var tex = load("res://assets/Sprites/%s/%s_%s.png" % [state.to_upper(), state, d])
			for i in 8:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * 96, 0, 96, 80)
				sf.add_frame(anim_name, at)
	body_sprite.sprite_frames = sf

func update_animation(dir: Vector2):
	var state := "idle"
	if dir != Vector2.ZERO:
		state = "run"
		if abs(dir.x) > abs(dir.y):
			facing = "right" if dir.x > 0 else "left"
		else:
			facing = "down" if dir.y > 0 else "up"

	var anim_name := state + "_" + facing
	if body_sprite.animation != anim_name:
		body_sprite.play(anim_name)

func _unhandled_input(event):
	if event.is_action_pressed("explosion"):
		explosion()
	if event.is_action_pressed("lightning"):
		lightning()

func explosion():
	if not can_explode:
		return
	can_explode = false
	_play_sfx(explosion_audio)
	var fx = explosion_fx.instantiate()
	fx.radius = explosion_radius
	fx.global_position = global_position
	get_parent().add_child(fx)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_to(enemy.global_position) <= explosion_radius:
			enemy.take_damage(explosion_damage)
	await get_tree().create_timer(explosion_cooldown).timeout
	can_explode = true

func lightning():
	if not can_lightning:
		return
	can_lightning = false
	_play_sfx(lightning_audio)
	var dir = aim_dir
	var fx = lightning_fx.instantiate()
	fx.length = lightning_length
	fx.direction = dir
	fx.global_position = global_position + dir * 50
	get_parent().add_child(fx)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var to_enemy = enemy.global_position - global_position
		var along = to_enemy.dot(dir)
		if along < 0 or along > lightning_length:
			continue
		if abs(to_enemy.cross(dir)) <= lightning_width:
			enemy.take_damage(lightning_damage)
	await get_tree().create_timer(lightning_cooldown).timeout
	can_lightning = true

func _play_sfx(stream: AudioStream):
	for audio_player in audio_players:
		if not audio_player.playing:
			audio_player.stream = stream
			audio_player.play()
			return
	# Se todos os canais estiverem ocupados, cria mais um para não cortar sons.
	var extra_player := AudioStreamPlayer.new()
	extra_player.name = "SfxPlayerExtra"
	add_child(extra_player)
	audio_players.append(extra_player)
	extra_player.stream = stream
	extra_player.play()

func play_pickup_sound():
	_play_sfx(pickup_audio)

func add_souls(amount: int):
	souls += amount
	souls_changed.emit(souls)
	while souls >= next_level_souls:
		level_up()
		
func _physics_process(_delta):
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
		last_horizontal = true
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("move_down"):
		last_horizontal = false

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if dir.x != 0 and dir.y != 0:
		if last_horizontal:
			dir.y = 0
		else:
			dir.x = 0
	dir = dir.normalized()

	velocity = dir * speed
	move_and_slide()

	aim_dir = (get_global_mouse_position() - global_position).normalized()
	aim.rotation = aim_dir.angle()

	update_animation(dir)


func level_up():
	level += 1
	next_level_souls = int(next_level_souls * 1.8)
	explosion_radius += 25
	explosion_damage += 5
	explosion_cooldown = max(0.5, explosion_cooldown - 0.1)
	lightning_damage += 3
	lightning_length += 40
	max_hp += 10
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	level_changed.emit(level)

func take_damage(amount: int):
	if dead:
		return
	hp -= amount
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		die()

func die():
	dead = true
	get_tree().reload_current_scene.call_deferred()
