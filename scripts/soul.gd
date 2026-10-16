extends Area2D

var player: Node2D
var attract_range := 150.0
var speed := 400.0
@export var lifetime := 10.0
var soul_visual_scene := preload("res://scenes/SoulFx.tscn")
var soul_visual: Node2D

func _ready():
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_timeout)
	soul_visual = soul_visual_scene.instantiate()
	add_child(soul_visual)
	player = get_tree().get_first_node_in_group("player")
	body_entered.connect(_on_body_entered)

func _on_lifetime_timeout():
	if is_inside_tree():
		queue_free()

func _physics_process(delta):
	if player and global_position.distance_to(player.global_position) < attract_range:
		global_position = global_position.move_toward(player.global_position, speed * delta)

func _on_body_entered(body):
	if body.is_in_group("player"):
		body.add_souls(1)
		body.play_pickup_sound()
		soul_visual.play_collect_effect()
		queue_free()
