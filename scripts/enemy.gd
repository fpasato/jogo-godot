extends CharacterBody2D

@export var speed := 100.0
@export var hp := 10
@export var contact_damage := 5
@export var attack_cooldown := 0.8
@export var attack_range := 60.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

static var shared_frames: SpriteFrames

var player: Node2D
var soul_scene = preload("res://scenes/Soul.tscn")
var can_attack := true
var attacking := false
var dead := false
var facing := "down"

func _ready():
	add_to_group("enemies")
	player = get_tree().get_first_node_in_group("player")
	if shared_frames == null:
		shared_frames = build_frames()
	sprite.sprite_frames = shared_frames
	sprite.play("run_down")

func build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for d in ["down", "up", "left", "right"]:
		_add_anim(sf, "run_" + d, "res://assets/Sprites/RUN/run_%s.png" % d, 10.0, true)
		_add_anim(sf, "attack_" + d, "res://assets/Sprites/ATTACK 1/attack1_%s.png" % d, 12.0, false)
	return sf

func _add_anim(sf: SpriteFrames, anim_name: String, path: String, fps: float, loop: bool):
	sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, loop)
	var tex = load(path)
	for i in 8:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * 96, 0, 96, 80)
		sf.add_frame(anim_name, at)

func _physics_process(_delta):
	if dead or not player:
		return

	var to_player = player.global_position - global_position
	if abs(to_player.x) > abs(to_player.y):
		facing = "right" if to_player.x > 0 else "left"
	else:
		facing = "down" if to_player.y > 0 else "up"

	if attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if to_player.length() <= attack_range and can_attack:
		start_attack()
		return

	velocity = to_player.normalized() * speed
	move_and_slide()
	var anim_name := "run_" + facing
	if sprite.animation != anim_name:
		sprite.play(anim_name)

func start_attack():
	attacking = true
	can_attack = false
	sprite.play("attack_" + facing)

	await get_tree().create_timer(0.35).timeout
	if not is_inside_tree() or dead:
		return
	if global_position.distance_to(player.global_position) <= attack_range + 20.0:
		player.take_damage(contact_damage)

	await sprite.animation_finished
	if not is_inside_tree() or dead:
		return
	attacking = false

	await get_tree().create_timer(attack_cooldown).timeout
	if not is_inside_tree():
		return
	can_attack = true

func take_damage(amount: int):
	if dead:
		return
	hp -= amount
	if hp <= 0:
		die()

func die():
	dead = true
	var soul = soul_scene.instantiate()
	soul.global_position = global_position
	get_parent().add_child.call_deferred(soul)
	queue_free()
