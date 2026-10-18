extends Node2D

@export var enemy_scene: PackedScene
@export var enemies_per_spawn := 3
@export var max_enemies := 100

@onready var player = $Player
@onready var label = $CanvasLayer/Label
@onready var timer = $Timer
@onready var hp_bar = $CanvasLayer/ProgressBar
@onready var level_label = $CanvasLayer/LevelLabel

func _on_hp_changed(current, maximum):
	hp_bar.max_value = maximum
	hp_bar.value = current

func _ready():
	MusicaManager.tocar_arcade()
	MusicaManager.volume = 0.15  
	player.souls_changed.connect(_on_souls_changed)
	timer.timeout.connect(_on_timer_timeout)
	player.hp_changed.connect(_on_hp_changed)
	player.level_changed.connect(_on_level_changed)

func _on_level_changed(new_level):
	level_label.text = "Nível %d" % new_level

func _on_souls_changed(total):
	label.text = "Almas: %d / 1.000.000" % total

func _on_timer_timeout():
	var current = get_tree().get_nodes_in_group("enemies").size()
	for i in enemies_per_spawn:
		if current >= max_enemies:
			return
		spawn_enemy()
		current += 1

func spawn_enemy():
	var e = enemy_scene.instantiate()
	var angle = randf() * TAU
	e.global_position = player.global_position + Vector2.from_angle(angle) * randf_range(600, 900)
	add_child(e)
